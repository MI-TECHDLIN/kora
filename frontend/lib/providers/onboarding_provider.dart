import 'package:flutter_riverpod/flutter_riverpod.dart';

/// TODO(Ez): back this with SharedPreferences/Supabase so it only shows once.
final onboardingProvider = StateNotifierProvider<OnboardingNotifier, bool>((
  ref,
) {
  return OnboardingNotifier();
});

class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier() : super(true);
  void complete() => state = false;
  void reset() => state = true;
}
