import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner uses isolated Yundo identities', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final resource = File('windows/runner/Runner.rc').readAsStringSync();
    final window = File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(cmake, contains('set(BINARY_NAME "Yundo")'));
    expect(cmake, contains('RENAME YundoService.exe'));
    expect(main, contains('L"Yundo Dev"'));
    expect(main, contains('L"Yundo"'));
    expect(main, contains('L"YundoDevMutex"'));
    expect(main, contains('L"YundoMutex"'));
    expect(window, contains('L"YUNDO_DEV_FLUTTER_RUNNER_WIN32_WINDOW"'));
    expect(window, contains('L"YUNDO_FLUTTER_RUNNER_WIN32_WINDOW"'));
    expect(window, contains('FindWindow(kWindowClassName, nullptr)'));
    expect(resource, contains('#define YUNDO_PRODUCT_NAME "Yundo Dev"'));
    expect(resource, contains('#define YUNDO_PRODUCT_NAME "Yundo"'));
    expect(resource, contains('VALUE "CompanyName", "Yundo"'));
  });

  test('Windows release packaging uses the Yundo public identity', () {
    final exe = File('windows/packaging/exe/make_config.yaml').readAsStringSync();
    final msix = File('windows/packaging/msix/make_config.yaml').readAsStringSync();
    final inno = File('windows/packaging/exe/inno_setup.sas').readAsStringSync();
    final packaging = File('scripts/package_windows.ps1').readAsStringSync();
    final makefile = File('Makefile').readAsStringSync();

    final icon = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final iconImageCount = icon[4] | (icon[5] << 8);

    expect(exe, contains('display_name: Yundo'));
    expect(exe, contains('  - zh'));
    expect(exe, contains('publisher_url: https://github.com/yundoapp/nimbus-client'));
    expect(msix, contains('identity_name: Yundo.Yundo'));
    expect(msix, contains('msix_version: 1.0.0.10002'));
    expect(msix, contains('protocol_activation: yundo'));
    expect(inno, contains('AppName={cm:YundoAppName}'));
    expect(inno, contains('chinesesimplified.YundoAppName=云渡'));
    expect(inno, contains(r'Name: "{autodesktop}\\{cm:YundoAppName}"'));
    expect(inno, contains(r'Name: "{autodesktop}\\Yundo.lnk"'));
    expect(inno, contains(r'Name: "{autodesktop}\\云渡.lnk"'));
    expect(inno, contains('ArchitecturesAllowed=x64compatible'));
    expect(inno, contains('ArchitecturesInstallIn64BitMode=x64compatible'));
    expect(icon.take(4), orderedEquals([0, 0, 1, 0]));
    expect(iconImageCount, greaterThan(1));
    expect(makefile, contains('NIMBUS_API_BASE_URL?=https://api.yundo.app/api/v1'));
    expect(makefile, contains(r'--build-dart-define=NIMBUS_API_BASE_URL=$(NIMBUS_API_BASE_URL)'));
    expect(packaging, contains('Yundo-Windows-Portable-x64.zip'));
  });

  test('Windows acceptance installer is opt-in and never uses release publishing', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final build = File('.github/workflows/build.yml').readAsStringSync();

    expect(ci, contains('ci:windows-acceptance'));
    expect(build, contains('windows-acceptance-artifact'));
    expect(build, contains('Package Windows acceptance installer'));
    expect(build, contains('--dart-define=NIMBUS_API_BASE_URL=https://api.yundo.app/api/v1'));
    expect(build, contains('--build-dart-define=NIMBUS_API_BASE_URL=https://api.yundo.app/api/v1'));
    expect(build, contains('actions/upload-artifact@v6'));
    expect(build, contains('retention-days: 3'));
  });

  test('mobile native projects only declare portrait orientation', () {
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    final android = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(ios, contains('UIInterfaceOrientationPortrait'));
    expect(ios, isNot(contains('UIInterfaceOrientationLandscape')));
    expect(android, contains('android:screenOrientation="portrait"'));
  });
}
