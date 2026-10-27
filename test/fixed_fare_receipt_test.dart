// The total is fixed (web sql/050): no Set fare; a food order's receipt photo
// comes before Start Trip and shows in booking details; after Start Trip only
// proof of delivery → Mark Complete. Plus the count badges.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;

import 'package:app_itulod/core/constants/app_icons.dart';
import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/customer/data/customer_repository.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_requests_tab.dart' show riderActiveBookingsProvider;
import 'package:app_itulod/features/rider/presentation/widgets/rider_trip_tab.dart';
import 'package:app_itulod/shared/models/booking_models.dart';
import 'package:app_itulod/shared/models/profile_model.dart';
import 'package:app_itulod/shared/providers/booking_extras_providers.dart';
import 'package:app_itulod/shared/screens/booking_details_sheet.dart';
import 'package:app_itulod/shared/widgets/liquid_glass_nav_bar.dart';
import 'package:app_itulod/shared/widgets/service_tab_bar.dart';

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

const _receipt = 'https://example.com/receipts/r1.jpg';

FoodDeliveryModel _food(String status, {String? receipt, String? proof, double? finalFare = 500.6, String pay = 'cash', String payStatus = 'pending'}) =>
    FoodDeliveryModel(
      id: 'f1',
      customerId: 'cust-1',
      riderId: 'rider-1',
      restaurantName: 'Saramsam Ylocano',
      pickupAddress: 'Rizal St, Laoag',
      deliveryAddress: 'Brgy. 1, Laoag City',
      instructions: '',
      itemSubtotal: 450,
      deliveryFee: 50.6,
      estimatedFare: 500.6,
      finalFare: finalFare,
      receiptPhotoUrl: receipt,
      deliveryProofUrl: proof,
      paymentMethod: pay,
      paymentStatus: payStatus,
      status: status,
      createdAt: DateTime(2026, 10, 27, 9),
    );

const _items = [
  FoodOrderItem(id: 'i1', name: 'Bagnet', unitPrice: 150, quantity: 2, subtotal: 300),
  FoodOrderItem(id: 'i2', name: 'Pinakbet', unitPrice: 150, quantity: 1, subtotal: 150, isOutOfStock: true),
];

void _tallView(WidgetTester tester) {
  final view = tester.view;
  view.physicalSize = const Size(400 * 3, 2600 * 3);
  view.devicePixelRatio = 3;
  addTearDown(view.resetPhysicalSize);
  addTearDown(view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _trip(WidgetTester tester, BookingBase b) async {
  _tallView(tester);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith((ref) => _as('rider-1', UserRole.rider)),
      riderActiveBookingsProvider.overrideWith((ref) async => [b]),
      foodOrderItemsProvider.overrideWith((ref, id) async => _items),
    ],
    child: const MaterialApp(home: Scaffold(body: RiderTripTab())),
  ));
  await _pump(tester);
  // the route map isn't what this test is about — fold it away
  final hide = find.text('Hide map');
  if (hide.evaluate().isNotEmpty) {
    await tester.tap(hide);
    await _pump(tester);
  }
}

/// The trip card's map and photos start timers; let them run out.
Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

bool _has(String text) => find.textContaining(text, skipOffstage: false).evaluate().isNotEmpty;

VoidCallback? _onPressed(WidgetTester tester, String label) {
  final button = find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  return tester.widget<ButtonStyleButton>(button.first).onPressed;
}

