import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:jaspr_css_file_builder/builder.dart';

void main() {
  var baseLoglength = 0;
  final dependencies = {
    'jaspr|lib/dom.dart': '''
      class StyleRule {}
    ''',

    'jaspr_css_file_builder|lib/annotations.dart': '''
      class CssFile {
        final String path;

        const CssFile(this.path);
      }
    ''',
  };

  group('Builder 類型測試:', () {
    test('未提供 "outputPaths" 參數時給予拋出 ArgumentError', () async {
      expect(() => CssFileBuilder(isTest: true), throwsA(isA<ArgumentError>()));
    });
  });

  group('@CssFile 的註解測試:', () {
    test('準備...', () async {
      final logs = <String>[];

      await testBuilder(
        CssFileBuilder(outputPaths: [], isTest: true),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            class UserTmpl {}
          ''',
        },

        rootPackage: 'my_project',
        onLog: (logRecord) {
          logs.add(logRecord.message);
        },
      );

      // NOTE:
      // - 訊息包含 `print`, `log` 等, 會受 `if` 影響所以不一定準確.
      baseLoglength = logs.length;
    });

    test('未指定輸出路徑時給予 log 警告訊息', () async {
      final logs = <String>[];

      await testBuilder(
        CssFileBuilder(outputPaths: [], isTest: true),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            @CssFile()
            List<StyleRule> get styles => [
              css('html').styles(fontSize: 16.px),
            ];

            class UserTmpl {
              @CssFile()
              static List<StyleRule> get styles => [
                css('html').styles(fontSize: 16.px),
              ];
            }
          ''',
        },

        rootPackage: 'my_project',
        onLog: (logRecord) {
          logs.add(logRecord.message);
        },
      );

      expect(logs, hasLength(2 + baseLoglength));

      final inputSystemPath = 'in library /my_project/lib/user_tmpl.dart';
      expect(
        logs,
        anyElement(
          contains(
            '@CssFile has not file path.'
            ' Failing element: styles $inputSystemPath.',
          ),
        ),
      );
      expect(
        logs,
        anyElement(
          contains(
            '@CssFile has not file path.'
            ' Failing element: UserTmpl.styles $inputSystemPath.',
          ),
        ),
      );
    });

    test('@CssFile 的路徑不在允許清單時給予 log 警告訊息', () async {
      final logs = <String>[];

      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(outputPaths: [], isTest: true),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          ...dependencies,

          'my_project|lib/user.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            class UserTmpl {
              @CssFile('lib/user_tmpl.dart')
              static List<StyleRule> get styles => [
                css('html').styles(fontSize: 16.px),
              ];
            }
          ''',
        },

        rootPackage: 'my_project',
        onLog: (logRecord) {
          logs.add(logRecord.message);
        },
      );

      expect(
        logs,
        anyElement(
          contains(
            'The output path "lib/user_tmpl.dart" is not allowed.'
            ' Please add this path to the "outputPaths" option in your build.yaml.',
          ),
        ),
      );
    });
  });

  group('@CssFile 的元素測試:', () {
    test('類型錯誤時給予 log 警告訊息', () async {
      final logs = <String>[];

      await testBuilder(
        CssFileBuilder(outputPaths: ['lib/user_tmpl.dart'], isTest: true),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            @CssFile('lib/user_tmpl.dart')
            List<dynamic> globalStyles = [
              css('html').styles(fontSize: 16.px),
            ];

            @CssFile('lib/user_tmpl.dart')
            List<dynamic> get globalGetterStyles => [
              css('html').styles(fontSize: 16.px),
            ];

            @CssFile('lib/user_tmpl.dart')
            List<StyleRule> get _globalGetterStyles => [
              css('html').styles(fontSize: 16.px),
            ];

            class UserTmpl {
              @CssFile('lib/user_tmpl.dart')
              static List<dynamic> clazzStyles = [
                css('html').styles(fontSize: 16.px),
              ];

              @CssFile('lib/user_tmpl.dart')
              List<StyleRule> clazzStaticStyles = [
                css('html').styles(fontSize: 16.px),
              ];

              @CssFile('lib/user_tmpl.dart')
              static List<dynamic> get clazzGetterStyles => [
                css('html').styles(fontSize: 16.px),
              ];

              @CssFile('lib/user_tmpl.dart')
              static List<StyleRule> get _clazzGetterStyles => [
                css('html').styles(fontSize: 16.px),
              ];
            }
          ''',
        },

        rootPackage: 'my_project',
        onLog: (logRecord) {
          logs.add(logRecord.message);
        },
      );

      final inputSystemPath = 'in library /my_project/lib/user_tmpl.dart';

      expect(
        logs,
        anyElement(
          contains(
            '@CssFile cannot be used on private classes or members.'
            ' Failing element: UserTmpl._clazzGetterStyles $inputSystemPath.',
          ),
        ),
      );

      expect(
        logs,
        anyElement(
          contains(
            '@CssFile cannot be used on non-static class members.'
            ' Failing element: UserTmpl.clazzStaticStyles $inputSystemPath.',
          ),
        ),
      );

      expect(
        logs,
        anyElement(
          contains(
            '@CssFile cannot be used on private variables or getters.'
            ' Failing element: _globalGetterStyles $inputSystemPath.',
          ),
        ),
      );

      expect(
        logs,
        anyElement(
          contains(
            '@CssFile can only be applied on variables or getters of type List<StyleRule>.'
            ' Failing element: globalStyles with type List<dynamic> $inputSystemPath.',
          ),
        ),
      );
      expect(
        logs,
        anyElement(
          contains(
            '@CssFile can only be applied on variables or getters of type List<StyleRule>.'
            ' Failing element: globalGetterStyles with type List<dynamic> $inputSystemPath.',
          ),
        ),
      );
      expect(
        logs,
        anyElement(
          contains(
            '@CssFile can only be applied on variables or getters of type List<StyleRule>.'
            ' Failing element: UserTmpl.clazzStyles with type List<dynamic> $inputSystemPath.',
          ),
        ),
      );
      expect(
        logs,
        anyElement(
          contains(
            '@CssFile can only be applied on variables or getters of type List<StyleRule>.'
            ' Failing element: UserTmpl.clazzGetterStyles with type List<dynamic> $inputSystemPath.',
          ),
        ),
      );
    });
  });

  group('輸出內容測試:', () {
    test('轉換腳本的引用對象不存在時給予 log 錯誤訊息', () async {
      final logs = <String>[];

      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(outputPaths: ['lib/user_tmpl.dart']),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          ...dependencies,

          'my_project|lib/user.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            class UserTmpl {
              @CssFile('lib/user_tmpl.dart')
              static List<StyleRule> get styles => [
                css('html').styles(fontSize: 16.px),
              ];
            }
          ''',
        },

        rootPackage: 'my_project',
        onLog: (logRecord) {
          logs.add(logRecord.message);
        },
      );

      expect(
        logs,
        anyElement(
          contains(
            'CSS transform failed (package:my_project/user.dart): Error: Couldn\'t resolve the package \'my_project\' in \'package:my_project/user.dart\'.\n'
            '/dev/stdin:2:8: Error: Not found: \'package:my_project/user.dart\'\n'
            'import \'package:my_project/user.dart\';\n'
            '       ^\n'
            '/dev/stdin:5:28: Error: Undefined name \'UserTmpl\'.\n'
            '  results.add(transformCss(UserTmpl.styles));\n'
            '                           ^^^^^^^^',
          ),
        ),
      );
    });

    test('生成對應轉換腳本', () async {
      await testBuilder(
        CssFileBuilder(outputPaths: ['lib/user_tmpl.dart'], isTest: true),

        {
          ...dependencies,

          'my_project|lib/user.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            class UserTmpl {
              @CssFile('lib/user_tmpl.dart')
              static List<StyleRule> get styles => [
                css('html').styles(fontSize: 16.px),
              ];
            }
          ''',
        },

        outputs: {
          'my_project|web/lib/user_tmpl.dart': trimIndent('            ', '''
            /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

            import 'package:jaspr/dom.dart';
            import 'package:my_project/user.dart';
            void main() async {
              final List<String> results = [];
              results.add(transformCss(UserTmpl.styles));
              print(results.join('===CSS_SEPARATOR_FOR_BUILD_RUNNER==='));
            }
            String transformCss(List<StyleRule> styleRules) {
              return styleRules.map((item) => item.toCss()).join('\\n');
            }'''),
        },

        rootPackage: 'my_project',
      );
    });
  });
}

String trimIndent(String indent, String text) {
  return text
      .split('\n')
      .map((line) => line.replaceFirst(indent, ''))
      .join('\n');
}
