import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
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
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _managedProfileId = 'nimbus-managed-profile';
const _managedProfileName = 'Yundo';
const _stateSentinel = Object();

final nimbusConnectionControllerProvider = NotifierProvider<NimbusConnectionController, NimbusConnectionState>(
  NimbusConnectionController.new,
);

class NimbusConnectionState {
  const NimbusConnectionState({
    this.isPreparing = false,
    this.plan,
    this.traffic,
    this.errorMessage,
    this.connectedReported = false,
    this.lastHeartbeatAt,
  });

  final bool isPreparing;
  final NimbusConnectPlan? plan;
  final NimbusConnectTraffic? traffic;
  final String? errorMessage;
  final bool connectedReported;
  final DateTime? lastHeartbeatAt;

  bool get hasPlan => plan != null;

  NimbusConnectionState copyWith({
    bool? isPreparing,
    Object? plan = _stateSentinel,
    Object? traffic = _stateSentinel,
    Object? errorMessage = _stateSentinel,
    bool? connectedReported,
    Object? lastHeartbeatAt = _stateSentinel,
  }) {
    return NimbusConnectionState(
      isPreparing: isPreparing ?? this.isPreparing,
      plan: identical(plan, _stateSentinel) ? this.plan : plan as NimbusConnectPlan?,
      traffic: identical(traffic, _stateSentinel) ? this.traffic : traffic as NimbusConnectTraffic?,
      errorMessage: identical(errorMessage, _stateSentinel) ? this.errorMessage : errorMessage as String?,
      connectedReported: connectedReported ?? this.connectedReported,
      lastHeartbeatAt: identical(lastHeartbeatAt, _stateSentinel) ? this.lastHeartbeatAt : lastHeartbeatAt as DateTime?,
    );
  }
}

