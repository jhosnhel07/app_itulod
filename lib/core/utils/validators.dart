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

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleanPhone = value.replaceAll(RegExp(r'[\s-]'), '');
    if (cleanPhone.length < 10 || cleanPhone.length > 13) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters long';
    }
    return null;
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
