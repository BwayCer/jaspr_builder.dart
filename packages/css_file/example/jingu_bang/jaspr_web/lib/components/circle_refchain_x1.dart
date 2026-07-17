import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../shared.dart';
import './circle_refchain_x2.dart';

@appCssFile
List<StyleRule> get circleRefChainStyles => [
  css('.styleColor1').styles(
    content: '1',
  ),
];

class CircleRefChain1 extends StatelessComponent {
  final String classes;

  const CircleRefChain1({this.classes = ''});

  static List<StyleRule> get styles => [
    css('.styleColor1').styles(
      backgroundColor: primarieColors[1],
    ),
    ...CircleRefChain2.styles,
  ];

  @override
  Component build(BuildContext context) {
    return .fragment([
      div(classes: '$classes styleColor1', []),
      CircleRefChain2(classes: classes),
    ]);
  }
}
