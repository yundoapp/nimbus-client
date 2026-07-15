import 'dart:io';

import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';

void main() {
  const rulesPackage = NimbusRulesPackage(
    manifest: NimbusRulesManifest(
      publicRulesVersion: '2026.07.10.1',
      userRulesVersion: 'sha256:user',
      configVersion: nimbusRulesConfigVersion,
      requiresUpdate: false,
      publicRulesChanged: false,
      userRulesChanged: false,
      configChanged: false,
    ),
    userRules: [NimbusRulePackageItem(pattern: 'example.com', patternType: 'domain', action: 'direct')],
    publicRules: [
      NimbusRulePackageItem(pattern: 'openai.com', patternType: 'domain', action: 'accelerate'),
      NimbusRulePackageItem(
        kind: 'rule_set',
        pattern: 'geosite-gfw',
        patternType: 'geosite',
        action: 'accelerate',
        sourceUrl: 'https://rules.example/geosite-gfw.srs',
        format: 'binary',
        updateInterval: '1d',
      ),
    ],
  );
  final decoded = NimbusRulesPackage.fromJson(rulesPackage.toJson());
  _expect(decoded.manifest.sameVersions(rulesPackage.manifest), '规则包版本缓存往返失败');
  _expect(decoded.userRules.single.pattern == 'example.com', '用户规则缓存往返失败');
  _expect(decoded.publicRules[0].action == 'accelerate', '公共规则缓存往返失败');
  _expect(decoded.publicRules[1].sourceUrl == 'https://rules.example/geosite-gfw.srs', '规则库 URL 缓存往返失败');

  const rules = [
    NimbusRulePackageItem(pattern: 'openai.com', patternType: 'domain', action: 'accelerate'),
    NimbusRulePackageItem(pattern: 'gemini.google.com', patternType: 'domain_exact', action: 'accelerate'),
    NimbusRulePackageItem(pattern: '10.20.0.0/16', patternType: 'cidr', action: 'direct'),
    NimbusRulePackageItem(
      kind: 'rule_set',
      pattern: 'geosite-cn',
      patternType: 'geosite',
      action: 'direct',
      sourceUrl: 'https://rules.example/geosite-cn.srs',
      format: 'binary',
      updateInterval: '1d',
    ),
    NimbusRulePackageItem(
      kind: 'rule_set',
      pattern: 'geoip-cn',
      patternType: 'geoip',
      action: 'direct',
      sourceUrl: 'https://rules.example/geoip-cn.srs',
      format: 'binary',
      updateInterval: '1d',
    ),
    NimbusRulePackageItem(pattern: 'aria2c', patternType: 'process', action: 'direct'),
    NimbusRulePackageItem(
      kind: 'rule_set',
      pattern: 'geosite-category-ads-all',
      patternType: 'geosite',
      action: 'block',
      sourceUrl: 'https://rules.example/geosite-category-ads-all.srs',
      format: 'binary',
      updateInterval: '1d',
    ),
    NimbusRulePackageItem(
      kind: 'rule_set',
      pattern: 'geosite-gfw',
      patternType: 'geosite',
      action: 'accelerate',
      sourceUrl: 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs',
      format: 'binary',
      updateInterval: '1d',
    ),
  ];
  final routeRules = buildNimbusRouteRules(rules, 'nimbus-proxy');
  _expect(routeRules.length == 8, '规则映射数量不正确');
  _expect(routeRules[0]['outbound'] == 'nimbus-proxy', '需要连接的域名未使用代理出口');
  _expect(routeRules[1]['domain'] != null, '精确域名规则未正确映射');
  _expect(routeRules[2]['outbound'] == 'nimbus-direct', '无需连接的网段未使用直连出口');
  _expect(routeRules[3]['rule_set'] != null, 'GeoSite 规则未正确映射');
  _expect(routeRules[5]['process_name'] != null, '进程规则未正确映射');
  _expect(routeRules[6]['action'] == 'reject', '拦截规则未正确映射');

  final ruleSets = buildNimbusRuleSets(rules, 'nimbus-proxy');
  _expect(ruleSets.length == 4, '远程规则库未完整生成');
  _expect(ruleSets.every((ruleSet) => ruleSet['download_detour'] == 'nimbus-proxy'), '规则集下载出口不正确');
  _expect(ruleSets.every((ruleSet) => ruleSet['update_interval'] == '1d'), '规则库未按日检查更新');
  _expect(ruleSets[0]['url'] == 'https://rules.example/geosite-cn.srs', '客户端没有使用 API 下发的规则库 URL');
  _expect(
    ruleSets.last['url'] == 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs',
    'GFW 规则库 URL 不正确',
  );

  var rejectedMissingUrl = false;
  try {
    buildNimbusRuleSets(const [
      NimbusRulePackageItem(kind: 'rule_set', pattern: 'geosite-invalid', patternType: 'geosite', action: 'direct'),
    ], 'nimbus-proxy');
  } on FormatException {
    rejectedMissingUrl = true;
  }
  _expect(rejectedMissingUrl, '客户端没有拒绝缺少 URL 的远程规则库');

  final fallback = nimbusFallbackRouteRule();
  _expect(fallback['ip_is_private'] == true, '内置兜底未覆盖本地网络');
  _expect(fallback['outbound'] == 'nimbus-direct', '内置兜底未使用直连出口');

  stdout.writeln('Nimbus 规则包 smoke 通过。');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
