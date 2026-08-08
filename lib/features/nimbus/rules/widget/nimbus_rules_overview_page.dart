import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_route_preferences_provider.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_access_icons.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_route_preferences_dialog.dart';
import 'package:hiddify/features/nimbus/rules/data/nimbus_core_rule_set_status.dart';
import 'package:hiddify/features/nimbus/rules/notifier/nimbus_rules_state.dart';
import 'package:hiddify/features/nimbus/widget/nimbus_page_layout.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class NimbusRulesOverviewPage extends ConsumerStatefulWidget {
  const NimbusRulesOverviewPage({super.key});

  @override
  ConsumerState<NimbusRulesOverviewPage> createState() => _NimbusRulesOverviewPageState();
}

class _NimbusRulesOverviewPageState extends ConsumerState<NimbusRulesOverviewPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _coreRuleSetStatusRefreshTimer;
  String _query = '';
  _RulesActionFilter _actionFilter = _RulesActionFilter.all;
  _RulesOriginFilter _originFilter = _RulesOriginFilter.all;
  int _displayLimit = _rulesPageSize;
  int _availableItemCount = 0;
  bool _paging = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _coreRuleSetStatusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(nimbusCoreRuleSetStatusProvider);
    });
  }

  void _handleScroll() {
    if (_paging || !_scrollController.hasClients || _displayLimit >= _availableItemCount) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 280) return;
    _paging = true;
    setState(() => _displayLimit += _rulesPageSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paging = false;
    });
  }

  void _resetPaging() {
    _displayLimit = _rulesPageSize;
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _coreRuleSetStatusRefreshTimer?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _openEditor({NimbusRoutePreference? preference}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => NimbusRoutePreferenceEditorDialog(preference: preference),
    );
    if (changed == true && mounted) {
      ref.invalidate(nimbusRoutePreferencesProvider);
      ref.invalidate(nimbusCachedRulesPackageProvider);
      ref.invalidate(nimbusRulesPackageProvider);
      final t = ref.read(translationsProvider).requireValue;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.nimbus.routePreferences.cloudSyncSaved)));
    }
  }

  Future<void> _openEditorForRule(_RuleItem item) async {
    var preference = item.preference;
    if (preference == null) {
      ref.invalidate(nimbusRoutePreferencesProvider);
      try {
        final latest = await ref.read(nimbusRoutePreferencesProvider.future);
        final key = item.pattern.trim().toLowerCase();
        for (final candidate in latest?.items ?? const <NimbusRoutePreference>[]) {
          if (candidate.value.trim().toLowerCase() == key) {
            preference = candidate;
            break;
          }
        }
      } catch (_) {
        // Keep the existing page usable when the refresh cannot complete.
      }
    }
    if (!mounted) return;
    if (preference == null) {
      final t = ref.read(translationsProvider).requireValue;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nimbus.home.retry)));
      return;
    }
    await _openEditor(preference: preference);
  }

  Future<void> _showCommonRuleDetails(_RuleItem item) async {
    final t = ref.read(translationsProvider).requireValue;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.pattern),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RuleDetailLine(label: t.nimbus.rules.commonRules, value: t.nimbus.rules.publicReadOnly),
              _RuleDetailLine(label: t.nimbus.rules.ruleType, value: _targetTypeLabel(t, item.patternType)),
              _RuleDetailLine(label: t.nimbus.rules.accessMethod, value: _actionLabel(t, item.action)),
              if (item.version != null && item.version!.isNotEmpty)
                _RuleDetailLine(label: t.nimbus.rules.rulesVersion, value: item.version!),
              _RuleDetailLine(
                label: t.nimbus.rules.updatedAt,
                value: _updatedValue(t, item.updatedAt, ref.read(localePreferencesProvider).flutterLocale.toString()),
              ),
              const SizedBox(height: 12),
              Text(
                t.nimbus.rules.publicReadOnlyHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(t.common.close))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final localeTag = ref.watch(localePreferencesProvider).flutterLocale.toString();
    final authState = ref.watch(nimbusAuthControllerProvider);
    final packageAsync = ref.watch(nimbusRulesPackageProvider);
    final package = packageAsync.valueOrNull ?? ref.watch(nimbusCachedRulesPackageProvider);
    final coreRuleSetStatus = ref.watch(nimbusCoreRuleSetStatusProvider).valueOrNull ?? const <String, DateTime?>{};
    final preferences = ref.watch(nimbusRoutePreferencesProvider);
    final publicItems = package == null
        ? null
        : _sortRuleItems([
            for (final item in package.publicRules)
              if (item.pattern.trim().isNotEmpty)
                _RuleItem(
                  pattern: item.pattern,
                  patternType: item.patternType,
                  action: _ruleAction(item.action),
                  origin: _RuleOrigin.common,
                  version: package.manifest.publicRulesVersion,
                  // The Core timestamp is the source of truth for the rule
                  // set actually loaded by sing-box.
                  updatedAt: coreRuleSetStatus.containsKey(item.pattern)
                      ? coreRuleSetStatus[item.pattern]
                      : package.publicRulesLoadedAt,
                ),
          ]);
    final userItems = _buildUserRuleItems(package: package, preferences: preferences.valueOrNull);
    final allItems = package == null && userItems == null
        ? null
        : _sortRuleItems([...userItems ?? const <_RuleItem>[], ...publicItems ?? const <_RuleItem>[]]);
    final visibleItems = allItems == null
        ? null
        : _filterRuleItems(allItems, query: _query, action: _actionFilter, origin: _originFilter);
    _availableItemCount = visibleItems?.length ?? 0;
    final loading = allItems == null && (authState.isRestoring || preferences.isLoading || packageAsync.isLoading);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.nimbus.rules.title),
        actions: [
          IconButton.filledTonal(
            tooltip: t.nimbus.rules.addRule,
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: nimbusPageContentMaxWidth),
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _RulesPriorityBanner(message: t.nimbus.rules.myRulesPriorityHint),
                const SizedBox(height: 16),
                _RulesToolbar(
                  searchController: _searchController,
                  query: _query,
                  actionFilter: _actionFilter,
                  originFilter: _originFilter,
                  translations: t,
                  onQueryChanged: (value) => setState(() {
                    _query = value.trim().toLowerCase();
                    _resetPaging();
                  }),
                  onClearQuery: () {
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _resetPaging();
                    });
                  },
                  onActionChanged: (value) => setState(() {
                    _actionFilter = value;
                    _resetPaging();
                  }),
                  onOriginChanged: (value) => setState(() {
                    _originFilter = value;
                    _resetPaging();
                  }),
                ),
                const SizedBox(height: 16),
                _RulesListCard(
                  items: visibleItems,
                  totalCount: allItems?.length ?? 0,
                  commonVersion: package?.manifest.publicRulesVersion,
                  localeTag: localeTag,
                  displayLimit: _displayLimit,
                  loading: loading,
                  translations: t,
                  onItemTap: (item) {
                    if (item.origin == _RuleOrigin.custom) {
                      _openEditorForRule(item);
                    } else {
                      _showCommonRuleDetails(item);
                    }
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

const _rulesPageSize = 25;

class _RulesPriorityBanner extends StatelessWidget {
  const _RulesPriorityBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_done_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _RulesToolbar extends StatelessWidget {
  const _RulesToolbar({
    required this.searchController,
    required this.query,
    required this.actionFilter,
    required this.originFilter,
    required this.translations,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onActionChanged,
    required this.onOriginChanged,
  });

  final TextEditingController searchController;
  final String query;
  final _RulesActionFilter actionFilter;
  final _RulesOriginFilter originFilter;
  final Translations translations;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<_RulesActionFilter> onActionChanged;
  final ValueChanged<_RulesOriginFilter> onOriginChanged;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const Key('nimbus-rules-search'),
      controller: searchController,
      onChanged: onQueryChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: translations.nimbus.rules.searchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: translations.nimbus.rules.clearSearch,
                onPressed: onClearQuery,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final action = _RulesFilterMenu<_RulesActionFilter>(
      label: _actionFilterLabel(translations, actionFilter),
      tooltip: translations.nimbus.rules.filterAction,
      icon: Icons.tune_rounded,
      options: [
        _RulesFilterOption(
          value: _RulesActionFilter.all,
          label: translations.nimbus.rules.filterAll,
          selected: actionFilter == _RulesActionFilter.all,
        ),
        _RulesFilterOption(
          value: _RulesActionFilter.accelerate,
          label: translations.nimbus.rules.accelerate,
          selected: actionFilter == _RulesActionFilter.accelerate,
        ),
        _RulesFilterOption(
          value: _RulesActionFilter.direct,
          label: translations.nimbus.rules.direct,
          selected: actionFilter == _RulesActionFilter.direct,
        ),
        _RulesFilterOption(
          value: _RulesActionFilter.block,
          label: translations.nimbus.rules.block,
          selected: actionFilter == _RulesActionFilter.block,
        ),
      ],
      onSelected: onActionChanged,
    );
    final origin = _RulesFilterMenu<_RulesOriginFilter>(
      label: _originFilterLabel(translations, originFilter),
      tooltip: translations.nimbus.rules.filterSource,
      icon: Icons.layers_outlined,
      options: [
        _RulesFilterOption(
          value: _RulesOriginFilter.all,
          label: translations.nimbus.rules.filterAll,
          selected: originFilter == _RulesOriginFilter.all,
        ),
        _RulesFilterOption(
          value: _RulesOriginFilter.custom,
          label: translations.nimbus.rules.myRules,
          selected: originFilter == _RulesOriginFilter.custom,
        ),
        _RulesFilterOption(
          value: _RulesOriginFilter.common,
          label: translations.nimbus.rules.commonRules,
          selected: originFilter == _RulesOriginFilter.common,
        ),
      ],
      onSelected: onOriginChanged,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              action,
              const SizedBox(width: 8),
              origin,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: action),
                const SizedBox(width: 8),
                Expanded(child: origin),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RulesFilterMenu<T> extends StatelessWidget {
  const _RulesFilterMenu({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final List<_RulesFilterOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final option in options)
        CheckedPopupMenuItem<T>(value: option.value, checked: option.selected, child: Text(option.label)),
    ],
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _RulesFilterOption<T> {
  const _RulesFilterOption({required this.value, required this.label, required this.selected});

  final T value;
  final String label;
  final bool selected;
}

class _RulesListCard extends StatelessWidget {
  const _RulesListCard({
    required this.items,
    required this.totalCount,
    required this.commonVersion,
    required this.localeTag,
    required this.displayLimit,
    required this.loading,
    required this.translations,
    required this.onItemTap,
  });

  final List<_RuleItem>? items;
  final int totalCount;
  final String? commonVersion;
  final String localeTag;
  final int displayLimit;
  final bool loading;
  final Translations translations;
  final ValueChanged<_RuleItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = items == null ? const <_RuleItem>[] : items!.take(displayLimit).toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${translations.nimbus.rules.currentRules} · ${translations.nimbus.rules.count(count: totalCount)}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        translations.nimbus.rules.commonVersion(version: commonVersion ?? '--'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (visibleItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 26),
              child: Text(
                translations.nimbus.rules.empty,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            for (var index = 0; index < visibleItems.length; index++) ...[
              _RuleRow(
                item: visibleItems[index],
                translations: translations,
                localeTag: localeTag,
                onTap: () => onItemTap(visibleItems[index]),
              ),
              if (index < visibleItems.length - 1) const Divider(height: 1, indent: 76),
            ],
          ],
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.item, required this.translations, required this.localeTag, required this.onTap});

  final _RuleItem item;
  final Translations translations;
  final String localeTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionColor = _actionColor(theme.colorScheme, item.action);
    final sourceColor = item.origin == _RuleOrigin.custom ? theme.colorScheme.primary : theme.colorScheme.secondary;
    final sourceLabel = item.origin == _RuleOrigin.custom
        ? translations.nimbus.rules.myRules
        : translations.nimbus.rules.commonRules;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 42,
                child: Icon(_actionIcon(item.action), color: actionColor, size: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  final title = Text(
                    item.pattern,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  );
                  final meta = Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _RuleMetaLabel(label: sourceLabel, color: sourceColor),
                      Text(
                        _targetTypeLabel(translations, item.patternType),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  );
                  final access = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_actionIcon(item.action), size: 15, color: actionColor),
                      const SizedBox(width: 4),
                      Text(
                        _actionLabel(translations, item.action),
                        style: theme.textTheme.bodySmall?.copyWith(color: actionColor),
                      ),
                    ],
                  );
                  final updated = Text(
                    _updatedValue(translations, item.updatedAt, localeTag),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 5),
                        meta,
                        const SizedBox(height: 4),
                        Wrap(spacing: 12, runSpacing: 3, children: [access, updated]),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, const SizedBox(height: 5), meta],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [access, const SizedBox(height: 5), updated],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _RuleMetaLabel extends StatelessWidget {
  const _RuleMetaLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
  );
}

class _RuleDetailLine extends StatelessWidget {
  const _RuleDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _RuleItem {
  const _RuleItem({
    required this.pattern,
    required this.patternType,
    required this.action,
    required this.origin,
    this.updatedAt,
    this.preference,
    this.version,
  });

  final String pattern;
  final String patternType;
  final _RuleAction action;
  final _RuleOrigin origin;
  final DateTime? updatedAt;
  final NimbusRoutePreference? preference;
  final String? version;
}

enum _RuleAction { accelerate, direct, block }

enum _RuleOrigin { custom, common }

enum _RulesActionFilter { all, accelerate, direct, block }

enum _RulesOriginFilter { all, custom, common }

_RuleAction _ruleAction(String action) => switch (action.trim().toLowerCase()) {
  'direct' => _RuleAction.direct,
  'block' || 'reject' => _RuleAction.block,
  _ => _RuleAction.accelerate,
};

String _targetTypeLabel(Translations t, String type) => switch (type) {
  'ip' => t.nimbus.rules.ip,
  'cidr' => t.nimbus.rules.cidr,
  'geosite' || 'geoip' || 'rule_set' => t.nimbus.rules.ruleLibrary,
  _ => t.nimbus.rules.domain,
};

String _actionLabel(Translations t, _RuleAction action) => switch (action) {
  _RuleAction.accelerate => t.nimbus.rules.accelerate,
  _RuleAction.direct => t.nimbus.rules.direct,
  _RuleAction.block => t.nimbus.rules.block,
};

String _updatedValue(Translations t, DateTime? updatedAt, String localeTag) {
  if (updatedAt == null) return t.nimbus.rules.notUpdated;
  return DateFormat.yMd(localeTag).add_Hm().format(updatedAt.toLocal());
}

String _actionFilterLabel(Translations t, _RulesActionFilter filter) => switch (filter) {
  _RulesActionFilter.all => t.nimbus.rules.filterAction,
  _RulesActionFilter.accelerate => t.nimbus.rules.accelerate,
  _RulesActionFilter.direct => t.nimbus.rules.direct,
  _RulesActionFilter.block => t.nimbus.rules.block,
};

String _originFilterLabel(Translations t, _RulesOriginFilter filter) => switch (filter) {
  _RulesOriginFilter.all => t.nimbus.rules.filterSource,
  _RulesOriginFilter.custom => t.nimbus.rules.myRules,
  _RulesOriginFilter.common => t.nimbus.rules.commonRules,
};

List<_RuleItem> _filterRuleItems(
  List<_RuleItem> items, {
  required String query,
  required _RulesActionFilter action,
  required _RulesOriginFilter origin,
}) {
  return items
      .where((item) {
        final matchesAction = switch (action) {
          _RulesActionFilter.all => true,
          _RulesActionFilter.accelerate => item.action == _RuleAction.accelerate,
          _RulesActionFilter.direct => item.action == _RuleAction.direct,
          _RulesActionFilter.block => item.action == _RuleAction.block,
        };
        final matchesOrigin = switch (origin) {
          _RulesOriginFilter.all => true,
          _RulesOriginFilter.custom => item.origin == _RuleOrigin.custom,
          _RulesOriginFilter.common => item.origin == _RuleOrigin.common,
        };
        if (!matchesAction || !matchesOrigin) return false;
        if (query.isEmpty) return true;
        return '${item.pattern} ${item.patternType}'.toLowerCase().contains(query);
      })
      .toList(growable: false);
}

List<_RuleItem> _sortRuleItems(Iterable<_RuleItem> items) {
  final sorted = items.toList(growable: false);
  sorted.sort((a, b) {
    // Custom rules are shown first because they override common rules.
    final originOrder = _originSortOrder(a.origin).compareTo(_originSortOrder(b.origin));
    if (originOrder != 0) return originOrder;
    final actionOrder = _actionSortOrder(a.action).compareTo(_actionSortOrder(b.action));
    if (actionOrder != 0) return actionOrder;
    return a.pattern.toLowerCase().compareTo(b.pattern.toLowerCase());
  });
  return sorted;
}

List<_RuleItem>? _buildUserRuleItems({
  required NimbusRulesPackage? package,
  required NimbusRoutePreferencesList? preferences,
}) {
  if (package == null && preferences == null) return null;
  final preferencesByPattern = <String, NimbusRoutePreference>{
    for (final preference in preferences?.items ?? const <NimbusRoutePreference>[])
      if (preference.value.trim().isNotEmpty) preference.value.trim().toLowerCase(): preference,
  };
  final itemsByPattern = <String, _RuleItem>{};

  void addItem({
    required String pattern,
    required String patternType,
    required String action,
    String? id,
    DateTime? updatedAt,
  }) {
    final normalized = pattern.trim();
    if (normalized.isEmpty) return;
    final key = normalized.toLowerCase();
    final preference =
        preferencesByPattern[key] ??
        (id == null
            ? null
            : NimbusRoutePreference(
                id: id,
                type: action,
                targetType: patternType,
                value: normalized,
                createdAt: updatedAt,
                updatedAt: updatedAt,
              ));
    itemsByPattern[key] = _RuleItem(
      pattern: normalized,
      patternType: patternType,
      action: _ruleAction(action),
      origin: _RuleOrigin.custom,
      updatedAt: preference?.updatedAt ?? preference?.createdAt ?? updatedAt ?? package?.cachedAt,
      preference: preference,
    );
  }

  for (final item in package?.userRules ?? const <NimbusRulePackageItem>[]) {
    addItem(
      id: item.id,
      pattern: item.pattern,
      patternType: item.patternType,
      action: item.action,
      updatedAt: item.updatedAt,
    );
  }
  for (final preference in preferences?.items ?? const <NimbusRoutePreference>[]) {
    addItem(
      pattern: preference.value,
      patternType: preference.targetType,
      action: preference.type,
      updatedAt: preference.updatedAt ?? preference.createdAt,
    );
  }
  return _sortRuleItems(itemsByPattern.values);
}

int _originSortOrder(_RuleOrigin origin) => switch (origin) {
  _RuleOrigin.custom => 0,
  _RuleOrigin.common => 1,
};

int _actionSortOrder(_RuleAction action) => switch (action) {
  _RuleAction.accelerate => 0,
  _RuleAction.direct => 1,
  _RuleAction.block => 2,
};

IconData _actionIcon(_RuleAction action) => switch (action) {
  _RuleAction.accelerate => nimbusRouteAccessIcon(requiresConnection: true),
  _RuleAction.direct => nimbusRouteAccessIcon(requiresConnection: false),
  _RuleAction.block => Icons.block_rounded,
};

Color _actionColor(ColorScheme colorScheme, _RuleAction action) => switch (action) {
  _RuleAction.accelerate => colorScheme.primary,
  _RuleAction.direct => colorScheme.tertiary,
  _RuleAction.block => colorScheme.error,
};
