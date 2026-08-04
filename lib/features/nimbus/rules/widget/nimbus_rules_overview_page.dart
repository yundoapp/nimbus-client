import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_route_preferences_provider.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_access_icons.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_route_preferences_dialog.dart';
import 'package:hiddify/features/nimbus/rules/notifier/nimbus_rules_state.dart';
import 'package:hiddify/utils/date_time_formatter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusRulesOverviewPage extends ConsumerStatefulWidget {
  const NimbusRulesOverviewPage({super.key});

  @override
  ConsumerState<NimbusRulesOverviewPage> createState() => _NimbusRulesOverviewPageState();
}

class _NimbusRulesOverviewPageState extends ConsumerState<NimbusRulesOverviewPage> {
  bool _publicExpanded = false;
  bool _userExpanded = false;

  Future<void> _openEditor({NimbusRoutePreference? preference}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => NimbusRoutePreferenceEditorDialog(preference: preference),
    );
    if (changed == true && mounted) {
      ref.invalidate(nimbusRoutePreferencesProvider);
      ref.invalidate(nimbusCachedRulesPackageProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final package = ref.watch(nimbusCachedRulesPackageProvider);
    final preferences = ref.watch(nimbusRoutePreferencesProvider);
    final publicItems = [
      for (final item in package?.publicRules ?? const <NimbusRulePackageItem>[])
        if (item.pattern.trim().isNotEmpty)
          _RuleItem(
            pattern: item.pattern,
            patternType: item.patternType,
            action: _ruleAction(item.action),
            updatedAt: package?.cachedAt,
          ),
    ];
    final userItems = preferences.when(
      data: (value) => [
        for (final item in value?.items ?? const <NimbusRoutePreference>[])
          if (item.value.trim().isNotEmpty)
            _RuleItem(
              pattern: item.value,
              patternType: item.targetType,
              action: _ruleAction(item.type),
              updatedAt: item.updatedAt ?? item.createdAt,
              preference: item,
            ),
      ],
      loading: () => null,
      error: (_, _) => const <_RuleItem>[],
    );
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
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _RuleGroupCard(
                  title: t.nimbus.rules.commonRules,
                  count: publicItems.length,
                  caption: t.nimbus.rules.commonVersion(version: package?.manifest.publicRulesVersion ?? '--'),
                  items: publicItems,
                  expanded: _publicExpanded,
                  onToggle: publicItems.length > _rulesPreviewLimit
                      ? () => setState(() => _publicExpanded = !_publicExpanded)
                      : null,
                  translations: t,
                ),
                const SizedBox(height: 16),
                _RuleGroupCard(
                  title: t.nimbus.rules.myRules,
                  count: userItems?.length ?? 0,
                  caption: t.nimbus.rules.myRulesPriorityHint,
                  items: userItems,
                  expanded: _userExpanded,
                  onToggle: (userItems?.length ?? 0) > _rulesPreviewLimit
                      ? () => setState(() => _userExpanded = !_userExpanded)
                      : null,
                  translations: t,
                  onItemTap: (item) => _openEditor(preference: item.preference),
                  onAdd: () => _openEditor(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _rulesPreviewLimit = 10;

class _RuleGroupCard extends StatelessWidget {
  const _RuleGroupCard({
    required this.title,
    required this.count,
    required this.caption,
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.translations,
    this.onItemTap,
    this.onAdd,
  });

  final String title;
  final int count;
  final String caption;
  final List<_RuleItem>? items;
  final bool expanded;
  final VoidCallback? onToggle;
  final Translations translations;
  final ValueChanged<_RuleItem>? onItemTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = items != null;
    final visibleItems = items == null
        ? const <_RuleItem>[]
        : expanded
        ? items!
        : items!.take(_rulesPreviewLimit).toList(growable: false);
    final hasMore = (items?.length ?? 0) > _rulesPreviewLimit;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title · ${translations.nimbus.rules.count(count: count)}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        caption,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (onAdd != null)
                  IconButton(
                    tooltip: translations.nimbus.rules.addRule,
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
          ),
          if (!loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (visibleItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
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
                onTap: onItemTap == null ? null : () => onItemTap!(visibleItems[index]),
              ),
              if (index < visibleItems.length - 1) const Divider(height: 1, indent: 76),
            ],
            if (hasMore)
              _ExpandRulesButton(
                expanded: expanded,
                onPressed: onToggle,
                label: expanded ? translations.nimbus.rules.collapse : translations.nimbus.rules.expand,
              ),
          ],
        ],
      ),
    );
  }
}

class _ExpandRulesButton extends StatelessWidget {
  const _ExpandRulesButton({required this.expanded, required this.onPressed, required this.label});

  final bool expanded;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
    label: Text(label),
  );
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.item, required this.translations, this.onTap});

  final _RuleItem item;
  final Translations translations;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionColor = _actionColor(theme.colorScheme, item.action);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox.square(dimension: 42, child: Icon(_actionIcon(item.action), color: actionColor, size: 22)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.pattern, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 3,
                  children: [
                    Text(
                      _targetTypeLabel(translations, item.patternType),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_actionIcon(item.action), size: 15, color: actionColor),
                        const SizedBox(width: 4),
                        Text(
                          _actionLabel(translations, item.action),
                          style: theme.textTheme.bodySmall?.copyWith(color: actionColor),
                        ),
                      ],
                    ),
                    Text(
                      _updatedLabel(translations, item.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    return InkWell(onTap: onTap, child: content);
  }
}

class _RuleItem {
  const _RuleItem({
    required this.pattern,
    required this.patternType,
    required this.action,
    this.updatedAt,
    this.preference,
  });

  final String pattern;
  final String patternType;
  final _RuleAction action;
  final DateTime? updatedAt;
  final NimbusRoutePreference? preference;
}

enum _RuleAction { accelerate, direct, block }

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

String _updatedLabel(Translations t, DateTime? updatedAt) {
  final value = updatedAt?.toLocal().format() ?? t.nimbus.rules.notUpdated;
  return '${t.nimbus.rules.updatedAt}: $value';
}

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
