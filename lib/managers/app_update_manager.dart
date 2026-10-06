/// App 更新检测管理器（强制更新版 + 架构感知）
/// - 每 3 分钟检查一次 GitHub Releases
/// - ★ 按设备 ABI 过滤 release，避免 32 位用户被强制装 64 位版本
/// - 检测到更新后缓存到 SharedPreferences
/// - 每次启动 App 都检查是否有缓存待更新 → 有则强弹
/// - 弹窗无法关闭，只能点"立即更新"
/// - ★ GitHub owner/repo 用独立 XOR 加密（不共用 secrets.dart 的 AES）
library;

import 'dart:convert';
import 'dart:ffi' show Abi;          // ★ 新增：检测设备架构
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/springs.dart';

// ══════════════════════════════════════════════════════════════════
// ★ 独立 XOR 加密（与 secrets.dart 完全无关）
// ══════════════════════════════════════════════════════════════════
const int _kXorKey = 0x3C;

/// 加密后的 "kaliroko"
const List<int> _kOwnerEnc = [
  0x57, 0x5D, 0x50, 0x55, 0x4E, 0x53, 0x57, 0x53,
];

/// 加密后的 "videos"
const List<int> _kRepoEnc = [
  0x4A, 0x55, 0x58, 0x59, 0x53, 0x4F,
];

String _xorDecode(List<int> bytes) =>
    String.fromCharCodes(bytes.map((b) => b ^ _kXorKey));

String? _ownerCache;
String? _repoCache;

String get _owner => _ownerCache ??= _xorDecode(_kOwnerEnc);
String get _repo => _repoCache ??= _xorDecode(_kRepoEnc);

// ══════════════════════════════════════════════════════════════════
class AppUpdateManager {
  AppUpdateManager._();
  static final AppUpdateManager instance = AppUpdateManager._();

  static const Duration _checkInterval = Duration(minutes: 3);

  static const String _kLastCheck = 'u1t';
  static const String _kPendingUpdate = 'u1p';

  // ══════════════════════════════════════════════════════════════
  // ★ 架构检测
  // ══════════════════════════════════════════════════════════════
  /// 当前 App 运行的 ABI 对应的后缀：`arm32` 或 `arm64`
  ///
  /// - `Abi.androidArm`   → 32 位 ARM  (armeabi-v7a)
  /// - `Abi.androidArm64` → 64 位 ARM  (arm64-v8a)
  /// - 其它（x86/x64）→ 兜底走 arm64
  static String get archSuffix {
    try {
      final abi = Abi.current();
      if (abi == Abi.androidArm) return 'arm32';
      return 'arm64';
    } catch (e) {
      debugPrint('[U] Abi.current() 失败，默认 arm64: $e');
      return 'arm64';
    }
  }

  // ── 检查更新 ──────────────────────────────────────────
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final local = await PackageInfo.fromPlatform();
      final myArch = archSuffix;
      debugPrint('[U] 本地版本: ${local.version}+${local.buildNumber}, '
          '架构: $myArch');

      final prefs = await SharedPreferences.getInstance();

