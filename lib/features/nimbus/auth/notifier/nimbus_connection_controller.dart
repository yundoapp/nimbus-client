import 'dart:async';
import 'dart:convert';

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
import 'package:hiddify/features/nimbus/rules/notifier/nimbus_rules_state.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _managedProfileId = 'yundo-managed-profile';
const _stateSentinel = Object();

final nimbusConnectionControllerProvider = NotifierProvider<NimbusConnectionController, NimbusConnectionState>(
  NimbusConnectionController.new,
);

final nimbusOwnedConnectionStatusProvider = Provider<AsyncValue<ConnectionStatus>>((ref) {
  return presentNimbusOwnedConnectionStatus(
    rawConnectionStatus: ref.watch(connectionNotifierProvider),
    nimbusConnection: ref.watch(nimbusConnectionControllerProvider),
  );
});

final nimbusAutoConnectSessionControllerProvider = NotifierProvider<NimbusAutoConnectSessionController, bool>(
  NimbusAutoConnectSessionController.new,
);

class NimbusAutoConnectSessionController extends Notifier<bool> {
  @override
  bool build() => true;

  void allow() => state = true;

  void suppress() => state = false;
}

bool shouldReapplyNimbusConnection({
  required ConnectionStatus? connection,
  required bool connectedReported,
  required bool userRulesOnly,
  required NimbusProxyMode proxyMode,
}) {
  if (connection is! Connected || !connectedReported) return false;
  if (!userRulesOnly) return true;
  return proxyMode == NimbusProxyMode.auto;
}

bool isNimbusOwnedConnection({required ConnectionStatus? connection, required bool connectedReported}) =>
    connection is Connected && connectedReported;

Future<NimbusRulesPackage> prepareNimbusRulesPackage({
  required NimbusRulesPackage? cached,
  required Future<NimbusRulesManifest> Function(NimbusRulesManifest? localManifest) fetchManifest,
  required Future<NimbusRulesPackage> Function() fetchPackage,
  required Future<void> Function(NimbusRulesPackage rulesPackage) savePackage,
}) async {
  NimbusRulesPackage? supportedCache = cached;
  if (supportedCache != null) {
    try {
      assertSupportedNimbusRulesPackage(supportedCache);
    } on FormatException {
      supportedCache = null;
    }
  }

  final manifest = await fetchManifest(supportedCache?.manifest);
  if (supportedCache != null && !manifest.requiresUpdate && manifest.sameVersions(supportedCache.manifest)) {
    return supportedCache;
  }

  final rulesPackage = await fetchPackage();
  assertSupportedNimbusRulesPackage(rulesPackage);
  await savePackage(rulesPackage);
  return rulesPackage;
}

void assertSupportedNimbusRulesPackage(NimbusRulesPackage rulesPackage) {
  if (rulesPackage.manifest.configVersion != nimbusRulesConfigVersion) {
    throw FormatException('unsupported rules config version: ${rulesPackage.manifest.configVersion}');
  }
}

AsyncValue<ConnectionStatus> presentNimbusOwnedConnectionStatus({
  required AsyncValue<ConnectionStatus> rawConnectionStatus,
  required NimbusConnectionState nimbusConnection,
}) {
  if (nimbusConnection.isDisconnecting) return const AsyncData(Disconnecting());
  if (nimbusConnection.isPreparing && !nimbusConnection.connectedReported) {
    return const AsyncData(Connecting());
  }
  final connection = rawConnectionStatus.valueOrNull;
  if (!nimbusConnection.connectedReported && (connection is Connected || connection is Connecting)) {
    return const AsyncData(Disconnected());
  }
  return rawConnectionStatus;
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
    this.recoveryRequestId = 0,
  });

  final bool isPreparing;
  final bool isDisconnecting;
  final NimbusConnectPlan? plan;
  final NimbusConnectTraffic? traffic;
  final String? errorMessage;
  final NimbusConnectionDiagnostic? diagnostic;
  final bool connectedReported;
  final DateTime? lastHeartbeatAt;
  final int recoveryRequestId;

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
    int? recoveryRequestId,
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
      recoveryRequestId: recoveryRequestId ?? this.recoveryRequestId,
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

