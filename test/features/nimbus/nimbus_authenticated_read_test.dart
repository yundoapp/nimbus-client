// flutter_test is provided by the Flutter test runner in this fork.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_authenticated_read.dart';

void main() {
  test('refreshes an expired session and retries the read once', () async {
    final expired = _session('expired');
    final refreshed = _session('refreshed');
    var activeSession = expired;
    final requestedTokens = <String>[];

    final result = await runNimbusAuthenticatedRead(
      session: expired,
      request: (session) async {
        requestedTokens.add(session.accessToken);
        if (session.accessToken == expired.accessToken) throw const _Unauthorized();
        return 'loaded';
      },
      isUnauthorized: (error) => error is _Unauthorized,
      refreshAfterUnauthorized: (_) async {
        activeSession = refreshed;
        return true;
      },
      currentSession: () => activeSession,
    );

    expect(result, 'loaded');
    expect(requestedTokens, ['expired', 'refreshed']);
  });

  test('uses a session already refreshed by another request', () async {
    final expired = _session('expired');
    final refreshed = _session('refreshed');
    var refreshCalls = 0;

    final result = await runNimbusAuthenticatedRead(
      session: expired,
      request: (session) async {
        if (session.accessToken == expired.accessToken) throw const _Unauthorized();
        return session.accessToken;
      },
      isUnauthorized: (error) => error is _Unauthorized,
      refreshAfterUnauthorized: (_) async {
        refreshCalls++;
        return true;
      },
      currentSession: () => refreshed,
    );

    expect(result, 'refreshed');
    expect(refreshCalls, 1);
  });

  test('does not retry when refresh keeps the rejected token', () async {
    final expired = _session('expired');
    var requestCalls = 0;

    await expectLater(
      runNimbusAuthenticatedRead(
        session: expired,
        request: (_) {
          requestCalls++;
          return Future.error(const _Unauthorized());
        },
        isUnauthorized: (error) => error is _Unauthorized,
        refreshAfterUnauthorized: (_) async => false,
        currentSession: () => expired,
      ),
      throwsA(isA<_Unauthorized>()),
    );
    expect(requestCalls, 1);
  });

  test('does not refresh or retry unrelated failures', () async {
    final session = _session('active');
    var refreshCalls = 0;

    await expectLater(
      runNimbusAuthenticatedRead(
        session: session,
        request: (_) async => throw const FormatException('invalid response'),
        isUnauthorized: (error) => error is _Unauthorized,
        refreshAfterUnauthorized: (_) async {
          refreshCalls++;
          return true;
        },
        currentSession: () => session,
      ),
      throwsFormatException,
    );
    expect(refreshCalls, 0);
  });
}

NimbusAuthSession _session(String accessToken) => NimbusAuthSession(
  accessToken: accessToken,
  refreshToken: 'refresh',
  user: const NimbusUser(id: 'user', username: 'user', status: 'active'),
  device: const NimbusDevice(id: 'device', deviceId: 'device-id', platform: 'test', deviceName: 'Test'),
);

class _Unauthorized implements Exception {
  const _Unauthorized();
}
