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
      padding: const EdgeInsets.symmetric(horizontal: KoraSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KoraSpacing.lg),
          Text(
            'KORA',
            textAlign: TextAlign.center,
            style: KoraText.caption.copyWith(
              color: KoraColors.textPrimary,
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
          const SizedBox(height: KoraSpacing.xl),
          PrimaryButton(
            label: 'Get started',
            tone: PrimaryButtonTone.white,
            expand: true,
            onPressed: onGetStarted,
          ),
          const SizedBox(height: KoraSpacing.sm),
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
    final type = KoraText.editorial;
    final pillHeight = type.fontSize! * 0.9;

    WidgetSpan inline(Widget child) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KoraSpacing.xs),
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
                  color: KoraColors.textPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(KoraRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoraSpacing.md,
                  ),
                  child: Text(
                    'co-rider',
                    style: KoraText.weight(
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
                color: KoraColors.elevated,
                child: const MascotDisplay(
                  state: AgentState.idle,
                  size: KoraSize.orbBubble,
                ),
              ),
            ),
            const TextSpan(text: ' for every '),
            inline(
              _Pill(
                height: pillHeight,
                gradient: KoraMood.holographic,
                child: const Icon(
                  TablerIcons.truckDelivery,
                  size: KoraSize.iconXl,
                  color: KoraMood.ink,
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
        borderRadius: BorderRadius.circular(KoraRadius.pill),
        border: Border.all(
          color: KoraGlass.border,
          width: KoraGlass.borderWidth,
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
