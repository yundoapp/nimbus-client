import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_start_notifier.g.dart';

String windowsStartupPackageName({required bool isDebug}) => isDebug ? 'Yundo.YundoDev' : 'Yundo.Yundo';

bool shouldEnableAutoStartByDefault({required bool initialized, required bool enabled}) => !initialized && !enabled;

@Riverpod(keepAlive: true)
class AutoStartNotifier extends _$AutoStartNotifier with InfraLogger {
  Timer? _timer;

  @override
  Future<bool> build() async {
    if (!PlatformUtils.isDesktop) return false;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    launchAtStartup.setup(
      appName: appInfo.name,
      appPath: Platform.resolvedExecutable,
      packageName: PlatformUtils.isWindows
          ? windowsStartupPackageName(isDebug: kDebugMode)
          : (kDebugMode ? 'app.yundo.client.dev' : 'app.yundo.client'),
    );
    var isEnabled = await launchAtStartup.isEnabled();
    final initialized = ref.read(Preferences.nimbusWindowsAutoStartInitialized);
    if (PlatformUtils.isWindows && shouldEnableAutoStartByDefault(initialized: initialized, enabled: isEnabled)) {
      await launchAtStartup.enable();
      isEnabled = await launchAtStartup.isEnabled();
    }
    if (PlatformUtils.isWindows && !initialized) {
      await ref.read(Preferences.nimbusWindowsAutoStartInitialized.notifier).update(true);
    }
    loggy.info("auto start is [${isEnabled ? "Enabled" : "Disabled"}]");
    _startTimer();
    ref.onDispose(() => _timer?.cancel());
    return isEnabled;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (timer) => updateStatus());
  }

  Future<bool> updateStatus() async {
    loggy.debug("update auto start status");
    final isEnabled = await launchAtStartup.isEnabled();
    state = AsyncValue.data(isEnabled);
    return isEnabled;
  }

  Future<void> enable() async {
    loggy.debug("enabling auto start");
    await launchAtStartup.enable();
    state = const AsyncValue.data(true);
  }

  Future<void> disable() async {
    loggy.debug("disabling auto start");
    await launchAtStartup.disable();
    state = const AsyncValue.data(false);
  }
}
