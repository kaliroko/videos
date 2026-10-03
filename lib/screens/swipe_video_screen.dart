/// 上下滑动视频播放器（仿抖音上下滑动）
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;                    // ★ 新增

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/video_model.dart';
import '../repository/simple_api.dart';
import '../theme/app_theme.dart';
import '../providers/nav_bar_visibility.dart';

class SwipeVideoScreen extends StatefulWidget {
  /// ★ 是否处于前台 tab；false 时暂停所有播放器
  final bool active;

  const SwipeVideoScreen({super.key, this.active = true});

  @override
  State<SwipeVideoScreen> createState() => _SwipeVideoScreenState();
}

class _SwipeVideoScreenState extends State<SwipeVideoScreen> {
  late final PageController _controller;

  final List<VideoItem> _videos = [];
  final Map<int, VideoPlayerController> _players = {};

  int _currentPage = 0;
  bool _loading = true;
  bool _fetching = false;
  String? _error;

  NavBarVisibility? _nav;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _initialLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nav = context.read<NavBarVisibility>();
    if (widget.active) _nav?.show();
  }

  @override
  void didUpdateWidget(covariant SwipeVideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ★ tab 切换：进入前台→恢复播放；进入后台→暂停全部
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        final p = _players[_currentPage];
        if (p != null && p.value.isInitialized) p.play();
      } else {
        for (final p in _players.values) {
          if (p.value.isInitialized && p.value.isPlaying) p.pause();
        }
      }
    }
  }

  @override
  void dispose() {
    _nav?.show();
    _controller.dispose();
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    await _loadNext();
    if (!mounted || _error != null) return;
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_fetching) return;
    _fetching = true;
    try {
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

      await _ensurePlayer(_videos.length - 1);
      if (_videos.length - 1 == _currentPage && widget.active) {
        _players[_currentPage]?.play();
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _ensurePlayer(int index) async {
    if (index < 0 || index >= _videos.length) return;

    if (_players.containsKey(index)) {
      final p = _players[index]!;
      if (p.value.isInitialized && index == _currentPage && widget.active) {
        p.play();
      }
      return;
    }

    final video = _videos[index];
    final player = VideoPlayerController.networkUrl(
      Uri.parse(video.url),
      httpHeaders: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13)',
        'Referer': 'https://www.kuaishou.com/',
      },
    );
    _players[index] = player;

    try {
      await player.initialize();
      await player.setLooping(true);
      if (!mounted) {
        player.dispose();
        _players.remove(index);
        return;
      }
      if (index == _currentPage && widget.active) {
        player.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[SwipeVideo] init $index failed: $e');
    }
  }

  void _onPageChanged(int index) {
    final oldPage = _currentPage;

    if (index > oldPage) {
      _nav?.hide();
    } else if (index < oldPage) {
      _nav?.show();
    }

    setState(() => _currentPage = index);

    _players.forEach((i, p) {
      if (i != index && p.value.isInitialized && p.value.isPlaying) {
        p.pause();
      }
    });

    _ensurePlayer(index);
    _ensurePlayer(index + 1);

    final toRemove =
        _players.keys.where((i) => (i - index).abs() > 2).toList();
    for (final i in toRemove) {
      _players[i]?.dispose();
      _players.remove(i);
    }

    if (index >= _videos.length - 1) {
      _loadNext();
    }
  }

  void _onTap(int index) {
    final p = _players[index];
    if (p == null || !p.value.isInitialized) return;
    if (p.value.isPlaying) {
      p.pause();
    } else {
      p.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _videos.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.accentColor),
        ),
      );
    }

    if (_error != null && _videos.isEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: Colors.white38),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadNext();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _videos.length + 1,
        itemBuilder: (context, index) {
          if (index >= _videos.length) {
            return const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: AppTheme.accentColor,
                  strokeWidth: 2,
                ),
              ),
            );
          }

          final player = _players[index];
          final ready = player != null && player.value.isInitialized;

          return GestureDetector(
            onTap: () => _onTap(index),
            child: SizedBox.expand(
              child: ready
                  ? _FitVideo(controller: player)
                  : const Center(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: Color(0xFFFB7299),
                          strokeWidth: 2,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 视频显示：原比例前景（轻微放大）+ 左右模糊填充
// - 竖屏/窄比例视频：左右黑边 → 模糊填充
// - 横屏视频：上下黑边 → 保持纯黑
// ══════════════════════════════════════════════════════════════
class _FitVideo extends StatelessWidget {
  final VideoPlayerController controller;
  const _FitVideo({required this.controller});

  /// 前景视频放大系数
  /// 1.00 = 原始大小（不裁切）
  /// 1.06 = 轻微放大（约裁 6% 边缘）
  /// 1.15 = 明显放大
  static const double _kForegroundScale = 1.06;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.width == 0 || size.height == 0) {
      return const ColoredBox(color: Colors.black);
    }

    final videoAR = size.width / size.height;

    // 前景：原比例 + 轻微放大裁边
    final Widget foreground = ClipRect(
      child: Transform.scale(
        scale: _kForegroundScale,
        child: AspectRatio(
          aspectRatio: videoAR,
          child: VideoPlayer(controller),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAR = constraints.maxWidth / constraints.maxHeight;

        // 视频比屏幕"窄" → 左右有黑边 → 用模糊填充
        // 视频比屏幕"宽/扁"（横屏）→ 上下黑边 → 保持纯黑
        final hasSideBlank = videoAR < screenAR;

        if (!hasSideBlank) {
          // 上下黑边 → 纯黑
          return ColoredBox(
            color: Colors.black,
            child: Center(child: foreground),
          );
        }

        // 左右黑边 → 模糊背景 + 放大的前景
        return Stack(
          fit: StackFit.expand,
          children: [
            // 底层：模糊铺满全屏
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 30,
                  sigmaY: 30,
                  tileMode: TileMode.clamp,
                ),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),
            // 前景：原比例（略放大）居中
            Center(child: foreground),
          ],
        );
      },
    );
  }
}