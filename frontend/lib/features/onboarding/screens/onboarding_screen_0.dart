import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';

/// Onboarding screen 0, the splash (PRD v4.0 §4.7, SDD v2.0 §4.0): giant
/// editorial type with inline holographic pills and a white CTA. The
/// iridescent streaks behind it come from the flow's backdrop.
class OnboardingSplash extends StatelessWidget {
  const OnboardingSplash({super.key, required this.onGetStarted});

  static const headline = 'Meet your co-rider for every delivery route';

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VoiceOpsSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: VoiceOpsSpacing.lg),
          Text(
            'VOICEOPS',
            textAlign: TextAlign.center,
            style: VoiceOpsText.caption.copyWith(
              color: VoiceOpsColors.textPrimary,
            ),
          ),
          Expanded(
            // Scales the type down rather than overflowing on short phones
            // or large accessibility text sizes.
            child: LayoutBuilder(
              builder: (context, constraints) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: const _EditorialHeadline(),
                ),
              ),
            ),
          ),
          const SizedBox(height: VoiceOpsSpacing.xl),
          PrimaryButton(
            label: 'Get started',
            tone: PrimaryButtonTone.white,
            expand: true,
            onPressed: onGetStarted,
          ),
          const SizedBox(height: VoiceOpsSpacing.sm),
        ],
      ),
    );
  }
}

/// "Meet your co-rider for every delivery route", set editorially: the
/// co-rider word sits on a glass highlight, followed by a pill holding the
/// co-rider itself, and a holographic pill leads into "delivery route".
class _EditorialHeadline extends StatelessWidget {
  const _EditorialHeadline();

  @override
  Widget build(BuildContext context) {
    final type = VoiceOpsText.editorial;
    final pillHeight = type.fontSize! * 0.9;

    WidgetSpan inline(Widget child) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VoiceOpsSpacing.xs),
        child: child,
      ),
    );

    return Semantics(
      container: true,
      label: OnboardingSplash.headline,
      header: true,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: type,
          children: [
            const TextSpan(text: 'Meet your '),
            inline(
              // Hugs the word: no fixed height or alignment, both of which
              // would clip the type or stretch the highlight full width.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: VoiceOpsColors.textPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VoiceOpsSpacing.md,
                  ),
                  child: Text(
                    'co-rider',
                    style: VoiceOpsText.weight(
                      type,
                      FontWeight.w700,
                    ).copyWith(height: 1),
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' '),
            inline(
              _Pill(
                height: pillHeight,
                color: VoiceOpsColors.elevated,
                child: const MascotDisplay(
                  state: AgentState.idle,
                  size: VoiceOpsSize.orbBubble,
                ),
              ),
            ),
            const TextSpan(text: ' for every '),
            inline(
              _Pill(
                height: pillHeight,
                gradient: VoiceOpsMood.holographic,
                child: const Icon(
                  TablerIcons.truckDelivery,
                  size: VoiceOpsSize.iconXl,
                  color: VoiceOpsMood.ink,
                ),
              ),
            ),
            const TextSpan(text: ' delivery route'),
          ],
        ),
      ),
    );
  }
}

/// A capsule twice as wide as it is tall, set inline with the type.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.height,
    required this.child,
    this.color,
    this.gradient,
  });

  final double height;
  final Widget child;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: height * 2,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
        border: Border.all(
          color: VoiceOpsGlass.border,
          width: VoiceOpsGlass.borderWidth,
        ),
      ),
      // OverflowBox lets the orb's halo bleed to the capsule edge instead of
      // shrinking the orb to fit.
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: child,
      ),
    );
  }
}
