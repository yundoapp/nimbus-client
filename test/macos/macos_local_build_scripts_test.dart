import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final devScript = File('scripts/build_install_run_macos_dev.sh').readAsStringSync();
  final prodScript = File('scripts/build_install_macos_local_prod.sh').readAsStringSync();

  test('开发版验收会在启动开发版前同步构建安装正式版', () {
    final prodInstallIndex = devScript.indexOf('build_install_macos_local_prod.sh');
    final devLaunchIndex = devScript.indexOf(r'open "$installed_app"');

    expect(prodInstallIndex, greaterThanOrEqualTo(0));
    expect(devLaunchIndex, greaterThan(prodInstallIndex));
  });

  test('本机正式版使用生产入口并固定覆盖 Applications', () {
    expect(prodScript, contains('--target=lib/main_prod.dart'));
    expect(prodScript, contains('https://api.yundo.app/api/v1'));
    expect(prodScript, contains('/Applications/Yundo.app'));
    expect(prodScript, contains('app.yundo.client'));
  });

  test('正式版失败时恢复备份且安装后不启动', () {
    expect(prodScript, contains('trap cleanup EXIT'));
    expect(prodScript, contains('正式版安装失败，正在恢复原有'));
    expect(prodScript, isNot(contains('\nopen ')));
    expect(prodScript, contains('正式版覆盖安装后意外启动'));
  });
}
