import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/glass_card.dart';
import '../providers/call_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/order_offer_provider.dart';
import '../providers/proactive_alert_provider.dart';
import '../providers/voice_session_provider.dart';
import 'order_offer_card.dart';
import 'proactive_alert_card.dart';

/// Voice-session layer above every main tab: the degraded-state banner when
/// voice drops or errors (frontend rules: never fail silently), the call
/// card while the co-rider has a customer on the line, a proactive risk
/// alert, and a new-order offer. They stack, so a failed offer answer shows
/// its banner over the still-open offer.
class VoiceOverlay extends ConsumerWidget {
  const VoiceOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeTabProvider) == null) return const SizedBox.shrink();
    final session = ref.watch(voiceSessionProvider);
    final call = ref.watch(activeCallProvider);
    final offer = ref.watch(orderOfferProvider);
    final issue = session.issue;
    final hasOffer = offer.offer != null || offer.notice != null;
    final hasAlert = ref.watch(proactiveAlertProvider) != null;
    if (issue == null && call == null && !hasOffer && !hasAlert) {
      return const SizedBox.shrink();
    }

    // Below the top row (co-rider bubble, map controls). Top, not bottom,
    // keeps the offer clear of push-to-talk, so the driver can still
    // answer it by voice.
    return Positioned(
      top:
          MediaQuery.paddingOf(context).top +
          KoraSpacing.md +
          KoraSize.orbBubble +
          KoraSpacing.sm,
      left: KoraSpacing.gutter,
      right: KoraSpacing.gutter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (issue != null)
            _Banner(
              key: const Key('voice-issue'),
              icon: switch (session.connection) {
                VoiceConnection.reconnecting ||
                VoiceConnection.failed => TablerIcons.wifiOff,
                _ => TablerIcons.alertTriangle,
              },
              message: issue,
              actionLabel: 'Dismiss',
              onAction: ref.read(voiceSessionProvider.notifier).dismissIssue,
            ),
          if (issue != null && call != null)
            const SizedBox(height: KoraSpacing.sm),
          if (call != null)
            _CallCard(
              name: call.customerName ?? 'your customer',
              sequence: call.sequence,
              onEnd: () {
                final sent = ref
                    .read(voiceSessionProvider.notifier)
                    .endCall(call.callId);
                if (!sent) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Voice is offline, so the call can't be ended from "
                        'here yet.',
                      ),
                    ),
                  );
                }
              },
            ),
          if ((issue != null || call != null) && hasAlert)
            const SizedBox(height: KoraSpacing.sm),
          if (hasAlert) const ProactiveAlertCard(),
          if ((issue != null || call != null || hasAlert) && hasOffer)
            const SizedBox(height: KoraSpacing.sm),
          if (hasOffer) const OrderOfferPanel(),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      fill: KoraColors.raised.withValues(alpha: 0.92),
      border: Border.all(
        color: KoraColors.amber.withValues(alpha: 0.5),
        width: KoraGlass.borderWidth,
      ),
      padding: const EdgeInsets.only(left: KoraSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: KoraSize.iconMd, color: KoraColors.amber),
          const SizedBox(width: KoraSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KoraSpacing.md),
              child: Text(message, style: KoraText.label),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(
                KoraSize.touchTarget,
                KoraSize.touchTarget,
              ),
            ),
            child: Text(
              actionLabel,
              style: KoraText.label.copyWith(
                color: KoraColors.primaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({
    required this.name,
    required this.sequence,
    required this.onEnd,
  });

  final String name;
  final int? sequence;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const Key('call-card'),
      fill: KoraColors.raised.withValues(alpha: 0.92),
      padding: const EdgeInsets.all(KoraSpacing.md),
      child: Row(
        children: [
          Container(
            width: KoraSize.avatar,
            height: KoraSize.avatar,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KoraColors.primaryTint,
            ),
            child: const Icon(
              TablerIcons.phoneCall,
              size: KoraSize.iconLg,
              color: KoraColors.primaryLight,
            ),
          ),
          const SizedBox(width: KoraSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sequence == null ? 'ON A CALL' : 'ON A CALL · STOP $sequence',
                  style: KoraText.caption,
                ),
                Text(
                  'Calling $name',
                  style: KoraText.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'End call',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEnd,
              child: Container(
                width: KoraSize.touchTarget,
                height: KoraSize.touchTarget,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoraColors.danger,
                ),
                child: const Icon(
                  TablerIcons.phoneOff,
                  size: KoraSize.iconMd,
                  color: KoraColors.onAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
