import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_input_validation.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_route_preference_logic.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/route_history/model/nimbus_route_history.dart';
import 'package:hiddify/features/nimbus/route_history/notifier/nimbus_route_history_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusRouteHistoryPage extends HookConsumerWidget {
  const NimbusRouteHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final state = ref.watch(nimbusRouteHistoryProvider);
    final recordingEnabled = ref.watch(Preferences.nimbusRouteHistoryEnabled);
    final query = useState('');
    final selectedFilter = useState(NimbusRouteHistoryFilter.all);
    final selectedDecisionFilter = useState(NimbusRouteDecisionFilter.all);
    final searchController = useTextEditingController();
    final visibleEntries = filterNimbusRouteHistory(
      entries: state.entries,
      filter: selectedFilter.value,
      decisionFilter: selectedDecisionFilter.value,
      query: query.value,
    );

    Future<void> clearHistory() async {
      final confirmed = await _showAdaptiveConfirmation(
        context: context,
        title: t.nimbus.routeHistory.clearTitle,
        message: t.nimbus.routeHistory.clearConfirm,
        confirmLabel: t.common.clear,
        cancelLabel: t.common.cancel,
      );
      if (confirmed ?? false) {
        ref.read(nimbusRouteHistoryProvider.notifier).clear();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.nimbus.routeHistory.title),
        actions: [
          if (state.entries.isNotEmpty)
            IconButton(
              tooltip: t.nimbus.routeHistory.clearTooltip,
              onPressed: clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const Gap(8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _RouteHistoryToolbar(
                    state: state,
                    recordingEnabled: recordingEnabled,
                    searchController: searchController,
                    query: query.value,
                    selectedFilter: selectedFilter.value,
                    selectedDecisionFilter: selectedDecisionFilter.value,
                    onQueryChanged: (value) => query.value = value,
                    onClearQuery: () {
                      searchController.clear();
                      query.value = '';
                    },
                    onFilterChanged: (value) => selectedFilter.value = value,
                    onDecisionFilterChanged: (value) => selectedDecisionFilter.value = value,
                    onRecordingChanged: ref.read(Preferences.nimbusRouteHistoryEnabled.notifier).update,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch ((state.entries.isEmpty, visibleEntries.isEmpty)) {
                    (true, _) => _RouteHistoryEmptyState(
                      title: t.nimbus.routeHistory.emptyTitle,
                      description: recordingEnabled
                          ? t.nimbus.routeHistory.emptyDescription
                          : t.nimbus.routeHistory.recordingDisabledDescription,
                    ),
                    (false, true) => _RouteHistoryEmptyState(
                      title: t.nimbus.routeHistory.noResultsTitle,
                      description: t.nimbus.routeHistory.noResultsDescription,
                    ),
                    _ => ListView.separated(
                      itemCount: visibleEntries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final entry = visibleEntries[index];
                        return _RouteHistoryTile(
                          entry: entry,
                          onTap: () => _openRouteHistoryDetails(context, ref, entry),
                        );
                      },
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData nimbusRouteHistoryDecisionIcon(NimbusRouteDecision decision) => switch (decision) {
  NimbusRouteDecision.direct => Icons.language_rounded,
  NimbusRouteDecision.accelerated => Icons.rocket_launch_rounded,
};

class _RouteHistoryToolbar extends ConsumerWidget {
  const _RouteHistoryToolbar({
    required this.state,
    required this.recordingEnabled,
    required this.searchController,
    required this.query,
    required this.selectedFilter,
    required this.selectedDecisionFilter,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onFilterChanged,
    required this.onDecisionFilterChanged,
    required this.onRecordingChanged,
  });

  final NimbusRouteHistoryState state;
  final bool recordingEnabled;
  final TextEditingController searchController;
  final String query;
  final NimbusRouteHistoryFilter selectedFilter;
  final NimbusRouteDecisionFilter selectedDecisionFilter;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<NimbusRouteHistoryFilter> onFilterChanged;
  final ValueChanged<NimbusRouteDecisionFilter> onDecisionFilterChanged;
  final ValueChanged<bool> onRecordingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final statusText = !recordingEnabled
        ? t.nimbus.routeHistory.recordingDisabled
        : state.activeCount > 0
        ? t.nimbus.routeHistory.recordingActive(count: state.activeCount)
        : state.isMonitoring
        ? t.nimbus.routeHistory.recording
        : t.nimbus.routeHistory.waiting;
    final statusColor = recordingEnabled && state.activeCount > 0
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          key: const Key('route-history-search'),
          controller: searchController,
          onChanged: onQueryChanged,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: t.nimbus.routeHistory.searchHint,
            prefixIcon: const Icon(Icons.search_rounded, key: Key('route-history-search-icon'), size: 20),
            prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 48),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(tooltip: t.common.clear, onPressed: onClearQuery, icon: const Icon(Icons.close_rounded)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        );
        final filterButton = _RouteHistoryFilterButton(
          selectedFilter: selectedFilter,
          selectedDecisionFilter: selectedDecisionFilter,
          onFilterChanged: onFilterChanged,
          onDecisionFilterChanged: onDecisionFilterChanged,
        );
        final status = Row(
          children: [
            Icon(
              recordingEnabled && state.activeCount > 0 ? Icons.radio_button_checked_rounded : Icons.history_rounded,
              size: 16,
              color: statusColor,
            ),
            const Gap(6),
            Expanded(
              child: Text(
                '$statusText · ${t.nimbus.routeHistory.count(count: state.entries.length, limit: nimbusRouteHistoryLimit)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: statusColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Gap(8),
            Text(t.nimbus.routeHistory.recordAccess, style: Theme.of(context).textTheme.bodySmall),
            const Gap(4),
            Switch.adaptive(
              key: const Key('route-history-recording-switch'),
              value: recordingEnabled,
              onChanged: onRecordingChanged,
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: search),
                const Gap(8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth < 520 ? 132 : 220),
                  child: filterButton,
                ),
              ],
            ),
            const Gap(10),
            status,
          ],
        );
      },
    );
  }
}

enum _RouteHistoryFilterAction { reset, direct, accelerated, active, completed }

class _RouteHistoryFilterButton extends ConsumerWidget {
  const _RouteHistoryFilterButton({
    required this.selectedFilter,
    required this.selectedDecisionFilter,
    required this.onFilterChanged,
    required this.onDecisionFilterChanged,
  });

  final NimbusRouteHistoryFilter selectedFilter;
  final NimbusRouteDecisionFilter selectedDecisionFilter;
  final ValueChanged<NimbusRouteHistoryFilter> onFilterChanged;
  final ValueChanged<NimbusRouteDecisionFilter> onDecisionFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final label = _filterLabel(t);
    if (PlatformUtils.isMobile) {
      return OutlinedButton.icon(
        key: const Key('route-history-filter'),
        onPressed: () => _showMobileFilter(context, t),
        icon: const Icon(Icons.filter_list_rounded),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return PopupMenuButton<_RouteHistoryFilterAction>(
      key: const Key('route-history-filter'),
      tooltip: t.nimbus.routeHistory.filterTooltip,
      onSelected: _apply,
      itemBuilder: (_) => _menuItems(t),
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.filter_list_rounded),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  String _filterLabel(Translations t) {
    final labels = <String>[
      if (selectedDecisionFilter == NimbusRouteDecisionFilter.direct) t.nimbus.routePreferences.directConnection,
      if (selectedDecisionFilter == NimbusRouteDecisionFilter.accelerated) t.nimbus.routePreferences.requiresConnection,
      if (selectedFilter == NimbusRouteHistoryFilter.active) t.nimbus.routeHistory.filterActive,
      if (selectedFilter == NimbusRouteHistoryFilter.completed) t.nimbus.routeHistory.filterCompleted,
    ];
    return labels.isEmpty ? t.nimbus.routeHistory.filterAllRecords : labels.join(' · ');
  }

  List<PopupMenuEntry<_RouteHistoryFilterAction>> _menuItems(Translations t) => [
    _menuItem(_filterOptions(t)[0]),
    const PopupMenuDivider(),
    _menuItem(_filterOptions(t)[1]),
    _menuItem(_filterOptions(t)[2]),
    const PopupMenuDivider(),
    _menuItem(_filterOptions(t)[3]),
    _menuItem(_filterOptions(t)[4]),
  ];

  List<({String label, _RouteHistoryFilterAction action, bool selected})> _filterOptions(Translations t) => [
    (
      action: _RouteHistoryFilterAction.reset,
      label: t.nimbus.routeHistory.filterAllRecords,
      selected:
          selectedFilter == NimbusRouteHistoryFilter.all && selectedDecisionFilter == NimbusRouteDecisionFilter.all,
    ),
    (
      action: _RouteHistoryFilterAction.direct,
      label: t.nimbus.routePreferences.directConnection,
      selected: selectedDecisionFilter == NimbusRouteDecisionFilter.direct,
    ),
    (
      action: _RouteHistoryFilterAction.accelerated,
      label: t.nimbus.routePreferences.requiresConnection,
      selected: selectedDecisionFilter == NimbusRouteDecisionFilter.accelerated,
    ),
    (
      action: _RouteHistoryFilterAction.active,
      label: t.nimbus.routeHistory.filterActive,
      selected: selectedFilter == NimbusRouteHistoryFilter.active,
    ),
    (
      action: _RouteHistoryFilterAction.completed,
      label: t.nimbus.routeHistory.filterCompleted,
      selected: selectedFilter == NimbusRouteHistoryFilter.completed,
    ),
  ];

  PopupMenuItem<_RouteHistoryFilterAction> _menuItem(
    ({String label, _RouteHistoryFilterAction action, bool selected}) option,
  ) {
    return PopupMenuItem(
      value: option.action,
      child: Row(
        children: [
          SizedBox(width: 24, child: option.selected ? const Icon(Icons.check_rounded, size: 18) : null),
          const Gap(8),
          Text(option.label),
        ],
      ),
    );
  }

  Future<void> _showMobileFilter(BuildContext context, Translations t) async {
    final action = await showModalBottomSheet<_RouteHistoryFilterAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final option in _filterOptions(t))
            ListTile(
              leading: SizedBox(width: 24, child: option.selected ? const Icon(Icons.check_rounded, size: 20) : null),
              title: Text(option.label),
              onTap: () => Navigator.of(sheetContext).pop(option.action),
            ),
        ],
      ),
    );
    if (action != null) _apply(action);
  }

  void _apply(_RouteHistoryFilterAction action) {
    switch (action) {
      case _RouteHistoryFilterAction.reset:
        onDecisionFilterChanged(NimbusRouteDecisionFilter.all);
        onFilterChanged(NimbusRouteHistoryFilter.all);
        return;
      case _RouteHistoryFilterAction.direct:
        onDecisionFilterChanged(
          selectedDecisionFilter == NimbusRouteDecisionFilter.direct
              ? NimbusRouteDecisionFilter.all
              : NimbusRouteDecisionFilter.direct,
        );
        return;
      case _RouteHistoryFilterAction.accelerated:
        onDecisionFilterChanged(
          selectedDecisionFilter == NimbusRouteDecisionFilter.accelerated
              ? NimbusRouteDecisionFilter.all
              : NimbusRouteDecisionFilter.accelerated,
        );
        return;
      case _RouteHistoryFilterAction.active:
        onFilterChanged(
          selectedFilter == NimbusRouteHistoryFilter.active
              ? NimbusRouteHistoryFilter.all
              : NimbusRouteHistoryFilter.active,
        );
        return;
      case _RouteHistoryFilterAction.completed:
        onFilterChanged(
          selectedFilter == NimbusRouteHistoryFilter.completed
              ? NimbusRouteHistoryFilter.all
              : NimbusRouteHistoryFilter.completed,
        );
        return;
    }
  }
}

