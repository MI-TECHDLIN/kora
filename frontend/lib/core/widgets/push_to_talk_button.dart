import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../providers/push_to_talk_provider.dart';
import '../theme/tokens.dart';

/// The central interaction of the app: a large circular push-to-talk
/// button. State comes from [pushToTalkProvider], never local widget state,
/// and each of the four states has its own fill, icon and motion so the
/// driver can read it at a glance. Only `recording` is lime ([VoiceOpsColors.live]).
///
/// Shell only — no audio capture. [onPressed] defaults to advancing the
/// placeholder provider so the states can be reviewed on device.
class PushToTalkButton extends ConsumerStatefulWidget {
  const PushToTalkButton({
    super.key,
    this.onPressed,
    this.size = VoiceOpsSize.pushToTalk,
  }) : assert(
         size >= VoiceOpsSize.pushToTalkMin,
         'push-to-talk must stay at least 80×80',
       );

  final VoidCallback? onPressed;
  final double size;

  @override
  ConsumerState<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends ConsumerState<PushToTalkButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(pushToTalkProvider, (_, next) => _syncLoop(next));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncLoop(ref.read(pushToTalkProvider));
  }

  // Animate only while there is something to show; idle costs no frames.
  void _syncLoop(PushToTalkState state) {
    if (state == PushToTalkState.idle || _reduceMotion) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pushToTalkProvider);
    final look = _PttLook.of(state);

    return Semantics(
      button: true,
      label: look.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            widget.onPressed ??
            () => ref.read(pushToTalkProvider.notifier).advance(),
        child: CustomPaint(
          painter: _PttHaloPainter(state: state, progress: _loop),
          child: AnimatedContainer(
            duration: VoiceOpsMotion.base,
            curve: VoiceOpsMotion.standard,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: look.fill,
              gradient: look.gradient,
              border: Border.all(
                color: look.border,
                width: VoiceOpsGlass.borderWidth * 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: look.glow,
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: VoiceOpsMotion.fast,
              child: Icon(
                look.icon,
                key: ValueKey(state),
                size: VoiceOpsSize.iconXl,
                color: look.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Static visual treatment per state.
class _PttLook {
  const _PttLook({
    required this.icon,
    required this.ink,
    required this.border,
    required this.glow,
    required this.semanticLabel,
    this.fill,
    this.gradient,
  });

  final IconData icon;
  final Color ink;
  final Color? fill;
  final Gradient? gradient;
  final Color border;
  final Color glow;
  final String semanticLabel;

  static _PttLook of(PushToTalkState state) => switch (state) {
    // Resting brand violet.
    PushToTalkState.idle => const _PttLook(
      icon: TablerIcons.microphone,
      ink: VoiceOpsColors.onPrimary,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [VoiceOpsColors.primary, VoiceOpsColors.primaryDark],
      ),
      border: VoiceOpsGlass.border,
      glow: VoiceOpsColors.primaryGlow,
      semanticLabel: 'Push to talk',
    ),
    // Mic hot — the one place lime is allowed.
    PushToTalkState.recording => const _PttLook(
      icon: TablerIcons.microphoneFilled,
      ink: VoiceOpsColors.onLive,
      fill: VoiceOpsColors.live,
      border: VoiceOpsColors.live,
      glow: VoiceOpsColors.liveGlow,
      semanticLabel: 'Recording. Tap to stop',
    ),
    // Dark, outlined, with a sweeping arc: working, mic off.
    PushToTalkState.processing => const _PttLook(
      icon: TablerIcons.loader2,
      ink: VoiceOpsColors.primaryLight,
      fill: VoiceOpsColors.elevated,
      border: VoiceOpsColors.primaryTint,
      glow: VoiceOpsColors.primaryTint,
      semanticLabel: 'Working on it',
    ),
    // Co-rider talking: light violet with a breathing ring.
    PushToTalkState.speaking => const _PttLook(
      icon: TablerIcons.waveSine,
      ink: VoiceOpsColors.onAccent,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [VoiceOpsColors.primaryLight, VoiceOpsColors.primary],
      ),
      border: VoiceOpsColors.primaryLight,
      glow: VoiceOpsColors.primaryGlow,
      semanticLabel: 'Co-rider speaking. Tap to interrupt',
    ),
  };
}

/// Animated layer around the button: lime rings while recording, a
/// sweeping arc while processing, a breathing ring while speaking.
class _PttHaloPainter extends CustomPainter {
  _PttHaloPainter({required this.state, required this.progress})
    : super(repaint: progress);

  final PushToTalkState state;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final t = progress.value;

    switch (state) {
      case PushToTalkState.idle:
        return;
      case PushToTalkState.recording:
        for (var i = 0; i < 2; i++) {
          final p = (t + i / 2) % 1;
          canvas.drawCircle(
            center,
            r * (1 + 0.45 * p),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = VoiceOpsColors.live.withValues(alpha: 0.55 * (1 - p)),
          );
        }
      case PushToTalkState.processing:
        final rect = Rect.fromCircle(center: center, radius: r + 6);
        canvas.drawArc(
          rect,
          t * 2 * math.pi,
          math.pi * 0.6,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = VoiceOpsColors.primaryLight,
        );
      case PushToTalkState.speaking:
        final breath = (math.sin(t * 2 * math.pi) + 1) / 2;
        canvas.drawCircle(
          center,
          r * (1.08 + 0.1 * breath),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = VoiceOpsColors.primaryLight.withValues(
              alpha: 0.25 + 0.35 * breath,
            ),
        );
    }
  }

  @override
  bool shouldRepaint(_PttHaloPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.progress != progress;
}
