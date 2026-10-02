/// 首页 — 统一深灰色 MD3 深色主题
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/repository/api_gateway.dart';
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
  int _activeCatIndex = 0;
  final ScrollController _scrollController = ScrollController();
  List<Category> _categories = ApiService.categories;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiService.fetchCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {
      if (mounted) setState(() => _categories = ApiService.categories);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 统一深灰 MD3 表面色，不再用渐变
      backgroundColor: AppTheme.surfaceColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            if (_bottomTab == 1) _buildCategoryBar(),
            Expanded(child: _buildVideoFeed()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildFab(),
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
          // API 来源徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _bottomTab == 1
                  ? AppTheme.accentColor.withValues(alpha: 0.2)
                  : AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _bottomTab == 1 ? 'JWT CMS' : 'Flask',
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

  // ── 分类栏 ────────────────────────────────────────────────────────────────
  Widget _buildCategoryBar() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final active = _activeCatIndex == i;
          return Padding(
            padding: const EdgeInsets.only(right: 5),
            child: GestureDetector(
              onTap: () {
                setState(() => _activeCatIndex = i);
                context.read<VideoProvider>().selectCategory(cat);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppTheme.accentColor : AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  cat.name,
                  style: TextStyle(
                    color: active ? Colors.black : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
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
                provider.loadMore();
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

  // ── 底部导航（Material 标准版）────────────────────────────────────────────
  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _bottomTab,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      labelBehavior: NavigationBarLabelBehavior.alwaysHide,
      indicatorColor: AppTheme.surfaceColor.withValues(alpha: 0.12),
      onDestinationSelected: (i) {
        setState(() => _bottomTab = i);
        if (i == 0) {
          context.read<VideoProvider>().setSource(VideoSource.oldApi);
        } else {
          context.read<VideoProvider>().setSource(VideoSource.newApi);
          setState(() => _activeCatIndex = 0);
        }
      },
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.cloud, color: AppTheme.textTertiary),
          selectedIcon: Icon(Icons.cloud_outlined, color: AppTheme.primaryColor),
          label: '老API',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome, color: AppTheme.textTertiary),
          selectedIcon: Icon(Icons.auto_awesome_outlined, color: AppTheme.accentColor),
          label: '新API',
        ),
      ],
    );
  }

  // ── FAB ───────────────────────────────────────────────────────────────────
  Widget _buildFab() {
    return Container(
      margin: const EdgeInsets.only(bottom: 72, right: 16),
      decoration: BoxDecoration(
        color: AppTheme.accentColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.refresh, color: Colors.black),
        onPressed: _refresh,
      ),
    );
  }

  void _refresh() => context.read<VideoProvider>().fetchVideos(refresh: true);

  void _playVideo(BuildContext context, MovieBean video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: video)),
    );
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
