import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../providers/driver_details_provider.dart';
import '../api/voiceops_api.dart';
import '../theme/tokens.dart';

/// The driver and their vehicle, from `GET /v1/driver/profile`, with its
/// loading, error (retry) and empty states. On the Map tab's card and in
/// Settings, where "show my vehicle" lands (`screen_navigate: settings`).
class DriverVehicleRow extends ConsumerWidget {
  const DriverVehicleRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(driverDetailsProvider);
    return profile.when(
      skipLoadingOnRefresh: false,
      loading: () => const _VehicleLayout(
        icon: TablerIcons.steeringWheel,
        title: 'Your vehicle',
        subtitle: 'Loading your profile…',
      ),
      error: (error, _) => _VehicleLayout(
        icon: TablerIcons.steeringWheel,
        title: "Couldn't load your vehicle",
        subtitle: error is ApiException
            ? error.message
            : 'Something went wrong. Try again.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(driverDetailsProvider),
      ),
      data: (driver) {
        final vehicle = driver.vehicleType;
        return _VehicleLayout(
          icon: vehicleIcon(vehicle),
          title: driver.name ?? 'You',
          subtitle: vehicle ?? 'No vehicle on your profile yet',
        );
      },
    );
  }
}

class _VehicleLayout extends StatelessWidget {
  const _VehicleLayout({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: VoiceOpsSize.avatar,
          height: VoiceOpsSize.avatar,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: VoiceOpsColors.primaryTint,
          ),
          child: Icon(
            icon,
            size: VoiceOpsSize.iconLg,
            color: VoiceOpsColors.primaryLight,
          ),
        ),
        const SizedBox(width: VoiceOpsSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: VoiceOpsText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: VoiceOpsText.bodyMuted,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: VoiceOpsColors.primaryLight,
              minimumSize: const Size(
                VoiceOpsSize.touchTarget,
                VoiceOpsSize.touchTarget,
              ),
            ),
            child: Text(
              actionLabel!,
              style: VoiceOpsText.label.copyWith(
                color: VoiceOpsColors.primaryLight,
              ),
            ),
          ),
      ],
    );
  }
}

/// A Tabler icon for the free-text `vehicle_type`.
IconData vehicleIcon(String? vehicleType) {
  final type = vehicleType?.toLowerCase() ?? '';
  if (type.isEmpty) return TablerIcons.steeringWheel;
  if (type.contains('scooter')) return TablerIcons.scooter;
  if (type.contains('motor') || type.contains('okada')) {
    return TablerIcons.motorbike;
  }
  if (type.contains('bike') || type.contains('cycle')) return TablerIcons.bike;
  if (type.contains('van') ||
      type.contains('truck') ||
      type.contains('lorry')) {
    return TablerIcons.truckDelivery;
  }
  return TablerIcons.car;
}
