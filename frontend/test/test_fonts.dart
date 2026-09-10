import 'package:google_fonts/google_fonts.dart';

/// Tests have no network; stop google_fonts from trying to download
/// Plus Jakarta Sans (text falls back to the test font).
void disableGoogleFontsFetching() {
  GoogleFonts.config.allowRuntimeFetching = false;
}
