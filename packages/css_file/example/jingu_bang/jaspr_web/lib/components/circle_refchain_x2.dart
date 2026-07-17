import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../shared.dart';
import './circle_refchain_x3.dart';

class CircleRefChain2 extends StatelessComponent {
  final String classes;

  const CircleRefChain2({this.classes = ''});

  static List<StyleRule> get styles => [
    css('.styleColor2').styles(
      backgroundColor: primarieColors[4],
    ),
    ...CircleRefChain3.styles,
  ];

  @override
  Component build(BuildContext context) {
    return .fragment([
      div(classes: '$classes styleColor2', []),
      CircleRefChain3(classes: classes),
    ]);
  }
}
