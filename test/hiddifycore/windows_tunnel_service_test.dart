import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/windows_tunnel_service.dart';

void main() {
  test('builds a Windows tunnel request from the minimized bridge config', () {
    const config = '''
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

    final request = WindowsTunnelSettings.fromConfig(config).toRequest();

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
}
