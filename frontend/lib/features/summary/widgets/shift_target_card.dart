import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/progress_meter.dart';
import '../../../providers/order_queue_provider.dart';
import '../data/order_queue.dart';

/// "8 of 15 target deliveries completed".
String targetProgressLabel(OrderQueue queue) =>
    '${queue.completed} of ${queue.target} target deliveries completed';

/// What is left, in a plain tone: no pressure, no streaks.
String targetRemainingLabel(OrderQueue queue) {
  if (queue.targetReached) return 'Target reached. Nice work today.';
  final left = queue.targetRemaining;
  return left == 1 ? '1 delivery to go' : '$left deliveries to go';
}

/// The driver's own daily target: progress against it, and a small editor to
/// set, change or clear it. The same `daily_delivery_target` preference the
/// voice tool writes.
class ShiftTargetCard extends ConsumerStatefulWidget {
  const ShiftTargetCard({super.key});

  @override
  ConsumerState<ShiftTargetCard> createState() => _ShiftTargetCardState();
}

class _ShiftTargetCardState extends ConsumerState<ShiftTargetCard> {
  final _controller = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _invalid;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit(int? current) => setState(() {
    _editing = true;
    _invalid = null;
    _controller.text = current == null ? '' : '$current';
  });

  void _cancel() => setState(() {
    _editing = false;
    _invalid = null;
  });

  Future<void> _save() async {
    final target = parseTarget(_controller.text);
    if (target == null) {
      setState(
        () => _invalid = 'Enter a whole number from 1 to $maxDailyTarget.',
      );
      return;
    }
    await _apply(target);
  }

  Future<void> _apply(int? target) async {
    setState(() => _saving = true);
    final saved = await ref.read(orderQueueProvider.notifier).setTarget(target);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderQueueProvider);
    final queue = state.queue;
    return GlassCard(
      key: const Key('target-card'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                TablerIcons.target,
                size: KoraSize.iconMd,
                color: KoraColors.primaryLight,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Expanded(child: Text('DAILY TARGET', style: KoraText.caption)),
            ],
          ),
          const SizedBox(height: KoraSpacing.md),
          if (_editing)
            _editor()
          else if (queue.hasTarget)
            _progress(queue)
          else
            _unset(),
          if (state.targetError case final message?) ...[
            const SizedBox(height: KoraSpacing.sm),
            Text(
              message,
              key: const Key('target-error'),
              style: KoraText.label.copyWith(color: KoraColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unset() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('No target set', style: KoraText.title),
      const SizedBox(height: KoraSpacing.xs),
      Text(
        'Pick a number of deliveries you would like to reach today. '
        'Or say "Kora, set my target to 15 deliveries today."',
        style: KoraText.bodyMuted,
      ),
      const SizedBox(height: KoraSpacing.md),
      Align(
        alignment: Alignment.centerLeft,
        child: PrimaryButton(
          key: const Key('target-set'),
          label: 'Set target',
          icon: TablerIcons.target,
          onPressed: () => _edit(null),
        ),
      ),
    ],
  );

  Widget _progress(OrderQueue queue) {
    final label = targetProgressLabel(queue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          key: const Key('target-progress-text'),
          style: KoraText.title,
        ),
        const SizedBox(height: KoraSpacing.sm),
        ProgressMeter(
          key: const Key('target-progress-meter'),
          value: queue.targetFraction,
          semanticLabel: label,
        ),
        const SizedBox(height: KoraSpacing.sm),
        Text(
          targetRemainingLabel(queue),
          key: const Key('target-remaining'),
          style: KoraText.bodyMuted,
        ),
        const SizedBox(height: KoraSpacing.xs),
        Wrap(
          spacing: KoraSpacing.sm,
          children: [
            TextButton.icon(
              key: const Key('target-change'),
              onPressed: _saving ? null : () => _edit(queue.target),
              icon: const Icon(TablerIcons.pencil, size: KoraSize.iconSm),
              label: const Text('Change'),
            ),
            TextButton.icon(
              key: const Key('target-clear'),
              onPressed: _saving ? null : () => _apply(null),
              icon: const Icon(TablerIcons.x, size: KoraSize.iconSm),
              label: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('target-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        onSubmitted: (_) => _save(),
        style: KoraText.title,
        decoration: InputDecoration(
          labelText: 'Deliveries today',
          hintText: 'For example, 15',
          errorText: _invalid,
        ),
      ),
      const SizedBox(height: KoraSpacing.md),
      Wrap(
        spacing: KoraSpacing.sm,
        runSpacing: KoraSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PrimaryButton(
            key: const Key('target-save'),
            label: _saving ? 'Saving...' : 'Save target',
            onPressed: _saving ? null : _save,
          ),
          TextButton(
            key: const Key('target-cancel'),
            onPressed: _saving ? null : _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    ],
  );
}
