import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/root_stack.dart';
import 'app/router.dart';
import 'core/theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: VoiceOpsApp()));
}

class VoiceOpsApp extends ConsumerWidget {
  const VoiceOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'VoiceOps',
      debugShowCheckedModeBanner: false,
      theme: buildVoiceOpsTheme(), // dark-mode-first: the only theme
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => RootStack(child: child!),
    );
  }
}
