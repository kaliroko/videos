/// 首页 —— 网页 hero + quick-panel + grid4 + tip 的 1:1 还原
///
/// 网页结构（.hero / .quick-panel / .grid4 / .tip）在手机上就是一条竖排列表，
/// 宽度断点和网页的 @media (max-width:760px) 一致：窄屏时 hero 竖排、图片在上。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/haven.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/haven_widgets.dart';
import '../../widgets/spring_tap.dart';
import '../chat_screen.dart';

class HavenHomeView extends StatefulWidget {
  const HavenHomeView({super.key, required this.onGo});

  /// 跳到对应模块（下标和 HavenShell 的 tab 顺序一致）
  final ValueChanged<int> onGo;

  @override
  State<HavenHomeView> createState() => _HavenHomeViewState();
}

class _HavenHomeViewState extends State<HavenHomeView> {
  // ── 首页的独立计时器 ────────────────────────────────────────────────
  Timer? _ticker;
  int _seconds = 0;
  bool _running = false;

  // ── 同频卡片上的两张动漫头像 ────────────────────────────────────────
  int _seedA = DateTime.now().millisecondsSinceEpoch;
  late int _seedB = _seedA + 17;

  static const List<String> _moeNames = <String>['月亮船', 'Sappho', '薄荷', '晚风'];

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _timerText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return m + ':' + s;
  }

  void _toggleTimer() {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    // 重新开始还是继续：有秒数就继续，没秒数就从头
    setState(() => _running = true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  void _stopTimer() {
    _ticker?.cancel();
    setState(() => _running = false);
    showHavenToast(
      context,
      _seconds == 0 ? '还没开始计时' : '这一段 ' + _timerText + '，记下来了吗',
    );
  }

  void _shuffleResonance() {
    setState(() {
      _seedA = DateTime.now().millisecondsSinceEpoch;
      _seedB = _seedA + 17;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 6, 20, 40 + bottom),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: <Widget>[
        FadeUpIn(child: _buildHero(narrow)),
        const SizedBox(height: 16),
        FadeUpIn(
          delay: const Duration(milliseconds: 60),
          child: _buildChatCard(),
        ),
        const SizedBox(height: 16),
        FadeUpIn(delay: const Duration(milliseconds: 110), child: _buildQuick(narrow)),
        const SizedBox(height: 16),
        FadeUpIn(delay: const Duration(milliseconds: 170), child: _buildGrid()),
        const SizedBox(height: 24),
        FadeUpIn(
          delay: const Duration(milliseconds: 220),
          child: HavenTip(
            title: 'SAPPHIC WISDOM',
            body: '女孩，请把自己的感受放在第一位。任何让你感到疼痛、异常出血或持续不适的情况，'
                '都不是「忍一忍就好」。欲望也一样：先问一句想不想，再伸手；'
                '任何时候都可以停下来。',
          ),
        ),
        const SizedBox(height: 34),
        Text(
          'HER HAVEN · SAPPHIC EXCLUSIVE SPACE\nDESIGNED FOR WOMEN WHO LOVE WOMEN',
          textAlign: TextAlign.center,
          style: HavenColors.footnote,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── 聊天室入口 ───────────────────────────────────────────────────

  Future<void> _openChatRoom() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
    );
  }

  Widget _buildChatCard() {
    return RepaintBoundary(
      child: SpringTap(
        onTap: _openChatRoom,
        pressedScale: 0.98,
        child: Container(
          padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HavenColors.glass,
          borderRadius: BorderRadius.circular(HavenColors.radiusCard),
          border: Border.all(color: HavenColors.glassBorder),
          boxShadow: HavenColors.glassShadow(lift: 0.8),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HavenColors.roseWash,
                borderRadius: BorderRadius.circular(HavenColors.radiusSm),
                border: Border.all(color: HavenColors.roseEdge),
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 20,
                color: HavenColors.rose,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          '聊天室 / CHAT ROOM',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HavenColors.cardTitle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 静态小圆点：常驻的脉冲动画会一直排帧，滚动时白耗
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HavenColors.rose,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: HavenColors.rose.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '真实的公共房间 · 图片、表情、回复、撤回',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: HavenColors.small,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: HavenColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── hero ─────────────────────────────────────────────────────────

  Widget _buildHero(bool narrow) {
    final text = Column(
      crossAxisAlignment:
          narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        HavenEyebrow('Welcome to the Sapphic Haven'),
        const SizedBox(height: 12),
        Text(
          '只有全然的接纳与共振',
          textAlign: narrow ? TextAlign.center : TextAlign.start,
          style: HavenColors.heroTitle,
        ),
        const SizedBox(height: 12),
        Text(
          '这里没有男性的凝视，也没有世俗的评判。记录你的情绪、探索身体的愉悦、'
          '寻找同频的姐妹。想要什么、想被怎样对待，都可以写下来 —— '
          '身体的感受不需要理由，也不需要向谁解释。',
          textAlign: narrow ? TextAlign.center : TextAlign.start,
          style: HavenColors.body,
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
          children: <Widget>[
            HavenButton(
              label: '写下私语',
              onPressed: () => widget.onGo(1),
            ),
            HavenButton(
              label: '调整呼吸',
              type: HavenButtonType.ghost,
              onPressed: () => widget.onGo(6),
            ),
          ],
        ),
      ],
    );

    const panel = MoeImagePanel(width: 152, height: 206);

    return GlassCard(
      tint: true,
      accentLeft: true,
      iridescent: true,
      padding: const EdgeInsets.all(22),
      child: narrow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MoeImagePanel(width: 152, height: 206),
                const SizedBox(height: 22),
                text,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: text),
                const SizedBox(width: 24),
                panel,
              ],
            ),
    );
  }

  // ── quick panel ──────────────────────────────────────────────────

  Widget _buildQuick(bool narrow) {
    final timerCard = GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '计时 / IMMERSIVE TIMER',
            style: TextStyle(
              fontFamily: HavenColors.serif,
              fontSize: 15,
              height: 1.4,
              letterSpacing: 1,
              color: HavenColors.inkStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text('专注当下，感受自己的节奏', style: HavenColors.small),
          const SizedBox(height: 10),
          Center(
            child: RollingDigits(
              text: _timerText,
              style: HavenColors.timer(size: 40),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: HavenButton(
                  label: _running ? '暂停' : (_seconds == 0 ? '开始' : '继续'),
                  onPressed: _toggleTimer,
                  height: 42,
                ),
              ),
              if (_seconds > 0) ...<Widget>[
                const SizedBox(width: 10),
                Expanded(
                  child: HavenButton(
                    label: '结束',
                    type: HavenButtonType.danger,
                    onPressed: _running ? _stopTimer : null,
                    height: 42,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final resonanceCard = GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '同频 / RESONANCE',
            style: TextStyle(
              fontFamily: HavenColors.serif,
              fontSize: 15,
              height: 1.4,
              letterSpacing: 1,
              color: HavenColors.inkStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text('找懂你的姐妹，也可以一起共振', style: HavenColors.small),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SpringTap(
                onTap: _shuffleResonance,
                pressedScale: 0.95,
                child: MoeAvatar(seed: _seedA, size: 46),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'LINK',
                  style: TextStyle(
                    fontFamily: HavenColors.sans,
                    fontSize: 11,
                    letterSpacing: 2,
                    color: HavenColors.inkFaint,
                  ),
                ),
              ),
              MoeAvatar(seed: _seedB, size: 46),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _moeNames[_seedA % _moeNames.length] + ' 正在附近',
            textAlign: TextAlign.center,
            style: HavenColors.small,
          ),
          const SizedBox(height: 12),
          HavenButton(
            label: '进入空间',
            type: HavenButtonType.ghost,
            expand: true,
            height: 42,
            onPressed: () => widget.onGo(4),
          ),
        ],
      ),
    );

    // 网页 @media (max-width:760px) 会把 .quick-panel 从两列收成一列，
    // 手机上照做 —— 两列时「计时」卡片只剩 110dp，按钮文字会被挤成省略号。
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          timerCard,
          const SizedBox(height: 12),
          resonanceCard,
        ],
      );
    }

    // 桌面宽度仍是等高两列；Row 在滚动区里高度无界，
    // 用 IntrinsicHeight 让两张卡先量出较高的那张，再一起拉齐。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: timerCard),
          const SizedBox(width: 20),
          Expanded(child: resonanceCard),
        ],
      ),
    );
  }

  // ── grid4 ────────────────────────────────────────────────────────

  Widget _buildGrid() {
    final items = <Widget>[
      HavenMiniCard(
        index: '01',
        title: '私语日记',
        subtitle: '情绪与感受记录',
        onTap: () => widget.onGo(1),
      ),
      HavenMiniCard(
        index: '02',
        title: '自慰时刻',
        subtitle: '私密欢愉 · 详细记录',
        onTap: () => widget.onGo(2),
      ),
      HavenMiniCard(
        index: '03',
        title: '健康知识',
        subtitle: '女性自爱与保护',
        onTap: () => widget.onGo(5),
      ),
      HavenMiniCard(
        index: '04',
        title: '影像时刻',
        subtitle: '上下滑动的私藏',
        onTap: () => widget.onGo(3),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: items,
    );
  }
}
