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
    publicRules: [NimbusRulePackageItem(pattern: 'openai.com', patternType: 'domain', action: 'accelerate')],
  );
  final decoded = NimbusRulesPackage.fromJson(rulesPackage.toJson());
  _expect(decoded.manifest.sameVersions(rulesPackage.manifest), '规则包版本缓存往返失败');
  _expect(decoded.userRules.single.pattern == 'example.com', '用户规则缓存往返失败');
  _expect(decoded.publicRules.single.action == 'accelerate', '公共规则缓存往返失败');

  const rules = [
    NimbusRulePackageItem(pattern: 'openai.com', patternType: 'domain', action: 'accelerate'),
    NimbusRulePackageItem(pattern: '10.20.0.0/16', patternType: 'cidr', action: 'direct'),
  ];
  final routeRules = buildNimbusRouteRules(rules, 'nimbus-proxy');
  _expect(routeRules.length == 2, '规则映射数量不正确');
  _expect(routeRules[0]['outbound'] == 'nimbus-proxy', '需要连接的域名未使用代理出口');
  _expect(routeRules[1]['outbound'] == 'nimbus-direct', '无需连接的网段未使用直连出口');

  final fallback = nimbusFallbackRouteRule();
  _expect(fallback['ip_is_private'] == true, '内置兜底未覆盖本地网络');
  _expect(fallback['outbound'] == 'nimbus-direct', '内置兜底未使用直连出口');

  stdout.writeln('Nimbus 规则包 smoke 通过。');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
