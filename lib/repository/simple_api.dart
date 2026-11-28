/// 随机视频仓库 — 主源 → 备源1→2→3→4 顺序自动切换
/// 单源超时 5 秒，超时/失败立即切换下一源，依次尝试
/// 所有源 URL 均使用 XOR 0x3C 加密
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:suisuinian/models/video_model.dart';

// ══════════════════════════════════════════════════════════════════
// ★ XOR 0x3C 密钥
// ══════════════════════════════════════════════════════════════════
const int _kXorKey = 0x3C;

String _xorDecode(List<int> bytes) =>
    String.fromCharCodes(bytes.map((b) => b ^ _kXorKey));

// ── 源1（主源）: https://api.wwlww.org/v1/get_video ───────────────
const List<int> _kEncPrimary = [
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  0x5D, 0x4C, 0x55, 0x12, 0x4B, 0x4B, 0x50, 0x4B, 0x4B,
  0x12, 0x53, 0x4E, 0x5B, 0x13, 0x4A, 0x0D, 0x13,
  0x5B, 0x59, 0x48, 0x63, 0x4A, 0x55, 0x58, 0x59, 0x53,
];

// ── 备源1: https://api.kuleu.com/api/MP4_xiaojiejie?type=json ─────
const List<int> _kEncKuleu = [
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  0x5D, 0x4C, 0x55, 0x12,
  0x57, 0x49, 0x50, 0x59, 0x49, 0x12, 0x5F, 0x53, 0x51,
  0x13, 0x5D, 0x4C, 0x55, 0x13,
  0x71, 0x6C, 0x08, 0x63,
  0x44, 0x55, 0x5D, 0x53, 0x56, 0x55, 0x59, 0x56, 0x55, 0x59,
  0x03, 0x48, 0x45, 0x4C, 0x59, 0x01,
  0x56, 0x4F, 0x53, 0x52,
];

// ── 备源2: https://tucdn.wpon.cn/api-girl/index.php?wpon=json ─────
const List<int> _kEncWpon = [
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  0x48, 0x49, 0x5F, 0x58, 0x52, 0x12,
  0x4B, 0x4C, 0x53, 0x52, 0x12, 0x5F, 0x52, 0x13,
  0x5D, 0x4C, 0x55, 0x11, 0x5B, 0x55, 0x4E, 0x50, 0x13,
  0x55, 0x52, 0x58, 0x59, 0x44, 0x12, 0x4C, 0x54, 0x4C,
  0x03, 0x4B, 0x4C, 0x53, 0x52, 0x01,
  0x56, 0x4F, 0x53, 0x52,
];

// ── 备源3: https://mm.diskgirl.com/get/get1.php ───────────────────
const List<int> _kEncDiskgirl = [
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  0x51, 0x51, 0x12,
  0x58, 0x55, 0x4F, 0x57, 0x5B, 0x55, 0x4E, 0x50, 0x12, 0x5F, 0x53, 0x51,
  0x13, 0x5B, 0x59, 0x48, 0x13, 0x5B, 0x59, 0x48, 0x0D, 0x12, 0x4C, 0x54, 0x4C,
];

// ── 备源4: https://api.woeo.net/API/api-girl/index.php?type=json ──
const List<int> _kEncWoeo = [
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  0x5D, 0x4C, 0x55, 0x12,
  0x4B, 0x53, 0x59, 0x53, 0x12, 0x52, 0x59, 0x48,
  0x13, 0x7D, 0x6C, 0x75, 0x13,
  0x5D, 0x4C, 0x55, 0x11, 0x5B, 0x55, 0x4E, 0x50, 0x13,
  0x55, 0x52, 0x58, 0x59, 0x44, 0x12, 0x4C, 0x54, 0x4C,
  0x03, 0x48, 0x45, 0x4C, 0x59, 0x01,
  0x56, 0x4F, 0x53, 0x52,
];

// ══════════════════════════════════════════════════════════════════
class _VideoSource {
  final String name; // 日志用名称
  final String url;
  final VideoItem? Function(dynamic body) parse;
  final bool isText;

  const _VideoSource({
    required this.name,
    required this.url,
    required this.parse,
    this.isText = false,
  });
}

// ── 各源解析 ────────────────────────────────────────────────────
VideoItem? _parseWwlww(dynamic body) {
  final map = body as Map<String, dynamic>;
  final videoUrl = (map['url'] ?? '').toString();
  if (videoUrl.isEmpty) return null;
  return _buildItem(videoUrl, (map['img_url'] ?? '').toString());
}

