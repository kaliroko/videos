/// Her Haven 基础组件库 —— 网页 HTML/CSS 的 1:1 Flutter 译本
///
/// 对应关系（网页 class → 这里的 widget）：
///   .btn.primary / .btn.ghost / .btn.danger → [HavenButton]
///   .chip / .chip.on                        → [HavenChip]
///   .card / .tip / .stat                    → GlassCard / [HavenTip] / [HavenStat]
///   .field-label                            → [HavenFieldLabel]
///   textarea / input[type=date]             → [HavenTextField] / [HavenFieldTile]
///   .switch                                 → [HavenSwitch]
///   .toast                                  → [showHavenToast]
///   .float-anim（弹幕）                      → [DanmakuFloat]
///   .view 的 fadeUp 动画                     → [FadeUpIn]
///   .anime-img-container / .sync-avatar-box → [MoeImagePanel] / [MoeAvatar]
///   #globalAnimeBg + #bgOverlay             → [HavenBackground]
///
/// ★ 所有颜色/字号/字距都从 HavenColors 取，不在组件里写死 ——
///   网页和 App 的视觉参数这才是一份真值。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/haven.dart';
import '../theme/springs.dart';
import 'spring_tap.dart';

// ══════════════════════════════════════════════════════════════════════
// 背景 —— #globalAnimeBg + #bgOverlay
// ══════════════════════════════════════════════════════════════════════

/// 网页的固定背景：一张动漫图 + brightness(.65) + 底部渐变遮罩。
///
/// ★ 图是**原样打包**的 1.png（没有重新编码、没有裁切），
///   和网页 background-image: url('./1.png') 是同一份文件。
/// ★ cover + top center 也和 CSS 的 background-position: center top 一致。
class HavenBackground extends StatelessWidget {
  const HavenBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // #globalAnimeBg
        RepaintBoundary(
          child: ColorFiltered(
            // filter: brightness(0.65) —— 用 4x4 颜色矩阵等比缩 RGB
            colorFilter: const ColorFilter.matrix(<double>[
              0.65, 0, 0, 0, 0, //
              0, 0.65, 0, 0, 0, //
              0, 0, 0.65, 0, 0, //
              0, 0, 0, 1, 0, //
            ]),
            child: Image.asset(
              'assets/images/haven_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // 不设 cacheWidth：和 HavenShell 里的 precacheImage 用同一个
              // AssetImage，解码结果直接复用，首帧不黑、也不会解两次
              errorBuilder: (_, __, ___) => ColoredBox(color: HavenColors.bg),
            ),
          ),
        ),
        // #bgOverlay
        DecoratedBox(
          decoration: BoxDecoration(gradient: HavenColors.overlayGradient),
        ),
        // 细颗粒 —— 暗色大面积渐变容易有 banding，压一层 96px 的噪点
        // 就有胶片/印刷的质感。静态平铺，不参与每帧重绘。
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/grain.png'),
                repeat: ImageRepeat.repeat,
                opacity: 0.6,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 文字
// ══════════════════════════════════════════════════════════════════════

/// .view-title —— 22px 衬线标题 + 右侧小注解
class HavenSectionTitle extends StatelessWidget {
  const HavenSectionTitle({
    super.key,
    required this.title,
    this.note,
    this.padding = const EdgeInsets.only(bottom: 20),
  });

  final String title;
  final String? note;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Flexible(
            child: Text(
              title,
              style: HavenColors.viewTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                note!,
                style: HavenColors.viewTitleNote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// .eyebrow —— 11px 大写字距 2
class HavenEyebrow extends StatelessWidget {
  const HavenEyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: HavenColors.eyebrow.copyWith(color: color),
    );
  }
}

/// .field-label —— 表单标签，可选玫瑰色强调后缀（网页里的 <em>）
class HavenFieldLabel extends StatelessWidget {
  const HavenFieldLabel(this.text, {super.key, this.accent, this.bottom = 12});

  final String text;

