import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
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
}
