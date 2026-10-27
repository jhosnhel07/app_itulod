// The rider settles their balance with iTULOD (web sql/051): "You owe ₱X"
// with Pay with GCash and I paid the admin, a pending / rejected claim, what
// iTULOD owes them, ₱0.00 all settled, and the payments history.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_itulod/features/rider/data/rider_repository.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_balance_card.dart';

class _FakeRepo implements RiderRepository {
  final claims = <(double, String, String?)>[];
  @override
  Future<void> claimPayment({required double amount, required String method, String? reference}) async {
    if (amount > 650) throw Exception("That's more than you owe (₱650.00).");
    claims.add((amount, method, reference));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RiderBalance _bal(double net) => RiderBalance(
      onlineEarnings: 200,
      cashCommission: 850,
      payoutsMade: 0,
      collectionsMade: 0,
      net: net,
      codUnremitted: 0,
    );

Future<_FakeRepo> _open(WidgetTester tester, double net, {RiderSettling settling = const RiderSettling()}) async {
  final view = tester.view;
  view.physicalSize = const Size(400 * 3, 1400 * 3);
  view.devicePixelRatio = 3;
  addTearDown(view.resetPhysicalSize);
  addTearDown(view.resetDevicePixelRatio);
  final repo = _FakeRepo();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      riderRepositoryProvider.overrideWithValue(repo),
      riderBalanceProvider.overrideWith((ref) async => _bal(net)),
      riderSettlingProvider.overrideWith((ref) async => settling),
    ],
    child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RiderBalanceCard()))),
  ));
  await tester.pumpAndSettle();
  return repo;
}

String _headline(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('balance-headline'))).data!;

void main() {
  testWidgets('owes iTULOD: Pay with GCash and I paid the admin', (tester) async {
    await _open(tester, -650);
    expect(_headline(tester), 'You owe iTULOD ₱650.00');
    expect(find.text('Pay ₱650.00 with GCash'), findsOneWidget);
    expect(find.byKey(const Key('claim-payment')), findsOneWidget);
  });

  testWidgets('below ₱20: no GCash, pay the admin', (tester) async {
    await _open(tester, -15);
    expect(find.byKey(const Key('pay-dues')), findsNothing);
    expect(find.byKey(const Key('claim-payment')), findsOneWidget);
    expect(find.textContaining('GCash needs at least ₱20.00'), findsOneWidget);
  });

  testWidgets('I paid the admin: the form sends amount, method and reference', (tester) async {
    final repo = await _open(tester, -650);
    await tester.tap(find.byKey(const Key('claim-payment')));
    await tester.pumpAndSettle();
    expect(find.textContaining('You owe ₱650.00'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('claim-amount')), '700');
    await tester.tap(find.byKey(const Key('claim-send')));
    await tester.pumpAndSettle();
    expect(find.text("That's more than you owe (₱650.00)."), findsOneWidget);
    await tester.enterText(find.byKey(const Key('claim-amount')), '650');
    await tester.tap(find.text('GCash sent'));
    await tester.enterText(find.byKey(const Key('claim-reference')), '1009 223 4455');
    await tester.tap(find.byKey(const Key('claim-send')));
    await tester.pumpAndSettle();
    expect(repo.claims, [(650.0, 'gcash', '1009 223 4455')]);
    expect(find.text('Sent — the admin will confirm your payment.'), findsOneWidget);
  });

  testWidgets('waiting for the admin: no buttons, just the note', (tester) async {
    await _open(tester, -650,
        settling: const RiderSettling(claim: RiderClaim(amount: 650, method: 'cash', status: 'pending')));
    expect(find.textContaining('Waiting for the admin to confirm your ₱650.00 cash payment'), findsOneWidget);
    expect(find.byKey(const Key('pay-dues')), findsNothing);
    expect(find.byKey(const Key('claim-payment')), findsNothing);
  });

  testWidgets('rejected: the reason shows, and they can pay again', (tester) async {
    await _open(tester, -650,
        settling: RiderSettling(
            claim: RiderClaim(amount: 650, method: 'cash', status: 'rejected', rejectReason: 'No cash received', reviewedAt: DateTime(2026, 10, 27))));
    expect(find.textContaining("wasn't confirmed: No cash received"), findsOneWidget);
    expect(find.byKey(const Key('pay-dues')), findsOneWidget);
  });

  testWidgets('iTULOD owes the rider: the admin sends it', (tester) async {
    await _open(tester, 320);
    expect(_headline(tester), 'iTULOD owes you ₱320.00');
    expect(find.textContaining('The admin sends this to you'), findsOneWidget);
    expect(find.byKey(const Key('pay-dues')), findsNothing);
  });

  testWidgets('settled: ₱0.00 and the payments history', (tester) async {
    await _open(tester, 0,
        settling: RiderSettling(history: [
          RiderSettlement(payout: false, amount: 650, method: 'gcash', note: 'Paid by GCash in the app', createdAt: DateTime(2026, 10, 27, 10)),
          RiderSettlement(payout: true, amount: 120, method: 'gcash', createdAt: DateTime(2026, 10, 20, 9)),
        ]));
    expect(_headline(tester), '₱0.00 · All settled');
    await tester.tap(find.text('Payments with iTULOD (2)'));
    await tester.pumpAndSettle();
    expect(find.text('You paid by GCash'), findsOneWidget);
    expect(find.text('iTULOD sent you · GCash'), findsOneWidget);
    expect(find.text('−₱650.00'), findsOneWidget);
    expect(find.text('+₱120.00'), findsOneWidget);
  });

  test('a rejected claim stops showing once a later payment is recorded', () {
    final c = RiderClaim(amount: 100, method: 'cash', status: 'rejected', reviewedAt: DateTime(2026, 10, 26));
    expect(RiderSettling(claim: c).rejected, isNotNull);
    expect(
        RiderSettling(claim: c, history: [RiderSettlement(payout: false, amount: 100, method: 'gcash', createdAt: DateTime(2026, 10, 27))]).rejected,
        isNull);
  });
}
