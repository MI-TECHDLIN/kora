import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/onboarding_provider.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/onboarding_controls.dart';
import 'onboarding_screen_0.dart';
import 'onboarding_screen_1.dart';
import 'onboarding_screen_2.dart';

/// Placeholder until a driver profile source exists.
/// TODO(Ez): onboarding now runs before sign-up, so no Supabase profile
/// exists yet here; decide what the Power greeting shows instead.
const _placeholderDriverName = 'Mary';

/// The 3-screen onboarding flow — splash, hook, power (PRD v4.0 §4.7).
/// Swipeable with progress dots and no skip button. The splash CTA and the
/// Next button advance; swiping or system back steps back. Next on Power,
/// the last screen, flips [onboardingProvider] and the router redirect hands
/// the driver to the welcome screen's "Get started", or straight into the
/// main app when already signed in.
///
/// The co-rider here takes the holographic material from the onboarding
/// route's OrbMaterialScope.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  static const pageCount = 3;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _pages = PageController();
  int _index = 0;

  // Local to the flow so it survives the Power page being swiped offscreen.
  bool _micAllowed = false;

  /// Fractional page, tracking a swipe frame by frame.
  double get _page => _pages.hasClients && _pages.position.hasContentDimensions
      ? _pages.page ?? 0
      : _index.toDouble();

  void _next() => _pages.nextPage(
    duration: VoiceOpsMotion.slow,
    curve: VoiceOpsMotion.emphasized,
  );

  void _complete() => ref.read(onboardingProvider.notifier).complete();

  void _back() => _pages.previousPage(
    duration: VoiceOpsMotion.slow,
    curve: VoiceOpsMotion.emphasized,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hook and Power advance with the Next button; the splash carries its
    // own CTA. Power is the last screen, so its Next finishes onboarding.
    final VoidCallback? onNext = _index == 0
        ? null
        : _index < OnboardingFlow.pageCount - 1
        ? _next
        : _complete;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _pages,
            builder: (context, _) => OnboardingBackdrop(page: _page),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      OnboardingSplash(onGetStarted: _next),
                      const OnboardingHook(),
                      OnboardingPower(
                        driverName: _placeholderDriverName,
                        micAllowed: _micAllowed,
                        onAllowMic: () => setState(() => _micAllowed = true),
                      ),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: _pages,
                  builder: (context, _) {
                    final page = _page;
                    return OnboardingControls(
                      page: page,
                      count: OnboardingFlow.pageCount,
                      lavender: lavenderAmount(page),
                      // Fades in from the splash.
                      nextVisibility: page.clamp(0.0, 1.0),
                      onNext: onNext,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
