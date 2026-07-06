import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusDesktopSettingsDialog extends ConsumerWidget {
  const NimbusDesktopSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoStart = ref.watch(autoStartNotifierProvider);
    final autoConnect = ref.watch(Preferences.nimbusAutoConnect);

    return AlertDialog(
      title: const Text('桌面设置'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.power_settings_new_rounded),
              title: const Text('开机启动'),
              value: autoStart.valueOrNull ?? false,
              onChanged: autoStart.isLoading
                  ? null
                  : (value) async {
                      if (value) {
                        await ref.read(autoStartNotifierProvider.notifier).enable();
                      } else {
                        await ref.read(autoStartNotifierProvider.notifier).disable();
                      }
                    },
            ),
            const Gap(4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bolt_rounded),
              title: const Text('启动后自动启用'),
              value: autoConnect,
              onChanged: ref.read(Preferences.nimbusAutoConnect.notifier).update,
            ),
            if (autoStart.hasError) ...[
              const Gap(8),
              Text(
                '开机启动状态读取失败',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
    );
  }
}
