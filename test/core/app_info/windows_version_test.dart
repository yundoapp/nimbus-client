import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/windows_version.dart';

void main() {
  test('recognizes Windows 11 from build even when registry product name says Windows 10', () {
    final values = parseWindowsCurrentVersionRegistry(r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion
    ProductName    REG_SZ    Windows 10 Pro
    DisplayVersion    REG_SZ    25H2
    CurrentBuildNumber    REG_SZ    26200
    UBR    REG_DWORD    0x22ab
''');

    expect(formatWindowsVersion(values, fallback: 'fallback'), 'Windows 11 Pro 25H2 (Build 26200.8875)');
  });

  test('keeps Windows 10 for pre-Windows 11 builds', () {
    expect(
      formatWindowsVersion(const {
        'ProductName': 'Windows 10 Enterprise',
        'DisplayVersion': '22H2',
        'CurrentBuild': '19045',
      }, fallback: 'fallback'),
      'Windows 10 Enterprise 22H2 (Build 19045)',
    );
  });

  test('uses fallback when the registry build is unavailable', () {
    expect(formatWindowsVersion(const {'ProductName': 'Windows 10 Pro'}, fallback: 'raw'), 'raw');
  });
}
