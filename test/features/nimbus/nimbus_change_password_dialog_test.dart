import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_change_password_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('修改密码弹窗在浅色模式展示完整字段', (tester) async {
    final repository = await _pumpDialog(tester, ThemeMode.light);

    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('当前密码'), findsOneWidget);
    expect(find.text('新密码'), findsOneWidget);
    expect(find.text('确认新密码'), findsOneWidget);
    expect(repository.changeCalls, 0);
  });

  testWidgets('修改密码弹窗在深色模式提交后保持当前登录态', (tester) async {
    final repository = await _pumpDialog(tester, ThemeMode.dark);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Current!123');
    await tester.enterText(fields.at(1), 'Changed!123');
    await tester.enterText(fields.at(2), 'Changed!123');
    await tester.tap(find.text('确认修改'));
    await tester.pumpAndSettle();

    expect(repository.changeCalls, 1);
    expect(repository.currentPassword, 'Current!123');
    expect(repository.newPassword, 'Changed!123');
    expect(find.text('密码已修改。'), findsOneWidget);
    expect(find.byType(NimbusChangePasswordDialog), findsNothing);
  });
}

Future<_FakeNimbusAuthRepository> _pumpDialog(WidgetTester tester, ThemeMode themeMode) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = _FakeNimbusAuthRepository(preferences);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        nimbusAuthRepositoryProvider.overrideWithValue(repository),
        nimbusAuthControllerProvider.overrideWith(_AuthenticatedController.new),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final translations = ref.watch(translationsProvider);
          return translations.hasValue
              ? MaterialApp(
                  theme: ThemeData.light(),
                  darkTheme: ThemeData.dark(),
                  themeMode: themeMode,
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => FilledButton(
                        onPressed: () =>
                            showDialog<void>(context: context, builder: (_) => const NimbusChangePasswordDialog()),
                        child: const Text('打开'),
                      ),
                    ),
                  ),
                )
              : const MaterialApp(home: CircularProgressIndicator());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return repository;
}

class _AuthenticatedController extends NimbusAuthController {
  @override
  NimbusAuthState build() => const NimbusAuthState.authenticated(session: _session);
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
          environment: Environment.prod,
        ),
      );

  int changeCalls = 0;
  String? currentPassword;
  String? newPassword;

  @override
  Future<void> changePassword({
    required NimbusAuthSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    changeCalls += 1;
    this.currentPassword = currentPassword;
    this.newPassword = newPassword;
  }
}

const _session = NimbusAuthSession(
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
  device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'macos', deviceName: 'Test Mac'),
);
