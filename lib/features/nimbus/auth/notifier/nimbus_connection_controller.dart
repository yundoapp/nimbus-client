import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_privileged_helper.dart';
import 'package:hiddify/hiddifycore/core_interface/windows_tunnel_service.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _managedProfileId = 'nimbus-managed-profile';
const _managedProfileName = 'Yundo';
const _stateSentinel = Object();

final nimbusConnectionControllerProvider = NotifierProvider<NimbusConnectionController, NimbusConnectionState>(
  NimbusConnectionController.new,
);

bool shouldReapplyNimbusConnection({
  required ConnectionStatus? connection,
  required bool userRulesOnly,
  required NimbusProxyMode proxyMode,
  required bool customWebsiteAccessEnabled,
}) {
  if (connection is! Connected) return false;
  if (!userRulesOnly) return true;
  return proxyMode == NimbusProxyMode.auto && customWebsiteAccessEnabled;
}

bool shouldReportNimbusConnected({required bool transportReady, required ConnectionStatus? connection}) {
  return transportReady && connection is Connected;
}

bool shouldPresentNimbusAsConnecting({
  required bool isPreparing,
  required bool connectedReported,
  required ConnectionStatus? connection,
}) {
  return isPreparing && !connectedReported && connection is! Disconnecting;
}

bool shouldPresentNimbusAsDisconnecting({required bool isDisconnecting}) => isDisconnecting;

bool shouldPresentNimbusFailureAsDisconnected({
  required String? errorMessage,
  required bool connectedReported,
  required ConnectionStatus? connection,
}) {
  if (errorMessage == null || connectedReported) return false;
  return connection is! Connected && connection is! Disconnecting;
}

bool shouldFailNimbusPreparingDisconnected({
  required bool isPreparing,
  required bool connectedReported,
  required ConnectionStatus connection,
}) {
  if (!isPreparing || connectedReported) return false;
  return connection is Disconnected && connection.connectionFailure != null;
}

class NimbusConnectionState {
  const NimbusConnectionState({
    this.isPreparing = false,
    this.isDisconnecting = false,
    this.plan,
    this.traffic,
    this.errorMessage,
    this.diagnostic,
    this.connectedReported = false,
    this.lastHeartbeatAt,
  });

  final bool isPreparing;
  final bool isDisconnecting;
  final NimbusConnectPlan? plan;
  final NimbusConnectTraffic? traffic;
  final String? errorMessage;
  final NimbusConnectionDiagnostic? diagnostic;
  final bool connectedReported;
  final DateTime? lastHeartbeatAt;

  bool get hasPlan => plan != null;

  NimbusConnectionState copyWith({
    bool? isPreparing,
    bool? isDisconnecting,
    Object? plan = _stateSentinel,
    Object? traffic = _stateSentinel,
    Object? errorMessage = _stateSentinel,
    Object? diagnostic = _stateSentinel,
    bool? connectedReported,
    Object? lastHeartbeatAt = _stateSentinel,
  }) {
    return NimbusConnectionState(
      isPreparing: isPreparing ?? this.isPreparing,
      isDisconnecting: isDisconnecting ?? this.isDisconnecting,
      plan: identical(plan, _stateSentinel) ? this.plan : plan as NimbusConnectPlan?,
      traffic: identical(traffic, _stateSentinel) ? this.traffic : traffic as NimbusConnectTraffic?,
      errorMessage: identical(errorMessage, _stateSentinel) ? this.errorMessage : errorMessage as String?,
      diagnostic: identical(diagnostic, _stateSentinel) ? this.diagnostic : diagnostic as NimbusConnectionDiagnostic?,
      connectedReported: connectedReported ?? this.connectedReported,
      lastHeartbeatAt: identical(lastHeartbeatAt, _stateSentinel) ? this.lastHeartbeatAt : lastHeartbeatAt as DateTime?,
    );
  }
}

class NimbusConnectionDiagnostic {
  const NimbusConnectionDiagnostic({
    required this.code,
    required this.failureCode,
    required this.stage,
    required this.summary,
  });

  final String code;
  final String failureCode;
  final String stage;
  final String summary;
}

class NimbusConnectionFailurePresentation {
  const NimbusConnectionFailurePresentation({
    required this.message,
    required this.diagnosticCode,
    required this.failureCode,
    required this.stage,
  });

  final String message;
  final String diagnosticCode;
  final String failureCode;
  final String stage;
}

class NimbusConnectionController extends Notifier<NimbusConnectionState> with AppLogger {
  static const _macOSPrivilegedHelper = MacOSPrivilegedHelper();

