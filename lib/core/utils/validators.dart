class Validators {
  Validators._();

  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Sign-up email: Gmail only, the same rule as the web's GMAIL_RE.
  static String? gmail(String? value) {
    final basic = email(value);
    if (basic != null) return basic;
    if (!RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false).hasMatch(value!.trim())) {
      return 'Only Gmail addresses (name@gmail.com) are accepted';
    }
    return null;
  }

  /// Digits only, at most 11 — what gets saved (web: normalizePhoneMobile).
  static String normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length > 11 ? digits.substring(0, 11) : digits;
  }

  /// A PH mobile number, 09XX XXX XXXX (web: isValidPhoneMobile).
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(normalizePhone(value))) {
      return 'Enter a valid mobile number (09XX XXX XXXX)';
    }
    return null;
  }

  /// The special characters Supabase Auth counts (same list as the web's
  /// PASSWORD_SYMBOLS in js/utils.js).
  static const String passwordSymbols = r'''!@#$%^&*()_+-=[]{};'\:"|<>?,./`~''';

  /// The password rule on sign-up, Profile → Change password and the reset
  /// page — on the web and the app, and enforced by Supabase Auth too.
  static final List<({String label, bool Function(String) test})> passwordRules = [
    (label: 'At least 8 characters', test: (p) => p.length >= 8),
    (label: '1 uppercase letter (A–Z)', test: (p) => RegExp('[A-Z]').hasMatch(p)),
    (label: '1 lowercase letter (a–z)', test: (p) => RegExp('[a-z]').hasMatch(p)),
    (label: '1 number (0–9)', test: (p) => RegExp('[0-9]').hasMatch(p)),
    (label: '1 special character (! @ # \$ …)', test: (p) => p.split('').any(passwordSymbols.contains)),
  ];

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    final missing = passwordRules.where((r) => !r.test(value)).toList();
    if (missing.isEmpty) return null;
    final names = missing.map((r) => r.label.replaceAll(RegExp(r' \(.*\)$'), '').toLowerCase());
    return 'Your password needs: ${names.join(', ')}';
  }

  static String? confirmPassword(String? value, String originalPassword) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != originalPassword) {
      return 'Passwords do not match';
    }
    return null;
  }

  /// Rejects a past date/time. Every booking this app creates is stamped
  /// server-side with `now()` at insert, so it can never itself be in the
  /// past — this exists for any UI that lets someone pick a date/time (e.g.
  /// a future "schedule for later" booking flow) so it can enforce the same
  /// rule client-side before it ever reaches the server.
  static String? futureDateTime(DateTime? value) {
    if (value == null) return 'Please select a valid future date and time.';
    // A minute of slack: the moment the user taps "now" shouldn't itself
    // read as "past" by the time the check runs.
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    if (value.isBefore(cutoff)) {
      return 'Please select a valid future date and time.';
    }
    return null;
  }
}
