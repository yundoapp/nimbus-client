import 'dart:io';

// flutter_test is provided by the Flutter test runner in this fork.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS branding', () {
    test('uses the canonical Yundo icon without legacy icon sources', () {
      final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final launchScreen = File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
      final bundledIcon = File('assets/images/app_icon.png').readAsBytesSync();
      final iosIcon = File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-1024.png').readAsBytesSync();
      final launchLogo = File('ios/Runner/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png').readAsBytesSync();

      expect(project, isNot(contains('AppIcon.icon')));
      expect(launchScreen, isNot(contains('LaunchImage')));
      expect(launchScreen, contains('LaunchBackground'));
      expect(launchScreen, contains('LaunchLogo'));
      expect(iosIcon, orderedEquals(bundledIcon));
      expect(launchLogo, orderedEquals(bundledIcon));
      expect(File('ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json').existsSync(), isFalse);
      expect(File('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png').existsSync(), isFalse);
    });

    test('generates localized production and development display names', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final debugConfig = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
      final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final localizationScript = File('scripts/localize_ios_display_name.sh').readAsStringSync();

      expect(infoPlist, contains('zh-Hans'));
      expect(infoPlist, contains('zh-Hant'));
      expect(debugConfig, contains('BASE_BUNDLE_IDENTIFIER=app.yundo.client.rebuild.dev'));
      expect(debugConfig, contains('APP_DISPLAY_NAME=Yundo Dev'));
      expect(project, contains('Localize Yundo Display Name'));
      expect(localizationScript, contains('云渡开发版'));
      expect(localizationScript, contains('雲渡開發版'));
      expect(localizationScript, contains('云渡'));
      expect(localizationScript, contains('雲渡'));
    });

    test('keeps iOS portrait-only and requests only the Packet Tunnel capability', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final appEntitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
      final tunnelEntitlements = File(
        'ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements',
      ).readAsStringSync();

      expect(infoPlist, contains('UIInterfaceOrientationPortrait'));
      expect(infoPlist, isNot(contains('UIInterfaceOrientationLandscape')));
      for (final entitlements in [appEntitlements, tunnelEntitlements]) {
        expect(entitlements, contains('packet-tunnel-provider'));
        expect(entitlements, isNot(contains('app-proxy-provider')));
        expect(entitlements, isNot(contains('dns-proxy')));
        expect(entitlements, isNot(contains('content-filter-provider')));
      }
    });
  });
}
