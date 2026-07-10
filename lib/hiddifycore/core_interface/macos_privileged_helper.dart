import 'package:flutter/services.dart';

class MacOSPrivilegedHelper {
  const MacOSPrivilegedHelper({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yundo_macos_privileged_helper');

  final MethodChannel _channel;

  Future<void> startTunnel(String config) async {
    await _channel.invokeMethod<void>('startTunnel', {'config': config});
  }

  Future<void> stopTunnel() async {
    await _channel.invokeMethod<void>('stopTunnel');
  }

  Future<Map<Object?, Object?>> status() async {
    return await _channel.invokeMethod<Map<Object?, Object?>>('status') ?? const {};
  }

  Future<void> openSystemSettings() async {
    await _channel.invokeMethod<void>('openSystemSettings');
  }
}
