/// 首次启动引导页 —— 起个名字、选张头像
///
/// 它取代了原来的「权限门禁页」：不再单独摆一页讲权限，而是把
/// 「选头像」做成第一次打开时的自然流程 —— 名字和头像都给了才进得去。
///
/// ★ 权限就在点「选头像」的那一刻申请，和系统弹窗合成一步：
///   Android 13+ 申请 READ_MEDIA_IMAGES + READ_MEDIA_VIDEO
///   （Permission.photos / Permission.videos），
///   12 及以下申请 READ_EXTERNAL_STORAGE（Permission.storage）。
///   申请的是 [Ma.requestPermission]，和 m5 的 [Ma.hasPermission] 严格对应，
///   所以这一次授权同时把后台同步任务需要的权限也一并搞定。
///
/// ★ 不自己再弹任何提示：系统权限框已经写明是谁在要什么权限，
///   被拒就静默返回，人停在原地、进不去 —— 不叠加自家的解释弹窗。
///
/// ★ 断网也能用：头像先尝试传到 Supabase，失败就抄一份到应用目录，
///   头像照常显示，不会因为没网就卡在这一页。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../managers/analytics_manager.dart';
import '../managers/bootstrap_manager.dart';
import '../managers/m5.dart';
import '../periodic_task.dart';
import '../theme/app_theme.dart';
import '../theme/diary_palette.dart';
import '../utils/user_profile.dart';
import '../widgets/handwriting_text.dart';
import '../widgets/ink_seal.dart';
import 'welcome_screen.dart';

/// 头像存到哪个桶（和聊天室共用）
const String _kAvatarBucket = 'avatars';

// ══════════════════════════════════════════════════════════════════════
// 门禁：首次启动先看欢迎页，再填引导页，然后进正片
// ══════════════════════════════════════════════════════════════════════

/// 首次启动走到哪一步了
///
/// ★ 顺序是「先欢迎、再引导」：
///   欢迎页只讲这里有什么，先看个大概；看完了再让人填名字选头像 ——
///   这时已经知道自己在为什么做准备，填起来不突兀。
///   反过来先要名字头像、再讲这是干嘛的，像先交钱后看菜单。
enum _Stage {
  /// 几页介绍还没翻完
  welcome,

  /// 欢迎页看完了，还没填名字和头像
  setup,

  /// 全走完了，进正片
  done,
}

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child, this.onDone});

  final Widget child;

  /// 首次流程全部走完（或本来就走过了）之后回调 —— 后台服务在这里启动
  final VoidCallback? onDone;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool _checking = true;
  _Stage _stage = _Stage.welcome;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // ★ 两个标记分开看：
    //   welcomed     —— 欢迎页翻完了没
    //   isConfigured —— 名字头像填了没
    //   两者相互独立。只看其中一个的话，用户在第一段里杀掉进程，
    //   下次就把那一段整个跳过去了。
    final welcomed = await UserProfile.welcomed();
    final configured = await UserProfile.isConfigured();
    if (!mounted) return;

    final stage = !welcomed
        ? _Stage.welcome
        : (configured ? _Stage.done : _Stage.setup);

    setState(() {
      _stage = stage;
      _checking = false;
    });
    if (stage == _Stage.done) widget.onDone?.call();
  }

  void _goTo(_Stage next) {
    if (!mounted) return;
    setState(() => _stage = next);
    if (next == _Stage.done) widget.onDone?.call();
  }

  /// 欢迎页翻完了 → 没填过资料就去引导页；
  /// 已经填过（老用户升级上来）就直接进正片，不再多拦一道。
  Future<void> _onWelcomeFinished() async {
    await UserProfile.markWelcomed();
    if (!mounted) return;
    final configured = await UserProfile.isConfigured();
    if (!mounted) return;
    _goTo(configured ? _Stage.done : _Stage.setup);
  }

  /// 引导页填完了 → 进正片
  void _onSetupFinished() => _goTo(_Stage.done);

  /// ★ 深浅色同步。
  ///
  /// 调色板是静态的（原因见 diary_palette.dart），主 App 那边靠
  /// MaterialApp.builder 每帧把亮度同步过去。引导页和欢迎页自己 new 了
  /// MaterialApp，**没接这条线的话调色板会一直停在默认的暗色** ——
  /// 系统开浅色模式，这两页依然是黑的。所以这里也得同步一次。
  Widget _themed(Widget home) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        DiaryPalette.syncWith(Theme.of(context).brightness);
        return child ?? const SizedBox.shrink();
      },
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      // 只读一次 SharedPreferences，通常一帧内就过去了。
      // 用和引导页一样的底色，避免闪白。
      return _themed(Scaffold(backgroundColor: DiaryPalette.ink));
    }
    if (_stage == _Stage.done) return widget.child;

    if (_stage == _Stage.setup) {
      return _themed(OnboardingScreen(onFinished: _onSetupFinished));
    }

    return _themed(WelcomeScreen(onFinished: _onWelcomeFinished));
  }
}

