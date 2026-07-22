Jaspr `@CssFile` Builder
=======

A compile-time static CSS generator designed specifically for the [Jaspr](https://github.com/schultek/jaspr) web framework.

Convert the `styleRules` definition component styles in the Jaspr Dart code into a standalone CSS file.

專為 [Jaspr](https://github.com/schultek/jaspr) Web 框架設計的編譯時靜態 CSS 生成器。

把 Jaspr Dart 程式碼中的 `styleRules` 定義組件樣式轉換成獨立的 CSS 文件。


## TL;DR

**Usage:**

  ```yml
  // build.yaml
  targets:
    $default:
      builders:
        jaspr_css_file_builder|css_file_builder:
          options:
            output_paths:
              - styles/app.css
  ```

  ```dart
  import 'package:jaspr_css_file_builder/annotations.dart';

  const appCssFile = CssFile('styles/app.css');

  // @appCssFile
  // or
  @CssFile('styles/app.css')
  List<StyleRule> get styles => [
    css('.main').styles(
      display: Display.flex,
      flexDirection: FlexDirection.row,
    ),
    css.media(MediaQuery.screen(maxWidth: 600.px), [
      css('.main').styles(
        flexDirection: FlexDirection.column,
      ),
    ]),
  ];

  class App extends StatelessComponent {
    @appCssFile
    static List<StyleRule> get styles => [
      css('.main', [
        css('&').styles(
          width: 100.px,
          padding: Padding.all(10.rem),
        ),
        css('p').styles(
          color: Colors.blue,
        ),
      ]),
    ];
  }
  ```

**Generator:**

  ```css
  /* web/styles/app.css */
  /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */

  .main {
    display: flex;
    flex-direction: row;
  }
  @media screen and (max-width: 600px) {
    .main {
      flex-direction: column;
    }
  }
  .main {
    width: 100px;
    padding: 10rem;
  }
  .main p {
    color: blue;
  }
  ```
