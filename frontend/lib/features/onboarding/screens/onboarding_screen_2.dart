import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../widgets/fill_or_scroll.dart';

/// Onboarding screen 2, the Power (PRD v4.0 §4.7, SDD v2.0 §4.2), over the
/// lavender mood. A layered card stack, not a flat grid, is a static demo
/// of the co-rider doing three things at once.
///
/// The "Mic access" card is a visual mock: no permission package is a
/// dependency yet, so its action only flips [micAllowed] through
/// [onAllowMic]. Wire the real OS request here when the voice work adds
/// the audio-in package.
class OnboardingPower extends StatelessWidget {
  const OnboardingPower({
    super.key,
    required this.driverName,
    required this.micAllowed,
    required this.onAllowMic,
  });

  static const headline = 'Three things happen at once. You do nothing.';

  final String driverName;
  final bool micAllowed;
  final VoidCallback onAllowMic;

  @override
  Widget build(BuildContext context) {
    // Dark status-bar icons while the light lavender mood is on screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VoiceOpsSpacing.gutter),
        child: FillOrScroll(
          builder: (context, viewport) => Column(
            children: [
              const SizedBox(height: VoiceOpsSpacing.lg),
              _Greeting(driverName: driverName),
              const SizedBox(height: VoiceOpsSpacing.lg),
              Expanded(
                child: _CardStack(
                  compact: FillOrScroll.isCompact(viewport),
                  micAllowed: micAllowed,
                  onAllowMic: onAllowMic,
                ),
              ),
              const SizedBox(height: VoiceOpsSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  headline,
                  style: FillOrScroll.headlineFor(
                    viewport,
                  ).copyWith(color: VoiceOpsMood.ink),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: VoiceOpsSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar with the co-rider beside it, over "Hello, [Name] — here's what
/// it caught already".
class _Greeting extends StatelessWidget {
  const _Greeting({required this.driverName});

  final String driverName;

  @override
  Widget build(BuildContext context) {
    final initial = driverName.isEmpty ? '' : driverName[0].toUpperCase();

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: VoiceOpsSize.avatar,
                height: VoiceOpsSize.avatar,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      VoiceOpsColors.primary,
                      VoiceOpsColors.primaryDark,
                    ],
                  ),
                  border: Border.all(
                    color: VoiceOpsMood.paper,
                    width: VoiceOpsGlass.borderWidth * 2,
                  ),
                ),
                child: Text(
                  initial,
                  style: VoiceOpsText.title.copyWith(
                    color: VoiceOpsColors.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: VoiceOpsSpacing.xs),
            const MascotDisplay(
              state: AgentState.thinking,
              size: VoiceOpsSize.avatar,
            ),
          ],
        ),
        const SizedBox(height: VoiceOpsSpacing.sm),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Hello, $driverName — ',
                style: VoiceOpsText.headline.copyWith(color: VoiceOpsMood.ink),
              ),
              TextSpan(
                text: "here's what it caught already",
                style: VoiceOpsText.weight(
                  VoiceOpsText.headline,
                  FontWeight.w400,
                ).copyWith(color: VoiceOpsMood.inkMuted),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// "Next stop" behind, the holographic "Live route" teaser peeking in from
/// the right edge, and the action-required "Mic access" card in front. The
/// three cards arrive almost together, staggered just enough to read as
/// parallel work.
class _CardStack extends StatefulWidget {
  const _CardStack({
    required this.compact,
    required this.micAllowed,
    required this.onAllowMic,
  });

  /// Short phones fan the cards tighter.
  final bool compact;
  final bool micAllowed;
  final VoidCallback onAllowMic;

  @override
  State<_CardStack> createState() => _CardStackState();
}

class _CardStackState extends State<_CardStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: VoiceOpsMotion.stagger,
  );

  // Small tilts (radians) give the stack its layered, hand-dealt look.
  static const _tiltBack = 0.05;
  static const _tiltTeaser = -0.08;
  static const _tiltFront = -0.03;

  static const _clusterHeight = 330.0;
  static const _clusterHeightCompact = 300.0;

  // Where the front card sits: low enough that the Next stop card's two rows
  // show above it. Short phones need it lower because their front card
  // wraps taller.
  static const _frontAt = Alignment.centerLeft;
  static const _frontAtCompact = Alignment(-1, 0.4);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _entrance.value = 1;
    } else if (_entrance.isDismissed) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Fades and lifts card [order] (0 = first) into place.
  Widget _arrive(int order, Widget child) {
    final start = order * 0.2;
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, start + 0.6, curve: VoiceOpsMotion.standard),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  /// Card [order] at [alignment] within the stack, [widthFactor] of its width.
  Widget _place(
    int order, {
    required Alignment alignment,
    required double widthFactor,
    required Widget card,
  }) => Positioned.fill(
    child: Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: _arrive(order, card),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // A fixed-height cluster keeps the cards overlapping as a stack on tall
    // phones instead of drifting apart; on short ones it shrinks and they
    // overlap more. Cards are placed by alignment rather than measured
    // offsets so the stack keeps intrinsic sizing (FillOrScroll needs it).
    return Center(
      child: SizedBox(
        height: widget.compact ? _clusterHeightCompact : _clusterHeight,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _place(
              0,
              alignment: Alignment.topRight,
              widthFactor: 0.64,
              card: Transform.rotate(
                angle: _tiltBack,
                child: const _NextStopCard(),
              ),
            ),
            _place(
              1,
              alignment: Alignment.bottomRight,
              widthFactor: 0.56,
              // Slides past the page edge so it peeks in from the side.
              card: FractionalTranslation(
                translation: const Offset(0.36, 0),
                child: Transform.rotate(
                  angle: _tiltTeaser,
                  child: const _LiveRouteTeaser(),
                ),
              ),
            ),
            _place(
              2,
              alignment: widget.compact ? _frontAtCompact : _frontAt,
              widthFactor: 0.7,
              card: Transform.rotate(
                angle: _tiltFront,
                child: _MicAccessCard(
                  allowed: widget.micAllowed,
                  onAllow: widget.onAllowMic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted-white card surface shared by the two light cards.
BoxDecoration _paperCard({required bool front}) => BoxDecoration(
  color: front ? VoiceOpsMood.paper : VoiceOpsMood.paperGlass,
  borderRadius: BorderRadius.circular(VoiceOpsRadius.card),
  border: Border.all(
    color: VoiceOpsMood.paperBorder,
    width: VoiceOpsGlass.borderWidth,
  ),
  boxShadow: VoiceOpsGlass.shadow,
);

TextStyle get _kicker =>
    VoiceOpsText.caption.copyWith(color: VoiceOpsMood.inkMuted);

class _NextStopCard extends StatelessWidget {
  const _NextStopCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      decoration: _paperCard(front: false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                TablerIcons.mapPin,
                size: VoiceOpsSize.iconSm,
                color: VoiceOpsMood.inkMuted,
              ),
              const SizedBox(width: VoiceOpsSpacing.xs),
              Expanded(
                child: Text(
                  'NEXT STOP',
                  style: _kicker,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '12 min',
                style: VoiceOpsText.label.copyWith(
                  color: VoiceOpsMood.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: VoiceOpsSpacing.sm),
          // Kept to two short rows: the front card covers the rest of this
          // one, and the stop itself must stay readable above it.
          Text(
            'Lekki Phase 1',
            style: VoiceOpsText.title.copyWith(color: VoiceOpsMood.ink),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LiveRouteTeaser extends StatelessWidget {
  const _LiveRouteTeaser();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      decoration: BoxDecoration(
        gradient: VoiceOpsMood.holographic,
        borderRadius: BorderRadius.circular(VoiceOpsRadius.card),
        border: Border.all(
          color: VoiceOpsMood.paperBorder,
          width: VoiceOpsGlass.borderWidth,
        ),
        boxShadow: VoiceOpsGlass.shadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: VoiceOpsSize.iconXl,
            height: VoiceOpsSize.iconXl,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: VoiceOpsMood.paperGlass,
            ),
            child: const Icon(
              TablerIcons.route,
              size: VoiceOpsSize.iconSm,
              color: VoiceOpsMood.ink,
            ),
          ),
          const SizedBox(height: VoiceOpsSpacing.md),
          Text(
            'Live route',
            style: VoiceOpsText.title.copyWith(color: VoiceOpsMood.ink),
          ),
          Text(
            '3 stops · 18 min',
            style: VoiceOpsText.label.copyWith(color: VoiceOpsMood.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _MicAccessCard extends StatelessWidget {
  const _MicAccessCard({required this.allowed, required this.onAllow});

  final bool allowed;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      decoration: _paperCard(front: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: VoiceOpsMotion.base,
                width: VoiceOpsSize.progressDot,
                height: VoiceOpsSize.progressDot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: allowed
                      ? VoiceOpsColors.success
                      : VoiceOpsColors.danger,
                ),
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              Flexible(
                child: Text(
                  allowed ? 'ALL SET' : 'ACTION REQUIRED',
                  style: _kicker,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: VoiceOpsSpacing.sm),
          Text(
            'Mic access',
            style: VoiceOpsText.headline.copyWith(color: VoiceOpsMood.ink),
          ),
          const SizedBox(height: VoiceOpsSpacing.xs),
          Text(
            'Your co-rider needs the mic so it can hear you over road noise.',
            style: VoiceOpsText.weight(
              VoiceOpsText.label,
              FontWeight.w400,
            ).copyWith(color: VoiceOpsMood.inkMuted),
          ),
          const SizedBox(height: VoiceOpsSpacing.md),
          AnimatedSwitcher(
            duration: VoiceOpsMotion.base,
            child: allowed
                ? Row(
                    key: const ValueKey('allowed'),
                    children: [
                      const Icon(
                        TablerIcons.circleCheck,
                        size: VoiceOpsSize.iconMd,
                        color: VoiceOpsMood.ink,
                      ),
                      const SizedBox(width: VoiceOpsSpacing.xs),
                      Flexible(
                        child: Text(
                          'Mic allowed',
                          style: VoiceOpsText.label.copyWith(
                            color: VoiceOpsMood.ink,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : _AllowButton(key: const ValueKey('allow'), onTap: onAllow),
          ),
        ],
      ),
    );
  }
}

/// Compact dark pill on the white card. Still a full 48px touch target.
class _AllowButton extends StatelessWidget {
  const _AllowButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(VoiceOpsRadius.pill);
    return Semantics(
      container: true,
      button: true,
      label: 'Allow mic',
      excludeSemantics: true,
      child: Material(
        color: VoiceOpsMood.ink,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: VoiceOpsSize.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VoiceOpsSpacing.lg,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    TablerIcons.microphone,
                    size: VoiceOpsSize.iconSm,
                    color: VoiceOpsMood.paper,
                  ),
                  const SizedBox(width: VoiceOpsSpacing.sm),
                  Flexible(
                    child: Text(
                      'Allow mic',
                      style: VoiceOpsText.label.copyWith(
                        color: VoiceOpsMood.paper,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
