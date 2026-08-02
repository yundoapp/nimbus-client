import 'dart:async';
import 'dart:math';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nimbusDesktopBehaviorControllerProvider = NotifierProvider<NimbusDesktopBehaviorController, void>(
  NimbusDesktopBehaviorController.new,
);

class NimbusDesktopBehaviorController extends Notifier<void> with AppLogger {
  Timer? _autoConnectTimer;
  Timer? _debounceTimer;
  int _failedAttempts = 0;
  final _attemptCoordinator = NimbusAutoConnectAttemptCoordinator();

  @override
  void build() {
    ref.onDispose(() {
      _autoConnectTimer?.cancel();
      _debounceTimer?.cancel();
    });

    ref.listen(Preferences.nimbusAutoConnect, (_, enabled) {
      if (enabled) {
        scheduleAutoConnect(reason: 'auto connect enabled');
      } else {
        _cancelAutoConnect();
      }
    });
    ref.listen(nimbusAutoConnectSessionControllerProvider, (_, sessionAutoConnectAllowed) {
      if (sessionAutoConnectAllowed) {
        scheduleAutoConnect(reason: 'session auto connect restored');
      } else {
        _cancelAutoConnect();
      }
    });
    ref.listen(nimbusAuthControllerProvider, (previous, next) {
      final becameReady =
          next.isAuthenticated &&
          !next.isRestoring &&
          (previous == null || !previous.isAuthenticated || previous.isRestoring);
      if (becameReady) scheduleAutoConnect(reason: 'auth ready');
    });
    ref.listen(nimbusConnectionControllerProvider, (previous, next) {
      if (next.recoveryRequestId > 0 && next.recoveryRequestId != previous?.recoveryRequestId) {
        scheduleAutoConnect(reason: 'unexpected disconnect recovery');
      }
    });
    ref.listen(connectionNotifierProvider, (_, next) {
      final nimbusConnection = ref.read(nimbusConnectionControllerProvider);
      if (nimbusConnection.recoveryRequestId > 0 &&
          !nimbusConnection.connectedReported &&
          next.valueOrNull is Disconnected) {
        scheduleAutoConnect(reason: 'connection resources released', resetBackoff: false);
      }
    });
    unawaited(ensureStartupRecovery(reason: 'startup'));
    scheduleAutoConnect(reason: 'startup');
  }

