/// 上游视频 API — 直接调用，无需 m.py 中间代理
///
/// 对应 m.py 中的抓取逻辑（AES-CBC 加密请求 + 解密响应）
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:bilibili_glass/models/video_model.dart';

// ── 上游 API 常量（与 m.py 完全一致）──────────────────────────────────────
const _apiUrl    = 'http://18.167.17.100:8099/api/videos/listHot';
const _aesKey    = '625202f9149maomi';
const _aesIv     = '5efd3f6060emaomi';
const _uid       = '104226911';
const _perPage   = 30;
const _maxPages  = 30;

class ApiRepository {
  // ── AES-CBC 加密（与 m.py aes_enc 完全等价，返回大写 hex 字符串）──────
  static String encryptPayload(Map<String, dynamic> payload) {
    final jsonStr   = jsonEncode(payload);
    final key       = enc.Key.fromUtf8(_aesKey);
    final iv        = enc.IV.fromUtf8(_aesIv);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);
    return base16.encode(encrypted.bytes).toUpperCase();
  }

  // ── AES-CBC 解密（与 m.py aes_dec 完全等价，接受大写 hex 字符串）──────
  static String decryptResponse(String hexCiphertext) {
    final key       = enc.Key.fromUtf8(_aesKey);
    final iv        = enc.IV.fromUtf8(_aesIv);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(enc.Encrypted(base16.decode(hexCiphertext)), iv: iv);
  }

  // ── 单页请求 ───────────────────────────────────────────────────────────
  static Future<List<VideoItem>> fetchPage(int page) async {
    try {
      final encrypted = encryptPayload({
        'page':    page,
        'perPage': _perPage,
        'uId':     _uid,
      });

      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'User-Agent':    'okhttp/3.12.0',
              'Content-Type':  'application/x-www-form-urlencoded',
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

  // ── 逐页累加（与 m.py fetch_all 逻辑一致）────────────────────────────
  static Future<List<VideoItem>> fetchAll() async {
    final all  = <VideoItem>[];
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
      if (mountedForDebug) {
        debugPrint('📡 第 $page 页 +${items.length}（去重后累计 ${all.length}）');
      }
      if (items.isEmpty) break;
    }

    if (mountedForDebug) {
      debugPrint('✅ 共获取 ${all.length} 条视频');
    }
    return all;
  }

  // ── 字段规范化（与 m.py normalize 一致）────────────────────────────────
  static VideoItem? _normalize(Map<String, dynamic> v) {
    final id = (v['mv_id'] ?? v['id'] ?? v['video_id'] ?? '').toString();
    if (id.isEmpty) return null;

    final rawPlay = ((v['mv_play_url'] ?? v['play_url'] ?? v['url'] ?? '') as String)
        .replaceAll(r'\/', '/');
    final playUrl = _rewriteUrl(rawPlay);
    if (!playUrl.contains(RegExp(r'\.(mp4|m3u8|flv|ts|mov)', caseSensitive: false))) {
      return null;
    }

    final rawCover = ((v['mv_img_url'] ?? v['img_url'] ?? v['cover'] ?? '') as String)
        .replaceAll(r'\/', '/');

    return VideoItem(
      id:       id,
      title:    (v['mv_title'] ?? v['title'] ?? '').toString(),
      url:      playUrl,
      coverUrl: rawCover,
      author:   (v['mu_name'] ?? v['user_name'] ?? '').toString(),
      uid:      (v['mu_id'] ?? v['uid'] ?? '').toString(),
      created:  (v['mv_created'] ?? v['create_time'] ?? '').toString(),
      fullCached: false,
      headCached: false,
    );
  }

  // ── URL 重写（与 m.py URL_REWRITE 一致）───────────────────────────────
  static String _rewriteUrl(String url) {
    if (url.isEmpty) return url;
    return url.replaceAll('http://119.28.204.36', 'https://ksasdawoopss.i5stuw.com');
  }
}

// 避免 print，用 debugPrint 代替（生产环境会被 flutter 忽略）
bool mountedForDebug = true;