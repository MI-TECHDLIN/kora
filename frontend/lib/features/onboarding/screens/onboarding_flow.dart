import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/onboarding_provider.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/onboarding_controls.dart';
import 'onboarding_screen_0.dart';
import 'onboarding_screen_1.dart';
import 'onboarding_screen_2.dart';
import 'onboarding_screen_3.dart';

/// Placeholder until a driver profile source exists.
/// TODO(Ez): read the driver's name from the Supabase profile once auth lands.
const _placeholderDriverName = 'Mary';

/// The 4-screen onboarding flow — splash, hook, power, trust (PRD v4.0
/// §4.7). Swipeable with progress dots and no skip button. The splash CTA
/// and the Next button advance; swiping or system back steps back.
/// Completing it flips [onboardingProvider] and the router redirect takes
/// the driver into the main app.
///
/// The co-rider here takes the holographic material from the onboarding
/// route's OrbMaterialScope.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  static const pageCount = 4;

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
    // Hook and Power advance with the Next button; the splash and Trust
    // carry their own CTA.
    final showsNext = _index == 1 || _index == 2;

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
                      OnboardingTrust(
                        onStartDriving: () =>
                            ref.read(onboardingProvider.notifier).complete(),
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
                      // Fades in from the splash, out toward Trust.
                      nextVisibility: page <= 1
                          ? page.clamp(0.0, 1.0)
                          : (3 - page).clamp(0.0, 1.0),
                      onNext: showsNext ? _next : null,
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
