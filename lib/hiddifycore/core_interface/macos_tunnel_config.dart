import 'dart:convert';

import 'package:path/path.dart' as p;

typedef PreparedMacOSTunnelConfig = ({String userCoreConfig, String tunnelConfig, int socksPort});

class MacOSTunnelConfigException implements Exception {
  const MacOSTunnelConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum MacOSTunnelNetworkMode { dualStack, ipv4Fallback }

const _macOSDirectRouteRuleSetTag = 'geoip-cn';
const _macOSTunnelSocksOutboundTag = 'yundo-socks';
const _macOSTunnelDirectOutboundTag = 'yundo-direct';

const _macOSDevRouteHistoryPort = 16757;
const _macOSReleaseRouteHistoryPort = 16758;

int nimbusMacOSTunnelRouteHistoryPort(String appProcessName) =>
    appProcessName.trim() == 'Yundo Dev' ? _macOSDevRouteHistoryPort : _macOSReleaseRouteHistoryPort;

typedef _MacOSTunnelRoutePolicy = ({List<Map<String, dynamic>> rules, List<Map<String, dynamic>> ruleSets});

PreparedMacOSTunnelConfig splitMacOSTunnelConfig(
  Map<String, dynamic> source, {
  required String appProcessName,
  bool? strictRouteOverride,
  bool configureWindowsDnsBridge = false,
  MacOSTunnelNetworkMode macOSNetworkMode = MacOSTunnelNetworkMode.dualStack,
  String? macOSDirectRouteRuleSetPath,
}) {
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

  final localInbounds = inbounds
      .where((item) => item['type'] == 'mixed' || item['type'] == 'socks')
      .where((item) => _isLoopbackListen(item['listen']))
      .toList();
  final localInbound = localInbounds.where((item) => item['listen'] != '::1').firstOrNull ?? localInbounds.firstOrNull;
  if (localInbound == null) {
    throw const MacOSTunnelConfigException('local inbound must only listen on loopback');
  }
  final listen = localInbound['listen'] as String;
  final socksPort = localInbound['listen_port'];
  if (socksPort is! int || socksPort < 1 || socksPort > 65535) {
    throw const MacOSTunnelConfigException('local inbound has an invalid port');
  }

  config['inbounds'] = inbounds.where((item) => item['type'] != 'tun').toList();
  if (macOSNetworkMode == MacOSTunnelNetworkMode.ipv4Fallback) {
    _configureIpv4OnlyDnsBridge(config, dnsTag: 'yundo-macos-dns', rejectIpv6: true);
  } else if (configureWindowsDnsBridge) {
    _configureIpv4OnlyDnsBridge(config, dnsTag: 'yundo-windows-dns');
  }

  final originalTun = tunInbounds.single;
  final routeHistoryClashApi = _macOSTunnelClashApi(config, appProcessName);
  final tunnelRoutePolicy = configureWindowsDnsBridge
      ? (
          rules: <Map<String, dynamic>>[
            {'action': 'sniff'},
          ],
          ruleSets: <Map<String, dynamic>>[],
        )
      : _projectMacOSTunnelRoutePolicy(config, macOSDirectRouteRuleSetPath);
  const allowedTunKeys = {'mtu', 'strict_route', 'endpoint_independent_nat'};
  final tunnelInbound = <String, dynamic>{
    'type': 'tun',
    'tag': 'yundo-tun',
    for (final entry in originalTun.entries)
      if (allowedTunKeys.contains(entry.key)) entry.key: entry.value,
    if (strictRouteOverride != null) 'strict_route': strictRouteOverride,
    'address': ['172.20.0.1/30', if (!configureWindowsDnsBridge) 'fdfe:dcba:9876::1/126'],
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
  final tunnelDns = _projectMacOSTunnelDns(config);
  final tunnelConfig = <String, dynamic>{
    'log': {'level': 'warn'},
    if (routeHistoryClashApi != null) 'experimental': {'clash_api': routeHistoryClashApi},
    if (tunnelDns != null) 'dns': tunnelDns,
    'inbounds': [tunnelInbound],
    'outbounds': [
      {
        'type': 'socks',
        'tag': _macOSTunnelSocksOutboundTag,
        'server': listen == '::1' ? '::1' : '127.0.0.1',
        'server_port': socksPort,
        'version': '5',
        if (username != null && username.isNotEmpty) 'username': username,
        if (password != null && password.isNotEmpty) 'password': password,
      },
      {'type': 'direct', 'tag': _macOSTunnelDirectOutboundTag},
    ],
    'route': {
      'rules': [
        if (directProcessNames.isNotEmpty)
          {'process_name': directProcessNames, 'action': 'route', 'outbound': _macOSTunnelDirectOutboundTag},
        ...tunnelRoutePolicy.rules,
      ],
      'final': _macOSTunnelSocksOutboundTag,
      'auto_detect_interface': true,
      if (tunnelRoutePolicy.ruleSets.isNotEmpty) 'rule_set': tunnelRoutePolicy.ruleSets,
    },
  };

  const encoder = JsonEncoder.withIndent('  ');
  return (userCoreConfig: encoder.convert(config), tunnelConfig: encoder.convert(tunnelConfig), socksPort: socksPort);
}

Map<String, dynamic>? _projectMacOSTunnelDns(Map<String, dynamic> config) {
  final sourceDns = config['dns'];
  if (sourceDns is! Map) return null;

  final sourceServers = sourceDns['servers'];
  if (sourceServers is! List) return null;

  const allowedServerKeys = {'type', 'tag', 'server', 'server_port', 'tls', 'detour'};
  final servers = <Map<String, dynamic>>[];
  for (final item in sourceServers) {
    if (item is! Map) continue;
    final source = Map<String, dynamic>.from(item);
    final type = source['type'];
    final tag = source['tag'];
    final server = source['server'];
    if (type is! String || !{'https', 'tls', 'tcp', 'udp', 'quic'}.contains(type)) continue;
    if (tag is! String || tag.isEmpty || server is! String || server.isEmpty || server.startsWith('/')) continue;
    if (source.keys.any((key) => !allowedServerKeys.contains(key))) continue;

    servers.add({
      for (final entry in source.entries) entry.key: jsonDecode(jsonEncode(entry.value)),
      'detour': _macOSTunnelSocksOutboundTag,
    });
  }

  if (servers.isEmpty) return null;
  final finalTag = sourceDns['final'];
  if (finalTag is! String || finalTag.isEmpty || !servers.any((server) => server['tag'] == finalTag)) {
    return null;
  }

  final strategy = sourceDns['strategy'];
  return {'servers': servers, 'final': finalTag, if (strategy is String && strategy.isNotEmpty) 'strategy': strategy};
}

Map<String, dynamic>? _macOSTunnelClashApi(Map<String, dynamic> config, String appProcessName) {
  final experimental = config['experimental'];
  final clashApi = experimental is Map ? experimental['clash_api'] : null;
  if (clashApi is! Map) return null;

  final secret = clashApi['secret'];
  return {
    'external_controller': '127.0.0.1:${nimbusMacOSTunnelRouteHistoryPort(appProcessName)}',
    if (secret is String && secret.isNotEmpty) 'secret': secret,
  };
}

_MacOSTunnelRoutePolicy _projectMacOSTunnelRoutePolicy(Map<String, dynamic> config, String? directRouteRuleSetPath) {
  final route = config['route'] is Map ? Map<String, dynamic>.from(config['route'] as Map) : <String, dynamic>{};
  final sourceRules = route['rules'] is List
      ? (route['rules'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  final sourceOutbounds = config['outbounds'] is List
      ? (config['outbounds'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  final directOutboundTags = sourceOutbounds
      .where((outbound) => outbound['type'] == 'direct' && outbound['tag'] is String)
      .map((outbound) => outbound['tag'] as String)
      .toSet();

  final projectedRules = <Map<String, dynamic>>[];
  final requiredRuleSetTags = <String>{};
  for (final sourceRule in sourceRules) {
    final projected = _projectMacOSTunnelRouteRule(sourceRule, directOutboundTags);
    if (projected == null) continue;
    projectedRules.add(projected);
    final ruleSetTags = projected['rule_set'];
    if (ruleSetTags is String) {
      requiredRuleSetTags.add(ruleSetTags);
    } else if (ruleSetTags is List) {
      requiredRuleSetTags.addAll(ruleSetTags.whereType<String>());
    }
  }
  if (!projectedRules.any((rule) => rule['action'] == 'sniff')) {
    projectedRules.insert(0, {'action': 'sniff'});
  }

  final sourceRuleSets = route['rule_set'] is List
      ? (route['rule_set'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  final projectedRuleSets = requiredRuleSetTags
      .map(
        (tag) => tag == _macOSDirectRouteRuleSetTag
            ? _macOSDirectRouteRuleSet(directRouteRuleSetPath)
            : _projectMacOSRemoteRuleSet(tag, sourceRuleSets),
      )
      .toList(growable: false);
  return (rules: projectedRules, ruleSets: projectedRuleSets);
}

Map<String, dynamic>? _projectMacOSTunnelRouteRule(Map<String, dynamic> source, Set<String> directOutboundTags) {
  const metadataKeys = {'action', 'outbound'};
  const matcherKeys = {
    'domain',
    'domain_suffix',
    'domain_keyword',
    'domain_regex',
    'ip_cidr',
    'ip_is_private',
    'source_ip_cidr',
    'port',
    'port_range',
    'source_port',
    'source_port_range',
    'network',
    'protocol',
    'process_name',
    'process_path',
    'rule_set',
    'ip_version',
    'invert',
  };

  final sourceAction = source['action'];
  final action = sourceAction ?? (source['outbound'] is String ? 'route' : null);
  if (action == 'sniff') {
    if (source.keys.length != 1) {
      throw const MacOSTunnelConfigException('macOS tunnel sniff rule contains unsupported fields');
    }
    return {'action': 'sniff'};
  }
  if (action != 'route' && action != 'reject' && action != 'hijack-dns') return null;
  if (source.keys.any((key) => !metadataKeys.contains(key) && !matcherKeys.contains(key))) {
    throw const MacOSTunnelConfigException('macOS tunnel route rule contains unsupported fields');
  }

  final match = <String, dynamic>{
    for (final entry in source.entries)
      if (matcherKeys.contains(entry.key)) entry.key: jsonDecode(jsonEncode(entry.value)),
  };
  if (match.keys.where((key) => key != 'invert').isEmpty) {
    throw const MacOSTunnelConfigException('macOS tunnel route rule has no matcher');
  }

  if (action == 'hijack-dns') {
    return {
      ...match,
      'action': 'hijack-dns',
    };
  }

  if (action == 'reject') {
    return {...match, 'action': 'reject'};
  }
  final sourceOutbound = source['outbound'];
  if (sourceOutbound is! String || sourceOutbound.isEmpty) {
    throw const MacOSTunnelConfigException('macOS tunnel route rule has no outbound');
  }
  return {
    ...match,
    'action': 'route',
    'outbound': directOutboundTags.contains(sourceOutbound)
        ? _macOSTunnelDirectOutboundTag
        : _macOSTunnelSocksOutboundTag,
  };
}

Map<String, dynamic> _projectMacOSRemoteRuleSet(String tag, List<Map<String, dynamic>> sourceRuleSets) {
  final source = sourceRuleSets.where((ruleSet) => ruleSet['tag'] == tag).firstOrNull;
  if (source == null || source['type'] != 'remote') {
    throw MacOSTunnelConfigException('macOS tunnel route rule set $tag is unavailable');
  }
  final sourceUrl = source['url'];
  final uri = sourceUrl is String ? Uri.tryParse(sourceUrl) : null;
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw MacOSTunnelConfigException('macOS tunnel route rule set $tag has an invalid URL');
  }
  final format = source['format'] ?? 'binary';
  if (format != 'binary') {
    throw MacOSTunnelConfigException('macOS tunnel route rule set $tag has an unsupported format');
  }
  return {
    'tag': tag,
    'type': 'remote',
    'format': 'binary',
    'url': sourceUrl,
    'update_interval': source['update_interval'] ?? '1d',
    'download_detour': _macOSTunnelSocksOutboundTag,
  };
}

Map<String, dynamic> _macOSDirectRouteRuleSet(String? ruleSetPath) {
  if (ruleSetPath == null || !p.isAbsolute(ruleSetPath) || p.extension(ruleSetPath) != '.srs') {
    throw const MacOSTunnelConfigException('macOS direct route rule set is unavailable');
  }
  return {'tag': _macOSDirectRouteRuleSetTag, 'type': 'local', 'format': 'binary', 'path': p.normalize(ruleSetPath)};
}

void _configureIpv4OnlyDnsBridge(Map<String, dynamic> config, {required String dnsTag, bool rejectIpv6 = false}) {
  final rawOutbounds = config['outbounds'];
  final outbounds = rawOutbounds is List
      ? rawOutbounds.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  final proxyTag = outbounds
      .where((outbound) {
        final type = outbound['type'];
        final tag = outbound['tag'];
        return tag is String && tag.isNotEmpty && type != 'direct' && type != 'block' && type != 'dns';
      })
      .map((outbound) => outbound['tag'] as String)
      .firstOrNull;
  if (proxyTag == null) {
    throw const MacOSTunnelConfigException('managed config has no proxy outbound for desktop DNS');
  }

  config['dns'] = {
    'servers': [
      {
        'type': 'https',
        'tag': dnsTag,
        'server': '1.1.1.1',
        'detour': proxyTag,
        'tls': {'enabled': true, 'server_name': 'cloudflare-dns.com'},
      },
    ],
    'final': dnsTag,
    'strategy': 'ipv4_only',
  };

  final route = config['route'] is Map ? Map<String, dynamic>.from(config['route'] as Map) : <String, dynamic>{};
  final rules = route['rules'] is List
      ? (route['rules'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  Map<String, dynamic>? privateDirectRule;
  if (rejectIpv6) {
    final directTag = outbounds
        .where((outbound) => outbound['type'] == 'direct' && outbound['tag'] is String)
        .map((outbound) => outbound['tag'] as String)
        .firstOrNull;
    if (directTag == null) {
      throw const MacOSTunnelConfigException('managed config has no direct outbound for private network access');
    }
    final privateDirectRuleIndex = rules.indexWhere(
      (rule) => rule['ip_is_private'] == true && rule['action'] == 'route' && rule['outbound'] == directTag,
    );
    privateDirectRule = privateDirectRuleIndex < 0
        ? {'ip_is_private': true, 'action': 'route', 'outbound': directTag}
        : rules.removeAt(privateDirectRuleIndex);
  }
  final insertAt = rules.indexWhere((rule) => rule['action'] != 'sniff');
  rules.insertAll(insertAt < 0 ? rules.length : insertAt, [
    {
      'port': [53],
      'action': 'hijack-dns',
    },
    if (privateDirectRule != null) privateDirectRule,
    if (rejectIpv6) {'ip_version': 6, 'action': 'reject'},
  ]);
  route['rules'] = rules;
  config['route'] = route;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

bool _isLoopbackListen(Object? listen) => listen == '127.0.0.1' || listen == 'localhost' || listen == '::1';
