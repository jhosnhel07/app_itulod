// The receipt that pops up after paying (web payment-return.html): it shows
// the receipt at once and asks the server to settle the payment, so a GCash
// payment that was just authorized turns Paid by itself.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_itulod/features/customer/data/customer_repository.dart';
import 'package:app_itulod/features/customer/presentation/widgets/payment_receipt_dialog.dart';

/// Pending until the server is asked [paidAfter] times; no network.
class _FakeRepo implements CustomerRepository {
  final Map<String, dynamic> row;
  final int paidAfter;
  int syncs = 0;
  _FakeRepo(this.row, {this.paidAfter = 1});

  String get _status => syncs >= paidAfter ? 'paid' : 'pending';

  @override
  Future<String?> syncPayment(String type, String id) async {
    syncs++;
    return _status;
  }

  @override
  Future<Map<String, dynamic>?> fetchPaymentReceipt(String type, String id) async =>
      {...row, 'payment_status': syncs == 0 ? 'pending' : _status};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ride = {
  'payment_method': 'gcash',
  'paymongo_reference': 'src_test123',
  'estimated_fare': 178,
  'created_at': '2026-10-27T03:00:00Z',
  'pickup_address': 'Laoag City Hall',
  'destination_address': 'Batac Public Market',
};

Future<void> _open(WidgetTester tester, _FakeRepo repo, {String type = 'transport', bool failed = false}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [customerRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPaymentReceipt(context, type: type, id: 'abcdef12-3456', failed: failed),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pump();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('an authorized GCash payment turns Paid by itself', (tester) async {
    final repo = _FakeRepo(_ride, paidAfter: 2);
    await _open(tester, repo);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Awaiting confirmation'), findsOneWidget); // receipt shows straight away

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(_text(tester, 'receipt-title'), 'Payment successful!');
    expect(find.text('Paid'), findsOneWidget);
    expect(_text(tester, 'receipt-amount'), contains('178.00'));
    expect(find.text('Laoag City Hall → Batac Public Market'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('#abcdef12'), findsOneWidget);
    expect(repo.syncs, 2);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentReceiptDialog), findsNothing);
  });

  testWidgets('sent back through "failed": says so, without asking the server', (tester) async {
    final repo = _FakeRepo(_ride);
    await _open(tester, repo, failed: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_text(tester, 'receipt-title'), 'Payment did not go through');
    expect(find.text('Failed'), findsOneWidget);
    expect(repo.syncs, 0);
  });

  testWidgets('wallet top-up: Top-up row, no route', (tester) async {
    final repo = _FakeRepo({
      'payment_method': 'gcash',
      'paymongo_reference': 'src_wallet1',
      'estimated_fare': 150,
      'created_at': '2026-10-27T03:00:00Z',
    });
    await _open(tester, repo, type: 'wallet');
    await tester.pump(const Duration(seconds: 2));
    expect(_text(tester, 'receipt-title'), 'Payment successful!');
    expect(find.text('Top-up'), findsOneWidget);
    expect(find.text('Route'), findsNothing);
    expect(_text(tester, 'receipt-amount'), contains('150.00'));
  });
}
