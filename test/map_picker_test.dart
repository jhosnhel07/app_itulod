import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:app_itulod/core/constants/map_config.dart';
import 'package:app_itulod/core/services/geocoding_service.dart';
import 'package:app_itulod/core/services/location_service.dart';
import 'package:app_itulod/core/services/route_service.dart';
import 'package:app_itulod/core/theme/app_theme.dart';
import 'package:app_itulod/features/customer/presentation/screens/map_picker_screen.dart';
import 'package:app_itulod/features/customer/presentation/widgets/route_preview_map.dart';

/// Returns a transparent image for every tile, so no test ever reaches the
/// OpenStreetMap tile servers.
///
/// Also records what was asked for. Which tiles a map requests is the only
/// evidence available in a widget test that its camera is pointing at the
/// right place — asserting that layers exist proves nothing, since a map
/// showing blank grey has all of its layers too.
class _FakeTileProvider extends TileProvider {
  final List<TileCoordinates> requested = [];

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requested.add(coordinates);
    return MemoryImage(TileProvider.transparentImage);
  }

  /// The geographic centre of each requested tile, via the standard
  /// slippy-map inverse projection.
  Iterable<LatLng> get requestedCenters => requested.map((t) {
        final n = math.pow(2, t.z).toDouble();
        final lon = (t.x + 0.5) / n * 360 - 180;
        final lat = math.atan(_sinh(math.pi * (1 - 2 * (t.y + 0.5) / n))) *
            180 /
            math.pi;
        return LatLng(lat, lon);
      });

  /// True when some requested tile covers [point] to within [toleranceDeg].
  bool covers(LatLng point, {double toleranceDeg = 1.0}) {
    return requestedCenters.any((c) =>
        (c.latitude - point.latitude).abs() < toleranceDeg &&
        (c.longitude - point.longitude).abs() < toleranceDeg);
  }
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

const _cebu = LatLng(10.3157, 123.8854);

/// Map-picker fixtures sit inside Ilocos Norte — the picker refuses spots
/// outside iTULOD's service area.
const _laoag = LatLng(18.1975, 120.5936);

/// A device fix that only lands after [delay] — a cold GPS start.
class _SlowLocationService extends LocationService {
  final LatLng point;
  final Duration delay;

  const _SlowLocationService(this.point, this.delay);

