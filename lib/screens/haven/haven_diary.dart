/// 私语 —— 网页「私语日记」与原有「碎碎念」动态墙的融合页
///
/// 融合方式（不是两个 tab，而是**一条时间线**）：
///   • 页头下面是一张「写给自己」的表单：日期 / 情绪 / 身体感受 /
///     注意力程度 / 想说的话 —— 存本机，永不上传。
///   • 表单下面一行「写一条碎碎念」，打开原有的发布卡片（配图 / 标题 /
///     地区 / 匿名 / 心情），发到动态墙。
///   • 再往下是**合并后的时间线**：自己的私密日记和所有人的碎碎念
///     按时间倒序混在一起，私密条目带「仅本机」标记。
///     于是「写给自己的」和「写给大家的」终于在同一张纸上。
///
/// ★ 视觉沿用原有那套弹簧语言：页头手写体、卡片进场、FAB 按压，
///   但颜色/字体/圆角全部走 HavenColors —— 和网页是同一套 tokens。
/// ★ MD3 组件（Slider / 日期选择器 / 对话框 / 输入框）没有替换，
///   只把它们的配色接到 Haven 主题上，所以交互手感和原 App 完全一致。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/diary_post.dart';
import '../../models/haven_models.dart';
import '../../providers/diary_provider.dart';
import '../../repository/haven_store.dart';
import '../../theme/diary_palette.dart';
import '../../theme/haven.dart';
import '../../theme/springs.dart';
import '../../utils/spring_scroll.dart';
import '../../widgets/diary_card.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/handwriting_text.dart';
import '../../widgets/haven_widgets.dart';
import '../../widgets/ink_seal.dart';
import '../../widgets/spring_tap.dart';
import '../diary_comments_sheet.dart';
import '../diary_compose_sheet.dart';

/// 页头循环书写的那几句话（只用了衬线子集里已有的字）
const List<String> _kWhispers = <String>[
  '今天也没发生什么大事',
  '但身体有点想你',
  '想被怎样对待，写下来',
  '夜里，手心是热的',
  '写下来就不算白过了',
  '要记得好好吃饭',
  '今天也是很好的一天',
  '把心事写下来就轻一点了',
];

/// 时间线上的一个条目：私密日记 或 碎碎念
class _TimelineItem {
  _TimelineItem.privateDiary(PrivateDiaryEntry e)
      : entry = e,
        post = null,
        at = e.date;

  _TimelineItem.post(DiaryPost p)
      : post = p,
        entry = null,
        at = p.createdAt;

  final PrivateDiaryEntry? entry;
  final DiaryPost? post;
  final DateTime at;
}

class HavenDiaryView extends StatefulWidget {
  const HavenDiaryView({super.key});

  @override
  State<HavenDiaryView> createState() => _HavenDiaryViewState();
}

