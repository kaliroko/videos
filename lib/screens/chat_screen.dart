/// 实时聊天室 —— Supabase Realtime + Telegram 完整复刻
library;

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../managers/analytics_manager.dart';

// ══════════════════════════════════════════════════════════════
const Color _kMyBubble = Color(0xFF2B5278);
const Color _kOtherBubble = Color(0xFF182533);
const Color _kMyText = Color(0xFFFFFFFF);
const Color _kOtherText = Color(0xFFFFFFFF);
const Color _kTimeMine = Color(0xFF8FB5D6);
const Color _kTimeOther = Color(0xFF6B7B8B);

const Color _kChatBg = Color(0xFF0E1621);
const Color _kBarBg = Color(0xFF17212B);
const Color _kInputBg = Color(0xFF242F3D);
const Color _kSendBtn = Color(0xFF64B5EF);
const Color _kOnline = Color(0xFF4EC9A6);

const Curve _kEmphasizedDecel = Cubic(0.05, 0.7, 0.1, 1.0);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _messages = <_ChatMessage>[];
  final _messageIds = <int>{};
  final _profiles = <String, _UserProfile>{};

  RealtimeChannel? _channel;
  String? _myDeviceId;
  String? _myNickname;
  String? _myAvatarUrl;

  bool _loading = true;
  bool _sending = false;
  bool _uploadingAvatar = false;
  bool _needsSetup = false;
  bool _connected = true;
  bool _hasText = false;
  bool _showScrollDown = false;
  bool _showEmojiPicker = false;

  int _onlineCount = 1;
  _ChatMessage? _replyTo;

  DateTime? _lastSendTime;
  static const _kMinSendInterval = Duration(seconds: 1);

  Timer? _reconnectTimer;
  final _setupNameController = TextEditingController();

  static const _kTable = 'chat_messages';
  static const _kProfileTable = 'user_profiles';
  static const _kBucket = 'avatars';
  static const _kFileBucket = 'chat_files';
  static const _kNicknameKey = 'chat_nickname';
  static const _kAvatarKey = 'chat_avatar_url';
  static const _kHistoryLimit = 100;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(() {
      final has = _inputController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.untrack();
    _channel?.unsubscribe();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    _setupNameController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final distanceFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    final shouldShow = distanceFromBottom > 200;
    if (shouldShow != _showScrollDown) {
      setState(() => _showScrollDown = shouldShow);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 初始化
  // ══════════════════════════════════════════════════════════════
  Future<void> _init() async {
    await AnalyticsManager.instance.init();

    final androidId = await _getAndroidId();
    if (androidId == null || androidId.isEmpty) {
      _myDeviceId = 'u_${DateTime.now().microsecondsSinceEpoch}';
      debugPrint('[Chat] ⚠️ 兜底 ID: $_myDeviceId');
    } else {
      _myDeviceId = androidId;
      debugPrint('[Chat] 🆔 Android ID: $_myDeviceId');
    }

    final serverProfile = await _fetchProfileFromServer(_myDeviceId!);

    if (serverProfile == null) {
      debugPrint('[Chat] 🆕 未注册');
      if (mounted) {
        setState(() {
          _loading = false;
          _needsSetup = true;
        });
      }
      return;
    }

    debugPrint('[Chat] ✅ 已注册: ${serverProfile.nickname}');
    _myNickname = serverProfile.nickname;
    _myAvatarUrl = serverProfile.avatarUrl;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNicknameKey, _myNickname!);
    if (_myAvatarUrl != null) {
      await prefs.setString(_kAvatarKey, _myAvatarUrl!);
    }

    await _loadHistory();
    _subscribeRealtime();
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _getAndroidId() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.id;
    } catch (e) {
      debugPrint('[Chat] ❌ Android ID 失败: $e');
      return null;
    }
  }

  Future<_UserProfile?> _fetchProfileFromServer(String deviceId) async {
    try {
      final data = await Supabase.instance.client
          .from(_kProfileTable)
          .select()
          .eq('device_id', deviceId)
          .maybeSingle();
      if (data == null) return null;
      return _UserProfile.fromMap(data);
    } catch (e) {
      debugPrint('[Chat] 查询档案失败: $e');
      return null;
    }
  }

  Future<void> _finishSetup() async {
    final name = _setupNameController.text.trim();
    if (name.isEmpty) {
      _snack('请输入昵称');
      return;
    }
    if (_myAvatarUrl == null) {
      _snack('请上传头像');
      return;
    }

    final existing = await _fetchProfileFromServer(_myDeviceId!);
    if (existing != null) {
      _myNickname = existing.nickname;
      _myAvatarUrl = existing.avatarUrl;
      setState(() => _needsSetup = false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kNicknameKey, _myNickname!);
      if (_myAvatarUrl != null) {
        await prefs.setString(_kAvatarKey, _myAvatarUrl!);
      }

      await _loadHistory();
      _subscribeRealtime();
      return;
    }

    try {
      await Supabase.instance.client.from(_kProfileTable).insert({
        'device_id': _myDeviceId,
        'nickname': name,
        'avatar_url': _myAvatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[Chat] ❌ 注册失败: $e');
      _snack('注册失败，请重试');
      return;
    }

    _myNickname = name;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNicknameKey, name);

    setState(() => _needsSetup = false);
    await _loadHistory();
    _subscribeRealtime();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _syncMyProfile() async {
    if (_myNickname == null || _myDeviceId == null) return;
    try {
      await Supabase.instance.client
          .from(_kProfileTable)
          .update({
            'nickname': _myNickname,
            if (_myAvatarUrl != null) 'avatar_url': _myAvatarUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('device_id', _myDeviceId!);
    } catch (e) {
      debugPrint('[Chat] ❌ 同步档案失败: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final data = await Supabase.instance.client
          .from(_kTable)
          .select()
          .order('created_at', ascending: false)
          .limit(_kHistoryLimit);
      final list = (data as List).cast<Map<String, dynamic>>();
      for (final m in list.reversed) {
        final msg = _ChatMessage.fromMap(m);
        if (_messageIds.add(msg.id)) _messages.add(msg);
      }
      if (mounted) setState(() {});
      await _loadProfilesForMessages();
      _scrollToBottom(animate: false);
    } catch (e) {
      debugPrint('[Chat] 加载历史失败: $e');
    }
  }

  Future<void> _loadProfilesForMessages() async {
    final ids = _messages
        .map((m) => m.deviceId)
        .where((id) => !_profiles.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final data = await Supabase.instance.client
          .from(_kProfileTable)
          .select()
          .inFilter('device_id', ids);
      for (final row in (data as List).cast<Map<String, dynamic>>()) {
        final p = _UserProfile.fromMap(row);
        _profiles[p.deviceId] = p;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Chat] 加载档案失败: $e');
    }
  }

  Future<void> _loadProfile(String deviceId) async {
    if (_profiles.containsKey(deviceId)) return;
    try {
      final data = await Supabase.instance.client
          .from(_kProfileTable)
          .select()
          .eq('device_id', deviceId)
          .maybeSingle();
      if (data != null) {
        _profiles[deviceId] = _UserProfile.fromMap(data);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();

    _channel = Supabase.instance.client
        .channel('chat_room')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _kTable,
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final msg = _ChatMessage.fromMap(row);
            if (!_messageIds.add(msg.id)) return;
            if (!mounted) return;
            setState(() => _messages.add(msg));
            _scrollToBottom();
            _loadProfile(msg.deviceId);
          },
        )
        .onPresenceSync((payload) {
          final states = _channel?.presenceState() ?? const [];
          final count = states.length;
          debugPrint('[Chat] 👥 在线人数: $count');
          if (mounted) setState(() => _onlineCount = count);
        })
        .subscribe((status, [err]) async {
          debugPrint('[Chat] Realtime: $status, err=$err');

          if (status == RealtimeSubscribeStatus.subscribed) {
            _connected = true;
            _reconnectTimer?.cancel();
            await _channel?.track({
              'device_id': _myDeviceId,
              'nickname': _myNickname,
              'online_at': DateTime.now().toIso8601String(),
            });
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            _connected = false;
            _scheduleReconnect();
          }
          if (mounted) setState(() {});
        });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _subscribeRealtime();
    });
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 380),
          curve: _kEmphasizedDecel,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  // 发送文本
  // ══════════════════════════════════════════════════════════════
  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final now = DateTime.now();
    if (_lastSendTime != null &&
        now.difference(_lastSendTime!) < _kMinSendInterval) {
      _snack('发送太快，请稍等');
      return;
    }
    _lastSendTime = now;

    _sending = true;
    _inputController.clear();
    final replyTo = _replyTo;
    setState(() => _replyTo = null);

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tempMsg = _ChatMessage(
      id: tempId,
      deviceId: _myDeviceId ?? '',
      nickname: _myNickname ?? '',
      content: text,
      createdAt: DateTime.now(),
      replyToId: replyTo?.id,
      replyToNickname: replyTo?.nickname,
      replyToContent: replyTo?.content,
    );
    setState(() => _messages.add(tempMsg));
    _scrollToBottom();

    try {
      final res = await Supabase.instance.client
          .from(_kTable)
          .insert({
            'device_id': _myDeviceId,
            'nickname': _myNickname,
            'content': text,
            'message_type': 'text',
            if (replyTo != null) 'reply_to_id': replyTo.id,
            if (replyTo != null) 'reply_to_nickname': replyTo.nickname,
            if (replyTo != null) 'reply_to_content': replyTo.content,
          })
          .select()
          .single();

      final realMsg = _ChatMessage.fromMap(res);
      if (!mounted) return;

      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx >= 0) _messages[idx] = realMsg;
        _messageIds.add(realMsg.id);
      });
    } catch (e) {
      debugPrint('[Chat] 发送失败: $e');
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m.id == tempId));
      _snack('发送失败，请重试');
    } finally {
      _sending = false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 附件菜单
  // ══════════════════════════════════════════════════════════════
  Future<void> _showAttachMenu() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() => _showEmojiPicker = false);

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kBarBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _attachItem(
              icon: Icons.photo,
              color: const Color(0xFF4EC9A6),
              label: '相册',
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            _attachItem(
              icon: Icons.insert_drive_file,
              color: const Color(0xFF64B5EF),
              label: '文件',
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            _attachItem(
              icon: Icons.camera_alt,
              color: const Color(0xFFFB7299),
              label: '拍照',
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (result == 'photo') await _pickAndSendImage(ImageSource.gallery);
    if (result == 'camera') await _pickAndSendImage(ImageSource.camera);
    if (result == 'file') await _pickAndSendFile();
  }

  Widget _attachItem({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          _snack('需要相机权限');
          return;
        }
      } else {
        final statuses = await <Permission>[
          Permission.photos,
          Permission.storage,
        ].request();
        final has = statuses.values.any((s) => s.isGranted || s.isLimited);
        if (!has) {
          _snack('需要相册权限');
          return;
        }
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = _pickExtension(picked.path);
      final filename =
          '${_myDeviceId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'images/$filename';

      _snack('正在上传…');

      await Supabase.instance.client.storage.from(_kFileBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: false,
            ),
          );

      final url = Supabase.instance.client.storage
          .from(_kFileBucket)
          .getPublicUrl(path);

      await _sendMediaMessage(
        messageType: 'image',
        fileUrl: url,
        fileName: filename,
      );
    } catch (e, st) {
      debugPrint('[Chat] ❌ 上传图片失败: $e\n$st');
      if (mounted) _snack('上传失败: $e');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _snack('无法读取文件');
        return;
      }

      if (bytes.length > 50 * 1024 * 1024) {
        _snack('文件不能超过 50 MB');
        return;
      }

      final filename =
          '${_myDeviceId}_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final path = 'files/$filename';

      _snack('正在上传…');

      await Supabase.instance.client.storage.from(_kFileBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: 'application/octet-stream',
              upsert: false,
            ),
          );

      final url = Supabase.instance.client.storage
          .from(_kFileBucket)
          .getPublicUrl(path);

      await _sendMediaMessage(
        messageType: 'file',
        fileUrl: url,
        fileName: file.name,
      );
    } catch (e, st) {
      debugPrint('[Chat] ❌ 上传文件失败: $e\n$st');
      if (mounted) _snack('上传失败: $e');
    }
  }

  Future<void> _sendMediaMessage({
    required String messageType,
    required String fileUrl,
    required String fileName,
  }) async {
    final replyTo = _replyTo;
    if (mounted) setState(() => _replyTo = null);

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tempMsg = _ChatMessage(
      id: tempId,
      deviceId: _myDeviceId ?? '',
      nickname: _myNickname ?? '',
      content: messageType == 'image' ? '[图片]' : '[文件]',
      createdAt: DateTime.now(),
      messageType: messageType,
      fileUrl: fileUrl,
      fileName: fileName,
      replyToId: replyTo?.id,
      replyToNickname: replyTo?.nickname,
      replyToContent: replyTo?.content,
    );
    setState(() => _messages.add(tempMsg));
    _scrollToBottom();

    try {
      final res = await Supabase.instance.client
          .from(_kTable)
          .insert({
            'device_id': _myDeviceId,
            'nickname': _myNickname,
            'content': tempMsg.content,
            'message_type': messageType,
            'file_url': fileUrl,
            'file_name': fileName,
            if (replyTo != null) 'reply_to_id': replyTo.id,
            if (replyTo != null) 'reply_to_nickname': replyTo.nickname,
            if (replyTo != null) 'reply_to_content': replyTo.content,
          })
          .select()
          .single();

      final realMsg = _ChatMessage.fromMap(res);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx >= 0) _messages[idx] = realMsg;
        _messageIds.add(realMsg.id);
      });
    } catch (e) {
      debugPrint('[Chat] 发送媒体失败: $e');
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m.id == tempId));
      _snack('发送失败，请重试');
    }
  }

  Future<void> _openImage(String url) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          child: Image.network(url),
        ),
      ),
    );
  }

  Future<void> _openFile(String url, String name) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 长按菜单
  // ══════════════════════════════════════════════════════════════
  Future<void> _showMessageMenu(_ChatMessage msg, bool isMine) async {
    HapticFeedback.mediumImpact();

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kBarBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.reply, color: _kSendBtn),
              title: const Text('回复',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (msg.messageType == 'text')
              ListTile(
                leading: const Icon(Icons.copy, color: _kSendBtn),
                title: const Text('复制',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'reply') {
      setState(() => _replyTo = msg);
      _inputFocus.requestFocus();
    } else if (result == 'copy') {
      await Clipboard.setData(ClipboardData(text: msg.content));
      _snack('已复制');
    }
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  // ══════════════════════════════════════════════════════════════
  // 头像上传
  // ══════════════════════════════════════════════════════════════
  Future<bool> _pickAndUploadAvatar() async {
    try {
      final permissions = <Permission>[
        Permission.photos,
        Permission.videos,
        Permission.storage,
      ];
      final statuses = await permissions.request();

      bool hasPermission = false;
      statuses.forEach((perm, status) {
        if (status.isGranted || status.isLimited) hasPermission = true;
      });

      if (!hasPermission) {
        final anyPermanentlyDenied =
            statuses.values.any((s) => s.isPermanentlyDenied);
        if (anyPermanentlyDenied) {
          if (mounted) {
            _snack('请到设置中开启相册权限');
            await openAppSettings();
          }
        } else {
          if (mounted) _snack('需要相册权限才能上传头像');
        }
        return false;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null) return false;

      final bytes = await picked.readAsBytes();
      final ext = _pickExtension(picked.path);
      final filename =
          '${_myDeviceId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage.from(_kBucket).uploadBinary(
            filename,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: false,
            ),
          );

      final url = Supabase.instance.client.storage
          .from(_kBucket)
          .getPublicUrl(filename);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAvatarKey, url);
      if (mounted) setState(() => _myAvatarUrl = url);

      if (_myNickname != null && !_needsSetup) {
        await _syncMyProfile();
      }
      return true;
    } catch (e, st) {
      debugPrint('[Chat] ❌ 上传失败: $e\n$st');
      if (mounted) _snack('上传失败: $e');
      return false;
    }
  }

  String _pickExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  // ══════════════════════════════════════════════════════════════
  // 设置面板
  // ══════════════════════════════════════════════════════════════
  Future<void> _showSettings() async {
    final nameController = TextEditingController(text: _myNickname);
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kBarBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('个人资料',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              _SpringScale(
                onTap: _uploadingAvatar
                    ? null
                    : () async {
                        setSheetState(() => _uploadingAvatar = true);
                        final ok = await _pickAndUploadAvatar();
                        if (ctx.mounted) {
                          setSheetState(() => _uploadingAvatar = false);
                        }
                        if (ok && mounted) setState(() {});
                      },
                child: Stack(
                  children: [
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kInputBg,
                        image: _myAvatarUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_myAvatarUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _myAvatarUrl == null
                          ? const Icon(Icons.person,
                              size: 40, color: Colors.white54)
                          : null,
                    ),
                    if (_uploadingAvatar)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black54,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _kSendBtn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: _kSendBtn,
                          shape: BoxShape.circle,
                          border: Border.all(color: _kBarBg, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt,
                            size: 15, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('点击更换头像',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 24),
              TextField(
                controller: nameController,
                maxLength: 16,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '昵称',
                  labelStyle: const TextStyle(color: Colors.white54),
                  counterStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: _kInputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _SpringButton(
                  onTap: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(_kNicknameKey, name);
                    if (!mounted) return;
                    setState(() => _myNickname = name);
                    await _syncMyProfile();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _kSendBtn,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Text('完成',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: _kChatBg,
        child: Center(
          child: CircularProgressIndicator(color: _kSendBtn),
        ),
      );
    }

    if (_needsSetup) return _buildSetupPage();
    return _buildChatPage();
  }

  // ══════════════════════════════════════════════════════════════
  // 引导页
  // ══════════════════════════════════════════════════════════════
  Widget _buildSetupPage() {
    return Scaffold(
      backgroundColor: _kBarBg,
      appBar: AppBar(
        backgroundColor: _kBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          '设置资料',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Text(
                '全球联网实时聊天室',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '和全球用户实时交流',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 40),
              Center(
                child: _SpringScale(
                  onTap: _uploadingAvatar
                      ? null
                      : () async {
                          setState(() => _uploadingAvatar = true);
                          await _pickAndUploadAvatar();
                          if (mounted) setState(() => _uploadingAvatar = false);
                        },
                  child: Stack(
                    children: [
                      Container(
                        width: 110, height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kInputBg,
                          image: _myAvatarUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(_myAvatarUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _myAvatarUrl == null
                            ? const Icon(Icons.person,
                                size: 52, color: Colors.white38)
                            : null,
                      ),
                      Positioned(
                        right: 2, bottom: 2,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: _kSendBtn,
                            shape: BoxShape.circle,
                            border: Border.all(color: _kBarBg, width: 3),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 17, color: Colors.white),
                        ),
                      ),
                      if (_uploadingAvatar)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 28, height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _kSendBtn,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _uploadingAvatar
                      ? null
                      : () async {
                          setState(() => _uploadingAvatar = true);
                          await _pickAndUploadAvatar();
                          if (mounted) setState(() => _uploadingAvatar = false);
                        },
                  child: Text(
                    _myAvatarUrl == null ? '上传头像' : '更换头像',
                    style: const TextStyle(color: _kSendBtn, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _setupNameController,
                maxLength: 16,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '输入昵称',
                  hintStyle: const TextStyle(
                      color: Colors.white38, fontSize: 15),
                  counterStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: _kInputBg,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _kSendBtn, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: _SpringButton(
                  onTap: _finishSetup,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kSendBtn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '开始聊天',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 聊天页
  // ══════════════════════════════════════════════════════════════
  Widget _buildChatPage() {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _kChatBg,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          const Positioned.fill(child: _ChatBackground()),
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    _messages.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    color: Colors.white24, size: 42),
                                SizedBox(height: 10),
                                Text('还没有消息',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 14)),
                              ],
                            ),
                          )
                        : _buildMessagesList(),
                    if (_showScrollDown)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _ScrollToBottomButton(
                          onTap: () => _scrollToBottom(),
                        ),
                      ),
                  ],
                ),
              ),
              _buildInputBar(bottomInset),
              if (_showEmojiPicker)
                SizedBox(
                  height: 260,
                  child: EmojiPicker(
                    textEditingController: _inputController,
                    config: Config(
                      height: 260,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        backgroundColor: _kBarBg,
                        emojiSizeMax: 26,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: _kBarBg,
                        iconColor: Colors.white38,
                        iconColorSelected: _kSendBtn,
                        indicatorColor: _kSendBtn,
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: _kBarBg,
                        buttonIconColor: Colors.white,
                        hintText: '搜索…',
                        hintTextStyle: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kBarBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 8,
      leadingWidth: 52,
      leading: Center(
        child: Container(
          width: 38, height: 38,
          decoration: const BoxDecoration(
            color: _kInputBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.groups, color: _kSendBtn, size: 22),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '公共聊天室',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _connected ? '$_onlineCount 人在线' : '连接中…',
            style: TextStyle(
              color: _connected ? _kOnline : Colors.orange,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _showSettings,
          icon: _myAvatarUrl != null
              ? ClipOval(
                  child: Image.network(
                    _myAvatarUrl!,
                    width: 34, height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 34, height: 34,
                      decoration: const BoxDecoration(
                        color: _kInputBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person,
                          size: 18, color: Colors.white54),
                    ),
                  ),
                )
              : Container(
                  width: 34, height: 34,
                  decoration: const BoxDecoration(
                    color: _kInputBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person,
                      size: 18, color: Colors.white54),
                ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final isMine = m.deviceId == _myDeviceId;
        final prev = i > 0 ? _messages[i - 1] : null;
        final showAvatar =
            !isMine && (prev == null || prev.deviceId != m.deviceId);

        final showDateSep =
            prev == null || !_isSameDay(prev.createdAt, m.createdAt);

        return Column(
          children: [
            if (showDateSep) _DateSeparator(date: m.createdAt),
            _MessageBubble(
              key: ValueKey(m.id),
              msg: m,
              profile: _profiles[m.deviceId],
              isMine: isMine,
              showAvatar: showAvatar,
              onLongPress: () => _showMessageMenu(m, isMine),
              onSwipeReply: () {
                setState(() => _replyTo = m);
                _inputFocus.requestFocus();
              },
              onTapImage: () => _openImage(m.fileUrl!),
              onTapFile: () => _openFile(m.fileUrl!, m.fileName ?? ''),
            ),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildInputBar(double bottomInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
      decoration: const BoxDecoration(
        color: _kBarBg,
        border: Border(
          top: BorderSide(color: Colors.black26, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            _ReplyPreview(msg: _replyTo!, onCancel: _cancelReply),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _kInputBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          setState(
                              () => _showEmojiPicker = !_showEmojiPicker);
                        },
                        icon: Icon(
                          _showEmojiPicker
                              ? Icons.keyboard
                              : Icons.emoji_emotions_outlined,
                          color: Colors.white54, size: 22,
                        ),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocus,
                          onTap: () {
                            if (_showEmojiPicker) {
                              setState(() => _showEmojiPicker = false);
                            }
                          },
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                          maxLines: 5,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: '消息',
                            hintStyle: TextStyle(
                                color: Colors.white54, fontSize: 15),
                            filled: false,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _showAttachMenu,
                        icon: const Icon(
                          Icons.attach_file,
                          color: Colors.white54, size: 20,
                        ),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedScale(
                scale: _hasText ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: _kEmphasizedDecel,
                child: AnimatedOpacity(
                  opacity: _hasText ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  child: _SendButton(onTap: _send),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 聊天背景：蓝黑渐变 + 几何图案
// ══════════════════════════════════════════════════════════════
class _ChatBackground extends StatelessWidget {
  const _ChatBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1826),
            Color(0xFF0E1621),
            Color(0xFF060A10),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _PatternPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawCircle(
      Offset(w * 0.85, h * 0.15),
      w * 0.5,
      Paint()
        ..color = const Color(0xFF64B5EF).withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      Offset(w * 0.1, h * 0.85),
      w * 0.6,
      Paint()
        ..color = const Color(0xFF64B5EF).withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    final linePaint = Paint()
      ..color = const Color(0xFF64B5EF).withValues(alpha: 0.025)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    for (double i = -h; i < w + h; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + h, h), linePaint);
    }

    final dotPaint = Paint()
      ..color = const Color(0xFF64B5EF).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final dots = <Offset>[
      Offset(w * 0.2, h * 0.25),
      Offset(w * 0.75, h * 0.55),
      Offset(w * 0.35, h * 0.7),
      Offset(w * 0.9, h * 0.85),
      Offset(w * 0.5, h * 0.1),
      Offset(w * 0.05, h * 0.5),
    ];
    for (final dot in dots) {
      canvas.drawCircle(dot, 3.0, dotPaint);
    }

    final triPath = Path()
      ..moveTo(w * 0.7, h * 0.3)
      ..lineTo(w * 0.8, h * 0.45)
      ..lineTo(w * 0.6, h * 0.45)
      ..close();
    canvas.drawPath(
      triPath,
      Paint()
        ..color = const Color(0xFF64B5EF).withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF64B5EF).withValues(alpha: 0.05),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(w * 0.5, h * 0.4),
          radius: w * 0.7,
        ),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════
class _SpringScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _SpringScale({required this.child, this.onTap});

  @override
  State<_SpringScale> createState() => _SpringScaleState();
}

class _SpringScaleState extends State<_SpringScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) => _ctrl.forward(),
      onTapCancel: () => _ctrl.forward(),
      onTap: widget.onTap,
      child: ScaleTransition(scale: _ctrl, child: widget.child),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _SpringButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _SpringButton({required this.onTap, required this.child});

  @override
  State<_SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<_SpringButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) {
        _ctrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(scale: _ctrl, child: widget.child),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _SendButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 0.7,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _bounce() {
    _ctrl.reverse().then((_) {
      if (!mounted) return;
      _ctrl.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 400, damping: 14),
          _ctrl.value,
          1.0,
          0.0,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) {
        _bounce();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _ctrl,
        child: Container(
          width: 42, height: 42,
          decoration: const BoxDecoration(
            color: _kSendBtn,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.send_rounded,
              color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _ScrollToBottomButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ScrollToBottomButton({required this.onTap});

  @override
  State<_ScrollToBottomButton> createState() => _ScrollToBottomButtonState();
}

class _ScrollToBottomButtonState extends State<_ScrollToBottomButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
      child: FadeTransition(
        opacity: _ctrl,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _kInputBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _kSendBtn, size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _ReplyPreview extends StatelessWidget {
  final _ChatMessage msg;
  final VoidCallback onCancel;

  const _ReplyPreview({required this.msg, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: _kInputBg,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: _kSendBtn, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.nickname,
                  style: const TextStyle(
                    color: _kSendBtn,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  msg.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70, fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _MessageBubble extends StatefulWidget {
  final _ChatMessage msg;
  final _UserProfile? profile;
  final bool isMine;
  final bool showAvatar;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback onTapImage;
  final VoidCallback onTapFile;

  const _MessageBubble({
    super.key,
    required this.msg,
    required this.profile,
    required this.isMine,
    required this.showAvatar,
    required this.onLongPress,
    required this.onSwipeReply,
    required this.onTapImage,
    required this.onTapFile,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  double _dragOffset = 0;
  static const double _kDragThreshold = 60;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: _kEmphasizedDecel);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: _kEmphasizedDecel));
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dx > 0 || _dragOffset > 0) {
      setState(() {
        _dragOffset = (_dragOffset + d.delta.dx).clamp(0.0, 80.0);
      });
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragOffset >= _kDragThreshold) {
      HapticFeedback.lightImpact();
      widget.onSwipeReply();
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final time =
        '${widget.msg.createdAt.hour.toString().padLeft(2, '0')}:${widget.msg.createdAt.minute.toString().padLeft(2, '0')}';
    final isMine = widget.isMine;
    final displayName = widget.profile?.nickname ?? widget.msg.nickname;
    final avatarUrl = widget.profile?.avatarUrl;
    final replyProgress = (_dragOffset / _kDragThreshold).clamp(0.0, 1.0);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: GestureDetector(
            onLongPress: widget.onLongPress,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: widget.msg.messageType == 'image'
                ? widget.onTapImage
                : widget.msg.messageType == 'file'
                    ? widget.onTapFile
                    : null,
            child: Stack(
              children: [
                if (_dragOffset > 0)
                  Positioned(
                    left: 8, top: 0, bottom: 0,
                    child: Center(
                      child: Opacity(
                        opacity: replyProgress,
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: _kSendBtn.withValues(alpha: replyProgress),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.reply, color: Colors.white, size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(_dragOffset, 0),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 3, bottom: 3,
                      left: isMine ? 60 : 8,
                      right: isMine ? 8 : 60,
                    ),
                    child: Row(
                      mainAxisAlignment: isMine
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isMine) ...[
                          SizedBox(
                            width: 32, height: 32,
                            child: widget.showAvatar
                                ? _AvatarImage(
                                    seed: widget.msg.deviceId,
                                    nickname: displayName,
                                    url: avatarUrl,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: isMine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMine && widget.showAvatar)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 12, bottom: 2),
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: _kSendBtn,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              _Bubble(
                                msg: widget.msg,
                                time: time,
                                isMine: isMine,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _Bubble extends StatelessWidget {
  final _ChatMessage msg;
  final String time;
  final bool isMine;

  const _Bubble({
    required this.msg,
    required this.time,
    required this.isMine,
  });

  static const double _tailH = 10.0;

  @override
  Widget build(BuildContext context) {
    final hasReply = msg.replyToNickname != null;
    final type = msg.messageType;

    return CustomPaint(
      painter: _TelegramBubblePainter(
        color: isMine ? _kMyBubble : _kOtherBubble,
        isMine: isMine,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: type == 'image' ? 4 : 12,
          right: type == 'image' ? 4 : 12,
          top: type == 'image' ? 4 : 7,
          bottom: (type == 'image' ? 4 : 7) + _tailH - 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasReply)
              Container(
                margin: EdgeInsets.only(
                    bottom: 6, left: type == 'image' ? 8 : 0),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: const Border(
                    left: BorderSide(color: _kSendBtn, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      msg.replyToNickname!,
                      style: const TextStyle(
                        color: _kSendBtn,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      msg.replyToContent ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70, fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            if (type == 'image')
              _buildImageContent(context)
            else if (type == 'file')
              _buildFileContent()
            else
              _buildTextContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            msg.content,
            style: TextStyle(
              color: isMine ? _kMyText : _kOtherText,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            time,
            style: TextStyle(
              color: isMine ? _kTimeMine : _kTimeOther,
              fontSize: 11,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageContent(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
              maxHeight: MediaQuery.of(context).size.width * 0.6,
            ),
            child: Image.network(
              msg.fileUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 200, height: 200,
                  color: Colors.black26,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kSendBtn,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                width: 200, height: 200,
                color: Colors.black26,
                child: const Icon(Icons.broken_image,
                    color: Colors.white38, size: 40),
              ),
            ),
          ),
          Positioned(
            right: 6, bottom: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                time,
                style: const TextStyle(
                  color: Colors.white, fontSize: 10, height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.insert_drive_file,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg.fileName ?? '文件',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '点击下载',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            time,
            style: TextStyle(
              color: isMine ? _kTimeMine : _kTimeOther,
              fontSize: 11,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _TelegramBubblePainter extends CustomPainter {
  final Color color;
  final bool isMine;

  _TelegramBubblePainter({required this.color, required this.isMine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const r = 15.0;
    const rSmall = 4.0;
    const tailW = 8.0;
    const tailH = 10.0;

    final w = size.width;
    final h = size.height - tailH;
    final path = Path();

    if (isMine) {
      path.moveTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
      path.lineTo(w - r, 0);
      path.quadraticBezierTo(w, 0, w, r);
      path.lineTo(w, h - rSmall);
      path.quadraticBezierTo(w, h, w - rSmall, h);
      path.lineTo(w - 6, h);
      path.quadraticBezierTo(w - 1, h + 3, w + tailW, h + tailH);
      path.quadraticBezierTo(w - 5, h - 1, w - rSmall - 6, h);
      path.lineTo(r, h);
      path.quadraticBezierTo(0, h, 0, h - r);
      path.close();
    } else {
      path.moveTo(w, r);
      path.quadraticBezierTo(w, 0, w - r, 0);
      path.lineTo(r, 0);
      path.quadraticBezierTo(0, 0, 0, r);
      path.lineTo(0, h - rSmall);
      path.quadraticBezierTo(0, h, rSmall, h);
      path.lineTo(6, h);
      path.quadraticBezierTo(1, h + 3, -tailW, h + tailH);
      path.quadraticBezierTo(5, h - 1, rSmall + 6, h);
      path.lineTo(w - r, h);
      path.quadraticBezierTo(w, h, w, h - r);
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TelegramBubblePainter old) =>
      old.color != color || old.isMine != isMine;
}

// ══════════════════════════════════════════════════════════════
class _AvatarImage extends StatelessWidget {
  final String seed;
  final String nickname;
  final String? url;

  const _AvatarImage({
    required this.seed,
    required this.nickname,
    this.url,
  });

  static const _colors = [
    Color(0xFFE84A7F),
    Color(0xFFFB7299),
    Color(0xFF7EC8E3),
    Color(0xFF9B8CFF),
    Color(0xFF4EC9A6),
    Color(0xFFF0A458),
    Color(0xFFEA6B7A),
    Color(0xFF7BA8F0),
  ];

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialAvatar(),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return _initialAvatar();
          },
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    final color = _colors[hash % _colors.length];
    final initial =
        nickname.isNotEmpty ? nickname.characters.first.toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _ChatMessage {
  final int id;
  final String deviceId;
  final String nickname;
  final String content;
  final DateTime createdAt;
  final String messageType;
  final String? fileUrl;
  final String? fileName;
  final int? replyToId;
  final String? replyToNickname;
  final String? replyToContent;

  _ChatMessage({
    required this.id,
    required this.deviceId,
    required this.nickname,
    required this.content,
    required this.createdAt,
    this.messageType = 'text',
    this.fileUrl,
    this.fileName,
    this.replyToId,
    this.replyToNickname,
    this.replyToContent,
  });

  factory _ChatMessage.fromMap(Map<String, dynamic> m) => _ChatMessage(
        id: (m['id'] as num).toInt(),
        deviceId: m['device_id'] as String? ?? '',
        nickname: m['nickname'] as String? ?? '匿名',
        content: m['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        messageType: m['message_type'] as String? ?? 'text',
        fileUrl: m['file_url'] as String?,
        fileName: m['file_name'] as String?,
        replyToId: (m['reply_to_id'] as num?)?.toInt(),
        replyToNickname: m['reply_to_nickname'] as String?,
        replyToContent: m['reply_to_content'] as String?,
      );
}

class _UserProfile {
  final String deviceId;
  final String nickname;
  final String? avatarUrl;

  _UserProfile({
    required this.deviceId,
    required this.nickname,
    this.avatarUrl,
  });

  factory _UserProfile.fromMap(Map<String, dynamic> m) => _UserProfile(
        deviceId: m['device_id'] as String? ?? '',
        nickname: m['nickname'] as String? ?? '匿名',
        avatarUrl: m['avatar_url'] as String?,
      );
}