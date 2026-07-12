import 'dart:async';
import 'package:build/build.dart';

Builder copyGeneratorBuilder(BuilderOptions options) => CopyGeneratorBuilder();

class CopyGeneratorBuilder implements Builder {
  // 定義輸入與輸出的映射關係: 輸入 ".dart"，輸出 ".g.dart"
  @override
  final Map<String, List<String>> buildExtensions = const {
    '.dart': ['.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // 1. 讀取觸發此 BuildStep 的輸入檔案內容
    final inputContent = await buildStep.readAsString(buildStep.inputId);

    // 2. 準備輸出的檔案路徑（把擴充檔名換成 .g.dart）
    final outputId = buildStep.inputId.changeExtension('.g.dart');

    // 3. 組合出你要生成的固定代碼文字
    final generatedCode =
        '''
// **************************************************************************
// GENERATED CODE - DO NOT MODIFY BY HAND
// **************************************************************************

// 這是複製自 ${buildStep.inputId.path} 的內容：
$inputContent
''';

    // 4. 將生成的代碼寫入檔案系統
    await buildStep.writeAsString(outputId, generatedCode);
  }
}