  Timer? _heartbeatTimer;
  Future<void>? _connectFuture;
  Future<void>? _disconnectFuture;
  Future<void>? _heartbeatFuture;
  int? _lastUploadTotal;
  int? _lastDownloadTotal;
  bool _sessionClosedByServer = false;
  bool _transportReady = false;
  DateTime? _lastDisconnectAt;

  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);
  Translations get _t => ref.read(translationsProvider).requireValue;

  String _describeError(Object error) => _repository.describeError(error, _t);

  String _diagnosticError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      final code = data is Map && data['code'] is String ? data['code'] as String : 'none';
      return 'DioException(type=${error.type.name}, status=${error.response?.statusCode}, code=$code)';
    }
    return error.runtimeType.toString();
  }

  @override
  NimbusConnectionState build() {
    ref.onDispose(_stopHeartbeat);
    Future.microtask(_deleteManagedProfileFile);

    ref.listen(connectionNotifierProvider, (_, next) {
      unawaited(_handleConnectionStatus(next));
    });
    ref.listen(nimbusAuthControllerProvider, (_, next) {
      if (!next.isAuthenticated) {
        unawaited(disconnect(reason: 'AUTH_SIGNED_OUT'));
      }
    });
    ref.listen(nimbusAppVersionControllerProvider, (_, next) {
      if (next.forceUpdate) {
        unawaited(disconnect(reason: 'APP_VERSION_UNSUPPORTED'));
      }
    });

    return const NimbusConnectionState();
  }

  Future<void> toggle({bool showErrors = true}) async {
    final connection = ref.read(connectionNotifierProvider).valueOrNull;
    if (connection is Connected || connection is Connecting) {
      await disconnect();
      return;
    }
    await connect(showErrors: showErrors);
  }

  Future<void> connect({bool showErrors = true}) async {
    final disconnectFuture = _disconnectFuture;
    if (disconnectFuture != null) await disconnectFuture;
    if (_connectFuture != null) return _connectFuture;
    final future = _connect(showErrors: showErrors);
    _connectFuture = future;
    try {
      await future;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> reconnect({bool showErrors = true, String reason = 'CLIENT_RECONNECT'}) async {
    await disconnect(reason: reason);
    await connect(showErrors: showErrors);
  }

  Future<bool> reapplyIfConnected({bool userRulesOnly = false}) async {
    final shouldReapply = shouldReapplyNimbusConnection(
      connection: ref.read(connectionNotifierProvider).valueOrNull,
      userRulesOnly: userRulesOnly,
      proxyMode: ref.read(Preferences.nimbusProxyMode),
      customWebsiteAccessEnabled: ref.read(Preferences.nimbusCustomWebsiteAccessEnabled),
    );
    if (!shouldReapply) return false;

    await reconnect(reason: 'CLIENT_SETTINGS_CHANGED');
    return true;
  }

  Future<void> selectLocation(NimbusLocation location) async {
    final authState = ref.read(nimbusAuthControllerProvider);
    if (authState.selectedLocationCode == location.code) return;

    await ref.read(nimbusAuthControllerProvider.notifier).selectLocation(location);
    await reapplyIfConnected();
  }

  Future<void> disconnect({String reason = 'CLIENT_DISCONNECTED', bool reportToServer = true}) async {
    final active = _disconnectFuture;
    if (active != null) return active;
    final future = _disconnect(reason: reason, reportToServer: reportToServer);
    _disconnectFuture = future;
    try {
      await future;
    } finally {
      _disconnectFuture = null;
    }
  }

  Future<void> _disconnect({required String reason, required bool reportToServer}) async {
    if (state.isDisconnecting) return;
    final transitionStopwatch = Stopwatch()..start();
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    final connectedReported = state.connectedReported;
    state = state.copyWith(isPreparing: false, isDisconnecting: true);

    if (connectedReported && !_sessionClosedByServer) {
      await _sendHeartbeat();
    }
    _stopHeartbeat();

    if (reportToServer && plan != null && session != null && !_sessionClosedByServer) {
      await _safeReportDisconnect(session: session, plan: plan, reason: reason);
    }

    state = const NimbusConnectionState(isDisconnecting: true);
    _sessionClosedByServer = false;
    _transportReady = false;
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    _lastDisconnectAt = DateTime.now();
    await _waitForMacOSConnectionRelease();
    await _deleteManagedProfileFile();
    const minimumTransitionDuration = Duration(milliseconds: 500);
    final remainingTransition = minimumTransitionDuration - transitionStopwatch.elapsed;
    if (remainingTransition > Duration.zero) {
      await Future<void>.delayed(remainingTransition);
    }
    state = const NimbusConnectionState();
  }

  Future<void> _connect({required bool showErrors}) async {
    final existing = ref.read(connectionNotifierProvider).valueOrNull;
    if (existing is Connected || existing is Connecting || existing is Disconnecting) return;
    state = state.copyWith(
      isPreparing: true,
      isDisconnecting: false,
      errorMessage: null,
      diagnostic: null,
      connectedReported: false,
    );
    if (await _blockForConnectionConflict(showErrors: showErrors)) return;

    await ref.read(nimbusAuthControllerProvider.notifier).refreshMe();
    final authState = ref.read(nimbusAuthControllerProvider);

    final session = authState.session;
    if (!authState.isAuthenticated || session == null) {
      await _fail(_t.nimbus.errors.loginRequired);
      return;
    }
    if (!(authState.me?.subscription.hasActivePlan ?? false)) {
      await _fail(_t.nimbus.errors.noPlan);
      return;
    }

    final version = await ref.read(nimbusAppVersionControllerProvider.notifier).check();
    if (version?.forceUpdate ?? false) {
      await _fail(_t.nimbus.errors.updateRequired);
      return;
    }

    _sessionClosedByServer = false;
    _transportReady = false;

    NimbusConnectPlan plan;
    try {
      final appVersion = _appVersion();
      var rulesPackage = await _prepareRulesPackage(session);
      plan = await _repository.createConnectPlan(
        session: session,
        selectedLocation: authState.selectedLocationCode,
        appVersion: appVersion,
        rulesManifest: rulesPackage.manifest,
      );
      if (plan.rulesManifest.requiresUpdate || !plan.rulesManifest.sameVersions(rulesPackage.manifest)) {
        rulesPackage = await _repository.fetchRulesPackage(session);
        _assertSupportedRulesPackage(rulesPackage);
        await _repository.saveRulesPackage(session.user.id, rulesPackage);
      }
      if (!plan.rulesManifest.sameVersions(rulesPackage.manifest)) {
        throw const FormatException('rules package changed while preparing connection');
      }
      if (await _blockForConnectionConflict(showErrors: showErrors)) {
        await _safeReportResult(session: session, plan: plan, status: 'failed', failureCode: 'OTHER_CONNECTION_ACTIVE');
        return;
      }
      await _writeManagedProfile(plan, rulesPackage);
      state = state.copyWith(isPreparing: true, plan: plan, traffic: plan.traffic, connectedReported: false);
    } catch (error) {
      loggy.warning('failed to prepare managed connection: ${_diagnosticError(error)}');
      await _fail(_describeError(error));
      if (_repository.isUnauthorized(error)) {
        await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
      }
      return;
    }

    try {
      final profile = _managedProfileEntity();
      final result = await ref
          .read(connectionRepositoryProvider)
          .connect(profile, ref.read(Preferences.disableMemoryLimit))
          .run();
      result.match((failure) => throw failure, (_) => null);
      _transportReady = true;
      await _handleConnectionStatus(ref.read(connectionNotifierProvider));
    } on ConnectionFailure catch (failure) {
      _transportReady = false;
      final presentation = presentNimbusConnectionFailure(failure, _t, isWindows: Platform.isWindows);
      await _safeReportResult(session: session, plan: plan, status: 'failed', failureCode: presentation.failureCode);
      state = const NimbusConnectionState();
      await _fail(presentation.message, diagnostic: _connectionDiagnostic(presentation));
    } catch (error) {
      _transportReady = false;
      await _safeReportResult(session: session, plan: plan, status: 'failed', failureCode: 'CLIENT_START_FAILED');
      state = const NimbusConnectionState();
      await _fail(
        _t.nimbus.errors.connectFailed,
        diagnostic: _connectionDiagnostic(
          const NimbusConnectionFailurePresentation(
            message: '',
            diagnosticCode: 'C-START-01',
            failureCode: 'CLIENT_START_FAILED',
            stage: 'START',
          ),
        ),
      );
      loggy.warning('failed to start managed connection', error);
    } finally {
      await _deleteManagedProfileFile();
    }
  }

  Future<bool> _blockForConnectionConflict({required bool showErrors}) async {
    if (!Platform.isMacOS) return false;

    try {
      final conflict = shouldRecheckConnectionConflict(_lastDisconnectAt, DateTime.now())
          ? await waitForMacOSConnectionRelease(inspect: _macOSPrivilegedHelper.connectionConflict)
          : await _macOSPrivilegedHelper.connectionConflict();
      if (conflict.routeCheckFailures > 0) {
        loggy.warning('macOS connection conflict route checks failed: ${conflict.routeCheckFailures}');
      }
      if (!conflict.hasConflict) return false;

      loggy.info(
        'macOS connection conflict detected '
        '(systemProxy=${conflict.systemProxyEnabled}, tunneledRoutes=${conflict.tunneledRouteCount})',
      );
      if (showErrors) {
        await _fail(_t.nimbus.errors.otherConnectionActive);
      } else if (state.isPreparing) {
        state = state.copyWith(isPreparing: false, plan: null, errorMessage: null, connectedReported: false);
      }
      return true;
    } catch (error) {
      loggy.warning('failed to inspect macOS connection conflict', error);
      return false;
    }
  }

  Future<void> _waitForMacOSConnectionRelease() async {
    if (!Platform.isMacOS) return;
    try {
      final conflict = await waitForMacOSConnectionRelease(inspect: _macOSPrivilegedHelper.connectionConflict);
      if (conflict.hasConflict) {
        loggy.warning(
          'macOS connection resources did not fully release '
          '(systemProxy=${conflict.systemProxyEnabled}, tunneledRoutes=${conflict.tunneledRouteCount})',
        );
      }
    } catch (error) {
      loggy.warning('failed to wait for macOS connection resources to release', error);
    }
  }

  Future<void> _handleConnectionStatus(AsyncValue<ConnectionStatus> next) async {
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    if (plan == null || session == null) return;

    if (next case AsyncData(:final value)
        when shouldFailNimbusPreparingDisconnected(
          isPreparing: state.isPreparing,
          connectedReported: state.connectedReported,
          connection: value,
        )) {
      final failure = (value as Disconnected).connectionFailure!;
      await _handleDisconnected(session: session, plan: plan, failure: failure);
      final presentation = presentNimbusConnectionFailure(failure, _t, isWindows: Platform.isWindows);
      await _fail(presentation.message, diagnostic: _connectionDiagnostic(presentation));
      return;
    }

    if (next case AsyncData(
      :final value,
    ) when shouldReportNimbusConnected(transportReady: _transportReady, connection: value)) {
      await _reportConnected(session: session, plan: plan);
      return;
    }

    if (next case AsyncData(value: Disconnected(:final connectionFailure))) {
      if (state.isPreparing && !state.connectedReported) return;
      await _handleDisconnected(session: session, plan: plan, failure: connectionFailure);
      return;
    }

    if (next case AsyncError(:final error)) {
      final wasPreparing = state.isPreparing && !state.connectedReported;
      await _handleDisconnected(session: session, plan: plan, failureCode: error.runtimeType.toString());
      if (wasPreparing) {
        await _fail(
          _t.nimbus.errors.connectFailed,
          diagnostic: _connectionDiagnostic(
            const NimbusConnectionFailurePresentation(
              message: '',
              diagnosticCode: 'C-STATUS-01',
              failureCode: 'CLIENT_STATUS_FAILED',
              stage: 'STATUS',
            ),
          ),
        );
      }
    }
  }

  Future<void> _reportConnected({required NimbusAuthSession session, required NimbusConnectPlan plan}) async {
    if (state.connectedReported) return;
    await _safeReportResult(session: session, plan: plan, status: 'connected');
    _primeTrafficBaseline();
    state = state.copyWith(isPreparing: false, connectedReported: true, errorMessage: null);
    _startHeartbeat();
  }

  Future<void> _handleDisconnected({
    required NimbusAuthSession session,
    required NimbusConnectPlan plan,
    ConnectionFailure? failure,
    String? failureCode,
  }) async {
    _stopHeartbeat();
    if (state.connectedReported) {
      if (!_sessionClosedByServer) {
        await _safeReportDisconnect(session: session, plan: plan, reason: failureCode ?? 'CLIENT_DISCONNECTED');
      }
    } else {
      await _safeReportResult(
        session: session,
        plan: plan,
        status: 'failed',
        failureCode:
            failureCode ??
            (failure == null
                ? 'CLIENT_START_FAILED'
                : presentNimbusConnectionFailure(failure, _t, isWindows: Platform.isWindows).failureCode),
      );
    }
    state = const NimbusConnectionState();
    _sessionClosedByServer = false;
    _transportReady = false;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    final plan = state.plan;
    if (plan == null) return;
    final interval = Duration(seconds: max(15, plan.heartbeatIntervalSeconds));
    _heartbeatTimer = Timer.periodic(interval, (_) => unawaited(_sendHeartbeat()));
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatFuture = null;
    _lastUploadTotal = null;
    _lastDownloadTotal = null;
  }

  Future<void> _sendHeartbeat() async {
    if (_heartbeatFuture != null) return _heartbeatFuture;
    final future = _sendHeartbeatThrottled();
    _heartbeatFuture = future;
    try {
      await future;
    } finally {
      _heartbeatFuture = null;
    }
  }

  Future<void> _sendHeartbeatThrottled() async {
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    if (plan == null || session == null || !state.connectedReported) return;

    final totals = _readTrafficTotals();
    final uploadDelta = _lastUploadTotal == null ? 0 : max(0, totals.upload - _lastUploadTotal!);
    final downloadDelta = _lastDownloadTotal == null ? 0 : max(0, totals.download - _lastDownloadTotal!);
    _lastUploadTotal = totals.upload;
    _lastDownloadTotal = totals.download;

    try {
      final heartbeat = await _repository.sendConnectHeartbeat(
        session: session,
        plan: plan,
        status: 'connected',
        uploadBytesDelta: uploadDelta,
        downloadBytesDelta: downloadDelta,
        appVersion: _appVersion(),
        rulesVersion: plan.rulesManifest.publicRulesVersion,
      );
      state = state.copyWith(traffic: heartbeat.traffic, lastHeartbeatAt: DateTime.now());
      if (heartbeat.disconnectRequired) {
        await _handleServerDisconnect(heartbeat);
      }
    } catch (error) {
      loggy.warning('failed to send connection heartbeat', error);
      if (_repository.isUnauthorized(error)) {
        await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
      }
      if (error is DioException && {403, 410}.contains(error.response?.statusCode)) {
        await _handleServerDisconnect(
          NimbusConnectHeartbeat(
            ok: false,
            disconnectRequired: true,
            reason: 'SESSION_CLOSED',
            traffic: state.traffic ?? plan.traffic,
          ),
        );
      }
    }
  }

  Future<void> _handleServerDisconnect(NimbusConnectHeartbeat heartbeat) async {
    _sessionClosedByServer = true;
    _stopHeartbeat();
    final message = heartbeat.reason == 'TRAFFIC_EXCEEDED'
        ? _t.nimbus.errors.trafficExceeded
        : _t.nimbus.errors.sessionEnded;
    state = state.copyWith(isPreparing: false, traffic: heartbeat.traffic, errorMessage: message);
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    state = NimbusConnectionState(traffic: heartbeat.traffic, errorMessage: message);
    _sessionClosedByServer = false;
  }

  void clearNotice() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null, diagnostic: null);
  }

  Future<void> handleAppPaused() async {
    if (state.connectedReported) await _sendHeartbeat();
  }

  Future<void> handleAppResumed() async {
    await _handleConnectionStatus(ref.read(connectionNotifierProvider));
    if (state.connectedReported) await _sendHeartbeat();
  }

  Future<NimbusRulesPackage> _prepareRulesPackage(NimbusAuthSession session) async {
    final cached = _repository.readRulesPackage(session.user.id);
    final manifest = await _repository.fetchRulesManifest(session: session, localManifest: cached?.manifest);
    if (cached != null && !manifest.requiresUpdate && manifest.sameVersions(cached.manifest)) {
      _assertSupportedRulesPackage(cached);
      return cached;
    }

    final rulesPackage = await _repository.fetchRulesPackage(session);
    _assertSupportedRulesPackage(rulesPackage);
    await _repository.saveRulesPackage(session.user.id, rulesPackage);
    return rulesPackage;
  }

  void _assertSupportedRulesPackage(NimbusRulesPackage rulesPackage) {
    if (rulesPackage.manifest.configVersion != nimbusRulesConfigVersion) {
      throw FormatException('unsupported rules config version: ${rulesPackage.manifest.configVersion}');
    }
  }

  Future<void> _writeManagedProfile(NimbusConnectPlan plan, NimbusRulesPackage rulesPackage) async {
    final resolver = ref.read(profilePathResolverProvider);
    await resolver.directory.create(recursive: true);
    await resolver
        .file(_managedProfileId)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(_buildConfig(plan, rulesPackage)));

    final profile = _managedProfileEntity();
    final dataSource = ref.read(profileDataSourceProvider);
    final existing = await dataSource.getById(_managedProfileId);
    if (existing == null) {
      await dataSource.insert(profile.toInsertEntry());
    } else {
      await dataSource.edit(_managedProfileId, profile.toUpdateEntry().copyWith(active: const Value(true)));
    }
  }

  Future<void> _deleteManagedProfileFile() async {
    try {
      await deleteNimbusManagedProfileFile(ref.read(profilePathResolverProvider));
    } catch (error) {
      loggy.warning('failed to remove managed connection config', error);
    }
  }

  ProfileEntity _managedProfileEntity() {
    return ProfileEntity.local(
      id: _managedProfileId,
      active: true,
      name: _managedProfileName,
      lastUpdate: DateTime.now(),
      populatedHeaders: const {'profile-title': _managedProfileName, 'nimbus-managed': true},
      userOverride: const UserOverride(name: _managedProfileName, isAutoUpdateDisable: true),
    );
  }

  Map<String, dynamic> _buildConfig(NimbusConnectPlan plan, NimbusRulesPackage rulesPackage) {
    _assertSupportedRulesPackage(rulesPackage);
    final patch = plan.singBoxConfigPatch;
    final outbounds = _normalizeOutbounds(patch['outbounds']);
    final routePatch = _asMap(patch['route']);

    if (!outbounds.any((outbound) => outbound['tag'] == 'nimbus-direct')) {
      outbounds.add({'type': 'direct', 'tag': 'nimbus-direct'});
    }

    final proxyMode = ref.read(Preferences.nimbusProxyMode);
    final customWebsiteAccessEnabled = ref.read(Preferences.nimbusCustomWebsiteAccessEnabled);
    final activeUserRules = selectActiveNimbusUserRules(
      isAutomaticMode: proxyMode == NimbusProxyMode.auto,
      customWebsiteAccessEnabled: customWebsiteAccessEnabled,
      userRules: rulesPackage.userRules,
    );
    final proxyTag = _proxyOutboundTag(routePatch, outbounds);
    final existingRules = _normalizeRules(routePatch['rules']);
    final existingRuleSets = _normalizeRules(routePatch['rule_set']);
    final existingRuleSetTags = existingRuleSets.map((ruleSet) => ruleSet['tag']).whereType<String>().toSet();
    final httpClients = buildNimbusHttpClients(proxyTag);
    final managedRuleSets = buildNimbusRuleSets([
      ...activeUserRules,
      ...rulesPackage.publicRules,
    ], proxyTag).where((ruleSet) => !existingRuleSetTags.contains(ruleSet['tag']));
    final routeRuleSets = [...managedRuleSets, ...existingRuleSets];
    final routeRules = proxyMode == NimbusProxyMode.global
        ? <Map<String, dynamic>>[]
        : [
            ...buildNimbusRouteRules(activeUserRules, proxyTag),
            ...buildNimbusRouteRules(rulesPackage.publicRules, proxyTag),
            nimbusFallbackRouteRule(),
            ...existingRules,
          ];
    final finalTag = proxyMode == NimbusProxyMode.global
        ? _proxyOutboundTag(routePatch, outbounds)
        : _finalOutboundTag(routePatch, outbounds);

    return {
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {'type': 'local', 'tag': 'nimbus-local'},
        ],
        'final': 'nimbus-local',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'nimbus-tun',
          if (!Platform.isMacOS) 'interface_name': 'nimbus0',
          'address': ['172.19.0.1/30'],
          'mtu': 9000,
          'auto_route': true,
          'strict_route': true,
          'stack': Platform.isMacOS ? 'system' : 'mixed',
          'sniff': true,
          'sniff_override_destination': true,
        },
        {
          'type': 'mixed',
          'tag': 'nimbus-mixed',
          'listen': '127.0.0.1',
          'listen_port': 12334,
          'sniff': true,
          'sniff_override_destination': true,
        },
      ],
      'outbounds': outbounds,
      if (httpClients.isNotEmpty) 'http_clients': httpClients,
      'route': {
        ...routePatch,
        'rules': routeRules,
        if (routeRuleSets.isNotEmpty) 'rule_set': routeRuleSets,
        if (routeRuleSets.isNotEmpty && useNimbusRuleSetHttpClient(nimbusRuleSetDownloadMode))
          'default_http_client': nimbusRuleSetHttpClientTag,
        'auto_detect_interface': true,
        'final': finalTag,
      },
      'experimental': buildNimbusExperimentalConfig(isDebugBuild: kDebugMode),
    };
  }

  List<Map<String, dynamic>> _normalizeOutbounds(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        outbounds.add(Map<String, dynamic>.from(item));
      }
    }
    if (outbounds.isEmpty) {
      outbounds.add({'type': 'direct', 'tag': 'nimbus-direct'});
    }
    return outbounds;
  }

  Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _normalizeRules(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  String _finalOutboundTag(Map<String, dynamic> route, List<Map<String, dynamic>> outbounds) {
    final routeFinal = route['final'];
    if (routeFinal is String && routeFinal.isNotEmpty) return routeFinal;
    final firstTag = outbounds.isEmpty ? null : outbounds.first['tag'];
    if (firstTag is String && firstTag.isNotEmpty) return firstTag;
    return 'nimbus-direct';
  }

  String _proxyOutboundTag(Map<String, dynamic> route, List<Map<String, dynamic>> outbounds) {
    for (final outbound in outbounds) {
      final type = outbound['type'];
      final tag = outbound['tag'];
      if (tag is String && tag.isNotEmpty && type != 'direct' && type != 'block' && type != 'dns') return tag;
    }
    return _finalOutboundTag(route, outbounds);
  }

  void _primeTrafficBaseline() {
    final totals = _readTrafficTotals();
    _lastUploadTotal = totals.upload;
    _lastDownloadTotal = totals.download;
  }

  ({int upload, int download}) _readTrafficTotals() {
    final stats = ref.read(statsNotifierProvider).valueOrNull;
    return (upload: stats?.uplinkTotal.toInt() ?? 0, download: stats?.downlinkTotal.toInt() ?? 0);
  }

  String _appVersion() {
    final appInfo = ref.read(appInfoProvider).requireValue;
    return '${appInfo.version}+${appInfo.buildNumber}';
  }

  Future<void> _safeReportResult({
    required NimbusAuthSession session,
    required NimbusConnectPlan plan,
    required String status,
    String? failureCode,
  }) async {
    try {
      await _repository.reportConnectResult(session: session, plan: plan, status: status, failureCode: failureCode);
    } catch (error) {
      loggy.warning('failed to report connection result', error);
    }
  }

  Future<void> _safeReportDisconnect({
    required NimbusAuthSession session,
    required NimbusConnectPlan plan,
    required String reason,
  }) async {
    try {
      await _repository.reportConnectDisconnect(session: session, plan: plan, reason: reason);
    } catch (error) {
      loggy.warning('failed to report connection disconnect', error);
    }
  }

  Future<void> _fail(String message, {NimbusConnectionDiagnostic? diagnostic}) async {
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    state = state.copyWith(
      isPreparing: false,
      errorMessage: message,
      diagnostic: diagnostic,
      plan: null,
      connectedReported: false,
    );
  }

  NimbusConnectionDiagnostic _connectionDiagnostic(NimbusConnectionFailurePresentation presentation) {
    final appInfo = ref.read(appInfoProvider).requireValue;
    return NimbusConnectionDiagnostic(
      code: presentation.diagnosticCode,
      failureCode: presentation.failureCode,
      stage: presentation.stage,
      summary: [
        'Yundo acceleration diagnostics',
        'diagnosticCode=${presentation.diagnosticCode}',
        'failureCode=${presentation.failureCode}',
        'stage=${presentation.stage}',
        'appVersion=${appInfo.version}+${appInfo.buildNumber}',
        'platform=${appInfo.operatingSystem}',
        'osVersion=${appInfo.operatingSystemVersion}',
      ].join('\n'),
    );
  }
}

