import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';

/// LeMUR-powered summary lands in Checkpoint 3.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'Summary screen — Checkpoint 3',
      style: VoiceOpsText.greetingLarge,
    ),
  );
}
