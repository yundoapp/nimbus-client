import 'package:flutter/material.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GeneralPage extends HookConsumerWidget {
  const GeneralPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(ref.watch(translationsProvider).requireValue.pages.settings.general.title)),
    body: ListView(children: const [GeneralSettingsTiles()]),
  );
}

class GeneralSettingsTiles extends HookConsumerWidget {
  const GeneralSettingsTiles({super.key, this.showDividers = false});

  final bool showDividers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final tiles = <Widget>[
      const LocalePrefTile(),
      const ThemeModePrefTile(),
      if (PlatformUtils.isAndroid) ...[
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.dynamicNotification),
          secondary: const Icon(Icons.speed_rounded),
          value: ref.watch(Preferences.dynamicNotification),
          onChanged: ref.read(Preferences.dynamicNotification.notifier).update,
        ),
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.hapticFeedback),
          secondary: const Icon(Icons.vibration_rounded),
          value: ref.watch(hapticServiceProvider),
          onChanged: ref.read(hapticServiceProvider.notifier).updatePreference,
        ),
      ],
      if (PlatformUtils.isDesktop) ...[
        Builder(
          builder: (context) {
            final autoStart = ref.watch(autoStartNotifierProvider);
            return SwitchListTile.adaptive(
              title: Text(t.pages.settings.general.autoStart),
              secondary: const Icon(Icons.auto_mode_rounded),
              value: autoStart.valueOrNull ?? false,
              onChanged: autoStart.hasValue
                  ? (value) async => value
                        ? await ref.read(autoStartNotifierProvider.notifier).enable()
                        : await ref.read(autoStartNotifierProvider.notifier).disable()
                  : null,
            );
          },
        ),
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.silentStart),
          secondary: const Icon(Icons.visibility_off_rounded),
          value: ref.watch(Preferences.silentStart),
          onChanged: ref.read(Preferences.silentStart.notifier).update,
        ),
      ],
      SwitchListTile.adaptive(
        title: Text(t.nimbus.settings.autoConnectOnLaunch),
        secondary: const Icon(Icons.bolt_rounded),
        value: ref.watch(Preferences.nimbusAutoConnect),
        onChanged: ref.read(Preferences.nimbusAutoConnect.notifier).update,
      ),
      if (PlatformUtils.isAndroid) const BatteryOptimizationWidget(),
    ];

    if (!showDividers) return Column(children: tiles);
    return Column(
      children: [
        for (var index = 0; index < tiles.length; index++) ...[
          tiles[index],
          if (index < tiles.length - 1) const Divider(height: 1, indent: 56),
        ],
      ],
    );
  }
}
