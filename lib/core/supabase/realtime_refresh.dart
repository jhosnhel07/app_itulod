import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_log.dart';
import 'supabase_client.dart';

/// Subscribes a dashboard to Supabase Realtime so its lists refresh the moment
/// a booking / payment / notification row changes anywhere — the same
/// "live dashboard" behaviour the web app gets from `supabase.channel(...)`.
///
/// Drop it on a [ConsumerState], call [startRealtime] once from `initState`,
/// and the channel is torn down automatically in `dispose`.
mixin RealtimeRefreshMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  RealtimeChannel? _realtimeChannel;
  Timer? _sweepTimer;

  void startRealtime({
    required String channelName,
    required List<String> tables,
    required VoidCallback onChange,
  }) {
    // A hot reload can re-run initState without disposing — don't stack channels.
    _teardownRealtime();

    final client = SupabaseConfig.client;
    var channel = client.channel(channelName);
    for (final table in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          if (mounted) onChange();
        },
      );
    }
    channel.subscribe();
    _realtimeChannel = channel;
  }

  /// Defensive, client-side half of automatic booking expiration: calls the
  /// server-side `expire_stale_bookings()` sweep immediately, then again on
  /// [interval], for as long as this screen is mounted. The database's
  /// pg_cron job (migration 010b) is the real background timer — this just
  /// means a dashboard that's open shows expirations the moment they happen
  /// instead of waiting for the next cron tick, and keeps working even on a
  /// Supabase plan where pg_cron isn't available.
  void startExpirySweep({
    required VoidCallback onChange,
    Duration interval = const Duration(seconds: 60),
  }) {
    _sweepTimer?.cancel();
    unawaited(_sweepOnce(onChange));
    _sweepTimer = Timer.periodic(interval, (_) => _sweepOnce(onChange));
  }

  Future<void> _sweepOnce(VoidCallback onChange) async {
    try {
      final result = await SupabaseConfig.client.rpc('expire_stale_bookings');
      final expiredCount = (result as num?)?.toInt() ?? 0;
      if (expiredCount > 0 && mounted) onChange();
    } catch (e, s) {
      // Non-fatal: pg_cron (or the next sweep tick) still covers this.
      AppLog.warn('expire_stale_bookings sweep failed', e, s);
    }
  }

  void _teardownRealtime() {
    final channel = _realtimeChannel;
    if (channel != null) {
      SupabaseConfig.client.removeChannel(channel);
      _realtimeChannel = null;
    }
  }

  @override
  void dispose() {
    _teardownRealtime();
    _sweepTimer?.cancel();
    super.dispose();
  }
}
