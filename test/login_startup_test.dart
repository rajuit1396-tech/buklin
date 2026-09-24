import 'package:buklin/backend_api.dart';
import 'package:buklin/login_screen.dart';
import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default launch shows login without a saved session',
      (tester) async {
    BackendApi.instance.user = null;
    BackendApi.instance.token = null;
    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: backendUrl.isEmpty);
}
