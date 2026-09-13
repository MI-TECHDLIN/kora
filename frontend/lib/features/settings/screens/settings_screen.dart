import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/driver_vehicle_row.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/vehicle_mode_provider.dart';

/// The driver's profile and vehicle; "show my vehicle" opens this tab
/// (`screen_navigate: settings`). Full settings sections land in
/// Checkpoint 3.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleMode = ref.watch(vehicleModeProvider);
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
            const SizedBox(height: VoiceOpsSpacing.md),
            GlassCard(
              key: const Key('vehicle-mode-selector'),
              padding: const EdgeInsets.all(VoiceOpsSpacing.md),
              child: Wrap(
                spacing: VoiceOpsSpacing.sm,
                runSpacing: VoiceOpsSpacing.sm,
                children: [
                  for (final mode in VehicleMode.values)
                    _VehicleModeChoice(
                      mode: mode,
                      selected: mode == vehicleMode,
                      onTap: () =>
                          ref.read(vehicleModeProvider.notifier).select(mode),
                    ),
                ],
              ),
            ),
            const SizedBox(height: VoiceOpsSpacing.lg),
            Text('MAP SOURCES', style: VoiceOpsText.caption),
            const SizedBox(height: VoiceOpsSpacing.sm),
            GlassCard(
              key: const Key('map-source-credit'),
              padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
              child: Text(
                'Map tiles by OpenFreeMap · Map data © OpenStreetMap contributors',
                style: VoiceOpsText.bodyMuted,
              ),
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

class _VehicleModeChoice extends StatelessWidget {
  const _VehicleModeChoice({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final VehicleMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: VoiceOpsMotion.fast,
          constraints: const BoxConstraints(
            minHeight: VoiceOpsSize.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: VoiceOpsSpacing.md,
            vertical: VoiceOpsSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? VoiceOpsColors.primaryTint
                : VoiceOpsColors.elevated,
            borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
            border: Border.all(
              color: selected
                  ? VoiceOpsColors.primaryLight
                  : VoiceOpsColors.divider,
              width: VoiceOpsGlass.borderWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode.icon,
                size: VoiceOpsSize.iconMd,
                color: selected
                    ? VoiceOpsColors.primaryLight
                    : VoiceOpsColors.textMuted,
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              Text(mode.label, style: VoiceOpsText.label),
            ],
          ),
        ),
      ),
    );
  }
}