class _RouteHistoryTile extends ConsumerWidget {
  const _RouteHistoryTile({required this.entry, required this.onTap});

  final NimbusRouteHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final colorScheme = Theme.of(context).colorScheme;
    final decisionColor = entry.decision == NimbusRouteDecision.direct ? colorScheme.tertiary : colorScheme.primary;
    final decisionLabel = entry.decision == NimbusRouteDecision.direct
        ? t.nimbus.routePreferences.directConnection
        : t.nimbus.routePreferences.requiresConnection;
    final statusLabel = entry.isActive ? t.nimbus.routeHistory.active : t.nimbus.routeHistory.completed;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final ruleLabel = entry.ruleDescription.isEmpty ? t.nimbus.routeHistory.defaultRule : entry.ruleDescription;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      isThreeLine: compact,
      leading: SizedBox.square(
        dimension: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: decisionColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(nimbusRouteHistoryDecisionIcon(entry.decision), color: decisionColor),
        ),
      ),
      title: Text(entry.endpoint, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        compact
            ? '$decisionLabel · $statusLabel\n${_formatShortDateTime(context, entry.startedAt)} · $ruleLabel'
            : '${_formatShortDateTime(context, entry.startedAt)} · $ruleLabel',
        maxLines: compact ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: compact
          ? const Icon(Icons.chevron_right_rounded)
          : Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _CompactLabel(label: decisionLabel, color: decisionColor),
                _CompactLabel(
                  label: statusLabel,
                  color: entry.isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
      onTap: onTap,
    );
  }
}

