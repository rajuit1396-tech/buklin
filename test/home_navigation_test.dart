import 'dart:convert';
import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scenario in ['completed', 'restricted', 'payment', 'working']) {
    testWidgets('customer Home button: $scenario', (tester) async {
      final snapshot = {
        'page': 1,
        'selected': 1,
        'loading': 'Dyna',
        'operator': false,
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
            'status': scenario == 'working' ? 'working' : 'completed',
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
      if (scenario == 'completed') {
        expect(find.byTooltip('Home'), findsOneWidget);
        await tester.tap(find.byTooltip('Home'));
        await tester.pumpAndSettle();
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
