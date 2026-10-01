import 'package:flutter_test/flutter_test.dart';

import 'package:app_itulod/core/utils/validators.dart';
import 'package:app_itulod/shared/models/booking_models.dart';

TransportBookingModel _booking({
  required String status,
  required DateTime createdAt,
  DateTime? acceptedAt,
  String? paymentMethod,
  String? paymentStatus,
}) {
  return TransportBookingModel(
    id: 'b1',
    customerId: 'c1',
    vehicleId: 'v1',
    pickupAddress: 'A',
    destinationAddress: 'B',
    status: status,
    createdAt: createdAt,
    acceptedAt: acceptedAt,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus,
  );
}

void main() {
  group('BookingBase.expiresAt (15-minute grace period)', () {
    test('a pending booking expires 15 minutes after it was created', () {
      final created = DateTime(2026, 1, 1, 10, 0);
      final b = _booking(status: 'pending', createdAt: created);
      expect(b.expiresAt, DateTime(2026, 1, 1, 10, 15));
    });

    test('an accepted booking expires 15 minutes after acceptance, not creation', () {
      final created = DateTime(2026, 1, 1, 10, 0);
      final accepted = DateTime(2026, 1, 1, 10, 5);
      final b = _booking(status: 'accepted', createdAt: created, acceptedAt: accepted);
      expect(b.expiresAt, DateTime(2026, 1, 1, 10, 20));
    });

    test('an accepted booking with no accepted_at yet has no expiry (race-safe)', () {
      final b = _booking(status: 'accepted', createdAt: DateTime(2026, 1, 1, 10));
      expect(b.expiresAt, isNull);
    });

    test('ongoing, completed, cancelled, expired and no_show never carry an expiry', () {
      for (final status in [
        'ongoing',
        'completed',
        'cancelled',
        'expired',
        'no_show',
      ]) {
        final b = _booking(
          status: status,
          createdAt: DateTime(2026, 1, 1, 10),
          acceptedAt: DateTime(2026, 1, 1, 10, 1),
        );
        expect(b.expiresAt, isNull, reason: 'status=$status');
      }
    });
  });

  group('BookingBase terminal / actionable state', () {
    test('completed, cancelled, expired and no_show are all terminal', () {
      for (final status in ['completed', 'cancelled', 'expired', 'no_show']) {
        final b = _booking(status: status, createdAt: DateTime(2026, 1, 1));
        expect(b.isTerminal, isTrue, reason: 'status=$status');
      }
    });

    test('pending, accepted and ongoing are not terminal', () {
      for (final status in ['pending', 'accepted', 'ongoing']) {
        final b = _booking(status: status, createdAt: DateTime(2026, 1, 1));
        expect(b.isTerminal, isFalse, reason: 'status=$status');
      }
    });

    test('an expired booking can never be cancelled', () {
      final b = _booking(status: 'expired', createdAt: DateTime(2026, 1, 1));
      expect(b.canCancel, isFalse);
    });

    test('an expired unpaid GCash booking never prompts payment again', () {
      final b = _booking(
        status: 'expired',
        createdAt: DateTime(2026, 1, 1),
        paymentMethod: 'gcash',
        paymentStatus: 'pending',
      );
      expect(b.needsPayment, isFalse);
    });

    test('isExpired / isNoShow read the right status', () {
      expect(_booking(status: 'expired', createdAt: DateTime(2026)).isExpired, isTrue);
      expect(_booking(status: 'no_show', createdAt: DateTime(2026)).isNoShow, isTrue);
      expect(_booking(status: 'completed', createdAt: DateTime(2026)).isExpired, isFalse);
    });
  });

  group('Validators.futureDateTime', () {
    test('accepts now and future times', () {
      expect(Validators.futureDateTime(DateTime.now()), isNull);
      expect(
        Validators.futureDateTime(DateTime.now().add(const Duration(hours: 1))),
        isNull,
      );
    });

    test('rejects a clearly past date/time with the exact required message', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(
        Validators.futureDateTime(past),
        'Please select a valid future date and time.',
      );
    });

    test('rejects null', () {
      expect(Validators.futureDateTime(null), isNotNull);
    });
  });
}
