import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../data/shift_report.dart';

/// The finished shift, drawn from the post-shift report: success ring, stat
/// tiles, the co-rider's recap, sentiment, incidents, route notes and the
/// coach's note. The tone is coaching, not grading: calm colours, no red
/// verdicts.
class ShiftReportView extends StatelessWidget {
  const ShiftReportView({super.key, required this.report, this.recap});

  final ShiftReport report;

  /// The streamed summary; the report's own executive summary stands in
  /// when the stream carried none.
  final String? recap;

  @override
  Widget build(BuildContext context) {
    final recapText = (recap?.trim().isNotEmpty ?? false)
        ? recap!.trim()
        : report.executiveSummary;
    final gap = const SizedBox(height: KoraSpacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SuccessCard(report: report),
        gap,
        _StatGrid(report: report),
        if (recapText != null) ...[
          gap,
          RecapCard(text: recapText, live: false),
        ],
        if (report.sentimentScore case final score?) ...[
          gap,
          _SentimentCard(score: score),
        ],
        if (report.incidents.isNotEmpty) ...[
          gap,
          _NoteList(
            key: const Key('report-incidents'),
            title: 'INCIDENTS - ${report.incidents.length}',
            items: report.incidents,
            dotColor: KoraColors.amber,
          ),
        ],
        if (report.routeIssues.isNotEmpty) ...[
          gap,
          _NoteList(
            key: const Key('report-route-issues'),
            title: 'ROUTE NOTES',
            items: report.routeIssues,
            dotColor: KoraColors.blue,
          ),
        ],
        if (report.recommendations case final note?) ...[
          gap,
          _CoachNote(text: note),
        ],
      ],
    );
  }
}

/// The co-rider's spoken summary as text; [live] while it is still
/// streaming in.
class RecapCard extends StatelessWidget {
  const RecapCard({super.key, required this.text, required this.live});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            live ? 'SHIFT SUMMARY - LIVE' : "CO-RIDER'S RECAP",
            style: KoraText.caption,
          ),
          const SizedBox(height: KoraSpacing.md),
          Text(text, style: KoraText.body),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.report});

  final ShiftReport report;

  @override
  Widget build(BuildContext context) {
    final percent = report.successRate.round();
    return GlassCard(
      key: const Key('report-success'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Row(
        children: [
          Semantics(
            label: '$percent percent success rate',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: KoraSize.successRing,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: report.successRate / 100),
                duration: KoraMotion.slow,
                curve: KoraMotion.standard,
                builder: (context, value, child) =>
                    CustomPaint(painter: _RingPainter(value), child: child),
                child: Center(
                  child: Text('$percent%', style: KoraText.numericCompact),
                ),
              ),
            ),
          ),
          const SizedBox(width: KoraSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SUCCESS RATE', style: KoraText.caption),
                const SizedBox(height: KoraSpacing.xs),
                Text(
                  report.totalDeliveries == 0
                      ? 'No stops on this shift'
                      : '${report.deliveredCount} of '
                            '${report.totalDeliveries} delivered',
                  style: KoraText.title,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);

  /// 0-1.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = KoraSize.successRingStroke;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = KoraColors.divider;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    // Start the sweep a cap's width before 12 o'clock so the round start
    // cap takes the violet start, not the green end of the gradient.
    final cap = stroke / rect.width;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: const [KoraColors.primary, KoraColors.success],
        transform: GradientRotation(-math.pi / 2 - cap),
      ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// One number under an icon, as a [StatTile] draws it.
typedef StatData = ({IconData icon, Color color, String value, String label});

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.report});

  final ShiftReport report;

  @override
  Widget build(BuildContext context) {
    final duration = report.shiftDuration;
    final stats = <StatData>[
      (
        icon: TablerIcons.circleCheck,
        color: KoraColors.success,
        value: '${report.deliveredCount}',
        label: 'Delivered',
      ),
      (
        icon: TablerIcons.circleX,
        color: KoraColors.pink,
        value: '${report.failedCount}',
        label: 'Failed',
      ),
      (
        icon: TablerIcons.hourglass,
        color: KoraColors.amber,
        value: '${report.remainingCount}',
        label: 'Remaining',
      ),
      if (duration != null)
        (
          icon: TablerIcons.clockHour4,
          color: KoraColors.blue,
          value: formatShiftDuration(duration),
          label: 'On shift',
        )
      else if (report.voiceSessions case final sessions?)
        (
          icon: TablerIcons.microphone,
          color: KoraColors.primaryLight,
          value: '$sessions',
          label: 'Voice check-ins',
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - KoraSpacing.md) / 2;
        return Wrap(
          spacing: KoraSpacing.md,
          runSpacing: KoraSpacing.md,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: StatTile(stat: stat),
              ),
          ],
        );
      },
    );
  }
}

