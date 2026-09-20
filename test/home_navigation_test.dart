import 'dart:convert';
import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('only customer work closing triggers automatic Home navigation', () {
    final previous = <Map<String, dynamic>>[
      {'id': 'job', 'customer_id': 'customer', 'status': 'requested'}
    ];
    for (final status in ['completed', 'cancelled']) {
      final next = <Map<String, dynamic>>[
        {'id': 'job', 'customer_id': 'customer', 'status': status}
      ];
      expect(
          closedCustomerWorkStatus(previous, next,
              operator: false, customerId: 'customer'),
          status);
      expect(
          closedCustomerWorkStatus(previous, next,
              operator: true, customerId: 'customer'),
          isNull);
      expect(
          closedCustomerWorkStatus(previous, next,
              operator: false, customerId: 'another-customer'),
          isNull);
      expect(
          closedCustomerWorkStatus(next, next,
              operator: false, customerId: 'customer'),
          isNull);
    }
  });
  for (final scenario in [
    'completed',
    'restricted',
    'payment',
    'working',
    'cancel_customer',
    'cancel_operator'
  ]) {
    testWidgets('customer Home button: $scenario', (tester) async {
      final snapshot = {
        'page': 1,
        'selected': 1,
        'loading': 'Dyna',
        'operator': scenario == 'cancel_operator',
        'online': false,
        'balance': scenario == 'payment' ? -20 : 0,
        'blocked': null,
        'hidden': [],
        'demoBlocks': {
          if (scenario == 'restricted')
            'false':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        },
        'fields': ['250', '', '', '', ''],
        'jobs': [
          {
            'id': 'finished-job',
            'customer_id': 'demo-customer',
            'operator_id': 'demo-operator',
            'status': scenario.startsWith('cancel_')
                ? 'accepted'
                : scenario == 'working'
                    ? 'working'
                    : 'completed',
            'service': 'Pickup van',
            'address': 'Saved work site',
            'details': 'Saved work details',
            'loading_vehicle': 'Dyna',
          }
        ],
      };
      SharedPreferences.setMockInitialValues(
          {'work-demo': jsonEncode(snapshot)});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(MaterialApp(home: WorkApp(preferences: prefs)));
      await tester.pumpAndSettle();
      if (scenario.startsWith('cancel_')) {
        await tester.scrollUntilVisible(find.text('Cancel work'), 250,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel work'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Cancel work')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Home'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final saved = jsonDecode(prefs.getString('work-demo')!);
        expect(saved['page'], scenario == 'cancel_customer' ? 0 : 1);
        expect(saved['jobs'][0]['status'], 'cancelled');
        expect(saved['demoBlocks'], isNotEmpty);
      } else if (scenario == 'completed') {
        expect(find.byTooltip('Home'), findsOneWidget);
        await tester.tap(find.byTooltip('Home'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Step 1 of 3'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Step 1 of 3'), findsOneWidget);
        final saved = jsonDecode(prefs.getString('work-demo')!);
        expect(saved['page'], 0);
        expect(saved['loading'], isNull);
        expect(saved['fields'], everyElement(isEmpty));
        expect(saved['jobs'][0]['status'], 'completed');
      } else {
        expect(find.byTooltip('Home'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
