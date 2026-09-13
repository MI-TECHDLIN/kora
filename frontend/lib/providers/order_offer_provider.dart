import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/voice_events.dart';
import '../core/theme/tokens.dart';

class OrderOfferState {
  const OrderOfferState({this.offer, this.responding = false, this.notice});

  final OrderOfferEvent? offer;
  final bool responding;

  /// Short-lived result of the most recently closed offer.
  final String? notice;
}

final orderOfferProvider =
    StateNotifierProvider<OrderOfferNotifier, OrderOfferState>(
      (ref) => OrderOfferNotifier(),
    );

class OrderOfferNotifier extends StateNotifier<OrderOfferState> {
  OrderOfferNotifier() : super(const OrderOfferState());

  Timer? _noticeTimer;

  void show(OrderOfferEvent offer) {
    _noticeTimer?.cancel();
    state = OrderOfferState(offer: offer);
  }

  void markResponding(String orderId) {
    if (state.offer?.orderId != orderId) return;
    state = OrderOfferState(offer: state.offer, responding: true);
  }

  void responseFailed() {
    if (!state.responding) return;
    state = OrderOfferState(offer: state.offer);
  }

  void clear() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    state = const OrderOfferState();
  }

  void close(String orderId, OrderOfferOutcome outcome) {
    if (state.offer?.orderId != orderId) return;
    _noticeTimer?.cancel();
    state = OrderOfferState(notice: _noticeFor(outcome));
    _noticeTimer = Timer(VoiceOpsMotion.notice, dismissNotice);
  }

  void dismissNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    if (state.notice != null) state = const OrderOfferState();
  }

  static String _noticeFor(OrderOfferOutcome outcome) => switch (outcome) {
    OrderOfferOutcome.accepted => 'Order accepted and added to your run.',
    OrderOfferOutcome.declined => 'Order declined and passed on.',
    OrderOfferOutcome.expired => 'Offer expired and went to another driver.',
    OrderOfferOutcome.withdrawn =>
      'Offer closed because another driver took the order.',
  };

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }
}
