/// 物理弹窗卡片 —— 从底部弹出来的纸片用这一套弹簧物理。
///
/// 目前评论面板在用。发布面板（`diary_compose_sheet.dart`）里还留着一份
/// 更早写死的同款物理，行为一致但没并过来 —— 想收拾的话照这里的用法替换即可。
///
/// 交互：
///   • 入场用欠阻尼弹簧，会轻轻过冲一下再落定
///   • 顶部把手跟手拖拽，向上拖带 0.25 倍阻尼（拉不太动），向下拖 1:1
///   • 松手按速度判定：甩得够快或者拖得够远就顺势飞走，否则弹回原位
///   • 拖拽时卡片带一点 3D 透视倾斜，松手回正
///   • 键盘弹出时卡片整体上移，且高度按剩余空间算，不会被顶出屏幕
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/diary_palette.dart';

/// 弹出物理弹窗。返回的 Future 在弹窗关闭时完成。
Future<void> showSpringSheet(
  BuildContext context, {
  required Widget scroller,
  Widget? header,
  Widget? footer,
  double maxHeightFactor = 0.9,
  bool barrierDismissible = true,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'sheet',
    // 遮罩自己画，才能跟着弹簧一起渐显
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, animation, secondaryAnimation) => SpringSheet(
      scroller: scroller,
      header: header,
      footer: footer,
      maxHeightFactor: maxHeightFactor,
      barrierDismissible: barrierDismissible,
    ),
  );
}

class SpringSheet extends StatefulWidget {
  const SpringSheet({
    super.key,
    required this.scroller,
    this.header,
    this.footer,
    this.maxHeightFactor = 0.9,
    this.barrierDismissible = true,
  });

  /// 中间可滚动的主体。用 SingleChildScrollView 或 ListView 都行
  final Widget scroller;

  /// 固定在顶部、不参与滚动（标题行）
  final Widget? header;

  /// 固定在底部、不参与滚动（比如输入栏、发布按钮）
  final Widget? footer;

  final double maxHeightFactor;

  /// 点遮罩能不能关掉
  final bool barrierDismissible;

  @override
  State<SpringSheet> createState() => _SpringSheetState();
}

class _SpringSheetState extends State<SpringSheet>
    with TickerProviderStateMixin {
  /// 入场：欠阻尼，落到 1 之前会过冲一点
  static const SpringDescription _springIn =
      SpringDescription(mass: 1, stiffness: 400, damping: 26);

  /// 出场：接近临界阻尼，不回头
  static const SpringDescription _springOut =
      SpringDescription(mass: 1, stiffness: 420, damping: 41);

  static const double _kRise = 430;
  static const double _kDismissDistance = 140;
  static const double _kDismissVelocity = 620;

  late final AnimationController _enter;
  late final AnimationController _drag;

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController.unbounded(vsync: this, value: 0);
    _drag = AnimationController.unbounded(vsync: this, value: 0);
    _enter.animateWith(SpringSimulation(_springIn, 0, 1, 0));
  }

  @override
  void dispose() {
    _enter.dispose();
    _drag.dispose();
    super.dispose();
  }

  // ── 手势 ──────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    final next = _drag.value + details.delta.dy;
    _drag.value = next < 0 ? next * 0.25 : next;
  }

  void _onDragEnd(DragEndDetails details) {
    if (_closing) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity > _kDismissVelocity || _drag.value > _kDismissDistance) {
      dismiss();
      return;
    }
    _drag.animateWith(SpringSimulation(_springIn, _drag.value, 0, velocity));
  }

  /// 外部也能主动关（比如发布成功后）
  Future<void> dismiss() async {
    if (_closing) return;
    setState(() => _closing = true);

    _drag.animateWith(SpringSimulation(_springOut, _drag.value, 900, 0));
    await _enter.animateWith(
      SpringSimulation(_springOut, _enter.value, -0.4, 0),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // ★ 扣掉键盘高度，否则弹出输入法后卡片会顶出屏幕
    final available = media.size.height - media.viewInsets.bottom;
    final base = available > 240 ? available : media.size.height;
    final maxHeight = base * widget.maxHeightFactor;

    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) => AnimatedBuilder(
        animation: _drag,
        builder: (context, innerChild) {
          final raw = _enter.value;
          final visible = raw.clamp(0.0, 1.0).toDouble();
          final dy = (1 - raw) * _kRise + _drag.value;
          final tilt = (_drag.value / _kRise).clamp(0.0, 1.0).toDouble() * 0.12;

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.barrierDismissible && !_closing ? dismiss : null,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.66 * visible),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateX(tilt),
                      child: Opacity(
                        opacity: visible,
                        child: Transform.scale(
                          scale: 0.94 + 0.06 * visible,
                          alignment: Alignment.bottomCenter,
                          child: innerChild,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: child,
      ),
      child: _buildCard(maxHeight),
    );
  }

  Widget _buildCard(double maxHeight) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: DiaryPalette.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SpringSheetScope(
          dismiss: dismiss,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(),
              if (widget.header != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: widget.header!,
                ),
              Flexible(child: widget.scroller),
              if (widget.footer != null) widget.footer!,
            ],
          ),
        ),
      ),
    );
  }

  /// 拖拽把手 —— 只有这块能拖，免得和内部滚动打架
  Widget _buildHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: SizedBox(
        height: 30,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 42,
            height: 4.5,
            decoration: BoxDecoration(
              color: DiaryPalette.paperEdge,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 弹窗里常用的小零件
// ══════════════════════════════════════════════════════════════════════

/// 把「带弹簧的关闭」透给弹窗内容，
/// 这样点关闭按钮也是滑下去，而不是硬 pop 掉。
class SpringSheetScope extends InheritedWidget {
  const SpringSheetScope({
    super.key,
    required this.dismiss,
    required super.child,
  });

  final Future<void> Function() dismiss;

  static Future<void> Function()? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SpringSheetScope>()
          ?.dismiss;

  @override
  bool updateShouldNotify(SpringSheetScope oldWidget) => false;
}

/// 弹窗标题行：印章 + 标题 + 关闭按钮
class SpringSheetHeader extends StatelessWidget {
  const SpringSheetHeader({
    super.key,
    required this.title,
    this.onClose,
    this.sealText = '念',
    this.titleStyle,
    this.trailing,
  });

  final String title;

  /// 不传就用带弹簧的关闭
  final VoidCallback? onClose;

  final String sealText;

  /// 默认毛笔体。毛笔体是裁剪过的子集，
  /// 如果标题里有子集外的字（比如「评论」的 评/论），就改用圆体（完整字库）。
  final TextStyle? titleStyle;

  final Widget? trailing;

  void _close(BuildContext context) {
    final dismiss = SpringSheetScope.maybeOf(context);
    if (dismiss != null) {
      dismiss();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkSealLite(text: sealText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle ??
                TextStyle(
                  fontFamily: DiaryPalette.brush,
                  fontSize: 25,
                  height: 1.2,
                  color: DiaryPalette.onPaper,
                ),
          ),
        ),
        if (trailing != null) trailing!,
        IconButton(
          onPressed: onClose ?? () => _close(context),
          icon: const Icon(Icons.close_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: DiaryPalette.paperDim,
            foregroundColor: DiaryPalette.onPaperSoft,
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// 小号朱砂印章（标题行专用，避免和 InkSeal 的交互耦合）
class InkSealLite extends StatelessWidget {
  const InkSealLite({super.key, required this.text, this.size = 32});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.055,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DiaryPalette.vermilion,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: size * 0.5,
            height: 1.0,
            color: DiaryPalette.onVermilion,
          ),
        ),
      ),
    );
  }
}
