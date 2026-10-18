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
    testWidgets('lays out with the app theme and shows the OSM attribution',
        (tester) async {
      await pumpPhone(
        tester,
        MapPickerScreen(
          title: 'Set pickup location',
          initialCenter: _laoag,
          initialAddress: 'Colon Street, Cebu City',
          autoLocate: false,
          tileProvider: _FakeTileProvider(),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Set pickup location'), findsOneWidget);
      expect(find.text('Colon Street, Cebu City'), findsOneWidget);
      expect(find.text('Confirm location'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);

      // Displaying this is a condition of the OSM tile licence.
      expect(find.text(MapConfig.attribution), findsOneWidget);
    });

    testWidgets('Confirm returns the pin coordinates and the address',
        (tester) async {
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
                      builder: (_) => MapPickerScreen(
                        title: 'Set destination',
                        initialCenter: _laoag,
                        initialAddress: 'SM City Cebu',
                        autoLocate: false,
                        tileProvider: _FakeTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Set destination'), findsOneWidget);

      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.address, 'SM City Cebu');
      expect(result!.point.latitude, closeTo(_laoag.latitude, 0.0001));
      expect(result!.point.longitude, closeTo(_laoag.longitude, 0.0001));
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
          geocodingServiceProvider.overrideWithValue(
            GeocodingService(client: _fakeGeocoder()),
          ),
        ],
      );

      // The post-frame lookup has to resolve before the label updates.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Colon Street, Parian, Cebu City, Cebu'), findsOneWidget);
      expect(find.text('Finding address…'), findsNothing);
    });

    testWidgets('falls back to coordinates when Nominatim has no name',
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
          geocodingServiceProvider.overrideWithValue(
            GeocodingService(client: emptyGeocoder),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Never an empty address: the booking form requires one.
      expect(find.textContaining('18.19750, 120.59360'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a search result moves the pin and fills the address',        (tester) async {
      final geocoder = _fakeGeocoder(searchRows: [
        {
          'lat': '18.1781',
          'lon': '120.5317',
          'display_name': 'Ayala Center Cebu, Cebu Business Park, Cebu City, Cebu',
        },
      ]);

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
                      builder: (_) => MapPickerScreen(
                        title: 'Set destination',
                        initialCenter: _laoag,
                        initialAddress: 'Colon Street',
                        autoLocate: false,
                        tileProvider: _FakeTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: [
          geocodingServiceProvider
              .overrideWithValue(GeocodingService(client: geocoder)),
        ],
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ayala');
      // 500 ms debounce, then the request.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final option =
          find.text('Ayala Center Cebu, Cebu Business Park, Cebu City, Cebu');
      expect(option, findsOneWidget);

      await tester.tap(option);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.address, 'Ayala Center Cebu, Cebu Business Park, Cebu City, Cebu');
      expect(result!.point.latitude, closeTo(18.1781, 0.0001));
      expect(result!.point.longitude, closeTo(120.5317, 0.0001));
    });

    // Regression: the picker asks the device for a location when it opens, and
    // a cold GPS fix can take many seconds. It used to move the map whenever
    // that fix eventually landed — throwing away a spot the user had already
    // dragged to in the meantime, without saying anything.
    testWidgets('a late device fix does not override a spot the user dragged to',
        (tester) async {
      const manila = LatLng(18.5636, 120.7875); // Pagudpud — far from Laoag
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
                      builder: (_) => MapPickerScreen(
                        title: 'Set pickup location',
                        tileProvider: _FakeTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: [
          locationServiceProvider.overrideWithValue(
            const _SlowLocationService(manila, Duration(seconds: 3)),
          ),
          geocodingServiceProvider.overrideWithValue(
            GeocodingService(client: _fakeGeocoder()),
          ),
        ],
      );

      await tester.tap(find.text('open'));
      // Not pumpAndSettle: while the picker is locating, its progress spinners
      // animate forever and settling would never return.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The user picks their spot while the fix is still in flight. Driven as a
      // slow gesture so flutter_map does not read it as a fling.
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(FlutterMap)));
      await gesture.moveBy(const Offset(-40, -40));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveBy(const Offset(-40, -40));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Now the fix lands.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNotNull);
      expect(
        (result!.point.latitude - manila.latitude).abs(),
        greaterThan(0.2),
        reason: "the late fix moved the map away from the user's choice",
      );
      // The drag was a couple of hundred metres, so the pin stays near Laoag.
      expect(result!.point.latitude, closeTo(_laoag.latitude, 0.1));
      expect(result!.point.longitude, closeTo(_laoag.longitude, 0.1));
    });

    testWidgets('a device fix does centre the map when the user has not moved it',
        (tester) async {
      const manila = LatLng(18.5636, 120.7875); // Pagudpud
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
                      builder: (_) => MapPickerScreen(
                        title: 'Set pickup location',
                        tileProvider: _FakeTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: [
          locationServiceProvider.overrideWithValue(
            const _SlowLocationService(manila, Duration(seconds: 1)),
          ),
          geocodingServiceProvider.overrideWithValue(
            GeocodingService(client: _fakeGeocoder()),
          ),
        ],
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNotNull);
      expect(result!.point.latitude, closeTo(manila.latitude, 0.01));
      expect(result!.point.longitude, closeTo(manila.longitude, 0.01));
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