VideoItem? _parseKuleu(dynamic body) {
  final map = body as Map<String, dynamic>;
  final videoUrl = (map['mp4_video'] ?? '').toString();
  if (videoUrl.isEmpty) return null;
  return _buildItem(videoUrl, '');
}

VideoItem? _parseWpon(dynamic body) {
  final map = body as Map<String, dynamic>;
  var videoUrl = (map['url'] ?? '').toString();
  if (videoUrl.isEmpty) return null;
  if (videoUrl.startsWith('//')) videoUrl = 'https:$videoUrl';
  return _buildItem(videoUrl, '');
}

VideoItem? _parseDiskgirl(dynamic body) {
  final text = body.toString().trim();
  if (text.isEmpty || !text.startsWith('http')) return null;
  return _buildItem(text, '');
}

VideoItem? _parseWoeo(dynamic body) {
  final map = body as Map<String, dynamic>;
  final videoUrl = (map['data'] ?? '').toString();
  if (videoUrl.isEmpty) return null;
  return _buildItem(videoUrl, '');
}

// ── 构建 VideoItem ──────────────────────────────────────────────
VideoItem _buildItem(String videoUrl, String coverUrl) {
  final rawName = videoUrl.split('/').last.split('?').first;
  return VideoItem(
    id: rawName,
    title: _decodeFileName(rawName),
    url: videoUrl,
    coverUrl: coverUrl,
    author: '',
    uid: '',
    created: '',
    fullCached: false,
    headCached: false,
  );
}

String _decodeFileName(String raw) {
  try {
    final withoutExt =
        raw.split('.').isEmpty ? raw : raw.substring(0, raw.lastIndexOf('.'));
    return Uri.decodeComponent(withoutExt);
  } catch (_) {
    return '视频';
  }
}

// ══════════════════════════════════════════════════════════════════
class SimpleApiRepository {
  SimpleApiRepository._();

  // ── 源列表：主源 → 备源1 → 备源2 → 备源3 → 备源4 ───────────────
  static final List<_VideoSource> _sources = [
    _VideoSource(name: '主源 wwlww',   url: _xorDecode(_kEncPrimary),  parse: _parseWwlww),
    _VideoSource(name: '备源1 kuleu',  url: _xorDecode(_kEncKuleu),    parse: _parseKuleu),
    _VideoSource(name: '备源2 wpon',   url: _xorDecode(_kEncWpon),     parse: _parseWpon),
    _VideoSource(name: '备源3 diskgirl', url: _xorDecode(_kEncDiskgirl), parse: _parseDiskgirl, isText: true),
    _VideoSource(name: '备源4 woeo',   url: _xorDecode(_kEncWoeo),     parse: _parseWoeo),
  ];

  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 400);
  static const Duration _sourceTimeout = Duration(seconds: 5);

  // ── 顺序尝试所有源，每个源 5 秒超时 ────────────────────────────
  static Future<VideoItem?> fetchOne() async {
    // 请求冷却
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < _minInterval) {
      await Future.delayed(_minInterval - elapsed);
    }
    _lastRequest = DateTime.now();

    final total = _sources.length;

    // ★ 从主源到备源依次尝试；任一步超时/失败 → 立即进入下一源
    for (int i = 0; i < total; i++) {
      final source = _sources[i];
      debugPrint('[SimpleApi] ▶ 尝试 ${i + 1}/$total : ${source.name}');

      try {
        final item = await _trySource(source);
        if (item != null) {
          debugPrint('[SimpleApi] ✅ 命中 ${source.name} → ${item.title}');
          return item;
        }
        debugPrint('[SimpleApi] ⚠️ ${source.name} 返回空，切换下一源');
      } catch (e) {
        debugPrint('[SimpleApi] ⚠️ ${source.name} 失败($e)，切换下一源');
      }
      // 循环继续 → 下一个源
    }

    debugPrint('[SimpleApi] ❌ 全部 $total 个源均失败');
    return null;
  }

  // ── 尝试单个源（5 秒超时）──────────────────────────────────────
  static Future<VideoItem?> _trySource(_VideoSource source) async {
    final response = await http
        .get(
          Uri.parse(source.url),
          headers: {'User-Agent': 'Mozilla/5.0'},
        )
        .timeout(_sourceTimeout); // ★ 5 秒无响应抛出 TimeoutException

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final dynamic body =
        source.isText ? response.body : jsonDecode(response.body);
    return source.parse(body);
  }

  // ── 批量拉取 ─────────────────────────────────────────────────
  static Future<List<VideoItem>> fetchVideos({int count = 1}) async {
    final list = <VideoItem>[];
    for (int i = 0; i < count; i++) {
      final v = await fetchOne();
      if (v != null) list.add(v);
    }
    return list;
  }
}