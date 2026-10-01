import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static bool _initialized = false;

  static SupabaseClient get client => Supabase.instance.client;

  /// True once [initialize] has completed and there is a stored session.
  static bool get hasSession =>
      _initialized && Supabase.instance.client.auth.currentSession != null;

  /// Safe to call more than once (e.g. from a bootstrap retry) — the
  /// underlying `Supabase.initialize` only runs the first time it succeeds.
  static Future<void> initialize() async {
    if (_initialized) return;

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ??
        'https://ajzlvrvqpggnnwerahhq.supabase.co';
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ??
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFqemx2cnZxcGdnbm53ZXJhaGhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyODQ2OTAsImV4cCI6MjA5ODg2MDY5MH0.qNa97RY152fJgaA5mYQ0iCEoFVT1hfpqzUk6pRspDRU';

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
  }
}
