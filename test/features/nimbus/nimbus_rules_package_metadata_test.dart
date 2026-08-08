import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

void main() {
  test('persists the timestamp of the active public snapshot', () {
    final loadedAt = DateTime.utc(2026, 8, 6, 8, 31, 52);
    final package = NimbusRulesPackage(
      manifest: _manifest(publicRulesUpdatedAt: DateTime.utc(2026, 8, 3)),
      userRules: const [],
      publicRules: const [],
      publicRulesLoadedAt: loadedAt,
    );

    final decoded = NimbusRulesPackage.fromJson(package.toJson());

    expect(decoded.publicRulesLoadedAt, loadedAt.toLocal());
  });

  test('fills missing metadata only from the matching bundled snapshot', () {
    final bundled = NimbusRulesPackage(
      manifest: _manifest(publicRulesUpdatedAt: DateTime.utc(2026, 8, 3)),
      userRules: const [],
      publicRules: const [],
      publicRulesLoadedAt: DateTime.utc(2026, 8, 6),
    );
    final cached = NimbusRulesPackage(manifest: _manifest(), userRules: const [], publicRules: const []);

    final enriched = cached.withFallbackPublicRulesMetadata(bundled);

    expect(enriched.manifest.publicRulesUpdatedAt, DateTime.utc(2026, 8, 3));
    expect(enriched.publicRulesLoadedAt, DateTime.utc(2026, 8, 6));
  });

  test('does not copy metadata from a different public snapshot', () {
    final bundled = NimbusRulesPackage(
      manifest: _manifest(publicRulesVersion: '2026.08.03.2', publicRulesUpdatedAt: DateTime.utc(2026, 8, 3)),
      userRules: const [],
      publicRules: const [],
    );
    final cached = NimbusRulesPackage(manifest: _manifest(), userRules: const [], publicRules: const []);

    final enriched = cached.withFallbackPublicRulesMetadata(bundled);

    expect(enriched.manifest.publicRulesUpdatedAt, isNull);
  });

  test('preserves user rule identity and update time in the package', () {
    final updatedAt = DateTime.utc(2026, 8, 7, 9, 20);
    const item = NimbusRulePackageItem(id: 'rule-1', pattern: 'example.com', patternType: 'domain', action: 'direct');
    final decoded = NimbusRulePackageItem.fromJson(item.toJson()..['updatedAt'] = updatedAt.toIso8601String());

    expect(decoded.id, 'rule-1');
    expect(decoded.updatedAt, updatedAt.toLocal());
  });
}

NimbusRulesManifest _manifest({String publicRulesVersion = '2026.08.03.1', DateTime? publicRulesUpdatedAt}) =>
    NimbusRulesManifest(
      publicRulesVersion: publicRulesVersion,
      publicRulesSourceVersion: 'sha256:public-source',
      publicRulesUpdatedAt: publicRulesUpdatedAt,
      userRulesVersion: 'sha256:user',
      configVersion: 'sing-box-rules-v3',
      requiresUpdate: false,
      publicRulesChanged: false,
      userRulesChanged: false,
      configChanged: false,
    );
