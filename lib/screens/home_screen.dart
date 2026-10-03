/// 首页 — 液态玻璃主题 + 统一深灰色 MD3 背景
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/providers/nav_bar_visibility.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/widgets/video_card.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/screens/video_player_screen.dart';
import 'package:bilibili_glass/screens/swipe_video_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  /// ★ 0 = 老API（网格）；1 = 新API（视频）
  int _bottomTab = 0;

  final PageController _pageController = PageController(initialPage: 0);
  final ScrollController _scrollController = ScrollController();

  static const double _kNavTriggerDelta = 0.5;
  static const double _kTopZone = 8.0;

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavBarVisibility>();
    final topInset = MediaQuery.of(context).padding.top;

    return LiquidGlassScope.stack(
      // 网格模式背景为深灰；视频页自己会盖一层黑色
      background: Container(color: AppTheme.surfaceColor),
      content: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        // ★ 水平 PageView —— 左右滑切换两个 tab
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          physics: const PageScrollPhysics(),
          children: [
            // ── Page 0: 老API（网格 + 顶部栏）──
            Column(
              children: [
                _buildAppBar(topInset: topInset),
                Expanded(child: _buildVideoFeed()),
              ],
            ),

            // ── Page 1: 新API（全屏视频）──
            SwipeVideoScreen(active: _bottomTab == 1),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: AnimatedSlide(
          offset: nav.visible ? Offset.zero : const Offset(0, 1.3),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: _buildBottomNav(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        // ★ FAB 只在老API页显示（视频页不需要刷新按钮）
        floatingActionButton: _bottomTab == 0 ? _buildFab() : null,
      ),
    );
  }

  // ── 翻页回调 ─────────────────────────────────────────────────────────────
  void _onPageChanged(int i) {
    setState(() => _bottomTab = i);
    context.read<NavBarVisibility>().show();

    // ★ 索引 0 = 老API → 需要 Provider 参与
    if (i == 0) {
      context.read<VideoProvider>().setSource(VideoSource.oldApi);
    }
  }

  // ── 顶部栏 ★ 优化 4：加 RepaintBoundary ─────────────────────────────────
  Widget _buildAppBar({required double topInset}) {
    return RepaintBoundary(   // ★ 优化 4
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, topInset + 10, 14, 8),
        child: Row(
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.movie, color: Colors.black, size: 18),
                ),
                const SizedBox(width: 6),
                const Text(
                  '玻璃哔哩',
                  style: TextStyle(
                    color: AppTheme.accentColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Flask',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _iconBtn(Icons.refresh, _refresh),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 17, color: AppTheme.textSecondary),
      ),
    );
  }

  // ── 老API 网格 ───────────────────────────────────────────────────────────
  Widget _buildVideoFeed() {
    return Consumer<VideoProvider>(
      builder: (context, provider, child) {
        if (provider.loading && provider.videos.isEmpty) {
          return _buildLoadingState();
        }
        if (provider.error != null && provider.videos.isEmpty) {
          return _buildErrorState(provider.error!);
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                provider.hasMore &&
                !provider.loading) {
              final maxScroll = _scrollController.position.maxScrollExtent;
              if (maxScroll > 0 &&
                  _scrollController.offset >= maxScroll * 0.85) {
                provider.fetchVideos();
              }
            }

            if (notification is ScrollUpdateNotification) {
              final offset = _scrollController.offset;
              final delta = notification.scrollDelta ?? 0;
              final nav = context.read<NavBarVisibility>();

              if (offset <= _kTopZone) {
                nav.show();
              } else if (delta > _kNavTriggerDelta) {
                nav.hide();
              } else if (delta < -_kNavTriggerDelta) {
                nav.show();
              }
            } else if (notification is ScrollEndNotification) {
              if (_scrollController.offset <= _kTopZone) {
                context.read<NavBarVisibility>().show();
              }
            }

            return false;
          },
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 9 / 14,
            ),
            itemCount: provider.videos.length + (provider.loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= provider.videos.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              // ★ 优化 3：每个卡片独立 RepaintBoundary
              //   滚动时一个卡片变化不影响其它卡片
              return RepaintBoundary(
                child: VideoCard(
                  video: provider.videos[index],
                  onTap: () => _playVideo(context, provider.videos[index]),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _playVideo(BuildContext context, VideoItem video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: video)),
    );
  }

  // ── 底部导航 ★ 优化 4：加 RepaintBoundary + 玻璃参数减负 ────────────────
  Widget _buildBottomNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RepaintBoundary(   // ★ 优化 4
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: GlassBottomBar(
          selectedIndex: _bottomTab,
          onTabSelected: (i) {
            // ★ 点 tab → 动画翻页；_onPageChanged 会同步状态
            _pageController.animateToPage(
              i,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          },
          tabs: [
            // ★ 第一个：老API（默认）
            GlassBottomBarTab(
              label: '老API',
              icon: Icons.cloud,
              selectedIcon: Icons.cloud_outlined,
              glowColor: AppTheme.primaryColor,
            ),
            // ★ 第二个：新API
            GlassBottomBarTab(
              label: '新API',
              icon: Icons.auto_awesome,
              selectedIcon: Icons.auto_awesome_outlined,
              glowColor: AppTheme.accentColor,
            ),
          ],
          barHeight: 60,
          iconSize: 24,
          selectedIconColor: AppTheme.accentColor,
          unselectedIconColor: AppTheme.textTertiary,
          // ★ 性能减负：保留折射（thickness / refractiveIndex），
          //   只削减性能大头（blur / chromaticAberration）
          glassSettings: const LiquidGlassSettings(
            thickness:           26,     // 30 → 26（保留玻璃厚度感）
            blur:                3,      // 6 → 3（★ 性能大头）
            refractiveIndex:     1.55,   // 1.59 → 1.55（★ 保留折射）
            saturation:          0.7,
            lightIntensity:      0.55,
            chromaticAberration: 0.05,   // 0.3 → 0.05（★ 性能大头）
            ambientStrength:     0.9,
            lightAngle:          0.785,
            glassColor:          Color(0x3DFFFFFF),
          ),
        ),
      ),
    );
  }

  // ── FAB（液态玻璃，性能减负）───────────────────────────────────────────
  Widget _buildFab() {
    return GlassIconButton(
      quality:       GlassQuality.minimal,   // ★ standard → minimal
      icon:          Icons.refresh,
      size:          46,
      useOwnLayer:   false,                  // ★ true → false
      onPressed:     _refresh,
      glowColor:     AppTheme.accentColor,
    );
  }

  void _refresh() {
    if (_bottomTab == 0) {
      // 老API → Provider 重新拉
      context.read<VideoProvider>().fetchVideos();
    } else {
      // 新API → 强制重建 SwipeVideoScreen（跳走再跳回）
      _pageController.jumpToPage(0);
      _pageController.jumpToPage(1);
    }
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.accentColor),
          SizedBox(height: 16),
          Text('正在加载…', style: TextStyle(color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: AppTheme.textTertiary),
            const SizedBox(height: 16),
            const Text('连接失败',
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error,
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}