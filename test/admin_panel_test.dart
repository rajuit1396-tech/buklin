import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buklin/admin_panel.dart';

void main() {
  testWidgets('admin requires operator machine and omits it for customers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AdminPanel(demo: true)));
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Customer One');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '+966501234567');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'customer_one');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'StrongPassword123');
    await tester.tap(find.text('Create operator'));
    await tester.pumpAndSettle();
    expect(find.text('Select one machine'), findsOneWidget);
    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();
    expect(find.text('Assigned machine'), findsNothing);
    await tester.tap(find.text('Create customer'));
    await tester.pumpAndSettle();
    expect(find.text('Customer One'), findsOneWidget);
    expect(find.textContaining('cannot sign in'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Password')).controller!.text, '');
    expect(find.textContaining('Machine:'), findsNothing);
  });
}