class _CompactLabel extends StatelessWidget {
  const _CompactLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      ),
    );
  }
}

class _RouteHistoryEmptyState extends StatelessWidget {
  const _RouteHistoryEmptyState({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.manage_search_rounded, size: 44, color: Theme.of(context).colorScheme.primary),
              const Gap(12),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const Gap(6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openRouteHistoryDetails(BuildContext context, WidgetRef ref, NimbusRouteHistoryEntry entry) async {
  if (shouldOpenNimbusRouteHistoryDetailsAsPage(isMobilePlatform: PlatformUtils.isMobile)) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => NimbusRouteHistoryDetailsPage(entry: entry)));
    return;
  }
  await _showRouteHistoryDetailsDialog(context, ref, entry);
}

@visibleForTesting
bool shouldOpenNimbusRouteHistoryDetailsAsPage({required bool isMobilePlatform}) => isMobilePlatform;

class NimbusRouteHistoryDetailsPage extends ConsumerWidget {
  const NimbusRouteHistoryDetailsPage({super.key, required this.entry});

  final NimbusRouteHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final action = _routeHistoryRuleAction(t, entry);
    return Scaffold(
      appBar: AppBar(title: Text(t.nimbus.routeHistory.detailsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [_RouteHistoryDetailsBody(entry: entry)],
        ),
      ),
      bottomNavigationBar: action == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => _addOppositeRoutePreference(
                    context,
                    ref,
                    domain: action.domain,
                    requestedType: action.requestedType,
                  ),
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(t.nimbus.routeHistory.addRule(category: action.requestedLabel)),
                ),
              ),
            ),
    );
  }
}

