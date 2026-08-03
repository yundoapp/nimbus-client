import 'package:flutter/material.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/rules/notifier/nimbus_rules_state.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/date_time_formatter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusRulesOverviewPage extends ConsumerWidget {
  const NimbusRulesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final package = ref.watch(nimbusCachedRulesPackageProvider);
    final localRules = ref.watch(rulesNotifierProvider);
    final appInfo = ref.watch(appInfoProvider).valueOrNull;
    final groups = _buildRuleGroups(t, package, localRules);
    final ruleCount = groups.fold<int>(0, (total, group) => total + group.items.length);

    return Scaffold(
      appBar: AppBar(title: Text(t.nimbus.rules.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _RulesSummary(
                  translations: t,
                  package: package,
                  appVersion: appInfo?.presentVersion ?? '--',
                  ruleCount: ruleCount,
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: Text(t.nimbus.rules.currentRules, style: Theme.of(context).textTheme.titleMedium)),
                    Text(
                      t.nimbus.rules.count(count: ruleCount),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (groups.isEmpty)
                  _EmptyRules(label: t.nimbus.rules.empty)
                else
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var index = 0; index < groups.length; index++) ...[
                          _RuleGroup(group: groups[index], translations: t),
                          if (index < groups.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RulesSummary extends StatelessWidget {
  const _RulesSummary({
    required this.translations,
    required this.package,
    required this.appVersion,
    required this.ruleCount,
  });

  final Translations translations;
  final NimbusRulesPackage? package;
  final String appVersion;
  final int ruleCount;

  @override
  Widget build(BuildContext context) {
    final t = translations;
    final theme = Theme.of(context);
    final manifest = package?.manifest;
    final metadata = [
      (t.nimbus.rules.appVersion, appVersion),
      (t.nimbus.rules.rulesVersion, manifest?.publicRulesVersion ?? '--'),
      (t.nimbus.rules.customRulesVersion, _shortVersion(manifest?.userRulesVersion)),
      (t.nimbus.rules.lastUpdated, package?.cachedAt?.toLocal().format() ?? t.nimbus.rules.notUpdated),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.nimbus.rules.summary, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          t.nimbus.rules.summaryCount(count: ruleCount),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 28,
          runSpacing: 12,
          children: [for (final item in metadata) _SummaryItem(label: item.$1, value: item.$2)],
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 150, maxWidth: 300),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _RuleGroup extends StatelessWidget {
  const _RuleGroup({required this.group, required this.translations});

  final _RuleGroupData group;
  final Translations translations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            '${group.title} · ${translations.nimbus.rules.count(count: group.items.length)}',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        for (var index = 0; index < group.items.length; index++) ...[
          _RuleRow(item: group.items[index], translations: translations),
          if (index < group.items.length - 1) const Divider(height: 1, indent: 72),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.item, required this.translations});

  final _RuleItem item;
  final Translations translations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionColor = switch (item.action) {
      _RuleAction.accelerate => theme.colorScheme.primary,
      _RuleAction.direct => theme.colorScheme.tertiary,
      _RuleAction.block => theme.colorScheme.error,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(_actionIcon(item.action), color: actionColor),
      title: Text(item.pattern, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${item.sourceLabel} · ${_actionLabel(translations, item.action)}'),
      dense: true,
    );
  }
}

class _EmptyRules extends StatelessWidget {
  const _EmptyRules({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Center(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
  );
}

class _RuleGroupData {
  const _RuleGroupData({required this.title, required this.items});

  final String title;
  final List<_RuleItem> items;
}

class _RuleItem {
  const _RuleItem({required this.pattern, required this.sourceLabel, required this.action});

  final String pattern;
  final String sourceLabel;
  final _RuleAction action;
}

enum _RuleAction { accelerate, direct, block }

List<_RuleGroupData> _buildRuleGroups(Translations t, NimbusRulesPackage? package, List<Rule> localRules) {
  final groups = <_RuleGroupData>[];
  final customItems = [
    for (final item in package?.userRules ?? const <NimbusRulePackageItem>[])
      if (item.pattern.trim().isNotEmpty)
        _RuleItem(pattern: item.pattern, sourceLabel: t.nimbus.rules.custom, action: _ruleAction(item.action)),
  ];
  final publicItems = [
    for (final item in package?.publicRules ?? const <NimbusRulePackageItem>[])
      if (item.pattern.trim().isNotEmpty)
        _RuleItem(pattern: item.pattern, sourceLabel: t.nimbus.rules.public, action: _ruleAction(item.action)),
  ];
  final localItems = [
    for (final rule in localRules)
      _RuleItem(pattern: _nativeRulePattern(rule), sourceLabel: t.nimbus.rules.local, action: _nativeRuleAction(rule)),
  ];

  if (customItems.isNotEmpty) groups.add(_RuleGroupData(title: t.nimbus.rules.custom, items: customItems));
  if (publicItems.isNotEmpty) groups.add(_RuleGroupData(title: t.nimbus.rules.public, items: publicItems));
  if (localItems.isNotEmpty) groups.add(_RuleGroupData(title: t.nimbus.rules.local, items: localItems));
  return groups;
}

_RuleAction _ruleAction(String action) => switch (action.trim().toLowerCase()) {
  'direct' => _RuleAction.direct,
  'block' || 'reject' => _RuleAction.block,
  _ => _RuleAction.accelerate,
};

_RuleAction _nativeRuleAction(Rule rule) => switch (rule.outbound) {
  Outbound.direct || Outbound.direct_with_fragment => _RuleAction.direct,
  Outbound.block => _RuleAction.block,
  _ => _RuleAction.accelerate,
};

IconData _actionIcon(_RuleAction action) => switch (action) {
  _RuleAction.accelerate => Icons.rocket_launch_outlined,
  _RuleAction.direct => Icons.public_outlined,
  _RuleAction.block => Icons.block_outlined,
};

String _actionLabel(Translations t, _RuleAction action) => switch (action) {
  _RuleAction.accelerate => t.nimbus.rules.accelerate,
  _RuleAction.direct => t.nimbus.rules.direct,
  _RuleAction.block => t.nimbus.rules.block,
};

String _nativeRulePattern(Rule rule) {
  if (rule.hasName() && rule.name.trim().isNotEmpty) return rule.name;
  final values = <String>[
    ...rule.domains,
    ...rule.domainSuffixes,
    ...rule.domainKeywords,
    ...rule.ipCidrs,
    ...rule.ruleSets,
    ...rule.processNames,
  ];
  return values.firstWhere((value) => value.trim().isNotEmpty, orElse: () => '--');
}

String _shortVersion(String? version) {
  final value = version?.trim() ?? '';
  if (value.isEmpty) return '--';
  if (value.startsWith('sha256:')) return value.substring(0, 15);
  return value;
}
