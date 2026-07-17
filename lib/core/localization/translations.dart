import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:hiddify/gen/translations.g.dart';

part 'translations.g.dart';

@Riverpod(keepAlive: true)
Future<Translations> translations(Ref ref) async {
  return await ref.watch(localePreferencesProvider).build();
}

final appDisplayNameProvider = Provider<String>((ref) {
  final translations = ref.watch(translationsProvider).requireValue;
  final environment = ref.watch(environmentProvider);
  return appDisplayName(translations, environment);
});

String appDisplayName(Translations translations, Environment environment) {
  return environment == Environment.dev ? translations.common.devAppTitle : translations.common.appTitle;
}
