/// Her Haven 主壳 —— 网页顶栏 + 标签页的 1:1 移动端译本
///
/// 网页结构：
///   .topbar → .brand（Her Haven / SAPPHIC · 专属空间）+ .tabs（横向可滚动的文字标签）
///   main    → 若干 .view，同一时刻只有一个 active
///
/// 这一版把「视图切换」换成了 MD3 的 fade-through：
///   旧页 30% 时长淡出 → 新页在剩下 70% 里淡入并上移 8px，
///   不再做整页透明度下压，也不会横滑 —— 暗色下这样更稳、更贵。
///
/// 滚动联动：
///   往下滚 72px 之内，品牌字会被慢慢折起来（高度 + 透明度一起收），
///   标签栏留在原地不动；底部一条 1px 的玫瑰线跟着当前页的滚动进度走。
///   这些状态走 ValueNotifier，只重绘头部，不会连累整页。
library;

import 'package:flutter/material.dart';

import '../../theme/haven.dart';
import '../../widgets/haven_widgets.dart';
import '../swipe_video_screen.dart';
import 'haven_breathe.dart';
import 'haven_diary.dart';
import 'haven_home.dart';
import 'haven_learn.dart';
import 'haven_moment.dart';
import 'haven_sync.dart';

/// 标签顺序 —— 网页的 6 个模块 + App 原有的「影像」视频流
const List<String> kHavenTabs = <String>[
  '首页',
  '私语',
  '身体时刻',
  '影像',
  '同频',
  '健康科普',
  '呼吸放松',
];

/// 视频页不参与「滚动折头」——它本身是整页手势区，折叠会打架
const int _kVideoTab = 3;

class HavenShell extends StatefulWidget {
  const HavenShell({super.key});

  @override
  State<HavenShell> createState() => _HavenShellState();
}

