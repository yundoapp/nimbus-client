import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/log/model/log_level.dart' as config_log_level;
import 'package:hiddify/features/nimbus/auth/model/nimbus_acceleration_diagnostic.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_diagnostics_localization.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rule_set_diagnostic.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_acceleration_diagnostics_controller.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper_stub.dart'
    if (dart.library.io) 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart' as loggyl;
import 'package:rxdart/rxdart.dart';

class HiddifyCoreService with InfraLogger {
  HiddifyCoreService(this.ref);
  final Ref ref;

  @override
  loggyl.Loggy<InfraLogger> get loggy => loggyl.Loggy<InfraLogger>('YundoCoreService');

  // CoreHiddifyCoreService() {}
  final core = getCoreInterface();

  CoreStatus currentState = const CoreStatus.stopped();
  final statusController = BehaviorSubject<CoreStatus>();
  final logController = BehaviorSubject<List<LogMessage>>();
  final CallOptions? grpcOptions = null; //CallOptions(timeout: const Duration(milliseconds: 10000));
  final Map<String, StreamSubscription?> subscriptions = {};
  List<OutboundGroup> latest = [];

  Future<void> init() async {
    await setup()
        .mapLeft((e) {
          loggy.error(e);
          if (PlatformUtils.isIOS) return;
          statusController.add(const CoreStatus.stopped());
          ref.read(inAppNotificationControllerProvider).showErrorToast(e);
        })
        .map((_) {
          loggy.info("Yundo core setup done");
          ref.read(coreRestartSignalProvider.notifier).restart();
        })
        .run();
  }

