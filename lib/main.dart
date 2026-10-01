import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything else (env, Supabase, first auth check) runs inside AppRoot so
  // the splash can show progress and offer Retry if a step fails.
  runApp(
    const ProviderScope(
      child: AppRoot(),
    ),
  );
}
