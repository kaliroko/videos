/// 设备信息助手
/// 获取：局域网 IP、公网 IP（多源 fallback + 10 分钟缓存）、Android 版本
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class DeviceInfoHelper {
  static String? _cachedPublicIp;
  static DateTime? _cachedAt;
  static const Duration _publicIpCacheDuration = Duration(minutes: 10);

  /// 返回设备元信息，失败时字段为空串，绝不抛异常
  static Future<Map<String, dynamic>> getDeviceMetadata() async {
    final metadata = <String, dynamic>{
      'os': Platform.operatingSystem,
      'android_version': '',
      'android_sdk_int': 0,
      'ip_address': '',
      'public_ip': '',
    };

    // 1. 局域网 IPv4
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      outer:
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            metadata['ip_address'] = addr.address;
            break outer;
          }
        }
      }
    } catch (e) {
      debugPrint('[DeviceInfo] 局域网 IP 获取失败: $e');
    }

    // 2. 公网 IP（多源 fallback + 缓存）
    metadata['public_ip'] = await _getPublicIp();

    // 3. Android 版本
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        metadata['android_version'] = info.version.release;
        metadata['android_sdk_int'] = info.version.sdkInt;
      } catch (e) {
        debugPrint('[DeviceInfo] Android 版本获取失败: $e');
      }
    }

    return metadata;
  }

  // ── 公网 IP（多源 fallback，10 分钟缓存）─────────────────────────────
  static Future<String> _getPublicIp() async {
    if (_cachedPublicIp != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _publicIpCacheDuration) {
      return _cachedPublicIp!;
    }

    const endpoints = <String>[
      'https://api.ipify.org',
      'https://ipinfo.io/ip',
      'https://ifconfig.me/ip',
      'https://icanhazip.com',
      'https://ident.me',
    ];

    for (final url in endpoints) {
      try {
        final resp =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final ip = resp.body.trim();
          if (_isValidIp(ip)) {
            _cachedPublicIp = ip;
            _cachedAt = DateTime.now();
            debugPrint('[DeviceInfo] 公网 IP: $ip (来源: $url)');
            return ip;
          }
        }
      } catch (e) {
        debugPrint('[DeviceInfo] 请求 $url 失败: $e');
      }
    }

    debugPrint('[DeviceInfo] ⚠️ 所有公网 IP 服务均失败');
    return '';
  }

  static bool _isValidIp(String s) {
    if (s.isEmpty || s.length > 45) return false;
    // IPv4
    final v4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    if (v4.hasMatch(s)) {
      return s.split('.').every((p) {
        final n = int.tryParse(p);
        return n != null && n >= 0 && n <= 255;
      });
    }
    // IPv6（粗略）
    if (s.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s)) {
      return true;
    }
    return false;
  }
}
