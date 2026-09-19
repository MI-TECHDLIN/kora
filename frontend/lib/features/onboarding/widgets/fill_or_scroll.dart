import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Lays an onboarding page out to exactly fill its viewport, so `Spacer` and
/// `Expanded` work, but scrolls instead of overflowing when the content is
/// taller: short phones and large accessibility text sizes.
///
/// [builder] gets the viewport size for sizing hero elements such as the
/// orb. Everything it returns must support intrinsic sizing, so no
/// `LayoutBuilder` inside.
class FillOrScroll extends StatelessWidget {
  const FillOrScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, Size viewport) builder;

  /// Below this viewport height a page switches to its compact layout.
  static const _compactBelow = 620.0;

  /// Whether [viewport] is short enough for compact type and spacing.
  static bool isCompact(Size viewport) => viewport.height < _compactBelow;

  /// The onboarding headline style for [viewport].
  static TextStyle headlineFor(Size viewport) =>
      isCompact(viewport) ? KoraText.displayCompact : KoraText.display;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: builder(context, constraints.biggest)),
        ),
      ),
    );
  }
}
