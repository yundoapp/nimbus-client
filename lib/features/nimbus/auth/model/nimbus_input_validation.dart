import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';

const nimbusDomainMaxLength = 253;
const nimbusPasswordMaxUtf8Bytes = 72;
const nimbusRuleTargetTypes = <String>['domain', 'ip', 'cidr'];

bool isNimbusPasswordWithinByteLimit(String value) => utf8.encode(value).length <= nimbusPasswordMaxUtf8Bytes;

String? normalizeNimbusDomain(String input) {
  final domain = input.trim().toLowerCase();
  if (domain.isEmpty || domain.length > nimbusDomainMaxLength) return null;
  if (domain.contains('://') || domain.contains('/') || domain.contains(':') || domain.contains('*')) return null;

  final labels = domain.split('.');
  if (labels.length < 2 || labels.any((label) => !_isValidDomainLabel(label))) return null;

  final topLevelDomain = labels.last;
  if (topLevelDomain.length < 2 || !RegExp('[a-z]').hasMatch(topLevelDomain)) return null;
  return domain;
}

String? normalizeNimbusRuleTarget(String input, String targetType) {
  final value = input.trim().toLowerCase();
  switch (targetType) {
    case 'domain':
      return normalizeNimbusDomain(value);
    case 'ip':
      final address = InternetAddress.tryParse(value);
      return address?.address;
    case 'cidr':
      final parts = value.split('/');
      if (parts.length != 2) return null;
      final address = InternetAddress.tryParse(parts[0]);
      final prefix = int.tryParse(parts[1]);
      if (address == null || prefix == null) return null;
      final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
      if (prefix < 0 || prefix > maxPrefix) return null;
      return '${address.address}/$prefix';
    default:
      return null;
  }
}

String? registrableNimbusDomain(String input) {
  final domain = normalizeNimbusDomain(input);
  if (domain == null) return null;
  final parsed = DomainUtils.parseDomain(domain);
  if (parsed == null) return null;
  return normalizeNimbusDomain(parsed.toString());
}

bool _isValidDomainLabel(String label) {
  if (label.isEmpty || label.length > 63 || label.startsWith('-') || label.endsWith('-')) return false;
  return RegExp(r'^[a-z0-9-]+$').hasMatch(label);
}
