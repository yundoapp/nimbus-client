import 'package:hiddify/core/localization/translations.dart';

/// Nimbus diagnostics intentionally support two Chinese variants and English.
/// Other app locales use English so a diagnostic never becomes a mixed-language
/// record when a translation is incomplete.
Translations nimbusDiagnosticsTranslations(Translations current) {
  return switch (current.$meta.locale) {
    AppLocale.zhCn || AppLocale.zhTw => current,
    _ => AppLocale.en.buildSync(),
  };
}
