import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
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
            'connectionStatus': connectionStatus?.format() ?? 'UNKNOWN',
            'selectedLocation': authState.selectedLocationCode,
            'subscriptionStatus': authState.me?.subscription.status,
            'uplink': stats?.uplink.toInt() ?? 0,
            'downlink': stats?.downlink.toInt() ?? 0,
          },
        );
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('问题已上报')));
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).restore();
        } else {
          errorMessage.value = repository.describeError(error);
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
      title: const Text('上报问题'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '会同时上传脱敏诊断信息，方便尽快定位问题。',
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
              decoration: const InputDecoration(
                labelText: '问题描述（选填）',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.edit_note_rounded),
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
        TextButton(onPressed: isSubmitting.value ? null : () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton.icon(
          onPressed: isSubmitting.value ? null : submit,
          icon: isSubmitting.value
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.outlined_flag_rounded),
          label: const Text('上报'),
        ),
      ],
    );
  }
}
