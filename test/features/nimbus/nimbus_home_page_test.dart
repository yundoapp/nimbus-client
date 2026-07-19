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

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('tester'), findsOneWidget);
    expect(find.ancestor(of: find.text('tester'), matching: find.byType(SingleChildScrollView)), findsOneWidget);
    expect(find.text(_connectionError), findsOneWidget);
    final banner = tester.widget<Material>(find.byKey(const Key('home-connection-notice')));
    final colors = Theme.of(tester.element(find.byKey(const Key('home-connection-notice')))).colorScheme;
    final message = tester.widget<Text>(find.text(_connectionError));
    final closeButton = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close_rounded));
    expect(banner.color, colors.errorContainer.withValues(alpha: 0.64));
    expect(message.style?.color, colors.error);
    expect(message.style?.fontWeight, FontWeight.w500);
    expect(closeButton.constraints, const BoxConstraints.tightFor(width: 44, height: 44));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机竖屏首页先展示使用情况再展示套餐信息', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          nimbusAuthControllerProvider.overrideWith(_ActiveSubscriptionNimbusAuthController.new),
          nimbusAppVersionControllerProvider.overrideWith(_NoopNimbusAppVersionController.new),
          connectionNotifierProvider.overrideWith(_DisconnectedConnectionNotifier.new),
          nimbusConnectionControllerProvider.overrideWith(_ConnectionErrorController.new),
        ],
        child: MaterialApp(theme: ThemeData.light(), home: const _ReadyHomePage()),
      ),
    );

    await tester.pumpAndSettle();

    final usageTitle = find.text('使用情况');
    final planTitle = find.text('当前套餐');
    expect(usageTitle, findsOneWidget);
    expect(planTitle, findsOneWidget);
    expect(tester.getTopLeft(usageTitle).dy, lessThan(tester.getTopLeft(planTitle).dy));
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

class _ActiveSubscriptionNimbusAuthController extends NimbusAuthController {
  @override
  NimbusAuthState build() {
    return NimbusAuthState.authenticated(
      session: _session,
      me: NimbusMe(
        user: const NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
        subscription: NimbusSubscription(
          status: 'active',
          planName: '月度套餐',
          startedAt: DateTime(2026, 7, 8),
          expiresAt: DateTime(2026, 8, 8),
          quotaBytes: 100 * 1024 * 1024 * 1024,
          usedBytes: 3 * 1024 * 1024 * 1024,
          remainingBytes: 97 * 1024 * 1024 * 1024,
        ),
        devices: const NimbusDeviceQuota(used: 1, limit: 3),
        rules: const NimbusRulesInfo(),
      ),
      locations: const NimbusLocationsList(
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
