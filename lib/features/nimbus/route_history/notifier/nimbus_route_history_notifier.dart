import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/route_history/model/nimbus_route_history.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

class NimbusRouteHistoryNotifier extends Notifier<NimbusRouteHistoryState> {
  static const _retryDelay = Duration(seconds: 1);

  WebSocket? _socket;
  bool _disposed = false;
  bool _started = false;
  bool _enabled = false;
  bool _connected = false;
  bool _recordingEnabled = false;

  @override
  NimbusRouteHistoryState build() {
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
        final socket = await WebSocket.connect(
          'ws://$nimbusRouteDiagnosticsController/connections',
          headers: {'Authorization': 'Bearer $nimbusRouteDiagnosticsSecret'},
        );
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