void main() {
  group('rider trip card', () {
    testWidgets('accepted food order: receipt first, Start Trip locked, no Set fare', (tester) async {
      await _trip(tester, _food('accepted'));
      expect(_has('Set fare'), isFalse);
      expect(_has('Final fare'), isFalse);
      expect(find.text('Navigate to pickup'), findsOneWidget);
      expect(find.text('Upload / take receipt photo'), findsOneWidget);
      expect(_onPressed(tester, 'Start Trip'), isNull);
      expect(_has('take a photo of the receipt to start the trip'), isTrue);
      // out of stock comes off: bring ₱300 for the food, not ₱450
      expect(_has('Out of stock'), isTrue);
      expect(_has('₱300.00'), isTrue);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('receipt saved: Start Trip opens', (tester) async {
      await _trip(tester, _food('accepted', receipt: _receipt));
      expect(find.text('Receipt saved'), findsOneWidget);
      expect(find.text('Upload / take receipt photo'), findsNothing);
      expect(_onPressed(tester, 'Start Trip'), isNotNull);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('after Start Trip: no Navigate, just proof → Mark Complete', (tester) async {
      await _trip(tester, _food('ongoing', receipt: _receipt));
      expect(find.textContaining('Navigate'), findsNothing);
      expect(find.text('Upload / take receipt photo'), findsNothing);
      expect(find.text('Take proof of delivery'), findsOneWidget);
      expect(_onPressed(tester, 'Mark Complete'), isNull);
      // out of stock can only be marked at the restaurant, before the trip
      expect(find.byTooltip('Mark out of stock'), findsNothing);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('proof saved: Mark Complete opens', (tester) async {
      await _trip(tester, _food('ongoing', receipt: _receipt, proof: 'https://example.com/p.jpg'));
      expect(find.text('Proof of delivery saved'), findsOneWidget);
      expect(_onPressed(tester, 'Mark Complete'), isNotNull);
      await _done(tester);
    });

    testWidgets('a parcel starts straight away — no receipt step', (tester) async {
      await _trip(
        tester,
        ParcelDeliveryModel(
          id: 'p1',
          customerId: 'cust-1',
          riderId: 'rider-1',
          senderName: 'Ana',
          senderPhone: '09170000001',
          senderAddress: 'Laoag',
          receiverName: 'Ben',
          receiverPhone: '09170000002',
          receiverAddress: 'Batac',
          parcelSize: 'Small',
          parcelDescription: '',
          instructions: '',
          estimatedFare: 120,
          finalFare: 120,
          paymentMethod: 'cash',
          status: 'accepted',
          createdAt: DateTime(2026, 10, 27, 9),
        ),
      );
      expect(find.text('Upload / take receipt photo'), findsNothing);
      expect(_has('Set fare'), isFalse);
      expect(_onPressed(tester, 'Start Trip'), isNotNull);
      await _done(tester);
    });
  });

  group('booking details', () {
    Future<void> open(WidgetTester tester, FoodDeliveryModel b, AuthNotifier auth) async {
      _tallView(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith((ref) => auth),
          customerRepositoryProvider.overrideWithValue(_NoRepo()),
          foodOrderItemsProvider.overrideWith((ref, id) async => _items),
          riderBookingViewProvider.overrideWith((ref, key) async => (customer: null, earn: null)),
        ],
        child: MaterialApp(home: Scaffold(body: BookingDetailsSheet(booking: b))),
      ));
      await _pump(tester);
    }

    testWidgets('customer: Total, out of stock refunded, and the receipt', (tester) async {
      await open(tester, _food('completed', receipt: _receipt, finalFare: 350.6, pay: 'gcash', payStatus: 'paid'),
          _as('cust-1', UserRole.customer));
      expect(_has('Final fare'), isFalse);
      expect(_has('Estimated fare'), isFalse);
      expect(find.text('Total', skipOffstage: false), findsOneWidget);
      expect(_has('₱350.60'), isTrue);
      expect(_has('− ₱150.00 · refunded to your iTULOD wallet'), isTrue);
      expect(find.byKey(const Key('details-receipt'), skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rider sees the receipt too; none before it is taken', (tester) async {
      await open(tester, _food('ongoing', receipt: _receipt), _as('rider-1', UserRole.rider));
      expect(find.byKey(const Key('details-receipt'), skipOffstage: false), findsOneWidget);
      await open(tester, _food('accepted'), _as('rider-1', UserRole.rider));
      expect(find.byKey(const Key('details-receipt'), skipOffstage: false), findsNothing);
      expect(_has('Then take a photo of the receipt to start the trip'), isTrue);
    });
  });

  group('count badges', () {
    testWidgets('bottom bar shows a number, none at 0', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LiquidGlassNavBar(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              LiquidNavItem(icon: AppIcons.home, activeIcon: AppIcons.homeActive, label: 'Home'),
              LiquidNavItem(icon: AppIcons.requests, activeIcon: AppIcons.requests, label: 'Requests', badge: 1),
              LiquidNavItem(icon: AppIcons.trip, activeIcon: AppIcons.trip, label: 'Trip', badge: 120),
            ],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('nav-badge-Requests')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.byKey(const Key('nav-badge-Home')), findsNothing);
    });

    testWidgets('service switcher counts', (tester) async {
      final controller = TabController(length: 4, vsync: const TestVSync());
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ServiceTabBar(controller: controller, counts: const [0, 2, 0, 1])),
      ));
      expect(find.byKey(const Key('service-count-Food')), findsOneWidget);
      expect(find.byKey(const Key('service-count-Hauling')), findsOneWidget);
      expect(find.byKey(const Key('service-count-Rides')), findsNothing);
      expect(find.text('Rides'), findsOneWidget);
    });

    test('what counts on the customer\'s Bookings tab', () {
      final now = DateTime(2026, 10, 27, 12);
      BookingBase b(String status, {int? rating, String pay = 'cash', String payStatus = 'paid', DateTime? updated}) =>
          TransportBookingModel(
            id: 't',
            customerId: 'c',
            pickupAddress: 'A',
            destinationAddress: 'B',
            status: status,
            estimatedFare: 100,
            rating: rating,
            paymentMethod: pay,
            paymentStatus: payStatus,
            createdAt: DateTime(2026, 10, 20),
            updatedAt: updated,
          );
      expect(b('pending').needsCustomer(now), isTrue);
      expect(b('ongoing').needsCustomer(now), isTrue);
      expect(b('completed', updated: DateTime(2026, 10, 26)).needsCustomer(now), isTrue, reason: 'to rate');
      expect(b('completed', rating: 5, updated: DateTime(2026, 10, 26)).needsCustomer(now), isFalse);
      expect(b('completed', updated: DateTime(2026, 10, 20)).needsCustomer(now), isFalse, reason: 'too old to nag');
      expect(b('completed', rating: 5, pay: 'gcash', payStatus: 'pending').needsCustomer(now), isTrue, reason: 'to pay');
      expect(b('cancelled').needsCustomer(now), isFalse);
    });
  });
}
