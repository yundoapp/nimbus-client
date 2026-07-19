import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/core_interface/windows_tunnel_service.dart';

const _tunnelConfig = '''
{
  "inbounds": [
    {
      "type": "tun",
      "address": ["172.20.0.1/30", "fdfe:dcba:9876::1/126"],
      "strict_route": true,
      "endpoint_independent_nat": true,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "server": "127.0.0.1",
      "server_port": 1080,
      "username": "local-user",
      "password": "local-password"
    }
  ]
}
''';

void main() {
  test('builds a Windows tunnel request from the minimized bridge config', () {
    final request = WindowsTunnelSettings.fromConfig(_tunnelConfig).toRequest();

    expect(request.ipv6, isTrue);
    expect(request.serverPort, 1080);
    expect(request.serverUsername, 'local-user');
    expect(request.serverPassword, 'local-password');
    expect(request.strictRoute, isTrue);
    expect(request.endpointIndependentNat, isTrue);
    expect(request.stack, 'system');
  });

  test('rejects a config without a single tunnel inbound', () {
    expect(() => WindowsTunnelSettings.fromConfig('{"inbounds": [], "outbounds": []}'), throwsFormatException);
  });

  test('installs the permission service only when the local service is unavailable', () async {
    var startAttempts = 0;
    final controls = <String>[];
    var waited = false;
    final service = WindowsTunnelService(
      isWindows: () => true,
      requestStarter: (_) async {
        startAttempts += 1;
        if (startAttempts == 1) throw const GrpcError.unavailable();
      },
      controlRunner: (action) async => controls.add(action),
      serviceWaiter: () async => waited = true,
    );

    await service.start(_tunnelConfig);

    expect(startAttempts, 2);
    expect(controls, ['install']);
    expect(waited, isTrue);
  });

  test('does not request elevation for a running service error', () async {
    var controlRuns = 0;
    final service = WindowsTunnelService(
      isWindows: () => true,
      requestStarter: (_) async => throw const GrpcError.permissionDenied(),
      controlRunner: (_) async => controlRuns += 1,
    );

    await expectLater(
      service.start(_tunnelConfig),
      throwsA(
        isA<WindowsTunnelServiceException>().having(
          (error) => error.kind,
          'kind',
          WindowsTunnelFailureKind.authorizationDenied,
        ),
      ),
    );
    expect(controlRuns, 0);
  });

  test('classifies a missing Windows network component', () async {
    final service = WindowsTunnelService(
      isWindows: () => true,
      requestStarter: (_) async => throw const GrpcError.unknown('Wintun driver could not be loaded'),
    );

    await expectLater(
      service.start(_tunnelConfig),
      throwsA(
        isA<WindowsTunnelServiceException>().having(
          (error) => error.kind,
          'kind',
          WindowsTunnelFailureKind.networkComponentUnavailable,
        ),
      ),
    );
  });

  test('classifies an existing Windows network component conflict', () async {
    final service = WindowsTunnelService(
      isWindows: () => true,
      requestStarter: (_) async => throw const GrpcError.unknown('object name already exists'),
    );

    await expectLater(
      service.start(_tunnelConfig),
      throwsA(
        isA<WindowsTunnelServiceException>().having(
          (error) => error.kind,
          'kind',
          WindowsTunnelFailureKind.networkComponentConflict,
        ),
      ),
    );
  });

  test('reset stops and uninstalls the Windows permission service', () async {
    var stopRuns = 0;
    final controls = <String>[];
    final service = WindowsTunnelService(
      isWindows: () => true,
      stopRequest: () async {
        stopRuns += 1;
        return true;
      },
      controlRunner: (action) async => controls.add(action),
    );

    expect(await service.reset(), isTrue);
    expect(stopRuns, 1);
    expect(controls, ['uninstall']);
  });
}
