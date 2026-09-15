/// The policies a driver agrees to at sign-up.
enum LegalDocument {
  terms('Terms of Service', 'assets/legal/terms.md'),
  privacy('Privacy Policy', 'assets/legal/privacy.md');

  const LegalDocument(this.title, this.assetPath);

  final String title;
  final String assetPath;
}
