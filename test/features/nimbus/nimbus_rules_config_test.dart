import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';

void main() {
  group('Nimbus managed Hiddify routes', () {
    test('puts a custom direct domain before public rules and local fallback', () {
      final options = buildNimbusManagedRouteOptions(rulesPackage: _rulesPackage, isAutomaticMode: true);

      expect(options.rules, hasLength(4));
      expect(options.rules[0], {
        'domain_suffix': ['rawya.ai'],
        'action': 'route',
        'outbound': nimbusHiddifyDirectTag,
      });
      expect(options.rules[1]['rule_set'], ['geosite-gfw']);
      expect(options.rules[1]['outbound'], 'nimbus-proxy');
      expect(options.rules[2], {
        'network': ['udp'],
        'action': 'route',
        'outbound': 'nimbus-proxy',
      });
      expect(options.rules[3], {'ip_is_private': true, 'action': 'route', 'outbound': nimbusHiddifyDirectTag});
      expect(options.ruleSets.single['tag'], 'geosite-gfw');
      expect(options.ruleSets.single['download_detour'], 'nimbus-proxy');
    });

    test('keeps custom rules effective in automatic mode', () {
      final options = buildNimbusManagedRouteOptions(rulesPackage: _rulesPackage, isAutomaticMode: true);

      expect(options.rules.where((rule) => rule['domain_suffix'] != null), isNotEmpty);
      expect(options.rules.any((rule) => rule['rule_set'] != null), isTrue);
    });

    test('compiles a custom block rule to a reject route action', () {
      final rules = buildNimbusRouteRules([
        const NimbusRulePackageItem(pattern: 'ads.example.com', patternType: 'domain', action: 'block'),
      ], 'nimbus-proxy');

      expect(rules, [
        {
          'domain_suffix': ['ads.example.com'],
          'action': 'reject',
        },
      ]);
    });

    test('routes every destination through acceleration in global mode', () {
      final options = buildNimbusManagedRouteOptions(rulesPackage: _rulesPackage, isAutomaticMode: false);

      expect(options.rules, [
        {'action': 'route', 'outbound': 'nimbus-proxy'},
      ]);
      expect(options.ruleSets, isEmpty);
    });

    test('persists the local rules package cache time', () {
      final cachedAt = DateTime.utc(2026, 8, 4, 12, 30);
      final encoded = _rulesPackage.copyWith(cachedAt: cachedAt).encode();
      final decoded = NimbusRulesPackage.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded.cachedAt?.toUtc(), cachedAt);
      expect(decoded.manifest.sameVersions(_rulesPackage.manifest), isTrue);
      expect(decoded.userRules.single.pattern, _rulesPackage.userRules.single.pattern);
      expect(decoded.userRules.single.action, _rulesPackage.userRules.single.action);
      expect(decoded.publicRules.single.pattern, _rulesPackage.publicRules.single.pattern);
      expect(decoded.publicRules.single.action, _rulesPackage.publicRules.single.action);
    });
  });
}

const _manifest = NimbusRulesManifest(
  publicRulesVersion: '2026.08.03.1',
  userRulesVersion: 'sha256:user',
  configVersion: nimbusRulesConfigVersion,
  requiresUpdate: false,
  publicRulesChanged: false,
  userRulesChanged: false,
  configChanged: false,
);

const _rulesPackage = NimbusRulesPackage(
  manifest: _manifest,
  userRules: [NimbusRulePackageItem(pattern: 'rawya.ai', patternType: 'domain', action: 'direct')],
  publicRules: [
    NimbusRulePackageItem(
      kind: 'rule_set',
      pattern: 'geosite-gfw',
      patternType: 'geosite',
      action: 'proxy',
      sourceUrl: 'https://rules.example/geosite-gfw.srs',
      format: 'binary',
      updateInterval: '1d',
    ),
  ],
);
