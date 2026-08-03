import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS 应用名称提供简体、繁体和开发版本地化', () {
    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    final project = File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final localizationScript = File('scripts/localize_macos_dev_display_name.sh').readAsStringSync();

    expect(infoPlist, contains('<key>CFBundleDisplayName</key>'));
    expect(infoPlist, contains('<key>LSHasLocalizedDisplayName</key>'));
    expect(project, contains('InfoPlist.strings in Resources'));
    expect(project, contains('Localize Dev Display Name'));
    expect(File('scripts/build_install_run_macos_dev.sh').readAsStringSync(), contains('lsregister'));
    expect(localizationScript, contains('云渡开发版'));
    expect(localizationScript, contains('雲渡開發版'));
    expect(File('lib/features/app/widget/app.dart').readAsStringSync(), contains('setApplicationBranding'));
    expect(File('macos/Runner/MainFlutterWindow.swift').readAsStringSync(), contains('processName = displayName'));

    expect(File('macos/Runner/zh-Hans.lproj/InfoPlist.strings').readAsStringSync(), contains('云渡'));
    expect(File('macos/Runner/zh-Hant.lproj/InfoPlist.strings').readAsStringSync(), contains('雲渡'));
  });

  test('macOS 使用完整云渡 AppIcon 资源而不是裁切的 Icon Composer 图层', () {
    final iconDirectory = Directory('macos/Runner/Assets.xcassets/AppIcon.appiconset');

    expect(iconDirectory.existsSync(), isTrue);
    expect(File('${iconDirectory.path}/icon_512x512.png').lengthSync(), greaterThan(1000));
    expect(Directory('macos/Runner/AppIcon.icon').existsSync(), isFalse);
    expect(
      File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      isNot(contains('AppIcon.icon in Resources')),
    );
  });
}
