/// The post-shift intelligence report, as `GET /v1/shift/{shift_id}/report`
/// returns the stored `intelligence_reports` row (docs/contracts/interface.md
/// section 2; shape from the backend's `run_shift_intelligence()`). Proposed
/// refinements live in docs/backend-handoff/shift-report-endpoint.md.
class ShiftReport {
  const ShiftReport({
    required this.totalDeliveries,
    required this.deliveredCount,
    required this.failedCount,
    required this.successRate,
    this.sentimentScore,
    this.incidents = const [],
    this.routeIssues = const [],
    this.recommendations,
    this.executiveSummary,
    this.voiceSessions,
    this.shiftStartedAt,
    this.shiftEndedAt,
  });

  factory ShiftReport.fromJson(Map<String, dynamic> json) {
    final patterns = json['failure_patterns'];
    final nested = patterns is Map<String, dynamic> ? patterns : const {};
    final total = _int(json['total_deliveries']);
    final delivered = _int(json['delivered_count']);
    final rate = _double(json['success_rate']);
    return ShiftReport(
      totalDeliveries: total,
      deliveredCount: delivered,
      failedCount: _int(json['failed_count']),
      successRate: (rate ?? (total > 0 ? delivered / total * 100 : 0))
          .clamp(0, 100)
          .toDouble(),
      sentimentScore: _double(json['sentiment_score'])?.clamp(0, 1).toDouble(),
      incidents: _strings(json['incidents'] ?? nested['incidents']),
      routeIssues: _strings(json['route_issues']),
      recommendations: _text(json['recommendations']),
      executiveSummary: _text(nested['executive_summary']),
      voiceSessions: switch (nested['voice_sessions_analyzed']) {
        final num n => n.toInt(),
        _ => null,
      },
      shiftStartedAt: _time(json['shift_started_at']),
      shiftEndedAt: _time(json['shift_ended_at']),
    );
  }

  final int totalDeliveries;
  final int deliveredCount;
  final int failedCount;

  /// Share of stops delivered, 0-100.
  final double successRate;

  /// 0.0-1.0 from LeMUR: how calm and confident the driver sounded. Null
  /// when the backend sent none.
  final double? sentimentScore;

  final List<String> incidents;
  final List<String> routeIssues;
  final String? recommendations;
  final String? executiveSummary;

  /// Voice sessions the report analysed.
  final int? voiceSessions;

  /// Proposed optional fields; the duration tile shows only with both.
  final DateTime? shiftStartedAt;
  final DateTime? shiftEndedAt;

  /// Stops neither delivered nor failed (pending or rescheduled).
  int get remainingCount {
    final left = totalDeliveries - deliveredCount - failedCount;
    return left < 0 ? 0 : left;
  }

  Duration? get shiftDuration {
    final start = shiftStartedAt;
    final end = shiftEndedAt;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }
}

int _int(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => num.tryParse(s)?.toInt() ?? 0,
  _ => 0,
};

// Supabase serialises DECIMAL columns as strings or numbers.
double? _double(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

List<String> _strings(Object? value) =>
    value is List ? [for (final item in value) ?_text(item)] : const [];

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
