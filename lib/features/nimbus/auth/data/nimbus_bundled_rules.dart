import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

final _logger = Loggy('YundoBundledRules');
final _safeRuleTag = RegExp(r'^[A-Za-z0-9_.!-]+$');

/// Builds a public-only package from the signed snapshot shipped with the app.
/// An account cache remains preferred because it also carries cloud rules.
Future<NimbusRulesPackage?> readNimbusBundledRulesPackage() async {
  try {
    final decoded = jsonDecode(await rootBundle.loadString('assets/rules/manifest.json'));
    if (decoded is! Map || decoded['items'] is! List) return null;

    final publicRules = <NimbusRulePackageItem>[];
    for (final rawItem in decoded['items'] as List) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final tag = item['tag'];
      final sourceUrl = item['sourceUrl'];
      final patternType = item['patternType'];
      final action = item['action'];
      if (tag is! String ||
          !_safeRuleTag.hasMatch(tag) ||
          sourceUrl is! String ||
          sourceUrl.isEmpty ||
          patternType is! String ||
          patternType.isEmpty ||
          action is! String ||
          action.isEmpty) {
        _logger.error('bundled rule manifest is missing semantics: $tag');
        return null;
      }
      publicRules.add(
        NimbusRulePackageItem(
          kind: 'rule_set',
          pattern: tag,
          patternType: patternType,
          action: action,
          sourceUrl: sourceUrl,
          format: 'binary',
          updateInterval: '1d',
        ),
      );
    }
    if (publicRules.isEmpty) return null;

    final sourceVersion = decoded['publicRulesSourceVersion'] as String?;
    if (sourceVersion == null || sourceVersion.isEmpty) return null;
    return NimbusRulesPackage(
      manifest: NimbusRulesManifest(
        publicRulesVersion: decoded['publicRulesVersion'] as String?,
        publicRulesSourceVersion: sourceVersion,
        publicRulesUpdatedAt: DateTime.tryParse(decoded['publicRulesUpdatedAt'] as String? ?? ''),
        // The connection plan can replace this with the account's version.
        userRulesVersion: 'sha256:bundled-empty-user-rules',
        configVersion: 'sing-box-rules-v3',
        requiresUpdate: false,
        publicRulesChanged: false,
        userRulesChanged: false,
        configChanged: false,
      ),
      userRules: const [],
      publicRules: publicRules,
    );
  } catch (error, stackTrace) {
    _logger.error('unable to read bundled public rule package: $error', error, stackTrace);
    return null;
  }
}

/// Returns the packaged rule-set paths that can be passed to Core as startup
/// fallbacks. Desktop builds use the signed App bundle; mobile builds copy
/// the asset to the app's writable working directory.
Future<Map<String, String>> ensureNimbusBundledRuleSetFiles({
  required Iterable<String> tags,
  required Directories directories,
}) async {
  final requestedTags = tags.where((tag) => _safeRuleTag.hasMatch(tag)).toSet();
  if (requestedTags.isEmpty) return const {};

  try {
    final manifest = jsonDecode(await rootBundle.loadString('assets/rules/manifest.json'));
    if (manifest is! Map || manifest['items'] is! List) return const {};

    final paths = <String, String>{};
    for (final item in manifest['items'] as List) {
      if (item is! Map) continue;
      final tag = item['tag'];
      final asset = item['asset'];
      if (tag is! String || !requestedTags.contains(tag) || asset is! String || !_isRuleAsset(asset, tag)) continue;

      final packagedPath = _packagedAssetPath(asset);
      if (packagedPath != null && await File(packagedPath).exists()) {
        paths[tag] = packagedPath;
        continue;
      }

      // macOS Helper validates fallbacks against the signed bundle. Never
      // silently replace a missing macOS bundle asset with a writable path.
      if (Platform.isMacOS) {
        _logger.error('bundled rule-set asset is missing: $asset');
        continue;
      }

      final bytes = await rootBundle.load(asset);
      final target = File(p.join(directories.workingDir.path, 'data', 'yundo-rules', '$tag.srs'));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
      paths[tag] = target.path;
    }
    return paths;
  } catch (error, stackTrace) {
    _logger.error('unable to prepare bundled rule-set fallbacks: $error', error, stackTrace);
    return const {};
  }
}

bool _isRuleAsset(String asset, String tag) => asset == 'assets/rules/$tag.srs';

String? _packagedAssetPath(String asset) {
  if (Platform.isMacOS) {
    return p.join(
      p.dirname(p.dirname(Platform.resolvedExecutable)),
      'Frameworks',
      'App.framework',
      'Resources',
      'flutter_assets',
      asset,
    );
  }
  if (Platform.isWindows || Platform.isLinux) {
    return p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', asset);
  }
  return null;
}
