import 'package:flutter/foundation.dart';

/// 全局底部液态玻璃栏的显隐控制器。
///
/// 任何页面只要：
///   context.read(`NavBarVisibility`).hide();
///   context.read(`NavBarVisibility`).show();
/// 就能控制底部栏的显示/隐藏，带 260ms 上下滑出动画。
final class NavBarVisibility extends ChangeNotifier {
  bool _visible = true;
  bool get visible => _visible;

  void show() {
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void set(bool v) => v ? show() : hide();
}