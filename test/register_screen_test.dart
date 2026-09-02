import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app_itulod/core/theme/app_theme.dart';
import 'package:app_itulod/features/auth/presentation/screens/register_screen.dart';
import 'package:app_itulod/features/auth/presentation/widgets/auth_gradient_button.dart';
import 'package:app_itulod/features/auth/presentation/widgets/auth_text_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return null;
    });

    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  /// Pumps the register screen at phone size with the real app theme.
  ///
  /// Both matter: the theme carries the button styles the screen inherits, and
  /// the pinned action bar only lays out against a real viewport.
  Future<void> pumpRegister(WidgetTester tester, {int initialStep = 0}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: RegisterScreen(initialStep: initialStep),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldNamed(String label) => find.descendant(
        of: find.byWidgetPredicate((w) => w is AuthTextField && w.label == label),
        matching: find.byType(TextFormField),
      );

  testWidgets('role step renders and Continue reaches the personal step', (tester) async {
    await pumpRegister(tester);

    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Continue'), findsWidgets);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the personal step must lay out without throwing');
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.byType(AuthBackButton), findsOneWidget);
  });

  testWidgets('rider role adds the license field to the personal step', (tester) async {
    await pumpRegister(tester);

    await tester.tap(find.text('Rider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Driver's License Number"), findsOneWidget);
  });

  // The pinned action bar puts AuthBackButton next to an Expanded sibling in a
  // Row, which lays it out with an unbounded width. Combined with a full-width
  // minimumSize from the theme that used to force an infinite width and blank
  // the whole screen, so every step with a back button needs covering.
  for (final step in const [1, 2, 3, 4]) {
    testWidgets('step $step lays out with the app theme', (tester) async {
      await pumpRegister(tester, initialStep: step);

      expect(tester.takeException(), isNull);
      expect(find.byType(AuthBackButton), findsOneWidget);
    });
  }

  testWidgets('customer submit is blocked until the terms box is ticked', (tester) async {
    await pumpRegister(tester, initialStep: 1);

    await tester.enterText(fieldNamed('Full Name'), 'Juan dela Cruz');
    await tester.enterText(fieldNamed('Phone Number'), '09171234567');
    await tester.enterText(fieldNamed('Email Address'), 'juan@example.com');
    await tester.enterText(fieldNamed('Password'), 'Password1!');
    await tester.enterText(fieldNamed('Confirm Password'), 'Password1!');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please accept the Terms & Privacy Policy.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validators name the field they reject', (tester) async {
    await pumpRegister(tester, initialStep: 1);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Full Name is required'), findsOneWidget);
    expect(find.text(' is required'), findsNothing);
  });

  testWidgets('rider cannot reach review with documents missing', (tester) async {
    await pumpRegister(tester, initialStep: 3);

    await tester.tap(find.text('Continue to Review'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Please upload: Driver's License"),
      findsOneWidget,
      reason: 'missing required uploads must be reported, not silently accepted',
    );
    expect(find.text('Review Your Application'), findsNothing);
  });
}
