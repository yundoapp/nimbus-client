import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_port.dart';

void main() {
  test('uses an isolated desktop core port for the Yundo dev app', () {
    expect(resolveDesktopCorePort('/data/app.yundo.client.rebuild.dev'), yundoDevDesktopCorePort);
  });

  test('keeps the legacy core port for the formal app', () {
    expect(resolveDesktopCorePort('/data/app.yundo.client'), legacyDesktopCorePort);
  });
}
