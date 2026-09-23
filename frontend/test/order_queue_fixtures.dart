import 'package:voiceops/features/summary/data/order_queue.dart';

/// One order in the `GET /v1/shift/{id}/queue` shape. [state] is the
/// presentation state; the stored `status` is derived from it.
Map<String, dynamic> orderJson(
  String id,
  int sequence,
  String state, {
  String? name,
  String? address,
  String? window,
  int? eta,
}) => {
  'delivery_id': id,
  'sequence': sequence,
  'recipient_name': name ?? 'Recipient $sequence',
  'address': address ?? '$sequence Main Street',
  'time_window': window,
  'status': switch (state) {
    'completed' => 'delivered',
    'active' || 'pending' => 'pending',
    final other => other,
  },
  'state': state,
  'eta_minutes': eta,
};

/// A queue snapshot as the backend sends it, counts included.
Map<String, dynamic> queueJson(
  List<Map<String, dynamic>> orders, {
  String shiftId = 'shift-1',
  int? target,
}) {
  int count(String state) => orders.where((o) => o['state'] == state).length;
  return {
    'shift_id': shiftId,
    'target': target,
    'counts': {
      'total': orders.length,
      'completed': count('completed'),
      'active': count('active'),
      'pending': count('pending'),
      'failed': count('failed'),
      'rescheduled': count('rescheduled'),
    },
    'orders': orders,
  };
}

/// [n] orders: the first [completed] done, then one active, then pending.
OrderQueue queueOf(int n, {int completed = 0, int? target}) =>
    OrderQueue.fromJson(
      queueJson([
        for (var i = 1; i <= n; i++)
          orderJson(
            'd-$i',
            i,
            i <= completed
                ? 'completed'
                : i == completed + 1
                ? 'active'
                : 'pending',
            window: i.isEven ? '${8 + i}:00 - ${9 + i}:00' : null,
          ),
      ], target: target),
    );
