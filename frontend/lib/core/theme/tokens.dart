import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// VoiceOps design tokens — the single source for every colour, spacing,
/// radius, size, duration and text style. Widgets reference these; they
/// never hardcode a value. Authority: CLAUDE.md § Design System and
/// `.firstmate/rules/frontend.md`. Dark-mode-first.
class VoiceOpsColors {
  VoiceOpsColors._();

  // ── Surfaces (dark, lowest → highest elevation) ──────────────────────
  static const canvas = Color(0xFF07060B);
  static const raised = Color(0xFF0E0B18);
  static const elevated = Color(0xFF151126);
  static const overlay = Color(0xFF1D1834);

  // ── Brand violet ─────────────────────────────────────────────────────
  static const primary = Color(0xFF8B5CF6);
  static const primaryLight = Color(0xFFC4B5FD);
  static const primaryDark = Color(0xFF4C1D95);
  static const primaryTint = Color(0x298B5CF6); // primary @ 16%
  static const primaryGlow = Color(0x598B5CF6); // primary @ 35%

  // ── Live (mic-hot) ───────────────────────────────────────────────────
  // Reserved for the mic-hot / recording state ONLY; not a general accent.
  // This is a safety property: a driver must be able to tell at a glance
  // that the mic is live, so nothing else in the app may be lime.
  static const live = Color(0xFFC8F250);
  static const liveGlow = Color(0x66C8F250); // live @ 40%, recording halo only
  static const onLive = canvas;

  // ── Secondary accents (card use only, sparing) ───────────────────────
  static const pink = Color(0xFFF9A8D4);
  static const blue = Color(0xFF7DD3FC);
  static const amber = Color(0xFFFBBF24);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFF87171); // error states

  // ── Text / ink ───────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF4F1FF);
  static const textMuted = Color(0xFFA7A1C4);
  static const textFaint = Color(0xFF7C7797); // ≥4.5:1 on canvas
  static const onPrimary = Color(0xFFFFFFFF);
  static const onAccent = canvas; // dark ink on pastel accents

  // ── Lines ────────────────────────────────────────────────────────────
  static const divider = Color(0x14FFFFFF); // white @ 8%
  static const scrim = Color(0xB307060B); // canvas @ 70%
}

/// Restrained glass. Readability and 60fps on a mid-range Android come
/// before the effect: one capped blur, near-transparent fill, hairline
/// border. Prefer an unblurred glass fill for repeated items (lists, chip
/// grids); reserve the backdrop blur for a few large surfaces.
class VoiceOpsGlass {
  VoiceOpsGlass._();

  /// Capped for perf + readability — restrained glass. Never exceed this.
  static const blur = 12.0;

  static const fillOpacity = 0.05;
  static const fill = Color(0x0DFFFFFF); // white @ 5%
  static const border = Color(0x1FFFFFFF); // white @ 12%
  static const borderWidth = 1.0;

