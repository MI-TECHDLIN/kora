import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pill_chip.dart';

class ActionChipData {
  const ActionChipData({
    required this.icon,
    required this.label,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final Color accent;
}

/// A compact command rail that keeps one full action visible on narrow phones
/// while letting drivers reveal the remaining actions with a horizontal swipe.
class ActionChipsRail extends StatelessWidget {
  const ActionChipsRail({
    super.key,
    required this.chips,
    required this.onSelect,
  });

  final List<ActionChipData> chips;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: VoiceOpsSize.control,
      child: ListView.separated(
        key: const Key('quick-actions-rail'),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: VoiceOpsSpacing.sm),
        itemBuilder: (context, i) => PillChip(
          icon: chips[i].icon,
          label: chips[i].label,
          accent: chips[i].accent,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}
