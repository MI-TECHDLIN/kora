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

class ActionChipsGrid extends StatelessWidget {
  const ActionChipsGrid({
    super.key,
    required this.chips,
    required this.onSelect,
  });
  final List<ActionChipData> chips;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: VoiceOpsSpacing.sm,
      crossAxisSpacing: VoiceOpsSpacing.sm,
      childAspectRatio: 2.9,
      children: List.generate(
        chips.length,
        (i) => PillChip(
          icon: chips[i].icon,
          label: chips[i].label,
          accent: chips[i].accent,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}
