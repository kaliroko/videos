/// 视频播放页 — 竖屏沉浸式播放
library;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/providers/video_provider.dart';
import 'package:bilibili_glass/theme/app_theme.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoItem video;
  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _playerController;
  ChewieController? _chewieController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _startPlayback();
  }

  void _startPlayback() {
    final playUrl = context.read<VideoProvider>().getPlayUrl(widget.video.url);
    _playerController = VideoPlayerController.networkUrl(Uri.parse(playUrl));

    _playerController!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _playerController!.play();
      _chewieController = ChewieController(
        videoPlayerController: _playerController!,
        autoPlay: true,
        looping: true,
        aspectRatio: _playerController!.value.aspectRatio,
        deviceOrientationsAfterFullScreen: const [DeviceOrientation.portraitUp],
        allowedScreenSleep: false,
        hideControlsTimer: const Duration(seconds: 5),
        placeholder: Container(color: Colors.black),
      );
      setState(() {});
    }).catchError((e) {
      debugPrint('视频初始化失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频加载失败: $e'), backgroundColor: AppTheme.liveColor),
        );
      }
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _playerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _initialized && _chewieController != null
          ? Stack(
              children: [
                Chewie(controller: _chewieController!),
                _buildOverlay(),
              ],
            )
          : Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            ),
    );
  }

  Widget _buildOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.video.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.person, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          widget.video.author,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.video.fullCached)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('⚡ 本地', style: TextStyle(color: Colors.white, fontSize: 10)),
                )
              else if (widget.video.headCached)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('🚀 缓存中', style: TextStyle(color: Colors.white, fontSize: 10)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