  /// 玫瑰色小尾巴，如「注意力程度 几乎没注意」里的后半句
  final String? accent;

  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: HavenColors.sans,
            fontSize: 12.5,
            height: 1.3,
            letterSpacing: 1,
            color: HavenColors.inkFaint,
          ),
          children: <InlineSpan>[
            TextSpan(text: text),
            if (accent != null)
              TextSpan(
                text: '  ' + accent!,
                style: TextStyle(
                  color: HavenColors.rose,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 按钮 —— .btn
// ══════════════════════════════════════════════════════════════════════

enum HavenButtonType { primary, ghost, danger }

/// 网页按钮：13px / 字距 1 / 4px 圆角 / 12×24 内边距，按下是弹簧缩放。
class HavenButton extends StatelessWidget {
  const HavenButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = HavenButtonType.primary,
    this.expand = false,
    this.icon,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final HavenButtonType type;
  final bool expand;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final isPrimary = type == HavenButtonType.primary;

    Color bg = HavenColors.rose;
    Color fg = HavenColors.onRose;
    Gradient? gradient;
    Border? border;
    switch (type) {
      case HavenButtonType.primary:
        fg = HavenColors.onRose;
        // 玫瑰的轻微对角渐变 + 一道 12% 的顶光，比纯色更「有材质」
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[HavenColors.rose, HavenColors.roseDeep],
        );
        border = Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        );
        break;
      case HavenButtonType.ghost:
        bg = Colors.transparent;
        fg = HavenColors.inkStrong;
        border = Border.all(
          color: HavenColors.inkStrong.withValues(alpha: 0.2),
        );
        break;
      case HavenButtonType.danger:
        bg = Colors.transparent;
        fg = HavenColors.rose;
        border = Border.all(color: HavenColors.rose);
        break;
    }

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: HavenColors.sans,
              fontSize: 13,
              height: 1.2,
              letterSpacing: 1,
              color: fg,
            ),
          ),
        ),
      ],
    );

    Widget box = AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: gradient == null ? bg : null,
          gradient: gradient,
          border: border,
          borderRadius: BorderRadius.circular(HavenColors.radiusChip),
        ),
        child: content,
      ),
    );

    if (isPrimary) {
      box = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HavenColors.radiusChip),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: HavenColors.rose.withValues(alpha: enabled ? 0.28 : 0.0),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: box,
      );
    }

    return SpringTap(
      onTap: onPressed,
      pressedScale: 0.97,
      spring: Springs.snappy,
      haptic: isPrimary,
      child: box,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Chip —— .chip / .chip.on
// ══════════════════════════════════════════════════════════════════════

class HavenChip extends StatelessWidget {
  const HavenChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.fixed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// .chip.static —— 只展示不可点（记录卡里的小标签）
  final bool fixed;

  @override
  Widget build(BuildContext context) {
    final bg = fixed
        ? HavenColors.inkStrong.withValues(alpha: 0.03)
        : (selected ? HavenColors.roseWash : Colors.transparent);
    final borderColor = fixed
        ? Colors.transparent
        : (selected ? HavenColors.rose : HavenColors.hairline);
    final textColor = fixed
        ? HavenColors.inkFaint
        : (selected ? HavenColors.rose : HavenColors.ink);

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: fixed ? 12 : 16,
        vertical: fixed ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HavenColors.radiusChip),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: HavenColors.sans,
          fontSize: fixed ? 11.5 : 12.5,
          height: 1.2,
          letterSpacing: 0.5,
          color: textColor,
        ),
      ),
    );

    if (fixed || onTap == null) return box;
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.94,
      child: box,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 表单
// ══════════════════════════════════════════════════════════════════════

/// 网页的 textarea / input 视觉：半透明黑底 + 一道发丝描边，聚焦时描边变玫瑰。
class HavenTextField extends StatelessWidget {
  const HavenTextField({
    super.key,
    this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.textInputAction,
    this.maxLength,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController? controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      maxLength: maxLength,
      textAlign: textAlign,
      cursorColor: HavenColors.rose,
      style: TextStyle(
        fontFamily: HavenColors.sans,
        fontSize: 13.5,
        height: 1.8,
        color: HavenColors.inkStrong,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: HavenColors.glassSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
          fontFamily: HavenColors.sans,
          fontSize: 13,
          color: HavenColors.inkFaint,
        ),
        border: _border(HavenColors.hairline),
        enabledBorder: _border(HavenColors.hairline),
        focusedBorder: _border(HavenColors.rose),
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(HavenColors.radiusField),
        borderSide: BorderSide(color: color, width: 1),
      );
}

/// 只读的「日期 / 时间」栏 —— 网页是原生 input[type=date]，点了弹日历。
class HavenFieldTile extends StatelessWidget {
  const HavenFieldTile({
    super.key,
    required this.value,
    required this.onTap,
    this.icon = Icons.event_outlined,
    this.placeholder = '选择',
  });

