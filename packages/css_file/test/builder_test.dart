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
        CssFileModuleBuilder(isTest: true),

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
        CssFileBuilder(outputPaths: [], isTest: true),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:my_project/user_tmpl.dart","cssPaths":["styles/user.css"],"infosList":[[{"category":1,"target":"UserTmpl.styles","line":5,"column":2}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===html {
                font-size: 16px;
              }
            ''',
          ),
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
            'The output path "styles/user.css" is not allowed.'
            ' Please add this path to the "output_paths" option in your build.yaml.',
          ),
        ),
      );
    });
  });

  group('@CssFile 的元素測試:', () {
    test('類型錯誤時給予 log 警告訊息', () async {
      final logs = <String>[];

      await testBuilder(
        CssFileModuleBuilder(isTest: true),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            @CssFile('styles/user.css')
            List<dynamic> globalStyles = [
              css('html').styles(fontSize: 16.px),
            ];

            @CssFile('styles/user.css')
            List<dynamic> get globalGetterStyles => [
              css('html').styles(fontSize: 16.px),
            ];

            @CssFile('styles/user.css')
            List<StyleRule> get _globalGetterStyles => [
              css('html').styles(fontSize: 16.px),
            ];

            class UserTmpl {
              @CssFile('styles/user.css')
              static List<dynamic> clazzStyles = [
                css('html').styles(fontSize: 16.px),
              ];

              @CssFile('styles/user.css')
              List<StyleRule> clazzStaticStyles = [
                css('html').styles(fontSize: 16.px),
              ];

              @CssFile('styles/user.css')
              static List<dynamic> get clazzGetterStyles => [
                css('html').styles(fontSize: 16.px),
              ];

              @CssFile('styles/user.css')
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

  group('兩步驟 Builder 測試:', () {
    test('CSS 路徑數量與程式碼資訊數量不相等時給予 log 警告', () async {
      final logs = <String>[];

      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(
          outputPaths: ['styles/ca.css', 'styles/cb.css'],
          isTest: true,
        ),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          ...dependencies,

          'my_project|lib/da.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/da.dart","cssPaths":["styles/ca.css","styles/cb.css"],"infosList":[[{"category":1,"target":"styleA1","line":10,"column":5},{"category":1,"target":"styleA2","line":11,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-2";
              }
            ''',
          ),
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
            'Multi-build conversion failed (package:jaspr_web/da.dart):'
            ' CSS path and node data loss.',
          ),
        ),
      );
    });

    test('CSS 資訊數量與程式碼內容數量不相等時給予 log 警告', () async {
      final logs = <String>[];

      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(outputPaths: ['styles/ca.css'], isTest: true),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          ...dependencies,

          'my_project|lib/da.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/da.dart","cssPaths":["styles/ca.css"],"infosList":[[{"category":1,"target":"styleA1","line":10,"column":5},{"category":1,"target":"styleA2","line":11,"column":5},{"category":1,"target":"styleA3","line":12,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-2";
              }
            ''',
          ),
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
            'Multi-build conversion failed (package:jaspr_web/da.dart):'
            ' CSS code data lost.',
          ),
        ),
      );
    });
  });

  group('輸出內容測試:', () {
    test('轉換腳本的引用對象不存在時給予 log 錯誤訊息', () async {
      final logs = <String>[];

      await testBuilder(
        CssFileModuleBuilder(),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            class UserTmpl {
              @CssFile('lib/user.css')
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
            'CSS transform failed (package:my_project/user_tmpl.dart):'
            ' Error: Couldn\'t resolve the package \'my_project\' in \'package:my_project/user_tmpl.dart\'.\n'
            '/dev/stdin:2:8: Error: Not found: \'package:my_project/user_tmpl.dart\'\n'
            'import \'package:my_project/user_tmpl.dart\';\n'
            '       ^\n'
            '/dev/stdin:5:28: Error: Undefined name \'UserTmpl\'.\n'
            '  results.add(transformCss(UserTmpl.styles));\n'
            '                           ^^^^^^^^',
          ),
        ),
      );
    });

    test('第一步 Builder: 生成對應轉換腳本', () async {
      await testBuilder(
        CssFileModuleBuilder(isTest: true),

        {
          ...dependencies,

          'my_project|lib/user_tmpl.dart': '''
            import 'package:jaspr/dom.dart';
            import 'package:jaspr_css_file_builder/annotations.dart';

            @CssFile('lib/other.css')
            List<StyleRule> get otherStyles => [
              css('html').styles(fontSize: 16.px),
            ];

            class UserTmpl {
              @CssFile('lib/user.css')
              static List<StyleRule> get styles => [
                css('html').styles(fontSize: 16.px),
              ];
            }
          ''',
        },

        outputs: {
          'my_project|lib/user_tmpl.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:my_project/user_tmpl.dart","cssPaths":["lib/other.css","lib/user.css"],"infosList":[[{"category":0,"target":"otherStyles","line":5,"column":33}],[{"category":1,"target":"UserTmpl.styles","line":11,"column":42}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===
              import 'package:jaspr/dom.dart';
              import 'package:my_project/user_tmpl.dart';
              void main() async {
                final List<String> results = [];
                results.add(transformCss(otherStyles));
                results.add(transformCss(UserTmpl.styles));
                print(results.join('===CSS_SEPARATOR_FOR_BUILD_RUNNER==='));
              }
              String transformCss(List<StyleRule> styleRules) {
                return styleRules.map((item) => item.toCss()).join('\\n');
              }
            ''',
          ),
        },

        rootPackage: 'my_project',
      );
    });

    test('第二步 Builder: 把各個 Dart 生成的內容組合成 CSS', () async {
      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(
          outputPaths: [
            'styles/ca.css',
            'styles/cb.css',
            'styles/cc.css',
            'styles/cd.css',
          ],
          isTest: true,
        ),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          ...dependencies,

          'my_project|lib/da.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/da.dart","cssPaths":["styles/ca.css"],"infosList":[[{"category":1,"target":"styleA1","line":10,"column":5},{"category":1,"target":"styleA2","line":11,"column":5},{"category":1,"target":"styleA3","line":12,"column":5},{"category":1,"target":"styleA4","line":13,"column":5},{"category":1,"target":"styleA5","line":14,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-2";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-3";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-4";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-5";
              }
            ''',
          ),

          'my_project|lib/db.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/db.dart","cssPaths":["styles/cb.css","styles/cc.css"],"infosList":[[{"category":1,"target":"styleB6","line":15,"column":5}],[{"category":1,"target":"styleC7","line":5,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cb {
                content: "db-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cc {
                content: "db-2";
              }
            ''',
          ),

          'my_project|lib/dc.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/dc.dart","cssPaths":["styles/cc.css","styles/cd.css"],"infosList":[[{"category":1,"target":"styleC8","line":2,"column":5}],[{"category":1,"target":"styleD9","line":18,"column":5},{"category":1,"target":"styleD10","line":30,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cc {
                content: "dc-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cd {
                content: "dc-2";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cd {
                content: "dc-3";
              }
            ''',
          ),

          'my_project|lib/dd.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/dd.dart","cssPaths":["styles/cc.css"],"infosList":[[{"category":1,"target":"styleC11","line":32,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cc {
                content: "dd-1";
              }
            ''',
          ),

          'my_project|lib/de.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/De.dart","cssPaths":["styles/cc.css"],"infosList":[[{"category":1,"target":"styleC12","line":50,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.cc {
                content: "de-1";
              }
            ''',
          ),
        },

        outputs: {
          'my_project|web/styles/ca.css': trimIndent('              ', '''
              /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

              .ca {
                content: "da-1";
              }
              .ca {
                content: "da-2";
              }
              .ca {
                content: "da-3";
              }
              .ca {
                content: "da-4";
              }
              .ca {
                content: "da-5";
              }
            '''),

          'my_project|web/styles/cb.css': trimIndent('              ', '''
              /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

              .cb {
                content: "db-1";
              }
            '''),

          'my_project|web/styles/cc.css': trimIndent('              ', '''
              /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

              .cc {
                content: "db-2";
              }
              .cc {
                content: "dc-1";
              }
              .cc {
                content: "dd-1";
              }
              .cc {
                content: "de-1";
              }
            '''),

          'my_project|web/styles/cd.css': trimIndent('              ', '''
              /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

              .cd {
                content: "dc-2";
              }
              .cd {
                content: "dc-3";
              }
            '''),
        },

        rootPackage: 'my_project',
      );
    });

    test('第二步 Builder: 全域生成的 CSS 排序放於 Class 生成的 CSS', () async {
      await testBuilder(
        // 帶入要測試的通用 Builder
        CssFileBuilder(outputPaths: ['styles/ca.css']),

        // 模擬虛擬檔案系統中的輸入檔案
        {
          ...dependencies,

          'my_project|lib/da.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/da.dart","cssPaths":["styles/ca.css"],"infosList":[[{"category":0,"target":"styleA1","line":10,"column":5},{"category":1,"target":"styleA2","line":11,"column":5},{"category":0,"target":"styleA3","line":12,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-top-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-class-2";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "da-top-3";
              }
            ''',
          ),

          'my_project|lib/db.styles.cssfile.txt': trimIndent(
            '              ',
            '''
              {"path":"package:jaspr_web/db.dart","cssPaths":["styles/ca.css"],"infosList":[[{"category":1,"target":"styleC8","line":2,"column":5},{"category":0,"target":"styleD9","line":18,"column":5},{"category":1,"target":"styleD10","line":30,"column":5}]]}
              ===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "db-class-1";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "db-top-2";
              }===CSS_SEPARATOR_FOR_BUILD_RUNNER===.ca {
                content: "db-class-3";
              }
            ''',
          ),
        },

        outputs: {
          'my_project|web/styles/ca.css': trimIndent('              ', '''
              /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

              .ca {
                content: "da-top-1";
              }
              .ca {
                content: "da-top-3";
              }
              .ca {
                content: "db-top-2";
              }
              .ca {
                content: "da-class-2";
              }
              .ca {
                content: "db-class-1";
              }
              .ca {
                content: "db-class-3";
              }
            '''),
        },

        rootPackage: 'my_project',
      );
    });
  });
}

String trimIndent(String indent, String text) {
  return text
      .trim()
      .split('\n')
      .map((line) => line.replaceFirst(indent, ''))
      .join('\n');
}
