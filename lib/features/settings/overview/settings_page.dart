import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_diagnostics_localization.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_acceleration_diagnostics_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_change_password_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_devices_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_issue_report_dialog.dart';
import 'package:hiddify/features/nimbus/widget/nimbus_page_layout.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final diagnosticsT = nimbusDiagnosticsTranslations(t);
    final settingsMenuOpensPage = shouldOpenNimbusMenuAsPage(isMobilePlatform: PlatformUtils.isMobile);
    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.title), centerTitle: false, titleSpacing: 16),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: nimbusPageContentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SettingsGroup(children: [GeneralSettingsTiles(showDividers: true)]),
                    _SettingsGroup(
                      children: [
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
                      ],
                    ),
                    _SettingsGroup(
                      children: [
                        ListTile(
                          title: Text(diagnosticsT.nimbus.diagnostics.menuTitle),
                          leading: const Icon(Icons.monitor_heart_rounded),
                          trailing: settingsMenuOpensPage ? const Icon(Icons.chevron_right_rounded) : null,
                          onTap: () => _openAdaptiveSettingsMenu(
                            context,
                            dialog: const NimbusAccelerationDiagnosticsDialog(),
                            page: const NimbusAccelerationDiagnosticsPage(),
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
                        ListTile(
                          title: Text(t.pages.about.title),
                          leading: const Icon(Icons.info_rounded),
                          trailing: settingsMenuOpensPage ? const Icon(Icons.chevron_right_rounded) : null,
                          onTap: () => _openAdaptiveSettingsMenu(
                            context,
                            dialog: const NimbusAboutDialog(),
                            page: const AboutPage(),
                          ),
                        ),
                      ],
                    ),
                    if (PlatformUtils.isIOS || PlatformUtils.isWindows)
                      _SettingsGroup(
                        children: [
                          ListTile(
                            title: Text(t.pages.settings.resetTunnel),
                            leading: const Icon(Icons.autorenew_rounded),
                            onTap: () async {
                              await ref.read(resetTunnelNotifierProvider.notifier).run();
                            },
                          ),
                        ],
                      ),
                    _SettingsGroup(
                      children: [
                        ListTile(
                          title: Text(t.nimbus.settings.logout),
                          leading: Icon(Icons.logout_rounded, color: Theme.of(context).colorScheme.error),
                          textColor: Theme.of(context).colorScheme.error,
                          onTap: () async {
                            await ref.read(nimbusAuthControllerProvider.notifier).logout();
                            if (context.mounted) context.go('/auth/login');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1) const Divider(height: 1, indent: 56),
            ],
          ],
        ),
      ),
    );
  }
}
