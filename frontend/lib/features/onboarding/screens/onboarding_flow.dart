import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/voice_recorder.dart';
import '../../../core/theme/tokens.dart';
import '../../../providers/location_provider.dart';
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
/// Power is also where the app asks for the mic and location. The flow
/// holds the real OS answers: it checks them silently on open, so anything
/// granted before shows as allowed, and asks only when the driver taps.
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

  // Local to the flow so they survive the Power page being swiped offscreen.
  bool _micAllowed = false;
  bool _locationAllowed = false;

  // One OS prompt at a time: a second tap mid-prompt is ignored.
  bool _asking = false;

  /// Fractional page, tracking a swipe frame by frame.
  double get _page => _pages.hasClients && _pages.position.hasContentDimensions
      ? _pages.page ?? 0
      : _index.toDouble();

  void _next() => _pages.nextPage(
    duration: KoraMotion.slow,
    curve: KoraMotion.emphasized,
  );

  void _complete() => ref.read(onboardingProvider.notifier).complete();

  void _back() => _pages.previousPage(
    duration: KoraMotion.slow,
    curve: KoraMotion.emphasized,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_checkPermissions());
  }

  Future<void> _checkPermissions() async {
    final mic = await _answer(ref.read(voiceRecorderProvider).hasPermission);
    final location = await _answer(
      ref.read(locationSourceProvider).hasPermission,
    );
    if (!mounted) return;
    // Never undo a grant that landed while the check was in flight.
    setState(() {
      _micAllowed |= mic;
      _locationAllowed |= location;
    });
  }

  Future<void> _allowMic() async {
    final allowed = await _ask(
      ref.read(voiceRecorderProvider).ensurePermission,
    );
    if (allowed != null && mounted) setState(() => _micAllowed = allowed);
  }

  Future<void> _allowLocation() async {
    final allowed = await _ask(
      ref.read(locationSourceProvider).requestPermission,
    );
    if (allowed == null || !mounted) return;
    setState(() => _locationAllowed = allowed);
    // The app-wide position stream started at launch without permission and
    // stopped there; start it again now that it can run.
    if (allowed) ref.invalidate(locationProvider);
  }

  /// Shows [request]'s OS prompt, or null while another is already up.
  Future<bool?> _ask(Future<bool> Function() request) async {
    if (_asking) return null;
    _asking = true;
    try {
      return await _answer(request);
    } finally {
      _asking = false;
    }
  }

  /// A permission plugin that fails counts as not allowed.
  static Future<bool> _answer(Future<bool> Function() permission) async {
    try {
      return await permission();
    } catch (_) {
      return false;
    }
  }

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
                        onAllowMic: _allowMic,
                        locationAllowed: _locationAllowed,
                        onAllowLocation: _allowLocation,
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