Future<void> _showRouteHistoryDetailsDialog(BuildContext context, WidgetRef ref, NimbusRouteHistoryEntry entry) async {
  final t = ref.read(translationsProvider).requireValue;
  final action = _routeHistoryRuleAction(t, entry);
  final shouldAdd = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.nimbus.routeHistory.detailsTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 560),
        child: SingleChildScrollView(child: _RouteHistoryDetailsBody(entry: entry)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(t.common.close)),
        if (action != null)
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.add_link_rounded),
            label: Text(t.nimbus.routeHistory.addRule(category: action.requestedLabel)),
          ),
      ],
    ),
  );
  if ((shouldAdd ?? false) && context.mounted && action != null) {
    await _addOppositeRoutePreference(context, ref, domain: action.domain, requestedType: action.requestedType);
  }
}

class _RouteHistoryDetailsBody extends ConsumerWidget {
  const _RouteHistoryDetailsBody({required this.entry});

  final NimbusRouteHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DetailRow(label: t.nimbus.routeHistory.target, value: entry.endpoint),
        _DetailRow(
          label: t.nimbus.routeHistory.finalDecision,
          value: entry.decision == NimbusRouteDecision.direct
              ? t.nimbus.routePreferences.directConnection
              : t.nimbus.routePreferences.requiresConnection,
        ),
        _DetailRow(
          label: t.nimbus.routeHistory.status,
          value: entry.isActive ? t.nimbus.routeHistory.active : t.nimbus.routeHistory.completed,
        ),
        _DetailRow(label: t.nimbus.routeHistory.startedAt, value: _formatFullDateTime(entry.startedAt)),
        _DetailRow(
          label: t.nimbus.routeHistory.completedAt,
          value: entry.completedAt == null
              ? t.nimbus.routeHistory.notCompleted
              : _formatFullDateTime(entry.completedAt!),
        ),
        _DetailRow(
          label: t.nimbus.routeHistory.matchedRule,
          value: entry.ruleDescription.isEmpty ? t.nimbus.routeHistory.defaultRule : entry.ruleDescription,
        ),
        if (entry.destinationIp.isNotEmpty)
          _DetailRow(label: t.nimbus.routeHistory.address, value: entry.destinationIp),
        if (entry.network.isNotEmpty)
          _DetailRow(label: t.nimbus.routeHistory.network, value: entry.network.toUpperCase()),
      ],
    );
  }
}

