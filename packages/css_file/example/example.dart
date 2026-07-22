import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_css_file_builder/annotations.dart';

const appCssFile = CssFile('styles/app.css');
// appCssFile.path == 'styles/app.css'
// Generate a CSS file at web/styles/app.css

// NOTE:
// Need to sync and allow this path in build.yaml
// ```yml
// targets:
//   $default:
//     builders:
//       jaspr_css_file_builder|css_file_builder:
//         options:
//           output_paths:
//             - styles/app.css
// ```

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
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'main', [
      p([.text('Hello World')]),
    ]);
  }

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

// Generator "web/styles/app.css"
// ```css
// /* AUTOMATICALLY GENERATED. DO NOT EDIT MANUALLY. */
//
// .main {
//   display: flex;
//   flex-direction: row;
// }
// @media screen and (max-width: 600px) {
//   .main {
//     flex-direction: column;
//   }
// }
// .main {
//   width: 100px;
//   padding: 10rem;
// }
// .main p {
//   color: blue;
// }
// ```
