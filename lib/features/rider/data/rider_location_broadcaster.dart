import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_log.dart';
import '../../../shared/models/booking_models.dart';

final riderLocationBroadcasterProvider = Provider<RiderLocationBroadcaster>((ref) {
  final broadcaster = RiderLocationBroadcaster(SupabaseConfig.client);
  ref.onDispose(broadcaster.dispose);
  return broadcaster;
});

/// Pushes the rider's GPS to `rider_locations` — the app equivalent of the
/// web's goOnline() / startLocationBroadcast() in js/map.js:
///
/// * **Online** (idle): ~1 write / 20 s with `is_online = true`, which is what
///   `get_nearby_riders()` shows customers before they book.
/// * **On a job**: ~1 write / 10 s tagged with the booking, which is what the
///   customer's booking-details map follows live (rl_select lets the customer
///   of an accepted/ongoing booking read their rider's row).
///
/// One position stream serves both; it stops when neither is needed.
class RiderLocationBroadcaster {
  final SupabaseClient _db;

  RiderLocationBroadcaster(this._db);

  StreamSubscription<Position>? _sub;
  String? _riderId;
  bool _online = false;
  BookingBase? _job;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isOnline => _online;

  /// Starts idle presence. Returns a user-facing error, or null on success.
  Future<String?> goOnline(String riderId) async {
    final problem = await _ensurePermission();
    if (problem != null) return problem;
    _riderId = riderId;
    _online = true;
    _lastWrite = DateTime.fromMillisecondsSinceEpoch(0); // write the first fix right away
    _ensureStream();
    return null;
  }

  /// Stops sending presence from this device without marking the rider
  /// offline — used when the rider went offline on another device (the web),
  /// which already wrote is_online = false.
  void stopPresenceLocally() {
    _online = false;
    _stopIfIdle();
  }

  Future<void> goOffline(String riderId) async {
    _online = false;
    try {
      await _db.from('rider_locations').update({'is_online': false}).eq('rider_id', riderId);
    } catch (e, s) {
      AppLog.warn('goOffline update failed', e, s);
    }
    _stopIfIdle();
  }

  /// Called whenever the rider's active booking changes (or ends: `null`).
  Future<void> setActiveJob(String riderId, BookingBase? job) async {
    if (job?.id == _job?.id && job?.status == _job?.status) return;
    _riderId = riderId;
    final hadJob = _job != null;
    _job = job;

    if (job != null) {
      if (await _ensurePermission() == null) {
        _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
        _ensureStream();
      }
      return;
    }

    if (hadJob) {
      // Trip over: drop the booking tag but keep the row (web:
      // stopLocationBroadcast). Deleting it also wiped is_online, which —
      // with online status synced to the web — switched an online rider off.
      try {
        await _db
            .from('rider_locations')
            .update({'booking_type': null, 'booking_id': null})
            .eq('rider_id', riderId);
      } catch (e, s) {
        AppLog.warn('clearing job location failed', e, s);
      }
    }
    _stopIfIdle();
  }

  /// On Android the stream runs as a foreground service with a "you're
  /// online" notification, so location keeps going to customers (and new-job
  /// alerts keep arriving — AppAlerts) while the app is in the background.
  /// It stops with the stream when the rider goes offline and has no job.
  static LocationSettings get _settings {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "iTULOD — you're online",
          notificationText: 'Sharing your location so customers can find and track you. Go offline to stop.',
          notificationChannelName: 'Rider location',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
  }

  void _ensureStream() {
    if (_sub != null) return;
    _sub = Geolocator.getPositionStream(
      locationSettings: _settings,
    ).listen(_onPosition, onError: (Object e, StackTrace s) {
      AppLog.warn('rider position stream error', e, s);
    });
    // The stream only emits on movement; push the current fix immediately so
    // a stationary rider still shows up.
    Geolocator.getCurrentPosition().then(_onPosition).catchError((Object e) {
      AppLog.warn('initial rider fix failed', e);
    });
  }

  void _stopIfIdle() {
    if (_online || _job != null) return;
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onPosition(Position p) async {
    final riderId = _riderId;
    if (riderId == null || (!_online && _job == null)) return;
    final interval = _job != null ? const Duration(seconds: 10) : const Duration(seconds: 20);
    final now = DateTime.now();
    if (now.difference(_lastWrite) < interval) return;
    _lastWrite = now;

    final job = _job;
    try {
      await _db.from('rider_locations').upsert({
        'rider_id': riderId,
        'lat': double.parse(p.latitude.toStringAsFixed(6)),
        'lng': double.parse(p.longitude.toStringAsFixed(6)),
        'heading': p.heading.isFinite && p.heading >= 0
            ? double.parse(p.heading.toStringAsFixed(1))
            : null,
        // Only the device that went online claims it; trip tracking from a
        // phone that didn't must not switch off a rider who's online on the web.
        if (_online) 'is_online': true,
        'booking_type': job?.kind.name,
        'booking_id': job?.id,
        'updated_at': now.toUtc().toIso8601String(),
      }, onConflict: 'rider_id');
    } catch (e, s) {
      AppLog.warn('rider location upsert failed', e, s);
    }
  }

  Future<String?> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Turn on location services to go online.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return 'Location is blocked for iTULOD. Enable it in your device settings.';
      }
      if (permission == LocationPermission.denied) {
        return "Couldn't access your location — location permission is needed to go online.";
      }
      return null;
    } catch (e, s) {
      AppLog.warn('location permission check failed', e, s);
      return "Couldn't access your location.";
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
