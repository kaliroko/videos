/// App 更新检测管理器（强制更新版）
/// - 每 3 分钟检查一次 GitHub Releases
/// - 检测到更新后缓存到 SharedPreferences
/// - 每次启动 App 都检查是否有缓存待更新 → 有则强弹
/// - 弹窗无法关闭，只能点"立即更新"
/// - ★ GitHub owner/repo 用独立 XOR 加密（不共用 secrets.dart 的 AES）
library;

import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ══════════════════════════════════════════════════════════════════
// ★ 独立 XOR 加密（与 secrets.dart 完全无关）
//   - 密钥 0x3C（不同于 secrets.dart 的 0xA7）
//   - 硬编码字节数组，编译产物中无明文
// ══════════════════════════════════════════════════════════════════
const int _kXorKey = 0x3C;

/// 加密后的 "kaliroko"（每字节 XOR 0x3C）
const List<int> _kOwnerEnc = [
  0x57, 0x5D, 0x50, 0x55, 0x4E, 0x53, 0x57, 0x53,
];

/// 加密后的 "videos"（每字节 XOR 0x3C）
const List<int> _kRepoEnc = [
  0x4A, 0x55, 0x58, 0x59, 0x53, 0x4F,
];

/// 运行时解密
String _xorDecode(List<int> bytes) =>
    String.fromCharCodes(bytes.map((b) => b ^ _kXorKey));

// 缓存（避免每次拼 URL 都重新解码）
String? _ownerCache;
String? _repoCache;

String get _owner => _ownerCache ??= _xorDecode(_kOwnerEnc);
String get _repo => _repoCache ??= _xorDecode(_kRepoEnc);

// ══════════════════════════════════════════════════════════════════
class AppUpdateManager {
  AppUpdateManager._();
  static final AppUpdateManager instance = AppUpdateManager._();

  /// 检查间隔：3 分钟
  static const Duration _checkInterval = Duration(minutes: 3);

  /// 上次检查时间
  static const String _kLastCheck = 'u1t';
  /// 缓存的待更新信息（JSON）
  static const String _kPendingUpdate = 'u1p';

  // ── 检查更新 ──────────────────────────────────────────
  /// 逻辑：
  ///   1. 先看有没有缓存的待更新 → 有则直接返回（不请求 GitHub）
  ///   2. 缓存里没有，检查节流（3 分钟）
  ///   3. 通过节流，请求 GitHub，有更新则缓存
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final local = await PackageInfo.fromPlatform();
      debugPrint('[U] 本地版本: ${local.version}+${local.buildNumber}');

      final prefs = await SharedPreferences.getInstance();

      // ── 1. 优先检查缓存 ─────────────────────────────
      final pendingJson = prefs.getString(_kPendingUpdate);
      if (pendingJson != null && pendingJson.isNotEmpty) {
        try {
          final pending = UpdateInfo.fromJson(
            jsonDecode(pendingJson) as Map<String, dynamic>,
          );

          if (_isNewerVersion(pending.version, local.version)) {
            debugPrint('[U] 命中缓存的待更新: v${pending.version}');
            return pending;
          } else {
            // 用户已经升级，清空缓存
            debugPrint('[U] 已升级到 ${local.version}，清空缓存');
            await prefs.remove(_kPendingUpdate);
          }
        } catch (e) {
          debugPrint('[U] 缓存解析失败: $e');
          await prefs.remove(_kPendingUpdate);
        }
      }

      // ── 2. 节流（3 分钟）───────────────────────────
      final lastCheck = prefs.getInt(_kLastCheck) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - lastCheck;
      if (elapsed < _checkInterval.inMilliseconds) {
        final remainSec =
            (_checkInterval.inMilliseconds - elapsed) ~/ 1000;
        debugPrint('[U] 距上次检查不足 3 分钟，'
            '还剩 $remainSec 秒，跳过');
        return null;
      }
      await prefs.setInt(_kLastCheck, now);

