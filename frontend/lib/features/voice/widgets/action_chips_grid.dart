import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';

class ActionChipData {
  const ActionChipData({
    required this.icon,
    required this.label,
    required this.iconBgColors,
  });
  final IconData icon;
  final String label;
  final List<Color> iconBgColors;
}

class ActionChip extends StatelessWidget {
  const ActionChip({super.key, required this.data, required this.onTap});
  final ActionChipData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: VoiceOpsRadius.md,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: LinearGradient(colors: data.iconBgColors),
              ),
              child: Icon(data.icon, size: 12, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data.label,
                style: VoiceOpsText.chipLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 2.6,
      children: List.generate(
        chips.length,
        (i) => ActionChip(data: chips[i], onTap: () => onSelect(i)),
      ),
    );
  }
}
