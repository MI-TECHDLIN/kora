import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Title row above a group of cards, with an optional trailing action
/// (e.g. "See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: VoiceOpsText.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (actionLabel != null)
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: VoiceOpsSize.touchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: VoiceOpsSpacing.md),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      actionLabel!,
                      style: VoiceOpsText.label.copyWith(
                        color: VoiceOpsColors.primaryLight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
