import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../shared.dart';

@appCssFile
List<StyleRule> get circleRefChainStyles => [
  css('.styleColor3').styles(
    content: '1',
  ),
];

class CircleRefChain3 extends StatelessComponent {
  final String classes;

  const CircleRefChain3({this.classes = ''});

  static List<StyleRule> get styles => [
    css('.styleColor3').styles(
      backgroundColor: primarieColors[7],
    ),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: '$classes styleColor3', []);
  }
}
