import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// It is also where the app asks for every OS permission it needs: the
/// "Mic access" and "Location" cards. [micAllowed] and [locationAllowed]
/// are the real OS answers, and [onAllowMic] / [onAllowLocation] ask.
/// The onboarding flow owns both.
class OnboardingPower extends StatelessWidget {
  const OnboardingPower({
    super.key,
    required this.driverName,
    required this.micAllowed,
    required this.onAllowMic,
    required this.locationAllowed,
    required this.onAllowLocation,
  });

  static const headline = 'Three things happen at once. You do nothing.';

  final String driverName;
  final bool micAllowed;
  final VoidCallback onAllowMic;
  final bool locationAllowed;
  final VoidCallback onAllowLocation;

  @override
  Widget build(BuildContext context) {
    // Dark status-bar icons while the light lavender mood is on screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KoraSpacing.gutter),
        child: FillOrScroll(
          builder: (context, viewport) => Column(
            children: [
              const SizedBox(height: KoraSpacing.lg),
              _Greeting(driverName: driverName),
              const SizedBox(height: KoraSpacing.sm),
              Expanded(
                child: _CardStack(
                  micAllowed: micAllowed,
                  onAllowMic: onAllowMic,
                  locationAllowed: locationAllowed,
                  onAllowLocation: onAllowLocation,
                ),
              ),
              const SizedBox(height: KoraSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  headline,
                  style: FillOrScroll.headlineFor(
                    viewport,
                  ).copyWith(color: KoraMood.ink),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: KoraSpacing.md),
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
                width: KoraSize.avatar,
                height: KoraSize.avatar,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      KoraColors.primary,
                      KoraColors.primaryDark,
                    ],
                  ),
                  border: Border.all(
                    color: KoraMood.paper,
                    width: KoraGlass.borderWidth * 2,
                  ),
                ),
                child: Text(
                  initial,
                  style: KoraText.title.copyWith(
                    color: KoraColors.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KoraSpacing.xs),
            const MascotDisplay(
              state: AgentState.thinking,
              size: KoraSize.avatar,
            ),
          ],
        ),
        const SizedBox(height: KoraSpacing.sm),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Hello, $driverName — ',
                style: KoraText.headline.copyWith(color: KoraMood.ink),
              ),
              TextSpan(
                text: "here's what it caught already",
                style: KoraText.weight(
                  KoraText.headline,
                  FontWeight.w400,
                ).copyWith(color: KoraMood.inkMuted),
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
/// the top-left corner, and the action-required "Mic access" and "Location"
/// cards in front. The cards arrive almost together, staggered just enough
/// to read as parallel work.
class _CardStack extends StatefulWidget {
  const _CardStack({
    required this.micAllowed,
    required this.onAllowMic,
    required this.locationAllowed,
    required this.onAllowLocation,
  });

  final bool micAllowed;
  final VoidCallback onAllowMic;
  final bool locationAllowed;
  final VoidCallback onAllowLocation;

  @override
  State<_CardStack> createState() => _CardStackState();
}

class _CardStackState extends State<_CardStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: KoraMotion.stagger,
  );

  // Small tilts (radians) give the stack its layered, hand-dealt look.
  static const _tiltBack = 0.05;
  static const _tiltTeaser = -0.08;
  static const _tiltFront = -0.03;
  static const _tiltLocation = 0.03;

  // How far a card slides under (positive) or sits apart from (negative)
  // the one after it. Negative here: a thin seam between the cards, so the
  // stagger reads as deliberate layering instead of cards merging into each
  // other. [_Overlapped] bounds either way by [_cardPadding], and [_Tilted]
  // puts each tilt into the card's laid-out height, so what the column
  // stacks is what the screen paints: even at the tilt's lowest and highest
  // corners the seam stays open, and no card covers another's text or allow
  // button, at any text size.
  static const _underNextStop = -KoraSpacing.xs;
  static const _underMic = -KoraSpacing.xs;

  // The front cards claim the right edge at the top (next stop) and the
  // bottom (location), and the left edge in the middle (mic), leaving the
  // top-left corner — above the mic card, left of the next-stop card —
  // uncovered, and (unlike the other free corner, bottom-left) still inside
  // a short phone's unscrolled viewport.
  static const _teaserAt = Alignment(-1, -1);

  static const _cardCount = 4;

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
    final start = order * 0.4 / (_cardCount - 1);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, start + 0.6, curve: KoraMotion.standard),
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
  Widget _deal(
    int order, {
    required Alignment alignment,
    required double widthFactor,
    required Widget card,
  }) => Align(
    alignment: alignment,
    child: FractionallySizedBox(
      widthFactor: widthFactor,
      child: _arrive(order, card),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The light cards stack in reading order, each laid over the bottom
    // padding of the one before. Bigger text pushes them down, and the page
    // scrolls, instead of piling them onto each other's buttons. The teaser
    // sits behind them all, placed by alignment.
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _deal(
              1,
              alignment: _teaserAt,
              widthFactor: 0.44,
              // Peeks past the top-left corner so it reads as sliding in
              // from off-screen, narrow enough that its label wraps clear
              // of the next-stop and mic cards instead of under them, but
              // not so far off that its icon and label get cropped away.
              card: const FractionalTranslation(
                translation: Offset(-0.15, -0.45),
                child: _Tilted(angle: _tiltTeaser, child: _LiveRouteTeaser()),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Overlapped(
                overlap: _underNextStop,
                child: _deal(
                  0,
                  alignment: Alignment.centerRight,
                  widthFactor: 0.64,
                  card: const _Tilted(angle: _tiltBack, child: _NextStopCard()),
                ),
              ),
              _Overlapped(
                overlap: _underMic,
                child: _deal(
                  2,
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.76,
                  card: _Tilted(
                    angle: _tiltFront,
                    child: _AccessCard(
                      title: 'Mic access',
                      reason:
                          'Your co-rider needs the mic so it can hear you '
                          'over road noise.',
                      allowIcon: TablerIcons.microphone,
                      allowLabel: 'Allow mic',
                      allowedLabel: 'Mic allowed',
                      allowed: widget.micAllowed,
                      onAllow: widget.onAllowMic,
                    ),
                  ),
                ),
              ),
              _deal(
                3,
                alignment: Alignment.centerRight,
                widthFactor: 0.7,
                card: _Tilted(
                  angle: _tiltLocation,
                  child: _AccessCard(
                    title: 'Location',
                    reason: 'It routes you stop to stop.',
                    allowIcon: TablerIcons.currentLocation,
                    allowLabel: 'Allow location',
                    allowedLabel: 'Location allowed',
                    allowed: widget.locationAllowed,
                    onAllow: widget.onAllowLocation,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lays [child] out as usual but takes [overlap] less height in its parent,
/// so the next card in the column slides over that much of its bottom edge.
/// A negative [overlap] does the opposite: the child takes that much more
/// height, leaving a gap before the next card. Keeps intrinsic sizing, which
/// [FillOrScroll] needs.
///
/// [overlap] may not exceed [_cardPadding] either way. Every card in the
/// stack pads its content by that much and reports its tilt as part of its
/// height ([_Tilted]), so an overlap within the padding lands on blank card,
/// never on a row of text or an allow button, and a gap within it keeps the
/// cards close enough to read as one stack rather than a list.
class _Overlapped extends SingleChildRenderObjectWidget {
  const _Overlapped({required this.overlap, required super.child})
    : assert(
        -_cardPadding <= overlap && overlap <= _cardPadding,
        'a card may slide under, or sit apart from, the next one by at most '
        'its own padding',
      );

  final double overlap;

  @override
  _RenderOverlapped createRenderObject(BuildContext context) =>
      _RenderOverlapped(overlap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOverlapped renderObject,
  ) => renderObject.overlap = overlap;
}

class _RenderOverlapped extends RenderProxyBox {
  _RenderOverlapped(this._overlap);

  double _overlap;
  set overlap(double value) {
    if (value == _overlap) return;
    _overlap = value;
    markNeedsLayout();
  }

  // A positive overlap trims the height the parent stacks; a negative one
  // (a gap) adds to it.
  double _trim(double height) => math.max(0, height - _overlap);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _trim(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _trim(super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final full = child!.getDryLayout(constraints);
    return constraints.constrain(Size(full.width, _trim(full.height)));
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, _trim(child!.size.height)),
    );
  }

  // It paints all of the child, the overlap included (and below it while
  // the card slides in), so it takes taps on all of it too.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// Tilts [child] by [angle] radians and, unlike [Transform.rotate], counts
/// the tilt in its own layout height: a rotated card's top corners rise and
/// its bottom corners drop outside the unrotated box, and the column that
/// stacks the cards has to stack what is actually painted. Without this the
/// card after it starts that much higher than the layout says, which is what
/// used to push the mic card onto the stop's rows.
///
/// Width is left alone. The cards are already inset by their width factors,
/// and the teaser is meant to bleed off the right edge.
class _Tilted extends SingleChildRenderObjectWidget {
  const _Tilted({required this.angle, required super.child});

  final double angle;

  @override
  _RenderTilted createRenderObject(BuildContext context) =>
      _RenderTilted(angle);

  @override
  void updateRenderObject(BuildContext context, _RenderTilted renderObject) =>
      renderObject.angle = angle;
}

class _RenderTilted extends RenderShiftedBox {
  _RenderTilted(this._angle) : super(null);

  double _angle;
  set angle(double value) {
    if (value == _angle) return;
    _angle = value;
    markNeedsLayout();
  }

  /// Height of a [width] x [height] box once tilted about its centre. The
  /// child sits centred inside it, so each end gains half the difference.
  double _tilted(double width, double height) => math.max(
    height,
    width * math.sin(_angle).abs() + height * math.cos(_angle).abs(),
  );

  @override
  double computeMinIntrinsicHeight(double width) =>
      _tilted(width, super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _tilted(width, super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final inner = child.getDryLayout(constraints);
    return constraints.constrain(
      Size(inner.width, _tilted(inner.width, inner.height)),
    );
  }

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(child.size.width, _tilted(child.size.width, child.size.height)),
    );
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }

  /// Rotation about the centre of this box, which is also the centre of the
  /// child — so the tilted card fills the height reserved for it exactly.
  Matrix4 get _rotation {
    final centre = size.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..rotateZ(_angle)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }

  final _tilt = LayerHandle<TransformLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _tilt.layer = context.pushTransform(
      needsCompositing,
      offset,
      _rotation,
      super.paint,
      oldLayer: _tilt.layer,
    );
  }

  @override
  void dispose() {
    _tilt.layer = null;
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _rotation,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_rotation);
    super.applyPaintTransform(child, transform);
  }
}

/// What every light card pads its content by, and so the budget a card has
/// to spare when the next one slides under it (see [_Overlapped]).
const _cardPadding = KoraSpacing.lg;

/// Frosted-white card surface shared by the light cards.
BoxDecoration _paperCard({required bool front}) => BoxDecoration(
  color: front ? KoraMood.paper : KoraMood.paperGlass,
  borderRadius: BorderRadius.circular(KoraRadius.card),
  border: Border.all(
    color: KoraMood.paperBorder,
    width: KoraGlass.borderWidth,
  ),
  boxShadow: KoraGlass.shadow,
);

TextStyle get _kicker =>
    KoraText.caption.copyWith(color: KoraMood.inkMuted);

class _NextStopCard extends StatelessWidget {
  const _NextStopCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: _paperCard(front: false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                TablerIcons.mapPin,
                size: KoraSize.iconSm,
                color: KoraMood.inkMuted,
              ),
              const SizedBox(width: KoraSpacing.xs),
              Expanded(
                child: Text(
                  'NEXT STOP',
                  style: _kicker,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The ETA gives way to the kicker rather than pushing the
              // row past the card edge at a large text size.
              Flexible(
                child: Text(
                  '12 min',
                  style: KoraText.label.copyWith(
                    color: KoraMood.inkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: KoraSpacing.sm),
          // Kept to two short rows: the front card covers the rest of this
          // one, and the stop itself must stay readable above it.
          Text(
            'Capitol Hill',
            style: KoraText.title.copyWith(color: KoraMood.ink),
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
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        gradient: KoraMood.holographic,
        borderRadius: BorderRadius.circular(KoraRadius.card),
        border: Border.all(
          color: KoraMood.paperBorder,
          width: KoraGlass.borderWidth,
        ),
        boxShadow: KoraGlass.shadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: KoraSize.iconXl,
            height: KoraSize.iconXl,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KoraMood.paperGlass,
            ),
            child: const Icon(
              TablerIcons.route,
              size: KoraSize.iconSm,
              color: KoraMood.ink,
            ),
          ),
          const SizedBox(height: KoraSpacing.md),
          Text(
            'Live route',
            style: KoraText.title.copyWith(color: KoraMood.ink),
          ),
          Text(
            '3 stops · 18 min',
            style: KoraText.label.copyWith(color: KoraMood.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// An action-required card for one OS permission: "ALL SET" and a check
/// once [allowed], otherwise an allow button that asks the OS.
class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.title,
    required this.reason,
    required this.allowIcon,
    required this.allowLabel,
    required this.allowedLabel,
    required this.allowed,
    required this.onAllow,
  });

  final String title;

  /// Why the co-rider needs it, in a line or two.
  final String reason;
  final IconData allowIcon;
  final String allowLabel;
  final String allowedLabel;
  final bool allowed;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: _paperCard(front: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: KoraMotion.base,
                width: KoraSize.progressDot,
                height: KoraSize.progressDot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: allowed
                      ? KoraColors.success
                      : KoraColors.danger,
                ),
              ),
              const SizedBox(width: KoraSpacing.sm),
              Flexible(
                child: Text(
                  allowed ? 'ALL SET' : 'ACTION REQUIRED',
                  style: _kicker,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: KoraSpacing.sm),
          Text(
            title,
            style: KoraText.headline.copyWith(color: KoraMood.ink),
          ),
          const SizedBox(height: KoraSpacing.xs),
          Text(
            reason,
            style: KoraText.weight(
              KoraText.label,
              FontWeight.w400,
            ).copyWith(color: KoraMood.inkMuted),
          ),
          const SizedBox(height: KoraSpacing.md),
          AnimatedSwitcher(
            duration: KoraMotion.base,
            child: allowed
                // As tall as the button it replaces, so the stack holds
                // still when the OS answers.
                ? ConstrainedBox(
                    key: const ValueKey('allowed'),
                    constraints: const BoxConstraints(
                      minHeight: KoraSize.touchTarget,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          TablerIcons.circleCheck,
                          size: KoraSize.iconMd,
                          color: KoraMood.ink,
                        ),
                        const SizedBox(width: KoraSpacing.xs),
                        Flexible(
                          child: Text(
                            allowedLabel,
                            style: KoraText.label.copyWith(
                              color: KoraMood.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : _AllowButton(
                    key: const ValueKey('allow'),
                    icon: allowIcon,
                    label: allowLabel,
                    onTap: onAllow,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Compact dark pill on the white card. Still a full 48px touch target.
class _AllowButton extends StatelessWidget {
  const _AllowButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(KoraRadius.pill);
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: KoraMood.ink,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: KoraSize.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KoraSpacing.lg,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: KoraSize.iconSm,
                    color: KoraMood.paper,
                  ),
                  const SizedBox(width: KoraSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      style: KoraText.label.copyWith(
                        color: KoraMood.paper,
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
