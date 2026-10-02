/// 视频播放页 — 直接播放视频直链
library;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:bilibili_glass/models/video_model.dart';
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
  String? _playError;

  @override
  void initState() {
    super.initState();
    _startPlayback();
  }

  Future<void> _startPlayback() async {
    debugPrint('[VideoPlayer] playing: ${widget.video.url}');

    _playerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.video.url),
    );

    try {
      await _playerController!.initialize();
      if (!mounted) return;

      setState(() => _initialized = true);
      _playerController!.play();
      _chewieController = ChewieController(
        videoPlayerController: _playerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _playerController!.value.aspectRatio,
        deviceOrientationsAfterFullScreen:
            const [DeviceOrientation.portraitUp],
        allowedScreenSleep: false,
        hideControlsTimer: const Duration(seconds: 5),
        placeholder: Container(color: Colors.black),
      );
      setState(() {});
    } catch (e) {
      debugPrint('[VideoPlayer] 初始化失败: $e');
      setState(() => _playError = e.toString());
    }
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
      body: _playError != null
          ? _buildErrorView()
          : _initialized && _chewieController != null
              ? Stack(
                  children: [
                    Chewie(controller: _chewieController!),
                    _buildOverlay(),
                  ],
                )
              : Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.accentColor),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.liveColor),
            const SizedBox(height: 16),
            const Text('播放失败',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
            const SizedBox(height: 8),
            Text(_playError ?? '',
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('返回'),
            ),
          ],
        ),
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
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (widget.video.author.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.person,
                              size: 12, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            widget.video.author,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
