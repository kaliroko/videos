/// 上游视频 API — 直接调用，无需 m.py 中间代理
///
/// 对应 m.py 中的抓取逻辑（AES-CBC 加密请求 + 解密响应）
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:suisuinian/models/video_model.dart';
import '../config/secrets.dart';

// ══════════════════════════════════════════════════════════════════
// 分页参数
// ══════════════════════════════════════════════════════════════════

/// 每页拉取条数
const int kDefaultPerPage = 80;

/// 最大页数（50 × 2 = 100 条）
const int kDefaultMaxPages = 2;

/// 全局硬上限：任何方式都不可能超过这个数
const int kMaxTotalVideos = 100;

class ApiRepository {
  // ── AES-CBC 加密（与 m.py aes_enc 等价，返回大写 hex 字符串）────────
  static String encryptPayload(Map<String, dynamic> payload) {
    final jsonStr   = jsonEncode(payload);
    final key       = enc.Key.fromUtf8(SecureConfig.apiAesKey);
    final iv        = enc.IV.fromUtf8(SecureConfig.apiAesIv);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);
    return encrypted.base16.toUpperCase();
  }

  // ── AES-CBC 解密（与 m.py aes_dec 等价，接受大写 hex 字符串）────────
  static String decryptResponse(String hexCiphertext) {
    final key       = enc.Key.fromUtf8(SecureConfig.apiAesKey);
    final iv        = enc.IV.fromUtf8(SecureConfig.apiAesIv);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(enc.Encrypted.fromBase16(hexCiphertext), iv: iv);
  }

  // ══════════════════════════════════════════════════════════════════
  // 单页请求
  // ══════════════════════════════════════════════════════════════════
  static Future<List<VideoItem>> fetchPage(
    int page, {
    int perPage = kDefaultPerPage,
  }) async {
    try {
      final encrypted = encryptPayload({
        'page':    page,
        'perPage': perPage,
        'uId':     SecureConfig.apiUid,
      });

      final response = await http
          .post(
            Uri.parse(SecureConfig.apiUrl),
            headers: {
              'User-Agent':   'okhttp/3.12.0',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': encrypted},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final decrypted = decryptResponse(response.body.trim());
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
          .map((e) => _normalize(e as Map<String, dynamic>))
          .whereType<VideoItem>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 逐页累加拉取
  // ──────────────────────────────────────────────────────────────────
  // - perPage   每页条数
  // - maxPages  最大页数（null = 不限制，但会被 hardLimit 拦住）
  // - hardLimit 硬上限（绝对不超过）
  //
  // 默认：50 条/页 × 2 页 = 100 条
  //
  // 用法示例：
  //   fetchAll()                            → 100 条（默认）
  //   fetchAll(perPage: 30, maxPages: 3)    → 90 条
  //   fetchAll(hardLimit: 50)               → 最多 50 条
  // ══════════════════════════════════════════════════════════════════
  static Future<List<VideoItem>> fetchAll({
    int perPage = kDefaultPerPage,
    int? maxPages = kDefaultMaxPages,
    int hardLimit = kMaxTotalVideos,
  }) async {
    final all  = <VideoItem>[];
    final seen = <String>{};

    int page = 1;
    while (true) {
      // 页数上限
      if (maxPages != null && page > maxPages) break;
      // 总量硬上限
      if (all.length >= hardLimit) break;

      final items = await fetchPage(page, perPage: perPage);
      if (items.isEmpty) break;

      for (final item in items) {
        if (seen.add(item.id)) all.add(item);
        if (all.length >= hardLimit) break;
      }

      // 按 created 降序排序（与 m.py 一致）
      all.sort((a, b) => b.created.compareTo(a.created));

      page++;
    }

    // 兜底截断
    if (all.length > hardLimit) {
      return all.sublist(0, hardLimit);
    }
    return all;
  }

  // ══════════════════════════════════════════════════════════════════
  // 拉取指定数量（自动翻页直到攒够）
  // ──────────────────────────────────────────────────────────────────
  // 例：
  //   fetchCount(100)   → 拉 100 条
  //   fetchCount(50)    → 拉 50 条
  //   fetchCount(200)   → 会被 hardLimit 截到 100 条
  // ══════════════════════════════════════════════════════════════════
  static Future<List<VideoItem>> fetchCount(
    int targetCount, {
    int perPage = kDefaultPerPage,
    int? maxPages = kDefaultMaxPages,
    int hardLimit = kMaxTotalVideos,
  }) async {
    // 用户要求的数量不能超过硬上限
    final want = targetCount > hardLimit ? hardLimit : targetCount;

    final all  = <VideoItem>[];
    final seen = <String>{};

    int page = 1;
    while (all.length < want) {
      if (maxPages != null && page > maxPages) break;

      final items = await fetchPage(page, perPage: perPage);
      if (items.isEmpty) break;

      for (final item in items) {
        if (seen.add(item.id)) all.add(item);
        if (all.length >= want) break;
      }

      page++;
    }

    all.sort((a, b) => b.created.compareTo(a.created));
    return all;
  }

  // ══════════════════════════════════════════════════════════════════
  // 单页获取（供 VideoProvider.fetchVideos 调用）
  // ★ 默认拉 50 条（而不是 30 条）
  // ══════════════════════════════════════════════════════════════════
  static Future<List<VideoItem>> fetchVideos({
    int perPage = kDefaultPerPage,
  }) async {
    return fetchPage(1, perPage: perPage);
  }

  // ══════════════════════════════════════════════════════════════════
  // 字段规范化（与 m.py normalize 一致）
  // ══════════════════════════════════════════════════════════════════
  static VideoItem? _normalize(Map<String, dynamic> v) {
    final id = (v['mv_id'] ?? v['id'] ?? v['video_id'] ?? '').toString();
    if (id.isEmpty) return null;

    final rawPlay =
        ((v['mv_play_url'] ?? v['play_url'] ?? v['url'] ?? '') as String)
            .replaceAll(r'\/', '/');
    final playUrl = _rewriteUrl(rawPlay);
    if (!playUrl.contains(
        RegExp(r'\.(mp4|m3u8|flv|ts|mov)', caseSensitive: false))) {
      return null;
    }

    final rawCover =
        ((v['mv_img_url'] ?? v['img_url'] ?? v['cover'] ?? '') as String)
            .replaceAll(r'\/', '/');

    return VideoItem(
      id:         id,
      title:      (v['mv_title'] ?? v['title'] ?? '').toString(),
      url:        playUrl,
      coverUrl:   rawCover,
      author:     (v['mu_name'] ?? v['user_name'] ?? '').toString(),
      uid:        (v['mu_id'] ?? v['uid'] ?? '').toString(),
      created:    (v['mv_created'] ?? v['create_time'] ?? '').toString(),
      fullCached: false,
      headCached: false,
    );
  }

  // ── URL 重写（与 m.py URL_REWRITE 一致）─────────────────────────────
  static String _rewriteUrl(String url) {
    if (url.isEmpty) return url;
    return url.replaceAll(
        SecureConfig.apiOriginHost,   // ★ 从加密配置里取，不再硬编码
        SecureConfig.apiRewriteHost);
  }
}