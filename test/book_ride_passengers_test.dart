// Book a Ride → Vehicle step: the passengers − / + filters the vehicle list
// to the ones whose range fits the group (sql/044), and the fare follows.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;

import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/customer/data/customer_repository.dart';
import 'package:app_itulod/features/customer/presentation/screens/book_ride_screen.dart';
import 'package:app_itulod/features/customer/presentation/widgets/riders_near_you_map.dart';
import 'package:app_itulod/shared/models/vehicle_model.dart';

const _vehicles = [
  VehicleModel(id: 'm', name: 'Motorcycle', baseFare: 25, perKmRate: 8, rideBaseFare: 20, rideBaseKm: 1, ridePerKmRate: 10, maxPassengers: 1),
  VehicleModel(id: 't', name: 'Tricycle', baseFare: 30, perKmRate: 9, rideBaseFare: 20, rideBaseKm: 1.5, ridePerKmRate: 8, extraPassengerFee: 20, maxPassengers: 3),
  VehicleModel(id: 'c', name: 'Car', baseFare: 40, perKmRate: 12, rideBaseFare: 65, ridePerKmRate: 15, maxPassengers: 4),
  VehicleModel(id: 's', name: 'SUV', rideBaseFare: 75, ridePerKmRate: 18, minPassengers: 3, maxPassengers: 6),
  VehicleModel(id: 'j', name: 'Jeepney', rideBaseFare: 14, rideBaseKm: 4, ridePerKmRate: 2, farePerPassenger: true, minPassengers: 9, maxPassengers: 14),
];

/// Signed out, no Supabase: the ride screen keeps no draft.
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

void main() {
  testWidgets('passengers filter the vehicles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith((ref) => AuthNotifier(_NoAuthRepo())),
        vehiclesForServiceProvider('ride').overrideWithValue(const AsyncValue.data(_vehicles)),
        nearbyRidersProvider.overrideWith((ref) => Stream.value(const <NearbyRider>[])),
      ],
      child: const MaterialApp(home: BookRideScreen()),
    ));
    await tester.pump();

    List<String> offered() => tester
        .widgetList<DropdownMenuItem<VehicleModel>>(
            find.byType(DropdownMenuItem<VehicleModel>, skipOffstage: false))
        .map((i) => i.value!.name)
        .toSet()
        .toList();
    Future<void> tap(String tip, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        final btn = tester.widget<IconButton>(find.ancestor(of: find.byTooltip(tip, skipOffstage: false), matching: find.byType(IconButton, skipOffstage: false)));
        btn.onPressed!();
        await tester.pump();
      }
    }

    String count() => tester.widget<Text>(find.byKey(const Key('ride-passengers'), skipOffstage: false)).data!;

    expect(count(), '1');
    expect(offered(), ['Motorcycle', 'Tricycle', 'Car']);

    await tap('More passengers', 2); // 3
    expect(count(), '3');
    expect(offered(), ['Tricycle', 'Car', 'SUV']);

    await tap('More passengers', 9); // 12
    expect(offered(), ['Jeepney']);

    await tap('More passengers', 3); // 15 — nothing fits in this list
    expect(offered(), isEmpty);
    expect(find.textContaining('No vehicle fits 15 passengers', skipOffstage: false), findsOneWidget);

    await tap('Fewer passengers', 14); // back to 1, never below
    expect(count(), '1');
    expect(tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Fewer passengers', skipOffstage: false), matching: find.byType(IconButton, skipOffstage: false))).onPressed, isNull);
    expect(offered(), ['Motorcycle', 'Tricycle', 'Car']);
    expect(tester.takeException(), isNull);
  });
}
