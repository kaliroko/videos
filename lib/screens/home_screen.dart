/// 首页 — B站风格布局
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/widgets/video_card.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/utils/format_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final List<String> _tabs = const ['推荐', '动态', '热门', '游戏', '音乐', '知识', '动漫'];
  int _selectedTab = 0;
  final ScrollController _scrollController = ScrollController();
  bool _showTopBarTransparent = true;

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    context.read<VideoProvider>().fetchVideos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final showing = _scrollController.offset < 120;
    if (showing != _showTopBarTransparent) {
      setState(() => _showTopBarTransparent = showing);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AdaptiveLiquidGlassLayer(
      settings: const LiquidGlassSettings(
        blur: 40.0,
        thickness: 20.0,
        lightIntensity: 1.5,
        lightAngle: 135.0,
        refractiveIndex: 1.2,
      ),
      quality: GlassQuality.standard,
      blendAmount: 8.0,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 顶部搜索栏（透明→磨砂渐变）
                SliverToBoxAdapter(
                  child: _buildAppBar(),
                ),
                // 分类 Tab 栏
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    tabs: _tabs,
                    selectedIndex: _selectedTab,
                    onSelect: (i) => setState(() => _selectedTab = i),
                  ),
                ),
                // 视频列表
                SliverPadding(
                  padding: const EdgeInsets.only(top: 4),
                  sliver: _buildVideoList(),
                ),
              ],
            ),
            // 直播角标提示（静态模拟）
            if (_showTopBarTransparent)
              Positioned(
                bottom: 16,
                right: 16,
                child: _buildLiveFab(),
              ),
          ],
        ),
        bottomNavigationBar: const GlassBottomNav(),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          // 左侧 Logo
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.movie, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 6),
              Text(
                '玻璃哔哩',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 18,
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
                color: AppTheme.surfaceColor.withOpacity(0.8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.textTertiary.withOpacity(0.2)),
              ),
              child: const TextField(
                readOnly: true,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索视频、UP主...',
                  hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textTertiary),
                  suffixIcon: Icon(Icons.mic, size: 18, color: AppTheme.textSecondary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 直播按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.liveColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.liveColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.liveColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('直播', style: TextStyle(color: AppTheme.liveColor, fontSize: 12)),
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
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
          );
        }
        if (provider.error != null) {
          return SliverToBoxAdapter(
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppTheme.textTertiary),
                  const SizedBox(height: 12),
                  Text('加载失败: ${provider.error}', style: const TextStyle(color: AppTheme.textTertiary)),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: () => provider.fetchVideos(), child: const Text('重试')),
                ],
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return VideoCard(video: provider.videos[index]);
            },
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
          BoxShadow(color: AppTheme.liveColor.withOpacity(0.4), blurRadius: 12, spreadRadius: 2),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text('直播', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Tab 栏持久化头部
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  _TabBarDelegate({required this.tabs, required this.selectedIndex, required this.onSelect});

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
                tabs[i],
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
        itemCount: tabs.length,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabs != oldDelegate.tabs || selectedIndex != oldDelegate.selectedIndex;
}

/// 底部导航栏 — GlassBottomBar
class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GlassBottomBar(
          quality: GlassQuality.standard,
          glassSettings: null,
          tabs: [
            GlassBottomBarTab(
              label: '首页',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              glowColor: AppTheme.accentColor,
            ),
            GlassBottomBarTab(
              label: '番剧',
              icon: Icons.movie_outlined,
              selectedIcon: Icons.movie,
              glowColor: AppTheme.primaryColor,
            ),
            GlassBottomBarTab(
              label: '直播',
              icon: Icons.live_tv_outlined,
              selectedIcon: Icons.live_tv,
              glowColor: AppTheme.liveColor,
            ),
            GlassBottomBarTab(
              label: '频道',
              icon: Icons.grid_view_outlined,
              selectedIcon: Icons.grid_view,
              glowColor: AppTheme.warningColor,
            ),
            GlassBottomBarTab(
              label: '我的',
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              glowColor: Colors.purple,
            ),
          ],
          selectedIndex: 0,
          onTabSelected: (i) {},
        ),
      ),
    );
  }
}
