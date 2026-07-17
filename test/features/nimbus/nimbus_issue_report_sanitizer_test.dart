import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_issue_report_sanitizer.dart';

void main() {
  test('问题描述在提交前移除常见敏感信息', () {
    final sanitized = sanitizeNimbusIssueReportText(
      'password=TopSecret! accessToken:abc.def.ghi.0123456789 '
      'Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature '
      '设备 550e8400-e29b-41d4-a716-446655440000 '
      '激活 ABCD-EFGH-JKMP-QRST '
      '配置 vless://private@example.com:443?security=reality '
      '日志 /Users/alice/Library/Logs/yundo.log',
    );

    expect(sanitized, isNot(contains('TopSecret')));
    expect(sanitized, isNot(contains('abc.def')));
    expect(sanitized, isNot(contains('eyJhbGci')));
    expect(sanitized, isNot(contains('550e8400')));
    expect(sanitized, isNot(contains('ABCD-EFGH')));
    expect(sanitized, isNot(contains('vless://')));
    expect(sanitized, isNot(contains('/Users/alice')));
  });

  test('诊断信息仅保留服务端契约允许的字段', () {
    final diagnostics = sanitizeNimbusIssueDiagnostics({
      'platform': 'ios',
      'appVersion': '1.0.0+10000',
      'connectionStatus': 'CONNECTED',
      'refreshToken': 'secret-refresh-token',
      'nodeConfig': 'vless://private.example',
      'uplink': 1024,
    });

    expect(diagnostics, containsPair('platform', 'ios'));
    expect(diagnostics, containsPair('uplink', 1024));
    expect(diagnostics, isNot(contains('refreshToken')));
    expect(diagnostics, isNot(contains('nodeConfig')));
  });
}
