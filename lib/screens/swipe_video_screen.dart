/// 上下滑动视频播放器（仿抖音上下滑动）
/// - 当前视频秒开
/// - 后台预加载后 4 个视频
/// - 不抢带宽，不限流
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/video_model.dart';
import '../repository/simple_api.dart';
import '../theme/app_theme.dart';
import '../providers/nav_bar_visibility.dart';

class SwipeVideoScreen extends StatefulWidget {
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

  // ══════════════════════════════════════════════════════════
  // 配置
  // ══════════════════════════════════════════════════════════

  /// URL 缓存数量（当前页 + 后 4 个 + 前 2 = 至少 7 条）
  static const int _kUrlBuffer = 6;

  /// 播放器保留范围（前后各 N 个）
  static const int _kPlayerKeepRange = 4;

  /// 预加载后面几个播放器
  static const int _kPreloadAheadCount = 4;

  /// 懒加载 URL 的间隔（防限流）
  static const Duration _kFetchInterval = Duration(milliseconds: 1200);

  /// 预加载启动延迟（等当前视频先稳）
  static const Duration _kPreloadStartDelay = Duration(seconds: 2);

  /// 每次预初始化之间间隔
  static const Duration _kPreloadGap = Duration(milliseconds: 500);

  // ── 运行时状态 ──────────────────────────────────────────────
  bool _fetchingNext = false;

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

  // ── 首屏：立即拉第 1 条 ────────────────────────────────────────────
  Future<void> _initialLoad() async {
    await _loadNext();           // 第 1 条：立即初始化播放器
    if (!mounted || _error != null) return;

    // 后台补齐 URL 到 (currentPage + _kUrlBuffer) 条
    unawaited(_ensureUrlBuffer());
  }

  // ── 确保 URL 缓存足够 ─────────────────────────────────────────────
  Future<void> _ensureUrlBuffer() async {
    if (_fetchingNext) return;
    _fetchingNext = true;
    try {
      while (mounted &&
          _videos.length < _currentPage + _kUrlBuffer &&
          _error == null) {
        final before = _videos.length;
        await _loadNext();
        if (!mounted) break;

        if (_videos.length == before) {
          // 拉失败 → 退避重试
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        // 每条之间休息（防限流）
        await Future.delayed(_kFetchInterval);
      }
    } finally {
      _fetchingNext = false;
    }
  }

  // ── 加载下一条视频 ────────────────────────────────────────────────
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

      final newIndex = _videos.length - 1;

      // ★ 只初始化「当前页」的播放器
      if (newIndex == _currentPage) {
        unawaited(_ensurePlayer(newIndex));
      }
    } finally {
      _fetching = false;
    }
  }

  // ── 确保某页播放器已初始化 ────────────────────────────────────────
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

  // ── 翻页回调 ──────────────────────────────────────────────────────
  void _onPageChanged(int index) {
    final oldPage = _currentPage;

    if (index > oldPage) {
      _nav?.hide();
    } else if (index < oldPage) {
      _nav?.show();
    }

    setState(() => _currentPage = index);

    // 暂停所有非当前页
    _players.forEach((i, p) {
      if (i != index && p.value.isInitialized && p.value.isPlaying) {
        p.pause();
      }
    });

    // ★ 立即初始化当前页（秒开）
    unawaited(_ensurePlayer(index));

    // ★ 后台预初始化后 4 个（串行，不抢带宽）
    unawaited(_preloadNextFour(index));

    // 释放距离太远的播放器（保留 ±4）
    final toRemove = _players.keys
        .where((i) => (i - index).abs() > _kPlayerKeepRange)
        .toList();
    for (final i in toRemove) {
      _players[i]?.dispose();
      _players.remove(i);
    }

    // 确保 URL 缓存
    unawaited(_ensureUrlBuffer());
  }

  // ── 预初始化后 4 个播放器（后台串行，不抢当前带宽）──────────────
  Future<void> _preloadNextFour(int currentIndex) async {
    // 等当前视频先稳住
    await Future.delayed(_kPreloadStartDelay);
    if (!mounted) return;

    for (int offset = 1; offset <= _kPreloadAheadCount; offset++) {
      final idx = currentIndex + offset;
      if (idx >= _videos.length) break;
      if (_players.containsKey(idx)) continue;

      await _ensurePlayer(idx);
      if (!mounted) return;

      // 两个预加载之间再等一下
      await Future.delayed(_kPreloadGap);
      if (!mounted) return;
    }
  }

  // ── 点击暂停/播放 ─────────────────────────────────────────────────
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

  // ── UI ────────────────────────────────────────────────────────────
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
// ══════════════════════════════════════════════════════════════
class _FitVideo extends StatelessWidget {
  final VideoPlayerController controller;
  const _FitVideo({required this.controller});

  static const double _kForegroundScale = 1.06;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.width == 0 || size.height == 0) {
      return const ColoredBox(color: Colors.black);
    }

    final videoAR = size.width / size.height;

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
        final hasSideBlank = videoAR < screenAR;

        if (!hasSideBlank) {
          return ColoredBox(
            color: Colors.black,
            child: Center(child: foreground),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
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
            Center(child: foreground),
          ],
        );
      },
    );
  }
}