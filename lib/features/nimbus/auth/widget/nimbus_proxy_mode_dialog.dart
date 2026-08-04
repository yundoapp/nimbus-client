import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusProxyModeDialog extends ConsumerStatefulWidget {
  const NimbusProxyModeDialog({super.key, this.asPage = false, this.applyChanges});

  final bool asPage;
  final Future<void> Function()? applyChanges;

  @override
  ConsumerState<NimbusProxyModeDialog> createState() => _NimbusProxyModeDialogState();
}

class _NimbusProxyModeDialogState extends ConsumerState<NimbusProxyModeDialog> {
  bool _isApplying = false;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedMode = ref.watch(Preferences.nimbusProxyMode);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    final t = ref.watch(translationsProvider).requireValue;
    final controlsEnabled = !_isApplying && !(connection?.isSwitching ?? false);
    final availableWidth = math.max(0.0, MediaQuery.sizeOf(context).width - 80);
    final contentWidth = math.min(520.0, availableWidth);

    Widget modeOption({required NimbusProxyMode mode, required String title, required String description}) {
      final selected = selectedMode == mode;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.42) : null,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: RadioListTile<NimbusProxyMode>(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          value: mode,
          enabled: controlsEnabled,
          title: Text(title),
          subtitle: Text(description),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      );
    }

    final content = RadioGroup<NimbusProxyMode>(
      groupValue: selectedMode,
      onChanged: (mode) {
        if (controlsEnabled && mode != null) _selectMode(mode);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          modeOption(
            mode: NimbusProxyMode.auto,
            title: t.nimbus.proxyMode.auto,
            description: t.nimbus.proxyMode.autoDescription,
          ),
          const Gap(12),
          modeOption(
            mode: NimbusProxyMode.global,
            title: t.nimbus.proxyMode.global,
            description: t.nimbus.proxyMode.globalDescription,
          ),
          if (_isApplying || (connection?.isSwitching ?? false)) ...[
            const Gap(16),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );

    if (widget.asPage) {
      return Scaffold(
        appBar: AppBar(title: Text(t.nimbus.home.connectionMode)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: content),
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(t.nimbus.home.connectionMode),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(child: content),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
    );
  }
}

class NimbusProxyModePage extends StatelessWidget {
  const NimbusProxyModePage({super.key});

  @override
  Widget build(BuildContext context) => const NimbusProxyModeDialog(asPage: true);
}
