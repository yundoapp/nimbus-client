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
    final exe = File(
      'windows/packaging/exe/make_config.yaml',
    ).readAsStringSync();
    final msix = File(
      'windows/packaging/msix/make_config.yaml',
    ).readAsStringSync();
    final packaging = File('scripts/package_windows.ps1').readAsStringSync();

    expect(exe, contains('display_name: Yundo'));
    expect(
      exe,
      contains('publisher_url: https://github.com/yundoapp/nimbus-client'),
    );
    expect(msix, contains('identity_name: Yundo.Yundo'));
    expect(msix, contains('msix_version: 1.0.0.10001'));
    expect(msix, contains('protocol_activation: yundo'));
    expect(packaging, contains('Yundo-Windows-Portable-x64.zip'));
  });

  test(
    'Windows acceptance installer is opt-in and never uses release publishing',
    () {
      final ci = File('.github/workflows/ci.yml').readAsStringSync();
      final build = File('.github/workflows/build.yml').readAsStringSync();

      expect(ci, contains('ci:windows-acceptance'));
      expect(build, contains('windows-acceptance-artifact'));
      expect(build, contains('Package Windows acceptance installer'));
      expect(build, contains('actions/upload-artifact@v6'));
      expect(build, contains('retention-days: 3'));
    },
  );

  test('mobile native projects only declare portrait orientation', () {
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    final android = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(ios, contains('UIInterfaceOrientationPortrait'));
    expect(ios, isNot(contains('UIInterfaceOrientationLandscape')));
    expect(android, contains('android:screenOrientation="portrait"'));
  });
}