class _HavenDiaryViewState extends State<HavenDiaryView>
    // springScrollTo 每次都会新建控制器，必须用复数那个 mixin
    with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _noteCtrl = TextEditingController();

  List<PrivateDiaryEntry> _entries = const <PrivateDiaryEntry>[];

  DateTime _date = DateTime.now();
  String _mood = kHavenMoods[0];
  final Set<String> _tags = <String>{};
  int _intensity = 0;

  /// 时间线筛选：0 全部 / 1 只给自己 / 2 碎碎念
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── 数据 ────────────────────────────────────────────────────────

  Future<void> _loadEntries() async {
    final list = await HavenStore.loadPrivateDiary();
    if (!mounted) return;
    setState(() => _entries = list);
  }

  Future<void> _refreshAll(DiaryProvider provider) async {
    await Future.wait<void>(<Future<void>>[
      provider.refresh(),
      _loadEntries(),
    ]);
  }

  // ── 写给自己的那一页 ────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '好',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _savePrivate() async {
    final note = _noteCtrl.text.trim();
    if (note.isEmpty && _tags.isEmpty && _mood.isEmpty) {
      showHavenToast(context, '写点什么再保存吧');
      return;
    }

    final entry = PrivateDiaryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      mood: _mood,
      tags: _tags.toList(growable: false),
      intensity: _intensity,
      note: note,
    );

    final next = <PrivateDiaryEntry>[entry, ..._entries];
    setState(() {
      _entries = next;
      _noteCtrl.clear();
      _tags.clear();
      _intensity = 0;
      _date = DateTime.now();
    });
    await HavenStore.savePrivateDiary(next);
    if (!mounted) return;
    showHavenToast(context, '已收好，只留在这台设备里');
    _scrollToTop();
  }

  Future<void> _deletePrivate(PrivateDiaryEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删掉这一页？'),
        content: const Text('这一条只在本机，删了就没有了。'),
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
    await HavenStore.savePrivateDiary(next);
    if (mounted) showHavenToast(context, '已删掉');
  }

  // ── 碎碎念 ──────────────────────────────────────────────────────

  Future<void> _openCompose() async {
    final provider = context.read<DiaryProvider>();
    final before = provider.posts.length;

    await showDiaryComposeSheet(
      context,
      initialName: provider.nickname,
      initialAnonymous: provider.anonymous,
      initialAvatar: provider.avatarUrl,
    );

    if (!mounted) return;
    if (provider.posts.length > before) _scrollToTop();
  }

  Future<void> _openComments(String postId) async {
    final provider = context.read<DiaryProvider>();
    await showDiaryCommentsSheet(
      context,
      postId: postId,
      initialName: provider.nickname,
      initialAnonymous: provider.anonymous,
    );
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    springScrollTo(_scroll.position, 0, vsync: this, spring: Springs.settle);
  }

  double _tiltFor(DiaryPost post) {
    final bucket = post.id.hashCode.abs() % 3;
    return (bucket - 1) * 0.006;
  }

  // ── 时间线 ──────────────────────────────────────────────────────

  List<_TimelineItem> _buildTimeline(DiaryProvider provider) {
    final items = <_TimelineItem>[
      if (_filter != 2)
        for (final e in _entries) _TimelineItem.privateDiary(e),
      if (_filter != 1)
        for (final p in provider.posts) _TimelineItem.post(p),
    ];
    items.sort((a, b) => b.at.compareTo(a.at));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiaryProvider>();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final items = _buildTimeline(provider);

    return RefreshIndicator(
      onRefresh: () => _refreshAll(provider),
      color: HavenColors.rose,
      backgroundColor: HavenColors.glass,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 40 + bottom),
        itemCount: items.isEmpty ? 2 : items.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildHeader(provider);
          if (items.isEmpty) return _buildEmptyTimeline();

          final item = items[index - 1];
          final entry = item.entry;
          if (entry != null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _privateCard(entry),
            );
          }

          final post = item.post!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(9, 0, 9, 12),
            child: RepaintBoundary(
              child: DiaryCard(
                post: post,
                mine: post.isMine(provider.deviceId),
                tilt: _tiltFor(post),
                commentCount: provider.commentCountFor(post.id),
                onComment: () => _openComments(post.id),
                reactionCounts: provider.reactionCountsFor(post.id),
                myReactions: provider.myReactionsFor(post.id),
                onReact: (emoji) => provider.toggleReaction(post.id, emoji),
                onDelete: () async {
                  await provider.remove(post);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyTimeline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.auto_stories_outlined,
            size: 34,
            color: HavenColors.inkFaint,
          ),
          const SizedBox(height: 14),
          Text(
            _filter == 1
                ? '还没有写给自己的页'
                : (_filter == 2 ? '动态墙还空着' : '还没有写过什么'),
            style: HavenColors.label,
          ),
          const SizedBox(height: 6),
          Text(
            _filter == 1 ? '上面那张表单，第一页留给你' : '第一句留给你',
            style: HavenColors.small,
          ),
        ],
      ),
    );
  }

  // ── 页头 + 表单 + 筛选 ──────────────────────────────────────────

  Widget _buildHeader(DiaryProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: HandwritingText(
                  lines: const <String>['私语'],
                  style: DiaryPalette.brushHero.copyWith(fontSize: 36),
                  charDuration: const Duration(milliseconds: 260),
                  startDelay: const Duration(milliseconds: 120),
                  penColor: DiaryPalette.vermilion,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkSeal(text: '语', size: 34),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '只有全然的接纳与共振',
            style: DiaryPalette.heroTagline,
          ),
          const SizedBox(height: 4),
          Text(
            'Every word stays with you.',
            style: DiaryPalette.heroTaglineEn,
          ),
          const SizedBox(height: 14),
          HandwritingText(
            lines: _kWhispers,
            style: DiaryPalette.brushLine.copyWith(fontSize: 19),
            loop: true,
            charDuration: const Duration(milliseconds: 120),
            holdDuration: const Duration(milliseconds: 2200),
            fadeDuration: const Duration(milliseconds: 420),
            gapDuration: const Duration(milliseconds: 260),
            startDelay: const Duration(milliseconds: 120),
            penColor: DiaryPalette.vermilion,
          ),
          const SizedBox(height: 20),
          _buildPrivateForm(),
          const SizedBox(height: 12),
          _buildComposeRow(),
          const SizedBox(height: 20),
          _buildFilterRow(provider),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildPrivateForm() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '写给自己',
                  style: HavenColors.viewTitle,
                ),
              ),
              Text('仅本机', style: HavenColors.small),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '写下来不是为了被谁看见，是为了别把自己弄丢。',
            style: HavenColors.caption,
          ),
          const SizedBox(height: 20),
          const HavenFieldLabel('日期'),
          HavenFieldTile(value: _fmtDate(_date), onTap: _pickDate),
          const SizedBox(height: 20),
          const HavenFieldLabel('今日情绪'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final m in kHavenMoods)
                HavenChip(
                  label: m,
                  selected: _mood == m,
                  onTap: () => setState(() => _mood = m),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const HavenFieldLabel('身体感受'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final t in kHavenBodyTags)
                HavenChip(
                  label: t,
                  selected: _tags.contains(t),
                  onTap: () => setState(() {
                    if (!_tags.remove(t)) _tags.add(t);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          HavenFieldLabel(
            '注意力程度',
            accent: kHavenIntensityLabels[_intensity],
          ),
          SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _intensity.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              onChanged: (v) => setState(() => _intensity = v.round()),
            ),
          ),
          const SizedBox(height: 8),
          const HavenFieldLabel('想对自己说些什么'),
          HavenTextField(
            controller: _noteCtrl,
            hint: '今晚想被怎样对待，写下来……',
            minLines: 4,
            maxLines: 8,
          ),
          const SizedBox(height: 18),
          HavenButton(label: '保存这一页', expand: true, onPressed: _savePrivate),
        ],
      ),
    );
  }

  Widget _buildComposeRow() {
    return SpringTap(
      onTap: _openCompose,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: HavenColors.glass,
          borderRadius: BorderRadius.circular(HavenColors.radiusCard),
          border: Border.all(color: HavenColors.glassBorder),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HavenColors.roseWash,
                borderRadius: BorderRadius.circular(HavenColors.radiusChip),
                border: Border.all(color: HavenColors.roseEdge),
              ),
              child: Icon(Icons.edit_outlined, size: 18, color: HavenColors.rose),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '写一条碎碎念',
                    style: HavenColors.cardTitle,
                  ),
                  const SizedBox(height: 4),
                  Text('配图、标题、匿名，发到动态墙上', style: HavenColors.small),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 13,
              color: HavenColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow(DiaryProvider provider) {
    final privateCount = _entries.length;
    final postCount = provider.posts.length;

    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              HavenChip(
                label: '全部 ' + (privateCount + postCount).toString(),
                selected: _filter == 0,
                onTap: () => setState(() => _filter = 0),
              ),
              HavenChip(
                label: '只给自己 ' + privateCount.toString(),
                selected: _filter == 1,
                onTap: () => setState(() => _filter = 1),
              ),
              HavenChip(
                label: '碎碎念 ' + postCount.toString(),
                selected: _filter == 2,
                onTap: () => setState(() => _filter = 2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 私密日记卡 ──────────────────────────────────────────────────

  Widget _privateCard(PrivateDiaryEntry entry) {
    return GlassCard(
      // 列表里关掉背景模糊：底色够暗，省掉每帧一次高斯模糊
      blur: false,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.mood.isEmpty ? '这一天' : entry.mood,
                  style: TextStyle(
                    fontFamily: HavenColors.serif,
                    fontSize: 16,
                    letterSpacing: 1,
                    color: HavenColors.inkStrong,
                  ),
                ),
              ),
              Text(
                _fmtDate(entry.date),
                style: TextStyle(
                  fontFamily: HavenColors.serif,
                  fontSize: 12,
                  letterSpacing: 1,
                  color: HavenColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: HavenColors.roseEdge),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  '仅本机',
                  style: TextStyle(
                    fontFamily: HavenColors.sans,
                    fontSize: 10.5,
                    letterSpacing: 1,
                    color: HavenColors.rose,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              for (final t in entry.tags) ...<Widget>[
                HavenChip(label: t, fixed: true),
                const SizedBox(width: 8),
              ],
            ],
          ),
          if (entry.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(entry.note, style: HavenColors.bodyOnGlass),
          ],
          const SizedBox(height: 16),
          HavenBar(value: entry.intensity / 5),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '注意力 · ' +
                      kHavenIntensityLabels[
                          entry.intensity.clamp(0, 5).toInt()],
                  style: HavenColors.small,
                ),
              ),
              SpringTap(
                onTap: () => _deletePrivate(entry),
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

String _fmtDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return d.year.toString() + '.' + m + '.' + day;
}
