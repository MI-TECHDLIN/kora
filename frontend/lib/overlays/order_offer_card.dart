import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/realtime/voice_events.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/glass_card.dart';
import '../providers/order_offer_provider.dart';
import '../providers/voice_session_provider.dart';

/// The time-boxed order offer, or a brief note on why the last one closed.
/// [VoiceOverlay] stacks it under its banner and call card, above every main
/// tab. There is no scrim, so the driver can still see the active screen and
/// hear the co-rider announce the same offer.
class OrderOfferPanel extends ConsumerWidget {
  const OrderOfferPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderOfferProvider);
    final offer = state.offer;
    if (offer != null) {
      return OrderOfferCard(
        key: ValueKey('order-offer-${offer.orderId}'),
        offer: offer,
        responding: state.responding,
        onAccept: () => ref
            .read(voiceSessionProvider.notifier)
            .respondToOrderOffer(offer.orderId, accept: true),
        onDecline: () => ref
            .read(voiceSessionProvider.notifier)
            .respondToOrderOffer(offer.orderId, accept: false),
      );
    }
    final notice = state.notice;
    if (notice == null) return const SizedBox.shrink();
    return _ClosedNotice(
      message: notice,
      onDismiss: ref.read(orderOfferProvider.notifier).dismissNotice,
    );
  }
}

class OrderOfferCard extends StatefulWidget {
  const OrderOfferCard({
    super.key,
    required this.offer,
    required this.responding,
    required this.onAccept,
    required this.onDecline,
  });

  final OrderOfferEvent offer;
  final bool responding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<OrderOfferCard> createState() => _OrderOfferCardState();
}

class _OrderOfferCardState extends State<OrderOfferCard> {
  Timer? _ticker;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(OrderOfferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.orderId != widget.offer.orderId) _startCountdown();
  }

  void _startCountdown() {
    _ticker?.cancel();
    _remaining = widget.offer.expiresInSeconds;
    _ticker = Timer.periodic(VoiceOpsMotion.countdownTick, (_) {
      if (_remaining <= 0) {
        _ticker?.cancel();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return GlassCard(
      key: const Key('order-offer-card'),
      borderRadius: VoiceOpsRadius.sheet,
      fill: VoiceOpsColors.raised.withValues(alpha: 0.96),
      border: Border.all(
        color: VoiceOpsColors.primary.withValues(alpha: 0.7),
        width: VoiceOpsGlass.borderWidth,
      ),
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: VoiceOpsSize.touchTarget,
                height: VoiceOpsSize.touchTarget,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: VoiceOpsColors.primaryTint,
                ),
                child: const Icon(
                  TablerIcons.package,
                  size: VoiceOpsSize.iconLg,
                  color: VoiceOpsColors.primaryLight,
                ),
              ),
              const SizedBox(width: VoiceOpsSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEW DELIVERY OFFER', style: VoiceOpsText.caption),
                    Text(
                      offer.area,
                      style: VoiceOpsText.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              _Countdown(seconds: _remaining),
            ],
          ),
          if (offer.distanceKm != null ||
              offer.timeWindow != null ||
              offer.packageCount != null) ...[
            const SizedBox(height: VoiceOpsSpacing.md),
            Wrap(
              spacing: VoiceOpsSpacing.sm,
              runSpacing: VoiceOpsSpacing.sm,
              children: [
                if (offer.distanceKm != null)
                  _Detail(
                    icon: TablerIcons.route,
                    text: '${_distance(offer.distanceKm!)} km away',
                  ),
                if (offer.timeWindow != null)
                  _Detail(icon: TablerIcons.clock, text: offer.timeWindow!),
                if (offer.packageCount != null)
                  _Detail(
                    icon: TablerIcons.packages,
                    text:
                        '${offer.packageCount} '
                        '${offer.packageCount == 1 ? 'package' : 'packages'}',
                  ),
              ],
            ),
          ],
          const SizedBox(height: VoiceOpsSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('decline-order'),
                  onPressed: widget.responding ? null : widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(VoiceOpsSize.control),
                    foregroundColor: VoiceOpsColors.textPrimary,
                    side: const BorderSide(
                      color: VoiceOpsColors.divider,
                      width: VoiceOpsGlass.borderWidth,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        VoiceOpsRadius.control,
                      ),
                    ),
                  ),
                  child: Text('Decline', style: VoiceOpsText.label),
                ),
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('accept-order'),
                  onPressed: widget.responding ? null : widget.onAccept,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(VoiceOpsSize.control),
                    backgroundColor: VoiceOpsColors.primary,
                    foregroundColor: VoiceOpsColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        VoiceOpsRadius.control,
                      ),
                    ),
                  ),
                  child: Text(
                    widget.responding ? 'Responding…' : 'Accept',
                    style: VoiceOpsText.label,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('offer-countdown'),
      constraints: const BoxConstraints(minHeight: VoiceOpsSize.touchTarget),
      padding: const EdgeInsets.symmetric(horizontal: VoiceOpsSpacing.md),
      decoration: BoxDecoration(
        color: VoiceOpsColors.overlay,
        borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        seconds > 0 ? '${seconds}s' : 'Closing…',
        style: VoiceOpsText.label.copyWith(color: VoiceOpsColors.primaryLight),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: VoiceOpsSize.iconSm, color: VoiceOpsColors.textMuted),
        const SizedBox(width: VoiceOpsSpacing.xs),
        Text(text, style: VoiceOpsText.bodyMuted),
      ],
    );
  }
}

class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const Key('order-offer-closed-notice'),
      fill: VoiceOpsColors.raised.withValues(alpha: 0.96),
      padding: const EdgeInsets.only(left: VoiceOpsSpacing.md),
      child: Row(
        children: [
          const Icon(
            TablerIcons.infoCircle,
            size: VoiceOpsSize.iconMd,
            color: VoiceOpsColors.primaryLight,
          ),
          const SizedBox(width: VoiceOpsSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: VoiceOpsSpacing.md),
              child: Text(message, style: VoiceOpsText.label),
            ),
          ),
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(
              minimumSize: const Size(
                VoiceOpsSize.touchTarget,
                VoiceOpsSize.touchTarget,
              ),
            ),
            child: Text(
              'Dismiss',
              style: VoiceOpsText.label.copyWith(
                color: VoiceOpsColors.primaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _distance(double value) => value.toStringAsFixed(value < 10 ? 1 : 0);
