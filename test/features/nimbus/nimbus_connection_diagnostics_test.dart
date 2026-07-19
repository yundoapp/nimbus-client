import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_issue_report_dialog.dart';
import 'package:hiddify/hiddifycore/core_interface/windows_tunnel_service.dart';

void main() {
  test('configuration failures expose a safe structural detail code', () {
    expect(nimbusConfigFailureDetailCode('managed config has no local mixed or socks inbound'), 'MISSING_LOCAL_BRIDGE');
    expect(nimbusConfigFailureDetailCode('parse error at secret.example'), 'CONFIG_PARSE_FAILED');
    expect(nimbusConfigFailureDetailCode(null), 'CONFIG_REJECTED');
  });

  late Translations translations;

  setUpAll(() async {
    translations = await AppLocale.zhCn.build();
  });

  test('Windows service failures keep an actionable reason and stable diagnostic code', () {
    final presentation = presentNimbusConnectionFailure(
      const ConnectionFailure.unexpected(
        WindowsTunnelServiceException(WindowsTunnelFailureKind.serviceUnavailable, 'UNAVAILABLE: connection refused'),
      ),
      translations,
      platform: NimbusDiagnosticPlatform.windows,
    );

    expect(presentation.message, contains('重启 Windows'));
    expect(presentation.diagnosticCode, 'W-SVC-02');
    expect(presentation.failureCode, 'WINDOWS_SERVICE_UNAVAILABLE');
    expect(presentation.stage, 'SERVICE_START');
  });

  test('unknown start failures use a stable platform-specific diagnostic code', () {
    const cases = {
      NimbusDiagnosticPlatform.windows: 'W-START-01',
      NimbusDiagnosticPlatform.macos: 'M-START-01',
      NimbusDiagnosticPlatform.ios: 'I-START-01',
      NimbusDiagnosticPlatform.android: 'A-START-01',
      NimbusDiagnosticPlatform.unknown: 'C-START-01',
    };

    for (final entry in cases.entries) {
      final presentation = presentNimbusConnectionFailure(
        const ConnectionFailure.unexpected('unknown'),
        translations,
        platform: entry.key,
      );

      expect(presentation.message, contains('复制诊断信息'));
      expect(presentation.diagnosticCode, entry.value);
      expect(presentation.failureCode, 'CLIENT_START_FAILED');
      expect(presentation.stage, 'START');
    }
  });

  test('system permission failures share one action while retaining the platform code', () {
    const cases = {
      NimbusDiagnosticPlatform.windows: 'W-PERM-01',
      NimbusDiagnosticPlatform.macos: 'M-PERM-01',
      NimbusDiagnosticPlatform.ios: 'I-PERM-01',
      NimbusDiagnosticPlatform.android: 'A-PERM-01',
    };

    for (final entry in cases.entries) {
      final presentation = presentNimbusConnectionFailure(
        const ConnectionFailure.missingVpnPermission(),
        translations,
        platform: entry.key,
      );

      expect(presentation.message, contains('系统设置'));
      expect(presentation.diagnosticCode, entry.value);
      expect(presentation.failureCode, 'MISSING_SYSTEM_PERMISSION');
      expect(presentation.stage, 'SYSTEM_PERMISSION');
    }
  });

  test('system component, notification, configuration, conflict and status failures are classified', () {
    final core = presentNimbusConnectionFailure(
      const ConnectionFailure.backgroundCoreNotAvailable(),
      translations,
      platform: NimbusDiagnosticPlatform.android,
    );
    final notification = presentNimbusConnectionFailure(
      const ConnectionFailure.missingNotificationPermission(),
      translations,
      platform: NimbusDiagnosticPlatform.android,
    );
    final configuration = presentNimbusConnectionFailure(
      const ConnectionFailure.invalidConfig(),
      translations,
      platform: NimbusDiagnosticPlatform.ios,
    );
    final conflict = presentNimbusConnectionConflict(translations, platform: NimbusDiagnosticPlatform.macos);
    final status = presentNimbusConnectionStatusFailure(translations, platform: NimbusDiagnosticPlatform.ios);

    expect((core.diagnosticCode, core.failureCode, core.stage), ('A-CORE-01', 'CORE_NOT_AVAILABLE', 'CORE_START'));
    expect(
      (notification.diagnosticCode, notification.failureCode, notification.stage),
      ('A-NOTIFY-01', 'MISSING_NOTIFICATION_PERMISSION', 'NOTIFICATION_PERMISSION'),
    );
    expect(
      (configuration.diagnosticCode, configuration.failureCode, configuration.stage),
      ('C-CONFIG-01', 'INVALID_MANAGED_CONFIG', 'CONFIGURATION'),
    );
    expect(
      (conflict.diagnosticCode, conflict.failureCode, conflict.stage),
      ('M-NET-02', 'OTHER_CONNECTION_ACTIVE', 'NETWORK_CONFLICT'),
    );
    expect(
      (status.diagnosticCode, status.failureCode, status.stage),
      ('I-STATUS-01', 'CLIENT_STATUS_FAILED', 'STATUS'),
    );
  });

  test('preparation failures keep the user-safe API message and a stable code', () {
    final presentation = presentNimbusPreparationFailure('网络不可用，请稍后重试。');

    expect(presentation.message, '网络不可用，请稍后重试。');
    expect(presentation.diagnosticCode, 'C-PLAN-01');
    expect(presentation.failureCode, 'PLAN_PREPARATION_FAILED');
    expect(presentation.stage, 'PLAN_PREPARATION');
  });

  test('issue report serializes only stable diagnostic metadata into the allowed field', () {
    const diagnostic = NimbusConnectionDiagnostic(
      code: 'I-PERM-01',
      failureCode: 'MISSING_SYSTEM_PERMISSION',
      stage: 'SYSTEM_PERMISSION',
      summary: 'safe diagnostics',
    );

    expect(
      buildNimbusIssueConnectionStatus(const ConnectionStatus.disconnected(), diagnostic),
      'DISCONNECTED; diagnostic=I-PERM-01; failure=MISSING_SYSTEM_PERMISSION; stage=SYSTEM_PERMISSION',
    );
  });
}
