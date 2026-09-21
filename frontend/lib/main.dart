import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/root_stack.dart';
import 'app/router.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/tokens.dart';
import 'features/auth/widgets/driver_profile_notice.dart';
import 'features/map/widgets/map_warmup.dart';
import 'providers/location_ping_provider.dart';
import 'providers/onboarding_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!SupabaseConfig.isConfigured) {
    debugPrint('SUPABASE_URL / SUPABASE_ANON_KEY not set: auth is disabled.');
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    // The anon key is Supabase's publishable key; never the service role.
    publishableKey: SupabaseConfig.anonKey,
  );
  final onboarded = await loadOnboardingCompleted(
    const SharedPreferencesOnboardingStore(),
  );
  runApp(
    ProviderScope(
      overrides: [
        onboardingCompletedAtLaunchProvider.overrideWithValue(onboarded),
      ],
      child: const KoraApp(),
    ),
  );
}

class KoraApp extends ConsumerWidget {
  const KoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Kora',
      debugShowCheckedModeBanner: false,
      theme: buildVoiceOpsTheme(), // dark-mode-first: the only theme
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => RootStack(
        child: MapWarmup(
          child: LocationPingLoop(child: DriverProfileNotice(child: child!)),
        ),
      ),
    );
  }
}
