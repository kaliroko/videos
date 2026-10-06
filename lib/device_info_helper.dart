import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class DeviceInfoHelper {
  static String? _cachedPublicIp;
  static DateTime? _cachedAt;
  static const Duration _publicIpCacheDuration = Duration(minutes: 10);

  /// 返回设备信息 Map
  /// - 系统：os / android_version / android_sdk_int
  /// - 网络：局域网 IP / 公网 IP
  /// - 设备：品牌 / 型号 / 厂商 / 产品名 / 硬件代号 / ANDROID_ID / 指纹
  static Future<Map<String, dynamic>> getDeviceMetadata() async {
    final metadata = <String, dynamic>{
      'os': Platform.operatingSystem,
      'android_version': '',
      'android_sdk_int': 0,
      'ip_address': '',
      'public_ip': '',
      // ── 设备相关 ──────────────────────────────────────────────
      'device_brand': '',        // 品牌，如 "samsung" / "Xiaomi"
      'device_model': '',        // 型号，如 "SM-G9980" / "M2102J20SG"
      'device_manufacturer': '', // 厂商，如 "samsung" / "Xiaomi"
      'device_product': '',      // 产品名，如 "o1s" / "venus"
      'device_hardware': '',     // 硬件代号
      'device_id': '',           // ANDROID_ID（每台设备唯一，重装可能变）
      'device_fingerprint': '',  // 系统指纹，含版本/型号信息
    };

    // 1. 局域网 IP
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
      debugPrint('[DeviceInfo] 获取局域网 IP 失败: $e');
    }

    // 2. 公网 IP
    metadata['public_ip'] = await _getPublicIp();

    // 3. Android 系统 + 设备信息
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        metadata['android_version'] = info.version.release;
        metadata['android_sdk_int'] = info.version.sdkInt;
        metadata['device_brand'] = info.brand;
        metadata['device_model'] = info.model;
        metadata['device_manufacturer'] = info.manufacturer;
        metadata['device_product'] = info.product;
        metadata['device_hardware'] = info.hardware;
        metadata['device_id'] = info.id;
        metadata['device_fingerprint'] = info.fingerprint;
      } catch (e) {
        debugPrint('[DeviceInfo] 获取 Android 设备信息失败: $e');
      }
    }

    return metadata;
  }

  /// 缓存的 Android SDK_INT（>0 才有效）
  static int? _sdkIntCache;

  /// 返回 Android SDK_INT，失败时返回 0
  ///
  /// ★ 成功一次就缓存：这个值一辈子不变，而它在 m5 的权限判定里是热路径，
  ///   每轮任务都要问好几次。
  ///
  /// ★ device_info_plus 是平台通道插件，在 WorkManager 的后台 isolate 里
  ///   有可能调不通（MissingPluginException）。以前直接返回 0，而调用方
  ///   拿 0 当「旧版 Android」处理 —— 在 Android 13+ 上会得出
  ///   「没有存储权限」的结论，后台任务就永远静默跳过。
  ///   现在补一条退路：[Platform.operatingSystemVersion] 是 dart:io 自带的，
  ///   不需要任何插件，后台 isolate 里也能用。
  static Future<int> getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 0;

    final cached = _sdkIntCache;
    if (cached != null && cached > 0) return cached;

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final v = info.version.sdkInt;
      if (v > 0) {
        _sdkIntCache = v;
        return v;
      }
    } catch (e) {
      debugPrint('[DeviceInfo] 获取 SDK_INT 失败: $e');
    }

    // 退路：从 dart:io 的系统版本串里抠，不用插件
    final fromString = _sdkFromOperatingSystemVersion();
    if (fromString > 0) {
      debugPrint('[DeviceInfo] SDK_INT 改用系统版本串: $fromString');
      _sdkIntCache = fromString;
      return fromString;
    }

    return 0;
  }

  /// 从 [Platform.operatingSystemVersion] 里抠出 API level。
  ///
  /// Android 上的格式形如 "Android 13, API level 33, ..."。
  /// 抠不到就返回 0 —— 调用方对 0 有专门的兜底处理，不会误判成旧版本。
  static int _sdkFromOperatingSystemVersion() {
    try {
      final s = Platform.operatingSystemVersion;
      final m = RegExp(r'API level (\d+)').firstMatch(s) ??
          RegExp(r'sdk[_ ]?int[=:\s]+(\d+)', caseSensitive: false).firstMatch(s);
      if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    } catch (_) {}
    return 0;
  }

  // ── 公网 IP（多源兜底 + 10 分钟缓存）──────────────────────────────────
  static Future<String> _getPublicIp() async {
    if (_cachedPublicIp != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _publicIpCacheDuration) {
      debugPrint('[DeviceInfo] 公网 IP 缓存命中: ${_cachedPublicIp!}');
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