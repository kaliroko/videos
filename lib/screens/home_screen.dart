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
  int _bottomTab = 0;
  final ScrollController _scrollController = ScrollController();

  /// ★ 触发底栏显隐的滑动阈值（像素）。
  /// 设小 → 灵敏；设大 → 需要更长的滑动距离。
  static const double _kNavTriggerDelta = 0.5;

  /// 靠近顶部多少像素内强制显示底栏
  static const double _kTopZone = 8.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSwipeMode = _bottomTab == 1;
    final nav = context.watch<NavBarVisibility>();
    final topInset = MediaQuery.of(context).padding.top;

    return LiquidGlassScope.stack(
      background: Container(
        color: isSwipeMode ? Colors.black : AppTheme.surfaceColor,
      ),
      content: Scaffold(
        backgroundColor: isSwipeMode ? Colors.black : Colors.transparent,
        body: Column(
          children: [
            if (!isSwipeMode) _buildAppBar(topInset: topInset),
            Expanded(
              child: isSwipeMode
                  ? const SwipeVideoScreen()
                  : _buildVideoFeed(),
            ),
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
        floatingActionButton: _buildFab(),
      ),
    );
  }

  // ── 顶部栏（手动加状态栏高度 padding）───────────────────────────────────
  Widget _buildAppBar({required double topInset}) {
    return Padding(
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
              color: _bottomTab == 1
                  ? AppTheme.accentColor.withValues(alpha: 0.2)
                  : AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _bottomTab == 1 ? 'kuleu.com' : 'Flask',
              style: TextStyle(
                color: _bottomTab == 1
                    ? AppTheme.accentColor
                    : AppTheme.primaryColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh, _refresh),
        ],
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

  // ── 主体内容（老 API 网格）───────────────────────────────────────────────
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
            // ① 触底自动加载下一页（保留原逻辑）
            if (notification is ScrollEndNotification &&
                provider.hasMore &&
                !provider.loading) {
              final maxScroll = _scrollController.position.maxScrollExtent;
              if (maxScroll > 0 &&
                  _scrollController.offset >= maxScroll * 0.85) {
                provider.fetchVideos();
              }
            }

            // ② ★ 底栏显隐：高灵敏度（阈值 0.5px）
            if (notification is ScrollUpdateNotification) {
              final offset = _scrollController.offset;
              final delta = notification.scrollDelta ?? 0;
              final nav = context.read<NavBarVisibility>();

              if (offset <= _kTopZone) {
                // 顶部附近 → 强制显示
                nav.show();
              } else if (delta > _kNavTriggerDelta) {
                // 手指往上滑（看下面内容）→ 隐藏底栏
                nav.hide();
              } else if (delta < -_kNavTriggerDelta) {
                // 手指往下滑（看上面内容）→ 显示底栏
                nav.show();
              }
            } else if (notification is ScrollEndNotification) {
              // 滑动停止时，若已在顶部附近 → 强制显示
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
              return VideoCard(
                video: provider.videos[index],
                onTap: () => _playVideo(context, provider.videos[index]),
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

  // ── 底部导航（液态玻璃）──────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: GlassBottomBar(
        selectedIndex: _bottomTab,
        onTabSelected: (i) {
          setState(() => _bottomTab = i);
          // 切换 tab 时恢复底栏可见
          context.read<NavBarVisibility>().show();
          final source = i == 0 ? VideoSource.oldApi : VideoSource.newApi;
          context.read<VideoProvider>().setSource(source);
        },
        tabs: [
          GlassBottomBarTab(
            label: '老API',
            icon: Icons.cloud,
            selectedIcon: Icons.cloud_outlined,
            glowColor: AppTheme.primaryColor,
          ),
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
        glassSettings: const LiquidGlassSettings(
          thickness:         30,
          blur:              6,
          refractiveIndex:   1.59,
          saturation:        0.7,
          lightIntensity:    0.6,
          chromaticAberration: 0.3,
          ambientStrength:   1.0,
          lightAngle:        0.785,
          glassColor:        Color(0x3DFFFFFF),
        ),
      ),
    );
  }

  // ── FAB（液态玻璃）─────────────────────────────────────────────────────────
  Widget _buildFab() {
    return GlassIconButton(
      quality:       GlassQuality.standard,
      icon:          Icons.refresh,
      size:          46,
      useOwnLayer:   true,
      onPressed:     _refresh,
      glowColor:     AppTheme.accentColor,
    );
  }

  void _refresh() => context.read<VideoProvider>().fetchVideos();

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