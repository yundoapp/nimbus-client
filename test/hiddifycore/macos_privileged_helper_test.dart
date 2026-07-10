import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_privileged_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_yundo_macos_privileged_helper');
  const helper = MacOSPrivilegedHelper(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('passes the minimized tunnel config to the native helper', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    await helper.startTunnel('{"inbounds":[]}');

    expect(captured?.method, 'startTunnel');
    expect(captured?.arguments, {'config': '{"inbounds":[]}'});
  });

  test('exposes the native service status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      return {'status': 'requiresApproval'};
    });

    expect(await helper.status(), {'status': 'requiresApproval'});
  });
}