class _HavenShellState extends State<HavenShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: kHavenTabs.length, vsync: this);

  int _index = 0;

  /// 0 = 顶部展开，1 = 品牌完全折起
  final ValueNotifier<double> _collapse = ValueNotifier<double>(0);

  /// 当前页的滚动进度 0~1，喂给底部那根玫瑰线
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _collapse.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_index == _tab.index) return;
    setState(() => _index = _tab.index);
    _collapse.value = 0;
    _progress.value = 0;
  }

  void _goTo(int i) {
    if (i < 0 || i >= kHavenTabs.length) return;
    _tab.animateTo(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 只处理竖向滚动；横向（标签栏自己的滚动）忽略。
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (_index == _kVideoTab) return false;

    // 量化到 1/24 档：折叠视觉上仍然连续，但头部不会每帧都重建
    final raw = (n.metrics.pixels / 72).clamp(0.0, 1.0);
    final t = (raw * 24).roundToDouble() / 24;
    if ((_collapse.value - t).abs() > 0.001) _collapse.value = t;

    final max = n.metrics.maxScrollExtent;
    final p = max > 8 ? (n.metrics.pixels / max).clamp(0.0, 1.0) : 0.0;
    if ((_progress.value - p).abs() > 0.003) _progress.value = p;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return HavenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 网页 .shell 是 max-width: 960 + 左右 20 的 padding，
        // 平板/折叠屏上别把玻璃卡拉成一条 —— 这里限制到 920。
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: <Widget>[
                ValueListenableBuilder<double>(
                  valueListenable: _collapse,
                  builder: (context, t, _) => _buildHeader(top, t),
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: _FadeThroughBody(
                      index: _index,
                      children: <Widget>[
                        HavenHomeView(onGo: _goTo),
                        const HavenDiaryView(),
                        const HavenMomentView(),
                        // ★ active 控制视频的播放 / 暂停：切走就停，别在后台烧电
                        SwipeVideoScreen(active: _index == _kVideoTab),
                        const HavenSyncView(),
                        const HavenLearnView(),
                        const HavenBreatheView(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double top, double t) {
    final dim = t.clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        // 折起来之后给头部垫一层底色，滚动时文字不会和背景图糊在一起
        color: HavenColors.bg.withValues(alpha: 0.82 * dim),
      ),
      padding: EdgeInsets.fromLTRB(20, top + 10, 20, 0),
      child: Column(
        children: <Widget>[
          ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: (1 - dim).clamp(0.0, 1.0),
              child: Opacity(
                opacity: (1 - dim).clamp(0.0, 1.0),
                child: _buildBrand(),
              ),
            ),
          ),
          SizedBox(height: 14 * (1 - dim)),
          _buildTabs(),
          _buildProgressLine(),
        ],
      ),
    );
  }

  Widget _buildBrand() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Her Haven', style: HavenColors.brand),
              const SizedBox(height: 4),
              Text('SAPPHIC · 专属空间', style: HavenColors.brandSub),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '18+',
            style: TextStyle(
              fontFamily: HavenColors.sans,
              fontSize: 11,
              letterSpacing: 1,
              color: HavenColors.inkFaint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 42,
      child: TabBar(
        controller: _tab,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: HavenColors.rose, width: 1),
          insets: EdgeInsets.zero,
        ),
        labelColor: HavenColors.rose,
        unselectedLabelColor: HavenColors.inkFaint,
        labelStyle: TextStyle(
          fontFamily: HavenColors.sans,
          fontSize: 13.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: HavenColors.sans,
          fontSize: 13.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w400,
        ),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStatePropertyAll<Color>(
          HavenColors.rose.withValues(alpha: 0.04),
        ),
        tabs: <Widget>[
          for (final label in kHavenTabs)
            Tab(height: 40, text: label),
        ],
      ),
    );
  }

  /// 发丝线 + 滚动进度。进度线只重绘这一根 1px，不动页面。
  Widget _buildProgressLine() {
    return SizedBox(
      height: 1,
      child: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, p, _) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: ColoredBox(color: HavenColors.hairline),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: p.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: ColoredBox(
                      color: HavenColors.rose.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// MD3 fade-through 视图容器
// ══════════════════════════════════════════════════════════════════════

/// 七个模块同时活在一个 Stack 里，但只画当前页。
///
/// ★ 为什么不用 TabBarView：
///   它只会横向滑，而且会和「整页淡入」叠在一起，暗色下容易闪。
///   fade-through 是 Material 对「同一层级的内容切换」给出的标准转场。
/// ★ 为什么不是 IndexedStack：
///   IndexedStack 没有转场，而且一上来就把七页全建出来（视频会立刻开始拉流）。
///   这里用 visited 集合，只有去过的页才建。
class _FadeThroughBody extends StatefulWidget {
  const _FadeThroughBody({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeThroughBody> createState() => _FadeThroughBodyState();
}

class _FadeThroughBodyState extends State<_FadeThroughBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  final Set<int> _visited = <int>{};
  int _current = 0;
  int _previous = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.index;
    _visited.add(_current);
  }

  @override
  void didUpdateWidget(covariant _FadeThroughBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _previous = _current;
      _current = widget.index;
      _visited.add(_current);
      _ctrl.forward(from: 0);
    }
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
      builder: (context, _) {
        final t = _ctrl.value;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            for (int i = 0; i < widget.children.length; i++) _page(i, t),
          ],
        );
      },
    );
  }

  Widget _page(int i, double t) {
    if (!_visited.contains(i)) return const SizedBox.shrink();

    final incoming = i == _current;
    final outgoing = i == _previous && i != _current;

    // MD3 fade-through：旧页在前 30% 退场，新页在剩下的 70% 进场
    final outT = (t / 0.3).clamp(0.0, 1.0);
    final inT = ((t - 0.3) / 0.7).clamp(0.0, 1.0);

    final opacity = incoming
        ? Curves.easeOutCubic.transform(inT)
        : (outgoing ? 1 - Curves.easeInCubic.transform(outT) : 0.0);
    final dy = incoming ? (1 - inT) * 8 : 0.0;

    return IgnorePointer(
      ignoring: !incoming,
      child: ExcludeSemantics(
        excluding: !incoming,
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: TickerMode(
              enabled: incoming,
              child: widget.children[i],
            ),
          ),
        ),
      ),
    );
  }
}
