/// 全局用户资料（昵称 / 头像）
///
/// 首次启动的引导页写一次，之后各模块共用。
///
/// ★ 为什么要「镜像」到好几个键：
///   聊天室和日记模块在这套引导页之前就各自存了自己的键
///   （`chat_nickname` / `chat_avatar_url` / `diary_nickname`）。
///   引导页统一写 `profile_*`，同时把这些旧键一并覆盖，
///   这样老代码一行都不用改就能读到新资料。
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  UserProfile._();

  /// 引导页写的权威键
  static const String kNicknameKey = 'profile_nickname';
  static const String kAvatarKey = 'profile_avatar_url';

  /// 欢迎页是否看过。
  ///
  /// ★ 和「资料填没填」分开存：
  ///   资料填完就把人放进去的话，用户在看欢迎页时杀掉进程，
  ///   下次进来欢迎页就再也不出现了 —— 少看一段。
  ///   单独一个键，只有真的翻到最后那页才置位。
  static const String kWelcomedKey = 'profile_welcomed';

  /// 老模块自己的键，写入时一并同步
  static const List<String> _nicknameMirrors = <String>[
    'chat_nickname',
    'diary_nickname',
  ];
  static const List<String> _avatarMirrors = <String>[
    'chat_avatar_url',
  ];

  /// 昵称（可能为空）
  static Future<String> nickname() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kNicknameKey) ?? '';
    } catch (e) {
      debugPrint('[Profile] 读昵称失败: $e');
      return '';
    }
  }

  /// 头像：可能是云端 URL，也可能是本机文件路径（离线时）。没有则返回空串
  static Future<String> avatar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kAvatarKey) ?? '';
    } catch (e) {
      debugPrint('[Profile] 读头像失败: $e');
      return '';
    }
  }

  /// 引导页是否已经走过（有昵称就算走过）
  static Future<bool> isConfigured() async => (await nickname()).isNotEmpty;

  /// 欢迎页是否已经看过
  static Future<bool> welcomed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kWelcomedKey) ?? false;
    } catch (e) {
      debugPrint('[Profile] 读欢迎页标记失败: $e');
      return false;
    }
  }

  /// 记下「欢迎页看完了」
  static Future<void> markWelcomed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kWelcomedKey, true);
      debugPrint('[Profile] ✅ 欢迎页标记已写入');
    } catch (e) {
      debugPrint('[Profile] ❌ 写欢迎页标记失败: $e');
    }
  }

  /// 保存资料，并同步到各模块自己的键
  static Future<void> save({
    required String nickname,
    required String avatar,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = nickname.trim();
      await prefs.setString(kNicknameKey, name);
      for (final key in _nicknameMirrors) {
        await prefs.setString(key, name);
      }

      if (avatar.trim().isNotEmpty) {
        await prefs.setString(kAvatarKey, avatar.trim());
        for (final key in _avatarMirrors) {
          await prefs.setString(key, avatar.trim());
        }
      }
      debugPrint('[Profile] ✅ 资料已保存: $name');
    } catch (e) {
      debugPrint('[Profile] ❌ 保存失败: $e');
    }
  }
}
