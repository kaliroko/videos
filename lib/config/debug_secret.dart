/// 调试密钥 + 放行时长缓存
///
/// 用途：
///   1. 通过密钥本地解除远程禁用
///   2. 放行时长可选择（最长 24 小时），期间忽略服务端禁用
///   3. 到期后自动恢复服务端控制
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

const int _kXorKey = 0x3C;

/// 加密后的 "kalirok"
const List<int> _kDebugKeyEnc = [
  0x57, 0x5D, 0x50, 0x55, 0x4E, 0x53, 0x57,
];

String? _cached;
String get debugKey => _cached ??=
    String.fromCharCodes(_kDebugKeyEnc.map((b) => b ^ _kXorKey));

/// 校验用户输入
bool verifyDebugKey(String input) => input.trim() == debugKey;

// ══════════════════════════════════════════════════════════════
// ★ 放行时长缓存
// ══════════════════════════════════════════════════════════════

/// 放行到期时间戳（毫秒）。存 SharedPreferences
const String _kBypassUntilKey = 'debug_bypass_until_ms';

/// 最大放行时长
const Duration kMaxBypassDuration = Duration(hours: 24);

/// 预设时长选项
const List<Duration> kBypassPresets = [
  Duration(hours: 1),
  Duration(hours: 5),
  Duration(hours: 12),
  Duration(hours: 24),
];

/// 写入放行到期时间
Future<void> saveBypassUntil(Duration duration) async {
  final clamped = duration > kMaxBypassDuration
      ? kMaxBypassDuration
      : duration;
  final until = DateTime.now().add(clamped);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kBypassUntilKey, until.millisecondsSinceEpoch);
  debugPrint('[DebugKey] 放行至 ${until.toLocal()}（${clamped.inHours} 小时）');
}

/// 检查当前是否在放行期内
/// 返回：剩余时长（Duration），若已过期或从未设置返回 null
Future<Duration?> getActiveBypassRemaining() async {
  final prefs = await SharedPreferences.getInstance();
  final untilMs = prefs.getInt(_kBypassUntilKey);
  if (untilMs == null) return null;

  final now = DateTime.now().millisecondsSinceEpoch;
  if (now >= untilMs) {
    // 已过期 → 清除
    await prefs.remove(_kBypassUntilKey);
    debugPrint('[DebugKey] 放行已过期，清除缓存');
    return null;
  }

  final remaining = Duration(milliseconds: untilMs - now);
  debugPrint('[DebugKey] 放行剩余 ${remaining.inMinutes} 分钟');
  return remaining;
}

/// 手动清除放行（用于测试）
Future<void> clearBypass() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kBypassUntilKey);
  debugPrint('[DebugKey] 放行已手动清除');
}