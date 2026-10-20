import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';
import '../utils/app_log.dart';

final appAlertsProvider = Provider<AppAlerts>((ref) {
  final alerts = AppAlerts();
  ref.onDispose(alerts.stop);
  return alerts;
});

/// Fallback phone notifications for when push (PushService / Firebase) isn't
/// available on this phone — e.g. no Google Play services. Each new row in
/// `notifications` for this user (rider accepted, trip completed, refund, new
/// job request…) is shown while the app is running in the background.
///
/// With push working, Firebase shows the same notifications (even with the
/// app closed) and this stays quiet, so nothing appears twice. New-job alerts
/// are notification rows too (web sql/037). It also creates the "Booking
/// updates" channel that Firebase pushes use.
///
/// While the app is on screen nothing is shown — the screens update live.
class AppAlerts with WidgetsBindingObserver {
  static const _channelId = 'itulod_updates';
  static const _channelName = 'Booking updates';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  RealtimeChannel? _channel;
  String? _userId;
  int _nextId = 1;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Set once Firebase push is registered for this phone — then this stays
  /// quiet (Firebase shows the same notifications).
  bool pushActive = false;

  Future<void> _init() async {
    if (_ready || kIsWeb) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Booking updates and new job requests',
      importance: Importance.high,
    ));
    await android?.requestNotificationsPermission();
    WidgetsBinding.instance.addObserver(this);
    _ready = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _lifecycle = state;

  /// Starts listening for [userId].
  Future<void> start({required String userId}) async {
    if (kIsWeb) return;
    if (_userId == userId && _channel != null) return;
    await stop();
    try {
      await _init();
    } catch (e, s) {
      AppLog.warn('AppAlerts: notifications unavailable', e, s);
      return;
    }
    _userId = userId;
    _channel = SupabaseConfig.client
        .channel('alerts-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            final row = payload.newRecord;
            _show(row['title']?.toString() ?? 'iTULOD', row['message']?.toString() ?? '');
          },
        )
        .subscribe();
  }

  Future<void> _show(String title, String body) async {
    if (!_ready || pushActive || _lifecycle == AppLifecycleState.resumed) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e, s) {
      AppLog.warn('AppAlerts: show failed', e, s);
    }
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _userId = null;
    if (channel != null) {
      try {
        await SupabaseConfig.client.removeChannel(channel);
      } catch (_) {/* best effort */}
    }
  }
}
