import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/driver_vehicle_row.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/map_style_provider.dart';
import '../../../providers/notification_preferences_provider.dart';
import '../../../providers/vehicle_mode_provider.dart';
import '../widgets/co_rider_voice_picker.dart';

/// The driver's profile and vehicle; "show my vehicle" opens this tab
/// (`screen_navigate: settings`). Full settings sections land in
/// Checkpoint 3.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleMode = ref.watch(vehicleModeProvider);
    final mapStyle = ref.watch(mapStyleProvider);
    final notificationPreferences = ref.watch(notificationPreferencesProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KoraSpacing.gutter,
          KoraSize.orbBubble + KoraSpacing.xl,
          KoraSpacing.gutter,
          KoraSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: KoraText.headline),
            const SizedBox(height: KoraSpacing.lg),
            Text('YOUR VEHICLE', style: KoraText.caption),
            const SizedBox(height: KoraSpacing.sm),
            const GlassCard(
              key: Key('vehicle-card'),
              padding: EdgeInsets.all(KoraSpacing.lg),
              child: DriverVehicleRow(),
            ),
            const SizedBox(height: KoraSpacing.md),
            GlassCard(
              key: const Key('vehicle-mode-selector'),
              padding: const EdgeInsets.all(KoraSpacing.md),
              child: Wrap(
                spacing: KoraSpacing.sm,
                runSpacing: KoraSpacing.sm,
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
            const SizedBox(height: KoraSpacing.lg),
            Text('MAP STYLE', style: KoraText.caption),
            const SizedBox(height: KoraSpacing.sm),
            GlassCard(
              key: const Key('map-style-selector'),
              padding: const EdgeInsets.all(KoraSpacing.md),
              child: Wrap(
                spacing: KoraSpacing.sm,
                runSpacing: KoraSpacing.sm,
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
            const SizedBox(height: KoraSpacing.lg),
            Text('NOTIFICATIONS', style: KoraText.caption),
            const SizedBox(height: KoraSpacing.sm),
            GlassCard(
              key: const Key('notification-preferences'),
              padding: const EdgeInsets.symmetric(
                horizontal: KoraSpacing.lg,
                vertical: KoraSpacing.sm,
              ),
              child: Column(
                children: [
                  _NotificationToggle(
                    key: const Key('proactive-alerts-toggle'),
                    title: 'Proactive alerts',
                    description: 'Traffic, reroutes, and delivery check-ins',
                    enabled: notificationPreferences.proactiveAlertsEnabled,
                    onChanged: (enabled) => ref
                        .read(notificationPreferencesProvider.notifier)
                        .setProactiveAlerts(enabled: enabled),
                  ),
                  const Divider(height: KoraSpacing.sm),
                  _NotificationToggle(
                    key: const Key('shift-summary-ready-toggle'),
                    title: 'Shift summary ready',
                    description: 'Open your report when it is ready',
                    enabled: notificationPreferences.shiftSummaryReadyEnabled,
                    onChanged: (enabled) => ref
                        .read(notificationPreferencesProvider.notifier)
                        .setShiftSummaryReady(enabled: enabled),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KoraSpacing.lg),
            Text('CO-RIDER VOICE', style: KoraText.caption),
            const SizedBox(height: KoraSpacing.sm),
            GlassCard(
              key: const Key('co-rider-voice-selector'),
              padding: const EdgeInsets.all(KoraSpacing.md),
              child: const CoRiderVoicePicker(),
            ),
            const SizedBox(height: KoraSpacing.lg),
            Text('MAP SOURCES', style: KoraText.caption),
            const SizedBox(height: KoraSpacing.sm),
            GlassCard(
              key: const Key('map-source-credit'),
              padding: const EdgeInsets.all(KoraSpacing.lg),
              child: Text(
                'Map tiles by OpenFreeMap · Map data © OpenStreetMap contributors',
                style: KoraText.bodyMuted,
              ),
            ),
            const SizedBox(height: KoraSpacing.lg),
            Text(
              'More settings are on the way.',
              style: KoraText.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({
    super.key,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KoraSize.touchTarget),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KoraText.label),
                const SizedBox(height: KoraSpacing.xs),
                Text(description, style: KoraText.bodyMuted),
              ],
            ),
          ),
          const SizedBox(width: KoraSpacing.md),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// One pill in a single-choice row (vehicle mode, map style, voice).
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
        borderRadius: BorderRadius.circular(KoraRadius.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: KoraMotion.fast,
          constraints: const BoxConstraints(
            minHeight: KoraSize.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: KoraSpacing.md,
            vertical: KoraSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? KoraColors.primaryTint
                : KoraColors.elevated,
            borderRadius: BorderRadius.circular(KoraRadius.pill),
            border: Border.all(
              color: selected
                  ? KoraColors.primaryLight
                  : KoraColors.divider,
              width: KoraGlass.borderWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: KoraSize.iconMd,
                color: selected
                    ? KoraColors.primaryLight
                    : KoraColors.textMuted,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Text(label, style: KoraText.label),
            ],
          ),
        ),
      ),
    );
  }
}
