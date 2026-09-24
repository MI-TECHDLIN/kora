import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';
import '../features/summary/data/order_queue.dart';
import 'shift_provider.dart';

/// The driver's `driver_preferences` key for their daily delivery target
/// (a whole number, stored as a string). Voice writes the same key.
const dailyDeliveryTargetKey = 'daily_delivery_target';

/// What Home and Summary read. [queue] is the latest snapshot, or
/// [OrderQueue.empty] while there is none (no shift yet, or the backend has
/// no queue endpoint): the screens then show their empty state.
class OrderQueueState {
  const OrderQueueState({
    this.queue = OrderQueue.empty,
    this.loading = false,
    this.busyDeliveryId,
    this.error,
    this.targetError,
  });

  final OrderQueue queue;

  /// A snapshot fetch is in flight.
  final bool loading;

  /// The delivery a manual "Mark completed" is sending, so its button can
  /// wait instead of double-firing.
  final String? busyDeliveryId;

  /// Why the last driver action failed; safe to show. Cleared by the next
  /// action or snapshot.
  final String? error;

  /// Why the last target change failed; safe to show.
  final String? targetError;

  OrderQueueState copyWith({
    OrderQueue? queue,
    bool? loading,
    String? busyDeliveryId,
    bool clearBusy = false,
    String? error,
    bool clearError = false,
    String? targetError,
    bool clearTargetError = false,
  }) => OrderQueueState(
    queue: queue ?? this.queue,
    loading: loading ?? this.loading,
    busyDeliveryId: clearBusy ? null : (busyDeliveryId ?? this.busyDeliveryId),
    error: clearError ? null : (error ?? this.error),
    targetError: clearTargetError ? null : (targetError ?? this.targetError),
  );
}

/// The single source of truth for the order queue and the daily target.
/// Seeded from `GET /v1/shift/{id}/queue`, replaced by every `queue_updated`
/// event, refreshed after a manual completion or target change, and reset
/// with the shift (see [ShiftNotifier]).
final orderQueueProvider =
    StateNotifierProvider<OrderQueueNotifier, OrderQueueState>(
      OrderQueueNotifier.new,
    );

class OrderQueueNotifier extends StateNotifier<OrderQueueState> {
  OrderQueueNotifier(this._ref) : super(const OrderQueueState()) {
    unawaited(refresh());
  }

  final Ref _ref;

  /// Bumped on every reset so a fetch that was in flight for the previous
  /// shift or driver never lands on the new one.
  int _epoch = 0;

  /// Bumped whenever a snapshot request starts or a WebSocket snapshot lands.
  /// The queue contract has no server revision, so this local version prevents
  /// an older REST response from replacing newer real-time state.
  int _snapshotVersion = 0;

  KoraApi get _api => _ref.read(koraApiProvider);

  /// Fetches the snapshot for the active shift. With no shift yet, it only
  /// reads the saved target so the driver can set one before starting. A
  /// failure (offline, or a backend without the endpoint) keeps what is
  /// showing rather than surfacing an error.
  Future<void> refresh() async {
    final epoch = _epoch;
    final snapshotVersion = ++_snapshotVersion;
    final shiftId = _ref.read(shiftProvider);
    state = state.copyWith(loading: true);
    try {
      if (shiftId == null) {
        final target = _targetFrom(await _api.fetchDriverPreferences());
        if (!_current(epoch, snapshotVersion)) return;
        state = state.copyWith(queue: state.queue.withTarget(target));
      } else {
        final queue = await _api.fetchOrderQueue(shiftId);
        if (!_current(epoch, snapshotVersion)) return;
        state = state.copyWith(queue: queue);
      }
    } catch (_) {
      // Keep the last snapshot; the next event or refresh reconciles.
    } finally {
      if (_current(epoch, snapshotVersion)) {
        state = state.copyWith(loading: false);
      }
    }
  }

  /// Replaces the snapshot with a `queue_updated` event's payload. An event
  /// for some other shift is ignored.
  void apply(OrderQueue queue) {
    final shiftId = _ref.read(shiftProvider);
    if (queue.shiftId != null && shiftId != null && queue.shiftId != shiftId) {
      return;
    }
    _snapshotVersion++;
    state = state.copyWith(queue: queue, loading: false, clearError: true);
  }

  /// Marks a stop delivered by touch, then refreshes so the next stop
  /// becomes active. Returns whether the backend accepted it.
  Future<bool> complete(String deliveryId) async {
    if (state.busyDeliveryId != null) return false;
    final epoch = _epoch;
    state = state.copyWith(busyDeliveryId: deliveryId, clearError: true);
    try {
      await _api.updateDeliveryStatus(deliveryId, 'delivered');
    } on ApiException catch (e) {
      if (_current(epoch)) {
        state = state.copyWith(clearBusy: true, error: e.message);
      }
      return false;
    } catch (_) {
      if (_current(epoch)) {
        state = state.copyWith(
          clearBusy: true,
          error: "Couldn't mark that order completed. Try again.",
        );
      }
      return false;
    }
    if (!_current(epoch)) return true;
    state = state.copyWith(clearBusy: true);
    await refresh();
    return true;
  }

  /// Sets the daily target, or clears it with null. The same preference the
  /// voice tool writes, so touch and voice agree. Returns whether it saved.
  Future<bool> setTarget(int? target) async {
    final epoch = _epoch;
    state = state.copyWith(clearTargetError: true);
    try {
      if (target == null) {
        await _api.clearDriverPreference(dailyDeliveryTargetKey);
      } else {
        await _api.setDriverPreference(dailyDeliveryTargetKey, '$target');
      }
    } on ApiException catch (e) {
      if (_current(epoch)) state = state.copyWith(targetError: e.message);
      return false;
    } catch (_) {
      if (_current(epoch)) {
        state = state.copyWith(
          targetError: "Couldn't save your target. Try again.",
        );
      }
      return false;
    }
    if (!_current(epoch)) return true;
    state = state.copyWith(queue: state.queue.withTarget(target));
    await refresh();
    return true;
  }

  /// Forgets everything: a new shift, or a sign-out. A new shift's snapshot
  /// (and the driver's target) arrives with the next [refresh].
  void reset() {
    _epoch++;
    _snapshotVersion++;
    state = const OrderQueueState();
  }

  bool _current(int epoch, [int? snapshotVersion]) =>
      mounted &&
      epoch == _epoch &&
      (snapshotVersion == null || snapshotVersion == _snapshotVersion);

  static int? _targetFrom(Map<String, String> preferences) =>
      parseTarget(preferences[dailyDeliveryTargetKey] ?? '');
}
