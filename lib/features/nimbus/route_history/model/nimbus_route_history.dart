const nimbusRouteHistoryLimit = 500;

class NimbusTunnelTrafficStats {
  const NimbusTunnelTrafficStats({required this.uploadTotal, required this.downloadTotal});

  final int uploadTotal;
  final int downloadTotal;
}

NimbusTunnelTrafficStats? parseNimbusTunnelTrafficStats(Map<String, dynamic> payload) {
  final uploadTotal = _nonNegativeInt(payload['uploadTotal']);
  final downloadTotal = _nonNegativeInt(payload['downloadTotal']);
  if (uploadTotal == null || downloadTotal == null) return null;
  return NimbusTunnelTrafficStats(uploadTotal: uploadTotal, downloadTotal: downloadTotal);
}

enum NimbusRouteDecision { direct, accelerated, rejected, unknown }

enum NimbusRouteHistoryFilter { all, active, completed }

enum NimbusRouteDecisionFilter { all, direct, accelerated, rejected }

String? oppositeNimbusRoutePreferenceType(NimbusRouteDecision decision) => switch (decision) {
  NimbusRouteDecision.direct => 'accelerate',
  NimbusRouteDecision.accelerated => 'direct',
  NimbusRouteDecision.rejected => null,
  NimbusRouteDecision.unknown => null,
};

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

bool isNimbusAcceleratedRouteChain(Iterable<String> chains) =>
    chains.any((tag) => tag == 'nimbus-proxy' || tag == 'yundo-proxy' || tag == 'yundo-socks');

NimbusRouteDecision nimbusRouteDecisionFromConnection({
  required String exactDecision,
  required String outbound,
  required Iterable<String> chains,
}) {
  switch (exactDecision.trim().toLowerCase()) {
    case 'direct':
      return NimbusRouteDecision.direct;
    case 'accelerated':
      return NimbusRouteDecision.accelerated;
    case 'rejected':
      return NimbusRouteDecision.rejected;
  }
  final explicitOutbound = outbound.trim();
  if (isNimbusDirectRouteChain([explicitOutbound])) return NimbusRouteDecision.direct;
  if (isNimbusAcceleratedRouteChain([explicitOutbound])) return NimbusRouteDecision.accelerated;

  // Older Core builds did not expose outbound. Keep backwards compatibility
  // for records that do contain a terminal route tag, but never infer
  // acceleration merely because a connection reached `final`.
  final hasDirectChain = isNimbusDirectRouteChain(chains);
  final hasAcceleratedChain = isNimbusAcceleratedRouteChain(chains);
  if (hasDirectChain && !hasAcceleratedChain) return NimbusRouteDecision.direct;
  if (hasAcceleratedChain && !hasDirectChain) return NimbusRouteDecision.accelerated;
  return NimbusRouteDecision.unknown;
}

class NimbusRouteHistoryEntry {
  const NimbusRouteHistoryEntry({
    required this.id,
    required this.target,
    required this.host,
    required this.sourceIp,
    required this.sourcePort,
    required this.inboundType,
    required this.destinationIp,
    required this.destinationPort,
    required this.network,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.outbound,
    required this.decision,
    required this.startedAt,
    this.completedAt,
  });

  final String id;
  final String target;
  final String host;
  final String sourceIp;
  final String sourcePort;
  final String inboundType;
  final String destinationIp;
  final String destinationPort;
  final String network;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final String outbound;
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
    String? sourceIp,
    String? sourcePort,
    String? inboundType,
    String? destinationIp,
    String? destinationPort,
    String? network,
    String? rule,
    String? rulePayload,
    List<String>? chains,
    String? outbound,
    NimbusRouteDecision? decision,
    DateTime? startedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return NimbusRouteHistoryEntry(
      id: id,
      target: target ?? this.target,
      host: host ?? this.host,
      sourceIp: sourceIp ?? this.sourceIp,
      sourcePort: sourcePort ?? this.sourcePort,
      inboundType: inboundType ?? this.inboundType,
      destinationIp: destinationIp ?? this.destinationIp,
      destinationPort: destinationPort ?? this.destinationPort,
      network: network ?? this.network,
      rule: rule ?? this.rule,
      rulePayload: rulePayload ?? this.rulePayload,
      chains: chains ?? this.chains,
      outbound: outbound ?? this.outbound,
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
  final sourceIp = _stringValue(metadata['sourceIP']);
  final sourcePort = _stringValue(metadata['sourcePort']);
  final inboundType = _stringValue(metadata['type']);
  final destinationIp = _stringValue(metadata['destinationIP']);
  final target = host.isNotEmpty ? host : destinationIp;
  if (target.isEmpty) return null;
  final chains = switch (connection['chains']) {
    final List value => value.whereType<String>().toList(growable: false),
    _ => const <String>[],
  };
  final outbound = _stringValue(connection['outbound']);
  final parsedStart = DateTime.tryParse(_stringValue(connection['start']))?.toLocal();
  final parsedClosedAt = DateTime.tryParse(_stringValue(connection['closedAt']))?.toLocal();

  return NimbusRouteHistoryEntry(
    id: id,
    target: target,
    host: host,
    sourceIp: sourceIp,
    sourcePort: sourcePort,
    inboundType: inboundType,
    destinationIp: destinationIp,
    destinationPort: _stringValue(metadata['destinationPort']),
    network: _stringValue(metadata['network']).toLowerCase(),
    rule: _stringValue(connection['rule']),
    rulePayload: _stringValue(connection['rulePayload']),
    chains: List.unmodifiable(chains),
    outbound: outbound,
    decision: nimbusRouteDecisionFromConnection(
      exactDecision: _stringValue(connection['decision']),
      outbound: outbound,
      chains: chains,
    ),
    startedAt: parsedStart ?? observedAt,
    completedAt: parsedClosedAt,
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
    if (parsed.isActive) activeIds.add(parsed.id);
    final existing = byId[parsed.id];
    byId[parsed.id] = parsed.copyWith(
      startedAt: existing?.startedAt ?? parsed.startedAt,
      completedAt: parsed.completedAt,
      clearCompletedAt: parsed.isActive,
    );
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
        NimbusRouteDecisionFilter.rejected => entry.decision == NimbusRouteDecision.rejected,
      };
      if (!matchesStatus || !matchesDecision) return false;
      if (normalizedQuery.isEmpty) return true;
      return [
        entry.target,
        entry.sourceIp,
        entry.sourcePort,
        entry.inboundType,
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

List<Map<String, dynamic>> extractNimbusRouteConnections(
  Map<String, dynamic> payload, {
  bool requireExactDecision = false,
}) {
  final connections = payload['connections'];
  if (connections is! List) return const [];
  return List.unmodifiable(
    connections
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where((connection) => !requireExactDecision || _isNimbusExactRouteDecision(connection['decision'])),
  );
}

List<Map<String, dynamic>> extractNimbusMacOSTunnelConnections(
  Map<String, dynamic> payload, {
  bool requireExactDecision = false,
}) => extractNimbusRouteConnections(payload, requireExactDecision: requireExactDecision);

bool _isNimbusExactRouteDecision(Object? value) => switch (_stringValue(value).toLowerCase()) {
  'direct' || 'accelerated' || 'rejected' => true,
  _ => false,
};

String _stringValue(Object? value) => value?.toString().trim() ?? '';

int? _nonNegativeInt(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed >= 0 ? parsed : null;
}
