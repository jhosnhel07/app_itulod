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

  static String distance(num? distanceKm) {
    if (distanceKm == null) return '—';
    final value = distanceKm is double
        ? distanceKm.toStringAsFixed(1)
        : distanceKm.toString();
    return '$value km';
  }
}
