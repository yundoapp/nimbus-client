import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_privileged_helper.dart';

void main() {
  test('recent disconnect allows one connection conflict recheck', () {
    final now = DateTime(2026, 7, 12, 12);

    expect(shouldRecheckConnectionConflict(now.subtract(const Duration(seconds: 2)), now), isTrue);
    expect(shouldRecheckConnectionConflict(now.subtract(const Duration(seconds: 4)), now), isTrue);
    expect(shouldRecheckConnectionConflict(now.subtract(const Duration(seconds: 6)), now), isFalse);
    expect(shouldRecheckConnectionConflict(now.add(const Duration(seconds: 1)), now), isFalse);
    expect(shouldRecheckConnectionConflict(null, now), isFalse);
  });

  test('断开后轮询到系统连接资源释放再允许继续', () async {
    var inspections = 0;
    final result = await waitForMacOSConnectionRelease(
      timeout: const Duration(milliseconds: 100),
      pollInterval: const Duration(milliseconds: 1),
      inspect: () async {
        inspections += 1;
        if (inspections < 3) {
          return const MacOSConnectionConflict(
            hasConflict: true,
            systemProxyEnabled: false,
            tunneledRouteCount: 4,
            routeCheckFailures: 0,
          );
        }
        return const MacOSConnectionConflict.none();
      },
    );

    expect(result.hasConflict, isFalse);
    expect(inspections, 3);
  });

  test('加速模式和节点地区等设置仅在加速已开启时自动重新应用', () {
    expect(
      shouldReapplyNimbusConnection(
        connection: const ConnectionStatus.connected(),
        userRulesOnly: false,
        proxyMode: NimbusProxyMode.global,
        customWebsiteAccessEnabled: false,
      ),
      isTrue,
    );
    expect(
      shouldReapplyNimbusConnection(
        connection: const ConnectionStatus.connected(),
        userRulesOnly: true,
        proxyMode: NimbusProxyMode.auto,
        customWebsiteAccessEnabled: true,
      ),
      isTrue,
    );
    expect(
      shouldReapplyNimbusConnection(
        connection: const ConnectionStatus.connected(),
        userRulesOnly: true,
        proxyMode: NimbusProxyMode.global,
        customWebsiteAccessEnabled: true,
      ),
      isFalse,
    );
    expect(
      shouldReapplyNimbusConnection(
        connection: const ConnectionStatus.disconnected(),
        userRulesOnly: false,
        proxyMode: NimbusProxyMode.auto,
        customWebsiteAccessEnabled: true,
      ),
      isFalse,
    );
  });

  test('startup cleanup removes only the managed profile file', () async {
    final workingDirectory = await Directory.systemTemp.createTemp('yundo-profile-cleanup-');
    addTearDown(() => workingDirectory.delete(recursive: true));
    final resolver = ProfilePathResolver(workingDirectory);
    await resolver.directory.create(recursive: true);
    final managed = resolver.file('nimbus-managed-profile');
    final unrelated = resolver.file('unrelated-profile');
    await managed.writeAsString('sensitive');
    await unrelated.writeAsString('keep');

    await deleteNimbusManagedProfileFile(resolver);

    expect(await managed.exists(), isFalse);
    expect(await unrelated.readAsString(), 'keep');
  });

  test('startup cleanup removes managed profiles from legacy bundle directories', () async {
    final supportDirectory = await Directory.systemTemp.createTemp('yundo-legacy-cleanup-');
    addTearDown(() => supportDirectory.delete(recursive: true));
    final retiredOwner = String.fromCharCodes(const [119, 105, 110, 116, 105, 111, 110]);
    final managed = File('${supportDirectory.path}/com.$retiredOwner.yundo.dev/configs/nimbus-managed-profile.json');
    final unrelated = File('${supportDirectory.path}/com.$retiredOwner.yundo.dev/configs/user-setting.json');
    await managed.parent.create(recursive: true);
    await managed.writeAsString('sensitive');
    await unrelated.writeAsString('keep');

    await deleteLegacyNimbusManagedProfileFiles(applicationSupportDirectory: supportDirectory);

    expect(await managed.exists(), isFalse);
    expect(await unrelated.readAsString(), 'keep');
  });
}
