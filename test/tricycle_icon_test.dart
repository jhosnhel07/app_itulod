import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/shared/widgets/tricycle_icon.dart';

void main() {
  testWidgets('tricycle icon draws the sidecar drawing at icon size', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: TricycleIcon(size: 20, color: Colors.blue))));
    final svg = find.byType(SvgPicture);
    expect(svg, findsOneWidget);
    expect(tester.getSize(svg), const Size(25, 20)); // FA-style 1.25 : 1
    expect(find.bySemanticsLabel('Tricycle'), findsOneWidget);
  });
}
