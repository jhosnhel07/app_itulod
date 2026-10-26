// Reopen where you were after Android closed the app (LastPlace): the tab,
// the booking screen and its half-filled form; nothing after log out.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;

import 'package:app_itulod/core/services/last_place.dart';
import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/customer/data/customer_repository.dart';
import 'package:app_itulod/features/customer/presentation/screens/book_ride_screen.dart';
import 'package:app_itulod/features/customer/presentation/widgets/riders_near_you_map.dart';
import 'package:app_itulod/shared/models/profile_model.dart';
import 'package:app_itulod/shared/models/vehicle_model.dart';

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

AuthNotifier _signedIn(String id) {
  // ignore: invalid_use_of_protected_member
  return AuthNotifier(_NoAuthRepo())..state = AppAuthState(
      status: AuthStatus.authenticated,
      profile: ProfileModel(id: id, fullName: 'Maria Santos', email: 'maria@example.com'));
}

const _vehicles = [
  VehicleModel(id: 'm', name: 'Motorcycle', rideBaseFare: 20, rideBaseKm: 1, ridePerKmRate: 10, maxPassengers: 1),
  VehicleModel(id: 'c', name: 'Car', rideBaseFare: 65, ridePerKmRate: 15, maxPassengers: 4),
  VehicleModel(id: 'j', name: 'Jeepney', rideBaseFare: 14, rideBaseKm: 4, ridePerKmRate: 2, farePerPassenger: true, minPassengers: 9, maxPassengers: 14),
];

String _now([Duration ago = Duration.zero]) => DateTime.now().subtract(ago).toIso8601String();

void main() {
  test('tab, open screen and drafts are kept per account; log out clears them', () async {
    SharedPreferences.setMockInitialValues({});
    await LastPlace.saveTab('customer', 'u1', 2);
    await LastPlace.setOpenForm('u1', 'parcel');
    await LastPlace.saveDraft('parcel', 'u1', {'senderName': 'Maria'});
    expect(await LastPlace.tab('customer', 'u1'), 2);
    expect(await LastPlace.tab('customer', 'u2'), isNull);
    expect(await LastPlace.openForm('u1'), 'parcel');
    expect((await LastPlace.draft('parcel', 'u1'))?['senderName'], 'Maria');

    await LastPlace.clearAll();
    expect(await LastPlace.tab('customer', 'u1'), isNull);
    expect(await LastPlace.openForm('u1'), isNull);
    expect(await LastPlace.draft('parcel', 'u1'), isNull);
  });

  test('a draft older than 30 minutes is dropped', () async {
    SharedPreferences.setMockInitialValues({
      'last_place.draft.ride.u1': jsonEncode({'pickup': 'old', '__saved': _now(const Duration(minutes: 31))}),
      'last_place.draft.ride.u2': jsonEncode({'pickup': 'fresh', '__saved': _now(const Duration(minutes: 5))}),
    });
    expect(await LastPlace.draft('ride', 'u1'), isNull);
    expect((await LastPlace.draft('ride', 'u2'))?['pickup'], 'fresh');
  });

  testWidgets('Book a Ride comes back with the draft, on the Vehicle step', (tester) async {
    SharedPreferences.setMockInitialValues({
      'last_place.draft.ride.u1': jsonEncode({
        'pickup': 'Laoag City Hall, Laoag City',
        'pickupPoint': {'lat': 18.1978, 'lng': 120.5936},
        'destination': 'Batac Public Market, Batac City',
        'destinationPoint': {'lat': 18.0554, 'lng': 120.5650},
        'stops': [],
        'passengers': 12,
        'vehicleId': 'j',
        'payment': 'gcash',
        '__step': 1,
        '__saved': _now(),
      }),
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _signedIn('u1')),
        vehiclesForServiceProvider('ride').overrideWithValue(const AsyncValue.data(_vehicles)),
        nearbyRidersProvider.overrideWith((ref) => Stream.value(const <NearbyRider>[])),
      ],
      child: const MaterialApp(home: BookRideScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.widget<Text>(find.byKey(const Key('ride-passengers'), skipOffstage: false)).data, '12');
    // the Vehicle step is the one on screen, with the Jeepney chosen
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.textContaining('Jeepney —'), findsWidgets);
    expect(find.text('Laoag City Hall, Laoag City', skipOffstage: false), findsOneWidget);
    expect(await LastPlace.openForm('u1'), 'ride');

    // leaving the screen: not reopened next time, but the draft stays
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    expect(await LastPlace.openForm('u1'), isNull);
    expect((await LastPlace.draft('ride', 'u1'))?['passengers'], 12);
    expect(tester.takeException(), isNull);
  });
}
