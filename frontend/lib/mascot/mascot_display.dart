import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rive/rive.dart' as rive;

import '../core/theme/tokens.dart';
import 'mascot_state.dart';

/// The co-rider's two orb materials (CLAUDE.md). Distinct moods — the
/// holographic bubble belongs to onboarding, chrome/mercury to the main app.
enum OrbMaterial { holographic, chrome }

/// Sets the [OrbMaterial] for every [MascotDisplay] below it. Without a
/// scope the main-app [OrbMaterial.chrome] orb is used.
class OrbMaterialScope extends InheritedWidget {
  const OrbMaterialScope({
    super.key,
    required this.material,
    required super.child,
  });

  final OrbMaterial material;

  static OrbMaterial of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OrbMaterialScope>()
          ?.material ??
      OrbMaterial.chrome;

  @override
  bool updateShouldNotify(OrbMaterialScope oldWidget) =>
      material != oldWidget.material;
}

/// The co-rider orb. Plays the authored Rive co-rider
/// (`assets/rive/corider.riv`) and falls back to a Flutter-drawn placeholder
/// while the file loads, or if it is missing or fails to load. Either way it
/// morphs smoothly between [AgentState]s.
class MascotDisplay extends StatefulWidget {
  const MascotDisplay({
    super.key,
    required this.state,
    this.size = VoiceOpsSize.orbHero,
    this.material,
  });

  final AgentState state;
  final double size;

  /// Overrides the surrounding [OrbMaterialScope].
  final OrbMaterial? material;

  @override
  State<MascotDisplay> createState() => _MascotDisplayState();
}

