import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';

/// Full Google Maps + agent-driven pin/route animation lands in Checkpoint 2.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Text('Map screen — Checkpoint 2', style: VoiceOpsText.greetingLarge),
  );
}
