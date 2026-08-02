import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusIssueReportDialog extends HookConsumerWidget {
  const NimbusIssueReportDialog({super.key, this.asPage = false});

  final bool asPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final repository = ref.watch(nimbusAuthRepositoryProvider);
    final appInfo = ref.watch(appInfoProvider).asData?.value;
    final connectionStatus = ref.watch(nimbusOwnedConnectionStatusProvider).asData?.value;
    final connectionDiagnostic = ref.watch(nimbusConnectionControllerProvider).diagnostic;
    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final category = useState('connection');
    final descriptionController = useTextEditingController();
    final contactController = useTextEditingController();
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
          category: category.value,
          description: descriptionController.text.trim(),
          contact: contactController.text.trim(),
          diagnostics: {
            'appVersion': appInfo == null ? null : '${appInfo.version}+${appInfo.buildNumber}',
            'appName': appInfo?.name,
            'platform': appInfo?.operatingSystem,
            'osVersion': appInfo?.operatingSystemVersion,
            'rulesVersion': authState.me?.rules.publicRulesVersion,
            'connectionStatus': buildNimbusIssueConnectionStatus(connectionStatus, connectionDiagnostic),
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
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
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

    final content = Column(
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
        DropdownButtonFormField<String>(
          initialValue: category.value,
          decoration: InputDecoration(
            labelText: t.nimbus.issueReport.categoryLabel,
            prefixIcon: const Icon(Icons.category_outlined),
          ),
          items: [
            DropdownMenuItem(value: 'connection', child: Text(t.nimbus.issueReport.categoryConnection)),
            DropdownMenuItem(value: 'account', child: Text(t.nimbus.issueReport.categoryAccount)),
            DropdownMenuItem(value: 'subscription', child: Text(t.nimbus.issueReport.categorySubscription)),
            DropdownMenuItem(value: 'other', child: Text(t.nimbus.issueReport.categoryOther)),
          ],
          onChanged: isSubmitting.value ? null : (value) => category.value = value ?? 'connection',
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
        const Gap(12),
        TextField(
          controller: contactController,
          enabled: !isSubmitting.value,
          maxLength: 200,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]')),
          ],
          decoration: InputDecoration(
            labelText: t.nimbus.issueReport.contactLabel,
            prefixIcon: const Icon(Icons.alternate_email_rounded),
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
    );

    final cancelButton = TextButton(
      onPressed: isSubmitting.value ? null : () => Navigator.of(context).pop(),
      child: Text(t.common.cancel),
    );
    final submitButton = FilledButton.icon(
      onPressed: isSubmitting.value ? null : submit,
      icon: isSubmitting.value
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.outlined_flag_rounded),
      label: Text(t.nimbus.issueReport.submit),
    );

    if (asPage) {
      return Scaffold(
        appBar: AppBar(title: Text(t.nimbus.issueReport.title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: content),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(child: cancelButton),
              const Gap(12),
              Expanded(child: submitButton),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(t.nimbus.issueReport.title),
      scrollable: true,
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: content),
      actions: [cancelButton, submitButton],
    );
  }
}

class NimbusIssueReportPage extends StatelessWidget {
  const NimbusIssueReportPage({super.key});

  @override
  Widget build(BuildContext context) => const NimbusIssueReportDialog(asPage: true);
}

String buildNimbusIssueConnectionStatus(ConnectionStatus? status, NimbusConnectionDiagnostic? diagnostic) {
  final connection = switch (status) {
    Disconnected() => 'DISCONNECTED',
    Connecting() => 'CONNECTING',
    Connected() => 'CONNECTED',
    Disconnecting() => 'DISCONNECTING',
    null => 'UNKNOWN',
  };
  if (diagnostic == null) return connection;
  return '$connection; diagnostic=${diagnostic.code}; failure=${diagnostic.failureCode}; stage=${diagnostic.stage}';
}
