import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';

/// Full settings sections land in Checkpoint 3.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Text('Settings screen — Checkpoint 3', style: VoiceOpsText.headline),
  );
}
