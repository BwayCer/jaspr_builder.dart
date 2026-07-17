import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:other_components/components.dart';

import './shared.dart';
import './components/circle_refchain_x1.dart';
import './components/circle_deferred_x1.dart' deferred as deferred_x1;

export './shared.dart' show appCssFile, componentsCssFile, deferredCssFile;

@componentsCssFile
List<StyleRule> get componentStyles_ => componentStyles;

const appBackgroundColor = Color('#3d2222');

@appCssFile
List<StyleRule> get appStyles => [
  css('body').styles(
    padding: .zero,
    margin: .unset,
    backgroundColor: appBackgroundColor,
  ),
  ...CircleRefChain1.styles,
];

/// 用以避免手機的寬度 layout viewport (元素大小) 大於 visual viewport (螢幕大小) 時高度會同比例放大的情況.
class RwdBody extends StatelessComponent {
  final Component child;

  const RwdBody(this.child, {super.key});

  @appCssFile
  static List<StyleRule> get styles => [
    css('.rwdbody').styles(
      position: .relative(),
      width: 100.vw,
      height: 100.vh,
      overflow: .auto,
    ),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: 'rwdbody', [child]);
  }
}

@client
class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => AppState();
}

class AppState extends State<App> {
  // 控制面板位置
  final double controlPanelHeight = 84.0;
  final double distanceFromBottom = 20.0;

  // 動態操作狀態
  double currentLength = 300.0; // 紅桿長度 (px)
  double currentAngle = -45.0; // 旋轉角度 (deg)

  // 安全角度邊界
  double minAngle = -180.0;
  double maxAngle = 180.0;

  bool isLoaded = false;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      Future.wait([
            Future.delayed(const Duration(seconds: 3)),
            deferred_x1.loadLibrary(),
          ])
          .then((_) {
            setState(() {
              isLoaded = true;
            });
          })
          .catchError((error) {
            print('Library "deferred_x1" loading failed: $error');
          });
    }
  }

  @appCssFile
  static List<StyleRule> get styles => [
    css('.fix-box', [
      css('&').styles(
        position: .fixed(top: 1.vh, left: 1.vw),
        zIndex: ZIndex(2),
        width: (4 * 40).px,
      ),
      css('& > .circle-box').styles(
        display: Display.inlineBlock,
        width: 30.px,
        height: 30.px,
        margin: .all(5.px),
        boxSizing: BoxSizing.borderBox,
        border: .all(style: .solid, color: primarieColors[17], width: 3.px),
        radius: .circular(50.percent),
      ),
      css.media(MediaQuery.screen(maxWidth: 359.98.px), [
        css('&').styles(
          position: .absolute(top: 3.6.px, left: 3.6.px),
        ),
      ]),
    ]),
    css('.main', [
      css('&').styles(
        position: Position.relative(),
        width: 100.percent,
        height: 100.vh,
        minWidth: 360.px,
        minHeight: 360.px,
        backgroundColor: appBackgroundColor,
        raw: {'overflow': 'hidden'},
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final Component deferredComponent = switch (isLoaded) {
      true => deferred_x1.CircleDeferred1(classes: 'circle-box'),
      false => .empty(),
    };
    return RwdBody(
      .fragment([
        div(
          classes: 'fix-box',
          [
            CircleRefChain1(classes: 'circle-box'),
            deferredComponent,
          ],
        ),
        div(
          classes: 'main',
          [
            RuyiJinguBang(
              currentLength: currentLength,
              currentAngle: currentAngle,
            ),
            ControlPanel(
              controlPanelHeight: controlPanelHeight,
              distanceFromBottom: distanceFromBottom,
              currentLength: currentLength,
              currentAngle: currentAngle,
              minAngle: minAngle,
              maxAngle: maxAngle,
              onLengthChanged: (val) {
                setState(() => currentLength = val);
              },
              onAngleChanged: (val) {
                setState(() => currentAngle = val);
              },
            ),
          ],
        ),
      ]),
    );
  }
}
