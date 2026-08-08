import 'dart:async';

import 'package:dio/dio.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('重新初始化 Core 后会重新订阅当前节点数据流', () async {
    final repository = _FakeProxyRepository();
    final container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWithValue(true),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(activeProxyNotifierProvider, (previous, next) {}, fireImmediately: true);
    addTearDown(subscription.close);

    await container.read(activeProxyNotifierProvider.future);
    expect(repository.watchActiveProxiesCalls, 1);

    container.read(coreRestartSignalProvider.notifier).restart();
    await container.read(activeProxyNotifierProvider.future);

    expect(repository.watchActiveProxiesCalls, 2);
  });

  test('连接就绪后主动测速并等待新的活动节点延时', () async {
    final repository = _FakeProxyRepository(publishDelayAfterUrlTest: 188);
    final container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWithValue(true),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    final subscription = container.listen(activeProxyNotifierProvider, (previous, next) {}, fireImmediately: true);
    addTearDown(subscription.close);

    await container.read(activeProxyNotifierProvider.future);
    await container.read(activeProxyNotifierProvider.notifier).refreshActiveDelay();

    expect(repository.urlTestActiveCalls, 1);
    expect(repository.getActiveProxySnapshotCalls, 1);
    expect(container.read(activeProxyNotifierProvider).valueOrNull?.urlTestDelay, 188);
  });
}

class _FakeProxyRepository implements ProxyRepository {
  _FakeProxyRepository({this.publishDelayAfterUrlTest});

  final int? publishDelayAfterUrlTest;
  final _activeProxyUpdates = StreamController<Either<ProxyFailure, List<OutboundGroup>>>.broadcast();
  int watchActiveProxiesCalls = 0;
  int urlTestActiveCalls = 0;
  int getActiveProxySnapshotCalls = 0;
  int? _snapshotDelay;

  void dispose() => _activeProxyUpdates.close();

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() async* {
    watchActiveProxiesCalls++;
    yield Right<ProxyFailure, List<OutboundGroup>>([
      OutboundGroup(items: [OutboundInfo(tag: 'nimbus-proxy')]),
    ]);
    yield* _activeProxyUpdates.stream;
  }

  @override
  Stream<Either<ProxyFailure, OutboundGroup?>> watchProxies() => const Stream.empty();

  @override
  TaskEither<ProxyFailure, oldipinfo.IpInfo> getCurrentIpInfo(CancelToken cancelToken) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> selectProxy(String groupTag, String outboundTag) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> urlTest(String groupTag) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> urlTestActive() {
    return TaskEither(() async {
      urlTestActiveCalls++;
      final delay = publishDelayAfterUrlTest;
      if (delay != null) {
        _snapshotDelay = delay;
      }
      return right(unit);
    });
  }

  @override
  TaskEither<ProxyFailure, OutboundInfo?> getActiveProxySnapshot() {
    return TaskEither(() async {
      getActiveProxySnapshotCalls++;
      return right(OutboundInfo(tag: 'nimbus-proxy', urlTestDelay: _snapshotDelay ?? 0));
    });
  }
}