class _MascotDisplayState extends State<MascotDisplay> {
  _CoRiderRig? _rig;
  OrbMaterial? _rigMaterial; // material the rig was built for (or failed for)
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (_CoRiderFile.file == null) {
      _CoRiderFile.load().then((file) {
        if (file != null && mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _rig?.still = _reduceMotion;
  }

  @override
  void didUpdateWidget(MascotDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _rig?.show(widget.state);
  }

  /// The rig for [material], built once the .riv has loaded. Null means
  /// "draw the placeholder".
  _CoRiderRig? _rigFor(OrbMaterial material) {
    final file = _CoRiderFile.file;
    if (file == null || _rigMaterial == material) return _rig;
    // The RiveWidget still holds the old controller until this frame ends.
    final old = _rig;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _rigMaterial = material;
    return _rig = _CoRiderRig.tryCreate(
      file,
      material,
      widget.state,
      still: _reduceMotion,
    );
  }

  @override
  void dispose() {
    _rig?.dispose(); // children unmount first, so the RiveWidget is gone
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = widget.material ?? OrbMaterialScope.of(context);
    final rig = _rigFor(material);

    return Semantics(
      image: true,
      label: 'Co-rider',
      value: widget.state.label,
      child: SizedBox.square(
        dimension: widget.size,
        child: rig == null
            ? _PlaceholderOrb(state: widget.state, material: material)
            : rive.RiveWidget(
                key: ValueKey(material),
                controller: rig.controller,
                fit: rive.Fit.contain,
              ),
      ),
    );
  }
}

/// Loads the co-rider .riv once and shares it with every orb on screen.
abstract final class _CoRiderFile {
  static const _asset = 'assets/rive/corider.riv';

  static rive.File? file;
  static Future<rive.File?>? _loading;

  static Future<rive.File?> load() => _loading ??= _decode();

  static Future<rive.File?> _decode() async {
    try {
      return file = await rive.File.asset(
        _asset,
        riveFactory: rive.Factory.rive,
      );
    } catch (error) {
      // Missing asset, or no native Rive runtime (e.g. `flutter test`).
      debugPrint('Co-rider: $_asset unavailable ($error); using placeholder.');
      return null;
    }
  }
}

/// One live co-rider: an artboard, its `CoRider` state machine, and the view
/// model whose triggers switch moods.
///
/// The .riv (built from docs/voiceops-corider-orb-rive-spec-v2.md) has one
/// artboard per [OrbMaterial] and fires moods through `CoRider` view-model
/// trigger properties named after [AgentStateX.riveKey]. Firing a mood that
/// is already playing restarts it; one-shot moods settle back to idle on
/// their own.
class _CoRiderRig {
  _CoRiderRig._(this.controller, this._viewModel, bool still) {
    this.still = still;
  }

  static const _stateMachine = 'CoRider';

  final rive.RiveWidgetController controller;
  final rive.ViewModelInstance _viewModel;
  bool _still = false;

  /// Builds the rig, or returns null if the file doesn't match the contract
  /// above, so the caller can fall back to the placeholder.
  static _CoRiderRig? tryCreate(
    rive.File file,
    OrbMaterial material,
    AgentState state, {
    required bool still,
  }) {
    rive.RiveWidgetController? controller;
    try {
      controller = rive.RiveWidgetController(
        file,
        artboardSelector: rive.ArtboardSelector.byName(switch (material) {
          OrbMaterial.holographic => 'Holographic',
          OrbMaterial.chrome => 'Chrome',
        }),
        stateMachineSelector: rive.StateMachineSelector.byName(_stateMachine),
      );
      rive.ViewModelInstance viewModel;
      try {
        viewModel = controller.dataBind(rive.DataBind.auto());
      } on rive.RiveDataBindException {
        // Default instance not exported: a blank one carries the same triggers.
        viewModel = controller.dataBind(rive.DataBind.empty());
      }
      final rig = _CoRiderRig._(controller, viewModel, still);
      // The state machine enters idle on its own.
      if (state != AgentState.idle) rig.show(state);
      return rig;
    } catch (error) {
      debugPrint('Co-rider: $material rig failed ($error); using placeholder.');
      controller?.dispose();
      return null;
    }
  }

  /// Switches the co-rider to [state] with the authored 600ms morph.
  void show(AgentState state) {
    _viewModel.trigger(state.riveKey)?.trigger();
    if (_still) _settle();
  }

  /// With reduced motion the co-rider holds still: no breathing, no drifting
  /// motes, and mood changes jump straight to the settled pose.
  set still(bool value) {
    if (_still == value) return;
    _still = value;
    controller.active = !value;
    if (value) _settle();
    controller.scheduleRepaint();
  }

  /// Plays through the mood morph at once, so a paused orb rests on the new
  /// mood rather than the first frame of the blend.
  void _settle() => controller.stateMachine.advanceAndApply(
    VoiceOpsMotion.orbMorph.inMicroseconds / Duration.microsecondsPerSecond,
  );

  void dispose() {
    _viewModel.dispose();
    controller.dispose();
  }
}

/// The Flutter-drawn orb shown until (or instead of) the Rive co-rider.
class _PlaceholderOrb extends StatefulWidget {
  const _PlaceholderOrb({required this.state, required this.material});

  final AgentState state;
  final OrbMaterial material;

  @override
  State<_PlaceholderOrb> createState() => _PlaceholderOrbState();
}

class _PlaceholderOrbState extends State<_PlaceholderOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _OrbFrame _frame;
  late _OrbMood _from;
  late _OrbMood _to;
  double _morph = 1;
  Duration _last = Duration.zero;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _from = _to = _OrbMood.of(widget.state);
    _frame = _OrbFrame(_to);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _ensureTicking();
  }

  @override
  void didUpdateWidget(_PlaceholderOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _from = _frame.mood;
      _to = _OrbMood.of(widget.state);
      _morph = 0;
      _ensureTicking();
    }
  }

  void _ensureTicking() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;

    if (_morph < 1) {
      final span =
          VoiceOpsMotion.orbMorph.inMicroseconds /
          Duration.microsecondsPerSecond;
      _morph = math.min(1, _morph + dt / span);
      _frame.mood = _OrbMood.lerp(
        _from,
        _to,
        VoiceOpsMotion.emphasized.transform(_morph),
      );
    }

