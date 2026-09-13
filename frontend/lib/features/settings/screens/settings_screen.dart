import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/driver_vehicle_row.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/map_style_provider.dart';
import '../../../providers/vehicle_mode_provider.dart';

/// The driver's profile and vehicle; "show my vehicle" opens this tab
/// (`screen_navigate: settings`). Full settings sections land in
/// Checkpoint 3.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleMode = ref.watch(vehicleModeProvider);
    final mapStyle = ref.watch(mapStyleProvider);
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
                    _Choice(
                      label: mode.label,
                      icon: mode.icon,
                      selected: mode == vehicleMode,
                      onTap: () =>
                          ref.read(vehicleModeProvider.notifier).select(mode),
                    ),
                ],
              ),
            ),
            const SizedBox(height: VoiceOpsSpacing.lg),
            Text('MAP STYLE', style: VoiceOpsText.caption),
            const SizedBox(height: VoiceOpsSpacing.sm),
            GlassCard(
              key: const Key('map-style-selector'),
              padding: const EdgeInsets.all(VoiceOpsSpacing.md),
              child: Wrap(
                spacing: VoiceOpsSpacing.sm,
                runSpacing: VoiceOpsSpacing.sm,
                children: [
                  for (final style in MapStyle.values)
                    _Choice(
                      label: style.label,
                      icon: style.icon,
                      selected: style == mapStyle,
                      onTap: () =>
                          ref.read(mapStyleProvider.notifier).select(style),
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

/// One pill in a single-choice row (vehicle mode, map style).
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
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
                icon,
                size: VoiceOpsSize.iconMd,
                color: selected
                    ? VoiceOpsColors.primaryLight
                    : VoiceOpsColors.textMuted,
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              Text(label, style: VoiceOpsText.label),
            ],
          ),
        ),
      ),
    );
  }
}
