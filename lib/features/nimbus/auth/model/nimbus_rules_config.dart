import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

const nimbusRulesConfigVersion = 'sing-box-rules-v1';

List<Map<String, dynamic>> buildNimbusRouteRules(List<NimbusRulePackageItem> rules, String proxyTag) {
  final normalized = <Map<String, dynamic>>[];
  for (final rule in rules) {
    final outbound = rule.action == 'direct' ? 'nimbus-direct' : proxyTag;
    if (rule.patternType == 'domain' && rule.pattern.isNotEmpty) {
      normalized.add({
        'domain_suffix': [rule.pattern],
        'outbound': outbound,
      });
    } else if ((rule.patternType == 'ip' || rule.patternType == 'cidr') && rule.pattern.isNotEmpty) {
      normalized.add({
        'ip_cidr': [rule.pattern],
        'outbound': outbound,
      });
    }
  }
  return normalized;
}

Map<String, dynamic> nimbusFallbackRouteRule() => {'ip_is_private': true, 'outbound': 'nimbus-direct'};
