/// 实时聊天室 —— Supabase Realtime + Telegram UI + MD3 物理弹簧
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../managers/analytics_manager.dart';

// ══════════════════════════════════════════════════════════════
// Telegram 深色模式配色
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
const Color _kAccent = Color(0xFFFB7299);

/// MD3 Emphasized 曲线
const Curve _kEmphasized = Cubic(0.2, 0.0, 0.0, 1.0);
const Curve _kEmphasizedDecel = Cubic(0.05, 0.7, 0.1, 1.0);
const Curve _kEmphasizedAccel = Cubic(0.3, 0.0, 0.8, 0.15);

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

  DateTime? _lastSendTime;
  static const _kMinSendInterval = Duration(seconds: 1);

  Timer? _reconnectTimer;
  final _setupNameController = TextEditingController();

  /// ★ 输入框是否为空（控制发送按钮显隐）
  bool _hasText = false;

  static const _kTable = 'chat_messages';
  static const _kProfileTable = 'user_profiles';
  static const _kBucket = 'avatars';
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
    _init();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.unsubscribe();
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    _setupNameController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await AnalyticsManager.instance.init();
    _myDeviceId = AnalyticsManager.instance.deviceId;
    if (_myDeviceId == null || _myDeviceId!.isEmpty) {
      _myDeviceId = 'anon-${DateTime.now().millisecondsSinceEpoch}';
    }

    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_kNicknameKey);
    _myAvatarUrl = prefs.getString(_kAvatarKey);

    if (savedName == null || savedName.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _needsSetup = true;
        });
      }
      return;
    }

    _myNickname = savedName;
    await _syncMyProfile();
    await _loadHistory();
    _subscribeRealtime();
    if (mounted) setState(() => _loading = false);
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNicknameKey, name);
    _myNickname = name;

    setState(() => _needsSetup = false);
    await _syncMyProfile();
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
    try {
      await Supabase.instance.client.from(_kProfileTable).upsert({
        'device_id': _myDeviceId,
        'nickname': _myNickname,
        if (_myAvatarUrl != null) 'avatar_url': _myAvatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[Chat] 同步档案失败: $e');
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
        .subscribe((status, [err]) {
          debugPrint('[Chat] Realtime 状态: $status, err=$err');

          if (status == RealtimeSubscribeStatus.subscribed) {
            _connected = true;
            _reconnectTimer?.cancel();
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

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tempMsg = _ChatMessage(
      id: tempId,
      deviceId: _myDeviceId ?? '',
      nickname: _myNickname ?? '',
      content: text,
      createdAt: DateTime.now(),
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

  Future<bool> _pickAndUploadAvatar() async {
    try {
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

      if (_myNickname != null) await _syncMyProfile();
      return true;
    } catch (e) {
      debugPrint('[Chat] 上传头像失败: $e');
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
              GestureDetector(
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
                child: _SpringScale(
                  child: Stack(
                    children: [
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kInputBg,
                          border: Border.all(
                            color: _kAccent.withValues(alpha: 0.5),
                            width: 2,
                          ),
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
                                  color: _kAccent,
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
                            color: _kAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: _kBarBg, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 15, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
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
                      color: _kAccent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Text('完成',
                        style: TextStyle(
                            color: Colors.black,
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
          child: CircularProgressIndicator(color: _kAccent),
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
      backgroundColor: _kChatBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFB7299), Color(0xFFE84A7F)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.chat_bubble,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 24),
                const Text('欢迎来到聊天室',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 8),
                const Text('设置一下你的资料吧',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: _uploadingAvatar
                      ? null
                      : () async {
                          setState(() => _uploadingAvatar = true);
                          await _pickAndUploadAvatar();
                          if (mounted) setState(() => _uploadingAvatar = false);
                        },
                  child: _SpringScale(
                    child: Stack(
                      children: [
                        Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kInputBg,
                            border: Border.all(
                              color: _myAvatarUrl != null
                                  ? _kAccent
                                  : Colors.white12,
                              width: _myAvatarUrl != null ? 2.5 : 1.5,
                            ),
                            image: _myAvatarUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_myAvatarUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _myAvatarUrl == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined,
                                        color: Colors.white54, size: 32),
                                    SizedBox(height: 6),
                                    Text('上传头像',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                  ],
                                )
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _kAccent,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _setupNameController,
                  maxLength: 16,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: '输入昵称',
                    hintStyle:
                        const TextStyle(color: Colors.white54, fontSize: 16),
                    counterStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: _kInputBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _kAccent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: _SpringButton(
                    onTap: _finishSetup,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _kAccent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '开始聊天',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  // ══════════════════════════════════════════════════════════════
  // 聊天页
  // ══════════════════════════════════════════════════════════════
  Widget _buildChatPage() {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _kChatBg,
      appBar: AppBar(
        backgroundColor: _kBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(
                    color: _kInputBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups, color: _kSendBtn, size: 18),
                ),
                if (!_connected)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kBarBg, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('公共聊天室',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Text(
                  _connected ? '所有人可见' : '连接中…',
                  style: TextStyle(
                    color: _connected ? Colors.white54 : Colors.orange,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _showSettings,
            child: _SpringScale(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                width: 34, height: 34,
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
                        size: 18, color: Colors.white54)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            color: Colors.white24, size: 48),
                        SizedBox(height: 12),
                        Text('还没有消息',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('说两句吧~',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    // ★ iOS 风格弹簧滚动物理
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 68),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isMine = m.deviceId == _myDeviceId;
                      final prev = i > 0 ? _messages[i - 1] : null;
                      final showAvatar =
                          !isMine && (prev == null || prev.deviceId != m.deviceId);
                      return _MessageBubble(
                        key: ValueKey(m.id),
                        msg: m,
                        profile: _profiles[m.deviceId],
                        isMine: isMine,
                        showAvatar: showAvatar,
                      );
                    },
                  ),
          ),
          _buildInputBar(bottomInset),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ★ Telegram 风
    // ══════════════════════════════════════════════════════════════
  // ★ Telegram 风格输入栏
  // ══════════════════════════════════════════════════════════════
  Widget _buildInputBar(double bottomInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
      decoration: const BoxDecoration(
        color: _kBarBg,
        border: Border(
          top: BorderSide(color: Colors.black26, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 输入框胶囊
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _kInputBg,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 表情
                  _SpringScale(
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 12),
                      child: Icon(Icons.emoji_emotions_outlined,
                          color: Colors.white54, size: 22),
                    ),
                  ),
                  // 输入
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '消息',
                        hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        isDense: true,
                      ),
                    ),
                  ),
                  // 附件
                  if (!_hasText)
                    _SpringScale(
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8, bottom: 12),
                        child: Icon(Icons.attach_file,
                            color: Colors.white54, size: 20),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ★ 发送按钮（弹簧动效 + 有文字才显示）
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
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ★ 物理弹簧：按下缩放
// ══════════════════════════════════════════════════════════════
class _SpringScale extends StatefulWidget {
  final Widget child;
  const _SpringScale({required this.child});

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
      child: ScaleTransition(scale: _ctrl, child: widget.child),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ★ 物理弹簧按钮
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
// ★ 发送按钮（MD3 弹簧回弹）
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
          const SpringDescription(
            mass: 1,
            stiffness: 400,
            damping: 14,
          ),
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
          width: 46, height: 46,
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
// ★ 消息气泡（MD3 Emphasized 入场 + 弹簧）
// ══════════════════════════════════════════════════════════════
class _MessageBubble extends StatefulWidget {
  final _ChatMessage msg;
  final _UserProfile? profile;
  final bool isMine;
  final bool showAvatar;

  const _MessageBubble({
    super.key,
    required this.msg,
    required this.profile,
    required this.isMine,
    this.showAvatar = true,
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

  @override
  Widget build(BuildContext context) {
    final time =
        '${widget.msg.createdAt.hour.toString().padLeft(2, '0')}:${widget.msg.createdAt.minute.toString().padLeft(2, '0')}';
    final isMine = widget.isMine;
    final displayName = widget.profile?.nickname ?? widget.msg.nickname;
    final avatarUrl = widget.profile?.avatarUrl;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: Padding(
            padding: EdgeInsets.only(
              top: 3, bottom: 3,
              left: isMine ? 60 : 8,
              right: isMine ? 8 : 60,
            ),
            child: Row(
              mainAxisAlignment:
                  isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                          padding: const EdgeInsets.only(left: 12, bottom: 2),
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
                        text: widget.msg.content,
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
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _Bubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isMine;

  const _Bubble({
    required this.text,
    required this.time,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          decoration: BoxDecoration(
            color: isMine ? _kMyBubble : _kOtherBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isMine ? _kMyText : _kOtherText,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  time,
                  style: TextStyle(
                    color: isMine ? _kTimeMine : _kTimeOther,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          right: isMine ? -6 : null,
          left: isMine ? null : -6,
          child: CustomPaint(
            size: const Size(8, 10),
            painter: _BubbleTailPainter(
              color: isMine ? _kMyBubble : _kOtherBubble,
              isMine: isMine,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isMine;
  _BubbleTailPainter({required this.color, required this.isMine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    if (isMine) {
      path.moveTo(0, 0);
      path.quadraticBezierTo(
          size.width * 0.3, size.height * 0.4, size.width, size.height);
      path.lineTo(0, size.height * 0.6);
    } else {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(
          size.width * 0.7, size.height * 0.4, 0, size.height);
      path.lineTo(size.width, size.height * 0.6);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter old) =>
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

  _ChatMessage({
    required this.id,
    required this.deviceId,
    required this.nickname,
    required this.content,
    required this.createdAt,
  });

  factory _ChatMessage.fromMap(Map<String, dynamic> m) => _ChatMessage(
        id: (m['id'] as num).toInt(),
        deviceId: m['device_id'] as String? ?? '',
        nickname: m['nickname'] as String? ?? '匿名',
        content: m['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '') ??
                DateTime.now(),
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