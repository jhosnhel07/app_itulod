// Booking details, rider's view (web sql/047): the customer instead of the
// rider card, the full order with the cash to bring, and what you earn —
// while the customer keeps their own view.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;

import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/customer/data/customer_repository.dart';
import 'package:app_itulod/shared/models/booking_models.dart';
import 'package:app_itulod/shared/models/profile_model.dart';
import 'package:app_itulod/shared/providers/booking_extras_providers.dart';
import 'package:app_itulod/shared/screens/booking_details_sheet.dart';

class _NoAuthRepo implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  User? get currentUser => null;
  @override
  Session? get currentSession => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No network: every lookup the sheet makes on its own fails quietly.
class _NoRepo implements CustomerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthNotifier _as(String id, UserRole role) {
  // ignore: invalid_use_of_protected_member
  return AuthNotifier(_NoAuthRepo())..state = AppAuthState(
      status: AuthStatus.authenticated,
      profile: ProfileModel(id: id, fullName: 'Test', email: 't@example.com', role: role));
}

FoodDeliveryModel _food(String status, {String? rider}) => FoodDeliveryModel(
      id: 'f1',
      customerId: 'cust-1',
      riderId: rider,
      restaurantName: 'Saramsam Ylocano',
      pickupAddress: 'Rizal St, Laoag',
      deliveryAddress: 'Brgy. 1, Laoag City',
      instructions: 'Gate is blue',
      itemSubtotal: 450,
      deliveryFee: 50.6,
      estimatedFare: 500.6,
      paymentMethod: 'cash',
      paymentStatus: 'pending',
      status: status,
      createdAt: DateTime(2026, 10, 27, 9),
    );

const _items = [
  FoodOrderItem(id: 'i1', name: 'Bagnet', unitPrice: 150, quantity: 2, subtotal: 300),
  FoodOrderItem(id: 'i2', name: 'Pinakbet', unitPrice: 150, quantity: 1, subtotal: 150),
];

Future<void> _open(WidgetTester tester, FoodDeliveryModel b,
    {required AuthNotifier auth, RiderBookingView view = const (customer: null, earn: null)}) async {
  final view0 = tester.view;
  view0.physicalSize = const Size(400 * 3, 2400 * 3);
  view0.devicePixelRatio = 3;
  addTearDown(view0.resetPhysicalSize);
  addTearDown(view0.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith((ref) => auth),
      customerRepositoryProvider.overrideWithValue(_NoRepo()),
      foodOrderItemsProvider.overrideWith((ref, id) async => _items),
      riderBookingViewProvider.overrideWith((ref, key) async => view),
    ],
    child: MaterialApp(home: Scaffold(body: BookingDetailsSheet(booking: b))),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _has(String text) => find.textContaining(text, skipOffstage: false).evaluate().isNotEmpty;

void main() {
  const earnEstimate = {'fare': 500.6, 'commission': 7.59, 'payout': 493.01, 'tip': null, 'is_final': false};

  testWidgets('rider, accepted food order: customer, order, cash to bring, earnings', (tester) async {
    await _open(tester, _food('accepted', rider: 'rider-1'),
        auth: _as('rider-1', UserRole.rider),
        view: (
          customer: {'full_name': 'Maria Santos', 'avatar_url': null, 'phone': '09171234567', 'member_since': '2026-09-01T00:00:00Z', 'completed_bookings': 3},
          earn: earnEstimate,
        ));
    expect(_has('YOUR CUSTOMER'), isTrue);
    expect(_has('Maria Santos'), isTrue);
    expect(_has('3 completed bookings'), isTrue);
    expect(_has('09171234567'), isTrue);
    expect(find.text('Call', skipOffstage: false), findsOneWidget);
    expect(find.text('Message', skipOffstage: false), findsOneWidget);
    expect(_has('2 × Bagnet'), isTrue);
    expect(_has('1 × Pinakbet'), isTrue);
    expect(_has('Bring ₱450.00 cash to buy the food'), isTrue);
    expect(_has('You earn (estimate)'), isTrue);
    expect(_has('iTULOD commission'), isTrue);
    expect(_has('Collect ₱500.60 in cash'), isTrue);
    expect(tester.widget<Text>(find.byKey(const Key('details-hero-amount'), skipOffstage: false)).data, '₱493.01');
    // the customer-only parts are gone
    expect(_has('YOUR RIDER'), isFalse);
    expect(_has('Rider documents'), isFalse);
    expect(_has('Start the trip within 15 minutes'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rider, waiting request: items and earnings, customer hidden', (tester) async {
    await _open(tester, _food('pending'), auth: _as('rider-1', UserRole.rider), view: (customer: null, earn: earnEstimate));
    expect(_has("The customer's name and number show once you accept"), isTrue);
    expect(_has('2 × Bagnet'), isTrue);
    expect(_has('You earn (estimate)'), isTrue);
    expect(_has('Accept within the 15-minute window'), isTrue);
  });

  testWidgets('customer view stays the customer view', (tester) async {
    // finished, so no live tracking map (its timer outlives a test)
    await _open(tester, _food('completed', rider: 'rider-1'), auth: _as('cust-1', UserRole.customer));
    expect(_has('YOUR CUSTOMER'), isFalse);
    expect(_has('Your earnings'), isFalse);
    expect(_has('2 × Bagnet'), isTrue);
    expect(_has('Bring ₱450.00 cash'), isFalse);
  });
}
