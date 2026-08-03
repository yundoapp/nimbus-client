import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/rules/notifier/nimbus_rules_state.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusRulesOverviewPage extends ConsumerWidget {
  const NimbusRulesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final cachedPackage = ref.watch(nimbusCachedRulesPackageProvider);
    final managedOptions = ref.watch(nimbusManagedRouteOptionsProvider);
    final currentRuntimeRules = ref.watch(nimbusCurrentRuntimeRulesProvider);
    final localRules = ref.watch(rulesNotifierProvider);
    final connection = ref.watch(nimbusConnectionControllerProvider);
    final isRuntimeLoaded = connection.isPreparing || connection.isDisconnecting || connection.connectedReported;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.nimbus.rules.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(t.nimbus.rules.description, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                _RulesStatusCard(
                  translations: t,
                  package: cachedPackage,
                  isRuntimeLoaded: isRuntimeLoaded,
                  runtimeText: isRuntimeLoaded ? t.nimbus.rules.runtimeLoaded : t.nimbus.rules.runtimeNotLoaded,
                ),
                const SizedBox(height: 20),
                _RulesSection(
                  title: t.nimbus.rules.runtimeSection,
                  children: [
                    _RuleListTile(
                      title: t.nimbus.rules.runtimeRules,
                      count: managedOptions.rules.length,
                      countLabel: t.nimbus.rules.count(count: managedOptions.rules.length),
                      items: managedOptions.rules,
                      emptyLabel: t.nimbus.rules.empty,
                      rawLabel: t.nimbus.rules.raw,
                    ),
                    _RuleListTile(
                      title: t.nimbus.rules.runtimeRuleSets,
                      count: managedOptions.ruleSets.length,
                      countLabel: t.nimbus.rules.librariesCount(count: managedOptions.ruleSets.length),
                      items: managedOptions.ruleSets,
                      emptyLabel: t.nimbus.rules.empty,
                      rawLabel: t.nimbus.rules.raw,
                    ),
                    if (currentRuntimeRules != null) ...[
                      _RuleListTile(
                        title: t.nimbus.rules.effectiveRules,
                        count: currentRuntimeRules['rules'] is List ? (currentRuntimeRules['rules'] as List).length : 0,
                        countLabel: t.nimbus.rules.count(
                          count: currentRuntimeRules['rules'] is List
                              ? (currentRuntimeRules['rules'] as List).length
                              : 0,
                        ),
                        items: _asMapList(currentRuntimeRules['rules']),
                        emptyLabel: t.nimbus.rules.empty,
                        rawLabel: t.nimbus.rules.raw,
                      ),
                      _RuleListTile(
                        title: t.nimbus.rules.effectiveRuleSets,
                        count: currentRuntimeRules['rule_set'] is List
                            ? (currentRuntimeRules['rule_set'] as List).length
                            : 0,
                        countLabel: t.nimbus.rules.librariesCount(
                          count: currentRuntimeRules['rule_set'] is List
                              ? (currentRuntimeRules['rule_set'] as List).length
                              : 0,
                        ),
                        items: _asMapList(currentRuntimeRules['rule_set']),
                        emptyLabel: t.nimbus.rules.empty,
                        rawLabel: t.nimbus.rules.raw,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                _RulesSection(
                  title: t.nimbus.rules.packageSection,
                  children: [
                    _PackageRuleListTile(
                      title: t.nimbus.rules.userRules,
                      items: cachedPackage?.userRules ?? const [],
                      emptyLabel: t.nimbus.rules.empty,
                      rawLabel: t.nimbus.rules.raw,
                      countLabel: t.nimbus.rules.count,
                    ),
                    _PackageRuleListTile(
                      title: t.nimbus.rules.publicRules,
                      items: cachedPackage?.publicRules ?? const [],
                      emptyLabel: t.nimbus.rules.empty,
                      rawLabel: t.nimbus.rules.raw,
                      countLabel: t.nimbus.rules.count,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _RulesSection(
                  title: t.nimbus.rules.localSection,
                  children: [
                    _NativeRuleListTile(
                      title: t.nimbus.rules.localRules,
                      rules: localRules,
                      emptyLabel: t.nimbus.rules.empty,
                      rawLabel: t.nimbus.rules.raw,
                      countLabel: t.nimbus.rules.count,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RulesStatusCard extends StatelessWidget {
  const _RulesStatusCard({
    required this.translations,
    required this.package,
    required this.isRuntimeLoaded,
    required this.runtimeText,
  });

  final Translations translations;
  final NimbusRulesPackage? package;
  final bool isRuntimeLoaded;
  final String runtimeText;

  @override
  Widget build(BuildContext context) {
    final t = translations;
    final theme = Theme.of(context);
    final manifest = package?.manifest;
    final rows = <(String, String)>[
      (t.nimbus.rules.status, runtimeText),
      (t.nimbus.rules.versionPublic, manifest?.publicRulesVersion ?? '-'),
      (t.nimbus.rules.versionUser, manifest?.userRulesVersion ?? '-'),
      (t.nimbus.rules.versionConfig, manifest?.configVersion ?? '-'),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isRuntimeLoaded ? Icons.check_circle_rounded : Icons.inventory_2_rounded,
                  color: isRuntimeLoaded ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(runtimeText, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < rows.length; index++) ...[
              _InfoRow(label: rows[index].$1, value: rows[index].$2),
              if (index < rows.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _RulesSection extends StatelessWidget {
  const _RulesSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, bottom: 8),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) const Divider(height: 1, indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleListTile extends StatelessWidget {
  const _RuleListTile({
    required this.title,
    required this.count,
    required this.countLabel,
    required this.items,
    required this.emptyLabel,
    required this.rawLabel,
  });

  final String title;
  final int count;
  final String countLabel;
  final List<Map<String, dynamic>> items;
  final String emptyLabel;
  final String rawLabel;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.rule_rounded),
    title: Text(title),
    subtitle: Text(count == 0 ? emptyLabel : countLabel),
    children: [for (final item in items) _RawRuleTile(data: item, rawLabel: rawLabel)],
  );
}

class _PackageRuleListTile extends StatelessWidget {
  const _PackageRuleListTile({
    required this.title,
    required this.items,
    required this.emptyLabel,
    required this.rawLabel,
    required this.countLabel,
  });

  final String title;
  final List<NimbusRulePackageItem> items;
  final String emptyLabel;
  final String rawLabel;
  final String Function({required int count}) countLabel;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.public_rounded),
      title: Text(title),
      subtitle: Text(items.isEmpty ? emptyLabel : countLabel(count: items.length)),
      children: [
        for (final item in items) _RawRuleTile(data: item.toJson(), summary: item.pattern, rawLabel: rawLabel),
      ],
    );
  }
}

class _NativeRuleListTile extends StatelessWidget {
  const _NativeRuleListTile({
    required this.title,
    required this.rules,
    required this.emptyLabel,
    required this.rawLabel,
    required this.countLabel,
  });

  final String title;
  final List<Rule> rules;
  final String emptyLabel;
  final String rawLabel;
  final String Function({required int count}) countLabel;

  @override
  Widget build(BuildContext context) {
    final items = rules
        .map((rule) => rule.toProto3Json())
        .whereType<Map>()
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList(growable: false);
    return ExpansionTile(
      leading: const Icon(Icons.tune_rounded),
      title: Text(title),
      subtitle: Text(items.isEmpty ? emptyLabel : countLabel(count: items.length)),
      children: [for (final item in items) _RawRuleTile(data: item, rawLabel: rawLabel)],
    );
  }
}

class _RawRuleTile extends StatelessWidget {
  const _RawRuleTile({required this.data, required this.rawLabel, this.summary});

  final Map<String, dynamic> data;
  final String rawLabel;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final json = const JsonEncoder.withIndent('  ').convert(data);
    return ExpansionTile(
      tilePadding: const EdgeInsetsDirectional.only(start: 56, end: 16),
      title: Text(summary ?? _ruleSummary(data)),
      subtitle: Text(rawLabel),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
      children: [SelectableText(json, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'))],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 132, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Expanded(child: SelectableText(value)),
    ],
  );
}

String _ruleSummary(Map<String, dynamic> data) {
  for (final key in ['domain_suffix', 'domain', 'ip_cidr', 'rule_set', 'process_name', 'pattern', 'tag']) {
    final value = data[key];
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String && value.isNotEmpty) return value;
  }
  return data['action']?.toString() ?? '{}';
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
}
