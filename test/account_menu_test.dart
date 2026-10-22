import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app_itulod/core/theme/theme_controller.dart';
import 'package:app_itulod/shared/widgets/account_menu_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/shared_preferences'), (c) async => null);
    await Supabase.initialize(url: 'https://placeholder.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('profile picture opens My profile, Dark mode and Log out', (tester) async {
    var openedProfile = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [AccountMenuButton(onOpenProfile: () => openedProfile++)]),
        ),
      ),
    ));

    await tester.tap(find.bySemanticsLabel('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);

    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    expect(container.read(themeChoiceProvider), AppThemeChoice.dark);

    await tester.tap(find.text('My profile'));
    await tester.pumpAndSettle();
    expect(openedProfile, 1);
    expect(find.text('Dark mode'), findsNothing); // the sheet closed
  });

  testWidgets('no My profile row without a profile page', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(appBar: AppBar(actions: const [AccountMenuButton()]))),
    ));
    await tester.tap(find.bySemanticsLabel('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsNothing);
    expect(find.text('Log out'), findsOneWidget);
  });
}
