import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
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
      borderRadius: KoraRadius.pill,
      padding: const EdgeInsets.all(KoraSpacing.xs),
      child: Row(
        children: [
          _RoundButton(
            onTap: onAddTap,
            semanticLabel: 'Add',
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KoraColors.primaryTint,
            ),
            child: const Icon(
              TablerIcons.plus,
              size: KoraSize.iconSm,
              color: KoraColors.primaryLight,
            ),
          ),
          const SizedBox(width: KoraSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              style: KoraText.body,
              decoration: InputDecoration(
                hintText: 'Ask me anything...',
                hintStyle: KoraText.body.copyWith(
                  color: KoraColors.textFaint,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          _RoundButton(
            onTap: onMicTap,
            semanticLabel: 'Speak',
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KoraColors.primary, KoraColors.primaryDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: KoraColors.primaryGlow,
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              TablerIcons.microphone,
              size: KoraSize.iconMd,
              color: KoraColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular button with a full [KoraSize.touchTarget] hit area.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.onTap,
    required this.semanticLabel,
    required this.decoration,
    required this.child,
  });

  final VoidCallback? onTap;
  final String semanticLabel;
  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: KoraSize.touchTarget,
          child: DecoratedBox(
            decoration: decoration,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
