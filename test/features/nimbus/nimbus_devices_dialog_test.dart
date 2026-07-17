import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_devices_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('设备管理弹窗在 ${themeMode.name} 模式显示设备并允许删除旧设备', (tester) async {
      String? removedDeviceId;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
            nimbusAuthControllerProvider.overrideWith(
              () => _FakeNimbusAuthController(onRemove: (deviceId) => removedDeviceId = deviceId),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeMode,
            home: const _TestPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('打开设备管理'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('设备管理'), findsOneWidget);
      expect(find.text('2/3 台设备'), findsOneWidget);
      expect(find.text('当前 Mac'), findsOneWidget);
      expect(find.text('旧 Mac'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      expect(find.byTooltip('删除设备'), findsOneWidget);

      await tester.tap(find.byTooltip('删除设备'));
      await tester.pumpAndSettle();

      expect(find.text('删除设备'), findsOneWidget);
      expect(find.text('确定删除“旧 Mac”吗？'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(removedDeviceId, 'old-device-ref');
    });
  }
}

class _TestPage extends ConsumerWidget {
  const _TestPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    return Scaffold(
      body: translations.hasValue
          ? FilledButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const NimbusDevicesDialog()),
              child: const Text('打开设备管理'),
            )
          : const CircularProgressIndicator(),
    );
  }
}

class _FakeNimbusAuthController extends NimbusAuthController {
  _FakeNimbusAuthController({required this.onRemove});

  final void Function(String deviceId) onRemove;

  @override
  NimbusAuthState build() => NimbusAuthState.authenticated(
    session: const NimbusAuthSession(
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
      device: NimbusDevice(
        id: 'current-device-ref',
        deviceId: 'current-device',
        platform: 'macos',
        deviceName: '当前 Mac',
      ),
    ),
    devices: NimbusDevicesList(
      limit: 3,
      items: [
        NimbusRegisteredDevice(
          id: 'current-device-ref',
          deviceId: 'current-device',
          platform: 'macos',
          deviceName: '当前 Mac',
          appVersion: '1.0.0+10000',
          status: 'active',
          isCurrent: true,
          firstLoginAt: DateTime(2026, 7),
          lastActiveAt: DateTime(2026, 7, 15, 1),
        ),
        NimbusRegisteredDevice(
          id: 'old-device-ref',
          deviceId: 'old-device',
          platform: 'macos',
          deviceName: '旧 Mac',
          appVersion: '1.0.0+10000',
          status: 'active',
          isCurrent: false,
          firstLoginAt: DateTime(2026, 7),
          lastActiveAt: DateTime(2026, 7, 14, 23),
        ),
      ],
    ),
  );

  @override
  Future<void> loadDevices() async {}

  @override
  Future<bool> removeDevice(String deviceId) async {
    onRemove(deviceId);
    return true;
  }
}
