/// TikTok 风格全屏上下滑动视频流 — 仅用于新API（kuleu.com）
/// 惰性加载：初始显示 1 条，滑到末尾时再请求下一条
/// 使用 MD3 真实物理弹簧动画：惯性滑动 + 弹跳归位
library;

import 'dart:math' show pow;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/repository/simple_api.dart';
import 'package:bilibili_glass/theme/app_theme.dart';

/// 抖音式 MD3 物理弹簧翻页
/// 继承 PageScrollPhysics，调高弹簧刚度与衰减，加入真实阻尼回弹
class TiktokPageScrollPhysics extends PageScrollPhysics {
  const TiktokPageScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  TiktokPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return TiktokPageScrollPhysics(parent: buildParent(ancestor));
  }

  // 更快的弹簧衰减 → 类似抖音那种"嗖"一下到位的感觉
  @override
  double get springDecay => -pow(0.001, 1.0 / (TiktokPageScrollPhysics._springsPerSecond * 2));

  // 更高的刚度 → 页面 snap 更果断
  @override
  double get springStiffness => 600.0;

  // 减小小球模拟阻尼 → 滚动惯性更强
  @override
  double get decayRate => 0.005;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final bearing = _getBearing(position, velocity);
    // 快速减速模拟（比默认 2500 dp/s² 更灵敏）
    const deceleration = 3500.0;
    // 速度阈值：低于此值触发 snap
    if (abs(velocity) > 0.001) {
      final double stoppingDistance = _speedAtDeceleration(abs(velocity), deceleration);
      if (stoppingDistance.abs() > position.dimensions * 0.25) {
        // 超出四分之一屏，强制 snap 到目标页
        final int targetPage = _pageAfter(position.pixels + bearing * stoppingDistance, position.viewportDimension);
        final double targetPixels = _pixelsAfterSnap(targetPage, position);
        return TweenAnimationSimulation(
          SpringSimulation(
            SpringDescription.withDampingRatio(
              mass: 1.0,
              stiffness: springStiffness,
              ratio: 0.9, // 接近临界阻尼，快速归位无过冲
            ),
            position.pixels,
            targetPixels,
            0.0,
          ),
          deceleration,
          bearing,
        );
      }
    }
    // 默认 PageSnap（低速滑）
    return super.createBallisticSimulation(position, velocity);
  }

  /// 根据速度和位置计算方向（+1 向下，-1 向上）
  double _getBearing(ScrollMetrics position, double velocity) {
    if (position.pixels == 0.0 && velocity < 0.0) return -1.0;
    if (position.maxScrollExtent == position.pixels && velocity > 0.0) return 1.0;
    return -velocity.sign;
  }

  /// 计算以给定减速度完全停止所需的距离
  double _speedAtDeceleration(double speed, double rate) {
    return sqrt(speed * speed / (2.0 * rate));
  }

  /// 计算 snap 后的目标像素位置
  double _pixelsAfterSnap(int page, ScrollMetrics position) {
    return page * position.viewportDimension + position.viewportDimension / 2.0 - position.extentAfter;
  }

  /// 判断滑动后应该进入哪一页
  int _pageAfter(double afterPixels, double viewportDimension) {
    if (afterPixels >= 0.0) {
      return (afterPixels / viewportDimension).ceil();
    } else {
      return (afterPixels / viewportDimension).floor();
    }
  }

  static const double _springsPerSecond = 6.0;
}

class TiktokFeedScreen extends StatefulWidget {
  const TiktokFeedScreen({super.key});

  @override
  State<TiktokFeedScreen> createState() => _TiktokFeedScreenState();
}

