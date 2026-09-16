import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Buklin work request flow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    await tester.pumpAndSettle();
    expect(find.text('BUKLIN'), findsOneWidget);
    expect(find.text('What equipment do you need?'), findsOneWidget);
    expect(find.text('5-finger excavator grapple'), findsOneWidget);
    expect(find.text('Next: loading vehicle'), findsOneWidget);
  });
}
