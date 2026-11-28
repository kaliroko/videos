/// Her Haven 本地存储 —— 私密日记 / 自慰时刻
///
/// ★ 只用 SharedPreferences 存 JSON 字符串：
///   条数少（各留最近 200 条）、结构简单，不值得上数据库。
/// ★ 全部读操作都吞异常：一条坏数据不该让整页打不开。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/haven_models.dart';

class HavenStore {
  HavenStore._();

  static const String _kPrivateDiary = 'haven.private_diary.v1';
  static const String _kMoments = 'haven.moments.v1';

  /// 每个模块最多留多少条
  static const int _kMaxEntries = 200;

  /// 读私密日记（按日期倒序）
  static Future<List<PrivateDiaryEntry>> loadPrivateDiary() async {
    final raw = await _readList(_kPrivateDiary);
    final list = <PrivateDiaryEntry>[];
    for (final m in raw) {
      try {
        list.add(PrivateDiaryEntry.fromJson(m));
      } catch (e) {
        debugPrint('[HavenStore] 跳过一条坏的日记数据: $e');
      }
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// 写私密日记（自动裁到最近 200 条）
  static Future<void> savePrivateDiary(List<PrivateDiaryEntry> entries) async {
    final sorted = List<PrivateDiaryEntry>.of(entries)
      ..sort((a, b) => b.date.compareTo(a.date));
    final bounded = sorted.length > _kMaxEntries
        ? sorted.sublist(0, _kMaxEntries)
        : sorted;
    await _writeList(
      _kPrivateDiary,
      bounded.map((e) => e.toJson()).toList(growable: false),
    );
  }

  /// 读自慰时刻（按时间倒序）
  static Future<List<MomentEntry>> loadMoments() async {
    final raw = await _readList(_kMoments);
    final list = <MomentEntry>[];
    for (final m in raw) {
      try {
        list.add(MomentEntry.fromJson(m));
      } catch (e) {
        debugPrint('[HavenStore] 跳过一条坏的自慰时刻数据: $e');
      }
    }
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  /// 写自慰时刻
  static Future<void> saveMoments(List<MomentEntry> entries) async {
    final sorted = List<MomentEntry>.of(entries)
      ..sort((a, b) => b.at.compareTo(a.at));
    final bounded = sorted.length > _kMaxEntries
        ? sorted.sublist(0, _kMaxEntries)
        : sorted;
    await _writeList(
      _kMoments,
      bounded.map((e) => e.toJson()).toList(growable: false),
    );
  }

  /// 清空本模块的所有本地数据
  static Future<void> clearLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrivateDiary);
      await prefs.remove(_kMoments);
    } catch (e) {
      debugPrint('[HavenStore] 清除失败: $e');
    }
  }

  // ── 底层 ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _readList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    } catch (e) {
      debugPrint('[HavenStore] 读取 $key 失败: $e');
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _writeList(
    String key,
    List<Map<String, dynamic>> list,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(list));
    } catch (e) {
      debugPrint('[HavenStore] 写入 $key 失败: $e');
    }
  }
}
