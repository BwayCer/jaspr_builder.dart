import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

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
  // 目前 build.yaml 是 `r'$web$': ['.css']`, 此處是隨參數動態更新,
  // 實際運行是正常的. 但後續可能要追蹤 issues/3295 看看怎麼變化.
  // https://github.com/dart-lang/build/issues/3295
  @override
  Map<String, List<String>> get buildExtensions => {r'$web$': _outputPaths};

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetGlob = Glob('lib/**.dart');
    await for (final inputId in buildStep.findAssets(assetGlob)) {
      final library = await buildStep.resolver.libraryFor(inputId);

      final matchElementStream = _matchElementByAnnotationStream(
        library,
        _checkCssFileType,
      );
      await for (final _MatchedElement(:cssFilePath) in matchElementStream) {
        if (!_outputPaths.contains(cssFilePath)) {
          log.warning(
            'The output path "$cssFilePath" is not allowed.'
            ' Please add this path to the "outputPaths" option in your build.yaml.',
          );
          continue;
        }

        await sampleBuild(buildStep, inputId);
      }
    }
  }

  final _checkCssFileType = createTypeChecker(
    CssFile,
    inPackage: 'jaspr_css_file_builder',
  );
}

class _MatchedElement {
  final String cssFilePath;
  final Element element;

  const _MatchedElement(this.cssFilePath, this.element);
}

/// 以註解過濾元素
Stream<_MatchedElement> _matchElementByAnnotationStream(
  LibraryElement library,
  CheckIsTargetType checkCssFileType,
) async* {
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
    final cssFile = _getCssFileAnnotation(
      element,
      checkCssFileType,
      inputSystemPath,
    );
    if (cssFile == null) continue;

    if (!_checkIsValidStyleRule(element, inputSystemPath)) continue;

    yield _MatchedElement(cssFile.path, element);
  }
}

/// 搜尋元素上是否有 `@CssFile` 註解並將其還原.
///
/// 當 `@CssFile` 沒有指定輸出路徑時會跳過該選項並以 `log.warning()` 輸出提示訊息.
CssFile? _getCssFileAnnotation(
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

Future<void> sampleBuild(BuildStep buildStep, AssetId inputId) async {
  // 1. 讀取觸發此 BuildStep 的輸入檔案內容
  final inputContent = await buildStep.readAsString(inputId);

  // 2. 組合出你要生成的固定代碼文字
  final generatedCode =
      '''
// **************************************************************************
// GENERATED CODE - DO NOT MODIFY BY HAND
// **************************************************************************

// 這是複製自 ${inputId.path} 的內容：
$inputContent
''';

  // 3. 準備輸出的檔案路徑
  final outputId = AssetId(buildStep.inputId.package, 'web/${inputId.path}');
  // 4. 將生成的代碼寫入檔案系統
  await buildStep.writeAsString(outputId, generatedCode);
}

// Footnote:
// [fn01]: https://github.com/schultek/jaspr/blob/e4cc9d1/packages/jaspr_builder/lib/src/styles/styles_module_builder.dart#L50
