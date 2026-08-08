import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';

import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_proxy_notifier.g.dart';

@riverpod
class IpInfoNotifier extends _$IpInfoNotifier with AppLogger {
  @override
  Future<oldipinfo.IpInfo> build() async {
    ref.disposeDelay(const Duration(seconds: 20));
    final cancelToken = CancelToken();
    Timer? timer;
    ref.onDispose(() {
      loggy.debug("disposing");
      cancelToken.cancel();
      timer?.cancel();
    });

    ref.listen(serviceRunningProvider, (_, next) => _idle = false);

    final autoCheck = ref.watch(Preferences.autoCheckIp);
    final serviceRunning = ref.watch(serviceRunningProvider);
    // loggy.debug(
    //   "idle? [$_idle], forced? [$_forceCheck], connected? [$serviceRunning]",
    // );
    if (!_forceCheck && !serviceRunning) {
      throw const ServiceNotRunning();
    } else if ((_idle && !_forceCheck) || (!_forceCheck && serviceRunning && !autoCheck)) {
      throw const UnknownIp();
    }

    _forceCheck = false;
    final info = await ref.watch(proxyRepositoryProvider).getCurrentIpInfo(cancelToken).getOrElse((err) {
      loggy.warning("error getting proxy ip info", err, StackTrace.current);
      // throw err; //hiddify: remove exception to be logged
      throw const UnknownIp();
    }).run();

    timer = Timer(const Duration(seconds: 10), () {
      loggy.debug("entering idle mode");
      _idle = true;
      ref.invalidateSelf();
    });

    return info;
  }

  bool _idle = false;
  bool _forceCheck = false;

  Future<void> refresh() async {
    if (state.isLoading) return;
    loggy.debug("refreshing");
    state = const AsyncLoading();
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    _forceCheck = true;
    ref.invalidateSelf();
  }
}

@Riverpod(keepAlive: true)
class ActiveProxyNotifier extends _$ActiveProxyNotifier with AppLogger {
  @override
  Stream<OutboundInfo> build() {
    // ref.disposeDelay(const Duration(seconds: 20));
    ref.watch(coreRestartSignalProvider);
    final serviceRunning = ref.watch(serviceRunningProvider);
    if (!serviceRunning) {
      return Stream.error(const ServiceNotRunning());
    }
    return _proxyRepo
        .watchActiveProxies()
        .map((event) => event.getOrElse((l) => List<OutboundGroup>.empty()))
        .map((event) => event.firstOrNull?.items.first ?? OutboundInfo());
  }

  ProxyRepository get _proxyRepo => ref.read(proxyRepositoryProvider);

  Future<void> urlTest(String? groupTag_) async {
    final groupTag = groupTag_ ?? "";
    if (state case AsyncData()) {
      await ref.read(hapticServiceProvider.notifier).lightImpact();
      await ref.read(proxyRepositoryProvider).urlTest(groupTag).getOrElse((err) {
        loggy.warning("error testing group", err);
        throw err;
      }).run();
    }
  }

  int _activeDelayRefreshGeneration = 0;
  DateTime? _lastActiveDelayRequestAt;

  Future<void> refreshActiveDelay({bool userInitiated = false}) async {
    final generation = ++_activeDelayRefreshGeneration;
    if (userInitiated) {
      await ref.read(hapticServiceProvider.notifier).lightImpact();
    }

    Object? lastError;
    const retryDelays = [Duration.zero, Duration(milliseconds: 500), Duration(seconds: 1)];
    for (final retryDelay in retryDelays) {
      if (generation != _activeDelayRefreshGeneration || !ref.read(serviceRunningProvider)) return;
      if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
      if (generation != _activeDelayRefreshGeneration || !ref.read(serviceRunningProvider)) return;
      final now = DateTime.now();
      final lastRequestAt = _lastActiveDelayRequestAt;
      if (lastRequestAt != null && now.difference(lastRequestAt) < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (generation != _activeDelayRefreshGeneration || !ref.read(serviceRunningProvider)) return;

      final baseline = _urlTestResultKey(state.valueOrNull);
      _lastActiveDelayRequestAt = DateTime.now();
      try {
        await _proxyRepo.urlTestActive().getOrElse((err) {
          throw err;
        }).run();
      } catch (error) {
        lastError = error;
        loggy.warning("active outbound URL test request failed", error);
        continue;
      }

      final snapshot = await _proxyRepo.getActiveProxySnapshot().run();
      final snapshotIsFresh = snapshot.match(
        (error) {
          lastError = error;
          loggy.warning("failed reading active outbound snapshot", error);
          return false;
        },
        (outbound) {
          if (outbound == null || outbound.urlTestDelay <= 0 || _urlTestResultKey(outbound) == baseline) {
            return false;
          }
          state = AsyncData(outbound);
          return true;
        },
      );
      if (snapshotIsFresh) return;

      if (await _waitForFreshActiveDelay(generation, baseline)) return;
    }

    if (lastError != null) {
      loggy.warning("active outbound URL test did not publish a fresh result", lastError);
    } else {
      loggy.warning("active outbound URL test did not publish a fresh result");
    }
  }

  Future<bool> _waitForFreshActiveDelay(int generation, String baseline) async {
    const pollInterval = Duration(milliseconds: 250);
    const maxPolls = 14;
    for (var poll = 0; poll < maxPolls; poll++) {
      await Future<void>.delayed(pollInterval);
      if (generation != _activeDelayRefreshGeneration || !ref.read(serviceRunningProvider)) return false;
      final current = state.valueOrNull;
      if (current != null && current.urlTestDelay > 0 && _urlTestResultKey(current) != baseline) return true;
    }
    return false;
  }

  String _urlTestResultKey(OutboundInfo? outbound) {
    if (outbound == null) return "none";
    final testedAt = outbound.urlTestTime;
    return "${testedAt.seconds}:${testedAt.nanos}:${outbound.urlTestDelay}";
  }
}