  /// validates config by path and save it
  ///
  /// [path] is used to save validated config
  /// [tempPath] includes base config, possibly invalid
  /// [debug] indicates if debug mode (avoid in prod)

  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) {
    return TaskEither(() async {
      try {
        final response = await core.fgClient.parse(ParseRequest(tempPath: tempPath, configPath: path, debug: false));
        if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      } catch (e) {
        await setup().run();
        final response = await core.fgClient.parse(ParseRequest(tempPath: tempPath, configPath: path, debug: false));
        if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      }
      return right(unit);
    });
  }

  TaskEither<String, String> generateFullConfigByPath(String path) {
    return TaskEither(() async {
      final response = await core.fgClient.parse(ParseRequest(configPath: path, debug: false));
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    });
  }

  TaskEither<String, Unit> setup() {
    return TaskEither(() async {
      try {
        final directories = ref.read(appDirectoriesProvider).requireValue;
        final debug = ref.read(debugModeNotifierProvider);
        final setupResponse = await core.setup(directories, debug, 3);

        if (setupResponse.isNotEmpty) {
          return left(setupResponse);
        }

        await startListeningLogs("fg", core.fgClient);
        // await startListeningStatus("fg", core.fgClient);
        if (!core.isSingleChannel()) {
          await startListeningLogs("bg", core.bgClient);
        }
        statusController.add(currentState);
        await startListeningStatus("bg", core.bgClient);
        // ref.read(coreRestartSignalProvider.notifier).restart();
        return right(unit);
      } catch (e) {
        return left(e.toString());
      }
    });
  }

  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    return TaskEither(() async {
      loggy.debug("changing options");
      // latestOptions = options;
      try {
        final res = await core.fgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson())),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
        await core.bgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson())),
        );
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unavailable) {
          loggy.debug("background core is not started yet! $e");
        } else {
          rethrow;
        }
      }

      return right(unit);
    });
  }

  TaskEither<ConnectionFailure, Unit> start(
    String path,
    String name,
    bool disableMemoryLimit, {
    bool enableRawConfig = false,
  }) {
    return TaskEither(() async {
      final diagnostics = ref.read(nimbusAccelerationDiagnosticsProvider.notifier);
      final t = nimbusDiagnosticsTranslations(ref.read(translationsProvider).requireValue);
      final ruleSetLogOffset = logBuffer.length;
      var ruleSetTags = _remoteRuleSetTags(path);
      statusController.add(currentState = const CoreStatus.starting());
      diagnostics.startStep(NimbusAccelerationStepId.corePrepare, detail: t.nimbus.diagnostics.corePrepare);
      loggy.debug("starting");
      final background = await core.setupBackground(path, name);
      // macOS prepares a derived user-core config after adding the managed
      // public and account rule sets. Read tags from that effective config so
      // diagnostics describe what the core actually loads.
      ruleSetTags = _remoteRuleSetTags(core.backgroundConfigPath(path));
      loggy.info('core background preparation response: $background');
      if (background != const CoreStatus.started()) {
        _recordRuleSetFailureFromLogs(ruleSetTags, ruleSetLogOffset, diagnostics, t);
        _recordRuleSetFailureIfPresent(background.toString(), diagnostics, t);
        diagnostics.failStep(
          NimbusAccelerationStepId.corePrepare,
          detail: background.toString(),
          errorCode: 'CORE_PREPARE_FAILED',
        );
        diagnostics.fail(errorCode: 'Y-CORE-001', detail: background.toString());
        loggy.warning('core background preparation failed: $background');
        statusController.add(currentState = const CoreStatus.stopped());
        return left(background.getCoreAlert() ?? const ConnectionFailure.unexpected("failed to start core"));
      }
      diagnostics.completeStep(NimbusAccelerationStepId.corePrepare, detail: t.nimbus.diagnostics.detailCorePrepared);
      // A previous stop may have left the old local HTTP/2 channel in a
      // closing state. Rebind before issuing the next start command.
      await stopListenSingle('fg');
      await stopListenSingle('bg');
      await core.refreshClients();
      await _refreshCoreListeners();
      final backgroundConfigPath = core.backgroundConfigPath(path);
      final useRawConfig = enableRawConfig || backgroundConfigPath != path;
      loggy.info('core start prepared (raw=$useRawConfig, macosPathRewritten=${backgroundConfigPath != path})');
      try {
        diagnostics.startStep(NimbusAccelerationStepId.coreStart, detail: t.nimbus.diagnostics.coreStart);
        final res = await core.bgClient.start(
          StartRequest(
            configPath: backgroundConfigPath,
            configName: name,
            disableMemoryLimit: disableMemoryLimit,
            enableRawConfig: useRawConfig,
          ),
        );
        loggy.info('core start response: state=${res.coreState}, type=${res.messageType}, message=${res.message}');
        if (res.messageType != MessageType.ALREADY_STARTED && res.messageType != MessageType.EMPTY) {
          _recordRuleSetFailureFromLogs(ruleSetTags, ruleSetLogOffset, diagnostics, t);
          _recordRuleSetFailureIfPresent(res.message, diagnostics, t);
          diagnostics.failStep(NimbusAccelerationStepId.coreStart, detail: res.message, errorCode: 'CORE_START_FAILED');
          diagnostics.fail(errorCode: 'Y-CORE-002', detail: res.message);
          final alert = _isSystemPermissionError(res.message) ? CoreAlert.requestVPNPermission : CoreAlert.startFailed;
          currentState = CoreStatus.stopped(
            alert: alert,
            message: "failed to start core ${res.messageType} ${res.message}",
          );

          statusController.add(currentState);

          await core.stop();

          return left(
            currentState.getCoreAlert() ??
                ConnectionFailure.unexpected("failed to start core ${res.messageType} ${res.message}"),
          );
        }
        await _refreshCoreListeners();
        diagnostics.completeStep(
          NimbusAccelerationStepId.coreStart,
          detail: t.nimbus.diagnostics.detailCoreProcessStarted,
        );
        diagnostics.startStep(NimbusAccelerationStepId.coreVerify, detail: t.nimbus.diagnostics.coreVerify);
        if (res.coreState != CoreStates.STARTED) {
          final detail = t.nimbus.diagnostics.detailCoreStatusUnexpected(state: res.coreState.name);
          diagnostics.failStep(
            NimbusAccelerationStepId.coreVerify,
            detail: detail,
            errorCode: 'CORE_STATUS_UNEXPECTED',
          );
          diagnostics.fail(errorCode: 'Y-CORE-004', detail: detail);
          await core.stop();
          statusController.add(currentState = const CoreStatus.stopped());
          return left(ConnectionFailure.unexpected(detail));
        }
        diagnostics.completeStep(
          NimbusAccelerationStepId.coreVerify,
          detail: t.nimbus.diagnostics.detailCoreStatusStarted,
        );

        diagnostics.startStep(NimbusAccelerationStepId.ruleSets, detail: t.nimbus.diagnostics.ruleSets);
        final ruleSetDiagnostics = await _waitForRuleSetDiagnostics(tags: ruleSetTags, logOffset: ruleSetLogOffset);
        if (ruleSetDiagnostics.hasFailure || !ruleSetDiagnostics.allResolved) {
          final detail =
              ruleSetDiagnostics.firstFailure?.detail ??
              t.nimbus.diagnostics.detailRuleSetsPending(
                tags: ruleSetDiagnostics.items.map((item) => item.tag).join(', '),
              );
          diagnostics.failStep(
            NimbusAccelerationStepId.ruleSets,
            detail: detail,
            errorCode: ruleSetDiagnostics.hasFailure ? 'RULE_SET_DOWNLOAD_FAILED' : 'RULE_SET_STATUS_UNKNOWN',
          );
          diagnostics.fail(errorCode: 'Y-RULE-001', detail: detail);
          await core.bgClient.stop(Empty());
          await core.stop();
          statusController.add(currentState = const CoreStatus.stopped());
          return left(ConnectionFailure.unexpected(detail));
        }
        final ruleSetDetail = ruleSetDiagnostics.firstUpdateFailure?.detail;
        diagnostics.completeStep(
          NimbusAccelerationStepId.ruleSets,
          detail: ruleSetDetail == null
              ? t.nimbus.diagnostics.detailRuleSetsLoaded(count: ruleSetDiagnostics.items.length)
              : t.nimbus.diagnostics.detailRuleSetsLoadedWithFailure(
                  count: ruleSetDiagnostics.items.length,
                  detail: ruleSetDetail,
                ),
        );

        diagnostics.startStep(NimbusAccelerationStepId.network, detail: t.nimbus.diagnostics.network);
        final networkPreparation = await _prepareTunnelNetworkMode(
          name: name,
          disableMemoryLimit: disableMemoryLimit,
          enableRawConfig: useRawConfig,
        );
        final networkError = networkPreparation.errorMessage;
        if (networkError != null) {
          diagnostics.failStep(
            NimbusAccelerationStepId.network,
            detail: networkError,
            errorCode: 'NETWORK_PROBE_FAILED',
          );
          diagnostics.fail(errorCode: 'Y-NETWORK-001', detail: networkError);
          loggy.warning('macOS tunnel network preparation failed: $networkError');
          await core.bgClient.stop(Empty());
          await core.stop();
          statusController.add(currentState = const CoreStatus.stopped());
          return left(ConnectionFailure.unexpected(networkError));
        }
        diagnostics.completeStep(
          NimbusAccelerationStepId.network,
          detail: networkPreparation.usedIpv4Fallback
              ? t.nimbus.diagnostics.detailNetworkFallback
              : t.nimbus.diagnostics.detailNetworkDualStack,
        );

        diagnostics.startStep(NimbusAccelerationStepId.tunnel, detail: t.nimbus.diagnostics.tunnel);
        final tunnel = await core.activateTunnel();
        loggy.info('macOS tunnel activation response: $tunnel');
        if (tunnel != const CoreStatus.started()) {
          diagnostics.failStep(
            NimbusAccelerationStepId.tunnel,
            detail: tunnel.toString(),
            errorCode: 'TUNNEL_START_FAILED',
          );
          diagnostics.fail(errorCode: 'Y-TUNNEL-001', detail: tunnel.toString());
          await core.bgClient.stop(Empty());
          await core.stop();
          statusController.add(currentState = const CoreStatus.stopped());
          return left(tunnel.getCoreAlert() ?? const ConnectionFailure.unexpected('failed to start tunnel'));
        }
        diagnostics.completeStep(NimbusAccelerationStepId.tunnel, detail: t.nimbus.diagnostics.detailTunnelActive);
        diagnostics.startStep(NimbusAccelerationStepId.routing, detail: t.nimbus.diagnostics.routing);
        diagnostics.completeStep(NimbusAccelerationStepId.routing, detail: t.nimbus.diagnostics.detailRoutingActive);
        loggy.info('macOS tunnel activation flow completed; releasing prepared config');
      } on GrpcError catch (e) {
        _recordRuleSetFailureFromLogs(ruleSetTags, ruleSetLogOffset, diagnostics, t);
        _recordRuleSetFailureIfPresent(e.message ?? e.toString(), diagnostics, t);
        diagnostics.failRunningStep(detail: e.message ?? e.toString(), errorCode: 'GRPC_ERROR');
        diagnostics.fail(errorCode: 'Y-CORE-003', detail: e.message ?? e.toString());
        loggy.error("failed to start bg core: $e");
        if (e.code == StatusCode.unavailable) {
          await core.stop();
          return left(const ConnectionFailure.unexpected("background core is not started yet!"));
        }
        if (_isSystemPermissionError(e.message)) {
          await core.stop();
          return left(const ConnectionFailure.missingVpnPermission());
        }
        return left(const ConnectionFailure.unexpected("failed to start background core"));
      } finally {
        loggy.debug('discarding prepared macOS connection config');
        await core.discardPreparedConfig();
        loggy.debug('prepared macOS connection config discarded');
      }

      loggy.info('core start flow completed');
      // if (res.messageType != MessageType.EMPTY) return left(res);

      return right(unit);
    });
  }

  Set<String> _remoteRuleSetTags(String path) {
    try {
      final decoded = jsonDecode(File(path).readAsStringSync());
      if (decoded is! Map) return const {};
      return nimbusRemoteRuleSetTagsFromConfig(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const {};
    }
  }

  Future<NimbusRuleSetDiagnosticsResult> _waitForRuleSetDiagnostics({
    required Set<String> tags,
    required int logOffset,
  }) async {
    if (tags.isEmpty) return const NimbusRuleSetDiagnosticsResult([]);
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    NimbusRuleSetDiagnosticsResult result = parseNimbusRuleSetDiagnostics(logMessages: const [], tags: tags);
    while (DateTime.now().isBefore(deadline)) {
      final start = logOffset.clamp(0, logBuffer.length);
      result = parseNimbusRuleSetDiagnostics(
        logMessages: logBuffer.skip(start).map((message) => message.message),
        tags: tags,
      );
      if (result.hasFailure || result.allResolved) return result;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return result;
  }

  void _recordRuleSetFailureIfPresent(
    String detail,
    NimbusAccelerationDiagnosticsController diagnostics,
    Translations t,
  ) {
    if (!detail.toLowerCase().contains('rule-set')) return;
    diagnostics.startStep(NimbusAccelerationStepId.ruleSets, detail: t.nimbus.diagnostics.ruleSets);
    diagnostics.failStep(NimbusAccelerationStepId.ruleSets, detail: detail, errorCode: 'RULE_SET_DOWNLOAD_FAILED');
  }

  void _recordRuleSetFailureFromLogs(
    Set<String> tags,
    int logOffset,
    NimbusAccelerationDiagnosticsController diagnostics,
    Translations t,
  ) {
    if (tags.isEmpty) return;
    final start = logOffset.clamp(0, logBuffer.length);
    final result = parseNimbusRuleSetDiagnostics(
      logMessages: logBuffer.skip(start).map((message) => message.message),
      tags: tags,
    );
    final failure = result.firstFailure;
    if (failure == null) return;
    diagnostics.startStep(NimbusAccelerationStepId.ruleSets, detail: t.nimbus.diagnostics.ruleSets);
    diagnostics.failStep(
      NimbusAccelerationStepId.ruleSets,
      detail: failure.detail ?? failure.tag,
      errorCode: 'RULE_SET_DOWNLOAD_FAILED',
    );
  }

  Future<void> _refreshCoreListeners() async {
    await startListeningLogs('fg', core.fgClient);
    await startListeningStatus('bg', core.bgClient);
    if (!core.isSingleChannel()) {
      await startListeningLogs('bg', core.bgClient);
      await startListeningStatus('bg', core.bgClient);
    }
  }

  bool _isSystemPermissionError(String? message) {
    final normalized = message?.toLowerCase() ?? '';
    return normalized.contains('permission denied') ||
        normalized.contains('operation not permitted') ||
        normalized.contains('access denied');
  }

  Future<({String? errorMessage, bool usedIpv4Fallback})> _prepareTunnelNetworkMode({
    required String name,
    required bool disableMemoryLimit,
    required bool enableRawConfig,
  }) async {
    final preparation = await core.prepareTunnelActivation();
    if (preparation.errorMessage case final error?) return (errorMessage: error, usedIpv4Fallback: false);
    if (preparation.fallbackConfigPath case final fallbackPath?) {
      loggy.info('restarting macOS user core with the IPv4 fallback config');
      await stopListenSingle('fg');
      await stopListenSingle('bg');
      CoreInfoResponse? response;
      try {
        response = await core.bgClient.restart(
          StartRequest(
            configPath: fallbackPath,
            configName: name,
            disableMemoryLimit: disableMemoryLimit,
            enableRawConfig: enableRawConfig,
          ),
        );
      } on GrpcError catch (error) {
        if (!_isExpectedCoreRestartTermination(error)) rethrow;
        loggy.info('core restart closed the old HTTP/2 stream; waiting for the new core state');
      }
      if (response != null &&
          response.messageType != MessageType.EMPTY &&
          response.messageType != MessageType.ALREADY_STARTED) {
        return (
          errorMessage: 'failed to apply macOS IPv4 fallback: ${response.messageType} ${response.message}',
          usedIpv4Fallback: true,
        );
      }
      await core.refreshClients();
      final coreState = await core.waitForCoreState();
      if (coreState != CoreStates.STARTED) {
        return (
          errorMessage: 'macOS IPv4 fallback core did not reach STARTED: ${coreState?.name ?? 'UNKNOWN'}',
          usedIpv4Fallback: true,
        );
      }
      await _refreshCoreListeners();
    }
    return (errorMessage: null, usedIpv4Fallback: preparation.usedIpv4Fallback);
  }

  bool _isExpectedCoreRestartTermination(GrpcError error) {
    final message = error.message?.toLowerCase() ?? '';
    return error.code == StatusCode.unknown &&
        message.contains('http/2 error') &&
        message.contains('forcefully terminated');
  }

  TaskEither<String, Unit> stop() {
    return TaskEither(() async {
      final diagnostics = ref.read(nimbusAccelerationDiagnosticsProvider.notifier);
      final t = ref.read(translationsProvider).requireValue;
      final isDiagnosticStop = diagnostics.isOperationRunning(NimbusAccelerationOperation.stop);
      if (isDiagnosticStop) {
        diagnostics.startStep(NimbusAccelerationStepId.coreStop, detail: t.nimbus.diagnostics.coreStop);
      }
      loggy.debug("stopping");
      var errMsg = "";
      try {
        await stopListenSingle('fg');
        await stopListenSingle('bg');
        await core.bgClient.stop(Empty());
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2") ?? false)) {
          errMsg = e.message ?? "failed to stop core: $e";

          loggy.error("failed to stop bg core: $e");
        }
      } catch (e) {
        loggy.error("failed to stop bg core: $e");
        // left("failed to stop core: $e");
      }
      if (!await core.stop()) {}
      if (isDiagnosticStop) {
        if (errMsg.isNotEmpty) {
          diagnostics.failStep(NimbusAccelerationStepId.coreStop, detail: errMsg, errorCode: 'CORE_STOP_FAILED');
        } else {
          diagnostics.completeStep(NimbusAccelerationStepId.coreStop, detail: t.nimbus.diagnostics.detailCoreStopped);
          diagnostics.startStep(NimbusAccelerationStepId.coreStopVerify, detail: t.nimbus.diagnostics.coreStopVerify);
          diagnostics.completeStep(
            NimbusAccelerationStepId.coreStopVerify,
            detail: t.nimbus.diagnostics.detailCoreStatusStopped,
          );
        }
      }
      statusController.add(currentState = const CoreStatus.stopped());
      if (errMsg.isNotEmpty) return left(errMsg);
      return right(unit);
    });
  }

  TaskEither<String, Unit> restart(String path, String name, bool disableMemoryLimit, {bool enableRawConfig = false}) {
    return TaskEither(() async {
      loggy.debug("restarting");
      // if (!await core.restart(path, name)) {
      try {
        final prepared = await core.prepareRestart(path, name);
        loggy.info('core restart preparation response: $prepared');
        if (prepared != const CoreStatus.started()) {
          loggy.warning('core restart preparation failed: $prepared');
          return left(prepared.getCoreAlert()?.toString() ?? 'failed to prepare tunnel restart');
        }
        final backgroundConfigPath = core.backgroundConfigPath(path);
        final useRawConfig = enableRawConfig || backgroundConfigPath != path;
        loggy.info('core restart prepared (raw=$useRawConfig, macosPathRewritten=${backgroundConfigPath != path})');
        final res = await core.bgClient.restart(
          StartRequest(
            configPath: backgroundConfigPath,
            configName: name,
            disableMemoryLimit: disableMemoryLimit,
            delayStart: true,
            enableRawConfig: useRawConfig,
          ),
        );
        loggy.info('core restart response: state=${res.coreState}, type=${res.messageType}, message=${res.message}');
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
        final networkPreparation = await _prepareTunnelNetworkMode(
          name: name,
          disableMemoryLimit: disableMemoryLimit,
          enableRawConfig: useRawConfig,
        );
        if (networkPreparation.errorMessage != null) {
          await core.bgClient.stop(Empty());
          await core.stop();
          return left(networkPreparation.errorMessage!);
        }
        final tunnel = await core.activateTunnel();
        loggy.info('macOS tunnel activation response: $tunnel');
        if (tunnel != const CoreStatus.started()) {
          await core.bgClient.stop(Empty());
          await core.stop();
          return left(tunnel.getCoreAlert()?.toString() ?? 'failed to restart tunnel');
        }
      } on GrpcError catch (e) {
        loggy.error("failed to restart bg core: $e");
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2 error") ?? false)) {
          return left("${e.message}");
        }
      } finally {
        await core.discardPreparedConfig();
      }

      return right(unit);
      // await stop().run();
      // return await start(path, name, disableMemoryLimit).run();
      // }
      // if (!core.isSingleChannel()) {
      //   await startListeningStatus("bg", core.bgClient);
      //   await startListeningLogs("bg", core.bgClient);
      // }
      // return right(unit);
    });
  }

  TaskEither<String, Unit> resetTunnel() {
    return TaskEither(() async {
      // only available on iOS (and macOS later)
      if (!PlatformUtils.isIOS) {
        throw UnimplementedError("reset tunnel function unavailable on platform");
      }

      // loggy.debug("resetting tunnel");
      final res = await core.resetTunnel();
      if (res) {
        return right(unit);
      }
      return left("failed to reset tunnel");
    });
  }

  // Stream<List<OutboundGroup>> watchGroups() async* {
  //   loggy.debug("watching groups");
  //   yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items);
  //   // res?.cancel();
  // }

  Stream<OutboundGroup?> watchGroup() async* {
    loggy.debug("watching group");
    // interrupt managed by core

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }
    try {
      yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items.isEmpty ? null : event.items.first);
    } catch (e) {
      loggy.error("error watching group: $e");
      rethrow;
    }
    // //emitting first event immediately
    // yield* core.bgClient.outboundsInfo(Empty()).take(1).map((event) => event.items.isEmpty ? null : event.items.first);
    // //emitting other event after every 4 seconds(latest event)
    // yield* core.bgClient.outboundsInfo(Empty()).throttleTime(const Duration(seconds: 4), leading: false, trailing: true).map((event) => event.items.isEmpty ? null : event.items.first);
  }

  Stream<List<OutboundGroup>> watchActiveGroups() async* {
    loggy.info("watching active groups");

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }

    try {
      yield* core.bgClient
          .mainOutboundsInfo(Empty())
          .map((event) {
            return latest = event.items.toList();
          })
          .startWith(latest);
    } catch (e) {
      loggy.error("error watching active groups: $e");
      rethrow;
    }
  }

  //
  // Stream<SingboxStatus> watchStatus() => _status;

  ResponseStream<SystemInfo> watchStats() {
    loggy.debug("watching stats");
    try {
      return core.bgClient.getSystemInfoStream(Empty());
    } catch (e) {
      loggy.error("error watching stats: $e");
      rethrow;
    }
  }

  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    return TaskEither(() async {
      loggy.debug("selecting outbound");
      try {
        final res = await core.bgClient.selectOutbound(
          SelectOutboundRequest(groupTag: groupTag, outboundTag: outboundTag),
          options: CallOptions(timeout: const Duration(seconds: 1)),
        );
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error selecting outbound: $e");
        rethrow;
      }
    });
  }

  TaskEither<String, Unit> urlTest(String tag) {
    return TaskEither(() async {
      loggy.debug("url test");
      try {
        final res = await core.bgClient.urlTest(UrlTestRequest(tag: tag));
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error in url test: $e");
        rethrow;
      }
    });
  }

  List<LogMessage> logBuffer = [];

  // SingboxConfigOption? latestOptions;

  Stream<List<LogMessage>> watchLogs(String path) async* {
    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty log stream");
      return;
    }
    await startListeningLogs("bg", core.bgClient);
    await startListeningLogs("fg", core.fgClient);
    try {
      yield* logController.stream;
    } catch (e) {
      loggy.error("error watching logs: $e");
      rethrow;
    }
    // Stream<List<String>> logStream(CoreClient coreClient) {
    //   return coreClient.logListener(Empty()).asBroadcastStream().map((event) => [event.message]).onErrorResume((error, stackTrace) {
    //     loggy.debug('Error in $coreClient: $error, retrying...');
    //     final delay = (currentState == const SingboxStatus.stopped()) ? 5 : 1;
    //     return const Stream<List<String>>.empty().delay(Duration(seconds: delay)).concatWith([logStream(coreClient)]);
    //   });
    // }

    // // Create streams for both fg and bg clients with retry logic
    // final fgLogStream = logStream(core.fgClient);

    // if (core.bgClient == core.fgClient) {
    //   yield* fgLogStream;
    //   return;
    // }
    // final bgLogStream = logStream(core.bgClient);
    // yield* MergeStream([bgLogStream, fgLogStream]);
  }

  TaskEither<String, Unit> clearLogs() {
    return TaskEither(() async {
      loggy.debug("clearing logs");
      logBuffer.clear();
      // final res = await core.bgClient(Empty());
      // if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");
      return right(unit);
    });
  }

  // TaskEither<String, WarpResponse> generateWarpConfig({
  //   required String licenseKey,
  //   required String previousAccountId,
  //   required String previousAccessToken,
  // }) {
  //   return TaskEither(() async {
  //     loggy.debug("generating warp config");
  //     final warpConfig = await core.fgClient.generateWarpConfig(
  //       GenerateWarpConfigRequest(
  //         licenseKey: licenseKey,
  //         accountId: previousAccountId,
  //         accessToken: previousAccessToken,
  //       ),
  //     );
  //     // if (warpConfig.code != ResponseCode.OK) return left("${warpConfig.code} ${warpConfig.message}");
  //     final WarpResponse warp = (
  //       log: warpConfig.log,
  //       accountId: warpConfig.account.accountId,
  //       accessToken: warpConfig.account.accessToken,
  //       wireguardConfig: jsonEncode(warpConfig.config.toProto3Json()),
  //     );
  //     return right(warp);
  //   });
  // }

  Stream<CoreStatus> watchStatus() async* {
    await startListeningStatus("bg", core.bgClient);
    yield* statusController.stream;
    // .endWith(const CoreStatus.stopped());
  }

  Future<void> startListeningStatus(String key, CoreClient cc) async {
    await listenSingle<CoreStatus>(
      "${key}StatusListener",
      () => cc
          .coreInfoListener(Empty(), options: grpcOptions)
          .doOnCancel(() {
            loggy.error("status", "Canceld");
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .doOnData((event) {
            loggy.debug("status", event);
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .doOnDone(() {
            loggy.error("status", "done");
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .endWith(CoreInfoResponse(coreState: CoreStates.STOPPED))
          .map((event) {
            currentState = CoreStatus.fromCoreInfo(event);
            statusController.add(currentState);
            return currentState;
          }),
      // .endWith(const CoreStatus.stopped())
      onError: (error) {
        loggy.error("Stream error in ${key}StatusListener: $error");

        // currentState = const CoreStatus.stopped();
        // statusController.add(currentState);

        // startListeningStatus(key, cc);
      },
    );
  }

  Future<void> startListeningLogs(String key, CoreClient cc) async {
    final logLevel = ref.read(ConfigOptions.logLevel);
    final coreLogLevel = getCoreLogLevel(logLevel);
    final listenKey = "${key}LogListener";
    // await stopListenSingle(listenKey);
    await listenSingle<LogMessage>(listenKey, () {
      return cc.logListener(LogRequest(level: coreLogLevel), options: grpcOptions).map((event) {
        // Handle incoming event
        logBuffer.add(event);
        if (logBuffer.length > 300) {
          logBuffer.removeAt(0);
        }
        logController.add(logBuffer);
        // loggy.log(getLogLevel(event.level), event.message);
        event.message.split('\n').forEach((line) {
          loggy.log(getLogLevel(event.level), line);
        });
        return event;
      });
    });
  }

  Future<void> stopListenSingle(String key) async {
    // Collect keys to remove first
    final keysToRemove = subscriptions.entries
        .where((entry) => entry.key.startsWith(key))
        .map((entry) => entry.key)
        .toList();

    // Cancel and remove
    for (final k in keysToRemove) {
      final sub = subscriptions[k];
      await sub?.cancel(); // cancel the subscription

      subscriptions.remove(k);
    }
  }

  Future<StreamSubscription<T>?> listenSingle<T>(
    String key,
    Stream<T> Function() stream, {
    Function(dynamic error)? onError,
  }) async {
    if (subscriptions.containsKey(key)) {
      // return subscriptions[key] as StreamSubscription<T>?;
      await stopListenSingle(key);
    }
    subscriptions[key] = null;
    subscriptions[key] = stream().listen(
      (event) {
        // loggy.debug(event);
      },
      cancelOnError: true,
      onError: (error) {
        loggy.log(loggyl.LogLevel.error, 'Stream error: $error');
        onError?.call(error);
        subscriptions[key]?.cancel();
        subscriptions.remove(key);
      },
    );
    return subscriptions[key] as StreamSubscription<T>?;
  }

  loggyl.LogLevel getLogLevel(LogLevel level) {
    return switch (level) {
      LogLevel.DEBUG => loggyl.LogLevel.debug,
      LogLevel.INFO => loggyl.LogLevel.info,
      LogLevel.WARNING => loggyl.LogLevel.warning,
      LogLevel.ERROR => loggyl.LogLevel.error,
      LogLevel.FATAL => loggyl.LogLevel.error,
      _ => loggyl.LogLevel.info, // Default case
    };
  }

  LogLevel getCoreLogLevel(config_log_level.LogLevel level) {
    return switch (level) {
      config_log_level.LogLevel.trace => LogLevel.TRACE,
      config_log_level.LogLevel.debug => LogLevel.DEBUG,
      config_log_level.LogLevel.info => LogLevel.INFO,
      config_log_level.LogLevel.warn => LogLevel.WARNING,
      config_log_level.LogLevel.error => LogLevel.ERROR,
      config_log_level.LogLevel.fatal => LogLevel.FATAL,
      config_log_level.LogLevel.panic => LogLevel.FATAL,
    };
  }

  Future<void> closeFront() async {
    if (!core.isInitialized()) {
      return;
    }
    if (!core.isSingleChannel()) {
      await stopListenSingle("fg");
      await stopListenSingle("bg");
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL_INSECURE));
      } catch (error) {
        loggy.debug('front core insecure close skipped: $error');
      }
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL));
      } catch (error) {
        loggy.debug('front core secure close skipped: $error');
      }
    }
  }

  TaskEither<String, LANIPResponse> getLANIP() {
    return TaskEither(() async {
      try {
        final response = await core.fgClient.getLANIP(Empty());
        return right(response);
      } catch (e) {
        loggy.error("failed to get LAN IP: $e");
        return left(e.toString());
      }
    });
  }
}
