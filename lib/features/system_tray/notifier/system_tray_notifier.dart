import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
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

enum TrayConnectionIndicator { connected, disconnected, transitioning }

TrayConnectionIndicator trayConnectionIndicatorFor(ConnectionStatus connection) => switch (connection) {
  Connected() => TrayConnectionIndicator.connected,
  Disconnected() => TrayConnectionIndicator.disconnected,
  Connecting() || Disconnecting() => TrayConnectionIndicator.transitioning,
};

String macosTrayIndicatorName(ConnectionStatus connection) => trayConnectionIndicatorFor(connection).name;

const _trayProxyModeKeyPrefix = 'proxy-mode:';
const _trayLocationKeyPrefix = 'location:';

String trayProxyModeKey(NimbusProxyMode mode) => '$_trayProxyModeKeyPrefix${mode.name}';

NimbusProxyMode? trayProxyModeFromKey(String key) {
  if (!key.startsWith(_trayProxyModeKeyPrefix)) return null;
  final modeName = key.substring(_trayProxyModeKeyPrefix.length);
  for (final mode in NimbusProxyMode.values) {
    if (mode.name == modeName) return mode;
  }
  return null;
}

String trayLocationKey(String locationCode) => '$_trayLocationKeyPrefix${Uri.encodeComponent(locationCode)}';

String? trayLocationCodeFromKey(String key) {
  if (!key.startsWith(_trayLocationKeyPrefix)) return null;
  try {
    return Uri.decodeComponent(key.substring(_trayLocationKeyPrefix.length));
  } on FormatException {
    return null;
  }
}

