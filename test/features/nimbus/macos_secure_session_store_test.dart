import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_yundo_macos_secure_session');
  const store = MacOSKeychainNimbusSessionStore(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('reads the session from the native keychain bridge', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'read');
      return '{"accessToken":"token"}';
    });

    expect(await store.read(), '{"accessToken":"token"}');
  });

  test('writes and deletes through the native keychain bridge', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    await store.write('session-json');
    await store.delete();

    expect(calls.map((call) => call.method), ['write', 'delete']);
    expect(calls.first.arguments, {'value': 'session-json'});
    expect(calls.last.arguments, isNull);
  });
}
