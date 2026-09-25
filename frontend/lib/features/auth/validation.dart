/// Client-side checks for the auth forms. Each validator returns an error
/// message, or null when the value is fine. Supabase Auth has the final say.
abstract final class AuthValidators {
  static const minPasswordLength = 8;

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// E.164: a plus, a non-zero country code digit, 8–15 digits in all.
  static final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

  static String? fullName(String? value) =>
      (value ?? '').trim().isEmpty ? 'Your full name is required' : null;

  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Your email is required';
    if (!_email.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  /// Sign-up password: long enough to be worth having.
  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'A password is required';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    return null;
  }

  /// Sign-in password: presence only, so older accounts still get in.
  static String? password(String? value) =>
      (value ?? '').isEmpty ? 'Your password is required' : null;

  static String? phone(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Your phone number is required';
    if (!_e164.hasMatch(normalizePhone(value!))) {
      return 'Include your country code, e.g. +1 512 555 0100';
    }
    return null;
  }

  /// Strips spaces, dashes, dots and brackets: `+1 (512) 555-0100` →
  /// `+15125550100`. Validate with [phone] first.
  static String normalizePhone(String value) =>
      value.trim().replaceAll(RegExp(r'[\s\-.()]'), '');
}