const _yundoMacosStatusItemChannel = MethodChannel('yundo_macos_status_item');

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with TrayListener, AppLogger {
  bool listenerAdded = false;

  @override
  Future<void> build() async {
    assert(PlatformUtils.isDesktop);
    if (PlatformUtils.isMacOS) {
      _yundoMacosStatusItemChannel.setMethodCallHandler(_handleMacosStatusItemCall);
    } else if (!listenerAdded) {
      trayManager.addListener(this);
      listenerAdded = true;
    }
    await _initializeTray();
  }

  Future<void> _initializeTray() async {
    final t = await ref.watch(translationsProvider.future);
    final locale = ref.watch(localePreferencesProvider);
    final proxyMode = ref.watch(Preferences.nimbusProxyMode);
    final authState = ref.watch(nimbusAuthControllerProvider);
    if (authState.isAuthenticated && authState.locations == null && !authState.isLoading) {
      Future.microtask(() => ref.read(nimbusAuthControllerProvider.notifier).loadLocations());
    }
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

    final tooltip = _trayTooltip(t, connection, urlTestDelay);
    if (PlatformUtils.isMacOS) {
      await _updateMacosStatusItem(t, connection, tooltip, proxyMode, authState, locale.languageCode);
    } else {
      await _setTrayIcon(connection);
      if (!PlatformUtils.isLinux) await trayManager.setToolTip(tooltip);
      await trayManager.setContextMenu(_trayMenu(t, connection, proxyMode, authState, locale.languageCode));
    }
  }

  Menu _trayMenu(
    Translations t,
    ConnectionStatus connection,
    NimbusProxyMode proxyMode,
    NimbusAuthState authState,
    String languageCode,
  ) => Menu(
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
      MenuItem.submenu(
        key: 'proxy-mode-menu',
        label: t.nimbus.home.connectionMode,
        disabled: connection.isSwitching,
        submenu: Menu(
          items: NimbusProxyMode.values
              .map(
                (mode) => MenuItem.checkbox(
                  key: trayProxyModeKey(mode),
                  label: _proxyModeLabel(t, mode),
                  checked: mode == proxyMode,
                ),
              )
              .toList(),
        ),
      ),
      MenuItem.submenu(
        key: 'location-menu',
        label: t.nimbus.home.locationTitle,
        disabled: !_locationsReady(authState) || connection.isSwitching,
        submenu: Menu(
          items: _trayLocations(authState)
              .map(
                (location) => MenuItem.checkbox(
                  key: trayLocationKey(location.code),
                  label: _locationDisplayName(t, location, languageCode),
                  checked: location.code == authState.selectedLocationCode,
                ),
              )
              .toList(),
        ),
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: t.common.quit),
    ],
  );

  Future<void> _setTrayIcon(ConnectionStatus connection) async {
    await trayManager.setIcon(_trayIconPath(connection));
  }

  String _trayIconPath(ConnectionStatus connection) {
    const images = Assets.images;
    if (PlatformUtils.isWindows) return images.trayIconIco;
    return images.trayIconPng.path;
  }

  Future<void> _updateMacosStatusItem(
    Translations t,
    ConnectionStatus connection,
    String tooltip,
    NimbusProxyMode proxyMode,
    NimbusAuthState authState,
    String languageCode,
  ) async {
    final iconData = await rootBundle.load(Assets.images.trayIconPng.path);
    await _yundoMacosStatusItemChannel.invokeMethod<void>('update', {
      'iconBytes': iconData.buffer.asUint8List(iconData.offsetInBytes, iconData.lengthInBytes),
      'indicator': macosTrayIndicatorName(connection),
      'toolTip': tooltip,
      'openLabel': t.nimbus.tray.openMainWindow,
      'connectionLabel': _connectionMenuLabel(t, connection),
      'connectionEnabled': !connection.isSwitching,
      'modeLabel': t.nimbus.home.connectionMode,
      'modeEnabled': !connection.isSwitching,
      'modeItems': NimbusProxyMode.values
          .map(
            (mode) => {'key': trayProxyModeKey(mode), 'label': _proxyModeLabel(t, mode), 'checked': mode == proxyMode},
          )
          .toList(),
      'locationLabel': t.nimbus.home.locationTitle,
      'locationItems': _trayLocations(authState)
          .map(
            (location) => {
              'key': trayLocationKey(location.code),
              'label': _locationDisplayName(t, location, languageCode),
              'checked': location.code == authState.selectedLocationCode,
            },
          )
          .toList(),
      'locationEnabled': _locationsReady(authState) && !connection.isSwitching,
      'quitLabel': t.common.quit,
    });
  }

  String _connectionMenuLabel(Translations t, ConnectionStatus connection) => switch (connection) {
    Disconnected() => t.connection.connect,
    Connecting() => t.connection.connecting,
    Connected() => t.connection.disconnect,
    Disconnecting() => t.connection.disconnecting,
  };

  Future<void> _handleMacosStatusItemCall(MethodCall call) async {
    switch (call.method) {
      case 'onLeftClick':
        await ref.read(windowNotifierProvider.notifier).showOrHide();
        return;
      case 'onMenuItemClick':
        final arguments = call.arguments as Map<Object?, Object?>?;
        final key = arguments?['key'] as String?;
        if (key != null) await _handleMenuAction(key);
        return;
    }
  }

  Future<void> _handleMenuAction(String key) async {
    final proxyMode = trayProxyModeFromKey(key);
    if (proxyMode != null) {
      if (proxyMode == ref.read(Preferences.nimbusProxyMode)) return;
      await ref.read(Preferences.nimbusProxyMode.notifier).update(proxyMode);
      await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected();
      return;
    }

    final locationCode = trayLocationCodeFromKey(key);
    if (locationCode != null) {
      final locations = ref.read(nimbusAuthControllerProvider).locations?.items ?? const <NimbusLocation>[];
      NimbusLocation? selectedLocation;
      for (final location in locations) {
        if (location.code == locationCode) {
          selectedLocation = location;
          break;
        }
      }
      if (selectedLocation != null) {
        await ref.read(nimbusConnectionControllerProvider.notifier).selectLocation(selectedLocation);
      }
      return;
    }

    if (key == 'open') {
      await ref.read(windowNotifierProvider.notifier).show();
    } else if (key == 'connection') {
      await ref.read(nimbusDesktopBehaviorControllerProvider.notifier).toggleConnectionFromTray();
    } else if (key == 'quit') {
      await ref.read(windowNotifierProvider.notifier).exit();
    }
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
    await _handleMenuAction(menuItem.key ?? '');
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

bool _locationsReady(NimbusAuthState authState) =>
    authState.isAuthenticated && authState.locations != null && authState.locations!.items.isNotEmpty;

List<NimbusLocation> _trayLocations(NimbusAuthState authState) =>
    authState.locations?.items ?? const [NimbusLocation(code: 'auto', displayName: '')];

String _proxyModeLabel(Translations t, NimbusProxyMode mode) => switch (mode) {
  NimbusProxyMode.auto => t.nimbus.proxyMode.auto,
  NimbusProxyMode.global => t.nimbus.proxyMode.global,
};

String _locationDisplayName(Translations t, NimbusLocation location, String languageCode) {
  if (location.code == 'auto') return t.nimbus.home.locationAuto;
  return location.displayNameForLanguage(languageCode);
}
