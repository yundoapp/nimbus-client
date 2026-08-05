import 'dart:convert';

enum NimbusAccelerationOperation { start, stop }

enum NimbusAccelerationAttemptStatus { running, success, failure }

enum NimbusAccelerationStepStatus { pending, running, success, failure }

enum NimbusAccelerationStepId {
  account,
  subscription,
  connectionState,
  rules,
  connectionPlan,
  // Kept for decoding diagnostic records written before the core stage was split.
  core,
  coreConfig,
  corePrepare,
  coreStart,
  coreVerify,
  ruleSets,
  coreStop,
  coreStopVerify,
  network,
  tunnel,
  routing,
  cleanup,
}

const nimbusAccelerationStartStepIds = <NimbusAccelerationStepId>[
  NimbusAccelerationStepId.connectionState,
  NimbusAccelerationStepId.account,
  NimbusAccelerationStepId.subscription,
  NimbusAccelerationStepId.rules,
  NimbusAccelerationStepId.connectionPlan,
  NimbusAccelerationStepId.coreConfig,
  NimbusAccelerationStepId.corePrepare,
  NimbusAccelerationStepId.coreStart,
  NimbusAccelerationStepId.coreVerify,
  NimbusAccelerationStepId.ruleSets,
  NimbusAccelerationStepId.network,
  NimbusAccelerationStepId.tunnel,
  NimbusAccelerationStepId.routing,
  NimbusAccelerationStepId.cleanup,
];

const nimbusAccelerationStopStepIds = <NimbusAccelerationStepId>[
  NimbusAccelerationStepId.connectionState,
  NimbusAccelerationStepId.coreStop,
  NimbusAccelerationStepId.coreStopVerify,
  NimbusAccelerationStepId.tunnel,
  NimbusAccelerationStepId.routing,
  NimbusAccelerationStepId.cleanup,
];

class NimbusAccelerationStepSnapshot {
  const NimbusAccelerationStepSnapshot({
    required this.id,
    this.status = NimbusAccelerationStepStatus.pending,
    this.detail,
    this.startedAt,
    this.completedAt,
    this.errorCode,
  });

  final NimbusAccelerationStepId id;
  final NimbusAccelerationStepStatus status;
  final String? detail;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? errorCode;

  NimbusAccelerationStepSnapshot copyWith({
    NimbusAccelerationStepStatus? status,
    Object? detail = _unset,
    Object? startedAt = _unset,
    Object? completedAt = _unset,
    Object? errorCode = _unset,
  }) {
    return NimbusAccelerationStepSnapshot(
      id: id,
      status: status ?? this.status,
      detail: identical(detail, _unset) ? this.detail : detail as String?,
      startedAt: identical(startedAt, _unset) ? this.startedAt : startedAt as DateTime?,
      completedAt: identical(completedAt, _unset) ? this.completedAt : completedAt as DateTime?,
      errorCode: identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.name,
    'status': status.name,
    if (detail != null) 'detail': detail,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (errorCode != null) 'errorCode': errorCode,
  };

  factory NimbusAccelerationStepSnapshot.fromJson(Map<String, dynamic> json) {
    final id = NimbusAccelerationStepId.values.byName(json['id'] as String);
    final status = NimbusAccelerationStepStatus.values.byName(json['status'] as String);
    return NimbusAccelerationStepSnapshot(
      id: id,
      status: status,
      detail: json['detail'] as String?,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      errorCode: json['errorCode'] as String?,
    );
  }
}

NimbusAccelerationStepId? runningNimbusAccelerationStepId(Iterable<NimbusAccelerationStepSnapshot> steps) {
  for (final step in steps.toList(growable: false).reversed) {
    if (step.status == NimbusAccelerationStepStatus.running) return step.id;
  }
  return null;
}

class NimbusAccelerationAttempt {
  const NimbusAccelerationAttempt({
    required this.operation,
    required this.status,
    required this.startedAt,
    required this.steps,
    this.completedAt,
    this.errorCode,
    this.errorDetail,
  });

  final NimbusAccelerationOperation operation;
  final NimbusAccelerationAttemptStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<NimbusAccelerationStepSnapshot> steps;
  final String? errorCode;
  final String? errorDetail;

  NimbusAccelerationAttempt copyWith({
    NimbusAccelerationAttemptStatus? status,
    Object? completedAt = _unset,
    List<NimbusAccelerationStepSnapshot>? steps,
    Object? errorCode = _unset,
    Object? errorDetail = _unset,
  }) {
    return NimbusAccelerationAttempt(
      operation: operation,
      status: status ?? this.status,
      startedAt: startedAt,
      completedAt: identical(completedAt, _unset) ? this.completedAt : completedAt as DateTime?,
      steps: steps ?? this.steps,
      errorCode: identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
      errorDetail: identical(errorDetail, _unset) ? this.errorDetail : errorDetail as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'operation': operation.name,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
    if (errorCode != null) 'errorCode': errorCode,
    if (errorDetail != null) 'errorDetail': errorDetail,
  };

  factory NimbusAccelerationAttempt.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final steps = rawSteps is List
        ? rawSteps
              .whereType<Map>()
              .map((item) => NimbusAccelerationStepSnapshot.fromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <NimbusAccelerationStepSnapshot>[];
    return NimbusAccelerationAttempt(
      operation: NimbusAccelerationOperation.values.byName(json['operation'] as String),
      status: NimbusAccelerationAttemptStatus.values.byName(json['status'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      steps: steps,
      errorCode: json['errorCode'] as String?,
      errorDetail: json['errorDetail'] as String?,
    );
  }
}

class NimbusAccelerationDiagnosticsState {
  const NimbusAccelerationDiagnosticsState({this.current, this.history = const []});

  final NimbusAccelerationAttempt? current;
  final List<NimbusAccelerationAttempt> history;

  bool get isRunning => current?.status == NimbusAccelerationAttemptStatus.running;

  NimbusAccelerationDiagnosticsState copyWith({Object? current = _unset, List<NimbusAccelerationAttempt>? history}) {
    return NimbusAccelerationDiagnosticsState(
      current: identical(current, _unset) ? this.current : current as NimbusAccelerationAttempt?,
      history: history ?? this.history,
    );
  }
}

const _unset = Object();

String encodeNimbusAccelerationHistory(List<NimbusAccelerationAttempt> attempts) =>
    jsonEncode(attempts.map((attempt) => attempt.toJson()).toList(growable: false));

List<NimbusAccelerationAttempt> decodeNimbusAccelerationHistory(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => NimbusAccelerationAttempt.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}
