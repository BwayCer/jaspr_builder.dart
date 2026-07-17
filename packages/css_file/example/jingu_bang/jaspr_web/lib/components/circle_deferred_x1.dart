import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../shared.dart';

class CircleDeferred1 extends StatelessComponent {
  final String classes;

  const CircleDeferred1({this.classes = ''});

  @deferredCssFile
  static List<StyleRule> get styles => [
    css('.styleColor10').styles(
      backgroundColor: primarieColors[10],
    ),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: '$classes styleColor10', []);
  }
}
