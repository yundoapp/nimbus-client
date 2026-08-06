import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_tunnel_config.dart';

void main() {
  const bundledRuleSetPath =
      '/Applications/Yundo Dev.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/rules/geoip-cn.srs';

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
    'dns': {
      'servers': [
        {'type': 'local', 'tag': 'nimbus-local'},
      ],
      'rules': [
        {
          'rule_set': ['geosite-cn'],
          'action': 'route',
          'server': 'nimbus-local',
        },
      ],
      'final': 'nimbus-local',
    },
    'route': {
      'rules': [
        {'action': 'sniff'},
        {
          'domain_suffix': ['force-proxy.example'],
          'action': 'route',
          'outbound': 'private-node',
        },
        {'rule_set': 'geosite-gfw', 'outbound': 'private-node'},
        {'ip_is_private': true, 'action': 'route', 'outbound': 'nimbus-direct'},
        {
          'rule_set': ['geoip-cn'],
          'action': 'route',
          'outbound': 'nimbus-direct',
        },
      ],
      'rule_set': [
        {
          'tag': 'geosite-gfw',
          'type': 'remote',
          'format': 'binary',
          'url': 'https://rules.example/geosite-gfw.srs',
          'update_interval': '24h0m0s',
          'download_detour': 'private-node',
        },
        {
          'tag': 'geoip-cn',
          'type': 'remote',
          'format': 'binary',
          'url': 'https://rules.example/geoip-cn.srs',
          'update_interval': '1d',
          'download_detour': 'private-node',
        },
        {
          'tag': 'geosite-cn',
          'type': 'remote',
          'format': 'binary',
          'url': 'https://rules.example/geosite-cn.srs',
          'update_interval': '1d',
          'download_detour': 'private-node',
        },
      ],
      'final': 'private-node',
    },
  };

  test('splits the user core from the minimal privileged TUN config', () {
    final prepared = splitMacOSTunnelConfig(
      managedConfig(),
      appProcessName: 'Yundo Dev',
      macOSNetworkMode: MacOSTunnelNetworkMode.ipv4Fallback,
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;

    final userInbounds = userConfig['inbounds'] as List<dynamic>;
    expect(userInbounds, hasLength(1));
    expect((userInbounds.single as Map<String, dynamic>)['type'], 'mixed');
    expect(jsonEncode(userConfig), contains('private.example'));
    expect(userConfig['dns'], {
      'servers': [
        {'type': 'local', 'tag': 'nimbus-local'},
      ],
      'rules': [
        {
          'rule_set': ['geosite-cn'],
          'action': 'route',
          'server': 'nimbus-local',
        },
      ],
      'final': 'nimbus-local',
      'strategy': 'ipv4_only',
    });
    expect((userConfig['route'] as Map<String, dynamic>)['rules'], [
      {'action': 'sniff'},
      {'ip_version': 6, 'action': 'reject'},
    ]);
    expect((userConfig['route'] as Map<String, dynamic>)['final'], 'private-node');
    expect((userConfig['route'] as Map<String, dynamic>)['rule_set'], hasLength(3));
    expect(
      ((userConfig['route'] as Map<String, dynamic>)['rule_set'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((ruleSet) => ruleSet['tag']),
      contains('geosite-cn'),
    );

    final tunnelInbounds = tunnelConfig['inbounds'] as List<dynamic>;
    final tunnelInbound = tunnelInbounds.single as Map<String, dynamic>;
    expect(tunnelInbound['type'], 'tun');
    expect(tunnelInbound['auto_route'], isTrue);
    expect(tunnelInbound['address'], ['172.20.0.1/30', 'fdfe:dcba:9876::1/126']);
    expect(tunnelInbound['stack'], 'system');
    expect(tunnelInbound, isNot(contains('route_exclude_address_set')));
    expect(tunnelInbound['strict_route'], isTrue);
    expect(tunnelInbound, isNot(contains('interface_name')));
    expect(tunnelInbound['sniff'], isTrue);
    expect(tunnelInbound['sniff_override_destination'], isTrue);
    expect(prepared.socksHost, '127.0.0.1');
    expect(prepared.socksPort, 12334);
    expect(prepared.socksUsername, isNull);
    expect(prepared.socksPassword, isNull);

    final route = tunnelConfig['route'] as Map<String, dynamic>;
    expect(route['rules'], [
      {
        'process_name': ['Yundo Dev', 'YundoPrivilegedHelper'],
        'action': 'route',
        'outbound': 'yundo-direct',
      },
      {'action': 'sniff'},
      {'ip_is_private': true, 'action': 'route', 'outbound': 'yundo-direct'},
      {'ip_version': 6, 'action': 'reject'},
      {
        'domain_suffix': ['force-proxy.example'],
        'action': 'route',
        'outbound': 'yundo-socks',
      },
      {'rule_set': 'geosite-gfw', 'action': 'route', 'outbound': 'yundo-socks'},
      {
        'rule_set': ['geoip-cn'],
        'action': 'route',
        'outbound': 'yundo-direct',
      },
    ]);
    expect(route['rule_set'], [
      {
        'tag': 'geosite-gfw',
        'type': 'remote',
        'format': 'binary',
        'url': 'https://rules.example/geosite-gfw.srs',
        'update_interval': '24h0m0s',
        'download_detour': 'yundo-socks',
      },
      {
        'tag': 'geoip-cn',
        'type': 'remote',
        'format': 'binary',
        'url': 'https://rules.example/geoip-cn.srs',
        'update_interval': '1d',
        'download_detour': 'yundo-socks',
        'fallback_path': bundledRuleSetPath,
      },
    ]);
    expect(tunnelConfig, isNot(contains('dns')));

    final tunnelJson = jsonEncode(tunnelConfig);
    expect(tunnelJson, isNot(contains('private.example')));
    expect(tunnelJson, isNot(contains('vless')));
    expect(tunnelJson, contains('force-proxy.example'));
    expect(tunnelJson, contains('https://rules.example/geosite-gfw.srs'));
    expect(tunnelJson, contains('Yundo Dev'));
    expect(tunnelJson, contains('YundoPrivilegedHelper'));
  });

  test('keeps the macOS user core dual-stack before capability probing', () {
    final config = managedConfig();
    (config['dns'] as Map<String, dynamic>)['strategy'] = 'prefer_ipv4';

    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;

    expect((userConfig['dns'] as Map<String, dynamic>)['strategy'], 'prefer_ipv4');
    expect((userConfig['route'] as Map<String, dynamic>)['rules'], [
      {'action': 'sniff'},
    ]);
    expect((userConfig['route'] as Map<String, dynamic>)['final'], 'private-node');
    expect((userConfig['route'] as Map<String, dynamic>)['rule_set'], hasLength(3));
    final tunnelInbound = (tunnelConfig['inbounds'] as List<dynamic>).single as Map<String, dynamic>;
    expect(tunnelInbound['address'], ['172.20.0.1/30', 'fdfe:dcba:9876::1/126']);
  });

  test('projects DNS hijack rules into the privileged tunnel', () {
    final config = managedConfig();
    (config['route'] as Map<String, dynamic>)['rules'] = [
      {'action': 'sniff'},
      {
        'port': [53],
        'action': 'hijack-dns',
      },
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {
        'domain_suffix': ['force-proxy.example'],
        'action': 'route',
        'outbound': 'private-node',
      },
    ];

    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;
    expect((tunnelConfig['route'] as Map<String, dynamic>)['rules'], [
      {
        'process_name': ['Yundo Dev', 'YundoPrivilegedHelper'],
        'action': 'route',
        'outbound': 'yundo-direct',
      },
      {'action': 'sniff'},
      {
        'port': [53],
        'action': 'hijack-dns',
      },
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {
        'domain_suffix': ['force-proxy.example'],
        'action': 'route',
        'outbound': 'yundo-socks',
      },
    ]);
  });

  test('adds a separate loopback Clash API for macOS route history', () {
    final config = managedConfig()
      ..['experimental'] = {
        'clash_api': {'external_controller': '127.0.0.1:16756', 'secret': 'route-history-secret'},
      };
    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;

    expect(tunnelConfig['experimental'], {
      'clash_api': {'external_controller': '127.0.0.1:16757', 'secret': 'route-history-secret'},
    });
  });

  test('disables user Core outbound monitoring while preserving macOS route history', () {
    final config = managedConfig()
      ..['experimental'] = {
        'clash_api': {'external_controller': '127.0.0.1:16756', 'secret': 'route-history-secret'},
        'monitoring': {
          'interval': '10m0s',
          'urls': ['https://www.gstatic.com/generate_204'],
        },
      };

    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;

    expect((userConfig['experimental'] as Map<String, dynamic>)['monitoring'], isNull);
    expect((userConfig['experimental'] as Map<String, dynamic>)['clash_api'], isNotNull);
    expect((tunnelConfig['experimental'] as Map<String, dynamic>)['clash_api'], isNotNull);
  });

  test('removes every direct member from the macOS acceleration path', () {
    final config = managedConfig();
    config['outbounds'] = [
      {
        'type': 'selector',
        'tag': 'select',
        'outbounds': ['lowest', 'balance', 'private-node', 'nimbus-direct'],
        'default': 'nimbus-direct',
      },
      {
        'type': 'urltest',
        'tag': 'lowest',
        'outbounds': ['private-node', 'nimbus-direct'],
      },
      {
        'type': 'balancer',
        'tag': 'balance',
        'outbounds': ['private-node', 'nimbus-direct'],
      },
      {'type': 'vless', 'tag': 'private-node', 'server': 'private.example'},
      {'type': 'direct', 'tag': 'nimbus-direct'},
    ];
    (config['route'] as Map<String, dynamic>)['final'] = 'select';

    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final outbounds = (userConfig['outbounds'] as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    final groups = outbounds.where((outbound) => {'selector', 'urltest', 'balancer'}.contains(outbound['type']));

    for (final group in groups) {
      expect(group['outbounds'], isNot(contains('nimbus-direct')));
    }
    expect(outbounds.firstWhere((outbound) => outbound['tag'] == 'select')['default'], 'lowest');
    expect((userConfig['route'] as Map<String, dynamic>)['final'], 'select');
  });

  test('rejects a macOS acceleration group without a proxy member', () {
    final config = managedConfig();
    config['outbounds'] = <dynamic>[
      {
        'type': 'selector',
        'tag': 'select',
        'outbounds': ['nimbus-direct'],
        'default': 'nimbus-direct',
      },
      ...(config['outbounds'] as List<dynamic>),
    ];
    (config['route'] as Map<String, dynamic>)['final'] = 'select';

    expect(
      () =>
          splitMacOSTunnelConfig(config, appProcessName: 'Yundo Dev', macOSDirectRouteRuleSetPath: bundledRuleSetPath),
      throwsA(
        isA<MacOSTunnelConfigException>().having(
          (error) => error.message,
          'message',
          contains('has no proxy outbound'),
        ),
      ),
    );
  });

  test('global mode keeps all public traffic on the local SOCKS path', () {
    final config = managedConfig();
    (config['route'] as Map<String, dynamic>)
      ..['rules'] = [
        {'action': 'sniff'},
      ]
      ..remove('rule_set');

    final prepared = splitMacOSTunnelConfig(config, appProcessName: 'Yundo Dev');
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;
    final tunnelInbound = (tunnelConfig['inbounds'] as List<dynamic>).single as Map<String, dynamic>;
    final route = tunnelConfig['route'] as Map<String, dynamic>;

    expect(tunnelInbound, isNot(contains('route_exclude_address_set')));
    expect(route, isNot(contains('rule_set')));
    expect(route['rules'], [
      {
        'process_name': ['Yundo Dev', 'YundoPrivilegedHelper'],
        'action': 'route',
        'outbound': 'yundo-direct',
      },
      {'action': 'sniff'},
    ]);
    expect(route['final'], 'yundo-socks');
  });

  test('allows Windows bridge to keep system DNS reachable', () {
    final prepared = splitMacOSTunnelConfig(
      managedConfig(),
      appProcessName: 'Yundo.exe',
      strictRouteOverride: false,
      configureWindowsDnsBridge: true,
    );
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final tunnelConfig = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;
    final tunnelInbound = (tunnelConfig['inbounds'] as List<dynamic>).single as Map<String, dynamic>;

    expect(tunnelInbound['strict_route'], isFalse);
    expect(tunnelInbound['address'], ['172.20.0.1/30']);
    expect(userConfig['dns'], {
      'servers': [
        {
          'type': 'https',
          'tag': 'yundo-windows-dns',
          'server': '1.1.1.1',
          'detour': 'private-node',
          'tls': {'enabled': true, 'server_name': 'cloudflare-dns.com'},
        },
      ],
      'final': 'yundo-windows-dns',
      'strategy': 'ipv4_only',
    });
    expect((userConfig['route'] as Map<String, dynamic>)['rules'], [
      {'action': 'sniff'},
      {
        'port': [53],
        'action': 'hijack-dns',
      },
      {
        'domain_suffix': ['force-proxy.example'],
        'action': 'route',
        'outbound': 'private-node',
      },
      {'rule_set': 'geosite-gfw', 'outbound': 'private-node'},
      {'ip_is_private': true, 'action': 'route', 'outbound': 'nimbus-direct'},
      {
        'rule_set': ['geoip-cn'],
        'action': 'route',
        'outbound': 'nimbus-direct',
      },
    ]);
    final tunnelRoute = tunnelConfig['route'] as Map<String, dynamic>;
    expect(tunnelRoute, isNot(contains('rule_set')));
    expect(tunnelRoute['rules'], [
      {
        'process_name': ['Yundo.exe', 'YundoPrivilegedHelper'],
        'action': 'route',
        'outbound': 'yundo-direct',
      },
      {'action': 'sniff'},
    ]);
  });

  test('prefers the IPv4 loopback bridge when Hiddify emits IPv6 bridges first', () {
    final config = managedConfig();
    (config['inbounds'] as List<dynamic>).insert(1, {
      'type': 'mixed',
      'tag': 'nimbus-mixed-in::1',
      'listen': '::1',
      'listen_port': 12335,
    });

    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );

    expect(prepared.socksHost, '127.0.0.1');
    expect(prepared.socksPort, 12334);
    final tunnel = jsonDecode(prepared.tunnelConfig) as Map<String, dynamic>;
    final tunnelOutbounds = tunnel['outbounds'] as List<dynamic>;
    expect((tunnelOutbounds.first as Map<String, dynamic>)['server'], '127.0.0.1');
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

  test('rejects configs without the bundled macOS direct route rule set', () {
    expect(
      () => splitMacOSTunnelConfig(managedConfig(), appProcessName: 'Yundo Dev'),
      throwsA(isA<MacOSTunnelConfigException>()),
    );
  });

  test('rejects a route rule that cannot be projected without changing semantics', () {
    final config = managedConfig();
    final rules = (config['route'] as Map<String, dynamic>)['rules'] as List<dynamic>;
    (rules[1] as Map<String, dynamic>)['unsupported_matcher'] = ['value'];

    expect(
      () =>
          splitMacOSTunnelConfig(config, appProcessName: 'Yundo Dev', macOSDirectRouteRuleSetPath: bundledRuleSetPath),
      throwsA(
        isA<MacOSTunnelConfigException>().having((error) => error.message, 'message', contains('unsupported fields')),
      ),
    );
  });

  test('rejects non-HTTPS remote rule sets in the privileged projection', () {
    final config = managedConfig();
    final ruleSets = (config['route'] as Map<String, dynamic>)['rule_set'] as List<dynamic>;
    (ruleSets.first as Map<String, dynamic>)['url'] = 'http://rules.example/geosite-gfw.srs';

    expect(
      () =>
          splitMacOSTunnelConfig(config, appProcessName: 'Yundo Dev', macOSDirectRouteRuleSetPath: bundledRuleSetPath),
      throwsA(isA<MacOSTunnelConfigException>().having((error) => error.message, 'message', contains('invalid URL'))),
    );
  });

  test('preserves Hiddify DNS servers in IPv4 fallback', () {
    final config = managedConfig();
    final outbounds = config['outbounds'] as List<dynamic>;
    outbounds.insert(0, {'type': 'selector', 'tag': 'select'});

    final prepared = splitMacOSTunnelConfig(
      config,
      appProcessName: 'Yundo Dev',
      macOSNetworkMode: MacOSTunnelNetworkMode.ipv4Fallback,
      macOSDirectRouteRuleSetPath: bundledRuleSetPath,
    );
    final userConfig = jsonDecode(prepared.userCoreConfig) as Map<String, dynamic>;
    final dns = userConfig['dns'] as Map<String, dynamic>;

    expect((dns['servers'] as List<dynamic>).single, {'type': 'local', 'tag': 'nimbus-local'});
    expect(dns['final'], 'nimbus-local');
    expect(dns['strategy'], 'ipv4_only');
  });
}
