import 'package:dio/dio.dart';

const _redacted = '[REDACTED]';

final _authorizationPattern = RegExp(r'(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', caseSensitive: false);
final _namedSecretPattern = RegExp(
  r'''((?:access|refresh)[-_ ]?token|password|passwd|activation[-_ ]?code|private[-_ ]?key|secret)\s*[:=]\s*["']?[^\s,;"'}]+''',
  caseSensitive: false,
);
final _bearerPattern = RegExp(r'\bbearer\s+[A-Za-z0-9._~+/=-]{12,}', caseSensitive: false);
final _uuidPattern = RegExp(
  r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
  caseSensitive: false,
);
final _activationCodePattern = RegExp(r'\b[A-Z0-9]{4}(?:-[A-Z0-9]{4}){3}\b');
final _connectionConfigPattern = RegExp(r'\b(?:vless|vmess|trojan|ss|ssr|hysteria2?)://[^\s]+', caseSensitive: false);
final _macOSUserPathPattern = RegExp(r'/Users/[^/\s]+', caseSensitive: false);

const _allowedDiagnosticKeys = {
  'appVersion',
  'appName',
  'platform',
  'osVersion',
  'rulesVersion',
  'connectionStatus',
  'selectedLocation',
  'subscriptionStatus',
  'uplink',
  'downlink',
};

/// 在问题描述离开设备前移除常见凭据、连接配置和本机身份信息。
String sanitizeNimbusIssueReportText(String input) {
  var value = input;
  value = value.replaceAllMapped(_authorizationPattern, (match) => '${match.group(1)}$_redacted');
  value = value.replaceAllMapped(_namedSecretPattern, (match) => '${match.group(1)}=$_redacted');
  value = value.replaceAll(_bearerPattern, 'Bearer $_redacted');
  value = value.replaceAll(_uuidPattern, _redacted);
  value = value.replaceAll(_activationCodePattern, _redacted);
  value = value.replaceAll(_connectionConfigPattern, _redacted);
  value = value.replaceAll(_macOSUserPathPattern, '/Users/$_redacted');
  return value;
}

/// 问题上报诊断字段采用允许列表，避免未来调用方误传令牌或连接配置。
Map<String, Object?> sanitizeNimbusIssueDiagnostics(Map<String, Object?> diagnostics) {
  return {
    for (final entry in diagnostics.entries)
      if (_allowedDiagnosticKeys.contains(entry.key)) entry.key: _sanitizeDiagnosticValue(entry.value),
  };
}

bool shouldRetryLegacyIssueReport(Object error) {
  if (error is! DioException) return false;
  final data = error.response?.data;
  if (data is! Map || data['code'] != 'VALIDATION_FAILED') return false;
  final fields = data['fields'];
  return fields is List && fields.any((field) => field == 'category' || field == 'contact');
}

String buildLegacyIssueReportDescription({
  required String category,
  required String description,
  required String contact,
}) {
  final parts = <String>[
    '[$category]',
    if (description.trim().isNotEmpty) description.trim(),
    if (contact.trim().isNotEmpty) 'Contact: ${contact.trim()}',
  ];
  final value = parts.join('\n');
  return value.length <= 1000 ? value : value.substring(0, 1000);
}

Object? _sanitizeDiagnosticValue(Object? value) {
  if (value is String) return sanitizeNimbusIssueReportText(value);
  if (value is num || value is bool || value == null) return value;
  return null;
}
