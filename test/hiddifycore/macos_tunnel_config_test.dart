import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_tunnel_config.dart';

void main() {
  Map<String, dynamic> managedConfig() => {
    'log': {'level': 'warn'},
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'nimbus-tun',
        'interface_name': 'must-not-reach-helper',
        'address': ['172.19.0.1/30'],
        'auto_route': true,
        'strict_route': true,
        'stack': 'system',
      },
      {'type': 'mixed', 'tag': 'nimbus-mixed', 'listen': '127.0.0.1', 'listen_port': 12334},
    ],
    'outbounds': [
      {'type': 'vless', 'tag': 'private-node', 'server': 'private.example'},
      {'type': 'direct', 'tag': 'nimbus-direct'},
    ],
    'route': {'final': 'private-node'},
  };

  test('splits the user core from the minimal privileged TUN config', () {
    final prepared = splitMacOSTunnelConfig(managedConfig(), appProcessName: 'Yundo Dev');
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;

    final userInbounds = userConfig['inbounds'] as List<dynamic>;
    expect(userInbounds, hasLength(1));
    expect((userInbounds.single as Map<String, dynamic>)['type'], 'mixed');
    expect(jsonEncode(userConfig), contains('private.example'));

    final tunnelInbounds = tunnelConfig['inbounds'] as List<dynamic>;
    final tunnelInbound = tunnelInbounds.single as Map<String, dynamic>;
    expect(tunnelInbound['type'], 'tun');
    expect(tunnelInbound['auto_route'], isTrue);
    expect(tunnelInbound['address'], ['172.20.0.1/30', 'fdfe:dcba:9876::1/126']);
    expect(tunnelInbound['stack'], 'system');
    expect(tunnelInbound, isNot(contains('interface_name')));
    expect(prepared.socksPort, 12334);

    final tunnelJson = jsonEncode(tunnelConfig);
    expect(tunnelJson, isNot(contains('private.example')));
    expect(tunnelJson, isNot(contains('vless')));
    expect(tunnelJson, contains('Yundo Dev'));
    expect(tunnelJson, contains('YundoPrivilegedHelper'));
  });

  test('rejects a local bridge that listens outside loopback', () {
    final config = managedConfig();
    final inbounds = config['inbounds'] as List<dynamic>;
    (inbounds[1] as Map<String, dynamic>)['listen'] = '0.0.0.0';

    expect(
      () => splitMacOSTunnelConfig(config, appProcessName: 'Yundo Dev'),
      throwsA(isA<MacOSTunnelConfigException>()),
    );
  });

  test('rejects configs without exactly one TUN inbound', () {
    final config = managedConfig();
    config['inbounds'] = [
      {'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': 12334},
    ];

    expect(
      () => splitMacOSTunnelConfig(config, appProcessName: 'Yundo Dev'),
      throwsA(isA<MacOSTunnelConfigException>()),
    );
  });
}
