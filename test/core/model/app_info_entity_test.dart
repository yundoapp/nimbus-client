import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';

void main() {
  group('version presentation', () {
    test('app version includes build number', () {
      const production = AppInfoEntity(
        name: 'Yundo',
        version: '4.1.2',
        buildNumber: '202608070',
        release: Release.general,
        operatingSystem: 'macos',
        operatingSystemVersion: '15.0',
        environment: Environment.prod,
      );
      const development = AppInfoEntity(
        name: 'Yundo Dev',
        version: '4.1.2',
        buildNumber: '202608070',
        release: Release.general,
        operatingSystem: 'macos',
        operatingSystemVersion: '15.0',
        environment: Environment.dev,
      );

      expect(production.presentVersion, '4.1.2+202608070');
      expect(development.presentVersion, '4.1.2+202608070 dev');
      expect(development.format(), contains('v4.1.2+202608070'));
    });

    test('remote version includes build number when available', () {
      final remote = RemoteVersionEntity(
        version: '4.1.3',
        buildNumber: '202608071',
        releaseTag: 'v4.1.3+202608071.dev',
        preRelease: true,
        url: 'https://example.invalid/release',
        publishedAt: DateTime.utc(2026, 8, 3),
        flavor: Environment.dev,
      );

      expect(remote.presentVersion, '4.1.3+202608071 dev');
    });

    test('remote version does not append an empty build number', () {
      final remote = RemoteVersionEntity(
        version: '4.1.3',
        buildNumber: '',
        releaseTag: 'v4.1.3',
        preRelease: false,
        url: 'https://example.invalid/release',
        publishedAt: DateTime.utc(2026, 8, 3),
        flavor: Environment.prod,
      );

      expect(remote.presentVersion, '4.1.3');
    });
  });
}
