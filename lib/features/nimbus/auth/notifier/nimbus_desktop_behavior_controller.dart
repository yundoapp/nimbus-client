import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nimbusDesktopBehaviorControllerProvider = NotifierProvider<NimbusDesktopBehaviorController, void>(
  NimbusDesktopBehaviorController.new,
);

class NimbusDesktopBehaviorController extends Notifier<void> with AppLogger {
  Timer? _autoConnectTimer;
  Timer? _debounceTimer;

  @override
  void build() {
    if (!PlatformUtils.isDesktop) return;

    ref.onDispose(() {
      _autoConnectTimer?.cancel();
      _debounceTimer?.cancel();
    });

    ref.listen(Preferences.nimbusAutoConnect, (_, enabled) {
      if (enabled) scheduleAutoConnect(reason: 'auto connect enabled');
    });
    ref.listen(nimbusAuthControllerProvider, (_, __) => scheduleAutoConnect(reason: 'auth changed'));
    ref.listen(nimbusAppVersionControllerProvider, (_, __) => scheduleAutoConnect(reason: 'version changed'));

    _autoConnectTimer = Timer.periodic(const Duration(minutes: 1), (_) => tryAutoConnect(reason: 'desktop monitor'));
    scheduleAutoConnect(reason: 'startup');
  }

  void scheduleAutoConnect({required String reason}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () => tryAutoConnect(reason: reason));
  }

  Future<void> tryAutoConnect({required String reason}) async {
    if (!PlatformUtils.isDesktop || !ref.read(Preferences.nimbusAutoConnect)) return;

    final authState = ref.read(nimbusAuthControllerProvider);
    if (!authState.isAuthenticated || authState.isRestoring) return;
    if (!(authState.me?.subscription.hasActivePlan ?? false)) return;

    final version = await ref.read(nimbusAppVersionControllerProvider.notifier).check();
    if (version?.forceUpdate ?? false) return;

    final connection = ref.read(connectionNotifierProvider).valueOrNull;
    if (connection is Connected || connection is Connecting || connection is Disconnecting) return;

    final activeProfile = ref.read(activeProfileProvider).valueOrNull;
    if (activeProfile == null) {
      loggy.debug('skip auto connect: no active profile [$reason]');
      return;
    }

    loggy.info('auto connect [$reason]');
    await ref.read(connectionNotifierProvider.notifier).mayConnect();
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
    await ref.read(connectionNotifierProvider.notifier).toggleConnection();
  }
}
