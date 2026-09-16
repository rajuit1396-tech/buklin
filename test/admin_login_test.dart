import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buklin/main.dart';

void main() {
  testWidgets('admin button opens login without management controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin panel'));
    await tester.pumpAndSettle();
    expect(find.text('Admin login'), findsOneWidget);
    expect(find.text('Username or email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Register an account'), findsNothing);
    expect(find.text('Manage balance'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
