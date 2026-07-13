import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'dart:convert';
import 'dart:io';
import 'package:glob/glob.dart';
import 'package:jaspr/dom.dart' show StyleRule;

import './utils.dart';
import './annotations.dart';

Builder cssFileBuilder(BuilderOptions options) {
  final outputPaths = _getOutputPaths(options, 'outputPaths');
  return CssFileBuilder(outputPaths: outputPaths);
}

List<String>? _getOutputPaths(BuilderOptions options, String field) {
  final rawPaths = options.config[field] as List?;

  List<String>? parsedPaths;
  if (rawPaths != null) {
    // 將類型轉換為 `List<String>`
    parsedPaths = rawPaths.map((e) => e as String).toList();
  }

  return parsedPaths;
}

class CssFileBuilder implements Builder {
  late final List<String> _outputPaths;

  CssFileBuilder({List<String>? outputPaths}) {
    if (outputPaths == null) {
      log.severe(
        'The build_runner option "outputPaths" is required.'
        ' Please configure it in your build.yaml.',
      );
      throw ArgumentError('Missing required config: "outputPaths"');
    }
    _outputPaths = outputPaths;
  }

  // NOTE:
  // - 目前 build.yaml 是 `r'$web$': ['.css']`, 此處是隨參數動態更新,
  //   實際運行是正常的. 但後續可能要追蹤 issues/3295 看看怎麼變化.
  //   https://github.com/dart-lang/build/issues/3295
  @override
  Map<String, List<String>> get buildExtensions => {r'$web$': _outputPaths};

  // NOTE:
  // - 目前沒有檢查到有更新才重建的功能, 這對 `dart run build_runner watch` 不友善.
  //   對於每份文件都讀取內容紀錄 Hash 變更是乎更加不友善. 不過還不知道如何檢查元素
  //   是否有外部引用.
  //   當實作此功能時 [DartModule], [_CodeInfo] 或許能為其提供工作空間.
  @override
  Future<void> build(BuildStep buildStep) async {
    final cssModuleCacheParty = _CssModuleCacheParty();

    final assetGlob = Glob('lib/**.dart');
    await for (final inputId in buildStep.findAssets(assetGlob)) {
      final inputPath = inputId.path; // `lib/...`
      final dartModule = _DartModule(
        'package:${inputId.package}/${inputPath.substring(4)}',
      );

      final matchCodeInfoStream = _matchCodeInfoStream(
        buildStep,
        inputId,
        _checkCssFileType,
      );
      await for (final _MatchCodeInfo(:cssFilePath, :codeInfo)
          in matchCodeInfoStream) {
        if (!_outputPaths.contains(cssFilePath)) {
          log.warning(
            'The output path "$cssFilePath" is not allowed.'
            ' Please add this path to the "outputPaths" option in your build.yaml.',
          );
          continue;
        }

        dartModule.add(codeInfo);
        cssModuleCacheParty.add(cssFilePath, codeInfo);
      }

      if (dartModule.infos.isEmpty) continue;

      await _resolveCssOfCodeInfo(dartModule);
    }

    for (final cssModule in cssModuleCacheParty.values) {
      final cssCode = cssModule.infos
          .map((item) => item.cssCode)
          .whereType<String>()
          .join('\n');

      final cssContent =
          '/* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */'
          '\n\n$cssCode';

      final outputId = AssetId(
        buildStep.inputId.package,
        'web/${cssModule.path}',
      );
      await buildStep.writeAsString(outputId, cssContent.trimRight());
    }
  }

  final _checkCssFileType = createTypeChecker(
    CssFile,
    inPackage: 'jaspr_css_file_builder',
  );
}

class _CodeInfo {
  final String target;
  int line;
  int column;
  String? cssCode;

  _CodeInfo(this.target, this.line, this.column);
}

class _DartModule {
  final String path;
  final List<_CodeInfo> infos = [];

  _DartModule(this.path);

  void add(_CodeInfo codeInfo) {
    infos.add(codeInfo);
  }
}

class _CssModule {
  final String path;
  final List<_CodeInfo> infos = [];

  _CssModule(this.path);

  void add(_CodeInfo codeInfo) {
    infos.add(codeInfo);
  }
}

class _CssModuleCacheParty {
  final Map<String, _CssModule> _rooms = {};

  _CssModule getOrCreateRoom(String roomId) {
    // `.putIfAbsent()` 如果找不到 key，會執行第二函式參數直接創建, 插入並回傳, 效率優於 `.containsKey()`.
    return _rooms.putIfAbsent(roomId, () => _CssModule(roomId));
  }

  Iterable<_CssModule> get values => _rooms.values;

