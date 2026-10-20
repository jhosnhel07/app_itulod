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

/// Phone notifications for what happens while iTULOD isn't on screen.
///
/// * Everyone: each new row in \`notifications\` for this user (a rider
///   accepted, trip completed, refund, tip, application approved…).
/// * Online riders: new ride / food / parcel requests they can take — the
///   read policies only deliver jobs matching their vehicle (sql/033).
///   Hauling riders already get a "New hauling job" notification row.
///
/// Comes from Supabase Realtime, so it works while the app is running —
/// in the foreground or in the background. An Online rider's app keeps
/// running in the background (the location foreground service), so riders
/// keep getting new-job alerts with the app minimised. Alerts for a fully
/// closed app would need push (Firebase Cloud Messaging), which isn't set up.
///
/// While the app is on screen nothing is shown here — the screens already
/// update live.
class AppAlerts with WidgetsBindingObserver {
  static const _channelId = 'itulod_updates';
  static const _channelName = 'Booking updates';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  RealtimeChannel? _channel;
  String? _userId;
  int _nextId = 1;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Riders only get new-job alerts while Online.
  bool riderOnline = false;

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

  /// Starts listening for [userId]. [rider]: also alert on new jobs.
  Future<void> start({required String userId, bool rider = false}) async {
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

    var channel = SupabaseConfig.client.channel('alerts-$userId').onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            final row = payload.newRecord;
            _show(row['title']?.toString() ?? 'iTULOD', row['message']?.toString() ?? '');
          },
        );
    if (rider) {
      for (final (table, label) in const [
        ('transport_bookings', 'ride'),
        ('food_deliveries', 'food delivery'),
        ('parcel_deliveries', 'parcel delivery'),
      ]) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: table,
          callback: (payload) => _newJob(label, payload.newRecord),
        );
      }
    }
    _channel = channel.subscribe();
  }

  void _newJob(String label, Map<String, dynamic> row) {
    if (!riderOnline || row['rider_id'] != null || row['status'] != 'pending') return;
    // A ride booked for later only shows in Requests 30 min before pickup.
    final scheduled = DateTime.tryParse(row['scheduled_for']?.toString() ?? '');
    if (scheduled != null && scheduled.isAfter(DateTime.now().add(const Duration(minutes: 30)))) return;
    final from = (row['pickup_address'] ?? row['sender_address'] ?? row['restaurant_name'] ?? '').toString();
    final to = (row['destination_address'] ?? row['delivery_address'] ?? row['receiver_address'] ?? '').toString();
    final fare = num.tryParse('${row['estimated_fare']}');
    final parts = [
      if (from.isNotEmpty && to.isNotEmpty) '${_short(from)} → ${_short(to)}',
      if (fare != null) 'est. ₱${fare.toStringAsFixed(2)}',
    ];
    _show('New $label request', parts.isEmpty ? 'Open iTULOD to see it.' : parts.join(' · '));
  }

  static String _short(String s) => s.length > 32 ? '${s.substring(0, 31)}…' : s;

  Future<void> _show(String title, String body) async {
    if (!_ready || _lifecycle == AppLifecycleState.resumed) return;
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