/// A small glass tile: icon, big number, label.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.stat});

  final StatData stat;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: Key('stat-${stat.label}'),
      frosted: false,
      shadow: false,
      borderRadius: KoraRadius.control,
      padding: const EdgeInsets.all(KoraSpacing.md),
      child: Semantics(
        label: '${stat.label}: ${stat.value}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(stat.icon, size: KoraSize.iconMd, color: stat.color),
            const SizedBox(height: KoraSpacing.sm),
            Text(
              stat.value,
              style: KoraText.numericCompact,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: KoraSpacing.xs),
            Text(
              stat.label,
              style: KoraText.label.copyWith(
                color: KoraColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// "6h 40m", or "45m" under an hour.
String formatShiftDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

class _SentimentCard extends StatelessWidget {
  const _SentimentCard({required this.score});

  /// 0-1.
  final double score;

  /// Coaching words, never a grade.
  String get _mood => switch (score) {
    >= 0.75 => 'Calm and steady',
    >= 0.5 => 'Mostly steady',
    _ => 'A demanding shift',
  };

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const Key('report-sentiment'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOW THE SHIFT FELT', style: KoraText.caption),
          const SizedBox(height: KoraSpacing.sm),
          Row(
            children: [
              Icon(
                TablerIcons.moodSmile,
                size: KoraSize.iconMd,
                color: KoraColors.blue,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Expanded(child: Text(_mood, style: KoraText.title)),
              Text(
                '${(score * 100).round()}%',
                style: KoraText.label.copyWith(
                  color: KoraColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: KoraSpacing.md),
          Semantics(
            label: 'Sentiment ${(score * 100).round()} percent',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoraRadius.pill),
              child: SizedBox(
                height: KoraSize.meter,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: KoraColors.divider),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: score,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.circular(KoraRadius.pill),
                          ),
                          gradient: LinearGradient(
                            colors: [
                              KoraColors.blue,
                              KoraColors.success,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: KoraSpacing.sm),
          Text(
            'How calm and confident you sounded on your voice check-ins.',
            style: KoraText.label.copyWith(color: KoraColors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({
    super.key,
    required this.title,
    required this.items,
    required this.dotColor,
  });

  final String title;
  final List<String> items;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: KoraText.caption),
          for (final item in items) ...[
            const SizedBox(height: KoraSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Centres the dot on the first line of body text.
                  padding: const EdgeInsets.only(top: KoraSpacing.sm),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(
                      dimension: KoraSize.listDot,
                    ),
                  ),
                ),
                const SizedBox(width: KoraSpacing.md),
                Expanded(child: Text(item, style: KoraText.bodyMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachNote extends StatelessWidget {
  const _CoachNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const Key('report-coach-note'),
      fill: KoraColors.primaryTint,
      border: Border.all(
        color: KoraColors.primaryGlow,
        width: KoraGlass.borderWidth,
      ),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                TablerIcons.bulb,
                size: KoraSize.iconMd,
                color: KoraColors.primaryLight,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Text("COACH'S NOTE", style: KoraText.caption),
            ],
          ),
          const SizedBox(height: KoraSpacing.md),
          Text(text, style: KoraText.body),
        ],
      ),
    );
  }
}
