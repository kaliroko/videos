/// 首页 — 竖屏短视频 Feed 风格
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

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  bool _appBarElevated = false;

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
    final elevated = _scrollController.offset > 60;
    if (elevated != _appBarElevated) setState(() => _appBarElevated = elevated);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            children: [
              _buildAppBar(),
              Expanded(child: _buildVideoFeed()),
            ],
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _buildFab(),
      ),
    );
  }

  // ── 顶部栏 ────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: _appBarElevated ? AppTheme.backgroundColor.withOpacity(0.95) : Colors.transparent,
      child: Row(
        children: [
          // Logo
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
              Text(
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
          // 刷新按钮
          _iconBtn(Icons.refresh, () => context.read<VideoProvider>().fetchVideos()),
          const SizedBox(width: 4),
          // 设置按钮
          _iconBtn(Icons.settings, _showServerDialog),
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

  // ── 视频 Feed（对称双列网格）────────────────────────────────────────
  Widget _buildVideoFeed() {
    return Consumer<VideoProvider>(
      builder: (context, provider, child) {
        if (provider.loading && provider.videos.isEmpty) {
          return const _buildLoadingState();
        }
        if (provider.error != null && provider.videos.isEmpty) {
          return _buildErrorState(provider.error!);
        }
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,       // 两列对称
            crossAxisSpacing: 8,     // 列间距
            mainAxisSpacing: 8,      // 行间距
            childAspectRatio: 9 / 14, // 竖屏卡片比例
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

  // ── 视频播放 ─────────────────────────────────────────────────────────
  void _playVideo(BuildContext context, dynamic video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(video: video),
      ),
    );
  }

  // ── 刷新服务器地址对话框 ─────────────────────────────────────────────
  void _showServerDialog() {
    final controller = TextEditingController();
    final provider = context.read<VideoProvider>();
    controller.text = provider.serverUrl;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('服务器地址', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.100:5000',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            prefixIcon: Icon(Icons.wifi, color: AppTheme.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textTertiary)),
          ),
          FilledButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                provider.setServerUrl(url);
                provider.fetchVideos();
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // ── 加载状态 ─────────────────────────────────────────────────────────
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
            Text('连接失败', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.read<VideoProvider>().fetchVideos(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showServerDialog,
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('设置服务器地址'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 右下角浮动按钮 ───────────────────────────────────────────────────
  Widget _buildFab() {
    return GlassIconButton(
      quality: GlassQuality.standard,
      icon: Icons.sync_problem,
      size: 48,
      useOwnLayer: true,
      onPressed: () => context.read<VideoProvider>().fetchVideos(),
      glowColor: AppTheme.accentColor,
    );
  }
}
