import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';

const nimbusDomainMaxLength = 253;
const nimbusPasswordMaxUtf8Bytes = 72;

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
