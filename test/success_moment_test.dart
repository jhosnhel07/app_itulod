import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/shared/widgets/success_moment.dart';

void main() {
  testWidgets('success moment shows, then closes by itself', (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => TextButton(
      onPressed: () async { await showSuccessMoment(ctx, title: 'Ride booked!', message: 'Waiting for a rider to accept.'); closed = true; },
      child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Ride booked!'), findsOneWidget);
    expect(find.text('Waiting for a rider to accept.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Ride booked!'), findsNothing);
    expect(closed, isTrue);
  });
  testWidgets('OK closes it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => TextButton(
      onPressed: () => showSuccessMoment(ctx, title: 'Trip complete!'), child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Trip complete!'), findsNothing);
  });
}
