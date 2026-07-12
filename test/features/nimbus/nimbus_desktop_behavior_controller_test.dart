import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_desktop_behavior_controller.dart';

void main() {
  test('auto connect retry uses bounded exponential backoff', () {
    expect(List.generate(8, (index) => nimbusAutoConnectRetryDelay(index).inMinutes), [1, 2, 4, 8, 16, 30, 30, 30]);
    expect(nimbusAutoConnectRetryDelay(-1), const Duration(minutes: 1));
  });
}
