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

  /// "Today, 8:42 AM" / "Yesterday, 3:10 PM" / "Tomorrow, 9:00 AM" /
  /// "Oct 12, 3:10 AM"; the year only when it isn't this year (web: formatDate).
  static String date(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final d = dateTime.toLocal();
    final now = DateTime.now();
    final time = DateFormat('h:mm a').format(d);
    final dayDiff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (dayDiff == 0) return 'Today, $time';
    if (dayDiff == 1) return 'Yesterday, $time';
    if (dayDiff == -1) return 'Tomorrow, $time';
    final day = DateFormat(d.year == now.year ? 'MMM d' : 'MMM d, yyyy').format(d);
    return '$day, $time';
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