    if (_reduceMotion) {
      _frame.pulse = 0;
      if (_morph >= 1) _ticker.stop(); // nothing left to animate
    } else {
      final mood = _frame.mood;
      _frame.pulse = (_frame.pulse + dt * mood.pulseHz) % 1;
      _frame.spin = (_frame.spin + dt * mood.spin) % (2 * math.pi);
    }
    _frame.repaint();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _OrbPainter(frame: _frame, material: widget.material),
      ),
    );
  }
}

/// How the orb behaves in one [AgentState]. Every field lerps, so a state
/// change is a smooth morph rather than a cut.
@immutable
class _OrbMood {
  const _OrbMood({
    required this.tint,
    required this.tintStrength,
    required this.glow,
    required this.pulseHz,
    required this.pulseDepth,
    required this.spin,
  });

  /// State colour blended into the material palette.
  final Color tint;
  final double tintStrength;

  /// Halo opacity.
  final double glow;

  /// Breaths per second and how far each breath scales the orb.
  final double pulseHz;
  final double pulseDepth;

  /// Band rotation, radians per second.
  final double spin;

  // The co-rider never shows `live` lime — that colour means "mic is hot"
  // and belongs to the push-to-talk button alone.
  static _OrbMood of(AgentState state) => switch (state) {
    AgentState.idle => const _OrbMood(
      tint: VoiceOpsColors.primary,
      tintStrength: 0,
      glow: 0.30,
      pulseHz: 0.22,
      pulseDepth: 0.02,
      spin: 0.25,
    ),
    AgentState.thinking => const _OrbMood(
      tint: VoiceOpsColors.primaryLight,
      tintStrength: 0.35,
      glow: 0.55,
      pulseHz: 0.8,
      pulseDepth: 0.03,
      spin: 1.6,
    ),
    AgentState.calling => const _OrbMood(
      tint: VoiceOpsColors.success,
      tintStrength: 0.40,
      glow: 0.60,
      pulseHz: 1.2,
      pulseDepth: 0.05,
      spin: 0.6,
    ),
    AgentState.mapping => const _OrbMood(
      tint: VoiceOpsColors.blue,
      tintStrength: 0.40,
      glow: 0.55,
      pulseHz: 0.6,
      pulseDepth: 0.03,
      spin: 1.0,
    ),
    AgentState.taskWorking => const _OrbMood(
      tint: VoiceOpsColors.amber,
      tintStrength: 0.35,
      glow: 0.55,
      pulseHz: 1.0,
      pulseDepth: 0.035,
      spin: 1.2,
    ),
    AgentState.summarizing => const _OrbMood(
      tint: VoiceOpsColors.amber,
      tintStrength: 0.30,
      glow: 0.45,
      pulseHz: 0.4,
      pulseDepth: 0.025,
      spin: 0.5,
    ),
    AgentState.celebrating => const _OrbMood(
      tint: VoiceOpsColors.pink,
      tintStrength: 0.45,
      glow: 0.80,
      pulseHz: 1.6,
      pulseDepth: 0.07,
      spin: 1.8,
    ),
  };

  static _OrbMood lerp(_OrbMood a, _OrbMood b, double t) {
    double mix(double x, double y) => x + (y - x) * t;
    return _OrbMood(
      tint: Color.lerp(a.tint, b.tint, t)!,
      tintStrength: mix(a.tintStrength, b.tintStrength),
      glow: mix(a.glow, b.glow),
      pulseHz: mix(a.pulseHz, b.pulseHz),
      pulseDepth: mix(a.pulseDepth, b.pulseDepth),
      spin: mix(a.spin, b.spin),
    );
  }
}

/// Per-frame orb values. Repaints the painter directly so animation never
/// rebuilds widgets.
class _OrbFrame extends ChangeNotifier {
  _OrbFrame(this.mood);

  _OrbMood mood;
  double pulse = 0; // 0..1 phase of the current breath
  double spin = 0; // radians

