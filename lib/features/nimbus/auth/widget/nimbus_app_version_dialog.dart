import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusAppVersionDialog extends ConsumerWidget {
  const NimbusAppVersionDialog({required this.version, super.key});

  final NimbusAppVersionCheck version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forceUpdate = version.forceUpdate;
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;

    return AlertDialog(
      title: Text(forceUpdate ? t.nimbus.appVersion.updateRequired : t.nimbus.appVersion.newVersion),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(forceUpdate ? t.nimbus.appVersion.forceMessage : t.nimbus.appVersion.optionalMessage),
            const Gap(12),
            _VersionRow(label: t.nimbus.appVersion.currentVersion, value: version.currentVersion),
            _VersionRow(label: t.nimbus.appVersion.latestVersion, value: version.latestVersion),
            _VersionRow(label: t.nimbus.appVersion.minimumVersion, value: version.minimumVersion),
            if (version.releaseNotes?.trim().isNotEmpty ?? false) ...[
              const Gap(12),
              Text(t.nimbus.appVersion.releaseNotes, style: theme.textTheme.labelLarge),
              const Gap(4),
              Text(version.releaseNotes!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      actions: [
        if (!forceUpdate) TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.later)),
        FilledButton.icon(
          onPressed: version.downloadUrl == null
              ? null
              : () async {
                  await UriUtils.tryLaunch(Uri.parse(version.downloadUrl!));
                },
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(t.nimbus.appVersion.openDownloadPage),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(value.isEmpty ? '--' : value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
