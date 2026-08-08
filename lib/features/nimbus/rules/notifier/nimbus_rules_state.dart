import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_bundled_rules.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// The last validated package that will be used for the next acceleration.
///
/// The package is deliberately read from the same repository cache used by
/// connection preparation, so the diagnostics page cannot drift from the
/// connection path.
final nimbusCachedRulesPackageProvider = Provider<NimbusRulesPackage?>((ref) {
  final userId = ref.watch(nimbusAuthControllerProvider.select((state) => state.session?.user.id));
  if (userId == null || userId.isEmpty) return null;
  return ref.read(nimbusAuthRepositoryProvider).readRulesPackage(userId);
});

/// Refreshes the package shown by the rules center while retaining the last
/// validated package when the account API is temporarily unavailable.
///
/// The connection path remains the authority for starting acceleration. This
/// provider only keeps the rules page aligned with that same package and
/// prevents a route-preferences request failure from looking like zero rules.
final nimbusRulesPackageProvider = FutureProvider.autoDispose<NimbusRulesPackage?>((ref) async {
  final authState = ref.watch(nimbusAuthControllerProvider);
  if (authState.isRestoring) return null;

  final session = authState.session;
  if (session == null) return null;

  final repository = ref.read(nimbusAuthRepositoryProvider);
  final bundled = await readNimbusBundledRulesPackage();
  final cached = repository.readRulesPackage(session.user.id);
  try {
    var package = await repository.fetchRulesPackage(session);
    if (bundled != null) package = package.withFallbackPublicRulesMetadata(bundled);
    if (package.manifest.configVersion != nimbusRulesConfigVersion) {
      throw FormatException('unsupported rules config version: ${package.manifest.configVersion}');
    }
    await repository.saveRulesPackage(session.user.id, package);
    return repository.readRulesPackage(session.user.id) ?? package;
  } catch (_) {
    if (cached != null) return bundled == null ? cached : cached.withFallbackPublicRulesMetadata(bundled);
    return bundled;
  }
});

/// Reads only the effective Core route section from the existing diagnostic
/// snapshot. Node credentials and the rest of the runtime configuration stay
/// out of the UI.
final nimbusCurrentRuntimeRulesProvider = Provider<Map<String, dynamic>?>((ref) {
  ref.watch(nimbusManagedRouteOptionsProvider);
  final directories = ref.watch(appDirectoriesProvider).valueOrNull;
  if (directories == null) return null;
  final file = File(p.join(directories.workingDir.path, 'data', 'current-config.json'));
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map || decoded['route'] is! Map) return null;
    final route = Map<String, dynamic>.from(decoded['route'] as Map);
    return {'rules': _mapList(route['rules']), 'rule_set': _mapList(route['rule_set'])};
  } catch (_) {
    return null;
  }
});

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
}
