import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static String currency(num? amount) {
    if (amount == null) return '₱0.00';
    return _currencyFormatter.format(amount);
  }

  static String date(DateTime? dateTime) {
    if (dateTime == null) return '—';
    return DateFormat('MMM d, yyyy • h:mm a').format(dateTime.toLocal());
  }

  static String dateOnly(DateTime? dateTime) {
    if (dateTime == null) return '—';
    return DateFormat('MMM d, yyyy').format(dateTime.toLocal());
  }

  /// Time only, in the device's local timezone — e.g. "10:15 AM". Used for
  /// showing a booking's auto-expiration cutoff.
  static String timeOnly(DateTime? dateTime) {
    if (dateTime == null) return '—';
    return DateFormat('h:mm a').format(dateTime.toLocal());
  }

  static String distance(num? distanceKm) {
    if (distanceKm == null) return '—';
    final value = distanceKm is double
        ? distanceKm.toStringAsFixed(1)
        : distanceKm.toString();
    return '$value km';
  }
}
