import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  test('连接状态映射为菜单栏三态指示器', () {
    expect(trayConnectionIndicatorFor(const Connected()), TrayConnectionIndicator.connected);
    expect(trayConnectionIndicatorFor(const Disconnected()), TrayConnectionIndicator.disconnected);
    expect(trayConnectionIndicatorFor(const Connecting()), TrayConnectionIndicator.transitioning);
    expect(trayConnectionIndicatorFor(const Disconnecting()), TrayConnectionIndicator.transitioning);
  });

  test('macOS 原生状态栏接收稳定的指示器名称', () {
    expect(macosTrayIndicatorName(const Connected()), 'connected');
    expect(macosTrayIndicatorName(const Disconnected()), 'disconnected');
    expect(macosTrayIndicatorName(const Connecting()), 'transitioning');
    expect(macosTrayIndicatorName(const Disconnecting()), 'transitioning');
  });

  test('开发版菜单栏提示使用本地化开发版名称', () {
    final translations = Translations();
    expect(trayAppDisplayName(translations, Environment.dev), translations.common.devAppTitle);
    expect(trayAppDisplayName(translations, Environment.prod), translations.common.appTitle);
  });

  test('Windows 托盘使用云渡专用三态图标', () {
    expect(windowsTrayIconPath(const Connected()), 'assets/images/yundo_tray_windows_connected.ico');
    expect(windowsTrayIconPath(const Disconnected()), 'assets/images/yundo_tray_windows_disconnected.ico');
    expect(windowsTrayIconPath(const Connecting()), 'assets/images/yundo_tray_windows_transitioning.ico');
    expect(windowsTrayIconPath(const Disconnecting()), 'assets/images/yundo_tray_windows_transitioning.ico');
  });

  test('macOS 状态栏使用云渡 Y 图标资源', () {
    final source = File('lib/features/system_tray/notifier/system_tray_notifier.dart').readAsStringSync();
    expect(source, contains("rootBundle.load(Assets.images.trayIconPng.path)"));
    expect(source, contains("MethodChannel('yundo_macos_status_item')"));
  });
}
