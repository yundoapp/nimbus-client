import 'dart:io';

import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_desktop_behavior_controller.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_notifier.g.dart';

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with TrayListener, AppLogger {
  bool listenerAdded = false;
  @override
  Future<void> build() async {
    assert(PlatformUtils.isDesktop);
    if (!listenerAdded) {
      trayManager.addListener(this);
      listenerAdded = true;
    }
    await _initializeTray();
  }

  Future<void> _initializeTray() async {
    final t = await ref.watch(translationsProvider.future);
    final urlTestDelay = await ref
        .watch(activeProxyNotifierProvider.future)
        .catchError((e) {
          loggy.warning("error getting active proxy", e);
          return OutboundInfo(urlTestDelay: 0);
        })
        .then((connection) => connection.urlTestDelay);
    final connection = await ref.watch(connectionNotifierProvider.future).catchError((e) {
      loggy.warning("error getting connection status", e);
      return const ConnectionStatus.disconnected();
    });

    await trayManager.setIcon(_trayIconPath(), isTemplate: PlatformUtils.isMacOS);
    if (!PlatformUtils.isLinux) await trayManager.setToolTip(_trayTooltip(t, connection, urlTestDelay));
    await trayManager.setContextMenu(_trayMenu(t, connection));
  }

  Menu _trayMenu(Translations t, ConnectionStatus connection) => Menu(
    items: [
      MenuItem(key: 'open', label: t.nimbus.tray.openMainWindow),
      MenuItem.separator(),
      MenuItem(
        key: 'connection',
        label: switch (connection) {
          Disconnected() => t.connection.connect,
          Connecting() => t.connection.connecting,
          Connected() => t.connection.disconnect,
          Disconnecting() => t.connection.disconnecting,
        },
        disabled: connection.isSwitching,
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: t.common.quit),
    ],
  );

  String _trayIconPath() {
    const images = Assets.images;
    final isWindows = PlatformUtils.isWindows;
    return isWindows ? images.trayIconIco : images.trayIconPng.path;
  }

  String _trayTooltip(Translations t, ConnectionStatus connection, int urlTestDelay) {
    final r = "${Constants.appName} - ${_statusText(t, connection)}";
    if (connection is Connected) {
      final hasDelay = urlTestDelay > 0 && urlTestDelay < 65000;
      if (Platform.isMacOS) windowManager.setBadgeLabel(hasDelay ? "${urlTestDelay}ms" : "");
      return hasDelay ? '$r : ${urlTestDelay}ms' : r;
    } else {
      if (Platform.isMacOS) windowManager.setBadgeLabel("");
      return r;
    }
  }

  String _statusText(Translations t, ConnectionStatus connection) => switch (connection) {
    Disconnected() => t.nimbus.tray.disconnected,
    Connecting() => t.connection.connecting,
    Connected() => t.connection.connected,
    Disconnecting() => t.connection.disconnecting,
  };

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'open') {
      await ref.read(windowNotifierProvider.notifier).show();
    } else if (menuItem.key == 'connection') {
      await ref.read(nimbusDesktopBehaviorControllerProvider.notifier).toggleConnectionFromTray();
    } else if (menuItem.key == 'quit') {
      await ref.read(windowNotifierProvider.notifier).exit();
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    // if (Platform.isMacOS) {
    //   await trayManager.popUpContextMenu();
    // } else {
    //   await ref.read(windowNotifierProvider.notifier).hideOrShow();
    // }
    await ref.read(windowNotifierProvider.notifier).showOrHide();
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }
}
