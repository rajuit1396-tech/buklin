import 'dart:convert';

import 'package:buklin/backend_api.dart';
import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('successful refresh clears a connection warning', (tester) async {
    final db = BackendApi.instance;
    db.user = null;
    db.token = null;
    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    final dynamic state = tester.state(find.byType(WorkApp));
    db.user = {'id': 'customer', 'role': 'customer', 'username': 'customer_one'};
    db.token = 'test-session';
    try {
      await http.runWithClient(
        () => state.refresh() as Future<void>,
        () => MockClient((_) async => throw http.ClientException('Offline')),
      );
      await tester.pump();
      expect(find.text(connectionWarning), findsOneWidget);

      Future<void> recover() => http.runWithClient(
            () => state.refresh() as Future<void>,
            () => MockClient((_) async => http.Response(
                jsonEncode({'jobs': [], 'balance': 12}), 200)),
          );
      await recover();
      await tester.pump();
      expect(find.text(connectionWarning), findsNothing);
      expect(find.text('Your balance: 12 Riyal'), findsOneWidget);

      state.setState(() => state.message = 'Work completed.');
      await recover();
      expect(state.message, 'Work completed.');
    } finally {
      await tester.pumpWidget(const SizedBox());
      db.user = null;
      db.token = null;
    }
  }, skip: !live);
}
