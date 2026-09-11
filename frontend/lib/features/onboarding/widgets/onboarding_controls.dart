import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';

/// Bottom row of the onboarding flow: progress dots and a round Next
/// button (SDD v2.0 §4.1–4.3). There is deliberately no skip button.
///
/// Every input is fractional so the row tracks a swipe frame by frame.
class OnboardingControls extends StatelessWidget {
  const OnboardingControls({
    super.key,
    required this.page,
    required this.count,
    required this.lavender,
    required this.nextVisibility,
    this.onNext,
  });

  /// Current page, fractional mid-swipe.
  final double page;
  final int count;

  /// 0 on the dark moods, 1 on lavender: blends the ink from light to dark.
  final double lavender;

  /// 0 hides the Next button, 1 shows it fully.
  final double nextVisibility;

  /// Null while the Next button is hidden.
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final ink = Color.lerp(
      VoiceOpsColors.textPrimary,
      VoiceOpsMood.ink,
      lavender,
    )!;
    final step = page.round().clamp(0, count - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VoiceOpsSpacing.gutter,
        VoiceOpsSpacing.sm,
        VoiceOpsSpacing.gutter,
        VoiceOpsSpacing.lg,
      ),
      child: Row(
        children: [
          Semantics(
            container: true,
            label: 'Step ${step + 1} of $count',
            excludeSemantics: true,
            child: Row(
              children: [for (var i = 0; i < count; i++) _dot(i, ink)],
            ),
          ),
          const Spacer(),
          // While hidden the button is inert: no taps, not announced.
          IgnorePointer(
            ignoring: onNext == null,
            child: ExcludeSemantics(
              excluding: onNext == null,
              child: Opacity(
                opacity: nextVisibility,
                child: _NextButton(ink: ink, onPressed: onNext),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int i, Color ink) {
    // Steps up to the current one are filled, so the last screen reads as
    // "all filled"; the current step also stretches into a pill.
    final filled = (1 - (i - page)).clamp(0.0, 1.0);
    final current = (1 - (page - i).abs()).clamp(0.0, 1.0);
    return Container(
      width:
          VoiceOpsSize.progressDot +
          (VoiceOpsSize.progressDotActive - VoiceOpsSize.progressDot) * current,
      height: VoiceOpsSize.progressDot,
      margin: const EdgeInsets.only(right: VoiceOpsSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
        color: ink.withValues(alpha: 0.25 + 0.75 * filled),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.ink, required this.onPressed});

  final Color ink;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Inverted disc: light on the dark moods, dark on lavender.
    final fill = ink;
    final glyph = ink.computeLuminance() > 0.5
        ? VoiceOpsMood.ink
        : VoiceOpsMood.paper;

    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: 'Next',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.circle,
        color: fill,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: VoiceOpsSize.control,
            child: Icon(
              TablerIcons.arrowRight,
              size: VoiceOpsSize.iconLg,
              color: glyph,
            ),
          ),
        ),
      ),
    );
  }
}
