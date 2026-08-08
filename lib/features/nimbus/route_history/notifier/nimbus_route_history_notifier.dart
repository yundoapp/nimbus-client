import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/route_history/model/nimbus_route_history.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_tunnel_config.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

final nimbusRouteHistoryProvider = NotifierProvider<NimbusRouteHistoryNotifier, NimbusRouteHistoryState>(
  NimbusRouteHistoryNotifier.new,
);

const bool nimbusExactRouteHistoryEnabled = bool.fromEnvironment('YUNDO_EXACT_ROUTE_HISTORY', defaultValue: true);
const int nimbusRouteHistorySnapshotIntervalMilliseconds = 1000;

class NimbusRouteHistoryState {
  const NimbusRouteHistoryState({this.entries = const [], this.isMonitoring = false});

  final List<NimbusRouteHistoryEntry> entries;
  final bool isMonitoring;

  int get activeCount => entries.where((entry) => entry.isActive).length;

  NimbusRouteHistoryState copyWith({List<NimbusRouteHistoryEntry>? entries, bool? isMonitoring}) {
    return NimbusRouteHistoryState(entries: entries ?? this.entries, isMonitoring: isMonitoring ?? this.isMonitoring);
  }
}

class NimbusRouteHistoryControllerConfig {
  const NimbusRouteHistoryControllerConfig({required this.webSocketUri, required this.secret});

  final Uri webSocketUri;
  final String secret;

  Map<String, dynamic>? get headers => secret.isEmpty ? null : {'Authorization': 'Bearer $secret'};

  NimbusRouteHistoryControllerConfig copyWithPort(int port) => NimbusRouteHistoryControllerConfig(
    webSocketUri: webSocketUri.replace(port: port),
    secret: secret,
  );
}

typedef NimbusRouteHistoryMonitoringController = ({NimbusRouteHistoryControllerConfig config, bool tunnelLayer});

/// Reads the authoritative traffic counters from the macOS tunnel Helper.
///
/// Direct traffic is handled by the privileged Helper, so the user Core's
/// stats stream cannot represent all traffic on macOS. This stream is kept
/// independent from route-history recording and can therefore be consumed by
/// the stats feature without changing the recording preference.
Stream<NimbusTunnelTrafficStats> watchNimbusMacOSTunnelTraffic(
  File controllerConfigFile, {
  required String appProcessName,
}) async* {
  const retryDelay = Duration(seconds: 1);
  while (true) {
    final controller = await loadNimbusRouteHistoryControllerConfig(controllerConfigFile);
    if (controller == null) {
      await Future<void>.delayed(retryDelay);
      continue;
    }

    final helperController = nimbusRouteHistoryMonitoringControllers(
      controller,
      isMacOS: true,
      appProcessName: appProcessName,
    ).single.config;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(helperController.webSocketUri.toString(), headers: helperController.headers);
      await for (final message in socket) {
        if (message is! String) continue;
        try {
          final decoded = jsonDecode(message);
          if (decoded is! Map) continue;
          final stats = parseNimbusTunnelTrafficStats(Map<String, dynamic>.from(decoded));
          if (stats != null) yield stats;
        } catch (_) {
          // Ignore malformed local snapshots and keep the stream alive.
        }
      }
    } catch (_) {
      // The Helper is expected to be unavailable while acceleration is stopped.
    } finally {
      await socket?.close();
    }
    await Future<void>.delayed(retryDelay);
  }
}

@visibleForTesting
List<NimbusRouteHistoryMonitoringController> nimbusRouteHistoryMonitoringControllers(
  NimbusRouteHistoryControllerConfig controller, {
  required bool isMacOS,
  required String appProcessName,
}) {
  if (!isMacOS) return [(config: controller, tunnelLayer: false)];

  // The privileged Helper owns the final direct/accelerated decision on
  // macOS. Reading the user Core as a second source duplicates every
  // accelerated request and can only expose an intermediate selector tag.
  return [(config: controller.copyWithPort(nimbusMacOSTunnelRouteHistoryPort(appProcessName)), tunnelLayer: true)];
}

@visibleForTesting
NimbusRouteHistoryControllerConfig? parseNimbusRouteHistoryControllerConfig(
  String content, {
  bool exactHistory = nimbusExactRouteHistoryEnabled,
}) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) return null;
    final experimental = decoded['experimental'];
    if (experimental is! Map) return null;
    final clashApi = experimental['clash_api'];
    if (clashApi is! Map) return null;
    final controller = clashApi['external_controller']?.toString().trim() ?? '';
    if (controller.isEmpty) return null;

    final sourceUri = Uri.tryParse(controller.contains('://') ? controller : 'http://$controller');
    if (sourceUri == null || !sourceUri.hasPort) return null;
    final host = sourceUri.host.toLowerCase();
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') return null;
    if (sourceUri.scheme != 'http' && sourceUri.scheme != 'https') return null;

    return NimbusRouteHistoryControllerConfig(
      webSocketUri: Uri(
        scheme: sourceUri.scheme == 'https' ? 'wss' : 'ws',
        host: sourceUri.host,
        port: sourceUri.port,
        path: '/connections',
        queryParameters: exactHistory
            ? const {'yundo_exact_history': '1', 'interval': '$nimbusRouteHistorySnapshotIntervalMilliseconds'}
            : null,
      ),
      secret: clashApi['secret']?.toString() ?? '',
    );
  } catch (_) {
    return null;
  }
}

