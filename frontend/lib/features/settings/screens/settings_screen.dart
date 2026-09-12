import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/driver_vehicle_row.dart';
import '../../../core/widgets/glass_card.dart';

/// The driver's profile and vehicle; "show my vehicle" opens this tab
/// (`screen_navigate: settings`). Full settings sections land in
/// Checkpoint 3.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          VoiceOpsSpacing.gutter,
          VoiceOpsSize.orbBubble + VoiceOpsSpacing.xl,
          VoiceOpsSpacing.gutter,
          VoiceOpsSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: VoiceOpsText.headline),
            const SizedBox(height: VoiceOpsSpacing.lg),
            Text('YOUR VEHICLE', style: VoiceOpsText.caption),
            const SizedBox(height: VoiceOpsSpacing.sm),
            const GlassCard(
              key: Key('vehicle-card'),
              padding: EdgeInsets.all(VoiceOpsSpacing.lg),
              child: DriverVehicleRow(),
            ),
            const SizedBox(height: VoiceOpsSpacing.lg),
            Text(
              'More settings are on the way.',
              style: VoiceOpsText.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }
}
