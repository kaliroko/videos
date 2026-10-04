/// 上游视频 API — 直接调用，无需 m.py 中间代理
///
/// 对应 m.py 中的抓取逻辑（AES-GCM 加密请求 + 解密响应）
/// ★ 密钥由 HardwareKey 硬件派生，不在源码中明文存储
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:bilibili_glass/models/video_model.dart';
import '../config/hardware_key.dart';
import '../config/secrets.dart';

// ── 上游 API 加密请求（AES-GCM，密钥由 HardwareKey 派生）───────────────────
// 所有敏感常量（key/uid/url）均通过 HardwareKey 运行时派生，编译产物中无明文
// 非敏感业务常量保留为 const
const _perPage = 30;
const _maxPages = 30;

class ApiRepository {
  // ── AES-GCM 加密（密钥由 HardwareKey 派生，每次使用随机 nonce）────────
  static Future<String> encryptPayload(Map<String, dynamic> payload) async {
    final jsonStr = jsonEncode(payload);
    final keyBytes = await HardwareKey.deriveApiKey();
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final nonce = enc.IV.generator(12); // 12 字节随机 nonce
    final encrypted = encrypter.encrypt(jsonStr, iv: nonce);

    // 拼接：nonce(12) + authTag(16) + ciphertext
    // 发送给服务端时需附带 nonce 和 tag，服务端同样从 HardwareKey 派生密钥
    final combined = Uint8List(12 + 16 + encrypted.bytes.length);
    combined.setRange(0, 12, nonce.bytes);
    combined.setRange(12, 28, encrypted.bytes.sublist(0, 16));
    combined.setRange(28, combined.length, encrypted.bytes.sublist(16));

    // 返回 Base64 编码的完整密文（含 nonce 和 tag）
    return base64Encode(combined);
  }

  // ── AES-GCM 解密（自动验证 auth tag）────────
  static Future<String> decryptResponse(String base64Ciphertext) async {
    final keyBytes = await HardwareKey.deriveApiKey();
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

    final data = base64Decode(base64Ciphertext);
    if (data.length < 28) {
      throw FormatException('Invalid response length');
    }

    final nonce = enc.IV(data.sublist(0, 12));
    final ctWithTag = data.sublist(12); // 包含 16 字节 auth tag

    try {
      return encrypter.decrypt(enc.Encrypted(ctWithTag), iv: nonce);
    } on FormatException {
      throw StateError('Auth tag mismatch: response may be tampered');
    }
  }

  // ── 单页请求 ───────────────────────────────────────────────────────────
  static Future<List<VideoItem>> fetchPage(int page) async {
    try {
      // 使用 SecureConfig 同步 getter 获取 API 配置（零改动原有接口）
      final uid = SecureConfig.apiUid;
      final apiUrl = SecureConfig.apiUrl;
      final rewriteHost = SecureConfig.apiRewriteHost;

      final encrypted = await encryptPayload({
        'page': page,
        'perPage': _perPage,
        'uId': uid,
      });

      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {
              'User-Agent': 'okhttp/3.12.0',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': encrypted},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final decrypted = await decryptResponse(response.body.trim());
      final json = jsonDecode(decrypted) as Map<String, dynamic>;
      if ((json['code'] ?? 0) != 0) return [];

      final data = json['data'];
      List<dynamic> items = [];
      if (data is Map) {
        items = (data['list'] ?? data['items'] ?? []) as List<dynamic>;
      } else if (data is List) {
        items = data;
      }

      return items
          .map((e) => _normalize(e as Map<String, dynamic>, rewriteHost))
          .whereType<VideoItem>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── 逐页累加（与 m.py fetch_all 逻辑一致）────────────────────────────
  static Future<List<VideoItem>> fetchAll() async {
    final all = <VideoItem>[];
    final seen = <String>{};

    for (int page = 1; page <= _maxPages; page++) {
      final items = await fetchPage(page);
      if (items.isEmpty) break;

      for (final item in items) {
        if (seen.add(item.id)) {
          all.add(item);
        }
      }
      // 按 created 降序排序（与 m.py 一致）
      all.sort((a, b) => b.created.compareTo(a.created));
    }

    return all;
  }

  // ── 单页获取（供 VideoProvider.fetchVideos 调用）──────────────────────
  static Future<List<VideoItem>> fetchVideos() async {
    return fetchPage(1);
  }

  // ── 字段规范化（与 m.py normalize 一致）────────────────────────────────
  static VideoItem? _normalize(Map<String, dynamic> v, String rewriteHost) {
    final id =
        (v['mv_id'] ?? v['id'] ?? v['video_id'] ?? '').toString();
    if (id.isEmpty) return null;

    final rawPlay = ((v['mv_play_url'] ?? v['play_url'] ?? v['url'] ?? '')
            as String)
        .replaceAll(r'\/', '/');
    final playUrl = _rewriteUrl(rawPlay, rewriteHost);
    if (!playUrl.contains(RegExp(
        r'\.(mp4|m3u8|flv|ts|mov)',
        caseSensitive: false,
    ))) {
      return null;
    }

    final rawCover = ((v['mv_img_url'] ?? v['img_url'] ?? v['cover'] ?? '')
            as String)
        .replaceAll(r'\/', '/');

    return VideoItem(
      id: id,
      title: (v['mv_title'] ?? v['title'] ?? '').toString(),
      url: playUrl,
      coverUrl: rawCover,
      author: (v['mu_name'] ?? v['user_name'] ?? '').toString(),
      uid: (v['mu_id'] ?? v['uid'] ?? '').toString(),
      created: (v['mv_created'] ?? v['create_time'] ?? '').toString(),
      fullCached: false,
      headCached: false,
    );
  }

  // ── URL 重写（与 m.py URL_REWRITE 一致）───────────────────────────────
  static String _rewriteUrl(String url, String rewriteHost) {
    if (url.isEmpty) return url;
    return url.replaceAll('http://119.28.204.36', rewriteHost);
  }
}