  @override
  Future<LocationResult> currentPosition({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await Future<void>.delayed(delay);
    return LocationResult.success(point);
  }
}

const _nominatimReverse = {
  'display_name':
      'Colon Street, Parian, Cebu City, Cebu, Central Visayas, 6000, Philippines',
};

/// Nominatim client that answers /reverse and /search from canned JSON.
http.Client _fakeGeocoder({List<Map<String, dynamic>>? searchRows}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/reverse')) {
      return http.Response(jsonEncode(_nominatimReverse), 200);
    }
    if (request.url.path.endsWith('/search')) {
      return http.Response(jsonEncode(searchRows ?? const []), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  /// Pumps a widget at phone size with the real app theme.
  ///
  /// Both matter: the theme carries the button and input styles the screen
  /// inherits, and a real viewport is what surfaces layout faults.
  Future<void> pumpPhone(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: AppTheme.lightTheme, home: home),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('MapPickerScreen', () {
    /// Routing is never reachable in tests — the picker falls back to a
    /// straight line, which is all these tests need.
    final noRouting = routeServiceProvider.overrideWithValue(
      RouteService(client: MockClient((_) async => http.Response('down', 503))),
    );

    /// Opens [screen] from a button and returns whatever it pops.
    Future<T? Function()> openFromButton<T>(
      WidgetTester tester,
      Widget screen, {
      List<Override> overrides = const [],
    }) async {
      T? result;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<T>(
                    MaterialPageRoute(builder: (_) => screen),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: [noRouting, ...overrides],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    Offset mapCentre(WidgetTester tester) => tester.getCenter(find.byType(FlutterMap));

    testWidgets('lays out with the app theme and shows the map attribution',
        (tester) async {
      await pumpPhone(
        tester,
        MapPickerScreen(
          title: 'Set pickup location',
          initialCenter: _laoag,
          initialAddress: 'Rizal Street, Laoag City',
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
        overrides: [noRouting],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Set pickup location'), findsOneWidget);
      expect(find.text('Rizal Street, Laoag City'), findsOneWidget);
      expect(find.text('Tap on the map to set the location.'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);

      // Displaying this is a condition of the tile licence. (No MAPBOX_TOKEN
      // in tests, so the Esri fallback is what's shown.)
      expect(find.text(MapConfig.attribution), findsOneWidget);
    });

    testWidgets('Done returns the opening pin and its address', (tester) async {
      final result = await openFromButton<PickedPlace>(
        tester,
        MapPickerScreen(
          title: 'Set destination',
          initialCenter: _laoag,
          initialAddress: 'Laoag City Hall',
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
      );
      expect(find.text('Set destination'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result(), isNotNull);
      expect(result()!.address, 'Laoag City Hall');
      expect(result()!.point.latitude, closeTo(_laoag.latitude, 0.0001));
      expect(result()!.point.longitude, closeTo(_laoag.longitude, 0.0001));
    });

    testWidgets('reverse-geocodes the opening pin into a short address',
        (tester) async {
      await pumpPhone(
        tester,
        MapPickerScreen(
          title: 'Set pickup location',
          initialCenter: _laoag,
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
        overrides: [
          noRouting,
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: _fakeGeocoder())),
        ],
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Colon Street, Parian, Cebu City, Cebu'), findsOneWidget);
      expect(find.text('Finding address…'), findsNothing);
    });

    testWidgets('falls back to coordinates when nothing has a name',
        (tester) async {
      final emptyGeocoder = MockClient((_) async => http.Response('{}', 200));
      await pumpPhone(
        tester,
        MapPickerScreen(
          title: 'Set pickup location',
          initialCenter: _laoag,
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
        overrides: [
          noRouting,
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: emptyGeocoder)),
        ],
      );
      await tester.pumpAndSettle();

      // Never an empty address: the booking form requires one.
      expect(find.textContaining('18.19750, 120.59360'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the map drops the pin there (web: click to set)',
        (tester) async {
      final result = await openFromButton<PickedPlace>(
        tester,
        MapPickerScreen(title: 'Set Location', autoLocate: false, tileProvider: _FakeTileProvider()),
        overrides: [
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: _fakeGeocoder())),
        ],
      );

      // Nothing pinned yet: Done is disabled.
      expect(find.text('Tap the map to set'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(result(), isNull);

      await tester.tapAt(mapCentre(tester));
      // flutter_map holds a tap briefly in case it is a double-tap (zoom).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Colon Street, Parian, Cebu City, Cebu'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The map opens on Laoag, so a tap in its middle pins Laoag.
      expect(result(), isNotNull);
      expect(result()!.point.latitude, closeTo(MapConfig.defaultCenter.latitude, 0.01));
      expect(result()!.point.longitude, closeTo(MapConfig.defaultCenter.longitude, 0.01));
      expect(result()!.address, 'Colon Street, Parian, Cebu City, Cebu');
    });

    testWidgets('a search result drops the pin and fills the address',
        (tester) async {
      final geocoder = _fakeGeocoder(searchRows: [
        {
          'lat': '18.1781',
          'lon': '120.5317',
          'display_name': 'Fort Ilocandia, Calayab, Laoag City, Ilocos Norte',
        },
      ]);
      final result = await openFromButton<PickedPlace>(
        tester,
        MapPickerScreen(
          title: 'Set destination',
          initialCenter: _laoag,
          initialAddress: 'Rizal Street',
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
        overrides: [geocodingServiceProvider.overrideWithValue(GeocodingService(client: geocoder))],
      );

      await tester.tap(find.byTooltip('Search a place'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fort');
      // 500 ms debounce, then the request.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final option = find.text('Fort Ilocandia, Calayab, Laoag City, Ilocos Norte');
      expect(option, findsOneWidget);
      await tester.tap(option);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result(), isNotNull);
      expect(result()!.address, 'Fort Ilocandia, Calayab, Laoag City, Ilocos Norte');
      expect(result()!.point.latitude, closeTo(18.1781, 0.0001));
      expect(result()!.point.longitude, closeTo(120.5317, 0.0001));
    });

    testWidgets('route mode: pickup, then it moves to drop-off by itself',
        (tester) async {
      final result = await openFromButton<PickedRoute>(
        tester,
        MapPickerScreen(
          title: 'Set location on map',
          routeMode: true,
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
        overrides: [
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: _fakeGeocoder())),
        ],
      );

      expect(find.text('Set Pickup'), findsOneWidget);
      expect(find.text('Set Drop-off'), findsOneWidget);
      expect(find.text('Tap on the map to set your pickup location.'), findsOneWidget);

      await tester.tapAt(mapCentre(tester));
      // flutter_map holds a tap briefly in case it is a double-tap (zoom).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      // Web: setting the pickup switches the map to drop-off.
      expect(find.text('Tap on the map to set your drop-off location.'), findsOneWidget);

      await tester.tapAt(mapCentre(tester) + const Offset(80, 90));
      // flutter_map holds a tap briefly in case it is a double-tap (zoom).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final route = result();
      expect(route, isNotNull);
      expect(route!.pickup, isNotNull);
      expect(route.dropoff, isNotNull);
      expect(route.pickup!.point.latitude, closeTo(MapConfig.defaultCenter.latitude, 0.01));
      expect(route.dropoff!.point.latitude, lessThan(route.pickup!.point.latitude),
          reason: 'the drop-off was tapped below the pickup');
      expect(route.dropoff!.point.longitude, greaterThan(route.pickup!.point.longitude),
          reason: 'the drop-off was tapped right of the pickup');
    });

    testWidgets('route mode opened on drop-off keeps the existing pickup',
        (tester) async {
      final result = await openFromButton<PickedRoute>(
        tester,
        MapPickerScreen(
          title: 'Set location on map',
          routeMode: true,
          initialPickup: const PickedPlace(point: _laoag, address: 'Laoag City Hall'),
          startMode: PinMode.dropoff,
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
        overrides: [
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: _fakeGeocoder())),
        ],
      );
      expect(find.text('Laoag City Hall'), findsOneWidget);
      expect(find.text('Tap on the map to set your drop-off location.'), findsOneWidget);

      await tester.tapAt(mapCentre(tester) + const Offset(-70, 60));
      // flutter_map holds a tap briefly in case it is a double-tap (zoom).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result()!.pickup!.address, 'Laoag City Hall');
      expect(result()!.pickup!.point.latitude, closeTo(_laoag.latitude, 0.0001));
      expect(result()!.dropoff, isNotNull);
    });

    // Regression: the picker asks the device for a location when it opens, and
    // a cold GPS fix can take many seconds. When it lands it may centre the
    // map, but never move a pin the user has already dropped.
    testWidgets('a late device fix does not move a pin the user dropped',
        (tester) async {
      const pagudpud = LatLng(18.5636, 120.7875); // far from Laoag
      PickedPlace? result;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<PickedPlace>(
                    MaterialPageRoute(
                      builder: (_) => MapPickerScreen(title: 'Set Location', tileProvider: _FakeTileProvider()),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: [
          noRouting,
          locationServiceProvider.overrideWithValue(const _SlowLocationService(pagudpud, Duration(seconds: 3))),
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: _fakeGeocoder())),
        ],
      );

      await tester.tap(find.text('open'));
      // Not pumpAndSettle: while locating, the spinner animates forever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The user taps their spot while the fix is still in flight.
      await tester.tapAt(mapCentre(tester));
      // flutter_map holds a tap briefly in case it is a double-tap (zoom).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // Now the fix lands.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNotNull);
      expect(result!.point.latitude, closeTo(MapConfig.defaultCenter.latitude, 0.05),
          reason: "the late fix moved the user's pin");
    });

    testWidgets('a device fix centres the map when nothing was pinned yet',
        (tester) async {
      const pagudpud = LatLng(18.5636, 120.7875);
      PickedPlace? result;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<PickedPlace>(
                    MaterialPageRoute(
                      builder: (_) => MapPickerScreen(title: 'Set Location', tileProvider: _FakeTileProvider()),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: [
          noRouting,
          locationServiceProvider.overrideWithValue(const _SlowLocationService(pagudpud, Duration(seconds: 1))),
          geocodingServiceProvider.overrideWithValue(GeocodingService(client: _fakeGeocoder())),
        ],
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));

      // The map now sits on the device location; a tap in its middle pins it.
      await tester.tapAt(mapCentre(tester));
      // flutter_map holds a tap briefly in case it is a double-tap (zoom).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNotNull);
      expect(result!.point.latitude, closeTo(pagudpud.latitude, 0.01));
      expect(result!.point.longitude, closeTo(pagudpud.longitude, 0.01));
    });
  });

  group('RoutePreviewMap', () {
    const mandaue = LatLng(10.3231, 123.9223);

    testWidgets('lays out a straight-line preview when routing failed',
        (tester) async {
      final tiles = _FakeTileProvider();

      await pumpPhone(
        tester,
        Scaffold(
          body: RoutePreviewMap(
            pickup: _cebu,
            destination: mandaue,
            tileProvider: tiles,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text(MapConfig.attribution), findsOneWidget);

      // Not just "a map exists" — a map looking at the trip.
      expect(tiles.requested, isNotEmpty);
      expect(tiles.covers(_cebu), isTrue,
          reason: 'no tile was requested near the pickup');
      expect(tiles.covers(mandaue), isTrue,
          reason: 'no tile was requested near the destination');
    });

    testWidgets('lays out a road polyline when one is supplied', (tester) async {
      await pumpPhone(
        tester,
        Scaffold(
          body: RoutePreviewMap(
            pickup: _cebu,
            destination: mandaue,
            routePoints: const [
              _cebu,
              LatLng(10.3180, 123.9000),
              mandaue,
            ],
            tileProvider: _FakeTileProvider(),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PolylineLayer<Object>), findsOneWidget);
    });

    // Regression: the preview used to rely on MapOptions.initialCameraFit,
    // which is applied in a post-frame callback — after TileLayer has already
    // done its only unprompted load, against the camera the map was born with.
    // A preview built on the first frame got away with it; this one, built once
    // the route arrives, requested no tiles at all and rendered blank grey.
    testWidgets('requests tiles for the trip when built after the first frame',
        (tester) async {
      final tiles = _FakeTileProvider();
      late StateSetter setOuterState;
      var showPreview = false;

      await pumpPhone(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Scaffold(
              body: ListView(
                children: [
                  const SizedBox(height: 400),
                  if (showPreview)
                    RoutePreviewMap(
                      pickup: _cebu,
                      destination: mandaue,
                      tileProvider: tiles,
                    ),
                ],
              ),
            );
          },
        ),
      );

      expect(tiles.requested, isEmpty, reason: 'no preview on screen yet');

      setOuterState(() => showPreview = true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tiles.requested, isNotEmpty,
          reason: 'the preview loaded no tiles, so it would render blank');
      expect(tiles.covers(_cebu), isTrue,
          reason: 'no tile was requested near the pickup');
      expect(tiles.covers(mandaue), isTrue,
          reason: 'no tile was requested near the destination');
    });

    testWidgets('re-frames on the road route once it replaces the guess',
        (tester) async {
      // A route that swings well north of the straight line: if the camera
      // never re-fits, no tile covers the detour.
      const detour = LatLng(10.4200, 123.9000);
      final tiles = _FakeTileProvider();
      late StateSetter setOuterState;
      List<LatLng>? route;

      await pumpPhone(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Scaffold(
              body: RoutePreviewMap(
                pickup: _cebu,
                destination: mandaue,
                routePoints: route,
                tileProvider: tiles,
              ),
            );
          },
        ),
      );

      setOuterState(() => route = const [_cebu, detour, mandaue]);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tiles.covers(detour, toleranceDeg: 0.6), isTrue,
          reason: 'the camera did not re-fit around the road route');
    });

    testWidgets('survives a pickup and destination on the same spot',
        (tester) async {
      // A zero-area bounds is what makes a camera fit divide by zero.
      final tiles = _FakeTileProvider();

      await pumpPhone(
        tester,
        Scaffold(
          body: RoutePreviewMap(
            pickup: _cebu,
            destination: _cebu,
            tileProvider: tiles,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tiles.covers(_cebu), isTrue);
    });

    testWidgets('survives a box too small for its own padding', (tester) async {
      final tiles = _FakeTileProvider();

      await pumpPhone(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 40,
              child: RoutePreviewMap(
                pickup: _cebu,
                destination: mandaue,
                height: 40,
                tileProvider: tiles,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tiles.requested, isNotEmpty);
    });
  });
}
