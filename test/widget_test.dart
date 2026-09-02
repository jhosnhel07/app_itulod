import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_itulod/app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The app reads config from .env at startup; supply dummy values so the
    // Supabase client can initialize in the test environment.
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return null;
    });

    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('iTULOD app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ITulodApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(ITulodApp), findsOneWidget);
  });
}
