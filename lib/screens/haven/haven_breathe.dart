/// 呼吸放松 —— 网页 Breathe 的 1:1 还原
///
/// 4-4-6 节律：吸气 4s（放大到 1.3）、屏息 4s（保持）、呼气 6s（缩回 1.0）。
/// 网页用 CSS 的 transition: transform 4s ease-in-out，
/// 这里用 AnimationController 配 Curves.easeInOut —— 和 CSS 是同一条曲线。
library;

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/haven.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/haven_widgets.dart';

class HavenBreatheView extends StatefulWidget {
  const HavenBreatheView({super.key});

  @override
  State<HavenBreatheView> createState() => _HavenBreatheViewState();
}

class _Phase {
  const _Phase(this.label, this.seconds, this.from, this.to);

  final String label;
  final int seconds;
  final double from;
  final double to;
}

const List<_Phase> _kPhases = <_Phase>[
  _Phase('吸气', 4, 1.0, 1.3),
  _Phase('屏息', 4, 1.3, 1.3),
  _Phase('呼气', 6, 1.3, 1.0),
];

class _HavenBreatheViewState extends State<HavenBreatheView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));

  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  Timer? _phaseTimer;
  bool _breathing = false;
  int _phaseIndex = 0;
  int _cycles = 0;

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_breathing) {
      _stop();
    } else {
      _start();
    }
  }

  void _start() {
    setState(() {
      _breathing = true;
      _cycles = 0;
    });
    _runPhase(0, 0);
  }

  void _stop() {
    _phaseTimer?.cancel();
    _ctrl.stop();
    _ctrl.value = 0;
    setState(() {
      _breathing = false;
      _phaseIndex = 0;
    });
  }

  void _runPhase(int index, int cycle) {
    if (!_breathing) return;
    final i = index % _kPhases.length;
    final phase = _kPhases[i];

    setState(() {
      _phaseIndex = i;
      _cycles = cycle;
    });

    _ctrl
      ..duration = Duration(seconds: phase.seconds)
      ..forward(from: 0);

    _phaseTimer?.cancel();
    _phaseTimer = Timer(Duration(seconds: phase.seconds), () {
      if (!mounted || !_breathing) return;
      final nextCycle = i == _kPhases.length - 1 ? cycle + 1 : cycle;
      _runPhase(index + 1, nextCycle);
    });
  }

  double get _scale {
    if (!_breathing) return 1.0;
    final p = _kPhases[_phaseIndex];
    return lerpDouble(p.from, p.to, _curve.value) ?? 1.0;
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
            title: 'Breathe',
            note: '4-4-6 节律，抚平情绪的涟漪',
          ),
        ),
        FadeUpIn(
          delay: const Duration(milliseconds: 80),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 320,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scale,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 180,
                        height: 180,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: HavenColors.rose),
                          gradient: RadialGradient(
                            colors: <Color>[
                              HavenColors.rose.withValues(alpha: 0.16),
                              HavenColors.rose.withValues(alpha: 0.02),
                            ],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: HavenColors.rose.withValues(alpha: 0.16),
                              blurRadius: 46,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          _breathing ? _kPhases[_phaseIndex].label : 'READY',
                          style: TextStyle(
                            fontFamily: HavenColors.serif,
                            fontSize: 14,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w300,
                            color: HavenColors.rose,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  '找一个舒服的姿势。吸气时小腹慢慢收紧，呼气时松开 —— 让身体自己决定节奏。',
                  textAlign: TextAlign.center,
                  style: HavenColors.caption,
                ),
                const SizedBox(height: 20),
                _buildPhaseRow(),
                const SizedBox(height: 18),
                HavenButton(
                  label: _breathing ? '停下' : '开始',
                  type: HavenButtonType.ghost,
                  height: 44,
                  onPressed: _toggle,
                ),
                if (_breathing && _cycles > 0) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    '已经完成 ' + _cycles.toString() + ' 轮',
                    style: HavenColors.small,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const HavenTip(
          title: 'HOW TO',
          body: '用鼻子吸气 4 秒，轻轻屏住 4 秒，再用嘴缓缓呼气 6 秒。'
              '把注意力放到小腹：收紧、停住、松开。三轮之后，身体会自己热起来。',
        ),
      ],
    );
  }

  Widget _buildPhaseRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < _kPhases.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 18),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: _breathing && _phaseIndex == i ? 22 : 8,
                height: 2,
                decoration: BoxDecoration(
                  color: _breathing && _phaseIndex == i
                      ? HavenColors.rose
                      : HavenColors.inkStrong.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _kPhases[i].label +
                    ' ' +
                    _kPhases[i].seconds.toString() +
                    's',
                style: HavenColors.small,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
