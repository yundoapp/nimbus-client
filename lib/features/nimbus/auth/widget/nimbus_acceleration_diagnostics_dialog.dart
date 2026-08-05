import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_acceleration_diagnostic.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_diagnostics_localization.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_acceleration_diagnostics_controller.dart';
import 'package:hiddify/features/nimbus/widget/nimbus_page_layout.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusAccelerationDiagnosticsDialog extends ConsumerWidget {
  const NimbusAccelerationDiagnosticsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final diagnosticsT = nimbusDiagnosticsTranslations(t);
    final state = ref.watch(nimbusAccelerationDiagnosticsProvider);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(diagnosticsT.nimbus.diagnostics.title)),
          IconButton(
            onPressed: () => _copyDiagnostics(context, ref, t),
            icon: const Icon(Icons.copy_rounded),
            tooltip: t.nimbus.errors.copyDiagnostics,
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .64),
          child: _DiagnosticsContent(state: state, t: diagnosticsT),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
    );
  }
}

class NimbusAccelerationDiagnosticsPage extends ConsumerWidget {
  const NimbusAccelerationDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final diagnosticsT = nimbusDiagnosticsTranslations(t);
    final state = ref.watch(nimbusAccelerationDiagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(diagnosticsT.nimbus.diagnostics.title),
        actions: [
          IconButton(
            onPressed: () => _copyDiagnostics(context, ref, t),
            icon: const Icon(Icons.copy_rounded),
            tooltip: t.nimbus.errors.copyDiagnostics,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: nimbusPageContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: _DiagnosticsContent(state: state, t: diagnosticsT),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsContent extends StatelessWidget {
  const _DiagnosticsContent({required this.state, required this.t});

  final NimbusAccelerationDiagnosticsState state;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    final history = current == null
        ? state.history
        : state.history.where((item) => item != current).toList(growable: false);
    final visibleHistoryLimit = current == null ? 10 : 9;
    final theme = Theme.of(context);
    return Scrollbar(
      thumbVisibility: true,
      child: ListView(
        children: [
          if (current != null) ...[
            _AttemptHeader(attempt: current, t: t),
            const Gap(12),
            ...current.steps.asMap().entries.map((entry) => _StepTile(index: entry.key + 1, step: entry.value, t: t)),
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
            ...history.take(visibleHistoryLimit).map((attempt) => _HistoryTile(attempt: attempt, t: t)),
          ],
        ],
      ),
    );
  }
}

Future<void> _copyDiagnostics(BuildContext context, WidgetRef ref, Translations t) async {
  final state = ref.read(nimbusAccelerationDiagnosticsProvider);
  await Clipboard.setData(ClipboardData(text: _diagnosticsText(state)));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nimbus.errors.diagnosticsCopied)));
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
              if (failed && (attempt.errorCode != null || attempt.errorDetail != null)) ...[
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
  const _StepTile({required this.index, required this.step, required this.t});

  final int index;
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
            width: 30,
            child: Text(
              '$index',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
            ),
          ),
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
                  _localizedStepDetail(t, step),
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
    final failure = attempt.status == NimbusAccelerationAttemptStatus.failure;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 34, right: 8, bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(
        failure ? Icons.close_rounded : Icons.history_rounded,
        color: failure ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text('$operation · $status'),
      subtitle: Text(detail),
      children: [
        ...attempt.steps.asMap().entries.map((entry) => _StepTile(index: entry.key + 1, step: entry.value, t: t)),
      ],
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
  NimbusAccelerationStepId.coreConfig => t.nimbus.diagnostics.coreConfig,
  NimbusAccelerationStepId.corePrepare => t.nimbus.diagnostics.corePrepare,
  NimbusAccelerationStepId.coreStart => t.nimbus.diagnostics.coreStart,
  NimbusAccelerationStepId.coreVerify => t.nimbus.diagnostics.coreVerify,
  NimbusAccelerationStepId.ruleSets => t.nimbus.diagnostics.ruleSets,
  NimbusAccelerationStepId.coreStop => t.nimbus.diagnostics.coreStop,
  NimbusAccelerationStepId.coreStopVerify => t.nimbus.diagnostics.coreStopVerify,
  NimbusAccelerationStepId.network => t.nimbus.diagnostics.network,
  NimbusAccelerationStepId.tunnel => t.nimbus.diagnostics.tunnel,
  NimbusAccelerationStepId.routing => t.nimbus.diagnostics.routing,
  NimbusAccelerationStepId.cleanup => t.nimbus.diagnostics.cleanup,
};

String _localizedStepDetail(Translations t, NimbusAccelerationStepSnapshot step) {
  final storedDetail = step.detail;
  if (storedDetail == null || storedDetail.isEmpty) return t.nimbus.diagnostics.pending;
  if (step.status == NimbusAccelerationStepStatus.failure) return storedDetail;

  final normalized = storedDetail.toLowerCase();
  final isRunning = step.status == NimbusAccelerationStepStatus.running;
  return switch (step.id) {
    NimbusAccelerationStepId.connectionState => t.nimbus.diagnostics.detailNoActiveConnection,
    NimbusAccelerationStepId.account =>
      _containsAny(normalized, ['刷新', 'refresh'])
          ? isRunning
                ? t.nimbus.diagnostics.detailRefreshingAccount
                : t.nimbus.diagnostics.detailAccountRefreshed
          : t.nimbus.diagnostics.detailSessionAvailable,
    NimbusAccelerationStepId.subscription =>
      _containsAny(normalized, ['检查', 'checking'])
          ? t.nimbus.diagnostics.detailCheckingAllowance
          : _containsAny(normalized, ['额度', 'allowance'])
          ? t.nimbus.diagnostics.detailAllowanceAvailable
          : t.nimbus.diagnostics.detailActivePlan,
    NimbusAccelerationStepId.rules => _localizedRulesDetail(t, storedDetail) ?? t.nimbus.diagnostics.rules,
    NimbusAccelerationStepId.connectionPlan => t.nimbus.diagnostics.detailPlanReceived,
    NimbusAccelerationStepId.core =>
      _containsAny(normalized, ['停止', 'stopped'])
          ? t.nimbus.diagnostics.detailCoreStopped
          : t.nimbus.diagnostics.detailCoreStarted,
    NimbusAccelerationStepId.coreConfig => t.nimbus.diagnostics.detailProfileValidated,
    NimbusAccelerationStepId.corePrepare => t.nimbus.diagnostics.detailCorePrepared,
    NimbusAccelerationStepId.coreStart => t.nimbus.diagnostics.detailCoreProcessStarted,
    NimbusAccelerationStepId.coreVerify => t.nimbus.diagnostics.detailCoreStatusStarted,
    NimbusAccelerationStepId.ruleSets => t.nimbus.diagnostics.detailRuleSetsLoaded(count: _ruleSetCount(storedDetail)),
    NimbusAccelerationStepId.coreStop => t.nimbus.diagnostics.detailCoreStopped,
    NimbusAccelerationStepId.coreStopVerify => t.nimbus.diagnostics.detailCoreStatusStopped,
    NimbusAccelerationStepId.network =>
      _containsAny(normalized, ['兜底', 'fallback'])
          ? t.nimbus.diagnostics.detailNetworkFallback
          : _containsAny(normalized, ['ipv6', 'dual-stack', 'dual stack'])
          ? t.nimbus.diagnostics.detailNetworkDualStack
          : t.nimbus.diagnostics.detailNetworkReady,
    NimbusAccelerationStepId.tunnel =>
      _containsAny(normalized, ['释放', 'released'])
          ? t.nimbus.diagnostics.detailTunnelReleased
          : t.nimbus.diagnostics.detailTunnelActive,
    NimbusAccelerationStepId.routing =>
      _containsAny(normalized, ['恢复', 'restored'])
          ? t.nimbus.diagnostics.detailRoutingRestored
          : t.nimbus.diagnostics.detailRoutingActive,
    NimbusAccelerationStepId.cleanup => t.nimbus.diagnostics.detailCleanupDone,
  };
}

String _ruleSetCount(String detail) {
  final count = RegExp(r'\d+').firstMatch(detail)?.group(0);
  return count ?? '--';
}

String? _localizedRulesDetail(Translations t, String detail) {
  final lines = detail.split('\n');
  if (lines.length < 2) return null;
  final countPattern = RegExp(r'\d+');
  final publicCount = countPattern.firstMatch(lines.first)?.group(0);
  final userCount = countPattern.firstMatch(lines[1])?.group(0);
  if (publicCount == null || userCount == null) return null;
  final version = RegExp('[（(]([^）)]+)[）)]').firstMatch(lines.first)?.group(1) ?? '--';
  return t.nimbus.diagnostics.detailRulesLoaded(publicCount: publicCount, publicVersion: version, userCount: userCount);
}

bool _containsAny(String value, Iterable<String> candidates) => candidates.any(value.contains);

String _diagnosticsText(NimbusAccelerationDiagnosticsState state) {
  return state.history.map((attempt) => attempt.toJson().toString()).join('\n');
}
