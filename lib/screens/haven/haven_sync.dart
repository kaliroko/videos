/// 同频空间 —— 网页 Sisterhood Space 的还原，并接上真正的聊天室
///
/// 网页的「同频」是纯前端演示：点 MATCH 随机连上一个名字，一起共频、聊天。
/// App 这边保留这套仪式感（头像、共频计时、浮起的暧昧弹幕），并加了一层
/// 只对成年女性开放的「共振」—— 连接之后，可以邀请对方一起进入同一段节奏。
/// 聊天仍然接回已有的真实聊天室：演示归演示，能真的说话的时候别假装能说话。
///
/// ★ 关于尺度：这里只写到「暗示」为止 —— 节奏、呼吸、声音、停下来。
///   不描写具体动作，也不替用户说 consent：任何一方说停，就停。
library;

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/diary_provider.dart';
import '../../theme/haven.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/haven_widgets.dart';
import '../../widgets/spring_tap.dart';
import '../chat_screen.dart';

/// 共振时轮流浮起来的那几句 —— 只到「暗示」为止，不写具体动作。
/// 想再露骨/再收敛，改这一张表就够了，别去散落的文案里找。
const List<String> _kPrompts = <String>[
  '把灯关掉，只留屏幕的光。',
  '手心是不是已经热了。',
  '先别往下，等我。',
  '跟着我的呼吸，慢一点。',
  '膝盖软了也没有关系。',
  '想象我就在你身后。',
  '腰有没有跟着紧起来。',
  '别咬着嘴唇。',
  '慢一点，别让自己太快。',
  '现在，告诉我你几分。',
  '我要听你的声音。',
  '这里只有我们，放开一点。',
  '做得很好，继续。',
  '我在。',
  '今晚，你只准想我。',
  '你可以停下来，随时都可以。',
];

/// 还没连接时，她轮流说给你听的那几句（陪伴感）
const List<String> _kHerIdle = <String>[
  '今晚的夜色很安静。',
  '我在，不用一个人扛。',
  '想聊什么都可以，或者什么都不说。',
  '屏幕这么暗，你也在吗。',
  '先别急着说话，听一会呼吸。',
];

class HavenSyncView extends StatefulWidget {
  const HavenSyncView({super.key});

  @override
  State<HavenSyncView> createState() => _HavenSyncViewState();
}

class _HavenSyncViewState extends State<HavenSyncView> {
  static const List<String> _names = <String>['月亮船', 'Sappho', '薄荷', '晚风'];

  /// 共振节奏：慢 8s / 缓 5s / 急 3.2s 一拍
  static const List<int> _tempoMs = <int>[8000, 5000, 3200];
  static const List<String> _tempoLabels = <String>['慢', '缓', '急'];

  bool _connected = false;
  bool _connecting = false;
  bool _syncing = false;
  int _seconds = 0;
  int _syncRounds = 0;
  Timer? _syncTimer;

  // ── 共振 ────────────────────────────────────────────────────────
  bool _resonating = false;
  int _resonanceSeconds = 0;
  int _promptIndex = 0;
  int _tempo = 1;
  Timer? _resoTimer;
  Timer? _promptTimer;

  /// 双人共振：合拍度 0~100，两个人都在同一段节奏里时往上走
  int _syncRate = 0;
  Timer? _rateTimer;

  /// 她刚刚回的那句话
  String? _herReply;

  /// 上一段共振结束后的余韵
  int _lastSessionSeconds = 0;
  int _lastRate = 0;
  String? _afterglow;

  int _herSeed = DateTime.now().millisecondsSinceEpoch;
  String _herName = _names[0];

  /// 未连接时轮播的「她」的陪伴短句
  int _idleIndex = 0;
  Timer? _idleTimer;

  // 一次只飘一条，和网页的 .float-anim 行为一致
  String? _floatText;
  int _floatId = 0;

  @override
  void initState() {
    super.initState();
    _idleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // 连上之后这段陪伴文案就不显示了，没必要再每 5 秒重建一次
      if (!mounted || _connected) return;
      setState(() => _idleIndex++);
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _syncTimer?.cancel();
    _resoTimer?.cancel();
    _promptTimer?.cancel();
    _rateTimer?.cancel();
    super.dispose();
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return m + ':' + s;
  }

  String get _timerText => _fmt(_seconds);

