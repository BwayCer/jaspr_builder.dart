import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:jaspr_css_file_builder/builder.dart';

void main() {
  group('通用 Code Generator 測試', () {
    test('應該正確讀取輸入的 Dart 原始碼，並生成對應的 .g.dart 檔案', () async {
      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          'your_package|lib/user_model.dart': '''
class UserModel {
  final String name;
  UserModel(this.name);
}''',
        },

        // 預期 build_runner 幫你吐出來的 .g.dart 檔案內容
        outputs: {
          'your_package|lib/user_model.g.dart': '''
// **************************************************************************
// GENERATED CODE - DO NOT MODIFY BY HAND
// **************************************************************************

// 這是複製自 lib/user_model.dart 的內容：
class UserModel {
  final String name;
  UserModel(this.name);
}
''',
        },
      );
    });
  });
}
