/// 玻璃卡 —— Her Haven 视觉语言的基本单元
///
/// 对应网页里的 `.card`：
/// ```css
/// background: rgba(22,17,26,.6);
/// backdrop-filter: blur(20px);
/// border-radius: 12px; padding: 30px;
/// box-shadow: 0 20px 40px rgba(0,0,0,.6);
/// border: 1px solid rgba(255,255,255,.08);
/// ```
///
/// ★ 玻璃的关键在**顺序**：ClipRRect → BackdropFilter → 半透明容器 → 内容。
///   容器必须是半透明的，模糊后的背景才透得出来；
///   要是把颜色刷成不透明，那就只是一张深色卡片，没有玻璃感了。
///
/// ★ 模糊很贵。放在滚动列表里时把 [blur] 关掉 —— 底色本身就够暗，
///   关掉之后退化成一层次级面板，仍然站得住，但省掉每帧一次高斯模糊。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/haven.dart';
import 'spring_tap.dart';

/// 网页 blur(20px) 大致对应这个 sigma。再大就开始糊成一团且更费。
const double _kBlurSigma = 18;

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.margin,
    this.radius = HavenColors.radiusCard,
    this.blur = true,
    this.tint = false,
    this.accentLeft = false,
    this.iridescent = false,
    this.onTap,
    this.onLongPress,
    this.haptic = false,
  });

  final Widget child;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// 是否加背景模糊。长列表里关掉能省一大截合成开销。
  final bool blur;

  /// 玫瑰 → 薰衣草 的对角渐变（网页 `.hero`）
  final bool tint;

  /// 左侧玫瑰竖条（网页 `.hero` 的 `border-left: 2px solid var(--rose)`）
  final bool accentLeft;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    Widget surface = Container(
      padding: padding,
      // 无模糊时要自己裁圆角，否则子内容会从圆角里溢出来
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tint
            ? null
            : (blur ? HavenColors.glass : HavenColors.glassOpaque),
        gradient: tint ? HavenColors.tintGradient : null,
        borderRadius: borderRadius,
        border: Border.all(color: HavenColors.glassBorder),
        boxShadow: HavenColors.glassShadow(),
      ),
      child: child,
    );

    if (accentLeft) {
      // 竖条画在玻璃**外侧**，否则会被圆角切掉一半
      surface = Stack(
        children: <Widget>[
          surface,
          Positioned(
            left: 0,
            top: radius * 0.6,
            bottom: radius * 0.6,
            child: Container(width: 2, color: HavenColors.rose),
          ),
        ],
      );
    }

    Widget result = surface;

    if (blur) {
      result = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _kBlurSigma, sigmaY: _kBlurSigma),
          child: result,
        ),
      );
    }

    // 玻璃卡往往在列表里，隔一层边界省掉不必要的重绘
    result = RepaintBoundary(child: result);

    if (iridescent) {
      result = CustomPaint(
        foregroundPainter: _IridescentBorderPainter(radius: radius),
        child: result,
      );
    }

    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }

    if (onTap != null || onLongPress != null) {
      result = SpringTap(
        onTap: onTap,
        onLongPress: onLongPress,
        haptic: haptic,
        pressedScale: 0.98,
        child: result,
      );
    }

    return result;
  }
}


/// 1px 镭射描边：玫瑰 → 冷白 → 薰衣草。
///
/// 静态绘制，不随帧变化；比再加一层 BackdropFilter 便宜得多，
/// 但能让主角卡的边缘「有一道金属反光」。
class _IridescentBorderPainter extends CustomPainter {
  const _IridescentBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0x00D17997),
          Color(0x80D17997),
          Color(0x80FFFFFF),
          Color(0x808E7BB5),
          Color(0x008E7BB5),
        ],
        stops: <double>[0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IridescentBorderPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
