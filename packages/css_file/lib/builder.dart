import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';

import 'package:glob/glob.dart';

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
  final List<PropertyAccessorElement> allGetters = [];

  // 收集該片段下的頂層 getters (例如外層的 List<StyleRule> get styles)
  allGetters.addAll(library.getters);

  // 收集該片段下所有類別內部的 getters (例如 class 裡的 static get styles)
  for (final clazz in library.classes) {
    allGetters.addAll(clazz.getters);
  }

  for (final element in allGetters) {
    final annotations = element.metadata.annotations;

    final hasCssFile = annotations.any(checkCssFileType);
    if (!hasCssFile) continue;

    final annotation = annotations.firstWhere(checkCssFileType);
    // 取得 @CssFile 的 path 參數
    final computedAnnotation = annotation.computeConstantValue();
    final pathValue =
        computedAnnotation?.getField('path')?.toStringValue() ?? '';
    if (pathValue == '') continue;

    yield _MatchedElement(pathValue, element);
  }
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