({String domain, String requestedType, String requestedLabel})? _routeHistoryRuleAction(
  Translations t,
  NimbusRouteHistoryEntry entry,
) {
  final domain = normalizeNimbusDomain(entry.host);
  if (domain == null) return null;
  final requestedType = oppositeNimbusRoutePreferenceType(entry.decision);
  return (
    domain: domain,
    requestedType: requestedType,
    requestedLabel: requestedType == 'accelerate'
        ? t.nimbus.routePreferences.requiresConnection
        : t.nimbus.routePreferences.directConnection,
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const Gap(12),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

Future<void> _addOppositeRoutePreference(
  BuildContext context,
  WidgetRef ref, {
  required String domain,
  required String requestedType,
}) async {
  final t = ref.read(translationsProvider).requireValue;
  final session = ref.read(nimbusAuthControllerProvider).session;
  if (session == null) return;
  final repository = ref.read(nimbusAuthRepositoryProvider);
  final requestedLabel = requestedType == 'accelerate'
      ? t.nimbus.routePreferences.requiresConnection
      : t.nimbus.routePreferences.directConnection;
  final existingLabel = requestedType == 'accelerate'
      ? t.nimbus.routePreferences.directConnection
      : t.nimbus.routePreferences.requiresConnection;
  final selectedDomain = await showNimbusRouteHistoryDomainSelector(
    context,
    t: t,
    observedDomain: domain,
    categoryLabel: requestedLabel,
  );
  if (selectedDomain == null || !context.mounted) return;

  try {
    final preferences = await repository.fetchRoutePreferences(session);
    final resolution = resolveNimbusRoutePreference(
      items: preferences.items,
      limit: preferences.limit,
      domain: selectedDomain,
      requestedType: requestedType,
    );
    if (!context.mounted) return;
    if (resolution.decision == NimbusRoutePreferenceDecision.duplicate) {
      _showMessage(context, t.nimbus.routePreferences.alreadyInCategory(category: requestedLabel));
      return;
    }
    if (resolution.decision == NimbusRoutePreferenceDecision.limitReached) {
      _showMessage(context, t.nimbus.routePreferences.limitReached);
      return;
    }

    if (resolution.decision == NimbusRoutePreferenceDecision.switchType) {
      final confirmed = await _showAdaptiveConfirmation(
        context: context,
        title: t.nimbus.routePreferences.switchTitle,
        message: t.nimbus.routePreferences.switchConfirm(
          domain: selectedDomain,
          from: existingLabel,
          to: requestedLabel,
        ),
        confirmLabel: t.nimbus.routePreferences.switchAction,
        cancelLabel: t.common.cancel,
      );
      if (!(confirmed ?? false)) return;
    }

    if (resolution.existing == null) {
      await repository.createRoutePreference(session: session, type: requestedType, input: selectedDomain);
    } else {
      await repository.updateRoutePreference(session: session, id: resolution.existing!.id, type: requestedType);
    }
    await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected(userRulesOnly: true);
    if (context.mounted) {
      _showMessage(context, t.nimbus.routeHistory.ruleAdded(domain: selectedDomain, category: requestedLabel));
    }
  } catch (error) {
    if (repository.isUnauthorized(error)) {
      await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
    }
    if (context.mounted) _showMessage(context, repository.describeError(error, t));
  }
}

@visibleForTesting
Future<String?> showNimbusRouteHistoryDomainSelector(
  BuildContext context, {
  required Translations t,
  required String observedDomain,
  required String categoryLabel,
}) {
  final mainDomain = registrableNimbusDomain(observedDomain);
  final distinctMainDomain = mainDomain == null || mainDomain == observedDomain ? null : mainDomain;

  if (PlatformUtils.isMobile) {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: SingleChildScrollView(
          child: _RouteHistoryDomainSelector(
            t: t,
            observedDomain: observedDomain,
            mainDomain: distinctMainDomain,
            categoryLabel: categoryLabel,
            showTitle: true,
            onSelected: (domain) => Navigator.of(sheetContext).pop(domain),
          ),
        ),
      ),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.nimbus.routeHistory.chooseDomainTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 420, maxWidth: 520),
        child: SingleChildScrollView(
          child: _RouteHistoryDomainSelector(
            t: t,
            observedDomain: observedDomain,
            mainDomain: distinctMainDomain,
            categoryLabel: categoryLabel,
            showTitle: false,
            onSelected: (domain) => Navigator.of(dialogContext).pop(domain),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(t.common.cancel))],
    ),
  );
}

