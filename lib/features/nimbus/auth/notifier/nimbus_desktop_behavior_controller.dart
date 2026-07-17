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
        _autoConnectTimer?.cancel();
        _debounceTimer?.cancel();
        _failedAttempts = 0;
      }
    });
    ref.listen(nimbusAuthControllerProvider, (previous, next) {
      final becameReady =
          next.isAuthenticated &&
          !next.isRestoring &&
          (previous == null || !previous.isAuthenticated || previous.isRestoring);
      if (becameReady) scheduleAutoConnect(reason: 'auth ready');
    });
    scheduleAutoConnect(reason: 'startup');
  }

  void scheduleAutoConnect({required String reason, bool resetBackoff = true}) {
    if (resetBackoff) _failedAttempts = 0;
    _autoConnectTimer?.cancel();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () => tryAutoConnect(reason: reason));
  }

  Future<void> tryAutoConnect({required String reason}) async {
    if (!ref.read(Preferences.nimbusAutoConnect)) return;

    final authState = ref.read(nimbusAuthControllerProvider);
    if (!authState.isAuthenticated || authState.isRestoring) return;
    if (!(authState.me?.subscription.hasActivePlan ?? false)) return;

    final version = await ref.read(nimbusAppVersionControllerProvider.notifier).check();
    if (version?.forceUpdate ?? false) return;

    final connection = ref.read(connectionNotifierProvider).valueOrNull;
    if (connection is Connected) {
      _failedAttempts = 0;
      _autoConnectTimer?.cancel();
      return;
    }
    if (connection is Connecting || connection is Disconnecting) return;

    loggy.info('auto connect [$reason]');
    await ref.read(nimbusConnectionControllerProvider.notifier).connect(showErrors: false);
    final current = ref.read(connectionNotifierProvider).valueOrNull;
    if (current is Connected) {
      _failedAttempts = 0;
      _autoConnectTimer?.cancel();
      return;
    }

    final retryDelay = nimbusAutoConnectRetryDelay(_failedAttempts);
    _failedAttempts += 1;
    loggy.info('auto connect retry scheduled in ${retryDelay.inMinutes} minute(s)');
    _autoConnectTimer?.cancel();
    _autoConnectTimer = Timer(retryDelay, () => tryAutoConnect(reason: 'retry after failure'));
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

Duration nimbusAutoConnectRetryDelay(int failedAttempts) {
  const retryMinutes = [1, 2, 4, 8, 16, 30];
  return Duration(minutes: retryMinutes[min(max(failedAttempts, 0), retryMinutes.length - 1)]);
}
