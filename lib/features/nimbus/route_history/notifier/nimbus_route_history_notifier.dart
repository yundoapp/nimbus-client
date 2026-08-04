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

@visibleForTesting
NimbusRouteHistoryControllerConfig? parseNimbusRouteHistoryControllerConfig(String content) {
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

  WebSocket? _socket;
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
      unawaited(_socket?.close());
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
    unawaited(_socket?.close());
    state = state.copyWith(
      entries: completeNimbusRouteHistory(state.entries, completedAt: DateTime.now()),
      isMonitoring: false,
    );
  }

  Future<void> _monitor() async {
    if (_started) return;
    _started = true;
    while (!_disposed && _enabled) {
      try {
        final controller = await _loadMonitoringController();
        if (controller == null) throw const FormatException('local route history controller is unavailable');
        final socket = await WebSocket.connect(controller.webSocketUri.toString(), headers: controller.headers);
        if (_disposed) {
          await socket.close();
          return;
        }
        _socket = socket;
        state = state.copyWith(isMonitoring: true);
        await for (final message in socket) {
          if (_disposed) return;
          _handleMessage(message);
        }
      } catch (_) {
        // The local controller is expected to be unavailable while acceleration is stopped.
      } finally {
        _socket = null;
        if (!_disposed && _enabled) {
          state = state.copyWith(
            entries: completeNimbusRouteHistory(state.entries, completedAt: DateTime.now()),
            isMonitoring: false,
          );
        }
      }
      if (!_disposed && _enabled) await Future<void>.delayed(_retryDelay);
    }
    _started = false;
  }

  Future<NimbusRouteHistoryControllerConfig?> _loadMonitoringController() async {
    final controller = await loadNimbusRouteHistoryControllerConfig(_controllerConfigFile);
    if (controller == null || !PlatformUtils.isMacOS) return controller;
    return controller.copyWithPort(nimbusMacOSTunnelRouteHistoryPort(p.basename(Platform.resolvedExecutable)));
  }

  void _handleMessage(Object? message) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      state = state.copyWith(
        entries: mergeNimbusRouteHistory(
          previous: state.entries,
          snapshot: extractNimbusRouteConnections(Map<String, dynamic>.from(decoded)),
          observedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Ignore one malformed local snapshot and keep monitoring subsequent updates.
    }
  }
}

@visibleForTesting
bool shouldMonitorNimbusRouteHistory({required bool isConnected, required bool recordingEnabled}) =>
    isConnected && recordingEnabled;