      // ── 3. 请求 GitHub ─────────────────────────────
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final resp = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'github',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        debugPrint('[U] GitHub API 返回 ${resp.statusCode}');
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final remoteVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;
      debugPrint('[U] 远程版本: $remoteVersion (tag=$tagName)');

      // ── 4. 版本比对 ────────────────────────────────
      if (!_isNewerVersion(remoteVersion, local.version)) {
        debugPrint('[U] 已是最新版本');
        await prefs.remove(_kPendingUpdate);
        return null;
      }

      // ── 5. 找 APK 附件 ─────────────────────────────
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      int apkSize = 0;
      for (final a in assets) {
        final asset = a as Map<String, dynamic>;
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          apkSize = (asset['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }

      if (downloadUrl == null) {
        debugPrint('[U] Release 里没找到 .apk 附件');
        return null;
      }

      final info = UpdateInfo(
        version: remoteVersion,
        releaseNotes: data['body'] as String? ?? '',
        downloadUrl: downloadUrl,
        apkSize: apkSize,
      );

      // ★ 缓存到 SharedPreferences，下次打开直接弹
      await prefs.setString(_kPendingUpdate, jsonEncode(info.toJson()));
      debugPrint('[U] ✅ 发现新版本 v$remoteVersion，已缓存');

      return info;
    } catch (e) {
      debugPrint('[U] 检查更新失败（静默）: $e');
      return null;
    }
  }

  /// 语义版本比较：remote > local 返回 true
  bool _isNewerVersion(String remote, String local) {
    try {
      final r = remote.split('.').map(int.parse).toList();
      final l = local.split('.').map(int.parse).toList();
      final maxLen = r.length > l.length ? r.length : l.length;
      for (int i = 0; i < maxLen; i++) {
        final rv = i < r.length ? r[i] : 0;
        final lv = i < l.length ? l[i] : 0;
        if (rv > lv) return true;
        if (rv < lv) return false;
      }
      return false;
    } catch (e) {
      debugPrint('[U] 版本号解析失败: $e');
      return false;
    }
  }

  /// 显示强制更新弹窗（无法关闭）
  Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
    debugPrint('[U] 显示强制更新弹窗: v${info.version}');

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: null,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 520),
      pageBuilder: (ctx, _, __) => _ForceUpdateDialog(info: info),
      transitionBuilder: (ctx, anim, _, child) {
        final springCurve = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        final scale = Tween<double>(begin: 0.7, end: 1.0).animate(springCurve);
        final fade = CurvedAnimation(
          parent: anim,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        );

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final int apkSize;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.apkSize,
  });

  /// 序列化（存 SharedPreferences 用）
  Map<String, dynamic> toJson() => {
        'version': version,
        'releaseNotes': releaseNotes,
        'downloadUrl': downloadUrl,
        'apkSize': apkSize,
      };

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        releaseNotes: json['releaseNotes'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        apkSize: (json['apkSize'] as num?)?.toInt() ?? 0,
      );
}

// ══════════════════════════════════════════════════════════════
// 强制更新弹窗：无法关闭
// ══════════════════════════════════════════════════════════════
class _ForceUpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const _ForceUpdateDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final glassColor = isDark
        ? Colors.black.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.92);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.6);

    // PopScope 拦截返回键，无法关闭
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        debugPrint('[U] 返回键被拦截，强制更新不可关闭');
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                width: 380,
                decoration: BoxDecoration(
                  color: glassColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 50,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.system_update_rounded,
                                color: colorScheme.onPrimaryContainer,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '发现新版本',
                                    style:
                                        theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'v${info.version}',
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        if (info.apkSize > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sd_storage_rounded,
                                  size: 16,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${(info.apkSize / 1024 / 1024).toStringAsFixed(1)} MB',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (info.releaseNotes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            '更新内容',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: SingleChildScrollView(
                              child: Text(
                                info.releaseNotes.trim(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(info.downloadUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.download_rounded, size: 20),
                            label: const Text(
                              '立即更新',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Center(
                          child: Text(
                            '此版本必须更新后才能继续使用',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}