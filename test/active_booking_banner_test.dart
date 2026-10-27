// Booking screens: the banner for a booking you still have going, and the
// "Book another?" question before a second booking of the same service
// (web: customer.js renderBookActive / okToBookAgain).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;

import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/customer/data/customer_repository.dart';
import 'package:app_itulod/features/customer/presentation/widgets/active_booking_banner.dart';
import 'package:app_itulod/features/customer/presentation/widgets/customer_home_tab.dart' show customerHomeSummaryProvider;
import 'package:app_itulod/shared/models/booking_models.dart';
import 'package:app_itulod/shared/models/profile_model.dart';

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

AuthNotifier _signedIn() {
  // ignore: invalid_use_of_protected_member
  return AuthNotifier(_NoAuthRepo())..state = const AppAuthState(
      status: AuthStatus.authenticated,
      profile: ProfileModel(id: 'me', fullName: 'Maria Santos', email: 'maria@example.com'));
}

/// Answers findActiveBooking with [active] for [kind] only; no network.
class _FakeRepo implements CustomerRepository {
  final BookingKind kind;
  final BookingBase? active;
  _FakeRepo(this.kind, this.active);
  @override
  Future<BookingBase?> findActiveBooking(String customerId, BookingKind k) async => k == kind ? active : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TransportBookingModel _ride(String status, {String? rider}) => TransportBookingModel(
      id: 'r1',
      customerId: 'me',
      riderId: rider,
      pickupAddress: 'Laoag City Hall',
      destinationAddress: 'Batac Public Market',
      status: status,
      estimatedFare: 178,
      createdAt: DateTime(2026, 10, 27, 9),
    );

Widget _app(Widget child, {List<BookingBase> active = const [], CustomerRepository? repo}) => ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _signedIn()),
        customerHomeSummaryProvider.overrideWith((ref) async => CustomerHomeSummary(activeBookings: active)),
        if (repo != null) customerRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child))),
    );

void main() {
  testWidgets('no booking going: no banner', (tester) async {
    await tester.pumpWidget(_app(const ActiveBookingBanner()));
    await tester.pump();
    expect(find.textContaining('You have a'), findsNothing);
  });

  testWidgets('a waiting ride: banner with View and Cancel, no Chat yet', (tester) async {
    await tester.pumpWidget(_app(const ActiveBookingBanner(), active: [_ride('pending')]));
    await tester.pump();
    expect(find.text('You have a ride waiting for a rider'), findsOneWidget);
    expect(find.textContaining('Laoag City Hall → Batac Public Market'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
  });

  testWidgets('a trip in progress: Chat, no Cancel; +1 more', (tester) async {
    await tester.pumpWidget(_app(const ActiveBookingBanner(),
        active: [_ride('ongoing', rider: 'rider-1'), _ride('pending')]));
    await tester.pump();
    expect(find.text('You have a ride in progress'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('+1 more in My Bookings'), findsOneWidget);
  });

  Future<bool?> ask(WidgetTester tester, BookingKind kind, BookingBase? existing, {String? tap}) async {
    bool? result;
    await tester.pumpWidget(_app(
      Consumer(builder: (context, ref, _) => TextButton(
            onPressed: () async => result = await okToBookAgain(context, ref, kind),
            child: const Text('Book'),
          )),
      repo: _FakeRepo(BookingKind.transport, existing),
    ));
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    if (tap != null) {
      await tester.tap(find.text(tap));
      await tester.pump();
    }
    return result;
  }

  testWidgets('same service while one is going: asks; Book anyway goes ahead', (tester) async {
    final r = await ask(tester, BookingKind.transport, _ride('pending'), tap: 'Book anyway');
    expect(r, isTrue);
  });

  testWidgets('the question names the booking it found', (tester) async {
    await ask(tester, BookingKind.transport, _ride('accepted', rider: 'rider-1'));
    expect(find.text('Book another?'), findsOneWidget);
    expect(find.textContaining('You already have a ride with a rider on the way'), findsOneWidget);
    expect(find.text('View my booking'), findsOneWidget);
  });

  testWidgets('another service, or nothing going: no question', (tester) async {
    expect(await ask(tester, BookingKind.parcel, _ride('pending')), isTrue);
    expect(find.text('Book another?'), findsNothing);
    expect(await ask(tester, BookingKind.transport, null), isTrue);
  });
}
