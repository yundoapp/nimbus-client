import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_acceleration_diagnostic.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_acceleration_diagnostics_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusAccelerationDiagnosticsDialog extends ConsumerWidget {
  const NimbusAccelerationDiagnosticsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final state = ref.watch(nimbusAccelerationDiagnosticsProvider);
    final theme = Theme.of(context);
    final current = state.current;
    final history = current == null
        ? state.history
        : state.history.where((item) => item != current).toList(growable: false);

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: _diagnosticsText(state)));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nimbus.errors.diagnosticsCopied)));
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(t.nimbus.diagnostics.title)),
          IconButton(onPressed: copy, icon: const Icon(Icons.copy_rounded), tooltip: t.nimbus.errors.copyDiagnostics),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .64),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView(
              children: [
                if (current != null) ...[
                  _AttemptHeader(attempt: current, t: t),
                  const Gap(12),
                  ...current.steps.map((step) => _StepTile(step: step, t: t)),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(t.nimbus.diagnostics.emptyHistory)),
                  ),
                if (history.isNotEmpty) ...[
                  const Gap(16),
                  Text(
                    t.nimbus.diagnostics.history,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Gap(8),
                  ...history.take(8).map((attempt) => _HistoryTile(attempt: attempt, t: t)),
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

class NimbusAccelerationDiagnosticsEntry extends ConsumerWidget {
  const NimbusAccelerationDiagnosticsEntry({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const Key('home-open-acceleration-diagnostics'),
        onPressed: onPressed,
        icon: const Icon(Icons.timeline_rounded, size: 18),
        label: Text(t.nimbus.diagnostics.view),
      ),
    );
  }
}

class _AttemptHeader extends StatelessWidget {
  const _AttemptHeader({required this.attempt, required this.t});

  final NimbusAccelerationAttempt attempt;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = attempt.status == NimbusAccelerationAttemptStatus.running;
    final failed = attempt.status == NimbusAccelerationAttemptStatus.failure;
    final label = attempt.operation == NimbusAccelerationOperation.start
        ? t.nimbus.diagnostics.start
        : t.nimbus.diagnostics.stop;
    final status = running
        ? t.nimbus.diagnostics.running
        : failed
        ? t.nimbus.diagnostics.failure
        : t.nimbus.diagnostics.success;
    final color = running
        ? theme.colorScheme.primary
        : failed
        ? theme.colorScheme.error
        : _diagnosticsSuccessColor(theme);
    final seconds = ((attempt.completedAt ?? DateTime.now()).difference(attempt.startedAt).inMilliseconds / 1000)
        .toStringAsFixed(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          running
              ? Icons.sync_rounded
              : failed
              ? Icons.close_rounded
              : Icons.check_circle_outline_rounded,
          color: color,
        ),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · $status', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Gap(3),
              Text(t.nimbus.diagnostics.completedIn(seconds: seconds), style: theme.textTheme.bodySmall),
              if (attempt.errorCode != null || attempt.errorDetail != null) ...[
                const Gap(3),
                Text(
                  [attempt.errorCode, attempt.errorDetail].whereType<String>().join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.t});

  final NimbusAccelerationStepSnapshot step;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isRunning = step.status == NimbusAccelerationStepStatus.running;
    final isFailure = step.status == NimbusAccelerationStepStatus.failure;
    final isSuccess = step.status == NimbusAccelerationStepStatus.success;
    final color = isFailure
        ? colors.error
        : isSuccess
        ? _diagnosticsSuccessColor(theme)
        : isRunning
        ? colors.primary
        : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Icon(
              isFailure
                  ? Icons.close_rounded
                  : isSuccess
                  ? Icons.check_circle_rounded
                  : isRunning
                  ? Icons.sync_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: color,
            ),
          ),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_stepLabel(t, step.id), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  step.detail ?? t.nimbus.diagnostics.pending,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: isFailure ? colors.error : colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.attempt, required this.t});

  final NimbusAccelerationAttempt attempt;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final time =
        '${localizations.formatShortDate(attempt.startedAt.toLocal())} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(attempt.startedAt.toLocal()))}';
    final operation = attempt.operation == NimbusAccelerationOperation.start
        ? t.nimbus.diagnostics.start
        : t.nimbus.diagnostics.stop;
    final status = attempt.status == NimbusAccelerationAttemptStatus.failure
        ? t.nimbus.diagnostics.failure
        : attempt.status == NimbusAccelerationAttemptStatus.running
        ? t.nimbus.diagnostics.running
        : t.nimbus.diagnostics.success;
    final completedDetail = attempt.operation == NimbusAccelerationOperation.start
        ? t.nimbus.diagnostics.detailAccelerationStarted
        : t.nimbus.diagnostics.detailAccelerationStopped;
    final detail = [
      time,
      attempt.errorCode,
      if (attempt.status == NimbusAccelerationAttemptStatus.success) completedDetail else attempt.errorDetail,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        attempt.status == NimbusAccelerationAttemptStatus.failure ? Icons.close_rounded : Icons.history_rounded,
        color: attempt.status == NimbusAccelerationAttemptStatus.failure ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text('$operation · $status'),
      subtitle: Text(detail),
    );
  }
}

Color _diagnosticsSuccessColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? Colors.green.shade400 : Colors.green.shade700;

String _stepLabel(Translations t, NimbusAccelerationStepId id) => switch (id) {
  NimbusAccelerationStepId.account => t.nimbus.diagnostics.account,
  NimbusAccelerationStepId.subscription => t.nimbus.diagnostics.subscription,
  NimbusAccelerationStepId.connectionState => t.nimbus.diagnostics.connectionState,
  NimbusAccelerationStepId.rules => t.nimbus.diagnostics.rules,
  NimbusAccelerationStepId.connectionPlan => t.nimbus.diagnostics.connectionPlan,
  NimbusAccelerationStepId.core => t.nimbus.diagnostics.core,
  NimbusAccelerationStepId.network => t.nimbus.diagnostics.network,
  NimbusAccelerationStepId.tunnel => t.nimbus.diagnostics.tunnel,
  NimbusAccelerationStepId.routing => t.nimbus.diagnostics.routing,
  NimbusAccelerationStepId.cleanup => t.nimbus.diagnostics.cleanup,
};

String _diagnosticsText(NimbusAccelerationDiagnosticsState state) {
  return state.history.map((attempt) => attempt.toJson().toString()).join('\n');
}
