import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';

void main() {
  test('仅在用户态 core 和系统通道都就绪后报告加速已开启', () {
    expect(shouldReportNimbusConnected(transportReady: false, connection: const ConnectionStatus.connected()), isFalse);
    expect(shouldReportNimbusConnected(transportReady: true, connection: const ConnectionStatus.connecting()), isFalse);
    expect(shouldReportNimbusConnected(transportReady: true, connection: const ConnectionStatus.connected()), isTrue);
  });

  test('系统通道就绪前将用户态 core 的已连接状态展示为加速中', () {
    expect(
      shouldPresentNimbusAsConnecting(
        isPreparing: true,
        connectedReported: false,
        connection: const ConnectionStatus.connected(),
      ),
      isTrue,
    );
    expect(
      shouldPresentNimbusAsConnecting(
        isPreparing: true,
        connectedReported: false,
        connection: const ConnectionStatus.disconnected(),
      ),
      isTrue,
    );
    expect(
      shouldPresentNimbusAsConnecting(
        isPreparing: false,
        connectedReported: false,
        connection: const ConnectionStatus.connected(),
      ),
      isFalse,
    );
    expect(
      shouldPresentNimbusAsConnecting(
        isPreparing: true,
        connectedReported: true,
        connection: const ConnectionStatus.connected(),
      ),
      isFalse,
    );
  });

  test('断开清理完成前持续展示正在停止加速', () {
    expect(shouldPresentNimbusAsDisconnecting(isDisconnecting: true), isTrue);
    expect(shouldPresentNimbusAsDisconnecting(isDisconnecting: false), isFalse);
  });
}