  void add(String path, _CodeInfo codeInfo) {
    getOrCreateRoom(path).add(codeInfo);
  }
}

class _MatchCodeInfo {
  final String cssFilePath;
  final _CodeInfo codeInfo;

  const _MatchCodeInfo(this.cssFilePath, this.codeInfo);
}

/// 以 [checkCssFileType] 方法過濾註解, 找到指定元素.
/// 把註解還原 [CssFile] 並取出 [_MatchCodeInfo.cssFilePath] 輸出路徑.
/// 解析元素給出 [_CodeInfo].
Stream<_MatchCodeInfo> _matchCodeInfoStream(
  BuildStep buildStep,
  AssetId inputId,
  CheckIsTargetType checkCssFileType,
) async* {
  if (!await buildStep.resolver.isLibrary(inputId)) return;

  final library = await buildStep.resolver.libraryFor(inputId);
  final unit = await buildStep.resolver.compilationUnitFor(inputId);
  final lineInfo = unit.lineInfo;

  // 初始的候選元素: 所有的 `class` 和全域變數
  // 參考 [GitHub: schultek/jaspr][fn01]
  final elementList = [...library.topLevelVariables, ...library.classes]
      .expand<Element>(
        (e) => switch (e) {
          final ClassElement e => [...e.fields, ...e.getters],
          final TopLevelVariableElement e when e.isOriginDeclaration => [e],
          TopLevelVariableElement(:final getter?) when e.isOriginGetterSetter =>
            [getter],
          _ => [],
        },
      );

  final inputSystemPath = library.firstFragment.source.fullName;

  for (final element in elementList) {
    final cssFile = _matchCssFileAnnotation(
      element,
      checkCssFileType,
      inputSystemPath,
    );
    if (cssFile == null) continue;

    if (!_checkIsValidStyleRule(element, inputSystemPath)) continue;

    final codeInfo = _resolveElement(element, lineInfo);
    if (codeInfo == null) continue;

    yield _MatchCodeInfo(cssFile.path, codeInfo);
  }
}

/// 以 [checkCssFileType] 方法過濾註解, 並將其還原成 [CssFile].
///
/// 當 [CssFile] 沒有指定輸出路徑時會忽略該註解並以 `log.warning()` 輸出提示訊息.
CssFile? _matchCssFileAnnotation(
  Element element,
  CheckIsTargetType checkCssFileType,
  String inputSystemPath,
) {
  final annotations = element.metadata.annotations;

  final hasCssFile = annotations.any(checkCssFileType);
  if (!hasCssFile) return null;

  final annotation = annotations.firstWhere(checkCssFileType);
  // 取得 @CssFile 的 path 參數
  final computedAnnotation = annotation.computeConstantValue();
  final pathValue = computedAnnotation?.getField('path')?.toStringValue() ?? '';
  if (pathValue == '') {
    String? elementTarget;
    if (element.enclosingElement case final ClassElement clazz) {
      elementTarget = ' ${clazz.name}.${element.name}';
    } else {
      elementTarget = ' ${element.name}';
    }

    log.warning(
      '@CssFile has not file path.'
      ' Failing element:$elementTarget in library $inputSystemPath.',
    );
    return null;
  }

  return CssFile(pathValue);
}

final TypeChecker _styleRuleChecker = TypeChecker.typeNamed(
  StyleRule,
  inPackage: 'jaspr',
);

/// 檢查對象是否為有效的 CSS 定義 (`List<StyleRule>`).
/// 參考 [GitHub: schultek/jaspr][fn01].
bool _checkIsValidStyleRule(Element element, String inputSystemPath) {
  if (element.enclosingElement case final ClassElement clazz
      when clazz.isPrivate || element.isPrivate) {
    log.severe(
      '@CssFile cannot be used on private classes or members.'
      ' Failing element: ${clazz.name}.${element.name} in library $inputSystemPath.',
    );
    return false;
  } else if (element.enclosingElement case final ClassElement clazz
      when (element is FieldElement && !element.isStatic) ||
          (element is GetterElement && !element.isStatic)) {
    log.severe(
      '@CssFile cannot be used on non-static class members.'
      ' Failing element: ${clazz.name}.${element.name} in library $inputSystemPath.',
    );
    return false;
  } else if (element.isPrivate) {
    log.severe(
      '@CssFile cannot be used on private variables or getters.'
      ' Failing element: ${element.name} in library $inputSystemPath.',
    );
    return false;
  }

  final type = switch (element) {
    final PropertyAccessorElement e => e.type.returnType,
    final PropertyInducingElement e => e.type,
    _ => null,
  };

  if (type == null ||
      !type.isDartCoreList ||
      !_styleRuleChecker.isAssignableFromType(
        (type as InterfaceType).typeArguments.first,
      )) {
    final prefix = switch (element.enclosingElement) {
      ClassElement(:final name) => '$name.',
      _ => '',
    };
    log.severe(
      '@CssFile can only be applied on variables or getters of type List<StyleRule>.'
      ' Failing element: $prefix${element.name} with type $type in library ${element.library?.firstFragment.source.fullName}.',
    );
    return false;
  }

  return true;
}