Future<NimbusRouteHistoryControllerConfig?> loadNimbusRouteHistoryControllerConfig(File file) async {
  if (!await file.exists()) return null;
  return parseNimbusRouteHistoryControllerConfig(await file.readAsString());
}

class NimbusRouteHistoryNotifier extends Notifier<NimbusRouteHistoryState> {
  static const _retryDelay = Duration(seconds: 1);

  final _sockets = <WebSocket>{};
  List<Map<String, dynamic>> _coreSnapshot = const [];
  List<Map<String, dynamic>> _tunnelSnapshot = const [];
  bool _disposed = false;
  bool _started = false;
  bool _enabled = false;
  bool _connected = false;
  bool _recordingEnabled = false;
  late final File _controllerConfigFile;

  @override
  NimbusRouteHistoryState build() {
    final workingDirectory = ref.watch(appDirectoriesProvider).requireValue.workingDir;
    _controllerConfigFile = File(p.join(workingDirectory.path, 'data', 'current-config.json'));
    ref.listen(nimbusOwnedConnectionStatusProvider, (_, next) {
      _connected = next.valueOrNull is Connected;
      _syncMonitoring();
    }, fireImmediately: true);
    ref.listen(Preferences.nimbusRouteHistoryEnabled, (_, enabled) {
      _recordingEnabled = enabled;
      _syncMonitoring();
    }, fireImmediately: true);
    ref.onDispose(() {
      _disposed = true;
      for (final socket in _sockets.toList(growable: false)) {
        unawaited(socket.close());
      }
    });
    return const NimbusRouteHistoryState();
  }

  void clear() => state = state.copyWith(entries: const []);

  void _syncMonitoring() =>
      _setEnabled(shouldMonitorNimbusRouteHistory(isConnected: _connected, recordingEnabled: _recordingEnabled));

  void _setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      unawaited(_monitor());
      return;
    }
    for (final socket in _sockets.toList(growable: false)) {
      unawaited(socket.close());
    }
    state = state.copyWith(
      entries: completeNimbusRouteHistory(state.entries, completedAt: DateTime.now()),
      isMonitoring: false,
    );
  }

  Future<void> _monitor() async {
    if (_started) return;
    _started = true;
    try {
      while (!_disposed && _enabled) {
        final controllers = await _loadMonitoringControllers();
        if (controllers == null) {
          await Future<void>.delayed(_retryDelay);
          continue;
        }

        await Future.wait(
          controllers.map((source) => _monitorController(source.config, tunnelLayer: source.tunnelLayer)),
        );
        if (!_disposed && _enabled) await Future<void>.delayed(_retryDelay);
      }
    } finally {
      _started = false;
    }
  }

  Future<void> _monitorController(NimbusRouteHistoryControllerConfig controller, {required bool tunnelLayer}) async {
    while (!_disposed && _enabled) {
      WebSocket? socket;
      try {
        socket = await WebSocket.connect(controller.webSocketUri.toString(), headers: controller.headers);
        if (_disposed || !_enabled) {
          await socket.close();
          return;
        }
        _sockets.add(socket);
        _updateMonitoringState();
        await for (final message in socket) {
          if (_disposed || !_enabled) return;
          _handleMessage(message, tunnelLayer: tunnelLayer);
        }
      } catch (_) {
        // The local controller is expected to be unavailable while acceleration is stopped.
      } finally {
        if (socket != null) {
          _sockets.remove(socket);
          if (tunnelLayer) {
            _tunnelSnapshot = const [];
          } else {
            _coreSnapshot = const [];
          }
          _rebuildHistory();
        }
        _updateMonitoringState();
      }
      if (!_disposed && _enabled) await Future<void>.delayed(_retryDelay);
    }
  }

  Future<List<NimbusRouteHistoryMonitoringController>?> _loadMonitoringControllers() async {
    final controller = await loadNimbusRouteHistoryControllerConfig(_controllerConfigFile);
    if (controller == null) return null;
    return nimbusRouteHistoryMonitoringControllers(
      controller,
      isMacOS: PlatformUtils.isMacOS,
      appProcessName: p.basename(Platform.resolvedExecutable),
    );
  }

  void _handleMessage(Object? message, {required bool tunnelLayer}) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      if (tunnelLayer) {
        _tunnelSnapshot = extractNimbusMacOSTunnelConnections(
          payload,
          requireExactDecision: nimbusExactRouteHistoryEnabled,
        );
      } else {
        _coreSnapshot = extractNimbusRouteConnections(payload, requireExactDecision: nimbusExactRouteHistoryEnabled);
      }
      _rebuildHistory();
    } catch (_) {
      // Ignore one malformed local snapshot and keep monitoring subsequent updates.
    }
  }

  void _rebuildHistory() {
    state = state.copyWith(
      entries: mergeNimbusRouteHistory(
        previous: state.entries,
        snapshot: [..._coreSnapshot, ..._tunnelSnapshot],
        observedAt: DateTime.now(),
      ),
    );
  }

  void _updateMonitoringState() {
    state = state.copyWith(isMonitoring: _sockets.isNotEmpty);
  }
}

@visibleForTesting
bool shouldMonitorNimbusRouteHistory({required bool isConnected, required bool recordingEnabled}) =>
    isConnected && recordingEnabled;
