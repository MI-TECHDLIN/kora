import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/auth_provider.dart';

/// Tells the driver when their `drivers` row couldn't be confirmed on the
/// backend, so a half-set-up account never passes for a finished one, and
/// lets them retry without leaving whatever screen they're on. Persistent —
/// not a one-shot SnackBar — because deliveries stay unavailable until the
/// row exists, and a notice the driver can miss mid-sign-up leaves them
/// stuck with no visible way to recover.
/// Sits above the router (the notice outlives the sign-up screen, which the
/// auth gate replaces as soon as the session lands) as an overlay, so it
/// never squeezes the screen underneath it.
class DriverProfileNotice extends ConsumerWidget {
  const DriverProfileNotice({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverProfileProvider);
    return Stack(
      children: [
        child,
        if (state.needsAttention)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(KoraSpacing.md),
                child: _RetryBanner(
                  message: state.message!,
                  syncing: state.status == DriverProfileStatus.syncing,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RetryBanner extends ConsumerWidget {
  const _RetryBanner({required this.message, required this.syncing});

  final String message;
  final bool syncing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      child: GlassCard(
        frosted: false,
        shadow: true,
        borderRadius: KoraRadius.control,
        fill: KoraColors.danger.withValues(alpha: 0.10),
        border: Border.all(
          color: KoraColors.danger.withValues(alpha: 0.35),
          width: KoraGlass.borderWidth,
        ),
        padding: const EdgeInsets.all(KoraSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              TablerIcons.alertCircle,
              size: KoraSize.iconMd,
              color: KoraColors.danger,
            ),
            const SizedBox(width: KoraSpacing.sm),
            Expanded(child: Text(message, style: KoraText.body)),
            const SizedBox(width: KoraSpacing.sm),
            TextButton(
              key: const Key('driver-profile-retry'),
              onPressed: syncing
                  ? null
                  : () => ref.read(driverProfileProvider.notifier).retry(),
              child: Text(syncing ? 'Retrying…' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