  final String value;
  final VoidCallback onTap;
  final IconData icon;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final empty = value.isEmpty;
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: HavenColors.glassSunken,
          borderRadius: BorderRadius.circular(HavenColors.radiusField),
          border: Border.all(color: HavenColors.hairline),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: HavenColors.rose),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                empty ? placeholder : value,
                style: TextStyle(
                  fontFamily: HavenColors.sans,
                  fontSize: 13.5,
                  letterSpacing: 0.5,
                  color: empty ? HavenColors.inkFaint : HavenColors.inkStrong,
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: HavenColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// .switch —— 40×22 的方角开关，滑块 18×18
class HavenSwitch extends StatelessWidget {
  const HavenSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: SizedBox(
        width: 46,
        height: 30,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value
                  ? HavenColors.rose
                  : HavenColors.inkStrong.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// .row —— 「标题 + 说明 + 右侧控件」的一行
class HavenSettingRow extends StatelessWidget {
  const HavenSettingRow({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: HavenColors.sans,
                    fontSize: 13.5,
                    height: 1.3,
                    letterSpacing: 0.5,
                    color: HavenColors.inkStrong,
                  ),
                ),
                if (description != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    style: TextStyle(
                      fontFamily: HavenColors.sans,
                      fontSize: 12,
                      height: 1.6,
                      color: HavenColors.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 数据展示
// ══════════════════════════════════════════════════════════════════════

/// .stat —— 一格统计
class HavenStat extends StatelessWidget {
  const HavenStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      decoration: BoxDecoration(
        color: HavenColors.glass,
        borderRadius: BorderRadius.circular(HavenColors.radiusSm),
        border: Border.all(color: HavenColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: HavenColors.statNumber),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: HavenColors.sans,
              fontSize: 11,
              height: 1.4,
              letterSpacing: 1.5,
              color: HavenColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// .bar —— 2px 进度条
class HavenBar extends StatelessWidget {
  const HavenBar({super.key, required this.value, this.height = 2});

  /// 0~1
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ColoredBox(
                color: HavenColors.inkStrong.withValues(alpha: 0.05),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: ColoredBox(color: HavenColors.rose),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// .tip —— 左侧一根玫瑰竖线的提示卡
class HavenTip extends StatelessWidget {
  const HavenTip({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HavenColors.radiusCard),
        border: Border.all(color: HavenColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.only(top: 4),
            color: HavenColors.rose,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: HavenColors.sans,
                    fontSize: 13.5,
                    letterSpacing: 1,
                    color: HavenColors.inkStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Text(body, style: HavenColors.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// .mini —— 首页四宫格里的入口卡
class HavenMiniCard extends StatelessWidget {
  const HavenMiniCard({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String index;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: HavenColors.glass,
          borderRadius: BorderRadius.circular(HavenColors.radiusSm),
          border: Border.all(color: HavenColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              index,
              style: TextStyle(
                fontFamily: HavenColors.serif,
                fontSize: 11,
                letterSpacing: 1,
                color: HavenColors.rose,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: HavenColors.sans,
                fontSize: 14,
                letterSpacing: 1,
                color: HavenColors.inkStrong,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: HavenColors.sans,
                fontSize: 11.5,
                color: HavenColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// details/summary —— 科普页的折叠条目，+ 会转成 ×
class HavenExpandTile extends StatefulWidget {
  const HavenExpandTile({
    super.key,
    required this.title,
    required this.body,
    this.initiallyOpen = false,
  });

  final String title;
  final String body;
  final bool initiallyOpen;

  @override
  State<HavenExpandTile> createState() => _HavenExpandTileState();
}

class _HavenExpandTileState extends State<HavenExpandTile>
    with SingleTickerProviderStateMixin {
  late bool _open = widget.initiallyOpen;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.initiallyOpen ? 1 : 0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HavenColors.radiusSm),
        border: Border.all(color: HavenColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SpringTap(
            onTap: _toggle,
            pressedScale: 0.99,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: HavenColors.sans,
                        fontSize: 14,
                        height: 1.4,
                        letterSpacing: 1,
                        color: HavenColors.inkStrong,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      return Transform.rotate(
                        angle: _ctrl.value * math.pi / 4,
                        child: Icon(
                          Icons.add,
                          size: 18,
                          color: _ctrl.value > 0.5
                              ? HavenColors.rose
                              : HavenColors.inkFaint,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Text(widget.body, style: HavenColors.body),
                  )
                : const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 滚动数字 —— 计时器专用
// ══════════════════════════════════════════════════════════════════════

/// 逐位滚动的数字。
///
/// 计时器如果只是把 Text 换字符串，数字会「啪」地跳一下，很廉价；
/// 这里把每一位拆开，变化的那一位向上翻进来、旧的向下翻出去，
/// 没变的位保持不动 —— 只有真正变的那一秒才有动画。
///
/// ★ 用衬线体的 tabularFigures（HavenColors.timer 里已经开了），
///   每个数字等宽，滚动时整行不会左右抖。
class RollingDigits extends StatelessWidget {
  const RollingDigits({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 170),
  });

  final String text;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < text.length; i++)
          ClipRect(
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.55),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              layoutBuilder: (current, previous) {
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    ...previous,
                    if (current != null) current,
                  ],
                );
              },
              child: Text(
                text[i],
                key: ValueKey<String>(i.toString() + ':' + text[i]),
                style: style,
              ),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 进场动画 —— .view 的 fadeUp
// ══════════════════════════════════════════════════════════════════════

/// 网页每个视图切换时都会 fadeUp：淡入 + 上移 10px。
/// 这里用弹簧推同一件事 —— 落位时有一点点过冲，比补间更有质感。
class FadeUpIn extends StatefulWidget {
  const FadeUpIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<FadeUpIn> createState() => _FadeUpInState();
}

class _FadeUpInState extends State<FadeUpIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController.unbounded(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      _ctrl.animateWith(SpringSimulation(Springs.bouncy, 0, 1, 0));
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final v = _ctrl.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - v)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Toast —— .toast
// ══════════════════════════════════════════════════════════════════════

/// 底部居中的玫瑰色胶囊提示，2.2 秒后自己走。
void showHavenToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _HavenToastHost(
      message: message,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _HavenToastHost extends StatefulWidget {
  const _HavenToastHost({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_HavenToastHost> createState() => _HavenToastHostState();
}

class _HavenToastHostState extends State<_HavenToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 40 + bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            // 0~0.08 淡入上浮，0.08~0.85 停留，0.85~1 淡出
            final opacity = t < 0.08
                ? t / 0.08
                : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
            final rise = t < 0.08 ? 10 * (1 - t / 0.08) : 0.0;
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, rise), child: child),
            );
          },
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: HavenColors.rose,
                borderRadius: BorderRadius.circular(2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: HavenColors.sans,
                  fontSize: 12.5,
                  height: 1.4,
                  letterSpacing: 1,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 弹幕 —— .float-anim
// ══════════════════════════════════════════════════════════════════════

/// 从底部浮起、淡出的那句话。父级把它放进 Stack 里，播完调 onDone。
class DanmakuFloat extends StatefulWidget {
  const DanmakuFloat({
    super.key,
    required this.text,
    required this.onDone,
    this.bottom = 40,
  });

  final String text;
  final VoidCallback onDone;
  final double bottom;

  @override
  State<DanmakuFloat> createState() => _DanmakuFloatState();
}

class _DanmakuFloatState extends State<DanmakuFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottom,
          child: IgnorePointer(
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -120 * t),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: HavenColors.rose.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      widget.text,
                      style: TextStyle(
                        fontFamily: HavenColors.sans,
                        fontSize: 13,
                        letterSpacing: 1,
                        color: HavenColors.rose,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 图片 —— 网页的动漫图（远端随机图 + 本地兜底）
// ══════════════════════════════════════════════════════════════════════

/// 网页里所有小图都来自同一个接口：
///   https://t.alcy.cc/moez?t=<时间戳>
/// 每次带不同时间戳，所以「换一张」就是换 seed。
class MoeImage extends StatelessWidget {
  const MoeImage({
    super.key,
    required this.seed,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  final int seed;
  final BoxFit fit;
  final Alignment alignment;

  static String urlFor(int seed) => 'https://t.alcy.cc/moez?t=' + seed.toString();

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: urlFor(seed),
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 320),
      fadeOutDuration: const Duration(milliseconds: 160),
      placeholder: (context, url) => const _MoeShimmer(),
      errorWidget: (context, url, error) => Image.asset(
        'assets/images/moe_fallback.jpg',
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, __, ___) => ColoredBox(color: HavenColors.glassSunken),
      ),
    );
  }
}

class _MoeShimmer extends StatefulWidget {
  const _MoeShimmer();

  @override
  State<_MoeShimmer> createState() => _MoeShimmerState();
}

class _MoeShimmerState extends State<_MoeShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                HavenColors.glassSunken,
                HavenColors.rose.withValues(alpha: 0.06 + 0.10 * _ctrl.value),
                HavenColors.glassSunken,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// .anime-img-container —— 180×250 的竖版动漫图，右上角一个「换一张」。
class MoeImagePanel extends StatefulWidget {
  const MoeImagePanel({
    super.key,
    this.initialSeed,
    this.width = 180,
    this.height = 250,
    this.kenBurns = false,
    this.radius = HavenColors.radiusSm,
    this.overlay,
  });

  final int? initialSeed;
  final double width;
  final double height;

  /// 缓慢呼吸式放大 —— 欢迎页用，静态图也会显得「活着」
  final bool kenBurns;

  /// 圆角，默认 8；hero banner 用 12
  final double radius;

  /// 压在图片上的内容（标题 / 按钮）。会盖住图片，但「换一张」仍在最上层
  final Widget? overlay;

  @override
  State<MoeImagePanel> createState() => _MoeImagePanelState();
}

class _MoeImagePanelState extends State<MoeImagePanel>
    with SingleTickerProviderStateMixin {
  late int _seed = widget.initialSeed ?? DateTime.now().millisecondsSinceEpoch;
  double _opacity = 1;

  late final AnimationController _kb = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  late final Animation<double> _kbScale = Tween<double>(
    begin: 1.0,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _kb, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.kenBurns) _kb.repeat(reverse: true);
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _seed = DateTime.now().millisecondsSinceEpoch;
      _opacity = 0.35;
    });
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: HavenColors.glassBorder),
        boxShadow: HavenColors.glassShadow(lift: 1.1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _opacity,
            child: AnimatedBuilder(
              animation: _kbScale,
              builder: (context, child) {
                return Transform.scale(
                  scale: widget.kenBurns ? _kbScale.value : 1.0,
                  child: child,
                );
              },
              child: MoeImage(seed: _seed),
            ),
          ),
          if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
          Positioned(
            top: 12,
            right: 12,
            child: SpringTap(
              onTap: _refresh,
              pressedScale: 0.94,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: const Text(
                  '换一张',
                  style: TextStyle(
                    fontFamily: HavenColors.sans,
                    fontSize: 11,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// .sync-avatar-box —— 圆角方形 / 圆形的动漫头像
class MoeAvatar extends StatelessWidget {
  const MoeAvatar({
    super.key,
    required this.seed,
    this.size = 48,
    this.radius = 4,
    this.circular = false,
  });

  final int seed;
  final double size;
  final double radius;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(radius),
        border: Border.all(color: HavenColors.glassBorder),
      ),
      child: MoeImage(seed: seed),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 其它小零件
// ══════════════════════════════════════════════════════════════════════

/// 一枚用于「加载中」的呼吸圆点
class HavenPulse extends StatefulWidget {
  const HavenPulse({super.key, this.size = 10, this.color});

  final double size;
  final Color? color;

  @override
  State<HavenPulse> createState() => _HavenPulseState();
}

class _HavenPulseState extends State<HavenPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (widget.color ?? HavenColors.rose).withValues(
              alpha: 0.4 + 0.6 * _ctrl.value,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: (widget.color ?? HavenColors.rose)
                    .withValues(alpha: 0.25 * _ctrl.value),
                blurRadius: 12,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 长按复制 —— 记录卡、昵称上都能挂
class HavenCopyable extends StatelessWidget {
  const HavenCopyable({super.key, required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        unawaited(_copy(context));
      },
      child: child,
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showHavenToast(context, '已复制');
  }
}
