jaspr_web
=======

測試項目：

  - 載入 CSS 文件

    ```dart
    // ./lib/main.server.dart
    runApp(
      Document(
        head: [
          link(href: appCssFile.path, rel: 'stylesheet'),
        ],
      ),
    );
    ```

  - 一般宣告 CSS 文件

    ```dart
    // ./lib/app.dart
    @appCssFile
    List<StyleRule> get appStyles => [...];
    ```

    ```dart
    // ./lib/app.dart
    class AppState extends State<App> {
      @appCssFile
      static List<StyleRule> get styles => [...];
    }
    ```

  - 層層引用的 CSS 文件

    ```dart
    // ./lib/app.dart
    import './components/circle_refchain_x1.dart';

    @appCssFile
    List<StyleRule> get appStyles => [
      ...CircleRefChain1.styles,
    ];
    ```

    ```dart
    // ./lib/components/circle_refchain_xX.dart
    import './circle_refchain_xX.dart';

    class CircleRefChain1 extends StatelessComponent {
      static List<StyleRule> get styles => [
        ...CircleRefChainX.styles,
      ];
    }
    ```

  - 外部外部專案的 CSS 文件

    ```dart
    // ./lib/app.dart
    import 'package:other_components/components.dart';

    @componentsCssFile
    List<StyleRule> get componentStyles_ => componentStyles;
    ```

  - 延遲載入文件中的 CSS 文件

    ```dart
    // ./lib/app.dart
    import './components/circle_deferred_x1.dart' deferred as deferred_x1;
    ```

    ```dart
    // ./lib/components/circle_deferred_x1.dart
    class CircleDeferred1 extends StatelessComponent {
      @deferredCssFile
      static List<StyleRule> get styles => [...];
    }
    ```
