import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/wake_word_provider.dart';

/// Keeps wake-word microphone ownership aligned with the app lifecycle.
class WakeWordLifecycle extends ConsumerStatefulWidget {
  const WakeWordLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WakeWordLifecycle> createState() => _WakeWordLifecycleState();
}

class _WakeWordLifecycleState extends ConsumerState<WakeWordLifecycle>
    with WidgetsBindingObserver {
  late final WakeWordController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(wakeWordControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setForeground(foreground: state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _controller.setForeground(foreground: false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(wakeWordControllerProvider);
    return widget.child;
  }
}
