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

    return LiquidGlassScope.stack(
      background: Container(color: AppTheme.surfaceColor),
      content: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        // ★ 直接用 GlassAppBar 作为 Scaffold.appBar
        appBar: _buildAppBar(),
        // ★ 用 extendBodyBehindAppBar 让 body 顶到 AppBar 下面
        extendBodyBehindAppBar: true,
        body: Padding(
          // 顶部留出 AppBar 高度（44 + 状态栏）
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 56,
          ),
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            physics: const PageScrollPhysics(),
            children: [
              // ── Page 0: 老API（网格）──
              _buildVideoFeed(),

              // ── Page 1: 新API（全屏视频）──
              SwipeVideoScreen(active: _bottomTab == 1),
            ],
          ),
        ),
        extendBody: true,
        bottomNavigationBar: AnimatedSlide(
          offset: nav.visible ? Offset.zero : const Offset(0, 1.3),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: _buildBottomNav(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _bottomTab == 0 ? _buildFab() : null,
      ),
    );
  }

  // ── 翻页回调 ─────────────────────────────────────────────────────────────
  void _onPageChanged(int i) {
    setState(() => _bottomTab = i);
    context.read<NavBarVisibility>().show();

    if (i == 0) {
      context.read<VideoProvider>().setSource(VideoSource.oldApi);
    }
  }

  // ── 顶部栏 ★ 用官方 GlassAppBar ───────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return GlassAppBar(
      // ★ 独立玻璃层（不依赖外部 LiquidGlassLayer）
      useOwnLayer: true,
      // 透明底（玻璃由组件自己渲染）
      backgroundColor: Colors.transparent,
      // 高度 56（比默认 44 稍大，配合内容）
      preferredSize: const Size.fromHeight(56),
      // 左对齐
      centerTitle: false,
      // ★ 与底栏同款的液态玻璃参数
      settings: const LiquidGlassSettings(
        thickness:           30,
        blur:                12,
        refractiveIndex:     1.59,
        saturation:          0.7,
        lightIntensity:      0.6,
        chromaticAberration: 0.3,
        ambientStrength:     1.0,
        lightAngle:          0.785,
        glassColor:          Color(0x3DFFFFFF),
      ),
      // 整栏内容放在 title 里
      title: Row(
        children: [
          // Logo + 名字
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.movie,
              color: Colors.black,
              size: 18,
            ),
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
          const Spacer(),
          // Flask 标签
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
          // 刷新按钮
          _iconBtn(Icons.refresh, _refresh),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
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

  // ── 底部导航 ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: GlassBottomBar(
          selectedIndex: _bottomTab,
          onTabSelected: (i) {
            _pageController.animateToPage(
              i,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          },
          tabs: [
            GlassBottomBarTab(
              label: 'JK纯欲',
              icon: Icons.cloud,
              selectedIcon: Icons.cloud_outlined,
              glowColor: AppTheme.primaryColor,
            ),
            GlassBottomBarTab(
              label: '白丝宝宝',
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
            thickness:           26,
            blur:                6,
            refractiveIndex:     1.55,
            saturation:          0.7,
            lightIntensity:      0.55,
            chromaticAberration: 0.05,
            ambientStrength:     0.9,
            lightAngle:          0.785,
            glassColor:          Color(0x3DFFFFFF),
          ),
        ),
      ),
    );
  }

  // ── FAB ─────────────────────────────────────────────────────────────────
  Widget _buildFab() {
    return GlassIconButton(
      quality:     GlassQuality.standard,
      icon:        Icons.refresh,
      size:        46,
      useOwnLayer: false,
      onPressed:   _refresh,
      glowColor:   AppTheme.accentColor,
    );
  }

  void _refresh() {
    if (_bottomTab == 0) {
      context.read<VideoProvider>().fetchVideos();
    } else {
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