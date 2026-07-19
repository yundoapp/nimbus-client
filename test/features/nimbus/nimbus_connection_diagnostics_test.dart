import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/hiddifycore/core_interface/windows_tunnel_service.dart';

void main() {
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
      isWindows: true,
    );

    expect(presentation.message, contains('重启 Windows'));
    expect(presentation.diagnosticCode, 'W-SVC-02');
    expect(presentation.failureCode, 'WINDOWS_SERVICE_UNAVAILABLE');
    expect(presentation.stage, 'SERVICE_START');
  });

  test('unknown start failures still provide a diagnostic code', () {
    final presentation = presentNimbusConnectionFailure(
      const ConnectionFailure.unexpected('unknown'),
      translations,
      isWindows: true,
    );

    expect(presentation.message, contains('复制诊断信息'));
    expect(presentation.diagnosticCode, 'C-START-01');
    expect(presentation.failureCode, 'CLIENT_START_FAILED');
  });
}
