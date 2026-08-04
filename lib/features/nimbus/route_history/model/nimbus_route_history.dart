const nimbusRouteHistoryLimit = 500;

enum NimbusRouteDecision { direct, accelerated }

enum NimbusRouteHistoryFilter { all, active, completed }

enum NimbusRouteDecisionFilter { all, direct, accelerated }

String oppositeNimbusRoutePreferenceType(NimbusRouteDecision decision) =>
    decision == NimbusRouteDecision.direct ? 'accelerate' : 'direct';

String formatNimbusRouteTextForDisplay(String value) => value
    .replaceAll('nimbus-proxy', 'yundo-proxy')
    .replaceAll('nimbus-direct', 'yundo-direct')
    .replaceAll('yundo-socks', 'yundo-proxy');

bool isNimbusDirectRouteChain(Iterable<String> chains) => chains.any(
  (tag) =>
      tag == 'nimbus-direct' ||
      tag == 'yundo-direct' ||
      tag == 'direct \u00a7hide\u00a7' ||
      tag == 'bypass \u00a7hide\u00a7',
);

class NimbusRouteHistoryEntry {
  const NimbusRouteHistoryEntry({
    required this.id,
    required this.target,
    required this.host,
    required this.destinationIp,
    required this.destinationPort,
    required this.network,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.decision,
    required this.startedAt,
    this.completedAt,
  });

  final String id;
  final String target;
  final String host;
  final String destinationIp;
  final String destinationPort;
  final String network;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final NimbusRouteDecision decision;
  final DateTime startedAt;
  final DateTime? completedAt;

  bool get isActive => completedAt == null;
  String get endpoint => destinationPort.isEmpty ? target : '$target:$destinationPort';
  String get ruleDescription =>
      [rule, rulePayload].where((value) => value.isNotEmpty).map(formatNimbusRouteTextForDisplay).join(' / ');

  NimbusRouteHistoryEntry copyWith({
    String? target,
    String? host,
    String? destinationIp,
    String? destinationPort,
    String? network,
    String? rule,
    String? rulePayload,
    List<String>? chains,
    NimbusRouteDecision? decision,
    DateTime? startedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return NimbusRouteHistoryEntry(
      id: id,
      target: target ?? this.target,
      host: host ?? this.host,
      destinationIp: destinationIp ?? this.destinationIp,
      destinationPort: destinationPort ?? this.destinationPort,
      network: network ?? this.network,
      rule: rule ?? this.rule,
      rulePayload: rulePayload ?? this.rulePayload,
      chains: chains ?? this.chains,
      decision: decision ?? this.decision,
      startedAt: startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    );
  }
}

NimbusRouteHistoryEntry? parseNimbusRouteHistoryEntry(Map<String, dynamic> connection, {required DateTime observedAt}) {
  final id = _stringValue(connection['id']);
  if (id.isEmpty) return null;
  final metadata = switch (connection['metadata']) {
    final Map value => Map<String, dynamic>.from(value),
    _ => const <String, dynamic>{},
  };
  final host = _stringValue(metadata['host']).toLowerCase();
  final destinationIp = _stringValue(metadata['destinationIP']);
  final target = host.isNotEmpty ? host : destinationIp;
  if (target.isEmpty) return null;
  final chains = switch (connection['chains']) {
    final List value => value.whereType<String>().toList(growable: false),
    _ => const <String>[],
  };
  final parsedStart = DateTime.tryParse(_stringValue(connection['start']))?.toLocal();

  return NimbusRouteHistoryEntry(
    id: id,
    target: target,
    host: host,
    destinationIp: destinationIp,
    destinationPort: _stringValue(metadata['destinationPort']),
    network: _stringValue(metadata['network']).toLowerCase(),
    rule: _stringValue(connection['rule']),
    rulePayload: _stringValue(connection['rulePayload']),
    chains: List.unmodifiable(chains),
    decision: isNimbusDirectRouteChain(chains) ? NimbusRouteDecision.direct : NimbusRouteDecision.accelerated,
    startedAt: parsedStart ?? observedAt,
  );
}

List<NimbusRouteHistoryEntry> mergeNimbusRouteHistory({
  required Iterable<NimbusRouteHistoryEntry> previous,
  required Iterable<Map<String, dynamic>> snapshot,
  required DateTime observedAt,
  int limit = nimbusRouteHistoryLimit,
}) {
  final byId = <String, NimbusRouteHistoryEntry>{for (final entry in previous) entry.id: entry};
  final activeIds = <String>{};
  for (final raw in snapshot) {
    final parsed = parseNimbusRouteHistoryEntry(raw, observedAt: observedAt);
    if (parsed == null) continue;
    activeIds.add(parsed.id);
    final existing = byId[parsed.id];
    byId[parsed.id] = parsed.copyWith(startedAt: existing?.startedAt ?? parsed.startedAt, clearCompletedAt: true);
  }
  for (final entry in byId.values.toList(growable: false)) {
    if (entry.isActive && !activeIds.contains(entry.id)) {
      byId[entry.id] = entry.copyWith(completedAt: observedAt);
    }
  }
  final ordered = byId.values.toList()..sort((left, right) => right.startedAt.compareTo(left.startedAt));
  return List.unmodifiable(ordered.take(limit));
}

List<NimbusRouteHistoryEntry> completeNimbusRouteHistory(
  Iterable<NimbusRouteHistoryEntry> entries, {
  required DateTime completedAt,
}) => List.unmodifiable(entries.map((entry) => entry.isActive ? entry.copyWith(completedAt: completedAt) : entry));

List<NimbusRouteHistoryEntry> filterNimbusRouteHistory({
  required Iterable<NimbusRouteHistoryEntry> entries,
  required NimbusRouteHistoryFilter filter,
  required NimbusRouteDecisionFilter decisionFilter,
  required String query,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return List.unmodifiable(
    entries.where((entry) {
      final matchesStatus = switch (filter) {
        NimbusRouteHistoryFilter.all => true,
        NimbusRouteHistoryFilter.active => entry.isActive,
        NimbusRouteHistoryFilter.completed => !entry.isActive,
      };
      final matchesDecision = switch (decisionFilter) {
        NimbusRouteDecisionFilter.all => true,
        NimbusRouteDecisionFilter.direct => entry.decision == NimbusRouteDecision.direct,
        NimbusRouteDecisionFilter.accelerated => entry.decision == NimbusRouteDecision.accelerated,
      };
      if (!matchesStatus || !matchesDecision) return false;
      if (normalizedQuery.isEmpty) return true;
      return [
        entry.target,
        entry.destinationIp,
        entry.destinationPort,
        entry.network,
        entry.rule,
        entry.rulePayload,
        ...entry.chains,
      ].map(formatNimbusRouteTextForDisplay).any((value) => value.toLowerCase().contains(normalizedQuery));
    }),
  );
}

List<Map<String, dynamic>> extractNimbusRouteConnections(Map<String, dynamic> payload) {
  final connections = payload['connections'];
  if (connections is! List) return const [];
  return List.unmodifiable(connections.whereType<Map>().map(Map<String, dynamic>.from));
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';
