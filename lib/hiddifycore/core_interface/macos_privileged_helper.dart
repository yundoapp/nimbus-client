import 'package:flutter/services.dart';

class MacOSConnectionConflict {
  const MacOSConnectionConflict({
    required this.hasConflict,
    required this.systemProxyEnabled,
    required this.tunneledRouteCount,
    required this.yundoRoutedCount,
    required this.routeCheckFailures,
  });

  const MacOSConnectionConflict.none()
    : hasConflict = false,
      systemProxyEnabled = false,
      tunneledRouteCount = 0,
      yundoRoutedCount = 0,
      routeCheckFailures = 0;

  factory MacOSConnectionConflict.fromMap(Map<Object?, Object?> map) {
    return MacOSConnectionConflict(
      hasConflict: map['hasConflict'] == true,
      systemProxyEnabled: map['systemProxyEnabled'] == true,
      tunneledRouteCount: map['tunneledRouteCount'] is int ? map['tunneledRouteCount']! as int : 0,
      yundoRoutedCount: map['yundoRoutedCount'] is int ? map['yundoRoutedCount']! as int : 0,
      routeCheckFailures: map['routeCheckFailures'] is int ? map['routeCheckFailures']! as int : 0,
    );
  }

  final bool hasConflict;
  final bool systemProxyEnabled;
  final int tunneledRouteCount;
  final int yundoRoutedCount;
  final int routeCheckFailures;
}

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

  Future<MacOSConnectionConflict> connectionConflict() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('connectionConflict') ?? const {};
    return MacOSConnectionConflict.fromMap(result);
  }

  Future<void> openSystemSettings() async {
    await _channel.invokeMethod<void>('openSystemSettings');
  }
}
