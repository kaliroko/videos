/// API 网关 — 对接 JWT + AES-ECB 加密新 API（移植文档）
///
/// 独立于旧 ApiRepository（listHot AES-CBC），两者互不干扰
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:bilibili_glass/managers/jwt_manager.dart';
import 'package:bilibili_glass/models/video_model.dart';

// ── 常量 ────────────────────────────────────────────────────────────────────
const _apiBase = 'https://bkij1.aemtpwbdn3xf7b.xyz/fast-cloud';
const _picBaseUrl = 'https://qv1tx2.shoupingxz.com';

// ── API 网关 ────────────────────────────────────────────────────────────────

class ApiService {
  /// 视频分类定义
  static const catRecommend = Category(id: '1', name: '推荐');
  static const catHot       = Category(id: '2', name: '热门');
  static const catNew       = Category(id: '3', name: '最新');
  static const catMovie     = Category(id: '4', name: '电影');
  static const catDrama     = Category(id: '5', name: '电视剧');
  static const catAnime     = Category(id: '6', name: '动漫');
  static const catDocumentary = Category(id: '7', name: '纪录片');
  static const catVariety   = Category(id: '8', name: '综艺');

  static const List<Category> categories = [
    catRecommend, catHot, catNew, catMovie,
    catDrama, catAnime, catDocumentary, catVariety,
  ];