class _TiktokFeedScreenState extends State<TiktokFeedScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  int _currentPage = 0;

  final List<VideoItem> _videos = [];
  bool _loading = true;
  String? _error;

  // 播放器状态
  final List<VideoPlayerController?> _controllers = [];
  final List<ChewieController?> _chewieControllers = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: 0,
      viewportFraction: 1.0,
    );
    _fetchNext();
  }

  // ── 数据加载 ────────────────────────────────────────────────────────────
  Future<void> _fetchNext() async {
    final video = await SimpleApiRepository.fetchOne();
    if (!mounted) return;
    if (video == null) {
      setState(() {
        _loading = false;
        _error = _videos.isEmpty ? '加载失败，请重试' : null;
      });
      return;
    }
    setState(() {
      _videos.add(video);
      _loading = false;
    });
  }

  // ── 播放器 ────────────────────────────────────────────────────────────
  Future<void> _initVideoAt(int index) async {
    if (index < 0 || index >= _videos.length) return;
    if (_controllers[index] != null) return;

    final video = _videos[index];
    final controller = VideoPlayerController.networkUrl(Uri.parse(video.url));
    _controllers[index] = controller;

    try {
      await controller.initialize();
      if (!mounted) return;

      _chewieControllers[index] = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: true,
        aspectRatio: controller.value.aspectRatio,
        placeholder: Container(color: Colors.black),
        showControls: false,
      );
    } catch (e) {
      debugPrint('[TiktokFeed] init video $index failed: $e');
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _pauseAllExcept(index);
    _initVideoAt(index);
    _playCurrent();

    // 滑到末尾时预加载下一条
    if (index >= _videos.length - 1 && !_loading) {
      _fetchNext();
    }
  }

  void _pauseAllExcept(int keepIndex) {
    for (int i = 0; i < _chewieControllers.length; i++) {
      final c = _chewieControllers[i];
      if (i != keepIndex && c != null) {
        c.pause();
      }
    }
  }

  void _playCurrent() {
    final chewie = _chewieControllers[_currentPage];
    if (chewie != null && chewie.videoPlayerController.value.isInitialized) {
      chewie.play();
    }
  }

  void _onVideoTap(int index) {
    final chewie = _chewieControllers[index];
    if (chewie == null) return;
    if (chewie.isPlaying) {
      chewie.pause();
    } else {
      chewie.play();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _controllers) c?.dispose();
    for (final c in _chewieControllers) c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 加载中
    if (_loading && _videos.isEmpty) {
      return _loadingView();
    }

    // 初始加载失败且无视频
    if (_error != null && _videos.isEmpty) {
      return _errorView(_error!);
    }

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const TiktokPageScrollPhysics(),
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                return _TiktokVideoCard(
                  video: _videos[index],
                  chewieController: _chewieControllers[index],
                  onTap: () => _onVideoTap(index),
                );
              },
            ),
            // 加载中指示器（滑到末尾触发时显示）
            if (_loading && _currentPage >= _videos.length - 1)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loadingView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accentColor),
            SizedBox(height: 16),
            Text('加载中…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _errorView(String msg) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: AppTheme.textTertiary),
            const SizedBox(height: 16),
            Text(msg, style: const TextStyle(color: AppTheme.textTertiary)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _fetchNext();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 单个抖音视频卡片 ──────────────────────────────────────────────────────────
class _TiktokVideoCard extends StatelessWidget {
  final VideoItem video;
  final ChewieController? chewieController;
  final VoidCallback onTap;

  const _TiktokVideoCard({
    required this.video,
    required this.chewieController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频播放器或封面占位
          chewieController != null &&
                  chewieController.videoPlayerController.value.isInitialized
              ? Chewie(controller: chewieController!)
              : _buildPlaceholder(),

          // 顶部导航栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'kuleu.com',
                        style: TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 右侧操作按钮
          Positioned(
            right: 10,
            bottom: 120,
            child: Column(
              children: [
                _actionButton(Icons.favorite_border, '点赞'),
                const SizedBox(height: 20),
                _actionButton(Icons.comment, '评论'),
                const SizedBox(height: 20),
                _actionButton(Icons.share, '分享'),
              ],
            ),
          ),

          // 底部信息
          Positioned(
            left: 12,
            right: 70,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (video.author.isNotEmpty)
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            AppTheme.accentColor.withValues(alpha: 0.3),
                        child: Text(
                          video.author[0].toUpperCase(),
                          style: const TextStyle(
                              color: AppTheme.accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        video.author,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  video.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (video.coverUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: video.coverUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => _emptyPlaceholder(),
            errorWidget: (_, __, ___) => _emptyPlaceholder(),
          )
        else
          _emptyPlaceholder(),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            ),
            child: const Icon(Icons.play_arrow,
                color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _emptyPlaceholder() {
    return Container(
      color: AppTheme.surfaceColor,
      child: const Center(
        child:
            Icon(Icons.movie, color: AppTheme.textTertiary, size: 48),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }
}
