/// 上下滑动视频播放器（仿抖音上下滑动）
/// - 当前视频秒开（首屏同步加载 2 条）
/// - 后台预加载后 3 个
/// - 前面保留 15 个播放器（向上滑回不重新请求）
/// - 记录播放进度，被释放后重新初始化会 seek 回去
/// - 两级释放：超范围 + 超上限
/// - 竖屏模糊 sigma 15 / 横屏 sigma 8
/// - 视频播完自动滑到下一条
/// - 用户往上滑回已播完的页 → 从头播（不再被弹回）
/// - ★ 优化：延迟 1800/2500/1000 → 1200/1000/500，首屏同步 2 条
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
  final Map<int, VoidCallback> _listeners = {};
  final Map<int, Duration> _savedPositions = {};

  int _currentPage = 0;
  bool _loading = true;
  bool _fetching = false;
  bool _fetchingNext = false;
  String? _error;

  bool _autoAdvancing = false;
  bool _pendingAutoAdvance = false;
  int? _pendingAutoAdvanceForPage;

  NavBarVisibility? _nav;

  // ══════════════════════════════════════════════════════════
  // 配置
  // ══════════════════════════════════════════════════════════

  static const int _kUrlBuffer = 6;
  static const int _kPlayerKeepBefore = 15;
  static const int _kPlayerKeepAfter = 4;
  static const int _kMaxTotalPlayers = 20;

  static const int _kPreloadAheadCount = 3;

  // ★ 优化后的延迟（从 1800/2500/1000 降下来）
  static const Duration _kFetchInterval = Duration(milliseconds: 1200);
  static const Duration _kPreloadStartDelay = Duration(milliseconds: 1000);
  static const Duration _kPreloadGap = Duration(milliseconds: 500);

  static const Duration _kMinSavedPosition = Duration(seconds: 1);
  static const Duration _kEndThreshold = Duration(milliseconds: 300);

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
    for (final entry in _players.entries) {
      final listener = _listeners.remove(entry.key);
      if (listener != null) entry.value.removeListener(listener);
      entry.value.dispose();
    }
    _players.clear();
    _listeners.clear();
    _savedPositions.clear();
    super.dispose();
  }

  // ── 首屏：立即同步加载 2 条 ─────────────────────────────────────
  Future<void> _initialLoad() async {
    // 第 1 条
    await _loadNext();
    if (!mounted || _error != null) return;

    // ★ 第 2 条也同步加载 → 用户一进来 2 条都就绪
    await _loadNext();
    if (!mounted || _error != null) return;

    // 后台补齐 URL + 预加载后 3 个
    unawaited(_ensureUrlBuffer());
    unawaited(_preloadAhead(0));
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
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
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
      if (newIndex == _currentPage) {
        unawaited(_ensurePlayer(newIndex));
      }

      // 最后一页播完 → 新视频就绪后自动滑
      if (_pendingAutoAdvance && _videos.length > _currentPage + 1) {
        final triggerPage = _pendingAutoAdvanceForPage;
        _pendingAutoAdvance = false;
        _pendingAutoAdvanceForPage = null;

        if (triggerPage != null && triggerPage == _currentPage) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _autoAdvanceToNext(_currentPage);
          });
        }
      }
    } finally {
      _fetching = false;
    }
  }

  // ── 确保某页播放器已初始化 ────────────────────────────────────────
  Future<void> _ensurePlayer(int index) async {
    if (index < 0 || index >= _videos.length) return;

    // ★ 复用播放器：已播完 → 从头播
    if (_players.containsKey(index)) {
      debugPrint('[SwipeVideo] ♻️ 复用播放器 $index');
      final p = _players[index]!;
      if (p.value.isInitialized && index == _currentPage && widget.active) {
        final v = p.value;
        if (v.duration > Duration.zero &&
            (v.duration - v.position) <= _kEndThreshold) {
          debugPrint('[SwipeVideo] ♻️ $index 已播完 → 从头播');
          try {
            await p.seekTo(Duration.zero);
          } catch (e) {
            debugPrint('[SwipeVideo] seek 到 0 失败 $index: $e');
          }
          if (!mounted) return;
          await p.play();
        } else {
          await p.play();
        }
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
      await player.setLooping(false);

      if (!mounted) {
        player.dispose();
        _players.remove(index);
        return;
      }

      final savedPos = _savedPositions[index];
      if (savedPos != null && savedPos > _kMinSavedPosition) {
        try {
          await player.seekTo(savedPos);
          debugPrint('[SwipeVideo] 恢复进度 $index → ${savedPos.inSeconds}s');
        } catch (e) {
          debugPrint('[SwipeVideo] seek 失败 $index: $e');
        }
      }

      void onTick() => _onPlayerTick(index, player);
      _listeners[index] = onTick;
      player.addListener(onTick);

      if (index == _currentPage && widget.active) {
        player.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[SwipeVideo] init $index failed: $e');
      _players.remove(index);
      _listeners.remove(index);
    }
  }

  // ★ 播放器 tick
  void _onPlayerTick(int index, VideoPlayerController player) {
    if (!mounted) return;
    if (_autoAdvancing) return;
    if (index != _currentPage) return;
    if (!widget.active) return;

    final v = player.value;
    if (!v.isInitialized) return;
    if (v.duration <= Duration.zero) return;
    if (v.position <= Duration.zero) return;

    final remaining = v.duration - v.position;
    if (remaining <= _kEndThreshold) {
      debugPrint('[SwipeVideo] 🎬 视频 $index 播完，自动滑到下一个');
      _autoAdvanceToNext(index);
    }
  }

  // ★ 自动滑到下一个
  void _autoAdvanceToNext(int index) {
    if (!mounted) return;
    if (_autoAdvancing) return;
    if (index != _currentPage) return;

    if (index >= _videos.length - 1) {
      if (!_pendingAutoAdvance) {
        debugPrint('[SwipeVideo] 最后一页，等待新视频...');
        _pendingAutoAdvance = true;
        _pendingAutoAdvanceForPage = index;
        _players[index]?.pause();
        unawaited(_ensureUrlBuffer());
      }
      return;
    }

    _autoAdvancing = true;
    _players[index]?.pause();

    if (_controller.hasClients) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _autoAdvancing = false;
    });
  }

  // ── 释放播放器 ────────────────────────────────────────────────────
  void _releasePlayer(int index) {
    final p = _players[index];
    if (p == null) return;

    final listener = _listeners.remove(index);
    if (listener != null) p.removeListener(listener);

    if (p.value.isInitialized) {
      final pos = p.value.position;
      final dur = p.value.duration;
      final isFinished = dur > Duration.zero &&
          (dur - pos) <= _kEndThreshold;
      if (isFinished) {
        _savedPositions.remove(index);
      } else if (pos > _kMinSavedPosition) {
        _savedPositions[index] = pos;
      }
    }

    p.dispose();
    _players.remove(index);
  }

  // ── 翻页回调 ──────────────────────────────────────────────────────
  void _onPageChanged(int index) {
    final oldPage = _currentPage;

    if (_pendingAutoAdvance) {
      _pendingAutoAdvance = false;
      _pendingAutoAdvanceForPage = null;
    }

    final isBackward = index < oldPage;

    if (index > oldPage) {
      _nav?.hide();
    } else if (isBackward) {
      _nav?.show();
    }

    setState(() => _currentPage = index);

    _players.forEach((i, p) {
      if (i != index && p.value.isInitialized && p.value.isPlaying) {
        p.pause();
      }
    });

    unawaited(_ensurePlayer(index));

    if (!isBackward) {
      unawaited(_preloadAhead(index));
    } else {
      debugPrint('[SwipeVideo] 用户回看，跳过预加载');
    }

    // 两级释放
    final farAway = _players.keys
        .where((i) =>
            i < index - _kPlayerKeepBefore ||
            i > index + _kPlayerKeepAfter)
        .toList();
    for (final i in farAway) {
      _releasePlayer(i);
    }

    if (_players.length > _kMaxTotalPlayers) {
      final sorted = _players.keys.toList()
        ..sort((a, b) =>
            (a - index).abs().compareTo((b - index).abs()));
      for (int i = _kMaxTotalPlayers; i < sorted.length; i++) {
        _releasePlayer(sorted[i]);
      }
    }

    unawaited(_ensureUrlBuffer());
  }

  // ── 预加载后 3 个 ────────────────────────────────────────────────
  Future<void> _preloadAhead(int snapshotPage) async {
    await Future.delayed(_kPreloadStartDelay);
    if (!mounted) return;

    if (_currentPage != snapshotPage) {
      debugPrint('[SwipeVideo] 预加载延迟结束，用户已翻走，放弃');
      return;
    }

    for (int offset = 1; offset <= _kPreloadAheadCount; offset++) {
      if (!mounted) return;
      if (_currentPage != snapshotPage) {
        debugPrint('[SwipeVideo] 预加载中途用户翻走，停止');
        return;
      }

      final idx = snapshotPage + offset;
      if (idx >= _videos.length) break;
      if (_players.containsKey(idx)) continue;

      await _ensurePlayer(idx);
      if (!mounted) return;

      await Future.delayed(_kPreloadGap);
    }

    debugPrint('[SwipeVideo] 预加载 $snapshotPage 完成（共 $_kPreloadAheadCount 个）');
  }

  // ── 点击暂停/播放 ─────────────────────────────────────────────────
  void _onTap(int index) {
    final p = _players[index];
    if (p == null || !p.value.isInitialized) return;

    if (p.value.isPlaying) {
      p.pause();
    } else {
      final v = p.value;
      if (v.duration > Duration.zero &&
          (v.duration - v.position) <= _kEndThreshold) {
        p.seekTo(Duration.zero).then((_) => p.play());
      } else {
        p.play();
      }
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

          return RepaintBoundary(
            child: GestureDetector(
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
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 视频显示：原比例前景（轻微放大）+ 四周模糊填充
// ══════════════════════════════════════════════════════════════
class _FitVideo extends StatelessWidget {
  final VideoPlayerController controller;
  const _FitVideo({required this.controller});

  static const double _kForegroundScale = 1.06;
  static const double _kBlurPortrait = 15.0;
  static const double _kBlurLandscape = 8.0;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.width == 0 || size.height == 0) {
      return const ColoredBox(color: Colors.black);
    }

    final videoAR = size.width / size.height;
    final isPortrait = videoAR < 1.0;
    final blurSigma = isPortrait ? _kBlurPortrait : _kBlurLandscape;

    final Widget foreground = ClipRect(
      child: Transform.scale(
        scale: _kForegroundScale,
        child: AspectRatio(
          aspectRatio: videoAR,
          child: VideoPlayer(controller),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
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
  }
}