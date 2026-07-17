import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

class ControlPanel extends StatelessComponent {
  // 控制面板位置
  final double controlPanelHeight;
  final double distanceFromBottom;

  // 動態操作狀態
  final double currentLength; // 紅桿長度 (px)
  final double currentAngle; // 旋轉角度 (deg)

  // 安全角度邊界
  final double minAngle;
  final double maxAngle;

  final ValueChanged<double> onLengthChanged;
  final ValueChanged<double> onAngleChanged;

  /// UI 介面: 磨砂玻璃極簡控制面板
  const ControlPanel({
    super.key,
    required this.controlPanelHeight,
    required this.distanceFromBottom,
    required this.currentLength,
    required this.currentAngle,
    required this.minAngle,
    required this.maxAngle,
    required this.onLengthChanged,
    required this.onAngleChanged,
  });

  @override
  Component build(BuildContext context) {
    return .fragment([
      RawText('<!-- 這怎麼會好維護呢 -->'),
      div(
        styles: Styles(
          display: .flex,
          position: Position.absolute(bottom: distanceFromBottom.px, left: 50.percent),
          zIndex: ZIndex(2),
          width: 80.percent,
          height: controlPanelHeight.px,
          maxWidth: 390.px,
          padding: .symmetric(horizontal: 20.px),
          boxSizing: .borderBox,
          border: Border.all(
            style: .solid,
            color: Color.rgba(255, 255, 255, 0.1),
            width: 1.px,
          ),
          radius: .circular(16.px),
          shadow: BoxShadow.combine([
            BoxShadow(
              color: Color.rgba(0, 0, 0, 0.37),
              offsetX: 0.px,
              offsetY: 8.px,
              blur: 32.px,
            ),
          ]),
          backdropFilter: .blur(20.px),
          transform: .translate(x: (-50).percent), // 水平精緻置中
          flexDirection: .column,
          justifyContent: JustifyContent.center,
          backgroundColor: Color.rgba(255, 255, 255, 0.06),
        ),
        [
          // 長度控制拉桿
          _buildSliderRow(
            "長度",
            currentLength,
            192.0,
            1920.0,
            onLengthChanged,
          ),
          // 角度控制拉桿
          _buildSliderRow(
            "角度",
            currentAngle,
            minAngle,
            maxAngle,
            onAngleChanged,
          ),
        ],
      ),
    ]);
  }

  // 控制面板內的極簡拉桿組件
  Component _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return div(
      styles: Styles(
        display: .flex,
        width: 100.percent,
        height: 32.px,
        justifyContent: JustifyContent.spaceBetween,
        alignItems: AlignItems.center,
      ),
      [
        span(
          styles: Styles(
            width: 40.px,
            color: Color('#e0e0e0'),
            fontSize: 13.px,
          ),
          [.text(label)],
        ),
        input(
          type: InputType.range,
          attributes: {
            'min': min.toString(),
            'max': max.toString(),
            'step': '0.5',
          },
          value: value.toString(),
          // events: events(
          //   onInput: (num? value) {
          //     // onChanged(double.parse(value ?? '0'));
          //     onChanged(value?.toDouble() ?? .0);
          //   },
          // ),
          events: {
            'input': (evt) {
              final input = evt.currentTarget as web.HTMLInputElement;
              onChanged(double.tryParse(input.value) ?? .0);
            },
          },
          styles: Styles(
            height: 4.px,
            margin: .symmetric(vertical: 0.px, horizontal: 12.px),
            flex: .basis(1.px),
            raw: {
              // 拉桿主色調採用金箍色
              'accent-color': '#f5af19',
            },
          ),
        ),
        span(
          styles: Styles.combine([
            Styles(
              color: Color('#a0a0a0'),
              fontSize: 11.px,
            ),
            Styles(
              width: 45.px,
              textAlign: TextAlign.right,
            ),
          ]),
          [
            .text(
              "${value.toStringAsFixed(0)}${label == '角度' ? '°' : 'px'}",
            ),
          ],
        ),
      ],
    );
  }
}
