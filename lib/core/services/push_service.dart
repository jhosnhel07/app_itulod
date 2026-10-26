import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_client.dart';
import '../utils/app_log.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final push = PushService();
  ref.onDispose(push.dispose);
  return push;
});

/// Phone push (Firebase Cloud Messaging), so notifications arrive even when
/// the app is closed. After login the phone's FCM token is saved with
/// register_device (web sql/037); the server's send-push then delivers every
/// new notification to it. Firebase shows them itself while the app isn't on
/// screen — on screen, the app updates live instead.
///
/// The token is removed on logout (AuthRepository.signOut → unregister_device).
class PushService {
  StreamSubscription<String>? _refreshSub;

  static Future<FirebaseMessaging?> _messaging() async {
    if (kIsWeb) return null;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    return FirebaseMessaging.instance;
  }

  /// Returns true when this phone will get push notifications.
  Future<bool> register() async {
    try {
      final fm = await _messaging();
      if (fm == null) return false;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return false;
      // firebase_messaging 17 marks getToken/onTokenRefresh deprecated in
      // favour of register()/onRegistered, which yield a Firebase
      // Installation ID for the newer "direct send" API. send-push uses the
      // standard FCM v1 `message.token` (a registration token), so keep these.
      // ignore: deprecated_member_use
      final token = await fm.getToken();
      if (token == null) return false;
      await _save(token);
      await _refreshSub?.cancel();
      // ignore: deprecated_member_use
      _refreshSub = fm.onTokenRefresh.listen((t) => _save(t).catchError((Object _) {}));
      return true;
    } catch (e, s) {
      AppLog.warn('PushService: push notifications unavailable', e, s);
      return false;
    }
  }

  static Future<void> _save(String token) async {
    await SupabaseConfig.client.rpc('register_device', params: {'p_token': token, 'p_platform': 'android'});
  }

  /// Stops pushes to this phone for the signed-in user. Call BEFORE signing
  /// out — the server only lets a user remove their own tokens.
  static Future<void> unregisterCurrentDevice() async {
    try {
      if (kIsWeb || Firebase.apps.isEmpty) return;
      // ignore: deprecated_member_use — see register()
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await SupabaseConfig.client.rpc('unregister_device', params: {'p_token': token});
      }
    } catch (e, s) {
      AppLog.warn('PushService: could not remove this device', e, s);
    }
  }

  /// The `link` of a tapped push (e.g. `messages/transport/<id>`, web
  /// notifications.link) — [onLink] runs for the push that opened the app
  /// and for every one tapped while it was in the background. Call after
  /// [register], which starts Firebase.
  StreamSubscription<RemoteMessage>? _tapSub;
  Future<void> listenForTaps(void Function(String link) onLink) async {
    try {
      final fm = await _messaging();
      if (fm == null) return;
      String? linkOf(RemoteMessage? m) {
        final link = m?.data['link']?.toString();
        return link == null || link.isEmpty ? null : link;
      }
      final first = linkOf(await fm.getInitialMessage());
      if (first != null) onLink(first);
      await _tapSub?.cancel();
      _tapSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final link = linkOf(m);
        if (link != null) onLink(link);
      });
    } catch (e, s) {
      AppLog.warn('PushService: tap handling unavailable', e, s);
    }
  }

  void dispose() {
    _refreshSub?.cancel();
    _refreshSub = null;
    _tapSub?.cancel();
    _tapSub = null;
  }
}
