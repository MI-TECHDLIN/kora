import 'package:flutter/widgets.dart';

import '../../../core/theme/tokens.dart';

/// One entrance timeline per form, retained through validation and auth updates.
mixin AuthEntrance<T extends StatefulWidget> on State<T>, TickerProvider {
  int get entranceItemCount;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: VoiceOpsMotion.stagger,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _entrance.value = 1;
    } else if (_entrance.isDismissed && !_entrance.isAnimating) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Fades and slides down in reading order without changing layout or input.
  Widget arrive(int order, Widget child) {
    assert(entranceItemCount > 1);
    assert(order >= 0 && order < entranceItemCount);
    // Match the overlapping intervals of the onboarding card entrance.
    final start = order * 0.4 / (entranceItemCount - 1);
    final progress = _entrance.drive(
      CurveTween(
        curve: Interval(start, start + 0.6, curve: VoiceOpsMotion.standard),
      ),
    );
    return FadeTransition(
      opacity: progress,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: progress,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -VoiceOpsSpacing.md * (1 - progress.value)),
          child: child,
        ),
      ),
    );
  }
}
