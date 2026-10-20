import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/shared/widgets/booking_stepper.dart';

void main() {
  Widget host({required VoidCallback onFinish, bool summary = true, TextEditingController? pickup}) => MaterialApp(
        home: Scaffold(
          body: BookingStepper(
            fare: '₱187.00',
            finishLabel: 'Book it',
            onFinish: onFinish,
            summary: summary ? () => [('Pickup', 'Laoag City Hall'), ('Estimated fare', '₱187.00')] : null,
            steps: [
              BookingStep('Where', [
                TextFormField(
                  key: const Key('pickup'),
                  controller: pickup,
                  validator: (v) => (v ?? '').isEmpty ? 'Set a pickup' : null,
                ),
              ]),
              const BookingStep('Vehicle', [Text('vehicle step')]),
            ],
          ),
        ),
      );

  testWidgets('Next checks the fields on the step, then moves on', (tester) async {
    var finished = 0;
    await tester.pumpWidget(host(onFinish: () => finished++));
    expect(find.text('₱187.00'), findsOneWidget); // fare in the header
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Set a pickup'), findsOneWidget);
    expect(find.text('vehicle step').hitTestable(), findsNothing);

    await tester.enterText(find.byKey(const Key('pickup')), 'Laoag City Hall');
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('vehicle step').hitTestable(), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Check your booking'), findsOneWidget);
    expect(find.text('Laoag City Hall'), findsWidgets);
    await tester.tap(find.text('Book it'));
    await tester.pump();
    expect(finished, 1);

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text('vehicle step').hitTestable(), findsOneWidget);
  });

  testWidgets('without a summary the last real step finishes (ride)', (tester) async {
    var finished = 0;
    await tester.pumpWidget(host(onFinish: () => finished++, summary: false));
    await tester.enterText(find.byKey(const Key('pickup')), 'Laoag');
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Book it'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget); // the next screen's dot
    await tester.tap(find.text('Book it'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('finish jumps back to a step whose field is now empty', (tester) async {
    var finished = 0;
    final pickup = TextEditingController();
    await tester.pumpWidget(host(onFinish: () => finished++, summary: false, pickup: pickup));
    await tester.enterText(find.byKey(const Key('pickup')), 'Laoag');
    await tester.tap(find.text('Next'));
    await tester.pump();
    pickup.clear(); // e.g. the address was cleared while on a later step
    await tester.tap(find.text('Book it'));
    await tester.pumpAndSettle();
    expect(finished, 0);
    expect(find.text('Set a pickup').hitTestable(), findsOneWidget);
  });
}
