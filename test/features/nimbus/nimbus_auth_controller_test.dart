import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_session_store.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('账号创建成功后会话持久化失败仍保持当前登录态', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessionStore = _FailingNimbusSessionStore();
    final repository = _FakeNimbusAuthRepository(preferences, sessionStore);
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        nimbusAuthRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(translationsProvider.future);
    container.read(nimbusAuthControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final success = await container
        .read(nimbusAuthControllerProvider.notifier)
        .register(username: 'tester', password: 'Password!1', acceptedTerms: true);
    final state = container.read(nimbusAuthControllerProvider);

    expect(success, isTrue);
    expect(sessionStore.writeAttempts, 1);
    expect(state.isAuthenticated, isTrue);
    expect(state.session?.user.username, 'tester');
    expect(state.me?.user.username, 'tester');
    expect(state.errorMessage, '账号已登录，但未能保存登录状态；下次打开应用时需要重新登录。');

    container.read(nimbusAuthControllerProvider.notifier).clearError();
    expect(container.read(nimbusAuthControllerProvider).errorMessage, isNull);
    expect(container.read(nimbusAuthControllerProvider).isAuthenticated, isTrue);
  });

  test('访问令牌过期且会话持久化失败时使用内存刷新令牌保持登录', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessionStore = _FailingNimbusSessionStore();
    final repository = _FakeNimbusAuthRepository(preferences, sessionStore);
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        nimbusAuthRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(translationsProvider.future);
    container.read(nimbusAuthControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await container
        .read(nimbusAuthControllerProvider.notifier)
        .register(username: 'tester', password: 'Password!1', acceptedTerms: true);

    repository.expireInitialAccessToken = true;
    await container.read(nimbusAuthControllerProvider.notifier).refreshMe();
    final state = container.read(nimbusAuthControllerProvider);

    expect(repository.refreshAttempts, 1);
    expect(sessionStore.writeAttempts, 2);
    expect(state.isAuthenticated, isTrue);
    expect(state.session?.accessToken, 'refreshed-access-token');
    expect(state.session?.refreshToken, 'refreshed-refresh-token');
    expect(state.errorMessage, '账号已登录，但未能保存登录状态；下次打开应用时需要重新登录。');
  });

  test('并发鉴权失败只轮换一次刷新令牌', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessionStore = _FailingNimbusSessionStore();
    final repository = _FakeNimbusAuthRepository(preferences, sessionStore)
      ..refreshDelay = const Duration(milliseconds: 20);
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        nimbusAuthRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(translationsProvider.future);
    container.read(nimbusAuthControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await container
        .read(nimbusAuthControllerProvider.notifier)
        .register(username: 'tester', password: 'Password!1', acceptedTerms: true);
    final rejectedSession = container.read(nimbusAuthControllerProvider).session!;

    final results = await Future.wait([
      container.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(rejectedSession),
      container.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(rejectedSession),
    ]);

    expect(results, everyElement(isTrue));
    expect(repository.refreshAttempts, 1);
    expect(container.read(nimbusAuthControllerProvider).session?.accessToken, 'refreshed-access-token');
  });

  test('服务端明确拒绝刷新令牌时才退出登录', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessionStore = _FailingNimbusSessionStore();
    final repository = _FakeNimbusAuthRepository(preferences, sessionStore);
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        nimbusAuthRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(translationsProvider.future);
    container.read(nimbusAuthControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await container
        .read(nimbusAuthControllerProvider.notifier)
        .register(username: 'tester', password: 'Password!1', acceptedTerms: true);

    repository.expireInitialAccessToken = true;
    repository.rejectRefreshToken = true;
    await container.read(nimbusAuthControllerProvider.notifier).refreshMe();

    expect(repository.refreshAttempts, 1);
    expect(sessionStore.deleteAttempts, 1);
    expect(container.read(nimbusAuthControllerProvider).isAuthenticated, isFalse);
  });

  test('刷新请求暂时失败时保留当前内存登录态', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessionStore = _FailingNimbusSessionStore();
    final repository = _FakeNimbusAuthRepository(preferences, sessionStore);
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        nimbusAuthRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(translationsProvider.future);
    container.read(nimbusAuthControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await container
        .read(nimbusAuthControllerProvider.notifier)
        .register(username: 'tester', password: 'Password!1', acceptedTerms: true);

    repository.expireInitialAccessToken = true;
    repository.failRefreshTemporarily = true;
    await container.read(nimbusAuthControllerProvider.notifier).refreshMe();
    final state = container.read(nimbusAuthControllerProvider);

    expect(repository.refreshAttempts, 1);
    expect(state.isAuthenticated, isTrue);
    expect(state.session?.refreshToken, 'test-refresh-token');
  });
}

class _FailingNimbusSessionStore implements NimbusSessionStore {
  int deleteAttempts = 0;
  int writeAttempts = 0;

  @override
  Future<void> delete() async {
    deleteAttempts += 1;
  }

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) {
    writeAttempts += 1;
    return Future<void>.error(PlatformException(code: 'secure_session_keychain_failed', details: -34018));
  }
}

class _FakeNimbusAuthRepository extends NimbusAuthRepository {
  _FakeNimbusAuthRepository(SharedPreferences preferences, NimbusSessionStore sessionStore)
    : super(
        preferences: preferences,
        appInfo: const AppInfoEntity(
          name: 'Yundo',
          version: '1.0.0',
          buildNumber: '10000',
          release: Release.general,
          operatingSystem: 'macos',
          operatingSystemVersion: 'test',
          environment: Environment.prod,
        ),
        sessionStore: sessionStore,
      );

  bool expireInitialAccessToken = false;
  bool failRefreshTemporarily = false;
  bool rejectRefreshToken = false;
  Duration refreshDelay = Duration.zero;
  int refreshAttempts = 0;

  static const session = NimbusAuthSession(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
    user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
    device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'macos', deviceName: 'Test Mac'),
  );

  @override
  Future<NimbusAuthSession?> readSession() async => null;

  @override
  Future<NimbusAuthSession> register({
    required String username,
    required String password,
    required bool acceptedTerms,
  }) async => session;

  @override
  Future<NimbusMe> fetchMe(String accessToken) async {
    if (expireInitialAccessToken && accessToken == session.accessToken) {
      throw _unauthorized('AUTH_INVALID_TOKEN');
    }
    return const NimbusMe(
      user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
      subscription: NimbusSubscription(status: 'none'),
      devices: NimbusDeviceQuota(used: 1, limit: 3),
      rules: NimbusRulesInfo(),
    );
  }

  @override
  Future<NimbusAuthSession> refresh(NimbusAuthSession session) async {
    refreshAttempts += 1;
    if (refreshDelay > Duration.zero) {
      await Future<void>.delayed(refreshDelay);
    }
    if (rejectRefreshToken) {
      throw _unauthorized('AUTH_INVALID_REFRESH_TOKEN');
    }
    if (failRefreshTemporarily) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
        type: DioExceptionType.connectionError,
      );
    }
    return session.copyWith(accessToken: 'refreshed-access-token', refreshToken: 'refreshed-refresh-token');
  }

  DioException _unauthorized(String code) {
    final request = RequestOptions(path: '/api/v1/auth');
    return DioException(
      requestOptions: request,
      response: Response<Map<String, dynamic>>(requestOptions: request, statusCode: 401, data: {'code': code}),
      type: DioExceptionType.badResponse,
    );
  }
}