class NimbusConnectionController extends Notifier<NimbusConnectionState> with AppLogger {
  Timer? _heartbeatTimer;
  Future<void>? _connectFuture;
  Future<void>? _heartbeatFuture;
  int? _lastUploadTotal;
  int? _lastDownloadTotal;
  bool _sessionClosedByServer = false;

  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);
  Translations get _t => ref.read(translationsProvider).requireValue;

  String _describeError(Object error) => _repository.describeError(error, _t);

  @override
  NimbusConnectionState build() {
    ref.onDispose(_stopHeartbeat);

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
    if (_connectFuture != null) return _connectFuture;
    final future = _connect(showErrors: showErrors);
    _connectFuture = future;
    try {
      await future;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> reconnect({bool showErrors = true}) async {
    await disconnect(reason: 'CLIENT_RECONNECT');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await connect(showErrors: showErrors);
  }

  Future<void> disconnect({String reason = 'CLIENT_DISCONNECTED', bool reportToServer = true}) async {
    if (state.connectedReported && !_sessionClosedByServer) {
      await _sendHeartbeat();
    }
    _stopHeartbeat();
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    state = state.copyWith(isPreparing: false);

    if (reportToServer && plan != null && session != null && !_sessionClosedByServer) {
      await _safeReportDisconnect(session: session, plan: plan, reason: reason);
    }

    state = const NimbusConnectionState();
    _sessionClosedByServer = false;
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
  }

  Future<void> _connect({required bool showErrors}) async {
    final existing = ref.read(connectionNotifierProvider).valueOrNull;
    if (existing is Connected || existing is Connecting || existing is Disconnecting) return;

    var authState = ref.read(nimbusAuthControllerProvider);
    if (authState.session != null && authState.me == null) {
      await ref.read(nimbusAuthControllerProvider.notifier).refreshMe();
      authState = ref.read(nimbusAuthControllerProvider);
    }

    final session = authState.session;
    if (!authState.isAuthenticated || session == null) {
      await _fail(_t.nimbus.errors.loginRequired, showErrors: showErrors);
      return;
    }
    if (!(authState.me?.subscription.hasActivePlan ?? false)) {
      await _fail(_t.nimbus.errors.noPlan, showErrors: showErrors);
      return;
    }

    final version = await ref.read(nimbusAppVersionControllerProvider.notifier).check();
    if (version?.forceUpdate ?? false) {
      await _fail(_t.nimbus.errors.updateRequired, showErrors: showErrors);
      return;
    }

    state = state.copyWith(isPreparing: true, errorMessage: null, connectedReported: false);
    _sessionClosedByServer = false;

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
      await _writeManagedProfile(plan, rulesPackage);
      state = state.copyWith(isPreparing: true, plan: plan, traffic: plan.traffic, connectedReported: false);
    } catch (error) {
      await _fail(_describeError(error), showErrors: showErrors);
      if (_repository.isUnauthorized(error)) {
        await ref.read(nimbusAuthControllerProvider.notifier).restore();
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
      await _handleConnectionStatus(ref.read(connectionNotifierProvider));
    } on ConnectionFailure catch (failure) {
      await _safeReportResult(session: session, plan: plan, status: 'failed', failureCode: _failureCode(failure));
      state = const NimbusConnectionState();
      await _fail(_friendlyConnectionFailure(failure), showErrors: showErrors);
    } catch (error) {
      await _safeReportResult(session: session, plan: plan, status: 'failed', failureCode: 'CLIENT_START_FAILED');
      state = const NimbusConnectionState();
      await _fail(_t.nimbus.errors.connectFailed, showErrors: showErrors);
      loggy.warning('failed to start managed connection', error);
    }
  }

  Future<void> _handleConnectionStatus(AsyncValue<ConnectionStatus> next) async {
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    if (plan == null || session == null) return;

    if (next case AsyncData(value: Connected())) {
      await _reportConnected(session: session, plan: plan);
      return;
    }

    if (next case AsyncData(value: Disconnected(:final connectionFailure))) {
      if (state.isPreparing && !state.connectedReported) return;
      await _handleDisconnected(session: session, plan: plan, failure: connectionFailure);
      return;
    }

    if (next case AsyncError(:final error)) {
      await _handleDisconnected(session: session, plan: plan, failureCode: error.runtimeType.toString());
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
        failureCode: failureCode ?? (failure == null ? 'CLIENT_START_FAILED' : _failureCode(failure)),
      );
    }
    state = const NimbusConnectionState();
    _sessionClosedByServer = false;
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
        await ref.read(nimbusAuthControllerProvider.notifier).restore();
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
    await ref
        .read(dialogNotifierProvider.notifier)
        .showCustomAlert(title: _t.nimbus.errors.disconnectedTitle, message: message);
    state = NimbusConnectionState(traffic: heartbeat.traffic, errorMessage: message);
    _sessionClosedByServer = false;
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
    final proxyTag = _proxyOutboundTag(routePatch, outbounds);
    final existingRules = _normalizeRules(routePatch['rules']);
    final routeRules = proxyMode == NimbusProxyMode.global
        ? <Map<String, dynamic>>[]
        : [
            ...buildNimbusRouteRules(rulesPackage.userRules, proxyTag),
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
          'interface_name': 'nimbus0',
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
      'route': {...routePatch, 'rules': routeRules, 'auto_detect_interface': true, 'final': finalTag},
      'experimental': {
        'cache_file': {'enabled': true},
      },
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

  Future<void> _fail(String message, {required bool showErrors}) async {
    state = state.copyWith(isPreparing: false, errorMessage: message, plan: null, connectedReported: false);
    if (showErrors) {
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlert(title: _t.nimbus.errors.cannotConnectTitle, message: message);
    }
  }

  String _friendlyConnectionFailure(ConnectionFailure failure) {
    return switch (failure) {
      MissingVpnPermission() => _t.nimbus.errors.missingSystemPermission,
      MissingPrivilege() => _t.nimbus.errors.missingPrivilege,
      _ => _t.nimbus.errors.connectFailed,
    };
  }

  String _failureCode(ConnectionFailure failure) {
    return switch (failure) {
      MissingVpnPermission() => 'MISSING_SYSTEM_PERMISSION',
      MissingPrivilege() => 'MISSING_SYSTEM_PRIVILEGE',
      InvalidConfig() => 'INVALID_MANAGED_CONFIG',
      InvalidConfigOption() => 'INVALID_CONFIG_OPTION',
      BackgroundCoreNotAvailable() => 'CORE_NOT_AVAILABLE',
      MissingNotificationPermission() => 'MISSING_NOTIFICATION_PERMISSION',
      MissingWarpLicense() || MissingPsiphonLicense() => 'UNSUPPORTED_LOCAL_OPTION',
      UnexpectedConnectionFailure() => 'CLIENT_START_FAILED',
    };
  }
}
