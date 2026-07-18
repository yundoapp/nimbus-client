import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  test('连接状态映射为约定的菜单栏状态点', () {
    expect(trayConnectionIndicatorFor(const ConnectionStatus.connected()), TrayConnectionIndicator.connected);
    expect(trayConnectionIndicatorFor(const ConnectionStatus.disconnected()), TrayConnectionIndicator.disconnected);
    expect(trayConnectionIndicatorFor(const ConnectionStatus.connecting()), TrayConnectionIndicator.transitioning);
    expect(trayConnectionIndicatorFor(const ConnectionStatus.disconnecting()), TrayConnectionIndicator.transitioning);
  });

  test('macOS 原生桥接收到稳定的三态名称', () {
    expect(macosTrayIndicatorName(const ConnectionStatus.connected()), 'connected');
    expect(macosTrayIndicatorName(const ConnectionStatus.disconnected()), 'disconnected');
    expect(macosTrayIndicatorName(const ConnectionStatus.connecting()), 'transitioning');
    expect(macosTrayIndicatorName(const ConnectionStatus.disconnecting()), 'transitioning');
  });

  test('托盘连接模式菜单键可以安全往返解析', () {
    for (final mode in NimbusProxyMode.values) {
      expect(trayProxyModeFromKey(trayProxyModeKey(mode)), mode);
    }
    expect(trayProxyModeFromKey('proxy-mode:unknown'), isNull);
    expect(trayProxyModeFromKey('location:auto'), isNull);
  });

  test('托盘位置菜单键支持特殊位置代码并拒绝其他菜单项', () {
    const locationCode = 'jp:tokyo/1';
    expect(trayLocationCodeFromKey(trayLocationKey(locationCode)), locationCode);
    expect(trayLocationCodeFromKey('proxy-mode:auto'), isNull);
  });

  test('主界面和托盘共用节点地区标题', () async {
    final zhCn = await AppLocale.zhCn.build();
    final zhTw = await AppLocale.zhTw.build();
    final en = await AppLocale.en.build();

    expect(zhCn.nimbus.home.locationTitle, '节点地区');
    expect(zhCn.nimbus.home.locationAuto, '自动选择');
    expect(zhTw.nimbus.home.locationAuto, '自動選擇');
    expect(en.nimbus.home.locationTitle, 'Server region');
    expect(en.nimbus.home.locationAuto, 'Automatic selection');
  });

  test('软件名随中文界面显示本地化品牌名', () async {
    final zhCn = await AppLocale.zhCn.build();
    final zhTw = await AppLocale.zhTw.build();
    final en = await AppLocale.en.build();

    expect(zhCn.common.appTitle, '云渡');
    expect(zhCn.common.devAppTitle, '云渡开发版');
    expect(zhTw.common.appTitle, '雲渡');
    expect(zhTw.common.devAppTitle, '雲渡開發版');
    expect(en.common.appTitle, 'Yundo');
    expect(en.common.devAppTitle, 'Yundo Dev');
  });
}
