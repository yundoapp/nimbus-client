import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_change_password_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_devices_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_issue_report_dialog.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final settingsMenuOpensPage = shouldOpenNimbusMenuAsPage(isMobilePlatform: PlatformUtils.isMobile);
    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.title)),
      body: ListView(
        children: [
          SettingsSection(
            title: t.pages.settings.general.title,
            icon: Icons.layers_rounded,
            namedLocation: context.namedLocation('general'),
            page: const GeneralPage(),
          ),
          const Divider(height: 16),
          ListTile(
            title: Text(t.nimbus.settings.deviceManagement),
            leading: const Icon(Icons.devices_rounded),
            trailing: settingsMenuOpensPage ? const Icon(Icons.chevron_right_rounded) : null,
            onTap: () => _openAdaptiveSettingsMenu(
              context,
              dialog: const NimbusDevicesDialog(),
              page: const NimbusDevicesPage(),
            ),
          ),
          ListTile(
            title: Text(t.nimbus.changePassword.title),
            leading: const Icon(Icons.password_rounded),
            trailing: settingsMenuOpensPage ? const Icon(Icons.chevron_right_rounded) : null,
            onTap: () => _openAdaptiveSettingsMenu(
              context,
              dialog: const NimbusChangePasswordDialog(),
              page: const NimbusChangePasswordPage(),
            ),
          ),
          ListTile(
            title: Text(t.nimbus.settings.issueReport),
            leading: const Icon(Icons.outlined_flag_rounded),
            trailing: settingsMenuOpensPage ? const Icon(Icons.chevron_right_rounded) : null,
            onTap: () => _openAdaptiveSettingsMenu(
              context,
              dialog: const NimbusIssueReportDialog(),
              page: const NimbusIssueReportPage(),
            ),
          ),
          if (Breakpoint(context).isMobile()) ...[
            SettingsSection(
              title: t.pages.about.title,
              icon: Icons.info_rounded,
              namedLocation: context.namedLocation('about'),
              page: const AboutPage(),
            ),
          ],
          if (PlatformUtils.isIOS || PlatformUtils.isWindows)
            Material(
              child: ListTile(
                title: Text(t.pages.settings.resetTunnel),
                leading: const Icon(Icons.autorenew_rounded),
                onTap: () async {
                  await ref.read(resetTunnelNotifierProvider.notifier).run();
                },
              ),
            ),
          ListTile(
            title: Text(t.nimbus.settings.logout),
            leading: const Icon(Icons.logout_rounded),
            onTap: () async {
              await ref.read(nimbusAuthControllerProvider.notifier).logout();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _openAdaptiveSettingsMenu(BuildContext context, {required Widget dialog, required Widget page}) async {
  if (shouldOpenNimbusMenuAsPage(isMobilePlatform: PlatformUtils.isMobile)) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return;
  }
  await showDialog<void>(context: context, builder: (_) => dialog);
}

@visibleForTesting
bool shouldOpenNimbusMenuAsPage({required bool isMobilePlatform}) => isMobilePlatform;

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    required this.namedLocation,
    this.page,
  });

  final String title;
  final Widget? subtitle;
  final IconData icon;
  final String namedLocation;
  final Widget? page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetPage = page;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        if (targetPage != null &&
            shouldOpenSettingsSectionAsPage(isMobilePlatform: PlatformUtils.isMobile, hasPage: true)) {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => targetPage));
          return;
        }
        if (context.mounted) context.go(namedLocation);
      },
    );
  }
}

@visibleForTesting
bool shouldOpenSettingsSectionAsPage({required bool isMobilePlatform, required bool hasPage}) =>
    isMobilePlatform && hasPage;
