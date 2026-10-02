/// 首页 — 液态玻璃主题 + 统一深灰色 MD3 背景
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/widgets/video_card.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/screens/video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _bottomTab = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScope.stack(
      background: Container(color: AppTheme.surfaceColor),
      content: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [_buildAppBar(), Expanded(child: _buildVideoFeed())],
          ),
        ),
        extendBody: true,
        bottomNavigationBar: _buildBottomNav(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _buildFab(),
      ),
    );
  }

  // ── 顶部栏 ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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

  // ── 视频网格 ──────────────────────────────────────────────────────────────
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
              if (maxScroll > 0 && _scrollController.offset >= maxScroll * 0.85) {
                provider.fetchVideos();
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassBottomBar(
        selectedIndex: _bottomTab,
        onTabSelected: (i) {
          setState(() => _bottomTab = i);
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
