import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('主页已有加速失败提示时不再重复弹出错误弹窗', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
          environmentProvider.overrideWith((ref) => Environment.dev),
          appInfoProvider.overrideWith(_FakeAppInfo.new),
          sharedPreferencesProvider.overrideWith((ref) => preferences),
          nimbusAuthRepositoryProvider.overrideWithValue(_FakeNimbusAuthRepository(preferences)),
          nimbusAuthControllerProvider.overrideWith(_AuthenticatedNimbusAuthController.new),
          nimbusAppVersionControllerProvider.overrideWith(_NoopNimbusAppVersionController.new),
          connectionNotifierProvider.overrideWith(_DisconnectedConnectionNotifier.new),
          nimbusConnectionControllerProvider.overrideWith(_ConnectionErrorController.new),
        ],
        child: MaterialApp(theme: ThemeData.light(), home: const _ReadyHomePage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text(_connectionError), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const _connectionError = '系统检测到另一款代理 App 正在运行。请先断开或退出该 App，再开启云渡加速。';

const _session = NimbusAuthSession(
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
  device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'macos', deviceName: 'Test Mac'),
);

class _FakeAppInfo extends AppInfo {
  @override
  Future<AppInfoEntity> build() async {
    return const AppInfoEntity(
      name: 'Yundo',
      version: '1.0.0',
      buildNumber: '10000',
      release: Release.general,
      operatingSystem: 'macos',
      operatingSystemVersion: 'test',
      environment: Environment.dev,
    );
  }
}

class _ReadyHomePage extends ConsumerWidget {
  const _ReadyHomePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final appInfo = ref.watch(appInfoProvider);
    final preferences = ref.watch(sharedPreferencesProvider);
    if (!translations.hasValue || !appInfo.hasValue || !preferences.hasValue) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return const HomePage();
  }
}

class _AuthenticatedNimbusAuthController extends NimbusAuthController {
  @override
  NimbusAuthState build() {
    return const NimbusAuthState.authenticated(
      session: _session,
      me: NimbusMe(
        user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
        subscription: NimbusSubscription(status: 'none'),
        devices: NimbusDeviceQuota(used: 1, limit: 3),
        rules: NimbusRulesInfo(),
      ),
      locations: NimbusLocationsList(
        items: [NimbusLocation(code: 'auto', displayName: '')],
      ),
    );
  }

  @override
  Future<void> loadLocations() async {}
}

class _NoopNimbusAppVersionController extends NimbusAppVersionController {
  @override
  NimbusAppVersionState build() => const NimbusAppVersionState(hasChecked: true);

  @override
  Future<NimbusAppVersionCheck?> check({bool force = false}) async => state.result;
}

class _DisconnectedConnectionNotifier extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const ConnectionStatus.disconnected());
}

class _ConnectionErrorController extends NimbusConnectionController {
  @override
  NimbusConnectionState build() => const NimbusConnectionState(errorMessage: _connectionError);
}

class _FakeNimbusAuthRepository extends NimbusAuthRepository {
  _FakeNimbusAuthRepository(SharedPreferences preferences)
    : super(
        preferences: preferences,
        appInfo: const AppInfoEntity(
          name: 'Yundo',
          version: '1.0.0',
          buildNumber: '10000',
          release: Release.general,
          operatingSystem: 'macos',
          operatingSystemVersion: 'test',
          environment: Environment.dev,
        ),
      );

  @override
  Future<NimbusAnnouncement?> fetchCurrentAnnouncement({required String platform, required String language}) async {
    return null;
  }
}
