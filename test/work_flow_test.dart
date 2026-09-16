import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buklin/main.dart';
import 'package:buklin/work_location.dart';

void main() {
  test('offer requires a whole Riyal amount from 30 to 999', () {
    for (final value in ['', '0', '-1', 'NaN', 'Infinity', '10.123', '1e3', '29', '1000', '250.50', '007', '030']) {
      expect(amountError(value), isNotNull);
    }
    for (final value in ['30', '99', '100', '150', '250', '999']) {
      expect(amountError(value), isNull);
    }
  });
  test('GPS coordinates reject invalid and non-finite values', () {
    for (final value in ['', 'abc', 'NaN', 'Infinity', '91', '-91']) {
      expect(coordinateError(value, 90), isNotNull);
    }
    expect(coordinateError('0', 90), isNull);
    expect(coordinateError('-90', 90), isNull);
    expect(coordinateError('180', 180), isNull);
  });

  testWidgets('loading vehicle is required and the form preserves page selections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    await tester.pumpAndSettle();
    final next = find.text('Next: loading vehicle');
    await tester.scrollUntilVisible(next, 300);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Dyna'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Inside store'), findsOneWidget);
    expect(find.text('Add vehicle to my list'), findsNothing);
    final continueButton = find.widgetWithText(FilledButton, 'Next: work location');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    await tester.tap(find.text('Trailer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Enter 30–999 Riyal'), findsOneWidget);
    expect(find.text('Riyal'), findsOneWidget);
    final amount = find.widgetWithText(TextFormField, 'Amount you want to give');
    await tester.enterText(amount, '12345');
    expect(tester.widget<TextFormField>(amount).controller!.text, '123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount you want to give'), '250');
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Where is the work?'), findsOneWidget);
    expect(find.textContaining('Trailer'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Search for an operator'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Search for an operator'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(TextFormField, 'Store number'), -250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Enter exactly 3 digits'), findsOneWidget);
    final store = find.widgetWithText(TextFormField, 'Store number');
    await tester.enterText(store, '0a0712');
    expect(tester.widget<TextFormField>(store).controller!.text, '007');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
  });
}



