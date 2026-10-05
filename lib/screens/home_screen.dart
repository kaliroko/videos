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
import 'package:bilibili_glass/providers/nav_bar_visibility.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/screens/diary_screen.dart';
import 'package:bilibili_glass/screens/swipe_video_screen.dart';
import 'package:bilibili_glass/screens/chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  /// ★ 只有 0/1 两个真正的 tab
  /// 0 = 碎碎念（日记动态）；1 = 视频
  /// 2 = 聊天室入口按钮（点击 push 独立页面，不是 tab）
  int _bottomTab = 0;

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
            SwipeVideoScreen(active: _bottomTab == 1),
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
    setState(() => _bottomTab = i);
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

  // ── 底部导航 ★ 三个位置，第三个是"入口按钮"──────────────────────
  Widget _buildBottomNav() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: GlassBottomBar(
          selectedIndex: _bottomTab,
          onTabSelected: (i) {
            // ★ 点击第三个位置 → 进入独立聊天室页面（不改变 tab）
            if (i == 2) {
              _openChatRoom();
              return;
            }

            // 碎碎念 / 视频 → 正常切换
            _pageController.animateToPage(
              i,
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
            GlassBottomBarTab(
              label: '白丝宝宝',
              icon: Icons.auto_awesome,
              selectedIcon: Icons.auto_awesome_outlined,
              glowColor: AppTheme.accentColor,
            ),
            // ★ 聊天室 = 入口按钮（点击进入独立页面）
            GlassBottomBarTab(
              label: '聊天室',
              icon: Icons.chat_bubble,
              selectedIcon: Icons.chat_bubble_outline,
              glowColor: const Color(0xFF64B5EF),
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
