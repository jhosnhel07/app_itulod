import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app_itulod/core/theme/theme_controller.dart';
import 'package:app_itulod/shared/models/profile_model.dart';
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
    var openedNotifs = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [AccountMenuButton(onOpenProfile: () => openedProfile++, onOpenNotifications: () => openedNotifs++, unread: 3)]),
        ),
      ),
    ));

    await tester.tap(find.bySemanticsLabel('Account menu, 3 unread notifications'));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    // the unread count: on the picture and on the row
    expect(find.text('3'), findsNWidgets(2));

    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    expect(container.read(themeChoiceProvider), AppThemeChoice.dark);

    await tester.tap(find.text('My profile'));
    await tester.pumpAndSettle();
    expect(openedProfile, 1);
    expect(find.text('Dark mode'), findsNothing); // the sheet closed

    await tester.tap(find.bySemanticsLabel('Account menu, 3 unread notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(openedNotifs, 1);
  });

  testWidgets('no My profile row without a profile page', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(appBar: AppBar(actions: const [AccountMenuButton()]))),
    ));
    await tester.tap(find.bySemanticsLabel('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('role tag names who is logged in', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [
        RoleTag(role: UserRole.customer),
        RoleTag(role: UserRole.rider),
        RoleTag(role: UserRole.admin),
      ])),
    ));
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Rider'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });
}