  /// Soft violet shadow under glass surfaces.
  static const shadow = [
    BoxShadow(
      color: Color(0x2E8B5CF6), // primary @ 18%
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

/// Co-rider orb palettes — CLAUDE.md's two distinct orb materials.
/// Holographic bubble for onboarding, chrome/mercury for the main app.
class VoiceOpsOrbColors {
  VoiceOpsOrbColors._();

  static const holographic = [
    Color(0xFFC4B5FD),
    Color(0xFFF9A8D4),
    Color(0xFF7DD3FC),
    Color(0xFFA7F3D0),
    Color(0xFFC4B5FD),
  ];

  static const chrome = [
    Color(0xFFEDEBF5),
    Color(0xFF8E8AA6),
    Color(0xFF2B2740),
    Color(0xFFD3CFE6),
    Color(0xFF5E5A78),
    Color(0xFFEDEBF5),
  ];

  static const specular = Color(0xFFFFFFFF);
  static const shade = Color(0xA607060B); // canvas @ 65%, sphere depth
}

/// Onboarding mood backgrounds and surfaces (PRD v4.0 §4.7): dark navy for
/// Hook, a lavender gradient for Power, holographic editorial for the
/// splash. Onboarding only; the main app stays on [VoiceOpsColors.canvas].
class VoiceOpsMood {
  VoiceOpsMood._();

  // Each mood is three top → bottom stops so moods lerp stop-for-stop.
  static const editorial = [
    Color(0x0007060B), // clear: the splash shows the root glow background
    Color(0x0007060B),
    Color(0x0007060B),
  ];
  static const navy = [Color(0xFF151C44), Color(0xFF0B1030), Color(0xFF060919)];
  static const lavender = [
    Color(0xFFEEE8FF),
    Color(0xFFD5C9FF),
    Color(0xFFB9A5F6),
  ];

  /// Dark ink for text and icons on the lavender mood and pastel surfaces.
  static const ink = Color(0xFF1B1538);
  static const inkMuted = Color(0xFF4F4677);

  /// White "paper": the splash CTA and the Power screen's front card.
  static const paper = Color(0xFFFFFFFF);
  static const paperGlass = Color(0xB3FFFFFF); // paper @ 70%, cards behind
  static const paperBorder = Color(0x99FFFFFF); // paper @ 60%, hairline

  /// Holographic film for pills and teaser/CTA cards. Built from the
  /// holographic orb palette so the surfaces and the orb read as one material.
  static const holographic = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFC4B5FD),
      Color(0xFFF9A8D4),
      Color(0xFF7DD3FC),
      Color(0xFFA7F3D0),
    ],
  );

  /// Iridescent light streaks behind the splash's editorial type:
  /// (colour, peak alpha, diameter, alignment).
  static const splashSheen = [
    (
      color: Color(0xFF7DD3FC),
      alpha: 0.22,
      size: 360.0,
      at: Alignment(-1.2, -0.2),
    ),
    (
      color: Color(0xFFF9A8D4),
      alpha: 0.16,
      size: 320.0,
      at: Alignment(1.1, 0.35),
    ),
    (
      color: Color(0xFFA7F3D0),
      alpha: 0.10,
      size: 260.0,
      at: Alignment(-0.6, 0.95),
    ),
  ];
}

class VoiceOpsSpacing {
  VoiceOpsSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Horizontal screen gutter.
  static const gutter = 22.0;
}

class VoiceOpsRadius {
  VoiceOpsRadius._();
  static const control = 14.0;
  static const card = 20.0;
  static const sheet = 28.0;

  /// Pills and the push-to-talk button.
  static const pill = 999.0;
}

class VoiceOpsSize {
  VoiceOpsSize._();

  static const iconSm = 16.0;
  static const iconMd = 20.0;
  static const iconLg = 24.0;
  static const iconXl = 32.0;

  /// Minimum touch target for any tappable control.
  static const touchTarget = 48.0;

  /// Height of buttons and single-line controls.
  static const control = 52.0;

  /// Push-to-talk diameter. Never below [pushToTalkMin] (frontend rules).
  static const pushToTalk = 88.0;
  static const pushToTalkMin = 80.0;

  /// Co-rider orb sizes. [orbOnboarding] is the Hook screen's waking orb;
  /// the welcome screen after it settles back to the smaller [orbHero].
  static const orbOnboarding = 220.0;
  static const orbHero = 150.0;
  static const orbBubble = 60.0;
  static const orbBubbleSmall = 40.0;

  /// Driver avatar in headers.
  static const avatar = 48.0;

  /// Onboarding progress dots; the current step stretches to a pill.
  static const progressDot = 8.0;
  static const progressDotActive = 24.0;
}

/// The Map tab: route line, pins, the driver's position dot and camera.
class VoiceOpsMap {
  VoiceOpsMap._();

  /// Route polyline stroke, drawn over a darker casing.
  static const routeWidth = 6.0;
  static const routeCasingWidth = 2.0;

  /// Numbered stop pins; the stop being navigated to is larger.
  static const stopPin = 34.0;
  static const stopPinActive = 44.0;

  /// The driver's live position: solid dot inside a soft halo.
  static const positionDot = 18.0;
  static const positionHalo = 44.0;

