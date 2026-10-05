/// 首页 — 液态玻璃主题 + 统一深灰色 MD3 背景
///
/// 三个位置：
///   0 = 碎碎念（日记分享动态）
///   1 = 白丝宝宝（上下滑动视频）
///   2 = 聊天室（独立页面入口，不切 tab）
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:suisuinian/providers/nav_bar_visibility.dart';
import 'package:suisuinian/theme/app_theme.dart';
import 'package:suisuinian/screens/diary_screen.dart';
import 'package:suisuinian/screens/swipe_video_screen.dart';
import 'package:suisuinian/screens/chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  /// PageView 只有两页：0 = 碎碎念，1 = 视频
  int _page = 0;

  /// 底栏有 3 个位置：0 = 碎碎念，1 = 聊天室（push 独立页面），2 = 视频
  /// ★ 聊天室在中间，所以底栏下标和 PageView 下标不是一回事，必须显式映射
  int get _barIndex => _page == 1 ? 2 : 0;

  final PageController _pageController = PageController(initialPage: 0);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavBarVisibility>();

    return LiquidGlassScope.stack(
      background: Container(color: AppTheme.surfaceColor),
      content: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          physics: const PageScrollPhysics(),
          children: [
            // ── Page 0: 碎碎念 ──
            const DiaryScreen(),

            // ── Page 1: 上下滑动视频 ──
            SwipeVideoScreen(active: _page == 1),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: AnimatedSlide(
          offset: nav.visible ? Offset.zero : const Offset(0, 1.3),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          child: _buildBottomNav(),
        ),
      ),
    );
  }

  // ── 翻页回调 ─────────────────────────────────────────────────────────────
  void _onPageChanged(int i) {
    setState(() => _page = i);
    context.read<NavBarVisibility>().show();
  }

  // ══════════════════════════════════════════════════════════════
  // ★ 进入独立聊天室页面
  // ══════════════════════════════════════════════════════════════
  Future<void> _openChatRoom() async {
    // 切换底栏的显示状态，让聊天页顶部状态栏图标可见
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => const ChatScreen(),
      ),
    );
    // 返回后恢复底栏
    if (mounted) {
      context.read<NavBarVisibility>().show();
    }
  }

  // ── 底部导航 ★ 三个位置，中间那个是聊天室入口────────────────────
  Widget _buildBottomNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: GlassBottomBar(
          selectedIndex: _barIndex,
          onTabSelected: (i) {
            // ★ 中间位置 → 进入独立聊天室页面（不改变当前页）
            if (i == 1) {
              _openChatRoom();
              return;
            }

            // 碎碎念(0) / 视频(2) → 切到对应 PageView 页
            _pageController.animateToPage(
              i == 2 ? 1 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          },
          tabs: [
            GlassBottomBarTab(
              label: '碎碎念',
              icon: Icons.create,
              selectedIcon: Icons.create,
              glowColor: AppTheme.accentColor,
            ),
            // ★ 聊天室 = 入口按钮（点击进入独立页面），放在中间
            GlassBottomBarTab(
              label: '聊天室',
              icon: Icons.chat_bubble,
              selectedIcon: Icons.chat_bubble_outline,
              glowColor: const Color(0xFF64B5EF),
            ),
            // 视频页（原来是第 2 个位置，和聊天室对调了）
            GlassBottomBarTab(
              label: '白丝宝宝',
              icon: Icons.auto_awesome,
              selectedIcon: Icons.auto_awesome_outlined,
              glowColor: AppTheme.accentColor,
            ),
          ],
          barHeight: 60,
          iconSize: 24,
          selectedIconColor: AppTheme.accentColor,
          unselectedIconColor: AppTheme.textTertiary,
          glassSettings: const LiquidGlassSettings(
            thickness:           26,
            blur:                6,
            refractiveIndex:     1.55,
            saturation:          0.7,
            lightIntensity:      0.55,
            chromaticAberration: 0.05,
            ambientStrength:     0.9,
            lightAngle:          0.785,
            glassColor:          Color(0x3DFFFFFF),
          ),
        ),
      ),
    );
  }
}
