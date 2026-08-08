import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// Reads the rule-set timestamps reported by the local Core API.
///
/// The Core owns remote SRS download, cache, validation, and refresh. This
/// provider only observes the already loaded state and never triggers an
/// update or changes the running configuration.
final nimbusCoreRuleSetStatusProvider = FutureProvider.autoDispose<Map<String, DateTime?>>((ref) {
  final directories = ref.watch(appDirectoriesProvider).valueOrNull;
  if (directories == null) return const {};

  final configFile = File(p.join(directories.workingDir.path, 'data', 'current-config.json'));
  return loadNimbusCoreRuleSetStatus(configFile);
});

Future<Map<String, DateTime?>> loadNimbusCoreRuleSetStatus(File configFile) async {
  if (!await configFile.exists()) return const {};

  try {
    final decoded = jsonDecode(await configFile.readAsString());
    if (decoded is! Map) return const {};
    final experimental = decoded['experimental'];
    if (experimental is! Map) return const {};
    final clashApi = experimental['clash_api'];
    if (clashApi is! Map) return const {};

    final controller = clashApi['external_controller']?.toString().trim() ?? '';
    if (controller.isEmpty) return const {};
    final sourceUri = Uri.tryParse(controller.contains('://') ? controller : 'http://$controller');
    if (sourceUri == null || !sourceUri.hasPort || !_isLocalController(sourceUri)) return const {};
    if (sourceUri.scheme != 'http' && sourceUri.scheme != 'https') return const {};

    final requestUri = sourceUri.replace(path: '/providers/rules', queryParameters: const {});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(requestUri).timeout(const Duration(seconds: 2));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final secret = clashApi['secret']?.toString() ?? '';
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode != HttpStatus.ok) return const {};
      final body = await response.transform(utf8.decoder).join();
      return parseNimbusCoreRuleSetStatusResponse(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    return const {};
  }
}

bool _isLocalController(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == '127.0.0.1' || host == 'localhost' || host == '::1';
}

Map<String, DateTime?> parseNimbusCoreRuleSetStatusResponse(Object? raw) {
  if (raw is! Map || raw['providers'] is! List) return const {};

  final result = <String, DateTime?>{};
  for (final item in raw['providers'] as List) {
    if (item is! Map) continue;
    final name = item['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final timestamp = item['updated_at']?.toString().trim();
    result[name] = timestamp == null || timestamp.isEmpty ? null : DateTime.tryParse(timestamp);
  }
  return result;
}
