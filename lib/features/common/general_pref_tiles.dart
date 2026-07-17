import 'package:flutter/material.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LocalePrefTile extends ConsumerWidget {
  const LocalePrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final locale = ref.watch(localePreferencesProvider);
    return ListTile(
      title: Text(t.pages.settings.general.locale),
      subtitle: Text(locale.localeName),
      leading: const Icon(Icons.translate_rounded),
      trailing: shouldOpenGeneralChoiceAsPage(isMobilePlatform: PlatformUtils.isMobile)
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: () async {
        final AppLocale? selectedLocale;
        if (shouldOpenGeneralChoiceAsPage(isMobilePlatform: PlatformUtils.isMobile)) {
          final navigator = Navigator.of(context);
          selectedLocale = await navigator.push<AppLocale>(
            MaterialPageRoute(
              builder: (_) => _SettingsSelectionPage<AppLocale>(
                title: t.pages.settings.general.locale,
                selected: locale,
                options: AppLocale.values,
                getTitle: (e) => e.localeName,
                onReset: () => ref.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en),
              ),
            ),
          );
        } else {
          selectedLocale = await ref
              .read(dialogNotifierProvider.notifier)
              .showSettingPicker<AppLocale>(
                title: t.pages.settings.general.locale,
                selected: locale,
                onReset: () => ref.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en),
                options: AppLocale.values,
                getTitle: (e) => e.localeName,
              );
        }
        if (selectedLocale != null) {
          await ref.read(localePreferencesProvider.notifier).changeLocale(selectedLocale);
        }
      },
    );
  }
}

class _SettingsSelectionPage<T> extends ConsumerWidget {
  const _SettingsSelectionPage({
    required this.title,
    required this.selected,
    required this.options,
    required this.getTitle,
    this.onReset,
  });

  final String title;
  final T selected;
  final List<T> options;
  final String Function(T e) getTitle;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onReset != null)
            TextButton(
              onPressed: () {
                onReset!();
                Navigator.of(context).pop();
              },
              child: Text(t.common.reset),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: options.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final option = options[index];
            final isSelected = option == selected;
            return ListTile(
              title: Text(getTitle(option)),
              trailing: isSelected ? Icon(Icons.check_rounded, color: theme.colorScheme.primary) : null,
              onTap: () => Navigator.of(context).pop(option),
            );
          },
        ),
      ),
    );
  }
}

class EnableAnalyticsPrefTile extends ConsumerWidget {
  const EnableAnalyticsPrefTile({super.key, this.onChanged});

  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final enabled = ref.watch(analyticsControllerProvider).requireValue;

    return SwitchListTile.adaptive(
      title: Text(t.pages.settings.general.enableAnalytics),
      subtitle: Text(t.pages.settings.general.enableAnalyticsMsg, style: Theme.of(context).textTheme.bodySmall),
      secondary: const Icon(Icons.analytics_rounded),
      value: enabled,
      onChanged: (value) async {
        if (onChanged != null) {
          return onChanged!(value);
        }
        if (enabled) {
          await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
        } else {
          await ref.read(analyticsControllerProvider.notifier).enableAnalytics();
        }
      },
    );
  }
}

class ThemeModePrefTile extends ConsumerWidget {
  const ThemeModePrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final themeMode = ref.watch(themePreferencesProvider);

    return ListTile(
      title: Text(t.pages.settings.general.themeMode),
      subtitle: Text(themeMode.present(t)),
      leading: Icon(switch (ref.watch(themePreferencesProvider)) {
        AppThemeMode.system => Icons.auto_awesome_rounded,
        AppThemeMode.light => Icons.light_mode_rounded,
        AppThemeMode.dark => Icons.dark_mode_rounded,
        AppThemeMode.black => Icons.contrast_rounded,
      }),
      trailing: shouldOpenGeneralChoiceAsPage(isMobilePlatform: PlatformUtils.isMobile)
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: () async {
        final AppThemeMode? selectedThemeMode;
        if (shouldOpenGeneralChoiceAsPage(isMobilePlatform: PlatformUtils.isMobile)) {
          final navigator = Navigator.of(context);
          selectedThemeMode = await navigator.push<AppThemeMode>(
            MaterialPageRoute(
              builder: (_) => _SettingsSelectionPage<AppThemeMode>(
                title: t.pages.settings.general.themeMode,
                selected: themeMode,
                options: AppThemeMode.values,
                getTitle: (e) => e.present(t),
                onReset: () => ref.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.system),
              ),
            ),
          );
        } else {
          selectedThemeMode = await ref
              .read(dialogNotifierProvider.notifier)
              .showSettingPicker<AppThemeMode>(
                title: t.pages.settings.general.themeMode,
                selected: themeMode,
                onReset: () => ref.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.system),
                options: AppThemeMode.values,
                getTitle: (e) => e.present(t),
              );
        }
        if (selectedThemeMode != null) {
          await ref.read(themePreferencesProvider.notifier).changeThemeMode(selectedThemeMode);
        }
      },
    );
  }
}

@visibleForTesting
bool shouldOpenGeneralChoiceAsPage({required bool isMobilePlatform}) => isMobilePlatform;

class ClosingPrefTile extends ConsumerWidget {
  const ClosingPrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final action = ref.watch(Preferences.actionAtClose);

    return ListTile(
      title: Text(t.pages.settings.general.actionAtClosing),
      subtitle: Text(action.present(t)),
      leading: const Icon(Icons.logout_rounded),
      onTap: () async {
        final selectedAction = await ref.read(dialogNotifierProvider.notifier).showActionAtClosing(selected: action);
        if (selectedAction != null) {
          await ref.read(Preferences.actionAtClose.notifier).update(selectedAction);
        }
      },
    );
  }
}
