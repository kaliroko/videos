/// 首页 — 双 Tab 底部导航（旧API / 新API），液态玻璃主题
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/widgets/video_card.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/screens/video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.movie, color: Colors.black, size: 16),
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
              color: _bottomTab == 0
                  ? AppTheme.primaryColor.withValues(alpha: 0.2)
                  : AppTheme.accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _bottomTab == 0 ? 'AES-CBC' : 'kuleu.com',
              style: TextStyle(
                color: _bottomTab == 0
                    ? AppTheme.primaryColor
                    : AppTheme.accentColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh, () => context.read<VideoProvider>().fetchVideos()),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: AppTheme.textSecondary),
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
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:    2,
            crossAxisSpacing:  8,
            mainAxisSpacing:   8,
            childAspectRatio:  9 / 14,
          ),
          itemCount: provider.videos.length,
          itemBuilder: (context, index) {
            final video = provider.videos[index];
            return VideoCard(
              video: video,
              onTap: () => _playVideo(context, video),
            );
          },
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

  // ── 底部双 Tab（液态玻璃）────────────────────────────────────────────────
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
            label: '旧API',
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
      quality:   GlassQuality.standard,
      icon:      Icons.refresh,
      size:      46,
      useOwnLayer: true,
      onPressed: () => context.read<VideoProvider>().fetchVideos(),
      glowColor: AppTheme.accentColor,
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.accentColor),
          SizedBox(height: 16),
          Text('正在加载视频...', style: TextStyle(color: AppTheme.textTertiary)),
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
              onPressed: () => context.read<VideoProvider>().fetchVideos(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}