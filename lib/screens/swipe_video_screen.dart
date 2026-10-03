/// 上下滑动视频播放器（仿抖音上下滑动）
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
  // ★ 预加载 + 节流配置
  // ══════════════════════════════════════════════════════════

  /// 目标预加载视频总数（URL 层面）
  static const int _kTargetPreloadCount = 30;

  /// 首屏立即初始化播放器的数量
  static const int _kInitialPlayerCount = 3;

  /// 翻页时向前预初始化播放器的数量
  static const int _kForwardPreloadRange = 3;

  /// 保留播放器范围
  static const int _kPlayerKeepRange = 4;

  // ── 节流参数 ──────────────────────────────────────────────
  /// 每条之间的基础间隔（毫秒），避免请求过密被限流
  static const Duration _kPreloadItemDelay =
      Duration(milliseconds: 450);

  /// 每拉 N 条后，长休息一次
  static const int _kPreloadBatchSize = 5;

  /// 长休息间隔
  static const Duration _kPreloadBatchDelay =
      Duration(milliseconds: 1200);

  /// 单次请求失败时的退避起始值
  static const Duration _kPreloadRetryBase =
      Duration(milliseconds: 800);

  /// 连续失败达到此值时，停止预加载（避免死循环打接口）
  static const int _kPreloadMaxRetry = 3;

  // ── 运行时状态 ──────────────────────────────────────────────
  bool _preloading = false;
  bool _preloadPaused = false;
  Timer? _preloadResumeTimer;

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
    _preloadResumeTimer?.cancel();
    _controller.dispose();
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    super.dispose();
  }

  // ── 首屏加载 ──────────────────────────────────────────────────────
  Future<void> _initialLoad() async {
    await _loadNext();
    if (!mounted || _error != null) return;
    await _loadNext();
    if (!mounted || _error != null) return;

    // 后台静默预加载到 30 条
    unawaited(_preloadRest());
  }

  // ── ★ 后台静默预加载（带节流 + 用户操作时暂停）────────────────────
  Future<void> _preloadRest() async {
    if (_preloading) return;    // 已经在跑就忽略
    _preloading = true;

    int sinceLastBatch = 0;
    int consecutiveFailures = 0;

    try {
      while (mounted &&
          _videos.length < _kTargetPreloadCount &&
          _error == null) {

        // ① 用户正在滑动 / 页面不活跃 → 暂停预加载
        if (_preloadPaused || !widget.active) {
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        // ② 连续失败太多 → 停止预加载
        if (consecutiveFailures >= _kPreloadMaxRetry) {
          debugPrint('[SwipeVideo] 连续失败 $consecutiveFailures 次，'
              '停止预加载（已有 ${_videos.length} 条）');
          break;
        }

        // ③ 真正拉一条
        final before = _videos.length;
        await _loadNext();
        if (!mounted) break;

        if (_videos.length == before) {
          // 没拉到（并发被跳过 / 拉取失败）
          consecutiveFailures++;
          // 指数退避：800ms → 1600ms → 3200ms
          final backoff = _kPreloadRetryBase *
              (1 << (consecutiveFailures - 1));
          debugPrint('[SwipeVideo] 预加载失败 '
              '(第 $consecutiveFailures 次)，等待 ${backoff.inMilliseconds}ms');
          await Future.delayed(backoff);
          continue;
        }

        // 拉到新的 → 重置失败计数
        consecutiveFailures = 0;
        sinceLastBatch++;

        // ④ 每批之间休息更久（防触发分钟级限流）
        if (sinceLastBatch >= _kPreloadBatchSize) {
          sinceLastBatch = 0;
          await Future.delayed(_kPreloadBatchDelay);
        } else {
          await Future.delayed(_kPreloadItemDelay);
        }
      }
    } finally {
      _preloading = false;
      debugPrint('[SwipeVideo] 预加载结束，共 ${_videos.length} 条');
    }
  }

  /// 用户开始操作时暂停预加载
  void _pausePreload() {
    _preloadPaused = true;
    _preloadResumeTimer?.cancel();
    // 2 秒后自动恢复
    _preloadResumeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _preloadPaused = false;
    });
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
      if (newIndex < _kInitialPlayerCount) {
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

    // ★ 用户翻页 → 暂停后台预加载 2 秒（优先保证当前体验）
    _pausePreload();

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

    // 预初始化当前页 + 后面 3 页
    for (int i = index; i <= index + _kForwardPreloadRange; i++) {
      if (i >= 0 && i < _videos.length) {
        unawaited(_ensurePlayer(i));
      }
    }

    // 释放距离太远的播放器
    final toRemove = _players.keys
        .where((i) => (i - index).abs() > _kPlayerKeepRange)
        .toList();
    for (final i in toRemove) {
      _players[i]?.dispose();
      _players.remove(i);
    }

    // 接近末尾 → 补充预加载
    if (index >= _videos.length - 3 &&
        _videos.length < _kTargetPreloadCount) {
      unawaited(_preloadRest());
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