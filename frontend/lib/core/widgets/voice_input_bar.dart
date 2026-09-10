import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'glass_card.dart';

class VoiceInputBar extends StatelessWidget {
  const VoiceInputBar({
    super.key,
    required this.controller,
    required this.onMicTap,
    this.onAddTap,
  });

  final TextEditingController controller;
  final VoidCallback onMicTap;
  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAddTap,
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VoiceOpsColors.primaryLight.withOpacity(0.2),
                border: Border.all(
                  color: VoiceOpsColors.primary.withOpacity(0.38),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.add,
                size: 18,
                color: VoiceOpsColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: VoiceOpsText.chipLabel,
              decoration: InputDecoration(
                hintText: 'Ask me anything...',
                hintStyle: VoiceOpsText.inputHint,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          GestureDetector(
            onTap: onMicTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [VoiceOpsColors.primary, VoiceOpsColors.primaryLight],
                ),
                boxShadow: [
                  BoxShadow(
                    color: VoiceOpsColors.primary.withOpacity(0.42),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
