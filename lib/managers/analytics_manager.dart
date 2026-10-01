/// 用户行为统计管理器（Supabase）
/// - 上报 App 打开记录（含设备信息 + 公网 IP + 地理位置）
library;

import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // ══════════════════════════════════════════════════════
  // Supabase 配置
  // ══════════════════════════════════════════════════════
  static const String _supabaseUrl =
      'https://ctqeylyblqwpxcrcqljn.supabase.co';
  static const String _supabaseAnonKey =
      'sb_publishable_KGaFq3VQ4vKUo98Vvi2yzA_DxxjMuHZ';
  // ══════════════════════════════════════════════════════

  String? _deviceId;
  String? get deviceId => _deviceId;

  bool _initialized = false;

  // IP 信息缓存（10 分钟）
  IpInfo? _cachedIpInfo;
  DateTime? _cachedAt;
  static const Duration _ipCacheDuration = Duration(minutes: 10);

  /// 初始化 Supabase（在 main 里调用一次）
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );

      final info = await DeviceInfoPlugin().androidInfo;
      _deviceId = info.id;

      _initialized = true;
      debugPrint('[Analytics] ✅ 初始化完成, deviceId=$_deviceId');
    } catch (e) {
      debugPrint('[Analytics] ❌ 初始化失败: $e');
    }
  }

  /// 上报"打开 App"
  Future<void> reportAppOpen() async {
    if (!_initialized) {
      debugPrint('[Analytics] 未初始化，跳过上报');
      return;
    }

    try {
      final pkg = await PackageInfo.fromPlatform();
      final info = await DeviceInfoPlugin().androidInfo;
      final ipInfo = await _getIpInfo();

      await Supabase.instance.client.from('app_opens').insert({
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
          '(IP=${ipInfo.ip}, 城市=${ipInfo.city}, '
          '地区=${ipInfo.region}, 运营商=${ipInfo.isp})');
    } catch (e) {
      debugPrint('[Analytics] ❌ 上报失败: $e');
    }
  }

  // ══════════════════════════════════════════════════════
  // 公网 IP + 地理位置（ip-api.com，免费，无需 token）
  // ══════════════════════════════════════════════════════
  Future<IpInfo> _getIpInfo() async {
    // 缓存命中
    if (_cachedIpInfo != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _ipCacheDuration) {
      debugPrint('[Analytics] IP 信息缓存命中: ${_cachedIpInfo!.ip}');
      return _cachedIpInfo!;
    }

    try {
      final resp = await http
          .get(Uri.parse('http://ip-api.com/json/?lang=zh-CN'))
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
        debugPrint('[Analytics] ip-api 返回失败: ${data['message']}');
      } else {
        debugPrint('[Analytics] ip-api HTTP ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[Analytics] ip-api 请求失败: $e');
    }

    // 兜底：只拿 IP
    final fallbackIp = await _getFallbackIp();
    if (fallbackIp.isNotEmpty) {
      final info = IpInfo(ip: fallbackIp);
      _cachedIpInfo = info;
      _cachedAt = DateTime.now();
      return info;
    }

    return IpInfo.empty;
  }

  /// 兜底：多源查 IP（不带城市）
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
      } catch (_) {
        // 尝试下一个
      }
    }

    debugPrint('[Analytics] ⚠️ 所有 IP 服务均失败');
    return '';
  }

  // ── IP 校验 ───────────────────────────────────────────
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