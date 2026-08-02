import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'window_notifier.g.dart';

const minimumWindowSize = Size(368, 568);
const defaultWindowSize = Size(868, 668);
const _applicationLifecycleChannel = MethodChannel('yundo.application.lifecycle');

@Riverpod(keepAlive: true)
class WindowNotifier extends _$WindowNotifier with AppLogger {
  Future<void>? _shutdownFuture;

  @override
  Future<void> build() async {
    if (!PlatformUtils.isDesktop) return;

    if (Platform.isMacOS) {
      _applicationLifecycleChannel.setMethodCallHandler(_handleNativeLifecycleCall);
      ref.onDispose(() => _applicationLifecycleChannel.setMethodCallHandler(null));
    }

    // if (Platform.isWindows) {
    //   loggy.debug("ensuring single instance");
    //   await WindowsSingleInstance.ensureSingleInstance([], "Hiddify");
    // }

    await windowManager.ensureInitialized();
    await initWindowState();
  }

  Future<void> saveWindowState() async {
    if (await windowManager.isMaximized()) {
      await ref.read(Preferences.windowMaximized.notifier).update(true);
    } else {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();

      await ref.read(Preferences.windowMaximized.notifier).update(false);
      await ref.read(Preferences.windowSize.notifier).update(size);
      await ref.read(Preferences.windowPosition.notifier).update(position);
    }
  }

  Future<void> initWindowState() async {
    final isMaximized = ref.read(Preferences.windowMaximized);
    loggy.debug("window state. maximized: $isMaximized");
    final size = ref.read(Preferences.windowSize);
    loggy.debug("window state. size: $size");
    final position = ref.read(Preferences.windowPosition);
    final isWindowVisible = position != null && await checkWindowVisivility(position, size);
    loggy.debug("window state. position: ${isWindowVisible ? position : "centered"}");
    final silentStart = ref.read(Preferences.silentStart);
    loggy.debug("window state. silent start: ${silentStart ? "Enabled" : "Disabled"}");

    await windowManager.waitUntilReadyToShow(
      WindowOptions(size: size, center: !isWindowVisible, minimumSize: minimumWindowSize),
    );
    if (isWindowVisible) {
      await windowManager.setPosition(position);
      loggy.debug("restoring window to position: $position");
    } else {
      loggy.debug("no previous position found, centering window");
    }
    if (isMaximized) {
      await windowManager.maximize();
      loggy.debug("restoring window to maximized state");
    }
    if (!silentStart) {
      await ref.read(windowNotifierProvider.notifier).show(focus: false);
      loggy.debug("showing app window on start");
    } else {
      loggy.debug("silent start, remain hidden accessible via tray");
    }
  }

  Future<bool> checkWindowVisivility(Offset windowPos, Size windowSize, {double tolerance = 10.0}) async {
    final Rect windowRect = windowPos & windowSize;

    final displays = await screenRetriever.getAllDisplays();

    for (final display in displays) {
      if (display.visiblePosition == null || display.visibleSize == null) {
        continue;
      }
      final Rect monitorRect = display.visiblePosition! & display.visibleSize!;
      if (windowRect.left >= (monitorRect.left - tolerance) &&
          windowRect.top >= (monitorRect.top - tolerance) &&
          windowRect.right <= (monitorRect.right + tolerance) &&
          windowRect.bottom <= (monitorRect.bottom + tolerance)) {
        return true;
      }
    }
    return false;
  }

  Future<void> show({bool focus = true}) async {
    await windowManager.show();
    if (focus) await windowManager.focus();
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(false);
    }
  }

  Future<void> hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(true);
    }
  }

  Future<void> showOrHide() async {
    if (await windowManager.isVisible()) {
      await hide();
    } else {
      await show();
    }
  }

  Future<void> exit() async {
    await _shutdown();
    await _allowNativeTermination();
    await windowManager.destroy();
  }

  Future<void> _shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    final future = _shutdownInternal();
    _shutdownFuture = future;
    return future.whenComplete(() {
      if (identical(_shutdownFuture, future)) _shutdownFuture = null;
    });
  }

  Future<void> _shutdownInternal() async {
    await ref
        .read(nimbusConnectionControllerProvider.notifier)
        .shutdown()
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
          loggy.warning("error shutting down connection on quit", e);
        });
    await trayManager.destroy();
  }

  Future<void> _handleNativeLifecycleCall(MethodCall call) async {
    if (call.method != 'applicationShouldTerminate') return;
    loggy.info('macOS termination requested; waiting for native connection cleanup');
    await _shutdown();
    await _allowNativeTermination();
  }

  Future<void> _allowNativeTermination() async {
    if (!Platform.isMacOS) return;
    await _applicationLifecycleChannel.invokeMethod<void>('allowTerminate');
  }
}
