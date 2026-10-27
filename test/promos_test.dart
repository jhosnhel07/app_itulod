// Promos (web sql/053): the discount rules, the picker on a booking form,
// My promos (claim / ready / used), the notification link, and how a promo
// shows to the customer and the rider (iTULOD pays it).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_itulod/features/promos/data/promo_repository.dart';
import 'package:app_itulod/features/promos/presentation/screens/my_promos_screen.dart';
import 'package:app_itulod/features/promos/presentation/widgets/promo_picker.dart';
import 'package:app_itulod/features/rider/data/rider_repository.dart';
import 'package:app_itulod/features/rider/presentation/widgets/rider_earnings_breakdown.dart';
import 'package:app_itulod/shared/models/booking_models.dart';

MyPromo _promo(String code, {String status = 'ready', String type = 'flat', double value = 30, double min = 100,
        List<String> services = const ['food', 'parcel'], DateTime? usedAt, String? usedType}) =>
    MyPromo(
      id: 'id-$code',
      code: code,
      title: code == 'FOOD30' ? '₱30 off food & parcels' : code,
      summary: '₱30.00 off food & parcels · min ₱100',
      discountType: type,
      discountValue: value,
      minFare: min,
      services: services,
      status: status,
      usedAt: usedAt,
      usedBookingType: usedType,
    );

class _FakePromos implements PromoRepository {
  final claims = <String>[];
  @override
  Future<String> claim({String? id, String? code}) async {
    claims.add(id ?? code ?? '');
    return code ?? 'FOOD30';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('discount rules (same as redeem-promo)', () {
    test('flat, percent, and never below the ₱20 minimum fare', () {
      expect(_promo('A').discountFor(150), 30);
      expect(_promo('B', type: 'percent', value: 10).discountFor(150), 15);
      expect(_promo('C', type: 'percent', value: 100).discountFor(200), 180);
      expect(_promo('D', value: 50).discountFor(40), 20);
      expect(_promo('E', value: 50).discountFor(20), 0);
    });

    test('usable only when ready, for this service, and the total is big enough', () {
      final p = _promo('FOOD30');
      expect(p.usableOn(BookingKind.parcel, 150), isTrue);
      expect(p.usableOn(BookingKind.parcel, 80), isFalse, reason: 'below min ₱100');
      expect(p.usableOn(BookingKind.transport, 150), isFalse, reason: 'not for rides');
      expect(_promo('USED', status: 'used').usableOn(BookingKind.parcel, 150), isFalse);
      expect(_promo('NEW', status: 'unclaimed').usableOn(BookingKind.parcel, 150), isFalse);
    });

    test('a promo notification links to My promos', () {
      expect(MyPromosScreen.forLink('promo/abc-123'), isNotNull);
      expect(MyPromosScreen.forLink('messages/food/x'), isNull);
      expect(MyPromosScreen.forLink(null), isNull);
    });
  });

  group('picker', () {
    Future<void> pump(WidgetTester tester, double fare, BookingKind kind, {List<MyPromo>? promos}) async {
      String? picked;
      await tester.pumpWidget(ProviderScope(
        overrides: [myPromosProvider.overrideWith((ref) async => promos ?? [_promo('FOOD30')])],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PromoPicker(
                kind: kind,
                fare: fare,
                selected: picked,
                onChanged: (c) => setState(() => picked = c),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    String note(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('promo-note'))).data!;

    testWidgets('below the minimum it says so', (tester) async {
      await pump(tester, 80, BookingKind.parcel);
      expect(note(tester), contains('needs a bigger total (min ₱100.00)'));
    });

    testWidgets('pick a promo → "You save ₱30.00 — new total ₱120.00"', (tester) async {
      await pump(tester, 150, BookingKind.parcel);
      expect(note(tester), '1 promo you can use on this booking.');
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('₱30 off food & parcels — save ₱30.00').last);
      await tester.pumpAndSettle();
      expect(note(tester), startsWith('You save ₱30.00 — new total ₱120.00'));
    });

    testWidgets('a food & parcel promo is not offered on a ride', (tester) async {
      await pump(tester, 300, BookingKind.transport);
      expect(note(tester), contains('No promos for rides yet'));
    });
  });

  group('My promos', () {
    testWidgets('new to claim, ready, and used', (tester) async {
      final fake = _FakePromos();
      final view = tester.view;
      view.physicalSize = const Size(400 * 3, 1400 * 3);
      view.devicePixelRatio = 3;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          promoRepositoryProvider.overrideWithValue(fake),
          myPromosProvider.overrideWith((ref) async => [
                _promo('FOOD30'),
                _promo('NEW10', status: 'unclaimed'),
                _promo('OLD', status: 'used', usedAt: DateTime(2026, 10, 20, 9), usedType: 'parcel'),
              ]),
        ],
        child: const MaterialApp(home: MyPromosScreen(focusId: 'id-NEW10')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Ready to use'), findsOneWidget);
      expect(find.text('New — claim it'), findsOneWidget);
      expect(find.textContaining('Used on Parcel'), findsOneWidget);
      await tester.tap(find.byKey(const Key('promo-claim-NEW10')));
      await tester.pumpAndSettle();
      expect(fake.claims, ['id-NEW10']);
      await tester.enterText(find.byKey(const Key('my-promos-code')), 'welcome10');
      await tester.tap(find.byKey(const Key('my-promos-claim')));
      await tester.pumpAndSettle();
      expect(fake.claims.last, 'welcome10');
    });
  });

  testWidgets("rider's earnings record shows the promo iTULOD paid", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EarningRecordsCard(records: [
            EarningRecord(method: 'cash', bookingType: 'parcel', amount: 134.4, commission: 24.66, payout: 139.74, promo: 30, createdAt: DateTime.now()),
          ]),
        ),
      ),
    ));
    expect(find.text('+₱139.74'), findsOneWidget);
    expect(find.text('Paid ₱134.40'), findsOneWidget);
    expect(find.text('+₱30.00 promo by iTULOD'), findsOneWidget);
    expect(find.text('−₱24.66 commission'), findsOneWidget);
  });
}
