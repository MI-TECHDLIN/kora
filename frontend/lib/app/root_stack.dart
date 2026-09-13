import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/gradient_orb_bg.dart';
import '../mascot/mascot_overlay.dart';
import '../overlays/task_progress_card.dart';
import '../overlays/voice_overlay.dart';

/// Wraps the router (passed in as [child]) in a Stack so global overlays sit
/// above every route at once — they are overlays, not routes. SDD v2.0 §2.1.
class RootStack extends StatelessWidget {
  const RootStack({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: VoiceOpsColors.canvas,
      ),
      child: GradientOrbBackground(
        // Gives the overlays (which sit outside any route) Material text
        // defaults instead of the debug "missing Material" style.
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              child,
              const MascotOverlay(),
              const TaskProgressCard(),
              const VoiceOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}
