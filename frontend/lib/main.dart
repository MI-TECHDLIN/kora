import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/root_stack.dart';
import 'core/theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: VoiceOpsApp()));
}

class VoiceOpsApp extends StatelessWidget {
  const VoiceOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceOps',
      debugShowCheckedModeBanner: false,
      theme: buildVoiceOpsTheme(),
      home: const RootStack(),
    );
  }
}
