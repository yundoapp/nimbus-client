import 'dart:convert';

typedef PreparedMacOSTunnelConfig = ({String userCoreConfig, String tunnelConfig, int socksPort});

class MacOSTunnelConfigException implements Exception {
  const MacOSTunnelConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

PreparedMacOSTunnelConfig splitMacOSTunnelConfig(Map<String, dynamic> source, {required String appProcessName}) {
  final config = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  final rawInbounds = config['inbounds'];
  if (rawInbounds is! List) {
    throw const MacOSTunnelConfigException('managed config has no inbounds');
  }

  final inbounds = rawInbounds.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  final tunInbounds = inbounds.where((item) => item['type'] == 'tun').toList();
  if (tunInbounds.length != 1) {
    throw const MacOSTunnelConfigException('managed config must contain exactly one tun inbound');
  }

  final localInbound = inbounds.where((item) => item['type'] == 'mixed' || item['type'] == 'socks').firstOrNull;
  if (localInbound == null) {
    throw const MacOSTunnelConfigException('managed config has no local mixed or socks inbound');
  }
  final listen = localInbound['listen'];
  if (listen != '127.0.0.1' && listen != 'localhost') {
    throw const MacOSTunnelConfigException('local inbound must only listen on loopback');
  }
  final socksPort = localInbound['listen_port'];
  if (socksPort is! int || socksPort < 1 || socksPort > 65535) {
    throw const MacOSTunnelConfigException('local inbound has an invalid port');
  }

  config['inbounds'] = inbounds.where((item) => item['type'] != 'tun').toList();

  final originalTun = tunInbounds.single;
  const allowedTunKeys = {'mtu', 'strict_route', 'endpoint_independent_nat', 'sniff', 'sniff_override_destination'};
  final tunnelInbound = <String, dynamic>{
    'type': 'tun',
    'tag': 'yundo-tun',
    for (final entry in originalTun.entries)
      if (allowedTunKeys.contains(entry.key)) entry.key: entry.value,
    'address': ['172.20.0.1/30', 'fdfe:dcba:9876::1/126'],
    'auto_route': true,
    'stack': 'system',
  };

  String? username;
  String? password;
  final users = localInbound['users'];
  if (users is List && users.isNotEmpty && users.first is Map) {
    final user = Map<String, dynamic>.from(users.first as Map);
    username = user['username'] as String?;
    password = user['password'] as String?;
  }

  final directProcessNames = <String>{
    appProcessName.trim(),
    'YundoPrivilegedHelper',
  }.where((name) => name.isNotEmpty).toList();
  final tunnelConfig = <String, dynamic>{
    'log': {'level': 'warn'},
    'inbounds': [tunnelInbound],
    'outbounds': [
      {
        'type': 'socks',
        'tag': 'yundo-socks',
        'server': '127.0.0.1',
        'server_port': socksPort,
        'version': '5',
        if (username != null && username.isNotEmpty) 'username': username,
        if (password != null && password.isNotEmpty) 'password': password,
      },
      {'type': 'direct', 'tag': 'yundo-direct'},
    ],
    'route': {
      'rules': [
        if (directProcessNames.isNotEmpty) {'process_name': directProcessNames, 'outbound': 'yundo-direct'},
      ],
      'final': 'yundo-socks',
      'auto_detect_interface': true,
    },
  };

  const encoder = JsonEncoder.withIndent('  ');
  return (userCoreConfig: encoder.convert(config), tunnelConfig: encoder.convert(tunnelConfig), socksPort: socksPort);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
