/// How an order reads to the driver. This is a presentation layer over the
/// frozen delivery status enum (`pending | delivered | failed | rescheduled`):
/// `active` is not stored, it is the pending stop with the lowest
/// `sequence_order` (docs/contracts/interface.md §3).
enum OrderState {
  active,
  pending,
  completed,
  failed,
  rescheduled;

  /// Reads the snapshot's `state`, falling back to the delivery `status` for
  /// a build that only sees the raw enum. Unknown values read as pending.
  static OrderState parse(Object? state, {Object? status}) {
    for (final candidate in OrderState.values) {
      if (candidate.name == state) return candidate;
    }
    return switch (status) {
      'delivered' => completed,
      'failed' => failed,
      'rescheduled' => rescheduled,
      _ => pending,
    };
  }
}

/// One stop in the driver's queue.
class QueueOrder {
  const QueueOrder({
    required this.deliveryId,
    required this.sequence,
    required this.state,
    this.recipientName,
    this.address,
    this.timeWindow,
    this.etaMinutes,
  });

  factory QueueOrder.fromJson(Map<String, dynamic> json) => QueueOrder(
    deliveryId: json['delivery_id'] as String? ?? '',
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    state: OrderState.parse(json['state'], status: json['status']),
    recipientName: _text(json['recipient_name']),
    address: _text(json['address']),
    timeWindow: _text(json['time_window']),
    etaMinutes: (json['eta_minutes'] as num?)?.round(),
  );

  final String deliveryId;
  final int sequence;
  final OrderState state;
  final String? recipientName;
  final String? address;
  final String? timeWindow;
  final int? etaMinutes;

  /// The name to show for the stop; the address stands in for a missing name.
  String get title => recipientName ?? address ?? 'Stop $sequence';
}

/// Order counts by state, as the snapshot's `counts`.
class QueueCounts {
  const QueueCounts({
    this.total = 0,
    this.completed = 0,
    this.active = 0,
    this.pending = 0,
    this.failed = 0,
    this.rescheduled = 0,
  });

  factory QueueCounts.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return QueueCounts(
      total: count('total'),
      completed: count('completed'),
      active: count('active'),
      pending: count('pending'),
      failed: count('failed'),
      rescheduled: count('rescheduled'),
    );
  }

  factory QueueCounts.of(Iterable<QueueOrder> orders) {
    int count(OrderState state) =>
        orders.where((order) => order.state == state).length;
    return QueueCounts(
      total: orders.length,
      completed: count(OrderState.completed),
      active: count(OrderState.active),
      pending: count(OrderState.pending),
      failed: count(OrderState.failed),
      rescheduled: count(OrderState.rescheduled),
    );
  }

  final int total;
  final int completed;
  final int active;
  final int pending;
  final int failed;
  final int rescheduled;
}

/// The queue snapshot: `GET /v1/shift/{shift_id}/queue`, and the payload of
/// every `queue_updated` event. All progress maths lives here so Home and
/// Summary always agree.
class OrderQueue {
  const OrderQueue({
    this.shiftId,
    this.target,
    this.counts = const QueueCounts(),
    this.orders = const [],
  });

  /// No shift, no orders and no target.
  static const empty = OrderQueue();

  factory OrderQueue.fromJson(Map<String, dynamic> json) {
    final orders = [
      if (json['orders'] case final List<dynamic> raw)
        for (final order in raw)
          if (order is Map<String, dynamic>) QueueOrder.fromJson(order),
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    return OrderQueue(
      shiftId: _text(json['shift_id']),
      target: _positive(json['target']),
      counts: json['counts'] is Map<String, dynamic>
          ? QueueCounts.fromJson(json['counts'] as Map<String, dynamic>)
          : QueueCounts.of(orders),
      orders: orders,
    );
  }

  final String? shiftId;

  /// The driver's daily delivery target, or null while unset.
  final int? target;
  final QueueCounts counts;

  /// In `sequence_order`, completed stops included.
  final List<QueueOrder> orders;

  OrderQueue withTarget(int? value) => OrderQueue(
    shiftId: shiftId,
    target: value,
    counts: counts,
    orders: orders,
  );

  bool get isEmpty => counts.total == 0;

  int get completed => counts.completed;

  /// The one stop being worked on, if any.
  QueueOrder? get active {
    for (final order in orders) {
      if (order.state == OrderState.active) return order;
    }
    return null;
  }

  List<QueueOrder> ordersIn(OrderState state) => [
    for (final order in orders)
      if (order.state == state) order,
  ];

  /// The active stop first, then pending ones: what Home previews.
  List<QueueOrder> upNext(int limit) => [
    for (final order in orders)
      if (order.state == OrderState.active || order.state == OrderState.pending)
        order,
  ].take(limit).toList();

  /// Completed share of the shift's orders, 0-1; 0 with no orders.
  double get shiftFraction =>
      counts.total <= 0 ? 0 : (counts.completed / counts.total).clamp(0, 1);

  bool get hasTarget => target != null;

  /// Completed share of the target, 0-1; 0 with no target.
  double get targetFraction {
    final goal = target;
    if (goal == null || goal <= 0) return 0;
    return (counts.completed / goal).clamp(0, 1).toDouble();
  }

  /// Deliveries still to go to reach the target; 0 once reached or unset.
  int get targetRemaining {
    final goal = target;
    if (goal == null) return 0;
    final left = goal - counts.completed;
    return left < 0 ? 0 : left;
  }

  bool get targetReached => hasTarget && counts.completed >= target!;
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// A whole number above zero, or null. A string is accepted because the
/// preference is stored as text.
int? _positive(Object? value) {
  final number = switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };
  return number != null && number > 0 ? number : null;
}

/// Validates the target editor's text: a positive whole number, or null.
int? parseTarget(String input) => _positive(input);
