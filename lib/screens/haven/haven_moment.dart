/// 身体时刻 —— 网页 Her Body & Pleasure 的 1:1 还原
///
/// 一块实时计时器、一个时长滑杆、三段自由书写、一个「是否疼痛」开关，
/// 下面是写过的记录。所有内容只写本机。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/haven_models.dart';
import '../../repository/haven_store.dart';
import '../../theme/haven.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/haven_widgets.dart';
import '../../widgets/spring_tap.dart';

class HavenMomentView extends StatefulWidget {
  const HavenMomentView({super.key});

  @override
  State<HavenMomentView> createState() => _HavenMomentViewState();
}

class _HavenMomentViewState extends State<HavenMomentView> {
  final TextEditingController _beforeCtrl = TextEditingController();
  final TextEditingController _duringCtrl = TextEditingController();
  final TextEditingController _afterCtrl = TextEditingController();

  List<MomentEntry> _entries = const <MomentEntry>[];
  bool _loading = true;

  // ── 计时器 ──────────────────────────────────────────────────────
  Timer? _ticker;
  int _elapsed = 0;
  bool _running = false;

  DateTime _at = DateTime.now();
  int _duration = 0;
  String _state = kHavenMomentStates[0];
  bool _pain = false;

  // ── 详细记录（都可以不填）─────────────────────────────────────
  final Set<String> _methods = <String>{};
  int _pleasure = 0;
  bool _orgasm = false;
  int _orgasmCount = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _beforeCtrl.dispose();
    _duringCtrl.dispose();
    _afterCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await HavenStore.loadMoments();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  // ── 计时 ────────────────────────────────────────────────────────

  String get _timerText {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return m + ':' + s;
  }

