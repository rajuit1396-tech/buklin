import 'dart:convert';
import 'package:buklin/app_language.dart';
import 'package:buklin/login_screen.dart';
import 'package:buklin/main.dart';
import 'package:buklin/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> chooseLanguage(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('language-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, name));
  await tester.pumpAndSettle();
}

void main() {
  test('all translations retain every interpolation value', () {
    final placeholders = RegExp(r'\{\w+\}');
    for (final entry in translations.entries) {
      expect(entry.value, hasLength(3), reason: entry.key);
      final expected =
          placeholders.allMatches(entry.key).map((m) => m[0]).toSet();
      for (final translation in entry.value) {
        expect(translation.trim(), isNotEmpty, reason: entry.key);
        expect(placeholders.allMatches(translation).map((m) => m[0]).toSet(),
            expected,
            reason: entry.key);
      }
    }
    expect(translate('bn', 'Customer offer: {amount} Riyal', {'amount': 250}),
        'গ্রাহকের প্রস্তাব: 250 রিয়াল');
    expect(translate('ur', 'Unknown server message'), 'Unknown server message');
  });

  test('unsupported saved language falls back to English', () async {
    SharedPreferences.setMockInitialValues({'buklin-language': 'unknown'});
    final controller =
        LanguageController(await SharedPreferences.getInstance());
    expect(controller.code, 'en');
    await controller.select('unsupported');
    expect(controller.code, 'en');
    controller.dispose();
  });

  testWidgets('sign-in language switches in place with Urdu RTL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller =
        LanguageController(await SharedPreferences.getInstance());
    final username = TextEditingController(text: 'operator@example.com');
    final password = TextEditingController(text: 'keep-this-password');
    addTearDown(controller.dispose);
    addTearDown(username.dispose);
    addTearDown(password.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguage(
        controller: controller,
        child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => MaterialApp(
                locale: Locale(controller.code),
                supportedLocales:
                    languageNames.keys.map((code) => Locale(code)),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: LoginScreen(
                    username: username,
                    password: password,
                    role: 'operator',
                    busy: false,
                    message: null,
                    onRoleChanged: (_) {},
                    onSubmit: () {})))));
    await tester.pumpAndSettle();
    for (final code in ['bn', 'ur', 'hi', 'en']) {
      await chooseLanguage(tester, languageNames[code]!);
      expect(find.text(translate(code, 'Welcome back')), findsOneWidget);
      expect(find.text(translate(code, 'Username or email')), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(LoginScreen))),
          code == 'ur' ? TextDirection.rtl : TextDirection.ltr);
      expect(username.text, 'operator@example.com');
      expect(password.text, 'keep-this-password');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('language persists across restart without losing customer draft',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(BuklinApp(preferences: preferences));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next: loading vehicle'), 300);
    await tester.tap(find.text('Next: loading vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trailer'));
    await tester.enterText(find.byType(TextFormField), '350');
    await chooseLanguage(tester, 'বাংলা');
    expect(find.text('৩ ধাপের মধ্যে ধাপ 2'), findsOneWidget);
    expect(find.text('ট্রেলার'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '350');
    expect(preferences.getString('buklin-language'), 'bn');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(BuklinApp(preferences: preferences));
    await tester.pumpAndSettle();
    expect(find.text('৩ ধাপের মধ্যে ধাপ 2'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '350');
    expect(
        jsonDecode(preferences.getString('work-demo')!)['loading'], 'Trailer');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'operator stays online while changing language and can switch off',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'work-demo': jsonEncode({
        'page': 0,
        'selected': 0,
        'loading': null,
        'operator': true,
        'online': true,
        'balance': 0,
        'blocked': null,
        'hidden': [],
        'demoBlocks': {},
        'fields': ['', '', '', '', ''],
        'jobs': [],
      })
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(BuklinApp(preferences: preferences));
    await tester.pumpAndSettle();
    await chooseLanguage(tester, 'اردو');
    expect(find.text('آن لائن • درخواستیں موصول ہو رہی ہیں'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('آپ آف لائن ہیں'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
