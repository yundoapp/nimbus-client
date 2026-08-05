import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_acceleration_diagnostic.dart';

void main() {
  test('start diagnostics expose every acceleration lifecycle stage in order', () {
    expect(
      nimbusAccelerationStartStepIds,
      equals([
        NimbusAccelerationStepId.connectionState,
        NimbusAccelerationStepId.account,
        NimbusAccelerationStepId.subscription,
        NimbusAccelerationStepId.rules,
        NimbusAccelerationStepId.connectionPlan,
        NimbusAccelerationStepId.core,
        NimbusAccelerationStepId.network,
        NimbusAccelerationStepId.tunnel,
        NimbusAccelerationStepId.routing,
        NimbusAccelerationStepId.cleanup,
      ]),
    );
  });

  test('round trips a completed acceleration attempt without sensitive data', () {
    final startedAt = DateTime.utc(2026, 8, 5, 1, 30);
    final attempt = NimbusAccelerationAttempt(
      operation: NimbusAccelerationOperation.start,
      status: NimbusAccelerationAttemptStatus.failure,
      startedAt: startedAt,
      completedAt: startedAt.add(const Duration(seconds: 4)),
      errorCode: 'Y-NETWORK-001',
      errorDetail: 'accelerated IPv4 probe failed',
      steps: [
        NimbusAccelerationStepSnapshot(
          id: NimbusAccelerationStepId.account,
          status: NimbusAccelerationStepStatus.success,
          detail: 'session is available',
          startedAt: startedAt,
          completedAt: startedAt.add(const Duration(milliseconds: 100)),
        ),
        NimbusAccelerationStepSnapshot(
          id: NimbusAccelerationStepId.network,
          status: NimbusAccelerationStepStatus.failure,
          detail: 'accelerated IPv4 probe failed',
          errorCode: 'NETWORK_PROBE_FAILED',
          startedAt: startedAt.add(const Duration(seconds: 1)),
          completedAt: startedAt.add(const Duration(seconds: 4)),
        ),
      ],
    );

    final decoded = decodeNimbusAccelerationHistory(encodeNimbusAccelerationHistory([attempt]));

    expect(decoded, hasLength(1));
    expect(decoded.single.operation, NimbusAccelerationOperation.start);
    expect(decoded.single.status, NimbusAccelerationAttemptStatus.failure);
    expect(decoded.single.errorCode, 'Y-NETWORK-001');
    expect(decoded.single.steps[1].id, NimbusAccelerationStepId.network);
    expect(decoded.single.steps[1].errorCode, 'NETWORK_PROBE_FAILED');
  });

  test('finds the last running stage for uncaught failures', () {
    expect(
      runningNimbusAccelerationStepId([
        const NimbusAccelerationStepSnapshot(
          id: NimbusAccelerationStepId.rules,
          status: NimbusAccelerationStepStatus.success,
        ),
        const NimbusAccelerationStepSnapshot(
          id: NimbusAccelerationStepId.connectionPlan,
          status: NimbusAccelerationStepStatus.running,
        ),
        const NimbusAccelerationStepSnapshot(
          id: NimbusAccelerationStepId.core,
          status: NimbusAccelerationStepStatus.running,
        ),
      ]),
      NimbusAccelerationStepId.core,
    );
    expect(
      runningNimbusAccelerationStepId([
        const NimbusAccelerationStepSnapshot(
          id: NimbusAccelerationStepId.rules,
          status: NimbusAccelerationStepStatus.success,
        ),
      ]),
      isNull,
    );
  });

  test('ignores malformed persisted history instead of blocking app startup', () {
    expect(decodeNimbusAccelerationHistory('{bad json'), isEmpty);
    expect(decodeNimbusAccelerationHistory('[{"operation":"unknown"}]'), isEmpty);
  });
}
