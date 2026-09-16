import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buklin/main.dart';

void main() {
  testWidgets('mobile app has no admin entry points', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    await tester.pumpAndSettle();
    expect(find.text('Admin panel'), findsNothing);
    expect(find.text('Admin login'), findsNothing);
  });
}
