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

Builder cssFileModuleBuilder(BuilderOptions options) {
  return CssFileModuleBuilder();
}

Builder cssFileBuilder(BuilderOptions options) {
  final outputPaths = _getOutputPaths(options, 'output_paths');
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

/// 用於 `dart run build_runner watch` 的測試開關
const isActualTest = false;

const _cssfileExtension = '.styles.cssfile.txt';

class CssFileModuleBuilder implements Builder {
  final bool isTest;

  /// 只在 dart 文件有變動時才會提取該文件和與其有引用關係文件的 `@CssFile` 並轉換成 CSS 程式碼.
  CssFileModuleBuilder({this.isTest = false});

  // 只在有變動時才更新, 且引用本文件的也會一起更新.
  @override
  Map<String, List<String>> buildExtensions = {
    r'.dart': [_cssfileExtension],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    if (!await buildStep.resolver.isLibrary(inputId)) return;

    final library = await buildStep.resolver.libraryFor(inputId);
    final unit = await buildStep.resolver.compilationUnitFor(inputId);
    final lineInfo = unit.lineInfo;

    final dartModule = _DartModule(inputId.uri.toString());

    if (isActualTest) print('[CssFileModuleBuilder] read ${dartModule.path}');
    final matchCodeInfoIterable = _matchCodeInfoIterable(
      inputId,
      library,
      lineInfo,
      _checkCssFileType,
    );
    for (final _MatchCodeInfo(:cssFilePath, :codeInfo)
        in matchCodeInfoIterable) {
      dartModule.add(cssFilePath, codeInfo);
    }

    if (dartModule.infosList.isEmpty) return;
    if (isActualTest) print('[CssFileModuleBuilder] update ${dartModule.path}');

    final dartModuleContent = await _serializeAndResolveCss(
      dartModule,
      isTest: isTest,
    );
    if (dartModuleContent == null) return;

    final outputId = inputId.changeExtension(_cssfileExtension);
    await buildStep.writeAsString(outputId, dartModuleContent);
  }

  final _checkCssFileType = createTypeChecker(
    CssFile,
    inPackage: 'jaspr_css_file_builder',
  );
}

class CssFileBuilder implements Builder {
  late final List<String> _outputPaths;
  final bool isTest;

  CssFileBuilder({List<String>? outputPaths, this.isTest = false}) {
    if (outputPaths == null) {
      log.severe(
        'The build_runner option "output_paths" is required.'
        ' Please configure it in your build.yaml.',
      );
      throw ArgumentError('Missing required config: "output_paths"');
    }
    _outputPaths = outputPaths;
  }

  // NOTE:
  // - 目前 build.yaml 是 `r'$web$': ['.css']`, 此處是隨參數動態更新,
  //   實際運行是正常的. 但後續可能要追蹤 issues/3295 看看怎麼變化.
  //   https://github.com/dart-lang/build/issues/3295
  @override
  Map<String, List<String>> get buildExtensions => {r'$web$': _outputPaths};

  @override
  Future<void> build(BuildStep buildStep) async {
    final dartInputIdMap = <String, AssetId>{};
    final schedule = _DartToCssSchedule(isTest: isTest || isActualTest);

    final assetGlob = Glob('lib/**$_cssfileExtension');
    // 反序列化 #1: 取得 metadata
    await for (final inputId in buildStep.findAssets(assetGlob)) {
      // 只讀取第一行
      final bytes = await buildStep.readAsBytes(inputId);
      final firstLine = await Stream.value(bytes)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .catchError((_) => '');

      if (isTest) print('[CssFileBuilder] read json: $firstLine');
      final parsedJson = jsonDecode(firstLine) as Map<String, Object?>;
      final dartModule = _DartModule.deserialize(parsedJson);
      dartInputIdMap[dartModule.path] = inputId;
      schedule.addDartModule(dartModule);
    }

    for (final _ScheduleResult(:mode, :path, :codeInfos) in schedule.plan()) {
      if (isTest || isActualTest) print('[CssFileBuilder] $mode "$path"');
      switch (mode) {
        case _ScheduleMode.read:
          final inputId = dartInputIdMap[path]!;
          final content = await buildStep.readAsString(inputId);

          // 反序列化 #2: 取得 CSS 程式碼
          final cssCodes = content.split(_cssSeparator).skip(1).toList();
          if (isTest) {
            print(
              '[CssFileBuilder] read "$path" content:\n${cssCodes.join('\n')}',
            );
          }
          schedule.addCssCode(path, cssCodes);
          break;

        case _ScheduleMode.write:
          if (!_outputPaths.contains(path)) {
            log.warning(
              'The output path "$path" is not allowed.'
              ' Please add this path to the "output_paths" option in your build.yaml.',
            );
            continue;
          }

          // 比較 enum 的 index, 較小的排前面.
          codeInfos!.sort(
            (a, b) => a.category.index.compareTo(b.category.index),
          );
          final cssCode = codeInfos
              .map((item) => item.cssCode)
              .whereType<String>()
              .join('\n');
          final cssContent =
              '/* GENERATED CODE - DO NOT MODIFY BY HAND */'
              '\n\n$cssCode';

          final outputId = AssetId(buildStep.inputId.package, 'web/$path');
          await buildStep.writeAsString(outputId, cssContent.trimRight());
          break;
      }
    }
  }
}

enum _ElementTypeCategory {
  topLevelVariable, // index = 0
  classElement, // index = 1
  other, // index = 2
}

class _CodeInfo {
  final _ElementTypeCategory category;
  final String target;
  int line;
  int column;
  String? cssCode;

  _CodeInfo(this.category, this.target, this.line, this.column);

  factory _CodeInfo.deserialize(Map<String, Object?> json) {
    return _CodeInfo(
      switch (json['category'] as int) {
        0 => _ElementTypeCategory.topLevelVariable,
        1 => _ElementTypeCategory.classElement,
        _ => _ElementTypeCategory.other,
      },
      json['target'] as String,
      json['line'] as int,
      json['column'] as int,
    );
  }

  Map<String, dynamic> serialize() {
    return {
      'category': category.index,
      'target': target,
      'line': line,
      'column': column,
    };
  }
}

class _CssModuleCacheParty {
  final Map<String, List<_CodeInfo>> _rooms = {};

  List<_CodeInfo> getOrCreateRoom(String roomId) {
    // `.putIfAbsent()` 如果找不到 key，會執行第二函式參數直接創建, 插入並回傳, 效率優於 `.containsKey()`.
    return _rooms.putIfAbsent(roomId, () => []);
  }

  Iterable<List<_CodeInfo>> get values => _rooms.values;

  void add(String path, _CodeInfo codeInfo) {
    getOrCreateRoom(path).add(codeInfo);
  }

  void addAll(String path, List<_CodeInfo> codeInfos) {
    getOrCreateRoom(path).addAll(codeInfos);
  }

  List<_CodeInfo>? removeRoom(String roomId) => _rooms.remove(roomId);
}

class _DartModule extends _CssModuleCacheParty {
  final String path;
  final List<String> cssPaths = [];
  final List<List<_CodeInfo>> infosList = [];

  _DartModule(this.path);

  factory _DartModule.deserialize(Map<String, Object?> json) {
    final dartModule = _DartModule(json['path'] as String);

    final cssPathsJson = json['cssPaths'] as List<dynamic>?;
    if (cssPathsJson != null) {
      dartModule.cssPaths.addAll(cssPathsJson.cast<String>());
    }

    final infosListJson = json['infosList'] as List<dynamic>?;
    if (infosListJson != null) {
      final parsedList = infosListJson.map<List<_CodeInfo>>((infos) {
        return (infos as List<dynamic>).map<_CodeInfo>((item) {
          return _CodeInfo.deserialize(item as Map<String, Object?>);
        }).toList();
      }).toList();

      dartModule.infosList.addAll(parsedList);
    }

    return dartModule;
  }

  Map<String, dynamic> serialize() {
    return {
      'path': path,
      'cssPaths': cssPaths,
      'infosList': infosList.map((item) {
        return item.map((info) => info.serialize()).toList();
      }).toList(),
    };
  }

  List<_CodeInfo> get infos => infosList.expand((list) => list).toList();

  @override
  List<_CodeInfo> getOrCreateRoom(String roomId) {
    return _rooms.putIfAbsent(roomId, () {
      final list = <_CodeInfo>[];
      cssPaths.add(roomId);
      infosList.add(list);
      return list;
    });
  }
}

class _AssociatedGroupInfo {
  // 關聯的 dartPath 路徑列表
  final List<String> associatedList = [];
  // 屬於此組合的 cssPath 列表
  final List<String> groups = [];
  int remainedNodeCount = 0;
}

enum _ScheduleMode { read, write }

class _ScheduleResult {
  final _ScheduleMode mode;
  final String path;
  List<_CodeInfo>? codeInfos;

  _ScheduleResult(this.mode, this.path);
}

class _DartToCssSchedule {
  final bool isTest;

  final Map<String, _DartModule> _dartModuleInfo = {};

  // 儲存 _CodeInfo  節點數資訊. Key 格式為: "dart_$dartPath", "css_${cssPath}"
  final Map<String, int> _nodeCountInfo = {};

  // 記錄每個 cssPath 關聯了哪些 dartPath 路徑
  final Map<String, List<String>> _associatedInfoMap = {};

  final List<_AssociatedGroupInfo> _associatedGroupInfos = [];

  final _cssModuleCacheParty = _CssModuleCacheParty();

  /// 假設每個 [_CodeInfo] 節點佔用一樣的大小.
  /// 一份 Dart 文件可以包含多份 CSS 文件; 一份 CSS 文件可能散落於多分 Dart 文件中.
  /// 計算與該 CSS 關聯的 Dart 所有的節點數扣除該 CSS 的自身的節點數後排序, 用此找出佔用記憶體最少的排程規劃.
  _DartToCssSchedule({this.isTest = false});

  /// 當 CSS 路徑數量與程式碼資訊數量不相等時會忽略該 Dart 文件結果並以
  /// `log.warning()` 輸出提示訊息.
  void addDartModule(_DartModule dartModule) {
    final dartPath = dartModule.path;
    int totalNodeCount = 0;

    if (dartModule.cssPaths.length != dartModule.infosList.length) {
      log.warning(
        'Multi-build conversion failed (${dartModule.path}): CSS path and node data loss.',
      );
      return;
    }

    for (int idx = 0; idx < dartModule.cssPaths.length; idx++) {
      final cssPath = dartModule.cssPaths[idx];
      final codeInfos = dartModule.infosList[idx];

      _associatedInfoMap.putIfAbsent(cssPath, () => []).add(dartPath);
      _cssModuleCacheParty.addAll(cssPath, codeInfos);

      // 記錄 cssPath 在此 Dart 文件的 _CodeInfo 節點數
      final cssNodeCount = codeInfos.length;
      _nodeCountInfo.update(
        'css_$cssPath',
        (int value) => value + cssNodeCount,
        ifAbsent: () => cssNodeCount,
      );
      totalNodeCount += cssNodeCount;
    }

    _dartModuleInfo[dartPath] = dartModule;
    // 記錄 Dart 文件的 _CodeInfo 總節點數
    _nodeCountInfo['dart_$dartPath'] = totalNodeCount;
  }

  /// 當 CSS 資訊數量與程式碼內容數量不相等時會忽略該 Dart 文件結果並以
  /// `log.warning()` 輸出提示訊息.
  void addCssCode(String dartPath, List<String> cssCodes) {
    // 讓 _CodeInfo 只被 _cssModuleCacheParty 引用. 並在 [plan] 後清除記憶體佔用.
    final dartModule = _dartModuleInfo.remove(dartPath)!;
    final codeInfos = dartModule.infos;

    if (codeInfos.length != cssCodes.length) {
      log.warning(
        'Multi-build conversion failed (${dartModule.path}): CSS code data lost.',
      );
      return;
    }

    // 依序將轉換結果填回 CodeInfo
    for (var idx = 0; idx < codeInfos.length; idx++) {
      codeInfos[idx].cssCode = cssCodes[idx];
    }
  }

  void _resolveGroupInfos() {
    final Map<String, _AssociatedGroupInfo> associatedGroupInfoMap = {};

    // 群組配對 並 計算以群組為單位之扣除後的剩餘節點數
    for (final MapEntry(key: cssPath, value: dartPaths)
        in _associatedInfoMap.entries) {
      final signature = dartPaths.join('|');

      final info = associatedGroupInfoMap.putIfAbsent(
        signature,
        () => _AssociatedGroupInfo()
          ..associatedList.addAll(dartPaths)
          ..remainedNodeCount = dartPaths.fold<int>(
            0,
            (sum, dartPath) => sum + (_nodeCountInfo['dart_$dartPath'] ?? 0),
          ),
      );

      info.groups.add(cssPath);
      info.remainedNodeCount -= _nodeCountInfo['css_$cssPath'] ?? 0;
    }

    if (isTest) {
      for (final info in associatedGroupInfoMap.values) {
        var selfNodeCount = 0;
        for (final cssPath in info.groups) {
          selfNodeCount += _nodeCountInfo['css_$cssPath'] ?? 0;
        }

        print(
          '[CssFileBuilder] sorting info:\n'
          '  groups: ${info.groups}\n'
          '  associatedList: ${info.associatedList}\n'
          '  selfNode: $selfNodeCount\n'
          '  otherNode: ${info.remainedNodeCount}',
        );
      }
    }

    // 依 remainedNodeCount 由少到多排序
    _associatedGroupInfos.addAll(
      associatedGroupInfoMap.values.toList()
        ..sort((a, b) => a.remainedNodeCount.compareTo(b.remainedNodeCount)),
    );
  }

  var _isFirstRun = true;

  Iterable<_ScheduleResult> plan() sync* {
    if (_isFirstRun) {
      _isFirstRun = false;
      _resolveGroupInfos();
    }

    if (_associatedGroupInfos.isEmpty) return;

    final completedReadList = [];
    for (final associatedGroupInfo in _associatedGroupInfos) {
      for (final dartPath in associatedGroupInfo.associatedList) {
        if (completedReadList.contains(dartPath)) continue;

        completedReadList.add(dartPath);
        yield _ScheduleResult(_ScheduleMode.read, dartPath);
      }

      for (final cssPath in associatedGroupInfo.groups) {
        // 清除已完成讀取的 _CodeInfo 的記憶體佔用
        yield _ScheduleResult(_ScheduleMode.write, cssPath)
          ..codeInfos = _cssModuleCacheParty.removeRoom(cssPath);
      }
    }
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
Iterable<_MatchCodeInfo> _matchCodeInfoIterable(
  AssetId inputId,
  LibraryElement library,
  LineInfo lineInfo,
  CheckIsTargetType checkCssFileType,
) sync* {
  // NOTE:
  // library 只在此處被創建, 因此把 `library.firstFragment.source.fullName` 改為通用的
  // `inputId`.
  final inputLibraryFullPath = '/${inputId.package}/${inputId.path}';

  // 初始的候選元素: 所有的 `class` 和全域變數
  // 關於 elementList 是參考 [GitHub: schultek/jaspr][fn01]
  final elementInfos = [
    (
      _ElementTypeCategory.topLevelVariable,
      library.topLevelVariables.expand<Element>(
        (e) => switch (e) {
          final TopLevelVariableElement e when e.isOriginDeclaration => [e],
          TopLevelVariableElement(:final getter?) when e.isOriginGetterSetter =>
            [getter],
          _ => [],
        },
      ),
    ),
    (
      _ElementTypeCategory.classElement,
      library.classes.expand<Element>(
        (e) => switch (e) {
          final ClassElement e => [...e.fields, ...e.getters],
        },
      ),
    ),
  ];
  for (final (category, elementList) in elementInfos) {
    for (final element in elementList) {
      final matchCodeInfo = _matchCodeInfo(
        category,
        element,
        checkCssFileType,
        lineInfo,
        inputLibraryFullPath,
      );
      if (matchCodeInfo != null) {
        yield matchCodeInfo;
      }
    }
  }
}

_MatchCodeInfo? _matchCodeInfo(
  _ElementTypeCategory category,
  Element element,
  CheckIsTargetType checkCssFileType,
  LineInfo lineInfo,
  String inputLibraryFullPath,
) {
  final cssFile = _matchCssFileAnnotation(
    element,
    checkCssFileType,
    inputLibraryFullPath,
  );
  if (cssFile == null) return null;

  if (!_checkIsValidStyleRule(element, inputLibraryFullPath)) return null;

  final codeInfo = _resolveElement(category, element, lineInfo);
  if (codeInfo == null) return null;

  return _MatchCodeInfo(cssFile.path, codeInfo);
}

/// 以 [checkCssFileType] 方法過濾註解, 並將其還原成 [CssFile].
///
/// 當 [CssFile] 沒有指定輸出路徑時會忽略該註解並以 `log.warning()` 輸出提示訊息.
CssFile? _matchCssFileAnnotation(
  Element element,
  CheckIsTargetType checkCssFileType,
  String inputLibraryFullPath,
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
      ' Failing element:$elementTarget in library $inputLibraryFullPath.',
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
///
/// 當元素類型不符預期時會以 `log.warning()` 輸出提示訊息.
bool _checkIsValidStyleRule(Element element, String inputLibraryFullPath) {
  if (element.enclosingElement case final ClassElement clazz
      when clazz.isPrivate || element.isPrivate) {
    log.warning(
      '@CssFile cannot be used on private classes or members.'
      ' Failing element: ${clazz.name}.${element.name} in library $inputLibraryFullPath.',
    );
    return false;
  } else if (element.enclosingElement case final ClassElement clazz
      when (element is FieldElement && !element.isStatic) ||
          (element is GetterElement && !element.isStatic)) {
    log.warning(
      '@CssFile cannot be used on non-static class members.'
      ' Failing element: ${clazz.name}.${element.name} in library $inputLibraryFullPath.',
    );
    return false;
  } else if (element.isPrivate) {
    log.warning(
      '@CssFile cannot be used on private variables or getters.'
      ' Failing element: ${element.name} in library $inputLibraryFullPath.',
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
    log.warning(
      '@CssFile can only be applied on variables or getters of type List<StyleRule>.'
      ' Failing element: $prefix${element.name} with type $type in library ${element.library?.firstFragment.source.fullName}.',
    );
    return false;
  }

  return true;
}

// 從 [element] 解析出 [_CodeInfo] 的訊息.
_CodeInfo? _resolveElement(
  _ElementTypeCategory category,
  Element element,
  LineInfo lineInfo,
) {
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
    category,
    targetName,
    location.lineNumber,
    location.columnNumber,
  );
}

// 使用特殊的分隔符號，方便精準切分多個輸出結果. (相對於反序列化 JSON)
const _cssSeparator = '===CSS_SEPARATOR_FOR_BUILD_RUNNER===';

/// 當 Dart 轉換 CSS 程式碼失敗時會以 `log.severe()` 輸出錯誤訊息.
Future<String?> _serializeAndResolveCss(
  _DartModule dartModule, {
  required bool isTest,
}) async {
  final metadata = jsonEncode(dartModule.serialize());
  final infosToTransform = dartModule.infos;

  var dartToCssCode = _generateTransformCssCode(
    dartModule.path,
    infosToTransform,
    _cssSeparator,
  );
  // NOTE:
  // - build_test 的假資料無法使用腳本讀取
  if (isTest) {
    return '$metadata\n$_cssSeparator\n$dartToCssCode';
  }

  final (error, outputText) = await _transformCssBatch(
    dartToCssCode,
    _cssSeparator,
  );

  if (error != null) {
    log.severe('CSS transform failed (${dartModule.path}): $error');
    return null;
  }

  return '$metadata\n$_cssSeparator$outputText';
}

String _generateTransformCssCode(
  String dartModulePath,
  List<_CodeInfo> targets,
  String separator,
) {
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
  buffer.write("}");

  return buffer.toString();
}

/// 批次轉換 CSS 方法: 一份 Dart 文件只跑一次行程，處理多個 [_CodeInfo].
Future<(String? error, String? outputText)> _transformCssBatch(
  String dartToCssCode,
  String separator,
) async {
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
  process.stdin.write(dartToCssCode);
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

  final totalOutput = outputs.join().trim();
  return (null, totalOutput);
}

// Footnote:
// [fn01]:
//   Reference from: https://github.com/schultek/jaspr/blob/e4cc9d1/packages/jaspr_builder/lib/src/styles/styles_module_builder.dart#L50
//   Copyright (c) 2025 The Jaspr Authors.
//   Licensed under the MIT License.