NimbusConnectionFailurePresentation presentNimbusConnectionFailure(
  ConnectionFailure failure,
  Translations t, {
  required bool isWindows,
}) {
  final windowsError = isWindows
      ? switch (failure) {
          UnexpectedConnectionFailure(error: final WindowsTunnelServiceException error) => error,
          _ => null,
        }
      : null;
  if (windowsError != null) {
    return switch (windowsError.kind) {
      WindowsTunnelFailureKind.serviceExecutableMissing => NimbusConnectionFailurePresentation(
        message: t.nimbus.errors.windowsServiceMissing,
        diagnosticCode: 'W-SVC-01',
        failureCode: 'WINDOWS_SERVICE_EXECUTABLE_MISSING',
        stage: 'SERVICE_INSTALL',
      ),
      WindowsTunnelFailureKind.authorizationDenied => NimbusConnectionFailurePresentation(
        message: t.nimbus.errors.windowsAuthorizationRequired,
        diagnosticCode: 'W-PERM-01',
        failureCode: 'WINDOWS_AUTHORIZATION_REQUIRED',
        stage: 'SERVICE_AUTHORIZATION',
      ),
      WindowsTunnelFailureKind.serviceUnavailable => NimbusConnectionFailurePresentation(
        message: t.nimbus.errors.windowsServiceUnavailable,
        diagnosticCode: 'W-SVC-02',
        failureCode: 'WINDOWS_SERVICE_UNAVAILABLE',
        stage: 'SERVICE_START',
      ),
      WindowsTunnelFailureKind.networkComponentUnavailable => NimbusConnectionFailurePresentation(
        message: t.nimbus.errors.windowsNetworkComponentUnavailable,
        diagnosticCode: 'W-NET-01',
        failureCode: 'WINDOWS_NETWORK_COMPONENT_UNAVAILABLE',
        stage: 'NETWORK_COMPONENT',
      ),
      WindowsTunnelFailureKind.networkComponentConflict => NimbusConnectionFailurePresentation(
        message: t.nimbus.errors.windowsNetworkComponentConflict,
        diagnosticCode: 'W-NET-02',
        failureCode: 'WINDOWS_NETWORK_COMPONENT_CONFLICT',
        stage: 'NETWORK_COMPONENT',
      ),
      WindowsTunnelFailureKind.startFailed => NimbusConnectionFailurePresentation(
        message: t.nimbus.errors.windowsStartFailed,
        diagnosticCode: 'W-START-01',
        failureCode: 'WINDOWS_TUNNEL_START_FAILED',
        stage: 'TUNNEL_START',
      ),
    };
  }

  return switch (failure) {
    MissingVpnPermission() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.missingSystemPermission,
      diagnosticCode: 'P-SYS-01',
      failureCode: 'MISSING_SYSTEM_PERMISSION',
      stage: 'SYSTEM_PERMISSION',
    ),
    MissingPrivilege() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.missingPrivilege,
      diagnosticCode: 'P-AUTH-01',
      failureCode: 'MISSING_SYSTEM_PRIVILEGE',
      stage: 'SYSTEM_AUTHORIZATION',
    ),
    InvalidConfig() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.connectFailed,
      diagnosticCode: 'C-CONFIG-01',
      failureCode: 'INVALID_MANAGED_CONFIG',
      stage: 'CONFIGURATION',
    ),
    InvalidConfigOption() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.connectFailed,
      diagnosticCode: 'C-CONFIG-02',
      failureCode: 'INVALID_CONFIG_OPTION',
      stage: 'CONFIGURATION',
    ),
    BackgroundCoreNotAvailable() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.connectFailed,
      diagnosticCode: 'C-CORE-01',
      failureCode: 'CORE_NOT_AVAILABLE',
      stage: 'CORE_START',
    ),
    MissingNotificationPermission() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.connectFailed,
      diagnosticCode: 'C-NOTIFY-01',
      failureCode: 'MISSING_NOTIFICATION_PERMISSION',
      stage: 'NOTIFICATION_PERMISSION',
    ),
    MissingWarpLicense() || MissingPsiphonLicense() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.connectFailed,
      diagnosticCode: 'C-OPTION-01',
      failureCode: 'UNSUPPORTED_LOCAL_OPTION',
      stage: 'LOCAL_OPTION',
    ),
    UnexpectedConnectionFailure() => NimbusConnectionFailurePresentation(
      message: t.nimbus.errors.connectFailed,
      diagnosticCode: 'C-START-01',
      failureCode: 'CLIENT_START_FAILED',
      stage: 'START',
    ),
  };
}

