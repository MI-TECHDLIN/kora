import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// The mood behind each onboarding screen, in page order (PRD v4.0 §4.7):
/// holographic editorial splash, dark navy Hook, lavender Power, navy Trust.
const onboardingMoods = [
  VoiceOpsMood.editorial,
  VoiceOpsMood.navy,
  VoiceOpsMood.lavender,
  VoiceOpsMood.navy,
];

/// How far [page] sits on the light lavender mood, 0 (dark) to 1 (lavender).
/// Shared chrome uses it to switch between light and dark ink.
double lavenderAmount(double page) => (1 - (page - 2).abs()).clamp(0.0, 1.0);

/// Full-bleed onboarding background. [page] is fractional mid-swipe, so the
/// mood blends stop-for-stop into the next one instead of cutting.
class OnboardingBackdrop extends StatelessWidget {
  const OnboardingBackdrop({super.key, required this.page});

  final double page;

  /// Horizontal squash that turns the round sheen glows into light streaks.
  static const _streak = 0.45;

  List<Color> _moodAt(double page) {
    final last = onboardingMoods.length - 1;
    final from = page.floor().clamp(0, last);
    final to = (from + 1).clamp(0, last);
    final t = (page - from).clamp(0.0, 1.0);
    return [
      for (var i = 0; i < onboardingMoods[from].length; i++)
        Color.lerp(onboardingMoods[from][i], onboardingMoods[to][i], t)!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // The splash's iridescent streaks fade out as the navy Hook slides in.
    final sheen = (1 - page).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _moodAt(page),
        ),
      ),
      child: sheen == 0
          ? const SizedBox.expand()
          : Stack(
              fit: StackFit.expand,
              children: [
                for (final s in VoiceOpsMood.splashSheen)
                  Align(
                    alignment: s.at,
                    child: Transform.scale(
                      scaleX: _streak,
                      child: Container(
                        width: s.size,
                        height: s.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              s.color.withValues(alpha: s.alpha * sheen),
                              s.color.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
