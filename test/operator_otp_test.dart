import 'package:buklin/backend_api.dart';
import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('incorrect operator OTP keeps the input dialog open',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => FilledButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => OperatorOtpDialog(
                            onVerify: (_) async => throw const ApiException(
                                'Incorrect four-digit customer OTP'))),
                    child: const Text('Open'))))));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1234');
    await tester.tap(find.text('Verify and start'));
    await tester.pumpAndSettle();

    expect(find.text('Enter customer OTP'), findsOneWidget);
    expect(find.text('Incorrect four-digit customer OTP'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
  });
}
