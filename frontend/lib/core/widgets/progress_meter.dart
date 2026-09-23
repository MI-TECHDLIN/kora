import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A calm horizontal progress bar: violet fill on a hairline track. [value]
/// is 0-1 and is clamped. Screen readers hear [semanticLabel].
class ProgressMeter extends StatelessWidget {
  const ProgressMeter({
    super.key,
    required this.value,
    required this.semanticLabel,
    this.height = KoraSize.meter,
  });

  final double value;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fraction = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KoraRadius.pill),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: KoraColors.divider),
              TweenAnimationBuilder<double>(
                tween: Tween(end: fraction),
                duration: KoraMotion.base,
                curve: KoraMotion.standard,
                builder: (context, animated, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: animated,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(
                        Radius.circular(KoraRadius.pill),
                      ),
                      gradient: LinearGradient(
                        colors: [KoraColors.primary, KoraColors.primaryLight],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