  // ── 连接 ────────────────────────────────────────────────────────

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final seed = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _connecting = false;
      _connected = true;
      _herSeed = seed;
      _herName = _names[seed % _names.length];
    });
    _float('嗨，今晚的夜色很安静。');
  }

  void _disconnect() {
    _syncTimer?.cancel();
    _resoTimer?.cancel();
    _promptTimer?.cancel();
    _rateTimer?.cancel();
    setState(() {
      _connected = false;
      _syncing = false;
      _resonating = false;
      _seconds = 0;
      _resonanceSeconds = 0;
      _syncRounds = 0;
      _promptIndex = 0;
      _syncRate = 0;
      _herReply = null;
      _afterglow = null;
      _lastSessionSeconds = 0;
      _lastRate = 0;
      _floatText = null;
    });
    showHavenToast(context, '已断开连接');
  }

  void _float(String text) {
    setState(() {
      _floatText = text;
      _floatId++;
    });
  }

  // ── 共频（仪式）─────────────────────────────────────────────────

  void _startSync() {
    if (!_connected) return;
    setState(() {
      _syncing = true;
      _seconds = 0;
    });
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
    _float('我准备好了，闭上眼睛了。');
  }

  void _stopSync() {
    _syncTimer?.cancel();
    setState(() {
      _syncing = false;
      _syncRounds++;
    });
    _float('刚才的共振很强烈，谢谢你。');
  }

  // ── 共振（成人向）──────────────────────────────────────────────

  void _startResonance() {
    if (!_connected || _resonating) return;
    setState(() {
      _resonating = true;
      _resonanceSeconds = 0;
      _promptIndex = 0;
      _syncRate = 18;
      _herReply = null;
      _afterglow = null;
    });

    // 合拍度慢慢往上走：两个人还在同一段节奏里，才会到 100
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_resonating) return;
      if (_syncRate >= 100) return;
      setState(() => _syncRate = (_syncRate + 4).clamp(0, 100).toInt());
    });

    _resoTimer?.cancel();
    _resoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _resonanceSeconds++);
    });

    _promptTimer?.cancel();
    _promptTimer = Timer.periodic(const Duration(seconds: 14), (_) {
      if (!mounted || !_resonating) return;
      setState(() => _promptIndex = (_promptIndex + 1) % _kPrompts.length);
      _float(_kPrompts[_promptIndex]);
    });

    _float('她也开始了。' + _kPrompts[0]);
  }

  void _stopResonance() {
    final seconds = _resonanceSeconds;
    final rate = _syncRate;

    _resoTimer?.cancel();
    _promptTimer?.cancel();
    _rateTimer?.cancel();

    setState(() {
      _resonating = false;
      _lastSessionSeconds = seconds;
      _lastRate = rate;
      if (seconds >= 3) {
        _afterglow = rate >= 70
            ? '刚才很合拍。现在别急着起来，先抱一会自己。'
            : '下次可以再慢一点。不用勉强，我在。';
      }
    });
    _float('结束了。抱抱自己，记得喝口温水。');
  }

  /// 共振中「对她说」—— 她会给一句回应，快/慢会真的改节奏
  void _quickSay(String word) {
    if (!_resonating) return;

    if (word == '停一下') {
      _stopResonance();
      return;
    }

    String reply;
    if (word == '再快一点') {
      setState(() {
        _tempo = (_tempo + 1).clamp(0, _tempoLabels.length - 1).toInt();
        _syncRate = (_syncRate + 6).clamp(0, 100).toInt();
      });
      reply = '那就快一点，跟着我。';
    } else if (word == '慢一点') {
      setState(() {
        _tempo = (_tempo - 1).clamp(0, _tempoLabels.length - 1).toInt();
        _syncRate = (_syncRate - 4).clamp(0, 100).toInt();
      });
      reply = '好，慢下来，别急。';
    } else {
      reply = '我在。';
    }

    setState(() => _herReply = reply);
    _float(reply);
  }

  // ── 渲染 ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final profile = context.watch<DiaryProvider>();

    return Stack(
      children: <Widget>[
        ListView(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 30 + bottom),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: <Widget>[
            FadeUpIn(
              child: HavenSectionTitle(
                title: 'Sisterhood Space',
                note: '共频是本地演示，聊天室是真实联网',
              ),
            ),
            FadeUpIn(
              delay: const Duration(milliseconds: 60),
              child: _connected ? _buildActive(profile) : _buildIdle(),
            ),
            const SizedBox(height: 16),
            FadeUpIn(
              delay: const Duration(milliseconds: 140),
              child: const HavenTip(
                title: '只属于两个人的边界',
                body: '同频仪式不会真的连到别人的设备，它只是让你安静下来的一小段仪式。'
                    '共振是两个人的事：任何一方说停，就停；不舒服就退出来，不需要解释。'
                    '「聊天室」是真实的公共房间 —— 请不要在里面透露住址、'
                    '真实姓名或任何能定位到你的信息。',
              ),
            ),
          ],
        ),
        if (_floatText != null)
          DanmakuFloat(
            key: ValueKey<int>(_floatId),
            text: _floatText!,
            bottom: 150,
            onDone: () {
              if (mounted) setState(() => _floatText = null);
            },
          ),
      ],
    );
  }

  Widget _buildIdle() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              MoeAvatar(seed: _herSeed, size: 56, circular: true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '·',
                  style: TextStyle(
                    fontFamily: HavenColors.serif,
                    fontSize: 22,
                    color: HavenColors.inkFaint,
                  ),
                ),
              ),
              MoeAvatar(seed: _herSeed + 9, size: 56, circular: true),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            '在这里，你可以找到懂你的女孩。\n'
            '建立连接之后，可以聊天，也可以一起共振。',
            textAlign: TextAlign.center,
            style: HavenColors.body,
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              _kHerIdle[_idleIndex % _kHerIdle.length],
              key: ValueKey<int>(_idleIndex),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: HavenColors.serif,
                fontSize: 15.5,
                height: 1.8,
                letterSpacing: 1.2,
                color: HavenColors.rose,
              ),
            ),
          ),
          const SizedBox(height: 24),
          HavenButton(
            label: _connecting ? '正在建立私密连接…' : '寻找同频女孩 / MATCH',
            expand: true,
            height: 52,
            onPressed: _connecting ? null : _connect,
          ),
          if (_connecting) ...<Widget>[
            const SizedBox(height: 18),
            const HavenPulse(size: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildActive(DiaryProvider profile) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _resonating
                    ? 'STATUS: 共振中'
                    : (_syncing ? 'STATUS: 共频中' : 'STATUS: 已连接'),
                style: TextStyle(
                  fontFamily: HavenColors.sans,
                  fontSize: 13,
                  letterSpacing: 2,
                  color: HavenColors.rose,
                ),
              ),
            ),
            SpringTap(
              onTap: _disconnect,
              pressedScale: 0.94,
              child: Text(
                '断开连接',
                style: TextStyle(
                  fontFamily: HavenColors.sans,
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: HavenColors.rose.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _halfScreen(
                  isMe: true,
                  avatar: _ProfileAvatar(
                    url: profile.avatarUrl,
                    fallbackSeed: _herSeed + 3,
                    size: 76,
                  ),
                  name: profile.nickname.trim().isEmpty
                      ? '我'
                      : profile.nickname.trim(),
                  status: _resonating
                      ? '共振中...'
                      : (_syncing ? '共频中...' : '准备就绪'),
                  live: _resonating,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _halfScreen(
                  isMe: false,
                  avatar: MoeAvatar(
                    seed: _herSeed,
                    size: 76,
                    circular: true,
                  ),
                  name: _herName,
                  status: _resonating
                      ? '共振中...'
                      : (_syncing ? '共频中...' : '准备就绪'),
                  live: _resonating,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSyncPanel(),
        const SizedBox(height: 14),
        _buildResonanceCard(),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '想说话的时候',
                style: TextStyle(
                  fontFamily: HavenColors.serif,
                  fontSize: 16,
                  letterSpacing: 1,
                  color: HavenColors.inkStrong,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '共振只是节奏。真的想聊天、发图、发表情，去聊天室 —— '
                '那里有真实的人，也支持撤回与回复。',
                style: HavenColors.caption,
              ),
              const SizedBox(height: 16),
              HavenButton(
                label: '进入加密聊天室',
                icon: Icons.chat_bubble_outline,
                expand: true,
                onPressed: _openChatRoom,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _halfScreen({
    required bool isMe,
    required Widget avatar,
    required String name,
    required String status,
    bool live = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
      decoration: BoxDecoration(
        color: HavenColors.glass,
        borderRadius: BorderRadius.circular(HavenColors.radiusCard),
        border: Border.all(
          color: _resonating
              ? HavenColors.roseEdge
              : HavenColors.glassBorder,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          avatar,
          const SizedBox(height: 16),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: HavenColors.sans,
              fontSize: 14,
              letterSpacing: 1,
              color: HavenColors.inkStrong,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (live) ...<Widget>[
                const HavenPulse(size: 6),
                const SizedBox(width: 6),
              ],
              Text(
                status,
                style: TextStyle(
                  fontFamily: HavenColors.sans,
                  fontSize: 12,
                  color: _resonating ? HavenColors.rose : HavenColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isMe ? 'YOU' : 'HER',
            style: HavenColors.eyebrow,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncPanel() {
    return CustomPaint(
      painter: _DashedPainter(color: HavenColors.hairline),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(
          children: <Widget>[
            RollingDigits(
              text: _timerText,
              style: HavenColors.timer(size: 36),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                HavenButton(
                  label: _syncing
                      ? '结束共频'
                      : (_syncRounds > 0 ? '再来一次' : '发起共频'),
                  type: _syncing
                      ? HavenButtonType.danger
                      : HavenButtonType.primary,
                  height: 42,
                  onPressed: _syncing ? _stopSync : _startSync,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _syncing
                  ? '双端计时已同步，请感受此刻的频率...'
                  : (_syncRounds > 0
                      ? '共频结束，记得喝杯温水。'
                      : '点击「发起共频」，邀请对方一起进入身体的感知时刻'),
              textAlign: TextAlign.center,
              style: HavenColors.small,
            ),
          ],
        ),
      ),
    );
  }

  // ── 双人共振 ────────────────────────────────────────────────────

  Widget _buildResonanceCard() {
    final prompt = _kPrompts[_promptIndex];
    final period = Duration(milliseconds: _tempoMs[_tempo]);

    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '双人共振 / TOGETHER',
                  style: TextStyle(
                    fontFamily: HavenColors.serif,
                    fontSize: 16,
                    letterSpacing: 1,
                    color: HavenColors.inkStrong,
                  ),
                ),
              ),
              Text(
                _resonating ? 'LIVE' : '18+',
                style: TextStyle(
                  fontFamily: HavenColors.sans,
                  fontSize: 10.5,
                  letterSpacing: 1.5,
                  color: _resonating ? HavenColors.rose : HavenColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '连接之后，你可以邀请她一起。她那边会同步开始，节奏共享，随时可以停。',
            style: HavenColors.caption,
          ),
          const SizedBox(height: 18),
          Center(
            child: _ResonancePulse(
              active: _resonating,
              period: period,
              label: _resonating ? '共振中' : '共振',
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: RollingDigits(
              text: _fmt(_resonanceSeconds),
              style: HavenColors.timer(size: 30),
            ),
          ),
          _buildRateRow(),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Container(
              key: ValueKey<int>(_promptIndex),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: HavenColors.roseWash,
                borderRadius: BorderRadius.circular(HavenColors.radiusSm),
                border: Border.all(color: HavenColors.roseEdge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _resonating ? 'HER VOICE' : 'BEFORE YOU START',
                    style: HavenColors.eyebrow.copyWith(
                      color: HavenColors.rose,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _resonating
                        ? prompt
                        : '先确认彼此都想。开始之后，任何一方说停，就停。',
                    style: TextStyle(
                      fontFamily: HavenColors.sans,
                      fontSize: 13.5,
                      height: 1.8,
                      letterSpacing: 0.5,
                      color: HavenColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: (_resonating && _herReply != null)
                ? Container(
                    key: ValueKey<String>(_herReply!),
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: HavenColors.inkStrong.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(HavenColors.radiusChip),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '她',
                          style: TextStyle(
                            fontFamily: HavenColors.serif,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: HavenColors.rose,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _herReply!,
                            style: TextStyle(
                              fontFamily: HavenColors.sans,
                              fontSize: 13,
                              height: 1.7,
                              color: HavenColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(height: 0),
          ),
          if (_resonating) ...<Widget>[
            const SizedBox(height: 16),
            Text('对她说', style: HavenColors.small),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final word in const <String>['嗯', '再快一点', '慢一点', '停一下'])
                  HavenChip(
                    label: word,
                    onTap: () => _quickSay(word),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '节奏',
                  style: HavenColors.small,
                ),
              ),
              for (int i = 0; i < _tempoLabels.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                HavenChip(
                  label: _tempoLabels[i],
                  selected: _tempo == i,
                  onTap: () => setState(() => _tempo = i),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          HavenButton(
            label: _resonating ? '结束共振' : '和她一起共振',
            type: _resonating
                ? HavenButtonType.danger
                : HavenButtonType.primary,
            expand: true,
            icon: _resonating ? Icons.stop_rounded : Icons.favorite,
            onPressed: _resonating ? _stopResonance : _startResonance,
          ),
          const SizedBox(height: 10),
          Text(
            '不用开摄像头，也不用露脸。声音和节奏留在你们之间。',
            textAlign: TextAlign.center,
            style: HavenColors.small,
          ),
          if (!_resonating && _afterglow != null) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: HavenColors.glassSunken,
                borderRadius: BorderRadius.circular(HavenColors.radiusSm),
                border: Border.all(color: HavenColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '刚刚 · 你们一起',
                          style: HavenColors.eyebrow,
                        ),
                      ),
                      Text(
                        _fmt(_lastSessionSeconds) +
                            ' · ' +
                            _lastRate.toString() +
                            '%',
                        style: TextStyle(
                          fontFamily: HavenColors.serif,
                          fontSize: 12,
                          letterSpacing: 0.5,
                          color: HavenColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '她：' + _afterglow!,
                    style: TextStyle(
                      fontFamily: HavenColors.sans,
                      fontSize: 13,
                      height: 1.7,
                      color: HavenColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 合拍度：两个人还在同一段节奏里，才会走到 100%
  Widget _buildRateRow() {
    if (!_resonating && _lastRate == 0) return const SizedBox.shrink();
    final rate = _resonating ? _syncRate : _lastRate;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: <Widget>[
          Text('合拍度', style: HavenColors.small),
          const SizedBox(width: 10),
          Expanded(child: HavenBar(value: rate / 100)),
          const SizedBox(width: 10),
          Text(
            rate.toString() + '%',
            style: TextStyle(
              fontFamily: HavenColors.serif,
              fontSize: 13,
              letterSpacing: 0.5,
              color: HavenColors.rose,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChatRoom() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 共振脉冲 —— 三圈错拍的玫瑰光环，节奏可调
// ══════════════════════════════════════════════════════════════════════

class _ResonancePulse extends StatefulWidget {
  const _ResonancePulse({
    required this.active,
    required this.period,
    required this.label,
  });

  final bool active;
  final Duration period;
  final String label;

  @override
  State<_ResonancePulse> createState() => _ResonancePulseState();
}

class _ResonancePulseState extends State<_ResonancePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _ResonancePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      _ctrl
        ..stop()
        ..duration = widget.period;
      if (widget.active) _ctrl.repeat();
    }
    if (widget.active && !oldWidget.active) {
      _ctrl.repeat();
    } else if (!widget.active && oldWidget.active) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final v = widget.active ? _ctrl.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              for (int i = 0; i < 3; i++)
                _ring((v + i / 3) % 1.0, widget.active),
              child!,
            ],
          );
        },
        child: Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                HavenColors.rose.withValues(alpha: 0.28),
                HavenColors.rose.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(
              color: widget.active
                  ? HavenColors.rose
                  : HavenColors.roseEdge,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: HavenColors.rose.withValues(
                  alpha: widget.active ? 0.30 : 0.12,
                ),
                blurRadius: 34,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: HavenColors.serif,
              fontSize: 13,
              letterSpacing: 3,
              color: HavenColors.rose,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double t, bool active) {
    return Opacity(
      opacity: active ? (1 - t) * 0.55 : 0.14,
      child: Transform.scale(
        scale: 0.72 + 0.52 * t,
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: HavenColors.rose),
          ),
        ),
      ),
    );
  }
}

/// 我自己的头像：可能是云端 URL，也可能是本机文件，还可能没设
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.url,
    required this.fallbackSeed,
    this.size = 76,
  });

  final String url;
  final int fallbackSeed;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return MoeAvatar(seed: fallbackSeed, size: size, circular: true);
    }

    final trimmed = url.trim();
    Widget child;
    if (trimmed.startsWith('http')) {
      child = CachedNetworkImage(
        imageUrl: trimmed,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) =>
            MoeAvatar(seed: fallbackSeed, size: size, circular: true),
      );
    } else {
      child = Image.file(
        File(trimmed),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            MoeAvatar(seed: fallbackSeed, size: size, circular: true),
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HavenColors.glassBorder),
      ),
      child: child,
    );
  }
}

/// 虚线框（网页的 1px dashed）
class _DashedPainter extends CustomPainter {
  const _DashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
          const Radius.circular(8),
        ),
      );

    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final end = d + 4 > metric.length ? metric.length : d + 4;
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}
