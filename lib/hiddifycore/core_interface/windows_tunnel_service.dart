import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/tunnelservice/tunnel.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/tunnelservice/tunnel_service.pbgrpc.dart';
import 'package:path/path.dart' as p;

class WindowsTunnelSettings {
  const WindowsTunnelSettings({
    required this.ipv6,
    required this.serverPort,
    required this.serverUsername,
    required this.serverPassword,
    required this.strictRoute,
    required this.endpointIndependentNat,
    required this.stack,
  });

  factory WindowsTunnelSettings.fromConfig(String config) {
    final source = jsonDecode(config);
    if (source is! Map<String, dynamic>) {
      throw const FormatException('tunnel config must be an object');
    }

    final inbounds = (source['inbounds'] as List?)?.whereType<Map>().map(Map<String, dynamic>.from).toList() ?? [];
    final tunInbounds = inbounds.where((item) => item['type'] == 'tun').toList();
    if (tunInbounds.length != 1) {
      throw const FormatException('tunnel config must contain exactly one tun inbound');
    }

    final outbounds = (source['outbounds'] as List?)?.whereType<Map>().map(Map<String, dynamic>.from).toList() ?? [];
    final socksOutbounds = outbounds.where((item) => item['type'] == 'socks').toList();
    if (socksOutbounds.length != 1) {
      throw const FormatException('tunnel config must contain exactly one socks outbound');
    }

    final tun = tunInbounds.single;
    final socks = socksOutbounds.single;
    final serverPort = socks['server_port'];
    if (serverPort is! int || serverPort < 1 || serverPort > 65535) {
      throw const FormatException('tunnel socks outbound has an invalid port');
    }

    final addresses = (tun['address'] as List?)?.whereType<String>() ?? const Iterable<String>.empty();
    return WindowsTunnelSettings(
      ipv6: addresses.any((address) => address.contains(':')),
      serverPort: serverPort,
      serverUsername: socks['username'] as String?,
      serverPassword: socks['password'] as String?,
      strictRoute: tun['strict_route'] == true,
      endpointIndependentNat: tun['endpoint_independent_nat'] == true,
      stack: (tun['stack'] as String?) ?? 'system',
    );
  }

  final bool ipv6;
  final int serverPort;
  final String? serverUsername;
  final String? serverPassword;
  final bool strictRoute;
  final bool endpointIndependentNat;
  final String stack;

  TunnelStartRequest toRequest() => TunnelStartRequest(
    ipv6: ipv6,
    serverPort: serverPort,
    serverUsername: serverUsername ?? '',
    serverPassword: serverPassword ?? '',
    strictRoute: strictRoute,
    endpointIndependentNat: endpointIndependentNat,
    stack: stack,
  );
}

class WindowsTunnelServicePermissionException implements Exception {
  const WindowsTunnelServicePermissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WindowsTunnelService {
  WindowsTunnelService({
    bool Function()? isWindows,
    Future<void> Function(TunnelStartRequest request)? requestStarter,
    Future<void> Function(String action)? controlRunner,
    Future<void> Function()? serviceWaiter,
    Future<bool> Function()? stopRequest,
  }) : _isWindows = isWindows ?? _platformIsWindows,
       _requestStarter = requestStarter,
       _controlRunner = controlRunner,
       _serviceWaiter = serviceWaiter,
       _stopRequestOverride = stopRequest;

  static const _port = 18020;
  static const _requestTimeout = Duration(seconds: 15);
  static const _serviceStartTimeout = Duration(seconds: 30);

  final bool Function() _isWindows;
  final Future<void> Function(TunnelStartRequest request)? _requestStarter;
  final Future<void> Function(String action)? _controlRunner;
  final Future<void> Function()? _serviceWaiter;
  final Future<bool> Function()? _stopRequestOverride;

  static bool _platformIsWindows() => Platform.isWindows;

  Future<void> start(String tunnelConfig) async {
    if (!_isWindows()) return;
    final request = WindowsTunnelSettings.fromConfig(tunnelConfig).toRequest();
    final startRequest = _requestStarter ?? _startRequest;

    try {
      await startRequest(request);
      return;
    } on GrpcError catch (error) {
      if (error.code != StatusCode.unavailable) rethrow;
    }

    await (_controlRunner ?? _runElevatedControl)('install');
    await (_serviceWaiter ?? _waitForService)();
    await startRequest(request);
  }

  Future<bool> stop() async {
    if (!_isWindows()) return false;
    return (_stopRequestOverride ?? _stopRequest)();
  }

  Future<bool> _stopRequest() async {
    final channel = _channel();
    try {
      await TunnelServiceClient(channel).stop(Empty()).timeout(_requestTimeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      await channel.shutdown();
    }
  }

  Future<bool> reset() async {
    if (!_isWindows()) return false;
    await stop();
    await (_controlRunner ?? _runElevatedControl)('uninstall');
    return true;
  }

  Future<void> _startRequest(TunnelStartRequest request) async {
    final channel = _channel();
    try {
      await TunnelServiceClient(channel).start(request).timeout(_requestTimeout);
    } finally {
      await channel.shutdown();
    }
  }

  Future<void> _waitForService() async {
    final deadline = DateTime.now().add(_serviceStartTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final channel = _channel();
      try {
        await TunnelServiceClient(channel).status(Empty()).timeout(const Duration(seconds: 2));
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } finally {
        await channel.shutdown();
      }
    }
    throw const WindowsTunnelServicePermissionException('acceleration service did not become ready');
  }

  Future<void> _runElevatedControl(String action) async {
    final executable = File(p.join(File(Platform.resolvedExecutable).parent.path, 'YundoService.exe'));
    if (!await executable.exists()) {
      throw const WindowsTunnelServicePermissionException('acceleration service executable is missing');
    }

    const command = r'''
$process = Start-Process -FilePath $env:YUNDO_SERVICE_EXECUTABLE -ArgumentList @('tunnel', $env:YUNDO_SERVICE_CONTROL) -Verb RunAs -WindowStyle Hidden -PassThru -Wait
exit $process.ExitCode
''';
    final result = await Process.run(
      'powershell.exe',
      const ['-NoProfile', '-NonInteractive', '-Command', command],
      environment: {
        ...Platform.environment,
        'YUNDO_SERVICE_EXECUTABLE': executable.path,
        'YUNDO_SERVICE_CONTROL': action,
      },
    );
    if (result.exitCode != 0) {
      throw WindowsTunnelServicePermissionException('acceleration service permission was not granted: $action');
    }
  }

  ClientChannel _channel() => ClientChannel(
    '127.0.0.1',
    port: _port,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
}
