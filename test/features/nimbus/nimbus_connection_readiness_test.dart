import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
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

  test('准备阶段收到明确断开失败时立即结束加速中状态', () {
    expect(
      shouldFailNimbusPreparingDisconnected(
        isPreparing: true,
        connectedReported: false,
        connection: const ConnectionStatus.disconnected(ConnectionFailure.missingVpnPermission()),
      ),
      isTrue,
    );
    expect(
      shouldFailNimbusPreparingDisconnected(
        isPreparing: true,
        connectedReported: false,
        connection: const ConnectionStatus.disconnected(),
      ),
      isFalse,
    );
    expect(
      shouldFailNimbusPreparingDisconnected(
        isPreparing: true,
        connectedReported: true,
        connection: const ConnectionStatus.disconnected(ConnectionFailure.missingVpnPermission()),
      ),
      isFalse,
    );
  });

  test('失败提示优先于底层加速中状态展示为未加速', () {
    expect(
      shouldPresentNimbusFailureAsDisconnected(
        errorMessage: '加速失败，请稍后重试。',
        connectedReported: false,
        connection: const ConnectionStatus.connecting(),
      ),
      isTrue,
    );
    expect(
      shouldPresentNimbusFailureAsDisconnected(
        errorMessage: null,
        connectedReported: false,
        connection: const ConnectionStatus.connecting(),
      ),
      isFalse,
    );
    expect(
      shouldPresentNimbusFailureAsDisconnected(
        errorMessage: '加速失败，请稍后重试。',
        connectedReported: true,
        connection: const ConnectionStatus.connecting(),
      ),
      isFalse,
    );
    expect(
      shouldPresentNimbusFailureAsDisconnected(
        errorMessage: '加速失败，请稍后重试。',
        connectedReported: false,
        connection: const ConnectionStatus.connected(),
      ),
      isFalse,
    );
  });
}