  /// Camera: zoom when following the driver, the closest a route fit may go,
  /// and the view before the first location fix.
  static const followZoom = 15.5;
  static const maxFitZoom = 16.0;
  static const initialZoom = 12.0;

  /// Space kept clear around a fitted route, beyond the card and nav.
  static const fitPadding = 48.0;

  /// A route fit includes the driver's position only within this distance
  /// of the stop.
  static const maxFitDriverMetres = 50000.0;
}

class VoiceOpsMotion {
  VoiceOpsMotion._();
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);

  /// Co-rider orb morph between agent states.
  static const orbMorph = Duration(milliseconds: 600);

  /// One slow in-or-out breath of the resting co-rider (onboarding Hook).
  static const breath = Duration(milliseconds: 4200);

  /// Entrance of the onboarding Power screen's card stack.
  static const stagger = Duration(milliseconds: 900);

  /// How long a snackbar notice stays up: long enough to read two lines.
  static const notice = Duration(seconds: 8);

  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubic;
}

/// Type scale. Plus Jakarta Sans substitutes for Circular Std / Sofia Pro
/// (proprietary) per CLAUDE.md — if licensed font files are supplied later,
/// swap them in here only.
class VoiceOpsText {
  VoiceOpsText._();

  /// Giant, light editorial type — the onboarding splash headline only.
  static final editorial = GoogleFonts.plusJakartaSans(
    fontSize: 50,
    fontWeight: FontWeight.w300,
    height: 1.12,
    letterSpacing: -1.6,
    color: VoiceOpsColors.textPrimary,
  );

  static final display = GoogleFonts.plusJakartaSans(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -1.2,
    color: VoiceOpsColors.textPrimary,
  );

  /// [display] on short phones, where the full size would push a screen's
  /// call to action below the fold.
  static final displayCompact = display.copyWith(
    fontSize: 30,
    letterSpacing: -0.9,
  );

  static final headline = GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
    color: VoiceOpsColors.textPrimary,
  );

  static final title = GoogleFonts.plusJakartaSans(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: VoiceOpsColors.textPrimary,
  );

  static final body = GoogleFonts.plusJakartaSans(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: VoiceOpsColors.textPrimary,
  );

  static final bodyMuted = body.copyWith(color: VoiceOpsColors.textMuted);

  static final label = GoogleFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.1,
    color: VoiceOpsColors.textPrimary,
  );

  /// Small uppercase status text (e.g. the co-rider state pill).
  static final caption = GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.8,
    color: VoiceOpsColors.textMuted,
  );

  /// [style] at another [weight]. google_fonts registers one font family per
  /// weight, so `copyWith(fontWeight: …)` alone keeps rendering the original
  /// weight; change weights through this instead.
  static TextStyle weight(TextStyle style, FontWeight weight) =>
      GoogleFonts.plusJakartaSans(
        textStyle: style.copyWith(fontWeight: weight),
      );

  /// Stats, ETAs, counts — tabular figures so digits don't jitter.
  static final numeric = GoogleFonts.plusJakartaSans(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: VoiceOpsColors.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData buildVoiceOpsTheme() {
  // `live` is deliberately absent from the ColorScheme so no Material
  // component can pick it up as an accent.
  final colorScheme = ColorScheme.fromSeed(
    seedColor: VoiceOpsColors.primary,
    brightness: Brightness.dark,
    primary: VoiceOpsColors.primary,
    onPrimary: VoiceOpsColors.onPrimary,
    surface: VoiceOpsColors.raised,
    onSurface: VoiceOpsColors.textPrimary,
    error: VoiceOpsColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: VoiceOpsColors.canvas,
    canvasColor: VoiceOpsColors.canvas,
    dividerColor: VoiceOpsColors.divider,
    iconTheme: const IconThemeData(
      color: VoiceOpsColors.textPrimary,
      size: VoiceOpsSize.iconMd,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: VoiceOpsColors.textPrimary,
      displayColor: VoiceOpsColors.textPrimary,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: VoiceOpsColors.primaryLight,
      selectionColor: VoiceOpsColors.primaryGlow,
      selectionHandleColor: VoiceOpsColors.primary,
    ),
  );
}
