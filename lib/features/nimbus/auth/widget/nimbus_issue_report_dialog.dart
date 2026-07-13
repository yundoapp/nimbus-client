import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusIssueReportDialog extends HookConsumerWidget {
  const NimbusIssueReportDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final repository = ref.watch(nimbusAuthRepositoryProvider);
    final appInfo = ref.watch(appInfoProvider).asData?.value;
    final connectionStatus = ref.watch(connectionNotifierProvider).asData?.value;
    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final descriptionController = useTextEditingController();
    final isSubmitting = useState(false);
    final errorMessage = useState<String?>(null);
    final t = ref.watch(translationsProvider).requireValue;

    Future<void> submit() async {
      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;

      isSubmitting.value = true;
      errorMessage.value = null;
      try {
        await repository.submitIssueReport(
          session: session,
          description: descriptionController.text.trim(),
          diagnostics: {
            'appVersion': appInfo == null ? null : '${appInfo.version}+${appInfo.buildNumber}',
            'appName': appInfo?.name,
            'platform': appInfo?.operatingSystem,
            'osVersion': appInfo?.operatingSystemVersion,
            'rulesVersion': authState.me?.rules.publicRulesVersion,
            'connectionStatus': _safeConnectionStatus(connectionStatus),
            'selectedLocation': authState.selectedLocationCode,
            'subscriptionStatus': authState.me?.subscription.status,
            'uplink': stats?.uplink.toInt() ?? 0,
            'downlink': stats?.downlink.toInt() ?? 0,
          },
        );
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(t.nimbus.issueReport.submitted)));
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).restore();
        } else {
          errorMessage.value = repository.describeError(error, t);
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    if (!authState.isAuthenticated) {
      Future.microtask(() {
        if (context.mounted) {
          Navigator.of(context).pop();
          context.go('/auth/login');
        }
      });
    }

    return AlertDialog(
      title: Text(t.nimbus.issueReport.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.nimbus.issueReport.description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Gap(12),
            TextField(
              controller: descriptionController,
              enabled: !isSubmitting.value,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]')),
              ],
              decoration: InputDecoration(
                labelText: t.nimbus.issueReport.descriptionLabel,
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.edit_note_rounded),
              ),
              onChanged: (_) => errorMessage.value = null,
            ),
            if (errorMessage.value != null) ...[
              const Gap(8),
              Text(
                errorMessage.value!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSubmitting.value ? null : () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton.icon(
          onPressed: isSubmitting.value ? null : submit,
          icon: isSubmitting.value
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.outlined_flag_rounded),
          label: Text(t.nimbus.issueReport.submit),
        ),
      ],
    );
  }
}

String _safeConnectionStatus(ConnectionStatus? status) => switch (status) {
  Disconnected() => 'DISCONNECTED',
  Connecting() => 'CONNECTING',
  Connected() => 'CONNECTED',
  Disconnecting() => 'DISCONNECTING',
  null => 'UNKNOWN',
};
