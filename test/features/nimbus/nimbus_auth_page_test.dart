import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_auth_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('注册已完成但会话未保存时进入首页并显示准确提示', (tester) async {
    _SuccessfulRegistrationWithStorageWarningController.registrationCalls = 0;
    final router = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (_, _) => const NimbusAuthPage(initialMode: NimbusAuthMode.register),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('测试首页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
          environmentProvider.overrideWith((ref) => Environment.prod),
          nimbusAuthControllerProvider.overrideWith(_SuccessfulRegistrationWithStorageWarningController.new),
        ],
        child: _TestApp(router: router),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'tester');
    await tester.enterText(fields.at(1), 'Password!1');
    await tester.enterText(fields.at(2), 'Password!1');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();

    expect(_SuccessfulRegistrationWithStorageWarningController.registrationCalls, 1);
    expect(find.text('测试首页'), findsOneWidget);
    expect(find.text('账号已登录，但未能保存登录状态；下次打开应用时需要重新登录。'), findsOneWidget);
  });

  testWidgets('临时密码登录后要求设置新密码并自动进入首页', (tester) async {
    _PasswordResetRequiredController.reset();
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => const NimbusAuthPage(initialMode: NimbusAuthMode.login),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('测试首页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
          environmentProvider.overrideWith((ref) => Environment.prod),
          nimbusAuthControllerProvider.overrideWith(_PasswordResetRequiredController.new),
        ],
        child: _TestApp(router: router),
      ),
    );
    await tester.pumpAndSettle();

    var fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'tester');
    await tester.enterText(fields.at(1), 'Temporary!1');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('设置新密码'), findsOneWidget);
    expect(find.text('临时密码'), findsOneWidget);
    fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(2), 'Changed!123');
    await tester.enterText(fields.at(3), 'Changed!123');
    await tester.tap(find.text('设置新密码并登录'));
    await tester.pumpAndSettle();

    expect(_PasswordResetRequiredController.loginCalls, 1);
    expect(_PasswordResetRequiredController.completeCalls, 1);
    expect(_PasswordResetRequiredController.completedUsername, 'tester');
    expect(_PasswordResetRequiredController.completedTemporaryPassword, 'Temporary!1');
    expect(_PasswordResetRequiredController.completedNewPassword, 'Changed!123');
    expect(find.text('测试首页'), findsOneWidget);
  });
}

class _TestApp extends ConsumerWidget {
  const _TestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    return translations.hasValue
        ? MaterialApp.router(routerConfig: router)
        : const MaterialApp(home: CircularProgressIndicator());
  }
}

class _SuccessfulRegistrationWithStorageWarningController extends NimbusAuthController {
  static int registrationCalls = 0;

  static const session = NimbusAuthSession(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
    user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
    device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'macos', deviceName: 'Test Mac'),
  );

  @override
  NimbusAuthState build() => const NimbusAuthState.unauthenticated();

  @override
  Future<bool> register({required String username, required String password, required bool acceptedTerms}) async {
    registrationCalls += 1;
    state = const NimbusAuthState.authenticated(session: session, errorMessage: '账号已登录，但未能保存登录状态；下次打开应用时需要重新登录。');
    return true;
  }
}

class _PasswordResetRequiredController extends NimbusAuthController {
  static int loginCalls = 0;
  static int completeCalls = 0;
  static String? completedUsername;
  static String? completedTemporaryPassword;
  static String? completedNewPassword;

  static const session = NimbusAuthSession(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
    user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
    device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'macos', deviceName: 'Test Mac'),
  );

  static void reset() {
    loginCalls = 0;
    completeCalls = 0;
    completedUsername = null;
    completedTemporaryPassword = null;
    completedNewPassword = null;
  }

  @override
  NimbusAuthState build() => const NimbusAuthState.unauthenticated();

  @override
  Future<NimbusLoginResult> login({required String username, required String password}) async {
    loginCalls += 1;
    return NimbusLoginResult.passwordChangeRequired;
  }

  @override
  Future<bool> completePasswordReset({
    required String username,
    required String temporaryPassword,
    required String newPassword,
  }) async {
    completeCalls += 1;
    completedUsername = username;
    completedTemporaryPassword = temporaryPassword;
    completedNewPassword = newPassword;
    state = const NimbusAuthState.authenticated(session: session);
    return true;
  }
}