class NimbusConnectionController extends Notifier<NimbusConnectionState> with AppLogger {
  Future<void>? _connectFuture;
  Future<void>? _disconnectFuture;
  bool _shutdownRequested = false;

  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);
  Translations get _t => ref.read(translationsProvider).requireValue;

  @override
  NimbusConnectionState build() {
    ref.listen(connectionNotifierProvider, (_, next) {
      _handleConnectionStatus(next);
    });
    ref.listen(nimbusAuthControllerProvider, (_, next) {
      if (!next.isAuthenticated) unawaited(disconnect(reason: 'AUTH_SIGNED_OUT'));
    });
    ref.listen(nimbusAppVersionControllerProvider, (_, next) {
      if (next.forceUpdate) unawaited(disconnect(reason: 'APP_VERSION_UNSUPPORTED'));
    });
    return const NimbusConnectionState();
  }

  Future<void> toggle({bool showErrors = true}) async {
    final connection = ref.read(connectionNotifierProvider).valueOrNull;
    if (isNimbusOwnedConnection(connection: connection, connectedReported: state.connectedReported)) {
      await disconnect(userInitiated: true);
      return;
    }
    await connect(showErrors: showErrors, userInitiated: true);
  }

  Future<void> connect({bool showErrors = true, bool userInitiated = false}) async {
    if (userInitiated) ref.read(nimbusAutoConnectSessionControllerProvider.notifier).allow();
    final active = _connectFuture;
    if (active != null) return active;
    final future = _connectInternal(showErrors: showErrors);
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
      connectedReported: state.connectedReported,
      userRulesOnly: userRulesOnly,
      proxyMode: ref.read(Preferences.nimbusProxyMode),
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

  Future<void> disconnect({
    String reason = 'CLIENT_DISCONNECTED',
    bool reportToServer = true,
    bool userInitiated = false,
  }) async {
    if (userInitiated) ref.read(nimbusAutoConnectSessionControllerProvider.notifier).suppress();
    final active = _disconnectFuture;
    if (active != null) return active;
    final future = _disconnectInternal(reason: reason, reportToServer: reportToServer);
    _disconnectFuture = future;
    try {
      await future;
    } finally {
      _disconnectFuture = null;
    }
  }

  Future<void> shutdown() async {
    loggy.info('application shutdown requested; stopping native connection');
    _shutdownRequested = true;
    ref.read(nimbusAutoConnectSessionControllerProvider.notifier).suppress();
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    final activeConnect = _connectFuture;
    if (activeConnect != null) {
      await activeConnect.timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((_) {});
    }
    await disconnect(reason: 'APP_EXIT', reportToServer: false);
  }

  Future<bool> ensureStartupRecovery({required String reason, bool showErrors = false}) async {
    loggy.info('Hiddify startup recovery [$reason]');
    final current = ref.read(connectionNotifierProvider).valueOrNull;
    if (current is Connected || current is Connecting || current is Disconnecting) {
      return isNimbusOwnedConnection(connection: current, connectedReported: state.connectedReported);
    }
    return true;
  }

  void clearNotice() {
    state = state.copyWith(errorMessage: null, diagnostic: null);
  }

  void handleAppPaused() {}

  void handleAppResumed() {}

  Future<void> _connectInternal({required bool showErrors}) async {
    if (_shutdownRequested) return;
    final startupReady = await ensureStartupRecovery(reason: 'connection request', showErrors: showErrors);
    if (!startupReady) return;

    final current = ref.read(connectionNotifierProvider).valueOrNull;
    if (current is Connected || current is Connecting || current is Disconnecting) {
      if (showErrors) _fail(_t.nimbus.errors.connectFailed, code: 'Y-CONNECTION-001', stage: 'preflight');
      return;
    }

    final authState = ref.read(nimbusAuthControllerProvider);
    if (!authState.isAuthenticated || authState.session == null) {
      _fail(_t.nimbus.errors.loginRequired, code: 'Y-AUTH-001', failureCode: 'LOGIN_REQUIRED', stage: 'preflight');
      return;
    }
    if (!(authState.me?.subscription.hasActivePlan ?? false)) {
      _fail(_t.nimbus.errors.noPlan, code: 'Y-PLAN-001', failureCode: 'NO_ACTIVE_PLAN', stage: 'preflight');
      return;
    }

    state = const NimbusConnectionState(isPreparing: true);
    try {
      await ref.read(nimbusAuthControllerProvider.notifier).refreshMe();
      final currentAuthState = ref.read(nimbusAuthControllerProvider);
      final session = currentAuthState.session;
      if (!currentAuthState.isAuthenticated || session == null) {
        _fail(_t.nimbus.errors.loginRequired, code: 'Y-AUTH-002', failureCode: 'LOGIN_REQUIRED', stage: 'prepare');
        return;
      }
      if (!(currentAuthState.me?.subscription.hasActivePlan ?? false)) {
        _fail(_t.nimbus.errors.noPlan, code: 'Y-PLAN-002', failureCode: 'NO_ACTIVE_PLAN', stage: 'prepare');
        return;
      }

      final appInfo = ref.read(appInfoProvider).requireValue;
      var rulesPackage = await _prepareRulesPackage(session);
      final plan = await _repository.createConnectPlan(
        session: session,
        selectedLocation: currentAuthState.selectedLocationCode,
        appVersion: appInfo.version,
        rulesManifest: rulesPackage.manifest,
      );
      if (plan.rulesManifest.requiresUpdate || !plan.rulesManifest.sameVersions(rulesPackage.manifest)) {
        rulesPackage = await _repository.fetchRulesPackage(session);
        assertSupportedNimbusRulesPackage(rulesPackage);
        await _repository.saveRulesPackage(session.user.id, rulesPackage);
        ref.invalidate(nimbusCachedRulesPackageProvider);
      }
      if (!plan.rulesManifest.sameVersions(rulesPackage.manifest)) {
        throw const FormatException('rules package changed while preparing connection');
      }
      if (_shutdownRequested) return;
      state = state.copyWith(plan: plan, traffic: plan.traffic);

      final profileContent = plan.profileContent?.trim();
      if (profileContent == null || profileContent.isEmpty) {
        _fail(
          _t.nimbus.errors.configurationUnavailable,
          code: 'Y-CONFIG-001',
          failureCode: 'STANDARD_PROFILE_MISSING',
          stage: 'prepare',
        );
        await _safeReportResult(session, plan, 'failed', 'STANDARD_PROFILE_MISSING');
        return;
      }
      _validateStandardProfileContent(profileContent);
      _applyManagedRouteOptions(rulesPackage);
      final validatedProfileContent = await _installStandardProfile(profileContent);
      if (_shutdownRequested) {
        await _cleanupFailedConnectionAttempt();
        return;
      }
      final profile = await ref.read(activeProfileProvider.future);
      if (profile == null) throw const FormatException('Hiddify active profile is unavailable');
      final profileFile = ref.read(profilePathResolverProvider).file(profile.id);
      if (!profileFile.existsSync()) {
        await profileFile.parent.create(recursive: true);
        await profileFile.writeAsString(validatedProfileContent);
      }
      final result = await ref
          .read(connectionRepositoryProvider)
          .connect(profile, ref.read(Preferences.disableMemoryLimit))
          .run();
      result.match((failure) => throw failure, (_) => null);
      if (_shutdownRequested) {
        await _cleanupFailedConnectionAttempt();
        return;
      }
      await ref.read(Preferences.startedByUser.notifier).update(true);
      _handleConnectionStatus(ref.read(connectionNotifierProvider));
    } on ConnectionFailure catch (error) {
      await _cleanupFailedConnectionAttempt();
      _fail(
        _t.nimbus.errors.connectFailed,
        code: 'Y-CONNECTION-002',
        failureCode: error.runtimeType.toString(),
        stage: 'start',
      );
    } catch (error, stackTrace) {
      loggy.warning('failed to prepare standard Hiddify profile', error, stackTrace);
      final apiErrorCode = _repository.apiErrorCode(error);
      await _cleanupFailedConnectionAttempt();
      _fail(
        _repository.describeError(error, _t),
        code: apiErrorCode == null ? 'Y-CONFIG-002' : 'Y-CONNECTION-003',
        failureCode: apiErrorCode ?? 'PROFILE_INVALID',
        stage: 'prepare',
      );
    }
  }

  Future<void> _cleanupFailedConnectionAttempt() async {
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    _clearManagedRouteOptions();
    await _removeManagedProfile();
  }

  Future<void> _disconnectInternal({required String reason, required bool reportToServer}) async {
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    state = state.copyWith(isPreparing: false, isDisconnecting: true, connectedReported: false);
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    _clearManagedRouteOptions();
    await ref.read(Preferences.startedByUser.notifier).update(false);
    if (reportToServer && plan != null && session != null) {
      unawaited(_safeReportDisconnect(session, plan, reason));
    }
    await _removeManagedProfile();
    state = const NimbusConnectionState();
  }

  Future<NimbusRulesPackage> _prepareRulesPackage(NimbusAuthSession session) {
    return prepareNimbusRulesPackage(
      cached: _repository.readRulesPackage(session.user.id),
      fetchManifest: (localManifest) => _repository.fetchRulesManifest(session: session, localManifest: localManifest),
      fetchPackage: () => _repository.fetchRulesPackage(session),
      savePackage: (rulesPackage) async {
        await _repository.saveRulesPackage(session.user.id, rulesPackage);
        ref.invalidate(nimbusCachedRulesPackageProvider);
      },
    );
  }

  void _applyManagedRouteOptions(NimbusRulesPackage rulesPackage) {
    final options = buildNimbusManagedRouteOptions(
      rulesPackage: rulesPackage,
      isAutomaticMode: ref.read(Preferences.nimbusProxyMode) == NimbusProxyMode.auto,
    );
    ref.read(nimbusManagedRouteOptionsProvider.notifier).state = options;
  }

  void _clearManagedRouteOptions() {
    ref.read(nimbusManagedRouteOptionsProvider.notifier).state = const NimbusManagedRouteOptions.empty();
  }

  Future<String> _installStandardProfile(String content) async {
    final parser = ref.read(profileParserProvider);
    final resolver = ref.read(profilePathResolverProvider);
    final dataSource = ref.read(profileDataSourceProvider);
    final repository = await ref.read(profileRepositoryProvider.future);
    await _removeManagedProfile();

    final file = resolver.file(_managedProfileId);
    final validationFile = resolver.file('$_managedProfileId.validation');
    final tempFile = resolver.tempFile(_managedProfileId);
    await tempFile.writeAsString(content);
    String validatedContent;
    try {
      final companion =
          (await parser
                  .addLocal(id: _managedProfileId, content: content, tempFilePath: tempFile.path, userOverride: null)
                  .run())
              .getOrElse((failure) => throw failure);
      await repository
          .validateConfig(validationFile.path, tempFile.path, null, false)
          .run()
          .then((result) => result.getOrElse((failure) => throw failure));
      if (!validationFile.existsSync()) {
        throw const FormatException('Hiddify validated profile file is unavailable');
      }
      validatedContent = await validationFile.readAsString();
      await validationFile.delete();
      await file.parent.create(recursive: true);
      await file.writeAsString(validatedContent);
      await dataSource.insert(companion);
    } finally {
      if (tempFile.existsSync()) await tempFile.delete();
      if (validationFile.existsSync()) await validationFile.delete();
    }
    return validatedContent;
  }

  Future<void> _removeManagedProfile() async {
    final dataSource = ref.read(profileDataSourceProvider);
    final resolver = ref.read(profilePathResolverProvider);
    final existing = await dataSource.getById(_managedProfileId);
    if (existing != null) {
      final file = resolver.file(_managedProfileId);
      if (file.existsSync()) {
        final repository = await ref.read(profileRepositoryProvider.future);
        await repository.deleteById(_managedProfileId, existing.active).run();
      } else {
        await dataSource.deleteById(_managedProfileId, existing.active);
      }
    } else {
      final file = resolver.file(_managedProfileId);
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }

  void _validateStandardProfileContent(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['outbounds'] is! List) {
      throw const FormatException('profileContent must be a Hiddify-compatible JSON profile');
    }
  }

  void _handleConnectionStatus(AsyncValue<ConnectionStatus> next) {
    final connection = next.valueOrNull;
    if (connection is Connected && state.isPreparing && !state.connectedReported) {
      state = state.copyWith(isPreparing: false, connectedReported: true, errorMessage: null, diagnostic: null);
      final session = ref.read(nimbusAuthControllerProvider).session;
      final plan = state.plan;
      if (session != null && plan != null) unawaited(_safeReportResult(session, plan, 'connected', null));
      return;
    }
    if (connection is Disconnected && state.connectedReported) {
      state = state.copyWith(connectedReported: false, recoveryRequestId: state.recoveryRequestId + 1);
    }
  }

  void _fail(String message, {required String code, String? failureCode, required String stage}) {
    state = state.copyWith(
      isPreparing: false,
      isDisconnecting: false,
      connectedReported: false,
      errorMessage: message,
      diagnostic: NimbusConnectionDiagnostic(
        code: code,
        failureCode: failureCode ?? 'CONNECTION_FAILED',
        stage: stage,
        summary: message,
      ),
    );
  }

  Future<void> _safeReportResult(
    NimbusAuthSession session,
    NimbusConnectPlan plan,
    String status,
    String? failureCode,
  ) async {
    try {
      await _repository.reportConnectResult(session: session, plan: plan, status: status, failureCode: failureCode);
    } catch (error) {
      loggy.warning('failed to report connection result', error);
    }
  }

  Future<void> _safeReportDisconnect(NimbusAuthSession session, NimbusConnectPlan plan, String reason) async {
    try {
      await _repository.reportConnectDisconnect(session: session, plan: plan, reason: reason);
    } catch (error) {
      loggy.warning('failed to report connection disconnect', error);
    }
  }
}
