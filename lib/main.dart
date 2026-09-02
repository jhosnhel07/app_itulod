import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/supabase/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment configuration
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // If .env is missing or cannot be loaded, SupabaseConfig will fallback to defaults
  }

  // Initialize Supabase client
  await SupabaseConfig.initialize();

  runApp(
    const ProviderScope(
      child: ITulodApp(),
    ),
  );
}
