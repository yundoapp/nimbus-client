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

  test('requests verified tunnel cleanup from the native helper', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    await helper.stopTunnel();

    expect(captured?.method, 'stopTunnel');
    expect(captured?.arguments, isNull);
  });

  test('exposes the native service status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      return {'status': 'requiresApproval'};
    });

    expect(await helper.status(), {'status': 'requiresApproval'});
  });

  test('maps the native connection conflict inspection', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'connectionConflict');
      return {
        'hasConflict': true,
        'systemProxyEnabled': true,
        'tunneledRouteCount': 2,
        'yundoRoutedCount': 1,
        'routeCheckFailures': 1,
      };
    });

    final conflict = await helper.connectionConflict();

    expect(conflict.hasConflict, isTrue);
    expect(conflict.systemProxyEnabled, isTrue);
    expect(conflict.tunneledRouteCount, 2);
    expect(conflict.yundoRoutedCount, 1);
    expect(conflict.routeCheckFailures, 1);
  });

  test('uses safe defaults for an incomplete conflict response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => const <Object?, Object?>{},
    );

    final conflict = await helper.connectionConflict();

    expect(conflict.hasConflict, isFalse);
    expect(conflict.systemProxyEnabled, isFalse);
    expect(conflict.tunneledRouteCount, 0);
    expect(conflict.yundoRoutedCount, 0);
    expect(conflict.routeCheckFailures, 0);
  });

  test('reads sanitized rule-set lifecycle messages from the helper', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ruleSetDiagnostics');
      return <Object?>['rule-set geosite-cn: loaded from bundled fallback', 'rule-set geosite-gfw: download completed'];
    });

    expect(await helper.ruleSetDiagnostics(), [
      'rule-set geosite-cn: loaded from bundled fallback',
      'rule-set geosite-gfw: download completed',
    ]);
  });
}
