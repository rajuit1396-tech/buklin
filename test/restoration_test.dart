import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buklin/main.dart';

void main() {
  testWidgets('customer draft survives closing and reopening the app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: WorkApp(preferences: prefs)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next: loading vehicle'), 300);
    await tester.tap(find.text('Next: loading vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trailer'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount you want to give'), '350');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: WorkApp(preferences: prefs)));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField,
      'Amount you want to give')).controller!.text, '350');
    final saved = jsonDecode(prefs.getString('work-demo')!);
    expect(saved['loading'], 'Trailer');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('active work stays active after reopening', (tester) async {
    final snapshot = {'page': 2, 'selected': 1, 'loading': 'Dyna', 'operator': false,
      'online': false, 'balance': 0, 'blocked': null, 'hidden': [], 'demoBlocks': {},
      'fields': ['250', '007', '', '', '', ''],
      'jobs': [{'id': 'saved-job', 'customer_id': 'demo-customer',
        'operator_id': 'demo-operator', 'status': 'working', 'service': 'Pickup van',
        'address': 'Saved work site', 'details': 'Saved work details', 'loading_vehicle': 'Dyna'}]};
    SharedPreferences.setMockInitialValues({'work-demo': jsonEncode(snapshot)});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(home: WorkApp(preferences: prefs)));
    await tester.pumpAndSettle();
    expect(find.text('Work in progress'), findsOneWidget);
    expect(find.text('Step 3 of 3'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('work-demo')!)['jobs'][0]['status'], 'working');
  });
}
