/// 首页 — B站风格布局 + 悬浮液态玻璃底部导航
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/widgets/video_card.dart';
import 'package:bilibili_glass/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final List<String> _tabs = const [
    '推荐', '动态', '热门', '游戏', '音乐', '知识', '动漫'
  ];
  int _selectedTab = 0;
  int _navIndex = 0;
  final List<String> _navLabels = const ['首页', '番剧', '直播', '频道', '我的'];
  final List<IconData> _navIconsOut = const [
    Icons.home_outlined, Icons.movie_outlined, Icons.live_tv_outlined,
    Icons.grid_view_outlined, Icons.person_outline,
  ];
  final List<IconData> _navIconsIn = const [
    Icons.home, Icons.movie, Icons.live_tv, Icons.grid_view, Icons.person,
  ];
  final List<Color> _navGlows = const [
    AppTheme.accentColor, AppTheme.primaryColor, AppTheme.liveColor,
    AppTheme.warningColor, Colors.purple,
  ];

  // 各页独立 StatefulWidget，切换时重建；当前页 keepAlive=true
  final List<Widget> _pages = const [
    _HomeTabPage(),
    _PlaceholderPage(label: '番剧'),
    _PlaceholderPage(label: '直播'),
    _PlaceholderPage(label: '频道'),
    _PlaceholderPage(label: '我的'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    context.read<VideoProvider>().fetchVideos();
  }

  void _onNavTap(int index) {
    setState(() {
      _navIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // LiquidGlassScope.stack 提供背景供 GlassBottomBar 折射使用
    return LiquidGlassScope.stack(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0a0a1a), Color(0xFF16213e), Color(0xFF0f3460)],
          ),
        ),
      ),
      content: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: IndexedStack(
          index: _navIndex,
          children: _pages,
        ),
        extendBodyBehindAppBar: true,
        // 悬浮液态玻璃底部导航
        bottomNavigationBar: _buildGlassBottomBar(),
      ),
    );
  }

  Widget _buildGlassBottomBar() {
    final GlobalKey bgKey = LiquidGlassScope.of(context) ?? GlobalKey();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: GlassBottomBar(
          quality: GlassQuality.standard,
          // blendAmount 控制玻璃叠加平滑度（Impeller 有效，Skia 忽略）
          blendAmount: 8.0,
          maskingQuality: MaskingQuality.high,
          barHeight: 60,
          iconSize: 24,
          backgroundKey: bgKey,
          tabs: List.generate(_navLabels.length, (i) {
            return GlassBottomBarTab(
              label: _navLabels[i],
              icon: _navIconsOut[i],
              selectedIcon: _navIconsIn[i],
              glowColor: _navGlows[i],
            );
          }),
          selectedIndex: _navIndex,
          onTabSelected: _onNavTap,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 首页内容页（保持 alive，避免每次返回都重新请求 API）
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTabPage extends StatefulWidget {
  const _HomeTabPage();

  @override
  State<_HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<_HomeTabPage>
    with AutomaticKeepAliveClientMixin {
  final List<String> _categories = const [
    '推荐', '动态', '热门', '游戏', '音乐', '知识', '动漫'
  ];
  int _selectedCat = 0;
  final ScrollController _scrollController = ScrollController();
  bool _transparent = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final showing = _scrollController.offset < 100;
    if (showing != _transparent) setState(() => _transparent = showing);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 顶部搜索栏
            SliverToBoxAdapter(
              child: _buildAppBar(),
            ),
            // 分类 Tab（固定）
            SliverPersistentHeader(
              pinned: true,
              delegate: _CategoryBarDelegate(
                categories: _categories,
                selectedIndex: _selectedCat,
                onSelect: (i) => setState(() => _selectedCat = i),
              ),
            ),
            // 视频列表
            SliverPadding(
              padding: const EdgeInsets.only(top: 4),
              sliver: _buildVideoList(),
            ),
          ],
        ),
        // 直播 FAB
        if (_transparent)
          Positioned(
            bottom: 88,
            right: 16,
            child: _buildLiveFab(),
          ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.movie, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 6),
              Text(
                '玻璃哔哩',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // 搜索框
          Expanded(
            flex: 3,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor.withOpacity(0.85),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: AppTheme.textTertiary.withOpacity(0.15)),
              ),
              child: const TextField(
                readOnly: true,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索视频、UP主...',
                  hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                  prefixIcon:
                      Icon(Icons.search, size: 18, color: AppTheme.textTertiary),
                  suffixIcon:
                      Icon(Icons.mic, size: 18, color: AppTheme.textSecondary),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 直播按钮
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.liveColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppTheme.liveColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.liveColor, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('直播',
                    style: TextStyle(color: AppTheme.liveColor, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    return Consumer<VideoProvider>(
      builder: (context, provider, child) {
        if (provider.loading && provider.videos.isEmpty) {
          return const SliverFillRemaining(
            child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor)),
          );
        }
        if (provider.error != null) {
          return SliverToBoxAdapter(
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppTheme.textTertiary),
                  const SizedBox(height: 12),
                  Text('加载失败: ${provider.error}',
                      style: const TextStyle(color: AppTheme.textTertiary)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: () => provider.fetchVideos(),
                      child: const Text('重试')),
                ],
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => VideoCard(video: provider.videos[index]),
            childCount: provider.videos.length,
          ),
        );
      },
    );
  }

  Widget _buildLiveFab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.liveColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: AppTheme.liveColor.withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text('直播',
              style:
                  TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 分类 Tab 持久化头部
class _CategoryBarDelegate extends SliverPersistentHeaderDelegate {
  final List<String> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  _CategoryBarDelegate({
    required this.categories,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: 44,
      color: AppTheme.backgroundColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (ctx, i) {
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text(
                categories[i],
                style: TextStyle(
                  color: selected ? AppTheme.accentColor : AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w400,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemCount: categories.length,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CategoryBarDelegate old) =>
      categories != old.categories || selectedIndex != old.selectedIndex;
}

/// 占位页面（番剧/直播/频道/我的）
class _PlaceholderPage extends StatelessWidget {
  final String label;
  const _PlaceholderPage({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers, size: 64, color: AppTheme.textTertiary),
          const SizedBox(height: 16),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 18)),
          const SizedBox(height: 8),
          Text('敬请期待',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }
}