  // ── 获取视频列表（/cms/query?groupId=X&page=Y）──────────────────────────
  static Future<List<MovieBean>> fetchList({
    required String groupId,
    int page = 1,
  }) async {
    try {
      final headers = await JwtManager.getRequestHeaders();
      final url = '$_apiBase/cms/query?groupId=$groupId&page=$page&os=android';
      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] == '1033' || body['code'] == '1034') {
        await JwtManager.forceRefresh();
        final h2 = await JwtManager.getRequestHeaders();
        final r2 = await http.get(Uri.parse(url), headers: h2)
            .timeout(const Duration(seconds: 15));
        return _parseList(r2.body);
      }
      if (body['code'] != '0000') return [];
      return _parseList(response.body);
    } catch (_) {
      return [];
    }
  }

  // ── 获取视频详情（/cms/vod/detail/{id}）─────────────────────────────────
  static Future<MovieBean?> fetchDetail(String movieId) async {
    try {
      final headers = await JwtManager.getRequestHeaders();
      final url = '$_apiBase/cms/vod/detail/$movieId?needCdnAuth=true&os=android';
      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] == '1033' || body['code'] == '1034') {
        await JwtManager.forceRefresh();
        final h2 = await JwtManager.getRequestHeaders();
        final r2 = await http.get(Uri.parse(url), headers: h2)
            .timeout(const Duration(seconds: 15));
        return _parseDetail(r2.body);
      }
      if (body['code'] != '0000') return null;
      return _parseDetail(response.body);
    } catch (_) {
      return null;
    }
  }

  // ── 搜索视频（POST /cms/vod/search3）─────────────────────────────────────
  static Future<List<MovieBean>> search(String keyword, {int page = 1}) async {
    try {
      final headers = await JwtManager.getRequestHeaders();
      final url = '$_apiBase/cms/vod/search3?os=android';
      final body = jsonEncode({
        'page': page,
        'pageSize': 20,
        'keyword': keyword,
        'groupId': 0,
        'groupIds': '',
        'tags': <String>[],
        'tagsSort': <int>[],
        'keywordType': 1,
        'sortType': 5,
      });

      final response = await http.post(
        Uri.parse(url),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != '0000') return [];
      return _parseList(response.body);
    } catch (_) {
      return [];
    }
  }

  // ── 推荐视频（/cms/vod/recommend）────────────────────────────────────────
  static Future<List<MovieBean>> fetchRecommend({String? groupId}) async {
    try {
      final headers = await JwtManager.getRequestHeaders();
      final url = Uri.parse('$_apiBase/cms/vod/recommend?os=android')
          .replace(queryParameters: groupId != null ? {'groupId': groupId} : null);
      final response = await http.get(url, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != '0000') return [];
      return _parseList(response.body);
    } catch (_) {
      return [];
    }
  }

  // ── 分类加载（优先从 API 动态获取，fallback 到硬编码）────────────────────
  static List<Category> _cachedCategories = categories;

  /// 尝试从 API 动态获取分类列表（/cms/sort 或 /cms/query?groupId=0）
  /// 失败时返回硬编码的默认分类
  static Future<List<Category>> fetchCategories() async {
    // 方案1：尝试 /cms/sort
    try {
      final headers = await JwtManager.getRequestHeaders();
      final response = await http
          .get(Uri.parse('$_apiBase/cms/sort?os=android'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == '0000') {
          final raw = body['data'] as List<dynamic>? ?? [];
          final list = raw
              .map((e) => e as Map<String, dynamic>)
              .map((e) => Category(
                    id:   (e['id']       ?? e['groupId'] ?? '').toString(),
                    name: (e['name']     ?? e['groupName'] ?? e['label'] ?? '').toString(),
                  ))
              .where((c) => c.name.isNotEmpty)
              .toList();
          if (list.isNotEmpty) {
            _cachedCategories = list;
            debugPrint('[ApiService] 分类已从 API 动态加载: ${list.length} 个');
            return list;
          }
        }
      }
    } catch (_) {}

    // 方案2：尝试 /cms/query?groupId=0 解析 vodClass 去重
    try {
      final headers = await JwtManager.getRequestHeaders();
      final response = await http
          .get(Uri.parse('$_apiBase/cms/query?groupId=0&page=1&os=android'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == '0000') {
          final data = body['data'] as Map<String, dynamic>? ?? {};
          final list = (data['list'] as List<dynamic>?) ?? [];
          final classSet = <String>{};
          final classMap = <String, String>{};
          for (final item in list) {
            final m = item as Map<String, dynamic>;
            final cls = (m['vodClass'] ?? '').toString();
            if (cls.isNotEmpty && !classSet.contains(cls)) {
              classSet.add(cls);
              classMap[cls] = cls;
            }
          }
          if (classSet.length >= 3) {
            _cachedCategories = classMap.entries
                .map((e) => Category(id: e.key, name: e.value))
                .toList();
            debugPrint('[ApiService] 分类已从视频列表推断: ${_cachedCategories.length} 个');
            return _cachedCategories;
          }
        }
      }
    } catch (_) {}

    // Fallback: 使用硬编码分类
    debugPrint('[ApiService] 动态加载分类失败，使用硬编码默认分类');
    return categories;
  }

  /// 获取当前可用分类列表
  static List<Category> get activeCategories => _cachedCategories;

  // ── CDN URL 解析 ─────────────────────────────────────────────────────────

  static const _m3u8Cdn = 'https://qaes3u8.gmdalian.com';
  static const _tsCdn   = 'https://qaes3tx.gmdalian.com';

  /// 解析封面图 URL（拼接 picBaseUrl）
  static String resolveCoverUrl(String rawCover) {
    if (rawCover.startsWith('http')) return rawCover;
    final needsSlash = !rawCover.startsWith('/');
    return '$_picBaseUrl${needsSlash ? '/' : ''}$rawCover';
  }

  /// 解析 m3u8 播放地址
  static String resolvePlayUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    final clean = relativeUrl.startsWith('/') ? relativeUrl : '/$relativeUrl';
    return '$_apiBase$clean';
  }

  // ── CDN 请求头 ───────────────────────────────────────────────────────────

  /// 图片 CDN 请求头（含 Referer 防盗链）
  static Map<String, String> imageHeaders() => {
    'User-Agent': 'okhttp/3.12.0',
    'Referer': 'https://bkij1.aemtpwbdn3xf7b.xyz/',
  };

  /// m3u8 索引文件请求头
  static Map<String, String> m3u8Headers() => {
    'User-Agent': 'okhttp/3.12.0',
    'Referer': _m3u8Cdn,
    'accessToken': 'FPCO3HQRBC3UNPSUH526WU0GF3KOI640',
    'version': '9.9.9',
  };

  /// ts / AES 密钥 CDN 请求头
  static Map<String, String> tsHeaders() => {
    'User-Agent': 'okhttp/3.12.0',
    'Referer': _tsCdn,
    'accessToken': 'FPCO3HQRBC3UNPSUH526WU0GF3KOI640',
    'version': '9.9.9',
  };

  // ── 内部解析 ─────────────────────────────────────────────────────────────
  static List<MovieBean> _parseList(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>? ?? {};
    final list = (data['list'] as List<dynamic>?) ?? [];
    return list.map((e) => MovieBean.fromJson(e as Map<String, dynamic>)).toList();
  }

  static MovieBean? _parseDetail(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    final vod = body['result']?['vod'] as Map<String, dynamic>?;
    if (vod == null) return null;
    return MovieBean.fromJson({'vod': vod});
  }
}

// ─── 数据类 ──────────────────────────────────────────────────────────────────

class Category {
  final String id;
  final String name;
  const Category({required this.id, required this.name});
}