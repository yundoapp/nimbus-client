import 'dart:async';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_acceleration_diagnostic.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _historyKey = 'yundo.acceleration_diagnostics.v1';
const _maxHistory = 30;

final nimbusAccelerationDiagnosticsProvider =
    NotifierProvider<NimbusAccelerationDiagnosticsController, NimbusAccelerationDiagnosticsState>(
      NimbusAccelerationDiagnosticsController.new,
    );

class NimbusAccelerationDiagnosticsController extends Notifier<NimbusAccelerationDiagnosticsState> {
  @override
  NimbusAccelerationDiagnosticsState build() {
    final preferences = ref.read(sharedPreferencesProvider).requireValue;
    return NimbusAccelerationDiagnosticsState(
      history: decodeNimbusAccelerationHistory(preferences.getString(_historyKey)),
    );
  }

  bool isOperationRunning(NimbusAccelerationOperation operation) =>
      state.current?.status == NimbusAccelerationAttemptStatus.running && state.current?.operation == operation;

  void begin(NimbusAccelerationOperation operation) {
    final stepIds = operation == NimbusAccelerationOperation.start
        ? nimbusAccelerationStartStepIds
        : nimbusAccelerationStopStepIds;
    state = state.copyWith(
      current: NimbusAccelerationAttempt(
        operation: operation,
        status: NimbusAccelerationAttemptStatus.running,
        startedAt: DateTime.now(),
        steps: stepIds.map((id) => NimbusAccelerationStepSnapshot(id: id)).toList(growable: false),
      ),
    );
    _persist();
  }

  void startStep(NimbusAccelerationStepId id, {String? detail}) {
    final current = state.current;
    if (current == null || current.status != NimbusAccelerationAttemptStatus.running) return;
    final now = DateTime.now();
    state = state.copyWith(
      current: current.copyWith(
        steps: _updateStep(
          current.steps,
          id,
          (step) => step.copyWith(
            status: NimbusAccelerationStepStatus.running,
            detail: detail,
            startedAt: step.startedAt ?? now,
          ),
        ),
      ),
    );
    _persist();
  }

  void completeStep(NimbusAccelerationStepId id, {String? detail}) {
    final current = state.current;
    if (current == null || current.status != NimbusAccelerationAttemptStatus.running) return;
    final now = DateTime.now();
    state = state.copyWith(
      current: current.copyWith(
        steps: _updateStep(
          current.steps,
          id,
          (step) => step.copyWith(
            status: NimbusAccelerationStepStatus.success,
            detail: detail ?? step.detail,
            startedAt: step.startedAt ?? now,
            completedAt: now,
          ),
        ),
      ),
    );
    _persist();
  }

  void failStep(NimbusAccelerationStepId id, {required String detail, String? errorCode}) {
    final current = state.current;
    if (current == null || current.status != NimbusAccelerationAttemptStatus.running) return;
    final now = DateTime.now();
    state = state.copyWith(
      current: current.copyWith(
        steps: _updateStep(
          current.steps,
          id,
          (step) => step.copyWith(
            status: NimbusAccelerationStepStatus.failure,
            detail: detail,
            startedAt: step.startedAt ?? now,
            completedAt: now,
            errorCode: errorCode,
          ),
        ),
      ),
    );
    _persist();
  }

  void complete({String? detail}) {
    final current = state.current;
    if (current == null || current.status != NimbusAccelerationAttemptStatus.running) return;
    final completed = current.copyWith(
      status: NimbusAccelerationAttemptStatus.success,
      completedAt: DateTime.now(),
      errorDetail: detail,
    );
    _finish(completed);
  }

  void fail({required String errorCode, required String detail}) {
    final current = state.current;
    if (current == null || current.status != NimbusAccelerationAttemptStatus.running) return;
    final failed = current.copyWith(
      status: NimbusAccelerationAttemptStatus.failure,
      completedAt: DateTime.now(),
      errorCode: errorCode,
      errorDetail: detail,
    );
    _finish(failed);
  }

  void _finish(NimbusAccelerationAttempt attempt) {
    final history = [attempt, ...state.history].take(_maxHistory).toList(growable: false);
    state = NimbusAccelerationDiagnosticsState(current: attempt, history: history);
    _persist();
  }

  List<NimbusAccelerationStepSnapshot> _updateStep(
    List<NimbusAccelerationStepSnapshot> steps,
    NimbusAccelerationStepId id,
    NimbusAccelerationStepSnapshot Function(NimbusAccelerationStepSnapshot step) update,
  ) {
    return steps.map((step) => step.id == id ? update(step) : step).toList(growable: false);
  }

  void _persist() {
    final preferences = ref.read(sharedPreferencesProvider).requireValue;
    unawaited(preferences.setString(_historyKey, encodeNimbusAccelerationHistory(state.history)));
  }
}
