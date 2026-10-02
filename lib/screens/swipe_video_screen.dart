/// 上下滑动视频播放器（仿抖音上下滑动）
/// - 视频按原比例显示，与现有播放器尺寸一致
/// - 上下滑动切换视频，自动播放当前页
/// - 惰性加载：滑到末尾才请求下一条
/// - 前后各保留 2 个播放器实例，其他自动释放
/// - 向下滑 → 隐藏全局底部液态玻璃栏；向上滑 → 恢复显示
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/video_model.dart';
import '../repository/simple_api.dart';
import '../theme/app_theme.dart';
import '../providers/nav_bar_visibility.dart';

class SwipeVideoScreen extends StatefulWidget {
  const SwipeVideoScreen({super.key});

  @override
  State<SwipeVideoScreen> createState() => _SwipeVideoScreenState();
}

class _SwipeVideoScreenState extends State<SwipeVideoScreen> {
  late final PageController _controller;

  final List<VideoItem> _videos = [];
  /// index → 播放器
  final Map<int, VideoPlayerController> _players = {};

  int _currentPage = 0;
  bool _loading = true;   // 首屏加载
  bool _fetching = false; // 是否正在请求下一条
  String? _error;

  /// ★ 全局底栏控制器缓存（dispose 阶段不能用 context）
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
    // 进入视频页，先确保底栏可见
    _nav?.show();
  }

  @override
  void dispose() {
    // 离开视频页前恢复底栏，避免回到别的页面看不到入口
    _nav?.show();
    _controller.dispose();
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    super.dispose();
  }

  /// ★ 首屏预加载 2 条，保证 PageView 一开始就能滑动
  Future<void> _initialLoad() async {
    await _loadNext();
    if (!mounted || _error != null) return;
    await _loadNext();
  }

  // ── 加载下一条 ────────────────────────────────────────────────────
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
      if (_videos.length - 1 == _currentPage) {
        _players[_currentPage]?.play();
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
      if (p.value.isInitialized && index == _currentPage) {
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
      if (index == _currentPage) {
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

    // ★ 向下滑 → 隐藏底栏；向上滑 → 显示底栏
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

    _ensurePlayer(index);
    _ensurePlayer(index + 1);

    // 释放距离 ≥ 2 的播放器
    final toRemove = _players.keys
        .where((i) => (i - index).abs() > 2)
        .toList();
    for (final i in toRemove) {
      _players[i]?.dispose();
      _players.remove(i);
    }

    // 滑到末尾占位页 → 自动请求下一条
    if (index >= _videos.length - 1) {
      _loadNext();
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
        // ★ 末尾多一页"加载占位页"，保证滑到底还能继续滑，能触发懒加载
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
// 视频按原比例显示
// ══════════════════════════════════════════════════════════════
class _FitVideo extends StatelessWidget {
  final VideoPlayerController controller;
  const _FitVideo({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}