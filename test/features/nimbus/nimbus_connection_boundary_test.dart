import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  group('Nimbus connection ownership', () {
    test('does not expose an unowned Hiddify connection as Nimbus connected', () {
      final status = presentNimbusOwnedConnectionStatus(
        rawConnectionStatus: const AsyncData(Connected()),
        nimbusConnection: const NimbusConnectionState(),
      );

      expect(status.valueOrNull, isA<Disconnected>());
      expect(isNimbusOwnedConnection(connection: const Connected(), connectedReported: false), isFalse);
    });

    test('exposes a connection only after Nimbus reports it', () {
      final status = presentNimbusOwnedConnectionStatus(
        rawConnectionStatus: const AsyncData(Connected()),
        nimbusConnection: const NimbusConnectionState(connectedReported: true),
      );

      expect(status.valueOrNull, isA<Connected>());
      expect(isNimbusOwnedConnection(connection: const Connected(), connectedReported: true), isTrue);
    });

    test('restores ownership only for a persisted user-started connection', () {
      expect(
        shouldRestoreNimbusOwnership(
          connection: const Connected(),
          startedByUser: true,
          activeProfileId: 'yundo-managed-profile',
        ),
        isTrue,
      );
      expect(
        shouldRestoreNimbusOwnership(
          connection: const Connected(),
          startedByUser: false,
          activeProfileId: 'yundo-managed-profile',
        ),
        isFalse,
      );
      expect(
        shouldRestoreNimbusOwnership(
          connection: const Connected(),
          startedByUser: true,
          activeProfileId: 'other-profile',
        ),
        isFalse,
      );
      expect(
        shouldRestoreNimbusOwnership(
          connection: const Disconnected(),
          startedByUser: true,
          activeProfileId: 'yundo-managed-profile',
        ),
        isFalse,
      );
    });

    test('presents preparation as connecting before Nimbus ownership is reported', () {
      final status = presentNimbusOwnedConnectionStatus(
        rawConnectionStatus: const AsyncData(Disconnected()),
        nimbusConnection: const NimbusConnectionState(isPreparing: true),
      );

      expect(status.valueOrNull, isA<Connecting>());
    });
  });

  group('Nimbus reapply boundary', () {
    test('does not reconnect an unowned or disconnected connection', () {
      expect(
        shouldReapplyNimbusConnection(
          connection: const Connected(),
          connectedReported: false,
          userRulesOnly: false,
          proxyMode: NimbusProxyMode.auto,
        ),
        isFalse,
      );
      expect(
        shouldReapplyNimbusConnection(
          connection: const Disconnected(),
          connectedReported: true,
          userRulesOnly: false,
          proxyMode: NimbusProxyMode.auto,
        ),
        isFalse,
      );
    });

    test('reapplies user rules only in automatic custom-site mode', () {
      expect(
        shouldReapplyNimbusConnection(
          connection: const Connected(),
          connectedReported: true,
          userRulesOnly: true,
          proxyMode: NimbusProxyMode.auto,
        ),
        isTrue,
      );
      expect(
        shouldReapplyNimbusConnection(
          connection: const Connected(),
          connectedReported: true,
          userRulesOnly: true,
          proxyMode: NimbusProxyMode.global,
        ),
        isFalse,
      );
    });
  });

  group('Nimbus rules package preparation', () {
    test('reuses a supported cache when manifest versions match', () async {
      var downloads = 0;
      var saves = 0;

      final result = await prepareNimbusRulesPackage(
        cached: _rulesPackage,
        fetchManifest: (_) async => _manifest,
        fetchPackage: () async {
          downloads += 1;
          return _rulesPackage;
        },
        savePackage: (_) async {
          saves += 1;
        },
      );

      expect(result, same(_rulesPackage));
      expect(downloads, 0);
      expect(saves, 0);
    });

    test('uses the supported cache when the manifest request fails', () async {
      final result = await prepareNimbusRulesPackage(
        cached: _rulesPackage,
        fetchManifest: (_) async => throw const FormatException('network unavailable'),
        fetchPackage: () async => throw StateError('must not download without a manifest'),
        savePackage: (_) async {},
      );

      expect(result, same(_rulesPackage));
    });

    test('refreshes the cache when the managed public source changes', () async {
      var downloads = 0;
      var saves = 0;

      final result = await prepareNimbusRulesPackage(
        cached: _rulesPackage,
        fetchManifest: (_) async => _sourceChangedManifest,
        fetchPackage: () async {
          downloads += 1;
          return _rulesPackage;
        },
        savePackage: (_) async {
          saves += 1;
        },
      );

      expect(result, same(_rulesPackage));
      expect(downloads, 1);
      expect(saves, 1);
    });

    test('keeps the old cache when a replacement download fails', () async {
      var saves = 0;

      final result = await prepareNimbusRulesPackage(
        cached: _rulesPackage,
        fetchManifest: (_) async => _changedManifest,
        fetchPackage: () async => throw const FormatException('truncated response'),
        savePackage: (_) async {
          saves += 1;
        },
      );

      expect(result, same(_rulesPackage));
      expect(saves, 0);
    });
  });
}

const _manifest = NimbusRulesManifest(
  publicRulesVersion: '2026.08.03.1',
  publicRulesSourceVersion: 'sha256:public-source',
  userRulesVersion: 'sha256:user',
  configVersion: nimbusRulesConfigVersion,
  requiresUpdate: false,
  publicRulesChanged: false,
  userRulesChanged: false,
  configChanged: false,
);

const _changedManifest = NimbusRulesManifest(
  publicRulesVersion: '2026.08.03.2',
  publicRulesSourceVersion: 'sha256:changed-source',
  userRulesVersion: 'sha256:user',
  configVersion: nimbusRulesConfigVersion,
  requiresUpdate: true,
  publicRulesChanged: true,
  userRulesChanged: false,
  configChanged: false,
);

const _sourceChangedManifest = NimbusRulesManifest(
  publicRulesVersion: '2026.08.03.1',
  publicRulesSourceVersion: 'sha256:changed-source',
  userRulesVersion: 'sha256:user',
  configVersion: nimbusRulesConfigVersion,
  requiresUpdate: true,
  publicRulesChanged: true,
  userRulesChanged: false,
  configChanged: false,
);

const _rulesPackage = NimbusRulesPackage(manifest: _manifest, userRules: [], publicRules: []);
