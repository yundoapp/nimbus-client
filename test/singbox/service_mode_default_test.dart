import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';

void main() {
  test('Windows defaults to tunnel mode', () {
    expect(ServiceMode.defaultForPlatform(isWindows: true, isDesktop: true), ServiceMode.tun);
  });

  test('other desktop platforms retain system proxy default', () {
    expect(ServiceMode.defaultForPlatform(isWindows: false, isDesktop: true), ServiceMode.systemProxy);
  });

  test('mobile platforms retain tunnel mode default', () {
    expect(ServiceMode.defaultForPlatform(isWindows: false, isDesktop: false), ServiceMode.tun);
  });
}
