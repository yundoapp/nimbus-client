import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusDevicesDialog extends HookConsumerWidget {
  const NimbusDevicesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final devices = authState.devices;
    final t = ref.watch(translationsProvider).requireValue;

    useEffect(() {
      Future.microtask(() => ref.read(nimbusAuthControllerProvider.notifier).loadDevices());
      return null;
    }, const []);

    if (!authState.isAuthenticated) {
      Future.microtask(() {
        if (context.mounted) {
          Navigator.of(context).pop();
          context.go('/auth/login');
        }
      });
    }

    return AlertDialog(
      title: Text(t.nimbus.devices.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: devices == null && authState.isLoading
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : _DevicesContent(devices: devices, isLoading: authState.isLoading),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
    );
  }
}

class _DevicesContent extends ConsumerWidget {
  const _DevicesContent({required this.devices, required this.isLoading});

  final NimbusDevicesList? devices;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = devices?.items ?? const <NimbusRegisteredDevice>[];
    final limit = devices?.limit ?? 0;
    final errorMessage = ref.watch(nimbusAuthControllerProvider).errorMessage;
    final t = ref.watch(translationsProvider).requireValue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.nimbus.devices.count(used: items.length, limit: limit == 0 ? '--' : limit)),
        if (errorMessage != null) ...[
          const Gap(8),
          Text(
            errorMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const Gap(12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(t.nimbus.devices.empty)),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _DeviceTile(device: items[index], isLoading: isLoading),
            ),
          ),
      ],
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device, required this.isLoading});

  final NimbusRegisteredDevice device;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_platformIcon(device.platform)),
      title: Row(
        children: [
          Expanded(child: Text(device.deviceName.isEmpty ? t.nimbus.devices.unknownDevice : device.deviceName)),
          if (device.isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                t.nimbus.devices.current,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${_platformName(t, device.platform)} · ${device.appVersion} · ${_lastActiveText(t, device.lastActiveAt)}',
      ),
      trailing: device.isCurrent
          ? null
          : IconButton(
              tooltip: t.nimbus.devices.deleteTooltip,
              onPressed: isLoading ? null : () => _confirmRemove(context, ref, device),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
    );
  }
}

Future<void> _confirmRemove(BuildContext context, WidgetRef ref, NimbusRegisteredDevice device) async {
  final t = ref.read(translationsProvider).requireValue;
  final deviceName = device.deviceName.isEmpty ? t.nimbus.devices.unknownDevice : device.deviceName;
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.nimbus.devices.deleteTitle),
          content: Text(t.nimbus.devices.deleteConfirm(name: deviceName)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.common.cancel)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t.common.delete)),
          ],
        ),
      ) ??
      false;
  if (!confirmed) return;
  await ref.read(nimbusAuthControllerProvider.notifier).removeDevice(device.id);
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'macos' => Icons.laptop_mac_rounded,
    'windows' => Icons.desktop_windows_rounded,
    'ios' => Icons.phone_iphone_rounded,
    'android' => Icons.phone_android_rounded,
    _ => Icons.devices_other_rounded,
  };
}

String _platformName(Translations t, String platform) {
  return switch (platform) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'ios' => 'iOS',
    'android' => 'Android',
    _ => t.nimbus.devices.unknownPlatform,
  };
}

String _lastActiveText(Translations t, DateTime? value) {
  if (value == null) return t.nimbus.devices.lastActiveEmpty;
  final time =
      '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)} ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  return t.nimbus.devices.lastActive(time: time);
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
