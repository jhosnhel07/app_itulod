import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/features/rider/data/rider_repository.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_balance_card.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_earnings_breakdown.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_earnings_tab.dart';

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
    await tester.tap(find.widgetWithText(ChoiceChip, 'GCash'));
    await tester.pumpAndSettle();
    expect(find.text('+₱457.95'), findsOneWidget);
    expect(find.text('+₱135.49'), findsNothing);
  });

  testWidgets('records: 20 at a time, then Show more', (tester) async {
    final many = [
      for (var i = 0; i < 26; i++)
        EarningRecord(method: 'cash', bookingType: 'transport', amount: 100, commission: 15, payout: 85 + i.toDouble(), createdAt: now.subtract(Duration(days: i))),
    ];
    await tester.pumpWidget(wrap(EarningRecordsCard(records: many)));
    expect(find.text('Showing 20 of 26'), findsOneWidget);
    expect(find.text('−₱15.00 commission'), findsNWidgets(20));
    await tester.ensureVisible(find.byKey(const Key('records-more')));
    await tester.tap(find.byKey(const Key('records-more')));
    await tester.pumpAndSettle();
    expect(find.text('−₱15.00 commission'), findsNWidgets(26));
    expect(find.byKey(const Key('records-more')), findsNothing);
  });

  testWidgets('Earnings tab: totals with trips → balance with iTULOD → 7 days → by method → records', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(400 * 3, 3000 * 3);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        riderEarningsProvider.overrideWith((ref) async => RiderEarnings(
              last7Days: const [0, 0, 0, 0, 0, 0, 0],
              records: records,
            )),
        riderBalanceProvider.overrideWith((ref) async => null),
        riderSettlingProvider.overrideWith((ref) async => const RiderSettling()),
      ],
      child: const MaterialApp(home: Scaffold(body: RiderEarningsTab())),
    ));
    await tester.pumpAndSettle();
    // all time: every paid trip; this month: not last year's
    expect(find.text('All time'), findsWidgets);
    expect(find.text('₱708.44'), findsOneWidget);
    expect(find.text('4 trips'), findsOneWidget);
    expect(find.text('₱623.44'), findsWidgets); // this month (and week / today: all three are now)
    expect(find.text('Rating'), findsNothing);
    double y(Finder f) => tester.getTopLeft(f.first).dy;
    expect(y(find.byKey(const Key('earn-summary'))) < y(find.text('Balance with iTULOD')), isTrue);
    expect(y(find.text('Balance with iTULOD')) < y(find.text('Last 7 days')), isTrue);
    expect(y(find.text('Last 7 days')) < y(find.text('Earnings by payment method')), isTrue);
    expect(y(find.text('Earnings by payment method')) < y(find.text('Earnings records')), isTrue);
    expect(find.textContaining('₱0.00 in the last 7 days'), findsOneWidget);
  });
}
