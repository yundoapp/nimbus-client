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
          customWebsiteAccessEnabled: true,
        ),
        isFalse,
      );
      expect(
        shouldReapplyNimbusConnection(
          connection: const Disconnected(),
          connectedReported: true,
          userRulesOnly: false,
          proxyMode: NimbusProxyMode.auto,
          customWebsiteAccessEnabled: true,
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
          customWebsiteAccessEnabled: true,
        ),
        isTrue,
      );
      expect(
        shouldReapplyNimbusConnection(
          connection: const Connected(),
          connectedReported: true,
          userRulesOnly: true,
          proxyMode: NimbusProxyMode.global,
          customWebsiteAccessEnabled: true,
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

    test('does not overwrite the cache when a replacement download fails', () async {
      var saves = 0;

      await expectLater(
        prepareNimbusRulesPackage(
          cached: _rulesPackage,
          fetchManifest: (_) async => _changedManifest,
          fetchPackage: () async => throw const FormatException('truncated response'),
          savePackage: (_) async {
            saves += 1;
          },
        ),
        throwsA(isA<FormatException>()),
      );

      expect(saves, 0);
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

const _changedManifest = NimbusRulesManifest(
  publicRulesVersion: '2026.08.03.2',
  userRulesVersion: 'sha256:user',
  configVersion: nimbusRulesConfigVersion,
  requiresUpdate: true,
  publicRulesChanged: true,
  userRulesChanged: false,
  configChanged: false,
);

const _rulesPackage = NimbusRulesPackage(manifest: _manifest, userRules: [], publicRules: []);
