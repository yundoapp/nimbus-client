import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';

void main() {
  test('移动端设置菜单使用页面，桌面端保留弹窗', () {
    expect(shouldOpenNimbusMenuAsPage(isMobilePlatform: true), isTrue);
    expect(shouldOpenNimbusMenuAsPage(isMobilePlatform: false), isFalse);
  });
}
