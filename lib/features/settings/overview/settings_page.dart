import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_devices_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_issue_report_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_route_preferences_dialog.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.title)),
      body: ListView(
        children: [
          SettingsSection(
            title: t.pages.settings.general.title,
            icon: Icons.layers_rounded,
            namedLocation: context.namedLocation('general'),
          ),
          ListTile(
            title: Text(t.nimbus.settings.accessPreferences),
            leading: const Icon(Icons.tune_rounded),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showDialog<void>(context: context, builder: (_) => const NimbusRoutePreferencesDialog()),
          ),
          SettingsSection(
            title: t.pages.logs.title,
            icon: Icons.description_rounded,
            namedLocation: context.namedLocation('logs'),
          ),
          const Divider(height: 16),
          ListTile(
            title: Text(t.nimbus.settings.deviceManagement),
            leading: const Icon(Icons.devices_rounded),
            onTap: () => showDialog<void>(context: context, builder: (_) => const NimbusDevicesDialog()),
          ),
          ListTile(
            title: Text(t.nimbus.settings.issueReport),
            leading: const Icon(Icons.outlined_flag_rounded),
            onTap: () => showDialog<void>(context: context, builder: (_) => const NimbusIssueReportDialog()),
          ),
          ListTile(
            title: Text(t.nimbus.settings.logout),
            leading: const Icon(Icons.logout_rounded),
            onTap: () async {
              await ref.read(nimbusAuthControllerProvider.notifier).logout();
              if (context.mounted) context.go('/auth/login');
            },
          ),
          if (PlatformUtils.isIOS)
            Material(
              child: ListTile(
                title: Text(t.pages.settings.resetTunnel),
                leading: const Icon(Icons.autorenew_rounded),
                onTap: () async {
                  await ref.read(resetTunnelNotifierProvider.notifier).run();
                },
              ),
            ),
          if (Breakpoint(context).isMobile()) ...[
            SettingsSection(
              title: t.pages.about.title,
              icon: Icons.info_rounded,
              namedLocation: context.namedLocation('about'),
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    required this.namedLocation,
  });

  final String title;
  final Widget? subtitle;
  final IconData icon;
  final String namedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(namedLocation),
    );
  }
}
