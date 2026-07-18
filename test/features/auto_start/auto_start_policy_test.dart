import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';

void main() {
  test('Windows startup identities are isolated', () {
    expect(windowsStartupPackageName(isDebug: true), 'Yundo.YundoDev');
    expect(windowsStartupPackageName(isDebug: false), 'Yundo.Yundo');
  });

  test('auto start is enabled only during first-run initialization', () {
    expect(shouldEnableAutoStartByDefault(initialized: false, enabled: false), isTrue);
    expect(shouldEnableAutoStartByDefault(initialized: false, enabled: true), isFalse);
    expect(shouldEnableAutoStartByDefault(initialized: true, enabled: false), isFalse);
  });

  test('only Windows defaults window closing to background mode', () {
    expect(ActionsAtClosing.defaultForPlatform(isWindows: true), ActionsAtClosing.hide);
    expect(ActionsAtClosing.defaultForPlatform(isWindows: false), ActionsAtClosing.ask);
  });
}
