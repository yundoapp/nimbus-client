import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_desktop_behavior_controller.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_notifier.g.dart';

String trayTooltipText(
  String appDisplayName,
  Translations translations,
  ConnectionStatus connection,
  int urlTestDelay,
) {
  final status = switch (connection) {
    Disconnected() => translations.nimbus.tray.disconnected,
    Connecting() => translations.connection.connecting,
    Connected() => translations.connection.connected,
    Disconnecting() => translations.connection.disconnecting,
  };
  final tooltip = '$appDisplayName - $status';
  final hasDelay = connection is Connected && urlTestDelay > 0 && urlTestDelay < 65000;
  return hasDelay ? '$tooltip : ${urlTestDelay}ms' : tooltip;
}

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

String trayMenuCacheKey(
  Translations translations,
  ConnectionStatus connection,
  NimbusProxyMode proxyMode,
  NimbusAuthState authState,
  String languageCode,
) => jsonEncode({
  'openLabel': translations.nimbus.tray.openMainWindow,
  'connectionLabel': switch (connection) {
    Disconnected() => translations.connection.connect,
    Connecting() => translations.connection.connecting,
    Connected() => translations.connection.disconnect,
    Disconnecting() => translations.connection.disconnecting,
  },
  'connectionEnabled': !connection.isSwitching,
  'modeLabel': translations.nimbus.home.connectionMode,
  'modeEnabled': !connection.isSwitching,
  'modeItems': NimbusProxyMode.values
      .map(
        (mode) => {
          'key': trayProxyModeKey(mode),
          'label': _proxyModeLabel(translations, mode),
          'checked': mode == proxyMode,
        },
      )
      .toList(),
  'locationLabel': translations.nimbus.home.locationTitle,
  'locationEnabled': _locationsReady(authState) && !connection.isSwitching,
  'locationItems': _trayLocations(authState)
      .map(
        (location) => {
          'key': trayLocationKey(location.code),
          'label': _locationDisplayName(translations, location, languageCode),
          'checked': location.code == authState.selectedLocationCode,
        },
      )
      .toList(),
  'quitLabel': translations.common.quit,
});

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with TrayListener, AppLogger {
  bool listenerAdded = false;
  String? _lastTrayIconPath;
  String? _lastTrayTooltip;
  String? _lastTrayMenuKey;

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
    final appDisplayName = ref.watch(appInfoProvider).requireValue.name;
    final locale = ref.watch(localePreferencesProvider);
    final proxyMode = ref.watch(Preferences.nimbusProxyMode);
    final authState = ref.watch(nimbusAuthControllerProvider);
    if (authState.isAuthenticated && authState.locations == null && !authState.isLoading) {
      Future.microtask(() => ref.read(nimbusAuthControllerProvider.notifier).loadLocations());
    }
    final urlTestDelay = ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull?.urlTestDelay ?? 0));
    final connection =
        ref.watch(nimbusOwnedConnectionStatusProvider).valueOrNull ?? const ConnectionStatus.disconnected();

    final tooltip = _trayTooltip(appDisplayName, t, connection, urlTestDelay);
    await _setTrayIcon(connection);
    if (!PlatformUtils.isLinux) await _setTrayTooltip(tooltip);
    await _setTrayMenu(t, connection, proxyMode, authState, locale.languageCode);
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
    final iconPath = _trayIconPath(connection);
    if (_lastTrayIconPath == iconPath) return;
    _lastTrayIconPath = iconPath;
    try {
      await trayManager.setIcon(iconPath);
    } catch (_) {
      if (_lastTrayIconPath == iconPath) _lastTrayIconPath = null;
      rethrow;
    }
  }

  String _trayIconPath(ConnectionStatus connection) {
    if (PlatformUtils.isWindows) {
      return switch (connection) {
        Connected() => Assets.images.trayIconConnectedIco,
        Connecting() || Disconnecting() => Assets.images.trayIconDisconnectedIco,
        Disconnected() => Assets.images.trayIconIco,
      };
    }
    return switch (connection) {
      Connected() => Assets.images.trayIconConnectedPng.path,
      Connecting() || Disconnecting() => Assets.images.trayIconDisconnectedPng.path,
      Disconnected() => Assets.images.trayIconPng.path,
    };
  }

  Future<void> _setTrayTooltip(String tooltip) async {
    if (_lastTrayTooltip == tooltip) return;
    _lastTrayTooltip = tooltip;
    try {
      await trayManager.setToolTip(tooltip);
    } catch (_) {
      if (_lastTrayTooltip == tooltip) _lastTrayTooltip = null;
      rethrow;
    }
  }

  Future<void> _setTrayMenu(
    Translations t,
    ConnectionStatus connection,
    NimbusProxyMode proxyMode,
    NimbusAuthState authState,
    String languageCode,
  ) async {
    final menuKey = trayMenuCacheKey(t, connection, proxyMode, authState, languageCode);
    if (_lastTrayMenuKey == menuKey) return;
    _lastTrayMenuKey = menuKey;
    try {
      await trayManager.setContextMenu(_trayMenu(t, connection, proxyMode, authState, languageCode));
    } catch (_) {
      if (_lastTrayMenuKey == menuKey) _lastTrayMenuKey = null;
      rethrow;
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

  String _trayTooltip(String appDisplayName, Translations t, ConnectionStatus connection, int urlTestDelay) {
    final hasDelay = connection is Connected && urlTestDelay > 0 && urlTestDelay < 65000;
    if (Platform.isMacOS) windowManager.setBadgeLabel(hasDelay ? "${urlTestDelay}ms" : "");
    return trayTooltipText(appDisplayName, t, connection, urlTestDelay);
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    await _handleMenuAction(menuItem.key ?? '');
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    await ref.read(windowNotifierProvider.notifier).show();
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