  void _toggleTimer() {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() {
      _running = true;
      if (_elapsed == 0) _at = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
    });
  }

  /// 结束并填入时长 —— 网页会把秒数折算成 5 的倍数
  void _stopAndFill() {
    _ticker?.cancel();
    var minutes = (_elapsed / 60).round();
    if (minutes > 0 && minutes < 5) minutes = 5;
    if (minutes > 60) minutes = 60;
    minutes = (minutes / 5).round() * 5;

    setState(() {
      _running = false;
      _duration = minutes;
    });
    showHavenToast(
      context,
      minutes == 0 ? '还没满一分钟，先归零了' : '记下 ' + minutes.toString() + ' 分钟',
    );
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted || _running) return;
      setState(() => _elapsed = 0);
    });
  }

  // ── 日期时间 ────────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '好',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      helpText: '选择时间',
      cancelText: '取消',
      confirmText: '好',
    );
    if (!mounted) return;

    final t = time ?? TimeOfDay.fromDateTime(_at);
    setState(() {
      _at = DateTime(date.year, date.month, date.day, t.hour, t.minute);
    });
  }

  // ── 保存 ────────────────────────────────────────────────────────

  Future<void> _save() async {
    final before = _beforeCtrl.text.trim();
    final during = _duringCtrl.text.trim();
    final after = _afterCtrl.text.trim();

    final hasDetail = _methods.isNotEmpty || _pleasure > 0 || _orgasm;
    if (before.isEmpty &&
        during.isEmpty &&
        after.isEmpty &&
        _duration == 0 &&
        !hasDetail) {
      showHavenToast(context, '至少记一点什么呀');
      return;
    }

    final entry = MomentEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      at: _at,
      minutes: _duration,
      state: _state,
      before: before,
      during: during,
      after: after,
      pain: _pain,
      methods: _methods.toList(growable: false),
      pleasure: _pleasure,
      orgasm: _orgasm,
      orgasmCount: _orgasm ? _orgasmCount : 0,
    );

    final next = <MomentEntry>[entry, ..._entries];
    setState(() {
      _entries = next;
      _beforeCtrl.clear();
      _duringCtrl.clear();
      _afterCtrl.clear();
      _duration = 0;
      _elapsed = 0;
      _pain = false;
      _methods.clear();
      _pleasure = 0;
      _orgasm = false;
      _orgasmCount = 1;
      _at = DateTime.now();
    });
    await HavenStore.saveMoments(next);
    if (mounted) showHavenToast(context, '收好了，记得对自己温柔一点');
  }

  void _clearForm() {
    setState(() {
      _beforeCtrl.clear();
      _duringCtrl.clear();
      _afterCtrl.clear();
      _duration = 0;
      _elapsed = 0;
      _pain = false;
      _state = kHavenMomentStates[0];
      _methods.clear();
      _pleasure = 0;
      _orgasm = false;
      _orgasmCount = 1;
    });
  }

  Future<void> _delete(MomentEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删掉这条记录？'),
        content: const Text('只在本机，删了就找不回来了。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('留着'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: HavenColors.rose),
            child: const Text('删掉'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final next = _entries.where((e) => e.id != entry.id).toList(growable: false);
    setState(() => _entries = next);
    await HavenStore.saveMoments(next);
    if (mounted) showHavenToast(context, '已删掉');
  }

  // ── 渲染 ────────────────────────────────────────────────────────

  int get _totalMinutes =>
      _entries.fold<int>(0, (sum, e) => sum + e.minutes);

  int get _avgMinutes {
    if (_entries.isEmpty) return 0;
    return (_totalMinutes / _entries.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 6, 20, 30 + bottom),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: <Widget>[
        FadeUpIn(
          child: HavenSectionTitle(
            title: 'Her Body & Pleasure',
            note: '私密探索记录',
          ),
        ),
        FadeUpIn(
          delay: const Duration(milliseconds: 60),
          child: Row(
            children: <Widget>[
              Expanded(
                child: HavenStat(
                  value: _entries.length.toString(),
                  label: '记录',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HavenStat(
                  value: _totalMinutes.toString(),
                  label: '总分钟',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HavenStat(
                  value: _avgMinutes.toString(),
                  label: '平均',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FadeUpIn(
          delay: const Duration(milliseconds: 120),
          child: GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildTimerPanel(),
                const SizedBox(height: 22),
                const HavenFieldLabel('时间'),
                HavenFieldTile(
                  value: _fmtDateTime(_at),
                  onTap: _pickDateTime,
                  icon: Icons.schedule_outlined,
                ),
                const SizedBox(height: 22),
                HavenFieldLabel(
                  '持续时长',
                  accent: _duration == 0
                      ? '未记录'
                      : _duration.toString() + ' min',
                ),
                SliderTheme(
                  data: _sliderTheme(),
                  child: Slider(
                    value: _duration.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 12,
                    onChanged: (v) =>
                        setState(() => _duration = v.round()),
                  ),
                ),
                const SizedBox(height: 10),
                const HavenFieldLabel('当时状态'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final s in kHavenMomentStates)
                      HavenChip(
                        label: s,
                        selected: _state == s,
                        onTap: () => setState(() => _state = s),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const HavenFieldLabel('开始前'),
                HavenTextField(
                  controller: _beforeCtrl,
                  hint: '情绪、灯光、想被怎样对待……',
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 18),
                const HavenFieldLabel('过程中'),
                HavenTextField(
                  controller: _duringCtrl,
                  hint: '感受的变化、节奏、呼吸……',
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 18),
                const HavenFieldLabel('结束后'),
                HavenTextField(
                  controller: _afterCtrl,
                  hint: '身体反馈、想要的拥抱……',
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 22),
                _buildDetails(),
                const SizedBox(height: 8),
                HavenSettingRow(
                  title: '是否有疼痛或不适',
                  description: '勾选后会出现护理提示',
                  trailing: HavenSwitch(
                    value: _pain,
                    onChanged: (v) => setState(() => _pain = v),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _pain
                      ? _DashedWarn(
                          text: '女孩，请务必关注自己的身体反馈。如果出现持续疼痛、异常出血或'
                              '事后长时间不适，请记录症状并尽快咨询妇科医生。不要独自忍受。',
                        )
                      : const SizedBox(height: 0),
                ),
                const SizedBox(height: 18),
                HavenButton(
                  label: '保存记录',
                  expand: true,
                  onPressed: _save,
                ),
                const SizedBox(height: 10),
                HavenButton(
                  label: '清空重填',
                  type: HavenButtonType.ghost,
                  expand: true,
                  onPressed: _clearForm,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: HavenPulse(size: 8)),
          )
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: <Widget>[
                Icon(
                  Icons.spa_outlined,
                  size: 32,
                  color: HavenColors.inkFaint,
                ),
                const SizedBox(height: 12),
                Text('还没有记录', style: HavenColors.label),
                const SizedBox(height: 6),
                Text('每一次感受都值得被认真对待', style: HavenColors.small),
              ],
            ),
          )
        else ...<Widget>[
          Text('写过的时刻', style: HavenColors.eyebrow),
          const SizedBox(height: 12),
          for (final entry in _entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _entryCard(entry),
            ),
        ],
      ],
    );
  }

  // ── 详细记录 ────────────────────────────────────────────────────

  Widget _buildDetails() {
    return Container(
      width: double.infinity,
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
                  'DETAILS · 详细记录',
                  style: HavenColors.eyebrow,
                ),
              ),
              Text('不填也行', style: HavenColors.small),
            ],
          ),
          const SizedBox(height: 16),
          const HavenFieldLabel('方式（可多选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final m in kHavenMethods)
                HavenChip(
                  label: m,
                  selected: _methods.contains(m),
                  onTap: () => setState(() {
                    if (!_methods.remove(m)) _methods.add(m);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          HavenFieldLabel(
            '强度',
            accent: kHavenPleasureLabels[_pleasure.clamp(0, 5).toInt()],
          ),
          SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _pleasure.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              onChanged: (v) => setState(() => _pleasure = v.round()),
            ),
          ),
          const SizedBox(height: 2),
          HavenSettingRow(
            title: '去了吗',
            description: '不想记就留空，没人会问',
            trailing: HavenSwitch(
              value: _orgasm,
              onChanged: (v) => setState(() => _orgasm = v),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _orgasm
                ? Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text('几次', style: HavenColors.label),
                        ),
                        _Stepper(
                          value: _orgasmCount,
                          onChanged: (v) => setState(() => _orgasmCount = v),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(height: 0),
          ),
          const SizedBox(height: 10),
          Text(
            '结束之后：清洗、补水、抱一会自己。',
            style: HavenColors.small,
          ),
        ],
      ),
    );
  }

  Widget _buildTimerPanel() {
    return CustomPaint(
      painter: _DashedRRectPainter(color: HavenColors.hairline),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: <Widget>[
            Text('REALTIME TIMER', style: HavenColors.eyebrow),
            const SizedBox(height: 12),
            RollingDigits(
              text: _timerText,
              style: HavenColors.timer(size: 40, color: HavenColors.rose),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                HavenButton(
                  label: _running
                      ? '暂停'
                      : (_elapsed == 0 ? '开始' : '继续'),
                  onPressed: _toggleTimer,
                  height: 42,
                ),
                if (_elapsed > 0) ...<Widget>[
                  const SizedBox(width: 10),
                  HavenButton(
                    label: '结束并填入',
                    type: HavenButtonType.danger,
                    onPressed: _running ? _stopAndFill : null,
                    height: 42,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(MomentEntry entry) {
    return GlassCard(
      blur: false,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.state,
                  style: TextStyle(
                    fontFamily: HavenColors.serif,
                    fontSize: 15.5,
                    letterSpacing: 1,
                    color: HavenColors.inkStrong,
                  ),
                ),
              ),
              Text(
                _fmtDateTime(entry.at),
                style: TextStyle(
                  fontFamily: HavenColors.serif,
                  fontSize: 11.5,
                  letterSpacing: 0.5,
                  color: HavenColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (entry.minutes > 0)
                HavenChip(label: entry.minutes.toString() + ' min', fixed: true),
              for (final m in entry.methods) HavenChip(label: m, fixed: true),
              if (entry.orgasm)
                HavenChip(
                  label: '去了 ' + entry.orgasmCount.toString() + ' 次',
                  fixed: true,
                ),
              if (entry.pain)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: HavenColors.rose),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '需要照顾自己',
                    style: TextStyle(
                      fontFamily: HavenColors.sans,
                      fontSize: 10.5,
                      letterSpacing: 1,
                      color: HavenColors.rose,
                    ),
                  ),
                ),
            ],
          ),
          if (entry.pleasure > 0) ...<Widget>[
            const SizedBox(height: 14),
            HavenBar(value: entry.pleasure / 5),
            const SizedBox(height: 6),
            Text(
              '强度 · ' +
                  kHavenPleasureLabels[
                      entry.pleasure.clamp(0, 5).toInt()],
              style: HavenColors.small,
            ),
          ],
          if (entry.before.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _noteBlock('开始前', entry.before),
          ],
          if (entry.during.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _noteBlock('过程中', entry.during),
          ],
          if (entry.after.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _noteBlock('结束后', entry.after),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Spacer(),
              SpringTap(
                onTap: () => _delete(entry),
                pressedScale: 0.94,
                child: Text(
                  '删除',
                  style: TextStyle(
                    fontFamily: HavenColors.sans,
                    fontSize: 12,
                    letterSpacing: 0.5,
                    color: HavenColors.rose.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteBlock(String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: HavenColors.sans,
            fontSize: 11,
            letterSpacing: 1.5,
            color: HavenColors.inkFaint,
          ),
        ),
        const SizedBox(height: 6),
        Text(text, style: HavenColors.bodyOnGlass),
      ],
    );
  }

  SliderThemeData _sliderTheme() {
    return SliderTheme.of(context).copyWith(
      activeTrackColor: HavenColors.rose,
      inactiveTrackColor: HavenColors.inkStrong.withValues(alpha: 0.08),
      thumbColor: HavenColors.rose,
      overlayColor: HavenColors.rose.withValues(alpha: 0.12),
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
    );
  }
}

String _fmtDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return d.year.toString() +
      '.' +
      two(d.month) +
      '.' +
      two(d.day) +
      ' ' +
      two(d.hour) +
      ':' +
      two(d.minute);
}

/// 次数加减 —— 30×30 的方角小按钮，按下去有弹簧
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 9,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _button(Icons.remove, value > min ? () => onChanged(value - 1) : null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            value.toString() + ' 次',
            style: TextStyle(
              fontFamily: HavenColors.serif,
              fontSize: 17,
              letterSpacing: 1,
              color: HavenColors.inkStrong,
            ),
          ),
        ),
        _button(Icons.add, value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }

  Widget _button(IconData icon, VoidCallback? onTap) {
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HavenColors.radiusChip),
          border: Border.all(color: HavenColors.hairline),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? HavenColors.inkGhost : HavenColors.rose,
        ),
      ),
    );
  }
}

/// .warn —— 玫瑰色虚线框的护理提示
class _DashedWarn extends StatelessWidget {
  const _DashedWarn({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: HavenColors.rose),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: HavenColors.sans,
            fontSize: 12.5,
            height: 1.8,
            color: HavenColors.rose,
          ),
        ),
      ),
    );
  }
}

/// 网页里 details / .warn 用的 dashed border，Flutter 没有现成实现，
/// 用 PathMetrics 把圆角矩形切成一段段短线。
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    this.radius = 8,
    this.dash = 4,
    this.gap = 4,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;

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
          Radius.circular(radius),
        ),
      );

    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}
