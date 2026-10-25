import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/features/rider/data/rider_repository.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_earnings_breakdown.dart';

void main() {
  final now = DateTime.now();
  final records = [
    EarningRecord(method: 'cash', bookingType: 'transport', amount: 159.4, commission: 23.91, payout: 135.49, createdAt: now),
    EarningRecord(method: 'gcash', bookingType: 'food', amount: 463.8, commission: 5.85, payout: 457.95, createdAt: now),
    EarningRecord(method: 'wallet', bookingType: 'transport', amount: 30, commission: 0, payout: 30, createdAt: now),
    // last year: only counted under "All time"
    EarningRecord(method: 'cash', bookingType: 'parcel', amount: 100, commission: 15, payout: 85, createdAt: DateTime(now.year - 1, 1, 5)),
  ];

  Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

  testWidgets('splits earnings by cash / GCash / wallet for the chosen period', (tester) async {
    await tester.pumpWidget(wrap(PaymentSplitCard(records: records)));
    expect(find.text('₱135.49'), findsOneWidget); // this month's cash
    expect(find.text('₱457.95'), findsOneWidget);
    expect(find.text('₱30.00'), findsOneWidget);
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('₱220.49'), findsOneWidget); // 135.49 + last year's 85
    expect(find.text('2 trips · 31%'), findsOneWidget); // 220.49 of 708.44
  });

  testWidgets('records list every paid trip and filter by method', (tester) async {
    await tester.pumpWidget(wrap(EarningRecordsCard(records: records)));
    expect(find.text('+₱135.49'), findsOneWidget);
    expect(find.text('Fee from customer'), findsOneWidget); // the wallet ₱30 with no commission
    await tester.tap(find.text('GCash'));
    await tester.pumpAndSettle();
    expect(find.text('+₱457.95'), findsOneWidget);
    expect(find.text('+₱135.49'), findsNothing);
  });
}