      // ── 1. 优先检查缓存 ─────────────────────────────
      final pendingJson = prefs.getString(_kPendingUpdate);
      if (pendingJson != null && pendingJson.isNotEmpty) {
        try {
          final pending = UpdateInfo.fromJson(
            jsonDecode(pendingJson) as Map<String, dynamic>,
          );

          // ★ 缓存也要匹配架构（防止旧缓存污染）
          if (pending.arch == myArch &&
              _isNewerVersion(pending.version, local.version)) {
            debugPrint('[U] 命中缓存的待更新: '
                'v${pending.version} ($myArch)');
            return pending;
          } else {
            debugPrint('[U] 缓存不匹配/已升级，清空缓存');
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
        debugPrint('[U] 距上次检查不足 3 分钟，还剩 $remainSec 秒，跳过');
        return null;
      }
      await prefs.setInt(_kLastCheck, now);

      // ── 3. ★ 请求 GitHub Releases 列表（不是 /latest）
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases?per_page=30',
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

      final releases = jsonDecode(resp.body) as List<dynamic>;
      debugPrint('[U] 拉取到 ${releases.length} 个 release');

      // ── 4. ★ 过滤当前架构的 release
      final myReleases = <Map<String, dynamic>>[];
      for (final r in releases) {
        final rel = r as Map<String, dynamic>;
        final tag = rel['tag_name'] as String? ?? '';
        if (_tagMatchesArch(tag, myArch)) {
          myReleases.add(rel);
        }
      }

      if (myReleases.isEmpty) {
        debugPrint('[U] 没找到 $myArch 的 release，跳过');
        return null;
      }

      // 按版本号降序排（不依赖 GitHub 时间排序）
      myReleases.sort((a, b) {
        final va = _parseVersion(a['tag_name'] as String? ?? '');
        final vb = _parseVersion(b['tag_name'] as String? ?? '');
        return _compareVersions(vb, va);
      });

      final latest = myReleases.first;
      final tagName = latest['tag_name'] as String? ?? '';
      final remoteVersion = _stripTag(tagName);
      debugPrint('[U] 远程版本: $remoteVersion (tag=$tagName, arch=$myArch)');

      // ── 5. 版本比对 ────────────────────────────────
      if (!_isNewerVersion(remoteVersion, local.version)) {
        debugPrint('[U] 已是最新版本');
        await prefs.remove(_kPendingUpdate);
        return null;
      }

      // ── 6. ★ 找 APK 附件（优先匹配架构后缀）
      final assets = latest['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      int apkSize = 0;

      // 第一轮：优先带架构名的 APK
      for (final a in assets) {
        final asset = a as Map<String, dynamic>;
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk') && name.contains(myArch)) {
          downloadUrl = asset['browser_download_url'] as String?;
          apkSize = (asset['size'] as num?)?.toInt() ?? 0;
          debugPrint('[U] 命中架构匹配 APK: $name');
          break;
        }
      }

      // 第二轮兜底：任意 APK（兼容旧 release 命名）
      if (downloadUrl == null) {
        for (final a in assets) {
          final asset = a as Map<String, dynamic>;
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String?;
            apkSize = (asset['size'] as num?)?.toInt() ?? 0;
            debugPrint('[U] 使用兜底 APK: $name');
            break;
          }
        }
      }

      if (downloadUrl == null) {
        debugPrint('[U] Release 里没找到 .apk 附件');
        return null;
      }

      final info = UpdateInfo(
        version: remoteVersion,
        releaseNotes: latest['body'] as String? ?? '',
        downloadUrl: downloadUrl,
        apkSize: apkSize,
        arch: myArch,   // ★ 记下架构
      );

      await prefs.setString(_kPendingUpdate, jsonEncode(info.toJson()));
      debugPrint('[U] ✅ 发现新版本 v$remoteVersion ($myArch)，已缓存');

      return info;
    } catch (e) {
      debugPrint('[U] 检查更新失败（静默）: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ★ tag 与架构匹配
  // ══════════════════════════════════════════════════════════════
  /// tag 是否符合指定架构：
  /// - arm32 → 必须以 `-arm32` 结尾
  /// - arm64 → 以 `-arm64` 结尾，**或**无后缀（兼容旧 tag）
  bool _tagMatchesArch(String tag, String arch) {
    if (!tag.startsWith('v')) return false;
    if (arch == 'arm32') {
      return tag.endsWith('-arm32');
    }
    // arm64
    return tag.endsWith('-arm64') || !tag.endsWith('-arm32');
  }

  /// v1.0.0.123-arm32 → 1.0.0.123
  String _stripTag(String tag) {
    var v = tag.startsWith('v') ? tag.substring(1) : tag;
    for (final suffix in const ['-arm32', '-arm64']) {
      if (v.endsWith(suffix)) {
        v = v.substring(0, v.length - suffix.length);
        break;
      }
    }
    return v;
  }

  List<int> _parseVersion(String tag) {
    final v = _stripTag(tag);
    try {
      return v.split('.').map(int.parse).toList();
    } catch (_) {
      return [0];
    }
  }

  int _compareVersions(List<int> a, List<int> b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < maxLen; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av > bv) return 1;
      if (av < bv) return -1;
    }
    return 0;
  }

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
    debugPrint('[U] 显示强制更新弹窗: v${info.version} (${info.arch})');

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: null,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 520),
      pageBuilder: (ctx, _, __) => _ForceUpdateDialog(info: info),
      // ★ 原来这里用 Curves.easeOutBack 把 0.7→1.0 拉出来，看着像弹簧，
      //   其实过冲量是画死的。现在交给 _SpringEnter 自己跑弹簧 ——
      //   路由的 transitionDuration 只留给背后遮罩的淡入用。
      transitionBuilder: (ctx, anim, _, child) =>
          _SpringEnter(child: child),
    );
  }
}

// ══════════════════════════════════════════════════════════════
/// 弹簧进场的包装器。
///
/// showGeneralDialog 塞进来的 anim 是 transitionDuration 驱动的**补间**，
/// 想吃弹簧就只能不用它 —— 这里自己起一个 unbounded 控制器跑 0→1。
class _SpringEnter extends StatefulWidget {
  const _SpringEnter({required this.child});

  final Widget? child;

  @override
  State<_SpringEnter> createState() => _SpringEnterState();
}

class _SpringEnterState extends State<_SpringEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController.unbounded(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    _t.animateWith(SpringSimulation(Springs.bouncy, 0, 1, 0));
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        return Opacity(
          // 透明度只吃 0~1，过冲那截夹掉
          opacity: v.clamp(0.0, 1.0),
          // 缩放不夹：0.7 起跳，过冲时窜到 1.05 再收回来
          child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
        );
      },
      child: widget.child,
    );
  }
}

// ══════════════════════════════════════════════════════════════
class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final int apkSize;

  /// ★ 该更新对应的架构（arm32 / arm64）
  final String arch;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.apkSize,
    this.arch = 'arm64',
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'releaseNotes': releaseNotes,
        'downloadUrl': downloadUrl,
        'apkSize': apkSize,
        'arch': arch,
      };

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        releaseNotes: json['releaseNotes'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        apkSize: (json['apkSize'] as num?)?.toInt() ?? 0,
        arch: json['arch'] as String? ?? 'arm64',
      );
}

// ══════════════════════════════════════════════════════════════
// 强制更新弹窗：无法关闭（保持不变）
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
                                    'v${info.version} · ${info.arch}',
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