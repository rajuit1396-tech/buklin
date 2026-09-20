import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations.dart';

const languageNames = {
  'en': 'English',
  'bn': 'বাংলা',
  'ur': 'اردو',
  'hi': 'हिन्दी',
};

class LanguageController extends ChangeNotifier {
  LanguageController(this.preferences) {
    final saved = preferences.getString(preferenceKey);
    code = languageNames.containsKey(saved) ? saved! : 'en';
  }

  static const preferenceKey = 'buklin-language';
  final SharedPreferences preferences;
  late String code;

  Future<void> select(String value) async {
    if (!languageNames.containsKey(value) || value == code) return;
    code = value;
    notifyListeners();
    await preferences.setString(preferenceKey, value);
  }
}

class AppLanguage extends InheritedNotifier<LanguageController> {
  const AppLanguage(
      {super.key, required LanguageController controller, required super.child})
      : super(notifier: controller);

  static LanguageController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguage>()?.notifier;
}

String translate(String code, String source,
    [Map<String, Object?> values = const {}]) {
  // Normalize known server messages without changing the English API contract.
  if (code != 'en') {
    if (source.startsWith('Exception: ')) {
      source = source.substring('Exception: '.length);
    }
    source = const {
          'Contact admin to assign your work location.':
              'Contact admin to assign your work location',
          'Contact admin to assign your account location.':
              'Contact admin to assign your work location',
          'Contact admin to assign your account store number.':
              'Contact admin to assign your store number',
          'Approved operator account required': 'Operator account required',
          'Request unavailable': 'Request no longer available',
          'Payment required. Pay your balance to receive new requests.':
              'Payment required. Pay your balance before receiving new requests.',
        }[source] ??
        source;
    for (final prefix in [
      'Work is paused until ',
      'New requests are paused until '
    ]) {
      if (source.startsWith(prefix) && source != '${prefix}{time}') {
        return translate(
            code, '${prefix}{time}', {'time': source.substring(prefix.length)});
      }
    }
  }
  final index = const {'bn': 0, 'ur': 1, 'hi': 2}[code];
  final text = index == null ? source : translations[source]?[index] ?? source;
  return text.replaceAllMapped(RegExp(r'\{(\w+)\}'),
      (match) => values[match[1]]?.toString() ?? match[0]!);
}

String tr(BuildContext context, String source,
        [Map<String, Object?> values = const {}]) =>
    translate(AppLanguage.of(context)?.code ?? 'en', source, values);

/// Only app-owned copy goes through this widget. User content stays unchanged.
class AppText extends StatelessWidget {
  const AppText(this.data,
      {super.key, this.style, this.textAlign, this.values = const {}});
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context) =>
      Text(tr(context, data, values), style: style, textAlign: textAlign);
}

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppLanguage.of(context);
    if (controller == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      key: const ValueKey('language-selector'),
      tooltip: tr(context, 'Language'),
      icon: const Icon(Icons.language),
      initialValue: controller.code,
      onSelected: controller.select,
      itemBuilder: (_) => languageNames.entries
          .map((entry) => CheckedPopupMenuItem<String>(
                value: entry.key,
                checked: controller.code == entry.key,
                child: Text(entry.value,
                    textDirection: entry.key == 'ur'
                        ? TextDirection.rtl
                        : TextDirection.ltr),
              ))
          .toList(),
    );
  }
}
