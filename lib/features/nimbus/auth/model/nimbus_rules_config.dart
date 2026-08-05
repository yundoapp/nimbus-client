import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const nimbusRulesConfigVersion = 'sing-box-rules-v3';
const nimbusRuleSetHttpClientTag = 'nimbus-rule-download';
const nimbusRuleSetDownloadMode = NimbusRuleSetDownloadMode.legacyDownloadDetour;
const nimbusHiddifyDirectTag = 'direct \u00a7hide\u00a7';

class NimbusManagedRouteOptions {
  const NimbusManagedRouteOptions({required this.rules, required this.ruleSets});

  const NimbusManagedRouteOptions.empty() : rules = const [], ruleSets = const [];

  final List<Map<String, dynamic>> rules;
  final List<Map<String, dynamic>> ruleSets;
}

final nimbusManagedRouteOptionsProvider = StateProvider<NimbusManagedRouteOptions>(
  (_) => const NimbusManagedRouteOptions.empty(),
);

enum NimbusRuleSetDownloadMode { legacyDownloadDetour, httpClient }

List<Map<String, dynamic>> buildNimbusManagedInbounds({required bool isMacOS}) => [
  {
    'type': 'tun',
    'tag': 'nimbus-tun',
    if (!isMacOS) 'interface_name': 'nimbus0',
    'address': ['172.19.0.1/30'],
    'mtu': 9000,
    'auto_route': true,
    'strict_route': true,
    'stack': isMacOS ? 'system' : 'mixed',
  },
  {'type': 'mixed', 'tag': 'nimbus-mixed', 'listen': '127.0.0.1', 'listen_port': 12334},
];

Map<String, dynamic> nimbusSniffRouteRule() => {'action': 'sniff'};

Map<String, dynamic> normalizeNimbusRouteRule(Map<String, dynamic> rule) {
  if (rule['action'] == null && rule['outbound'] is String) {
    return {...rule, 'action': 'route'};
  }
  return Map<String, dynamic>.from(rule);
}

List<NimbusRulePackageItem> selectActiveNimbusUserRules({
  required bool isAutomaticMode,
  required List<NimbusRulePackageItem> userRules,
}) {
  if (!isAutomaticMode) {
    return const <NimbusRulePackageItem>[];
  }
  return userRules;
}

List<Map<String, dynamic>> buildNimbusRouteRules(
  List<NimbusRulePackageItem> rules,
  String proxyTag, {
  String directTag = 'nimbus-direct',
}) {
  final normalized = <Map<String, dynamic>>[];
  for (final rule in rules) {
    final outbound = rule.action == 'direct' ? directTag : proxyTag;
    if (rule.pattern.isEmpty) continue;
    final match = switch (rule.patternType) {
      'domain' => <String, dynamic>{
        'domain_suffix': [rule.pattern],
      },
      'domain_exact' => <String, dynamic>{
        'domain': [rule.pattern],
      },
      'ip' || 'cidr' => <String, dynamic>{
        'ip_cidr': [rule.pattern],
      },
      'geosite' || 'geoip' => <String, dynamic>{
        'rule_set': [rule.pattern],
      },
      'process' => <String, dynamic>{
        'process_name': [rule.pattern],
      },
      _ => null,
    };
    if (match == null) continue;
    normalized.add({
      ...match,
      if (rule.action == 'block') 'action': 'reject' else ...{'action': 'route', 'outbound': outbound},
    });
  }
  return normalized;
}

bool useNimbusRuleSetHttpClient(NimbusRuleSetDownloadMode mode) => mode == NimbusRuleSetDownloadMode.httpClient;

List<Map<String, dynamic>> buildNimbusHttpClients(
  String detourTag, {
  NimbusRuleSetDownloadMode mode = nimbusRuleSetDownloadMode,
}) => useNimbusRuleSetHttpClient(mode)
    ? [
        {'tag': nimbusRuleSetHttpClientTag, 'detour': detourTag},
      ]
    : const [];

List<Map<String, dynamic>> buildNimbusRuleSets(
  List<NimbusRulePackageItem> rules,
  String downloadDetour, {
  NimbusRuleSetDownloadMode mode = nimbusRuleSetDownloadMode,
}) {
  final definitions = <String, Map<String, dynamic>>{};
  for (final rule in rules) {
    if (rule.kind != 'rule_set' || rule.pattern.isEmpty || definitions.containsKey(rule.pattern)) continue;
    final sourceUrl = rule.sourceUrl?.trim() ?? '';
    final sourceUri = Uri.tryParse(sourceUrl);
    if (sourceUrl.isEmpty || sourceUri == null || sourceUri.scheme != 'https' || sourceUri.host.isEmpty) {
      throw FormatException('远程规则库 ${rule.pattern} 缺少有效的 HTTPS 下载地址');
    }
    if (rule.format != null && rule.format != 'binary') {
      throw FormatException('远程规则库 ${rule.pattern} 使用了不支持的格式 ${rule.format}');
    }
    definitions[rule.pattern] = {
      'tag': rule.pattern,
      'type': 'remote',
      'format': rule.format ?? 'binary',
      'url': sourceUrl,
      'update_interval': rule.updateInterval ?? '1d',
      if (useNimbusRuleSetHttpClient(mode))
        'http_client': nimbusRuleSetHttpClientTag
      else
        'download_detour': downloadDetour,
    };
  }
  return definitions.values.toList(growable: false);
}

Map<String, dynamic> nimbusFallbackRouteRule({String directTag = 'nimbus-direct'}) => {
  'ip_is_private': true,
  'action': 'route',
  'outbound': directTag,
};

Map<String, dynamic> nimbusGlobalRouteRule({String proxyTag = 'nimbus-proxy'}) => {
  'action': 'route',
  'outbound': proxyTag,
};

NimbusManagedRouteOptions buildNimbusManagedRouteOptions({
  required NimbusRulesPackage rulesPackage,
  required bool isAutomaticMode,
  String proxyTag = 'nimbus-proxy',
  String directTag = nimbusHiddifyDirectTag,
}) {
  if (!isAutomaticMode) {
    // Global mode must also bypass Hiddify's built-in regional rules. The
    // managed rule is inserted before those rules by the core adapter.
    return NimbusManagedRouteOptions(
      rules: [nimbusGlobalRouteRule(proxyTag: proxyTag)],
      ruleSets: const [],
    );
  }

  final activeUserRules = selectActiveNimbusUserRules(
    isAutomaticMode: isAutomaticMode,
    userRules: rulesPackage.userRules,
  );
  final activeRules = [...activeUserRules, ...rulesPackage.publicRules];
  return NimbusManagedRouteOptions(
    rules: [
      ...buildNimbusRouteRules(activeRules, proxyTag, directTag: directTag),
      // 浏览器可能在域名和协议尚未可供规则匹配前就发起 UDP。将其送入加速
      // 出站，避免首包落入 macOS TUN 下不可用的普通直连兜底。
      {
        'network': ['udp'],
        'action': 'route',
        'outbound': proxyTag,
      },
      nimbusFallbackRouteRule(directTag: directTag),
    ],
    ruleSets: buildNimbusRuleSets(activeRules, proxyTag),
  );
}
