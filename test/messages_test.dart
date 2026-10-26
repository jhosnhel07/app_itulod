// Messages (web js/messages.js, sql/046): the list with Active / Past and
// unread counts, and a chat with quick replies, "Seen" and the read-only
// state of a finished trip.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Session, User;

import 'package:app_itulod/features/auth/data/auth_repository.dart';
import 'package:app_itulod/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_itulod/features/chat/data/chat_model.dart';
import 'package:app_itulod/features/chat/data/chat_repository.dart';
import 'package:app_itulod/features/chat/presentation/providers/chat_provider.dart';
import 'package:app_itulod/features/chat/presentation/screens/chat_screen.dart';
import 'package:app_itulod/features/chat/presentation/screens/messages_screen.dart';
import 'package:app_itulod/shared/models/booking_models.dart';
import 'package:app_itulod/shared/models/profile_model.dart';

class _NoAuthRepo implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  User? get currentUser => null;
  @override
  Session? get currentSession => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthNotifier _signedIn(String id) {
  // ignore: invalid_use_of_protected_member
  return AuthNotifier(_NoAuthRepo())..state = AppAuthState(
      status: AuthStatus.authenticated,
      profile: ProfileModel(id: id, fullName: 'Maria Santos', email: 'maria@example.com'));
}

/// Records what the chat sends; no network.
class _FakeChat implements ChatRepository {
  final sent = <String>[];
  int reads = 0;
  @override
  Future<void> markRead(String bookingType, String bookingId) async => reads++;
  @override
  Future<Map<String, String>> signPhotos(List<String> paths) async => {};
  @override
  Future<void> sendMessage({required String bookingType, required String bookingId, required String senderId,
      String body = '', String? imagePath}) async => sent.add(body);
  @override
  Future<void> sendPhoto({required String bookingType, required String bookingId, required String senderId,
      required File file}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _now = DateTime.now();
Conversation _convo({required String id, required bool active, int unread = 0, String? last}) => Conversation(
      bookingType: 'transport',
      bookingId: id,
      status: active ? 'accepted' : 'completed',
      iAm: 'customer',
      otherId: 'rider-1',
      otherName: 'Juan Dela Cruz',
      otherPhone: active ? '09181112222' : null,
      vehicle: 'Motorcycle · ABC 1234',
      route: 'Laoag City Hall → Batac Public Market',
      lastBody: last,
      lastAt: last == null ? null : _now,
      unread: unread,
      canSend: active,
      sortAt: _now,
    );

Widget _app(Widget home, {List<Conversation> list = const [], List<ChatMessage> messages = const [],
    DateTime? otherRead, _FakeChat? chat}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith((ref) => _signedIn('me')),
      conversationsProvider.overrideWith((ref) => Stream.value(list)),
      chatMessagesProvider.overrideWith((ref, key) => Stream.value(messages)),
      otherReadProvider.overrideWith((ref, key) => Stream.value(otherRead)),
      chatRepositoryProvider.overrideWithValue(chat ?? _FakeChat()),
    ],
    child: MaterialApp(home: home),
  );
}

void main() {
  // phone size, so a header or chip row that overflows fails the test
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(390 * 3, 844 * 3);
    view.devicePixelRatio = 3;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('list: Active and Past, unread count and the last message', (tester) async {
    final list = [
      _convo(id: 'b1', active: true, unread: 2, last: 'On my way'),
      _convo(id: 'b2', active: false, last: 'Thanks!'),
    ];
    await tester.pumpWidget(_app(const Scaffold(body: MessagesView()), list: list));
    await tester.pump();
    await tester.pump();

    expect(find.text('Juan Dela Cruz'), findsOneWidget); // only the active one
    expect(find.text('On my way'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('Ride · Laoag City Hall'), findsOneWidget);

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.text('Thanks!'), findsOneWidget);
    expect(find.text('On my way'), findsNothing);
  });

  testWidgets('chat: header, quick reply sends, "Seen" under my last message', (tester) async {
    final chat = _FakeChat();
    final c = _convo(id: 'b1', active: true);
    final t = _now.subtract(const Duration(minutes: 5));
    final messages = [
      ChatMessage(id: 'm1', bookingType: 'transport', bookingId: 'b1', senderId: 'me', body: 'I am at the gate', createdAt: t),
      ChatMessage(id: 'm2', bookingType: 'transport', bookingId: 'b1', senderId: 'rider-1', body: 'Coming', createdAt: t.add(const Duration(minutes: 1))),
      ChatMessage(id: 'm3', bookingType: 'transport', bookingId: 'b1', senderId: 'me', body: 'Thanks', createdAt: t.add(const Duration(minutes: 2))),
    ];
    await tester.pumpWidget(_app(
      ChatScreen(kind: BookingKind.transport, bookingId: 'b1', conversation: c),
      list: [c], messages: messages, otherRead: t.add(const Duration(minutes: 3)), chat: chat,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.textContaining('Motorcycle · ABC 1234'), findsOneWidget);
    expect(find.byTooltip('Call Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Seen'), findsOneWidget);
    expect(chat.reads, greaterThan(0)); // opened → marked read

    await tester.tap(find.text("I'm at the pickup point"));
    await tester.pump();
    expect(chat.sent, ["I'm at the pickup point"]);
  });

  testWidgets('a finished trip is read-only, with no Call', (tester) async {
    final c = _convo(id: 'b2', active: false, last: 'Thanks!');
    await tester.pumpWidget(_app(
      ChatScreen(kind: BookingKind.transport, bookingId: 'b2', canSend: false, conversation: c),
      list: [c],
      messages: [ChatMessage(id: 'm1', bookingType: 'transport', bookingId: 'b2', senderId: 'rider-1', body: 'Thanks!', createdAt: _now)],
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Call Juan Dela Cruz'), findsNothing);
  });

  test('a notification link opens the right chat', () {
    expect(ChatScreen.forLink('messages/transport/abc-123'), isNotNull);
    expect(ChatScreen.forLink('messages/hauling/abc'), isNotNull);
    expect(ChatScreen.forLink('messages/nope/abc'), isNull);
    expect(ChatScreen.forLink('history'), isNull);
    expect(ChatScreen.forLink(null), isNull);
  });
}
