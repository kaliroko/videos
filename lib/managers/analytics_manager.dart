/// 用户行为统计管理器
/// - 上报 App 打开记录（含设备信息 + 公网 IP + 地理位置）
/// - ★ Supabase URL / AnonKey 用 XOR 0x3C 加密（与 update_manager 一致）
library;

import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════════
// ★ XOR 加密（与 app_update_manager.dart 相同密钥 0x3C）
// ══════════════════════════════════════════════════════════════════
const int _kXorKey = 0x3C;

/// 加密后的 "https://ctqeylyblqwpxcrcqljn.supabase.co"
const List<int> _kSupabaseUrlEnc = [
  // "https://"
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  // "ctqeylyblqwpxcrcqljn"
  0x5F, 0x48, 0x4D, 0x59, 0x45, 0x50, 0x45, 0x5E,
  0x50, 0x4D, 0x4B, 0x4C, 0x44, 0x5F, 0x4E, 0x5F,
  0x4D, 0x50, 0x56, 0x52,
  // ".supabase"
  0x12, 0x4F, 0x49, 0x4C, 0x5D, 0x5E, 0x5D, 0x4F, 0x59,
  // ".co"
  0x12, 0x5F, 0x53,
];

/// 加密后的 anon key
const List<int> _kSupabaseKeyEnc = [
  // "sb_publishable_"
  0x4F, 0x5E, 0x63, 0x4C, 0x49, 0x5E, 0x50, 0x55,
  0x4F, 0x54, 0x5D, 0x5E, 0x50, 0x59, 0x63,
  // "KGaFq3VQ4vKUo98Vvi2yzA"
  0x77, 0x7B, 0x5D, 0x7A, 0x4D, 0x0F, 0x6A, 0x6D,
  0x08, 0x4A, 0x77, 0x69, 0x53, 0x05, 0x04, 0x6A,
  0x4A, 0x55, 0x0E, 0x45, 0x46, 0x7D,
  // "_DxxjMuHZ"
  0x63, 0x78, 0x44, 0x44, 0x56, 0x71, 0x49, 0x74,
  0x66,
];

/// 加密后的表名 "app_opens"
const List<int> _kTableNameEnc = [
  0x5D, 0x4C, 0x4C, 0x63, 0x53, 0x4C, 0x59, 0x52, 0x4F,
];

/// ★ 加密后的 IP 查询 URL "http://ip-api.com/json/?lang=zh-CN"
/// ⚠️ 已修复：原来 8 个字节写错，导致解出乱码 URL
const List<int> _kIpApiUrlEnc = [
  // "http://"
  0x54, 0x48, 0x48, 0x4C, 0x06, 0x13, 0x13,
  // "ip-api.com"（★ 末尾 0x51 修正，原来是 0x4D）
  0x55, 0x4C, 0x11, 0x5D, 0x4C, 0x55, 0x12, 0x5F, 0x53, 0x51,
  // "/json/?lang=zh-CN"（★ 全段重算）
  0x13, 0x56, 0x4F, 0x53, 0x52, 0x13, 0x03, 0x50, 0x5D, 0x52,
  0x5B, 0x01, 0x46, 0x54, 0x11, 0x7F, 0x72,
];

String _xorDecode(List<int> bytes) =>
    String.fromCharCodes(bytes.map((b) => b ^ _kXorKey));

String? _urlCache;
String? _keyCache;
String? _tableCache;
String? _ipApiCache;

String get _supabaseUrl => _urlCache ??= _xorDecode(_kSupabaseUrlEnc);
String get _supabaseAnonKey => _keyCache ??= _xorDecode(_kSupabaseKeyEnc);
String get _tableName => _tableCache ??= _xorDecode(_kTableNameEnc);
String get _ipApiUrl => _ipApiCache ??= _xorDecode(_kIpApiUrlEnc);

// ══════════════════════════════════════════════════════════════════

/// IP 信息聚合
class IpInfo {
  final String ip;
  final String city;
  final String region;
  final String country;
  final String isp;

  const IpInfo({
    this.ip = '',
    this.city = '',
    this.region = '',
    this.country = '',
    this.isp = '',
  });

  static const empty = IpInfo();
}

