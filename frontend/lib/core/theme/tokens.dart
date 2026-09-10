import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — matches VoiceOps SDD v2.0 §8.
class VoiceOpsColors {
  VoiceOpsColors._();

  static const primary = Color(0xFF7C3AED);
  static const primaryLight = Color(0xFFA78BFA);
  static const primaryDark = Color(0xFF4C1D95);

  static const grad1 = Color(0xFFC084FC); // idle
  static const grad2 = Color(0xFF818CF8); // idle
  static const grad3 = Color(0xFFF472B6); // creating/celebrating
  static const grad4 = Color(0xFF34D399); // task done
  static const grad5 = Color(0xFF38BDF8); // translating
  static const gradAmber = Color(0xFFFBBF24); // summarizing/ideas

  static const orbViolet = Color(0xFFC4B5FD);
  static const orbPink = Color(0xFFF9A8D4);
  static const orbBlue = Color(0xFFBAE6FF);
  static const orbLilac = Color(0xFFF0D2FF);

  static const glassWhite = Color(0x62FFFFFF);
  static const glassWhiteStrong = Color(0xE0FFFFFF);
  static const glassBorder = Color(0xBFFFFFFF);

  static const textPrimary = Color(0xFF3B0764);
  static const textMuted = Color(0xFF7C3AED);
  static const textFaint = Color(0xFFA78BFA);

  static const success = Color(0xFF059669);
  static const warning = Color(0xFFF59E0B);
}

class VoiceOpsSpacing {
  VoiceOpsSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class VoiceOpsRadius {
  VoiceOpsRadius._();
  static const sm = 14.0;
  static const md = 18.0;
  static const lg = 28.0;
  static const card = 20.0;
  static const pill = 54.0;
}

class VoiceOpsText {
  VoiceOpsText._();

  static TextStyle get greetingSmall => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: VoiceOpsColors.textMuted,
  );

  static TextStyle get greetingLarge => GoogleFonts.inter(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: VoiceOpsColors.textPrimary,
  );

  static TextStyle get chipLabel => GoogleFonts.inter(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: VoiceOpsColors.textPrimary,
  );

  static TextStyle get inputHint => GoogleFonts.inter(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: VoiceOpsColors.textFaint,
  );

  static TextStyle get mascotLabel => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: VoiceOpsColors.textMuted,
    letterSpacing: 0.4,
  );
}

ThemeData buildVoiceOpsTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: GoogleFonts.inter().fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: VoiceOpsColors.primary,
      brightness: Brightness.light,
    ),
  );
}