bool shouldRecheckConnectionConflict(DateTime? lastDisconnectAt, DateTime now) {
  if (lastDisconnectAt == null) return false;
  final elapsed = now.difference(lastDisconnectAt);
  return !elapsed.isNegative && elapsed <= const Duration(seconds: 5);
}

Future<MacOSConnectionConflict> waitForMacOSConnectionRelease({
  required Future<MacOSConnectionConflict> Function() inspect,
  Duration timeout = const Duration(milliseconds: 2500),
  Duration pollInterval = const Duration(milliseconds: 150),
}) async {
  final deadline = DateTime.now().add(timeout);
  var conflict = await inspect();
  while (conflict.hasConflict && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(pollInterval);
    conflict = await inspect();
  }
  return conflict;
}

Future<void> deleteNimbusManagedProfileFile(ProfilePathResolver resolver) async {
  final file = resolver.file(_managedProfileId);
  if (await file.exists()) await file.delete();
}

Future<void> deleteLegacyNimbusManagedProfileFiles({Directory? applicationSupportDirectory}) async {
  var supportDirectory = applicationSupportDirectory;
  if (supportDirectory == null) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;
    supportDirectory = Directory('$home/Library/Application Support');
  }

  final retiredOwner = String.fromCharCodes(const [119, 105, 110, 116, 105, 111, 110]);
  for (final bundleId in ['com.$retiredOwner.yundo.dev', 'com.$retiredOwner.yundo']) {
    final file = File('${supportDirectory.path}/$bundleId/configs/$_managedProfileId.json');
    if (await file.exists()) await file.delete();
  }
}