// 從 [element] 解析出 [_CodeInfo] 的訊息.
_CodeInfo? _resolveElement(Element element, LineInfo lineInfo) {
  String targetName;
  if (element.enclosingElement case final ClassElement clazz) {
    targetName = '${clazz.name}.${element.name}';
  } else if (element.name != null) {
    targetName = element.name!;
  } else {
    // NOTE:
    // 這情況應該不可能發生
    return null;
  }

  // 獲取行號與列號
  // NOTE:
  // - 不知道什麼情況 `.nameOffset` 會是 `null`
  final location = lineInfo.getLocation(element.firstFragment.nameOffset ?? 0);

  return _CodeInfo(
    targetName,
    location.lineNumber,
    location.columnNumber,
  );
}

/// 當 Dart 轉換 CSS 程式碼失敗時會以 `log.severe()` 輸出錯誤訊息.
Future<void> _resolveCssOfCodeInfo(_DartModule dartModule) async {
  final infosToTransform = dartModule.infos;
  final (error, cssResults) = await _transformCssBatch(
    dartModule.path,
    infosToTransform,
  );

  if (error != null) {
    log.severe('CSS transform failed (${dartModule.path}): $error');
  } else if (cssResults!.length != infosToTransform.length) {
    log.severe('CSS transform failed (${dartModule.path}): data lost.');
  } else {
    // 依序將轉換結果填回 CodeInfo
    for (var idx = 0; idx < infosToTransform.length; idx++) {
      infosToTransform[idx].cssCode = cssResults[idx];
    }
  }
}

/// 批次轉換 CSS 方法: 一份 Dart 文件只跑一次行程，處理多個 [_CodeInfo].
Future<(String? error, List<String>? cssResults)> _transformCssBatch(
  String dartModulePath,
  List<_CodeInfo> targets,
) async {
  // 使用特殊的分隔符號，方便後續精準切分多個 target 的輸出結果
  const separator = '===CSS_SEPARATOR_FOR_BUILD_RUNNER===';

  // 生成動態 Dart 程式碼
  // 透過 import 該 dartModulePath，並依序呼叫各個 `target.toCss()`.
  final buffer = StringBuffer();

  buffer.writeln("import 'package:jaspr/dom.dart';");
  buffer.writeln("import '$dartModulePath';"); // 匯入來源 Dart 檔案
  buffer.writeln("void main() async {");
  buffer.writeln("  final List<String> results = [];");

  for (final info in targets) {
    buffer.writeln("  results.add(transformCss(${info.target}));");
  }

  buffer.writeln("  print(results.join('$separator'));");
  buffer.writeln("}");
  buffer.writeln("String transformCss(List<StyleRule> styleRules) {");
  buffer.writeln(
    "  return styleRules.map((item) => item.toCss()).join('\\n');",
  );
  buffer.writeln("}");

  // 啟動 Dart 子行程
  // NOTE:
  // - 這邊指定的 `--packages` 會使用專案的第三方套件
  // - `/dev/stdin` 相當於 `-` 會從 stdin 讀取
  final process = await Process.start('dart', [
    'run',
    '--packages=.dart_tool/package_config.json',
    '/dev/stdin',
  ]);

  // 把生成的代碼寫入至標準輸入
  process.stdin.write(buffer.toString());
  await process.stdin.close();

  // 監聽並收集執行結果 (stdout 與 stderr)
  final List<String> outputs = [];
  final List<String> errors = [];
  process.stdout.transform(utf8.decoder).listen((data) => outputs.add(data));
  process.stderr.transform(utf8.decoder).listen((data) => errors.add(data));

  // 等待行程執行完畢
  final exitCode = await process.exitCode;

  if (exitCode != 0) {
    return (errors.join().trim(), null);
  }

  // 解析標準輸出，並用分隔符號拆回各個 [_CodeInfo] 的 CSS 內容
  final totalOutput = outputs.join().trim();
  final cssList = totalOutput.split(separator);

  return (null, cssList);
}

// Footnote:
// [fn01]: https://github.com/schultek/jaspr/blob/e4cc9d1/packages/jaspr_builder/lib/src/styles/styles_module_builder.dart#L50
