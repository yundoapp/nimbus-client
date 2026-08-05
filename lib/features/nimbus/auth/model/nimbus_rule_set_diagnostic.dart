enum NimbusRuleSetDiagnosticStatus { pending, loaded, loadedWithFailure, failure }

class NimbusRuleSetDiagnostic {
  const NimbusRuleSetDiagnostic({required this.tag, required this.status, this.detail});

  final String tag;
  final NimbusRuleSetDiagnosticStatus status;
  final String? detail;
}

class NimbusRuleSetDiagnosticsResult {
  const NimbusRuleSetDiagnosticsResult(this.items);

  final List<NimbusRuleSetDiagnostic> items;

  bool get hasFailure => items.any((item) => item.status == NimbusRuleSetDiagnosticStatus.failure);
  bool get allResolved => items.every((item) => item.status != NimbusRuleSetDiagnosticStatus.pending);

  NimbusRuleSetDiagnostic? get firstUpdateFailure {
    for (final item in items) {
      if (item.status == NimbusRuleSetDiagnosticStatus.loadedWithFailure) return item;
    }
    return null;
  }

  NimbusRuleSetDiagnostic? get firstFailure {
    for (final item in items) {
      if (item.status == NimbusRuleSetDiagnosticStatus.failure) return item;
    }
    return null;
  }
}

Set<String> nimbusRemoteRuleSetTagsFromConfig(Map<String, dynamic> config) {
  final route = config['route'];
  if (route is! Map || route['rule_set'] is! List) return const {};
  return {
    for (final item in route['rule_set'] as List)
      if (item is Map && item['type'] == 'remote' && item['tag'] is String && (item['tag'] as String).isNotEmpty)
        item['tag'] as String,
  };
}

NimbusRuleSetDiagnosticsResult parseNimbusRuleSetDiagnostics({
  required Iterable<String> logMessages,
  required Iterable<String> tags,
}) {
  final states = <String, NimbusRuleSetDiagnostic>{
    for (final tag in tags.where((tag) => tag.trim().isNotEmpty))
      tag: NimbusRuleSetDiagnostic(tag: tag, status: NimbusRuleSetDiagnosticStatus.pending),
  };
  if (states.isEmpty) return const NimbusRuleSetDiagnosticsResult([]);

  for (final message in logMessages) {
    final normalized = message.trim();
    for (final tag in states.keys) {
      final prefix = 'rule-set $tag:';
      final markerIndex = normalized.indexOf(prefix);
      if (markerIndex < 0) continue;
      final detail = normalized.substring(markerIndex + prefix.length).trim();
      final status = switch (detail) {
        'loaded from cache' || 'download completed' => NimbusRuleSetDiagnosticStatus.loaded,
        _ when detail.startsWith('download failed:') =>
          states[tag]!.status == NimbusRuleSetDiagnosticStatus.loaded
              ? NimbusRuleSetDiagnosticStatus.loadedWithFailure
              : NimbusRuleSetDiagnosticStatus.failure,
        _ => states[tag]!.status,
      };
      states[tag] = NimbusRuleSetDiagnostic(tag: tag, status: status, detail: detail);
    }

    for (final tag in states.keys) {
      if (normalized.contains('updated rule-set $tag') || normalized.contains('update rule-set $tag: not modified')) {
        states[tag] = NimbusRuleSetDiagnostic(
          tag: tag,
          status: NimbusRuleSetDiagnosticStatus.loaded,
          detail: normalized,
        );
      }
      final fetchMarker = normalized.indexOf('fetch rule-set $tag:');
      if (fetchMarker >= 0) {
        states[tag] = NimbusRuleSetDiagnostic(
          tag: tag,
          status: NimbusRuleSetDiagnosticStatus.failure,
          detail: normalized.substring(fetchMarker + 'fetch rule-set $tag:'.length).trim(),
        );
      }
    }
  }

  return NimbusRuleSetDiagnosticsResult(states.values.toList(growable: false));
}