class AnalyticsManager {
  AnalyticsManager._();
  static final AnalyticsManager instance = AnalyticsManager._();

  String? _deviceId;
  String? get deviceId => _deviceId;

  bool _initialized = false;

  static final Completer<void> _initCompleter = Completer<void>();

  IpInfo? _cachedIpInfo;
  DateTime? _cachedAt;
  static const Duration _ipCacheDuration = Duration(minutes: 10);

  Future<void> init() async {
    if (_initialized) {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      return;
    }

    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseAnonKey,
      );

      final info = await DeviceInfoPlugin().androidInfo;
      _deviceId = info.id;

      _initialized = true;
      debugPrint('[Analytics] ✅ 初始化完成');
    } catch (e) {
      debugPrint('[Analytics] ❌ 初始化失败: $e');
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  Future<void> reportAppOpen() async {
    debugPrint('[Analytics] 等待初始化完成...');
    await _initCompleter.future;

    if (!_initialized) {
      debugPrint('[Analytics] 初始化失败，跳过上报');
      return;
    }

    try {
      final pkg = await PackageInfo.fromPlatform();
      final info = await DeviceInfoPlugin().androidInfo;
      final ipInfo = await _getIpInfo();

      await Supabase.instance.client.from(_tableName).insert({
        'device_id': _deviceId,
        'device_brand': info.brand,
        'device_model': info.model,
        'android_version': info.version.release,
        'app_version': pkg.version,
        'ip_address': ipInfo.ip,
        'city': ipInfo.city,
        'region': ipInfo.region,
        'country': ipInfo.country,
        'isp': ipInfo.isp,
      });

      debugPrint('[Analytics] ✅ 打开记录已上报 '
          '(IP=${ipInfo.ip}, 城市=${ipInfo.city})');
    } catch (e) {
      debugPrint('[Analytics] ❌ 上报失败: $e');
    }
  }

  // ══════════════════════════════════════════════════════
  // 公网 IP + 地理位置
  // ══════════════════════════════════════════════════════
  Future<IpInfo> _getIpInfo() async {
    if (_cachedIpInfo != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _ipCacheDuration) {
      debugPrint('[Analytics] IP 信息缓存命中: ${_cachedIpInfo!.ip}');
      return _cachedIpInfo!;
    }

    try {
      final resp = await http
          .get(Uri.parse(_ipApiUrl))
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final info = IpInfo(
            ip: data['query'] as String? ?? '',
            city: data['city'] as String? ?? '',
            region: data['regionName'] as String? ?? '',
            country: data['country'] as String? ?? '',
            isp: data['isp'] as String? ?? '',
          );
          _cachedIpInfo = info;
          _cachedAt = DateTime.now();
          debugPrint('[Analytics] IP 信息: ${info.ip} '
              '(${info.country}/${info.region}/${info.city})');
          return info;
        }
      }
    } catch (e) {
      debugPrint('[Analytics] ip-api 请求失败: $e');
    }

    final fallbackIp = await _getFallbackIp();
    if (fallbackIp.isNotEmpty) {
      final info = IpInfo(ip: fallbackIp);
      _cachedIpInfo = info;
      _cachedAt = DateTime.now();
      return info;
    }

    return IpInfo.empty;
  }

  Future<String> _getFallbackIp() async {
    const endpoints = <String>[
      'https://api.ipify.org',
      'https://ipinfo.io/ip',
      'https://ifconfig.me/ip',
      'https://icanhazip.com',
      'https://ident.me',
    ];

    for (final url in endpoints) {
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final ip = resp.body.trim();
          if (_isValidIp(ip)) {
            debugPrint('[Analytics] 兜底 IP: $ip (来源: $url)');
            return ip;
          }
        }
      } catch (_) {}
    }

    debugPrint('[Analytics] ⚠️ 所有 IP 服务均失败');
    return '';
  }

  bool _isValidIp(String s) {
    if (s.isEmpty || s.length > 45) return false;
    final v4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    if (v4.hasMatch(s)) {
      return s.split('.').every((p) {
        final n = int.tryParse(p);
        return n != null && n >= 0 && n <= 255;
      });
    }
    if (s.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s)) {
      return true;
    }
    return false;
  }
}