import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_route_preferences_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusProxyModeDialog extends ConsumerStatefulWidget {
  const NimbusProxyModeDialog({super.key, this.loadConfiguredSiteCount, this.openCustomWebsites, this.applyChanges});

  final Future<int?> Function()? loadConfiguredSiteCount;
  final Future<void> Function(BuildContext context)? openCustomWebsites;
  final Future<void> Function()? applyChanges;

  @override
  ConsumerState<NimbusProxyModeDialog> createState() => _NimbusProxyModeDialogState();
}

class _NimbusProxyModeDialogState extends ConsumerState<NimbusProxyModeDialog> {
  int? _configuredSiteCount;
  bool _isLoadingCount = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfiguredSiteCount());
  }

  Future<void> _loadConfiguredSiteCount() async {
    if (mounted) setState(() => _isLoadingCount = true);
    try {
      final countLoader = widget.loadConfiguredSiteCount;
      if (countLoader != null) {
        final count = await countLoader();
        if (mounted) setState(() => _configuredSiteCount = count);
      } else {
        final session = ref.read(nimbusAuthControllerProvider).session;
        if (session == null) return;
        final preferences = await ref.read(nimbusAuthRepositoryProvider).fetchRoutePreferences(session);
        if (mounted) setState(() => _configuredSiteCount = preferences.used);
      }
    } catch (_) {
      if (mounted) setState(() => _configuredSiteCount = null);
    } finally {
      if (mounted) setState(() => _isLoadingCount = false);
    }
  }

  Future<void> _openCustomWebsites() async {
    final customOpener = widget.openCustomWebsites;
    if (customOpener != null) {
      await customOpener(context);
    } else {
      await showDialog<void>(context: context, builder: (_) => const NimbusRoutePreferencesDialog());
    }
    if (mounted) await _loadConfiguredSiteCount();
  }

  Future<void> _applyPreferenceChange(Future<void> Function() updatePreference) async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    try {
      await updatePreference();
      final applyChanges = widget.applyChanges;
      if (applyChanges != null) {
        await applyChanges();
      } else {
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected();
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _selectMode(NimbusProxyMode mode) async {
    if (mode == ref.read(Preferences.nimbusProxyMode)) return;
    await _applyPreferenceChange(() => ref.read(Preferences.nimbusProxyMode.notifier).update(mode));
  }

  Future<void> _setCustomWebsiteAccess(bool enabled) async {
    await _applyPreferenceChange(() => ref.read(Preferences.nimbusCustomWebsiteAccessEnabled.notifier).update(enabled));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedMode = ref.watch(Preferences.nimbusProxyMode);
    final customWebsiteAccessEnabled = ref.watch(Preferences.nimbusCustomWebsiteAccessEnabled);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    final t = ref.watch(translationsProvider).requireValue;
    final isAutomaticMode = selectedMode == NimbusProxyMode.auto;
    final controlsEnabled = !_isApplying && !(connection?.isSwitching ?? false);
    final availableWidth = math.max(0.0, MediaQuery.sizeOf(context).width - 80);
    final contentWidth = math.min(520.0, availableWidth);
    final configuredCount = _isLoadingCount ? '—' : (_configuredSiteCount?.toString() ?? '—');

    return AlertDialog(
      title: Text(t.nimbus.home.connectionMode),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: RadioGroup<NimbusProxyMode>(
            groupValue: selectedMode,
            onChanged: (mode) {
              if (controlsEnabled && mode != null) _selectMode(mode);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioListTile<NimbusProxyMode>(
                  contentPadding: EdgeInsets.zero,
                  value: NimbusProxyMode.auto,
                  enabled: controlsEnabled,
                  title: Text(t.nimbus.proxyMode.auto),
                  subtitle: Text(t.nimbus.proxyMode.autoDescription),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 52),
                  child: AnimatedOpacity(
                    opacity: isAutomaticMode ? 1 : 0.48,
                    duration: const Duration(milliseconds: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: BorderDirectional(start: BorderSide(color: theme.colorScheme.outlineVariant)),
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 16),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: customWebsiteAccessEnabled,
                              onChanged: isAutomaticMode && controlsEnabled ? _setCustomWebsiteAccess : null,
                              title: Text(t.nimbus.proxyMode.customWebsiteAccess),
                              subtitle: Text(
                                isAutomaticMode
                                    ? t.nimbus.proxyMode.customWebsiteAccessDescription
                                    : t.nimbus.proxyMode.customWebsiteAccessAutoOnly,
                              ),
                            ),
                            Divider(height: 1, color: theme.colorScheme.outlineVariant),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              enabled: isAutomaticMode && controlsEnabled,
                              onTap: isAutomaticMode && controlsEnabled ? _openCustomWebsites : null,
                              title: Text(t.nimbus.proxyMode.customWebsiteConfiguredCount(count: configuredCount)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(t.nimbus.proxyMode.manageCustomWebsites),
                                  const Gap(4),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Gap(8),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const Gap(8),
                RadioListTile<NimbusProxyMode>(
                  contentPadding: EdgeInsets.zero,
                  value: NimbusProxyMode.global,
                  enabled: controlsEnabled,
                  title: Text(t.nimbus.proxyMode.global),
                  subtitle: Text(t.nimbus.proxyMode.globalDescription),
                ),
                if (_isApplying || (connection?.isSwitching ?? false)) ...[
                  const Gap(12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
    );
  }
}
