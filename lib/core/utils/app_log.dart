import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Minimal logging seam. Everything that used to be swallowed by a bare
/// `catch (_) {}` should route through here so failures are at least visible
/// in the console — and so there is a single place to wire in Sentry / a
/// crash reporter later.
class AppLog {
  AppLog._();

  /// Optional sink for a crash reporter. Set once at startup, e.g.
  /// `AppLog.onError = Sentry.captureException;`
  static void Function(Object error, StackTrace? stack, {String? context})?
      onError;

  static void debug(String message) {
    if (kDebugMode) developer.log(message, name: 'iTULOD');
  }

  /// A non-fatal failure that was handled/recovered but should not vanish.
  static void warn(String context, Object error, [StackTrace? stack]) {
    developer.log(
      context,
      name: 'iTULOD',
      level: 900, // WARNING
      error: error,
      stackTrace: stack,
    );
    onError?.call(error, stack, context: context);
  }
}
