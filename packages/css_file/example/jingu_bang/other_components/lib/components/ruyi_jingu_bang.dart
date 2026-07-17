import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class RuyiJinguBang extends StatelessComponent {
  // 動態操作狀態
  final double currentLength; // 紅桿長度 (px)
  final double currentAngle; // 旋轉角度 (deg)

  /// 本體設計: 金箍棒 (畫面正中央)
  const RuyiJinguBang({
    super.key,
    required this.currentLength,
    required this.currentAngle,
  });

  static List<StyleRule> get styles => [
    css('.ruyi-jingu-bang', [
      css('&').styles(
        display: .flex,
        position: Position.absolute(top: 50.percent, left: 50.percent),
        zIndex: ZIndex(1),
        height: 24.px,
        transition: Transition('transform', duration: Duration(milliseconds: 50), curve: Curve.linear),
        alignItems: .center,
        raw: {
          // 使用 transform 修正置中點，並帶入動態旋轉
          // and transition
          'transform-origin': 'center center',
        },
      ),
      // 中間紅色桿子
      css('& .red-stick').styles(
        width: 420.px,
        height: 18.px,
        // 圓柱體上下內陰影 + 外投影
        shadow: BoxShadow.combine([
          BoxShadow.inset(
            color: Color.rgba(255, 255, 255, 0.2),
            offsetX: 0.px,
            offsetY: 4.px,
            blur: 4.px,
          ),
          BoxShadow.inset(
            color: Color.rgba(0, 0, 0, 0.4),
            offsetX: 0.px,
            offsetY: (-4).px,
            blur: 4.px,
          ),
          BoxShadow(
            color: Color.rgba(0, 0, 0, 0.5),
            offsetX: 0.px,
            offsetY: 6.px,
            blur: 12.px,
          ),
        ]),
        flex: Flex(grow: 14, shrink: 1.2),
        backgroundColor: Color('#b81d24'),
      ),
      // 金箍的金屬光澤樣式封裝
      css('& .gold-cuff').styles(
        width: 90.px,
        height: 24.px,
        radius: .all(.circular(2.px)),
        shadow: BoxShadow.combine([
          BoxShadow.inset(
            color: Color.rgba(255, 255, 255, 0.4),
            offsetX: 0.px,
            offsetY: 3.px,
            blur: 3.px,
          ),
          BoxShadow.inset(
            color: Color.rgba(0, 0, 0, 0.3),
            offsetX: 0.px,
            offsetY: (-3).px,
            blur: 3.px,
          ),
          BoxShadow(
            color: Color.rgba(0, 0, 0, 0.4),
            offsetX: 0.px,
            offsetY: 4.px,
            blur: 8.px,
          ),
        ]),
        flex: Flex(grow: 3, shrink: 1),
        backgroundColor: Color('#f5af19'),
        raw: {
          // 多層次線性漸層模擬圓柱金屬反光
          // and shadow
          'background':
              'linear-gradient(to bottom, #b8860b 0%, #e6b800 20%, #fff7d1 40%, #ffd700 55%, #cc9900 75%, #8a6400 100%)',
        },
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'ruyi-jingu-bang',
      styles: Styles(
        width: currentLength.px,
        transform: .combine([
          .translate(x: (-50).percent, y: (-50).percent),
          .rotate(Angle.deg(currentAngle)),
        ]),
      ),
      [
        // 左端金色金箍
        div(classes: 'gold-cuff', []),
        // 中間紅色桿子 (動態長度變數驅動)
        div(classes: 'red-stick', []),
        // 右端金色金箍
        div(classes: 'gold-cuff', []),
      ],
    );
  }
}
