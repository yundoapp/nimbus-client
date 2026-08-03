import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';

void main() {
  group('Nimbus managed Hiddify routes', () {
    test('puts a custom direct domain before public rules and local fallback', () {
      final options = buildNimbusManagedRouteOptions(
        rulesPackage: _rulesPackage,
        isAutomaticMode: true,
        customWebsiteAccessEnabled: true,
      );

      expect(options.rules, hasLength(3));
      expect(options.rules[0], {
        'domain_suffix': ['rawya.ai'],
        'action': 'route',
        'outbound': nimbusHiddifyDirectTag,
      });
      expect(options.rules[1]['rule_set'], ['geosite-gfw']);
      expect(options.rules[1]['outbound'], 'nimbus-proxy');
      expect(options.rules[2], {'ip_is_private': true, 'action': 'route', 'outbound': nimbusHiddifyDirectTag});
      expect(options.ruleSets.single['tag'], 'geosite-gfw');
      expect(options.ruleSets.single['download_detour'], 'nimbus-proxy');
    });

    test('keeps public rules but omits custom sites when the device switch is off', () {
      final options = buildNimbusManagedRouteOptions(
        rulesPackage: _rulesPackage,
        isAutomaticMode: true,
        customWebsiteAccessEnabled: false,
      );

      expect(options.rules.where((rule) => rule['domain_suffix'] != null), isEmpty);
      expect(options.rules.any((rule) => rule['rule_set'] != null), isTrue);
    });

    test('does not inject product routes in global mode', () {
      final options = buildNimbusManagedRouteOptions(
        rulesPackage: _rulesPackage,
        isAutomaticMode: false,
        customWebsiteAccessEnabled: true,
      );

      expect(options.rules, isEmpty);
      expect(options.ruleSets, isEmpty);
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