  void scheduleAutoConnect({required String reason, bool resetBackoff = true}) {
    if (resetBackoff) _failedAttempts = 0;
    _autoConnectTimer?.cancel();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () => tryAutoConnect(reason: reason));
  }

  Future<void> tryAutoConnect({required String reason}) =>
      _attemptCoordinator.run(() => _tryAutoConnect(reason: reason));

  Future<void> _tryAutoConnect({required String reason}) async {
    if (!_shouldAttemptAutoConnect()) return;
    if (!await ensureStartupRecovery(reason: reason)) {
      if (_shouldAttemptAutoConnect()) _scheduleAutoConnectRetry();
      return;
    }
    var authState = ref.read(nimbusAuthControllerProvider);
    if (!authState.isAuthenticated || authState.isRestoring) return;
    var connection = ref.read(connectionNotifierProvider).valueOrNull;
    if (shouldRecoverWindowsOrphanedConnection(
      isWindows: PlatformUtils.isWindows,
      authState: authState,
      connection: connection,
    )) {
      loggy.warning(
        'Windows startup found an unmanaged existing connection before account details loaded; '
        'stopping it before retrying the account request',
      );
      await ref.read(connectionNotifierProvider.notifier).abortConnection();
      await ref.read(nimbusAuthControllerProvider.notifier).refreshMe();
      authState = ref.read(nimbusAuthControllerProvider);
      connection = ref.read(connectionNotifierProvider).valueOrNull;
    }

    if (!(authState.me?.subscription.hasActivePlan ?? false)) return;

    final version = await ref.read(nimbusAppVersionControllerProvider.notifier).check();
    if (version?.forceUpdate ?? false) return;
    if (!_shouldAttemptAutoConnect()) return;

    var nimbusConnection = ref.read(nimbusConnectionControllerProvider);
    if (isNimbusOwnedConnection(connection: connection, connectedReported: nimbusConnection.connectedReported)) {
      _failedAttempts = 0;
      _autoConnectTimer?.cancel();
      return;
    }
    if (shouldWaitForNimbusConnectionOwnership(
      connection: connection,
      connectedReported: nimbusConnection.connectedReported,
    )) {
      loggy.warning('startup found an unowned native connection; stopping it before auto connect');
      await ref.read(connectionNotifierProvider.notifier).abortConnection();
      final stopped = ref.read(connectionNotifierProvider).valueOrNull;
      if (stopped is Disconnected) {
        scheduleAutoConnect(reason: 'unowned connection stopped', resetBackoff: false);
      } else {
        _scheduleAutoConnectRetry();
      }
      return;
    }

    loggy.info('auto connect [$reason]');
    await ref.read(nimbusConnectionControllerProvider.notifier).connect(showErrors: false);
    final current = ref.read(connectionNotifierProvider).valueOrNull;
    nimbusConnection = ref.read(nimbusConnectionControllerProvider);
    if (isNimbusOwnedConnection(connection: current, connectedReported: nimbusConnection.connectedReported)) {
      _failedAttempts = 0;
      _autoConnectTimer?.cancel();
      return;
    }

    _scheduleAutoConnectRetry();
  }

  Future<bool> ensureStartupRecovery({required String reason}) {
    return ref.read(nimbusConnectionControllerProvider.notifier).ensureStartupRecovery(reason: reason);
  }

  void _scheduleAutoConnectRetry() {
    final retryDelay = nimbusAutoConnectRetryDelay(_failedAttempts);
    _failedAttempts += 1;
    loggy.info('auto connect retry scheduled in ${retryDelay.inMinutes} minute(s)');
    _autoConnectTimer?.cancel();
    _autoConnectTimer = Timer(retryDelay, () => tryAutoConnect(reason: 'retry after failure'));
  }

  bool _shouldAttemptAutoConnect() {
    return shouldAttemptNimbusAutoConnect(
      autoConnectEnabled: ref.read(Preferences.nimbusAutoConnect),
      sessionAutoConnectAllowed: ref.read(nimbusAutoConnectSessionControllerProvider),
    );
  }

  void _cancelAutoConnect() {
    _autoConnectTimer?.cancel();
    _debounceTimer?.cancel();
    _failedAttempts = 0;
  }

  Future<void> toggleConnectionFromTray() async {
    final authState = ref.read(nimbusAuthControllerProvider);
    final versionState = ref.read(nimbusAppVersionControllerProvider);
    if (!authState.isAuthenticated ||
        !(authState.me?.subscription.hasActivePlan ?? false) ||
        versionState.forceUpdate) {
      await ref.read(windowNotifierProvider.notifier).show();
      return;
    }
    await ref.read(nimbusConnectionControllerProvider.notifier).toggle();
  }
}

class NimbusAutoConnectAttemptCoordinator {
  Future<void>? _activeAttempt;

  Future<void> run(Future<void> Function() attempt) {
    final activeAttempt = _activeAttempt;
    if (activeAttempt != null) return activeAttempt;

    final future = attempt();
    _activeAttempt = future;
    return future.whenComplete(() {
      if (identical(_activeAttempt, future)) {
        _activeAttempt = null;
      }
    });
  }
}

bool shouldAttemptNimbusAutoConnect({required bool autoConnectEnabled, required bool sessionAutoConnectAllowed}) =>
    autoConnectEnabled && sessionAutoConnectAllowed;

bool shouldWaitForNimbusConnectionOwnership({required ConnectionStatus? connection, required bool connectedReported}) =>
    !isNimbusOwnedConnection(connection: connection, connectedReported: connectedReported) &&
    (connection is Connected || connection is Connecting || connection is Disconnecting);

bool shouldRecoverWindowsOrphanedConnection({
  required bool isWindows,
  required NimbusAuthState authState,
  required ConnectionStatus? connection,
}) =>
    isWindows && authState.isAuthenticated && !authState.isRestoring && authState.me == null && connection is Connected;

Duration nimbusAutoConnectRetryDelay(int failedAttempts) {
  const retryMinutes = [1, 2, 4, 8, 16, 30];
  return Duration(minutes: retryMinutes[min(max(failedAttempts, 0), retryMinutes.length - 1)]);
}