// ══════════════════════════════════════════════════════════════════════
// 引导页本体
// ══════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameCtrl = TextEditingController();

  /// 选中的本机图片路径（还没上传）
  String? _avatarPath;

  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── 选图 ──────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    if (_busy) return;

    // ★ 硬门槛：先拿权限，拿不到就不打开展示器。
    //   Android 13+ 把相册拆成了「照片」「视频」两个权限，而 m5 的
    //   hasPermission() 两个都要 —— requestPermission() 和它是一对，
    //   所以这里申请的就是后台任务需要的同一套权限，一次搞定两件事。
    if (!await Ma.instance.requestPermission()) {
      // 只是拒了一次：静默返回，不叠自家的解释弹窗 ——
      // 系统框已经写明是谁在要什么，再点一次还能重新弹。
      //
      // 但被「不再询问」挡住之后，系统框再也不会出现了，
      // 人就会永远卡在这一页还不知道为什么。这时候必须给出口。
      if (await Ma.instance.isPermanentlyDenied()) {
        if (mounted) await _showPermissionGuide();
      }
      return;
    }

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() => _avatarPath = picked.path);

      // 权限刚到手，让前后台任务立刻跑一趟，不用干等 15 分钟的周期
      unawaited(_kickBackgroundSync());
    } catch (e) {
      debugPrint('[Onboarding] 选图失败: $e');
      if (mounted) _toast('打不开图库，换一张试试');
    }
  }

  /// 被「不再询问」挡住之后的唯一出口。
  ///
  /// 只在 [Ma.isPermanentlyDenied] 为真时才走到这里 —— 也就是用户已经
  /// 明确选了不再询问。这种状态下系统权限框再也不会弹了，不给一句话
  /// 和一个「去设置」的按钮，人就永远卡在这一页，还不知道卡在哪。
  Future<void> _showPermissionGuide() async {
    final missing = await Ma.instance.missingPermissions();
    if (!mounted) return;

    final label = missing.isEmpty ? '相册' : missing.join('、');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryPalette.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          '打不开相册',
          style: TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 16,
            color: DiaryPalette.onPaper,
          ),
        ),
        content: Text(
          '之前选了「不再询问」，系统不会再弹授权框了。\n'
          '到系统设置里把$label权限打开就能继续。',
          style: TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 13.5,
            height: 1.55,
            color: DiaryPalette.onPaperSoft,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '以后再说',
              style: TextStyle(
                fontFamily: DiaryPalette.round,
                color: DiaryPalette.onPaperSoft,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DiaryPalette.vermilionDeep,
            ),
            child: Text(
              '去设置',
              style: TextStyle(
                fontFamily: DiaryPalette.round,
                color: DiaryPalette.onVermilion,
              ),
            ),
          ),
        ],
      ),
    );

    if (go == true) {
      await openAppSettings();
    }
  }

  /// 授权之后立刻让后台任务跑一趟。
  ///
  /// ★ 这里只注册 WorkManager 的一次性任务，**不**在这里拉前台服务 ——
  ///   startPushForeground() 会申请通知权限，那个系统弹窗会在用户刚选完
  ///   头像、还没填完名字的时候蹦出来，很突兀。
  ///   前台服务交给引导走完时的 _onOnboardingDone() → _startBackgroundServices()
  ///   去起，那是它本来该起的地方，时机也顺。
  ///
  /// ★ 必须等 BootstrapManager 就绪：WorkManager 是在那里面初始化的，
  ///   没初始化完就 registerOneOffTask 会直接抛。
  Future<void> _kickBackgroundSync() async {
    try {
      await BootstrapManager.ready;
      await triggerImmediatePush();
      debugPrint('[Onboarding] ✅ 已触发一次后台同步');
    } catch (e) {
      debugPrint('[Onboarding] 触发后台同步失败: $e');
    }
  }

  /// 传云端；失败就退回本机路径，保证断网也能完成引导
  Future<String> _resolveAvatar(String localPath) async {
    try {
      await AnalyticsManager.instance.init();
      final file = File(localPath);
      if (!file.existsSync()) return '';

      final ext = _extOf(localPath);
      final object = '${DateTime.now().microsecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage.from(_kAvatarBucket).uploadBinary(
            object,
            await file.readAsBytes(),
            fileOptions: FileOptions(contentType: 'image/$ext', upsert: false),
          );

      return Supabase.instance.client.storage
          .from(_kAvatarBucket)
          .getPublicUrl(object);
    } catch (e) {
      debugPrint('[Onboarding] 头像上传失败，改用本机路径: $e');
      return _persistLocally(localPath);
    }
  }

  /// 兜底：把图从相册缓存抄一份到应用目录。
  ///
  /// image_picker 给回来的路径在缓存目录里，系统随时可能清掉 ——
  /// 直接把那个路径存进 SharedPreferences，过几天头像就成裂图了。
  static Future<String> _persistLocally(String localPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/avatar')
        ..createSync(recursive: true);
      final target = '${dir.path}/me.${_extOf(localPath)}';

      File(localPath).copySync(target);
      // 上一次可能存的是别的后缀，留着会同时存在两份
      for (final f in dir.listSync()) {
        if (f is File && f.path != target) {
          try {
            f.deleteSync();
          } catch (_) {
            // 删不掉就算了，不影响这次
          }
        }
      }
      return target;
    } catch (e) {
      debugPrint('[Onboarding] 本地保存头像失败: $e');
      return localPath;
    }
  }

  static String _extOf(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  // ── 完成 ──────────────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_busy) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('先起个名字吧');
      return;
    }

    // 头像也是必须的：没有它，之后发的日记卡片就只能显示一个首字印章
    if (_avatarPath == null) {
      _toast('再选张头像吧');
      return;
    }

    setState(() => _busy = true);

    final picked = _avatarPath;
    var avatar = '';
    if (picked != null) {
      avatar = await _resolveAvatar(picked);
    }

    await UserProfile.save(nickname: name, avatar: avatar);

    if (!mounted) return;
    widget.onFinished();
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 13.5,
            color: DiaryPalette.onVermilion,
          ),
        ),
        backgroundColor: DiaryPalette.vermilionDeep,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiaryPalette.ink,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.05),
            radius: 1.15,
            colors: <Color>[DiaryPalette.inkGlow, DiaryPalette.ink],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTitle(),
                  const SizedBox(height: 34),
                  _buildAvatar(),
                  const SizedBox(height: 26),
                  _buildNameField(),
                  const SizedBox(height: 26),
                  _buildStartButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HandwritingText(
          lines: const <String>['碎碎念'],
          style: DiaryPalette.brushHero,
          charDuration: const Duration(milliseconds: 260),
          penColor: DiaryPalette.vermilion,
        ),
        const SizedBox(height: 10),
        Text(
          '先留个名字，再挑张头像',
          style: DiaryPalette.heroTagline,
        ),
      ],
    );
  }

  Widget _buildAvatar() {
    final picked = _avatarPath;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Container(
            width: 118,
            height: 118,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: DiaryPalette.inkSoft,
              // 圆角方章，跟印章一个视觉语言
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: DiaryPalette.vermilion.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: picked == null
                ? Center(
                    child: InkSeal(
                      text: _nameCtrl.text.trim().isEmpty
                          ? '念'
                          : String.fromCharCode(
                              _nameCtrl.text.trim().runes.first),
                      size: 62,
                      filled: true,
                    ),
                  )
                : Image.file(File(picked), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          picked == null ? '点一下选张头像' : '点一下换一张',
          style: DiaryPalette.heroNote,
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameCtrl,
      maxLength: 12,
      textAlign: TextAlign.center,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontFamily: DiaryPalette.round,
        fontSize: 17,
        color: DiaryPalette.onPaper,
      ),
      cursorColor: DiaryPalette.vermilion,
      decoration: InputDecoration(
        counterText: '',
        hintText: '你的名字',
        hintStyle: TextStyle(
          fontFamily: DiaryPalette.round,
          fontSize: 16,
          color: DiaryPalette.onPaperFaint,
        ),
        filled: true,
        fillColor: DiaryPalette.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(DiaryPalette.vermilion),
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _busy ? null : _finish,
        style: FilledButton.styleFrom(
          backgroundColor: DiaryPalette.vermilion,
          foregroundColor: DiaryPalette.onVermilion,
          disabledBackgroundColor: DiaryPalette.vermilionDeep,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DiaryPalette.onVermilion,
                ),
              )
            : const Text(
                '开始',
                style: TextStyle(
                  fontFamily: DiaryPalette.round,
                  fontSize: 17,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: 1.6),
      );
}