  void repaint() => notifyListeners();
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.frame, required this.material})
    : super(repaint: frame);

  final _OrbFrame frame;
  final OrbMaterial material;

  bool get _holo => material == OrbMaterial.holographic;

  @override
  void paint(Canvas canvas, Size size) {
    final mood = frame.mood;
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final breath = math.sin(frame.pulse * 2 * math.pi);
    final r = maxR * 0.72 * (1 + mood.pulseDepth * breath);
    final body = Rect.fromCircle(center: center, radius: r);

    final palette = [
      for (final c
          in _holo ? VoiceOpsOrbColors.holographic : VoiceOpsOrbColors.chrome)
        Color.lerp(c, mood.tint, mood.tintStrength)!,
    ];

    // Halo — a radial fade, not a blur filter, to stay cheap per frame.
    final haloBase = Color.lerp(
      _holo ? VoiceOpsColors.primaryLight : VoiceOpsColors.primary,
      mood.tint,
      mood.tintStrength,
    )!;
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            haloBase.withValues(alpha: mood.glow),
            haloBase.withValues(alpha: 0),
          ],
          stops: [r / maxR * 0.85, 1],
        ).createShader(Rect.fromCircle(center: center, radius: maxR)),
    );

    // Body.
    final bodyPaint = Paint();
    if (_holo) {
      // Iridescent bands swirling around a centre that wanders with the
      // spin, so it reads as a thin film rather than a colour wheel.
      bodyPaint.shader = SweepGradient(
        center: Alignment(
          math.cos(frame.spin) * 0.4,
          math.sin(frame.spin) * 0.4,
        ),
        colors: palette,
        transform: GradientRotation(frame.spin),
      ).createShader(body);
    } else {
      // Chrome reflects a horizon: bright sky, dark band, lit ground. The
      // horizon sways gently with the spin phase.
      final sway = math.sin(frame.spin) * 0.12;
      bodyPaint.shader = LinearGradient(
        begin: Alignment(-0.3 + sway, -1),
        end: Alignment(0.3 - sway, 1),
        colors: palette,
        stops: const [0, 0.38, 0.52, 0.62, 0.85, 1],
      ).createShader(body);
    }
    canvas.drawCircle(center, r, bodyPaint);

    if (_holo) {
      // Counter-rotating translucent film for the soap-bubble shimmer.
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = SweepGradient(
            center: Alignment(
              -math.sin(frame.spin * 1.3) * 0.5,
              math.cos(frame.spin * 1.3) * 0.5,
            ),
            colors: [
              for (final c in palette.reversed) c.withValues(alpha: 0.45),
            ],
            transform: GradientRotation(-frame.spin * 1.7),
          ).createShader(body),
      );
      // See-through core: a bubble is clear in the middle, colour at the rim.
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              VoiceOpsColors.primaryDark.withValues(alpha: 0.45),
              VoiceOpsColors.primaryDark.withValues(alpha: 0),
            ],
            stops: const [0, 0.8],
          ).createShader(body),
      );
    }

    // Sphere depth: darken toward the lower-right edge.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [
            VoiceOpsOrbColors.shade.withValues(alpha: 0),
            VoiceOpsOrbColors.shade.withValues(alpha: _holo ? 0.35 : 0.65),
          ],
          stops: const [0.5, 1],
        ).createShader(body),
    );

    // Specular highlight.
    final spec = Rect.fromCenter(
      center: center + Offset(-r * 0.32, -r * 0.4),
      width: r * (_holo ? 0.75 : 0.55),
      height: r * (_holo ? 0.45 : 0.32),
    );
    canvas.drawOval(
      spec,
      Paint()
        ..shader = RadialGradient(
          colors: [
            VoiceOpsOrbColors.specular.withValues(alpha: _holo ? 0.6 : 0.9),
            VoiceOpsOrbColors.specular.withValues(alpha: 0),
          ],
        ).createShader(spec),
    );

    // Rim.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.025);
    if (_holo) {
      rim.shader = SweepGradient(
        colors: palette,
        transform: GradientRotation(-frame.spin),
      ).createShader(body);
    } else {
      rim.color = VoiceOpsOrbColors.specular.withValues(alpha: 0.3);
    }
    canvas.drawCircle(center, r, rim);
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      oldDelegate.material != material || oldDelegate.frame != frame;
}
