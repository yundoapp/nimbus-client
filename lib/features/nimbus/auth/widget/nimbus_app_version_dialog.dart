import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/utils/uri_utils.dart';

class NimbusAppVersionDialog extends StatelessWidget {
  const NimbusAppVersionDialog({required this.version, super.key});

  final NimbusAppVersionCheck version;

  @override
  Widget build(BuildContext context) {
    final forceUpdate = version.forceUpdate;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(forceUpdate ? '需要更新' : '发现新版本'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(forceUpdate ? '当前版本已不再支持，请更新后继续使用。' : '有新的版本可用。'),
            const Gap(12),
            _VersionRow(label: '当前版本', value: version.currentVersion),
            _VersionRow(label: '最新版本', value: version.latestVersion),
            _VersionRow(label: '最低支持', value: version.minimumVersion),
            if (version.releaseNotes?.trim().isNotEmpty ?? false) ...[
              const Gap(12),
              Text('更新说明', style: theme.textTheme.labelLarge),
              const Gap(4),
              Text(version.releaseNotes!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      actions: [
        if (!forceUpdate) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('稍后')),
        FilledButton.icon(
          onPressed: version.downloadUrl == null
              ? null
              : () async {
                  await UriUtils.tryLaunch(Uri.parse(version.downloadUrl!));
                },
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('打开下载页'),
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
