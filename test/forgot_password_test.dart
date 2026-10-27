// Forgot password (web sql/049): email or number → 6-digit code → new
// password → on to the dashboard (via /login). The server is faked here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthState, Session, User;

import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/auth/presentation/screens/forgot_password_screen.dart';

class _FakeAuth implements AuthRepository {
  final sent = <String>[];
  String? verifiedWith;
  String? newPassword;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  User? get currentUser => null;
  @override
  Session? get currentSession => null;

  @override
  Future<String> sendResetCode(String identifier) async {
    if (identifier == '0917 000 0001') throw const AuthException('No account uses that mobile number.');
    sent.add(identifier);
    return 'ma***@gmail.com';
  }

  @override
  Future<void> verifyResetCode(String identifier, String code) async {
    if (code != '482913') throw const AuthException('That code is wrong or has expired.');
    verifiedWith = '$identifier/$code';
  }

  @override
  Future<void> updatePassword(String password) async => newPassword = password;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The sign-in background animates forever, so pumpAndSettle never ends.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<_FakeAuth> _open(WidgetTester tester, {String initial = ''}) async {
  final view = tester.view;
  view.physicalSize = const Size(400 * 3, 1400 * 3);
  view.devicePixelRatio = 3;
  addTearDown(view.resetPhysicalSize);
  addTearDown(view.resetDevicePixelRatio);
  final fake = _FakeAuth();
  final router = GoRouter(initialLocation: '/forgot-password', routes: [
    GoRoute(path: '/forgot-password', builder: (_, __) => ForgotPasswordScreen(initialIdentifier: initial)),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('LOGIN → DASHBOARD'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fake),
      authNotifierProvider.overrideWith((ref) => AuthNotifier(fake)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(tester);
  return fake;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextFormField).first, text);
  await tester.pump();
}

String _sub(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('fp-sub'))).data!;

void main() {
  testWidgets('number → code → new password → on to the dashboard', (tester) async {
    final fake = await _open(tester, initial: '0917 123 4567');

    // step 1: the number typed at login is already there
    await tester.tap(find.byKey(const Key('fp-send')));
    await _settle(tester);
    expect(fake.sent, ['0917 123 4567']);
    expect(_sub(tester), contains('ma***@gmail.com'));
    expect(find.text('Resend code (60s)'), findsOneWidget);

    // step 2: a wrong code stays put; the right one moves on
    await _type(tester, '111111');
    await tester.tap(find.byKey(const Key('fp-verify')));
    await _settle(tester);
    expect(find.text('That code is wrong or has expired.'), findsOneWidget);
    expect(find.byKey(const Key('fp-verify')), findsOneWidget);
    await _type(tester, '482 913');
    await tester.tap(find.byKey(const Key('fp-verify')));
    await _settle(tester);
    expect(fake.verifiedWith, '0917 123 4567/482913');
    expect(_sub(tester), contains('Create your new password'));

    // step 3: the password rules apply, then save → /login (→ dashboard)
    await tester.enterText(find.byType(TextFormField).at(0), 'weak');
    await tester.enterText(find.byType(TextFormField).at(1), 'weak');
    await tester.tap(find.byKey(const Key('fp-save')));
    await _settle(tester);
    expect(fake.newPassword, isNull);
    await tester.enterText(find.byType(TextFormField).at(0), 'NewPass#2026');
    await tester.enterText(find.byType(TextFormField).at(1), 'NewPass#2026');
    await tester.tap(find.byKey(const Key('fp-save')));
    await _settle(tester);
    expect(fake.newPassword, 'NewPass#2026');
    expect(find.text('LOGIN → DASHBOARD'), findsOneWidget);
  });

  testWidgets('an unknown number says so and stays on step 1', (tester) async {
    await _open(tester);
    await _type(tester, '0917 000 0001');
    await tester.tap(find.byKey(const Key('fp-send')));
    await _settle(tester);
    expect(find.text('No account uses that mobile number.'), findsOneWidget);
    expect(find.byKey(const Key('fp-send')), findsOneWidget);
  });
}
