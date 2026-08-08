import 'dart:io';
import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/route_history/notifier/nimbus_route_history_notifier.dart';
import 'package:hiddify/features/stats/data/stats_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'stats_notifier.g.dart';

@riverpod
class StatsNotifier extends _$StatsNotifier with AppLogger {
  @override
  Stream<SystemInfo> build() {
    ref.disposeDelay(const Duration(seconds: 10));
    final serviceRunning = ref.watch(serviceRunningProvider);
    if (serviceRunning) {
      if (PlatformUtils.isMacOS) {
        final workingDirectory = ref.watch(appDirectoriesProvider).requireValue.workingDir;
        var previousUploadTotal = 0;
        var previousDownloadTotal = 0;
        var hasPreviousTrafficStats = false;
        return watchNimbusMacOSTunnelTraffic(
          File(p.join(workingDirectory.path, 'data', 'current-config.json')),
          appProcessName: p.basename(Platform.resolvedExecutable),
        ).throttleTime(const Duration(seconds: 1), leading: false, trailing: true).map((helperStats) {
          final upload = helperStats.uploadTotal;
          final download = helperStats.downloadTotal;
          final uplink = hasPreviousTrafficStats ? math.max(0, upload - previousUploadTotal) : 0;
          final downlink = hasPreviousTrafficStats ? math.max(0, download - previousDownloadTotal) : 0;
          previousUploadTotal = upload;
          previousDownloadTotal = download;
          hasPreviousTrafficStats = true;

          return SystemInfo.create()
            ..trafficAvailable = true
            ..uplink = Int64(uplink)
            ..downlink = Int64(downlink)
            ..uplinkTotal = Int64(upload)
            ..downlinkTotal = Int64(download);
        });
      }
    }

    if (serviceRunning) {
      return ref
          .watch(statsRepositoryProvider)
          .watchStats()
          .map((event) => event.getOrElse((_) => SystemInfo.create()));
    }
    return Stream.value(SystemInfo.create());
  }
}
