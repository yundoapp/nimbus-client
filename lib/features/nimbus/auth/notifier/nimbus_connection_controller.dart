import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_bundled_rules.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_acceleration_diagnostic.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_diagnostics_localization.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_acceleration_diagnostics_controller.dart';
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

bool shouldRestoreNimbusOwnership({required ConnectionStatus? connection, required bool startedByUser}) =>
    startedByUser && connection is Connected;

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

  NimbusRulesManifest manifest;
  try {
    manifest = await fetchManifest(supportedCache?.manifest);
  } catch (_) {
    if (supportedCache != null) return supportedCache;
    rethrow;
  }
  if (supportedCache != null && !manifest.requiresUpdate && manifest.sameVersions(supportedCache.manifest)) {
    return supportedCache;
  }

  try {
    final rulesPackage = await fetchPackage();
    assertSupportedNimbusRulesPackage(rulesPackage);
    await savePackage(rulesPackage);
    return rulesPackage;
  } catch (_) {
    if (supportedCache != null) return supportedCache;
    rethrow;
  }
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
  Translations get _diagnosticsT => nimbusDiagnosticsTranslations(_t);

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
    final currentConnection = ref.read(connectionNotifierProvider).valueOrNull;
    final startedByUser = ref.read(Preferences.startedByUser);
    return NimbusConnectionState(
      connectedReported: shouldRestoreNimbusOwnership(connection: currentConnection, startedByUser: startedByUser),
    );
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
    final diagnostics = ref.read(nimbusAccelerationDiagnosticsProvider.notifier);
    diagnostics.begin(NimbusAccelerationOperation.start);
    diagnostics.startStep(NimbusAccelerationStepId.connectionState);
    final startupReady = await ensureStartupRecovery(reason: 'connection request', showErrors: showErrors);
    if (!startupReady) {
      diagnostics.failStep(
        NimbusAccelerationStepId.connectionState,
        detail: _diagnosticsT.nimbus.diagnostics.detailNoActiveConnection,
      );
      diagnostics.fail(
        errorCode: 'Y-CONNECTION-001',
        detail: _diagnosticsT.nimbus.diagnostics.detailNoActiveConnection,
      );
      return;
    }

    final current = ref.read(connectionNotifierProvider).valueOrNull;
    if (current is Connected || current is Connecting || current is Disconnecting) {
      diagnostics.failStep(
        NimbusAccelerationStepId.connectionState,
        detail: _diagnosticsT.nimbus.diagnostics.detailNoActiveConnection,
      );
      diagnostics.fail(
        errorCode: 'Y-CONNECTION-001',
        detail: _diagnosticsT.nimbus.diagnostics.detailNoActiveConnection,
      );
      if (showErrors) _fail(_t.nimbus.errors.connectFailed, code: 'Y-CONNECTION-001', stage: 'preflight');
      return;
    }
    diagnostics.completeStep(
      NimbusAccelerationStepId.connectionState,
      detail: _diagnosticsT.nimbus.diagnostics.detailNoActiveConnection,
    );

    final authState = ref.read(nimbusAuthControllerProvider);
    diagnostics.startStep(NimbusAccelerationStepId.account);
    if (!authState.isAuthenticated || authState.session == null) {
      diagnostics.failStep(
        NimbusAccelerationStepId.account,
        detail: _diagnosticsT.nimbus.diagnostics.detailSessionMissing,
        errorCode: 'LOGIN_REQUIRED',
      );
      diagnostics.fail(errorCode: 'Y-AUTH-001', detail: _diagnosticsT.nimbus.diagnostics.detailSessionMissing);
      _fail(_t.nimbus.errors.loginRequired, code: 'Y-AUTH-001', failureCode: 'LOGIN_REQUIRED', stage: 'preflight');
      return;
    }
    diagnostics.completeStep(
      NimbusAccelerationStepId.account,
      detail: _diagnosticsT.nimbus.diagnostics.detailSessionAvailable,
    );
    diagnostics.startStep(NimbusAccelerationStepId.subscription);
    if (!(authState.me?.subscription.hasActivePlan ?? false)) {
      diagnostics.failStep(
        NimbusAccelerationStepId.subscription,
        detail: _diagnosticsT.nimbus.diagnostics.detailPlanMissing,
        errorCode: 'NO_ACTIVE_PLAN',
      );
      diagnostics.fail(errorCode: 'Y-PLAN-001', detail: _diagnosticsT.nimbus.diagnostics.detailPlanMissing);
      _fail(_t.nimbus.errors.noPlan, code: 'Y-PLAN-001', failureCode: 'NO_ACTIVE_PLAN', stage: 'preflight');
      return;
    }
    diagnostics.completeStep(
      NimbusAccelerationStepId.subscription,
      detail: _diagnosticsT.nimbus.diagnostics.detailActivePlan,
    );

    state = const NimbusConnectionState(isPreparing: true);
    try {
      diagnostics.startStep(
        NimbusAccelerationStepId.account,
        detail: _diagnosticsT.nimbus.diagnostics.detailRefreshingAccount,
      );
      await ref.read(nimbusAuthControllerProvider.notifier).refreshMe();
      final currentAuthState = ref.read(nimbusAuthControllerProvider);
      final session = currentAuthState.session;
      if (!currentAuthState.isAuthenticated || session == null) {
        diagnostics.failStep(
          NimbusAccelerationStepId.account,
          detail: _diagnosticsT.nimbus.diagnostics.detailSessionExpired,
          errorCode: 'LOGIN_REQUIRED',
        );
        diagnostics.fail(errorCode: 'Y-AUTH-002', detail: _diagnosticsT.nimbus.diagnostics.detailSessionExpired);
        _fail(_t.nimbus.errors.loginRequired, code: 'Y-AUTH-002', failureCode: 'LOGIN_REQUIRED', stage: 'prepare');
        return;
      }
      diagnostics.completeStep(
        NimbusAccelerationStepId.account,
        detail: _diagnosticsT.nimbus.diagnostics.detailAccountRefreshed,
      );
      diagnostics.startStep(
        NimbusAccelerationStepId.subscription,
        detail: _diagnosticsT.nimbus.diagnostics.detailCheckingAllowance,
      );
      if (!(currentAuthState.me?.subscription.hasActivePlan ?? false)) {
        diagnostics.failStep(
          NimbusAccelerationStepId.subscription,
          detail: _diagnosticsT.nimbus.diagnostics.detailPlanInactive,
          errorCode: 'NO_ACTIVE_PLAN',
        );
        diagnostics.fail(errorCode: 'Y-PLAN-002', detail: _diagnosticsT.nimbus.diagnostics.detailPlanInactive);
        _fail(_t.nimbus.errors.noPlan, code: 'Y-PLAN-002', failureCode: 'NO_ACTIVE_PLAN', stage: 'prepare');
        return;
      }
      diagnostics.completeStep(
        NimbusAccelerationStepId.subscription,
        detail: _diagnosticsT.nimbus.diagnostics.detailAllowanceAvailable,
      );

      final appInfo = ref.read(appInfoProvider).requireValue;
      diagnostics.startStep(NimbusAccelerationStepId.rules);
      var rulesPackage = await _prepareRulesPackage(session);
      diagnostics.startStep(NimbusAccelerationStepId.connectionPlan);
      final plan = await _repository.createConnectPlan(
        session: session,
        selectedLocation: currentAuthState.selectedLocationCode,
        appVersion: appInfo.version,
        rulesManifest: rulesPackage.manifest,
      );
      var usingRulesFallback = false;
      if (plan.rulesManifest.requiresUpdate || !plan.rulesManifest.sameVersions(rulesPackage.manifest)) {
        diagnostics.startStep(NimbusAccelerationStepId.rules, detail: _diagnosticsT.nimbus.diagnostics.rules);
        try {
          rulesPackage = await _repository.fetchRulesPackage(session);
          assertSupportedNimbusRulesPackage(rulesPackage);
          await _repository.saveRulesPackage(session.user.id, rulesPackage);
          ref.invalidate(nimbusCachedRulesPackageProvider);
          ref.invalidate(nimbusRulesPackageProvider);
        } catch (error) {
          usingRulesFallback = true;
          loggy.warning('rules package refresh failed; keeping the last validated snapshot: $error');
        }
      }
      if (!plan.rulesManifest.sameVersions(rulesPackage.manifest)) {
        if (!usingRulesFallback) {
          throw const FormatException('rules package changed while preparing connection');
        }
        // The plan is authoritative for the current account versions. Keep
        // the last validated payload for this connection rather than blocking
        // the network because a newer remote package could not be downloaded.
        rulesPackage = rulesPackage.copyWith(manifest: plan.rulesManifest);
      }
      diagnostics.completeStep(NimbusAccelerationStepId.rules, detail: _rulesLoadedDiagnostic(rulesPackage));
      diagnostics.completeStep(
        NimbusAccelerationStepId.connectionPlan,
        detail: _diagnosticsT.nimbus.diagnostics.detailPlanReceived,
      );
      if (_shutdownRequested) {
        diagnostics.fail(errorCode: 'CANCELED', detail: _diagnosticsT.nimbus.diagnostics.detailStopRequested);
        return;
      }
      state = state.copyWith(plan: plan, traffic: plan.traffic);

      final profileContent = plan.profileContent?.trim();
      if (profileContent == null || profileContent.isEmpty) {
        diagnostics.failStep(
          NimbusAccelerationStepId.coreConfig,
          detail: _t.nimbus.errors.configurationUnavailable,
          errorCode: 'STANDARD_PROFILE_MISSING',
        );
        diagnostics.fail(errorCode: 'Y-CONFIG-001', detail: _t.nimbus.errors.configurationUnavailable);
        _fail(
          _t.nimbus.errors.configurationUnavailable,
          code: 'Y-CONFIG-001',
          failureCode: 'STANDARD_PROFILE_MISSING',
          stage: 'prepare',
        );
        await _safeReportResult(session, plan, 'failed', 'STANDARD_PROFILE_MISSING');
        return;
      }
      diagnostics.startStep(NimbusAccelerationStepId.rules, detail: _diagnosticsT.nimbus.diagnostics.rules);
      await _applyManagedRouteOptions(rulesPackage);
      diagnostics.completeStep(NimbusAccelerationStepId.rules, detail: _rulesLoadedDiagnostic(rulesPackage));
      diagnostics.startStep(NimbusAccelerationStepId.coreConfig, detail: _diagnosticsT.nimbus.diagnostics.coreConfig);
      _validateStandardProfileContent(profileContent);
      final validatedProfileContent = await _installStandardProfile(profileContent);
      if (_shutdownRequested) {
        await _cleanupFailedConnectionAttempt();
        diagnostics.fail(errorCode: 'CANCELED', detail: _diagnosticsT.nimbus.diagnostics.detailStopRequested);
        return;
      }
      final profile = await ref.read(activeProfileProvider.future);
      if (profile == null) throw const FormatException('Hiddify active profile is unavailable');
      final profileFile = ref.read(profilePathResolverProvider).file(profile.id);
      if (!profileFile.existsSync()) {
        await profileFile.parent.create(recursive: true);
        await profileFile.writeAsString(validatedProfileContent);
      }
      diagnostics.completeStep(
        NimbusAccelerationStepId.coreConfig,
        detail: _diagnosticsT.nimbus.diagnostics.detailProfileValidated,
      );
      diagnostics.startStep(NimbusAccelerationStepId.corePrepare, detail: _diagnosticsT.nimbus.diagnostics.corePrepare);
      loggy.info('starting managed connection repository');
      final result = await ref
          .read(connectionRepositoryProvider)
          .connect(profile, ref.read(Preferences.disableMemoryLimit))
          .run();
      loggy.info('managed connection repository returned: ${result.isRight() ? 'success' : 'failure'}');
      result.match((failure) => throw failure, (_) => null);
      if (_shutdownRequested) {
        await _cleanupFailedConnectionAttempt();
        diagnostics.fail(errorCode: 'CANCELED', detail: _diagnosticsT.nimbus.diagnostics.detailStopRequested);
        return;
      }
      loggy.info('persisting managed connection state');
      await ref.read(Preferences.startedByUser.notifier).update(true);
      loggy.info('managed connection state persisted');
      _markConnectionEstablished();
      loggy.info('managed connection state promoted to connected');
      diagnostics.startStep(NimbusAccelerationStepId.cleanup, detail: _diagnosticsT.nimbus.diagnostics.cleanup);
      diagnostics.completeStep(
        NimbusAccelerationStepId.cleanup,
        detail: _diagnosticsT.nimbus.diagnostics.detailCleanupDone,
      );
      diagnostics.complete(detail: _diagnosticsT.nimbus.diagnostics.detailAccelerationStarted);
      loggy.info('acceleration start diagnostics completed');
    } on ConnectionFailure catch (error) {
      loggy.warning('Yundo connection start failed: $error');
      await _cleanupFailedConnectionAttempt();
      _fail(
        _t.nimbus.errors.connectFailed,
        code: 'Y-CONNECTION-002',
        failureCode: error.runtimeType.toString(),
        stage: 'start',
      );
      diagnostics.failRunningStep(detail: error.toString(), errorCode: error.runtimeType.toString());
      diagnostics.fail(errorCode: 'Y-CONNECTION-002', detail: error.toString());
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
      diagnostics.failRunningStep(detail: error.toString(), errorCode: apiErrorCode ?? 'PROFILE_INVALID');
      diagnostics.fail(errorCode: apiErrorCode ?? 'Y-CONFIG-002', detail: error.toString());
    }
  }

  String _rulesLoadedDiagnostic(NimbusRulesPackage package) {
    final publicVersion = package.manifest.publicRulesVersion?.trim();
    final detail = _diagnosticsT.nimbus.diagnostics.detailRulesLoaded(
      publicCount: package.publicRules.length.toString(),
      publicVersion: publicVersion == null || publicVersion.isEmpty ? '--' : publicVersion,
      userCount: package.userRules.length.toString(),
    );
    final sources = [...package.publicRules, ...package.userRules]
        .where((item) => item.sourceUrl?.trim().isNotEmpty ?? false)
        .map((item) => '${item.pattern}=${item.sourceUrl}')
        .join('|');
    return sources.isEmpty ? detail : '$detail\nsource=$sources';
  }

  Future<void> _cleanupFailedConnectionAttempt() async {
    final diagnostics = ref.read(nimbusAccelerationDiagnosticsProvider.notifier);
    final shouldRecord = diagnostics.isOperationRunning(NimbusAccelerationOperation.start);
    if (shouldRecord) {
      diagnostics.startStep(NimbusAccelerationStepId.cleanup, detail: _diagnosticsT.nimbus.diagnostics.cleanup);
    }
    try {
      await ref.read(connectionNotifierProvider.notifier).abortConnection();
      _clearManagedRouteOptions();
      await _removeManagedProfile();
      if (shouldRecord) {
        diagnostics.completeStep(
          NimbusAccelerationStepId.cleanup,
          detail: _diagnosticsT.nimbus.diagnostics.detailCleanupDone,
        );
      }
    } catch (error) {
      if (shouldRecord) {
        diagnostics.failStep(NimbusAccelerationStepId.cleanup, detail: error.toString(), errorCode: 'CLEANUP_FAILED');
      }
      rethrow;
    }
  }

  Future<void> _disconnectInternal({required String reason, required bool reportToServer}) async {
    final diagnostics = ref.read(nimbusAccelerationDiagnosticsProvider.notifier);
    diagnostics.begin(NimbusAccelerationOperation.stop);
    diagnostics.startStep(NimbusAccelerationStepId.connectionState);
    diagnostics.completeStep(
      NimbusAccelerationStepId.connectionState,
      detail: _diagnosticsT.nimbus.diagnostics.detailStopRequested,
    );
    final plan = state.plan;
    final session = ref.read(nimbusAuthControllerProvider).session;
    state = state.copyWith(isPreparing: false, isDisconnecting: true, connectedReported: false);
    try {
      diagnostics.startStep(NimbusAccelerationStepId.coreStop, detail: _diagnosticsT.nimbus.diagnostics.coreStop);
      await ref.read(connectionNotifierProvider.notifier).abortConnection();
      diagnostics.startStep(NimbusAccelerationStepId.tunnel, detail: _diagnosticsT.nimbus.diagnostics.tunnel);
      diagnostics.completeStep(
        NimbusAccelerationStepId.tunnel,
        detail: _diagnosticsT.nimbus.diagnostics.detailTunnelReleased,
      );
      diagnostics.startStep(NimbusAccelerationStepId.routing, detail: _diagnosticsT.nimbus.diagnostics.routing);
      _clearManagedRouteOptions();
      diagnostics.completeStep(
        NimbusAccelerationStepId.routing,
        detail: _diagnosticsT.nimbus.diagnostics.detailRoutingRestored,
      );
      await ref.read(Preferences.startedByUser.notifier).update(false);
      if (reportToServer && plan != null && session != null) {
        unawaited(_safeReportDisconnect(session, plan, reason));
      }
      diagnostics.startStep(NimbusAccelerationStepId.cleanup, detail: _diagnosticsT.nimbus.diagnostics.cleanup);
      await _removeManagedProfile();
      diagnostics.completeStep(
        NimbusAccelerationStepId.cleanup,
        detail: _diagnosticsT.nimbus.diagnostics.detailCleanupDone,
      );
      diagnostics.complete(detail: _diagnosticsT.nimbus.diagnostics.detailAccelerationStopped);
      state = const NimbusConnectionState();
    } catch (error, stackTrace) {
      diagnostics.failRunningStep(detail: error.toString(), errorCode: 'Y-CLEANUP-001');
      diagnostics.fail(errorCode: 'Y-CLEANUP-001', detail: error.toString());
      state = state.copyWith(isDisconnecting: false);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<NimbusRulesPackage> _prepareRulesPackage(NimbusAuthSession session) {
    return _prepareRulesPackageWithBundledFallback(session);
  }

  Future<NimbusRulesPackage> _prepareRulesPackageWithBundledFallback(NimbusAuthSession session) async {
    final cached = _repository.readRulesPackage(session.user.id) ?? await readNimbusBundledRulesPackage();
    return prepareNimbusRulesPackage(
      cached: cached,
      fetchManifest: (localManifest) => _repository.fetchRulesManifest(session: session, localManifest: localManifest),
      fetchPackage: () => _repository.fetchRulesPackage(session),
      savePackage: (rulesPackage) async {
        await _repository.saveRulesPackage(session.user.id, rulesPackage);
        ref.invalidate(nimbusCachedRulesPackageProvider);
      },
    );
  }

  Future<void> _applyManagedRouteOptions(NimbusRulesPackage rulesPackage) async {
    final ruleSetTags = rulesPackage.publicRules
        .followedBy(rulesPackage.userRules)
        .where((rule) => rule.kind == 'rule_set')
        .map((rule) => rule.pattern);
    final bundledRuleSetPaths = await ensureNimbusBundledRuleSetFiles(
      tags: ruleSetTags,
      directories: ref.read(appDirectoriesProvider).requireValue,
    );
    final options = buildNimbusManagedRouteOptions(
      rulesPackage: rulesPackage,
      isAutomaticMode: ref.read(Preferences.nimbusProxyMode) == NimbusProxyMode.auto,
      bundledRuleSetPaths: bundledRuleSetPaths,
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
    // The core reports Connected before macOS tunnel activation completes. Only
    // _connectInternal may promote the Nimbus-owned state to connected.
    if (connection is Connected && state.isPreparing) {
      return;
    }
    if (connection is Disconnected && state.connectedReported) {
      state = state.copyWith(connectedReported: false, recoveryRequestId: state.recoveryRequestId + 1);
    }
  }

  void _markConnectionEstablished() {
    state = state.copyWith(isPreparing: false, connectedReported: true, errorMessage: null, diagnostic: null);
    final session = ref.read(nimbusAuthControllerProvider).session;
    final plan = state.plan;
    if (session != null && plan != null) unawaited(_safeReportResult(session, plan, 'connected', null));
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