enum _RouteHistoryDomainChoice { observed, main, custom }

class _RouteHistoryDomainSelector extends StatefulWidget {
  const _RouteHistoryDomainSelector({
    required this.t,
    required this.observedDomain,
    required this.mainDomain,
    required this.categoryLabel,
    required this.showTitle,
    required this.onSelected,
  });

  final Translations t;
  final String observedDomain;
  final String? mainDomain;
  final String categoryLabel;
  final bool showTitle;
  final ValueChanged<String> onSelected;

  @override
  State<_RouteHistoryDomainSelector> createState() => _RouteHistoryDomainSelectorState();
}

class _RouteHistoryDomainSelectorState extends State<_RouteHistoryDomainSelector> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  _RouteHistoryDomainChoice _choice = _RouteHistoryDomainChoice.observed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.observedDomain);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectChoice(_RouteHistoryDomainChoice? choice) {
    if (choice == null) return;
    setState(() {
      _choice = choice;
      _error = null;
    });
    if (choice == _RouteHistoryDomainChoice.custom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _submit() {
    final candidate = switch (_choice) {
      _RouteHistoryDomainChoice.observed => widget.observedDomain,
      _RouteHistoryDomainChoice.main => widget.mainDomain ?? widget.observedDomain,
      _RouteHistoryDomainChoice.custom => _controller.text,
    };
    final domain = normalizeNimbusDomain(candidate);
    if (domain == null) {
      setState(() => _error = widget.t.nimbus.routePreferences.domainInvalid);
      return;
    }
    widget.onSelected(domain);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return RadioGroup<_RouteHistoryDomainChoice>(
      groupValue: _choice,
      onChanged: _selectChoice,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle) ...[
            Text(t.nimbus.routeHistory.chooseDomainTitle, style: Theme.of(context).textTheme.titleLarge),
            const Gap(8),
          ],
          Text(t.nimbus.routeHistory.chooseDomainDescription(category: widget.categoryLabel)),
          const Gap(8),
          RadioListTile<_RouteHistoryDomainChoice>(
            contentPadding: EdgeInsets.zero,
            value: _RouteHistoryDomainChoice.observed,
            title: Text(widget.observedDomain),
            subtitle: Text(t.nimbus.routeHistory.currentDomainDescription),
          ),
          if (widget.mainDomain != null)
            RadioListTile<_RouteHistoryDomainChoice>(
              contentPadding: EdgeInsets.zero,
              value: _RouteHistoryDomainChoice.main,
              title: Text(widget.mainDomain!),
              subtitle: Text(t.nimbus.routeHistory.mainDomainDescription),
            ),
          RadioListTile<_RouteHistoryDomainChoice>(
            contentPadding: EdgeInsets.zero,
            value: _RouteHistoryDomainChoice.custom,
            title: Text(t.nimbus.routeHistory.customDomain),
            subtitle: Text(t.nimbus.routeHistory.customDomainDescription),
          ),
          if (_choice == _RouteHistoryDomainChoice.custom) ...[
            const Gap(4),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(nimbusDomainMaxLength)],
              decoration: InputDecoration(
                labelText: t.nimbus.routePreferences.domainLabel,
                prefixIcon: const Icon(Icons.language_rounded),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ] else if (_error != null) ...[
            const Gap(4),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Gap(16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.add_link_rounded),
            label: Text(t.nimbus.routeHistory.confirmDomain(category: widget.categoryLabel)),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _showAdaptiveConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) {
  if (PlatformUtils.isMobile) {
    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            const Gap(8),
            Text(message, style: Theme.of(sheetContext).textTheme.bodyMedium),
            const Gap(20),
            FilledButton(onPressed: () => Navigator.of(sheetContext).pop(true), child: Text(confirmLabel)),
          ],
        ),
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(cancelLabel)),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(confirmLabel)),
      ],
    ),
  );
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _formatShortDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  if (local.year == now.year && local.month == now.month && local.day == now.day) return time;
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} $time';
}

String _formatFullDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
