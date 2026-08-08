import 'package:flutter/material.dart';
// flutter_test is provided by the Flutter test runner in this fork.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_auth_page.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_auth_validation.dart';
import 'package:hiddify/gen/translations_zh_CN.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _TestNimbusAuthController extends NimbusAuthController {
  @override
  NimbusAuthState build() => const NimbusAuthState.unauthenticated();
}

void main() {
  testWidgets('registration shows username and password requirements', (tester) async {
    final t = TranslationsZhCn();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => t),
          nimbusAuthControllerProvider.overrideWith(_TestNimbusAuthController.new),
        ],
        child: const MaterialApp(home: NimbusAuthPage(initialMode: NimbusAuthMode.register)),
      ),
    );
    await tester.pump();

    expect(find.text(t.nimbus.auth.usernameRequirements), findsOneWidget);
    expect(find.text(t.nimbus.auth.passwordRequirements), findsOneWidget);
    expect(find.text('4-32 位，仅支持字母和数字'), findsOneWidget);
    expect(find.text('至少 8 位，需同时包含大写字母、小写字母、数字和特殊字符；最多 72 字节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login keeps registration-only requirements hidden', (tester) async {
    final t = Translations();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => t),
          nimbusAuthControllerProvider.overrideWith(_TestNimbusAuthController.new),
        ],
        child: const MaterialApp(home: NimbusAuthPage(initialMode: NimbusAuthMode.login)),
      ),
    );
    await tester.pump();

    expect(find.text(t.nimbus.auth.usernameRequirements), findsNothing);
    expect(find.text(t.nimbus.auth.passwordRequirements), findsNothing);
  });

  test('registration rejects underscores but login remains compatible with legacy usernames', () {
    final t = TranslationsZhCn();

    expect(validateNimbusUsername(t, 'new_user', allowLegacyUnderscore: false), t.nimbus.auth.usernameInvalid);
    expect(validateNimbusUsername(t, 'newuser', allowLegacyUnderscore: false), isNull);
    expect(validateNimbusUsername(t, 'old_user', allowLegacyUnderscore: true), isNull);
  });

  test('new passwords require all four character classes', () {
    final t = TranslationsZhCn();

    expect(validateNimbusNewPassword(t, 'Aa1!aaaa'), isNull);
    expect(validateNimbusNewPassword(t, 'Aa1!aaa'), t.nimbus.auth.passwordTooShort);
    expect(validateNimbusNewPassword(t, 'aa1!aaaa'), t.nimbus.auth.passwordNeedsUppercase);
    expect(validateNimbusNewPassword(t, 'AA1!AAAA'), t.nimbus.auth.passwordNeedsLowercase);
    expect(validateNimbusNewPassword(t, 'Aa!aaaaa'), t.nimbus.auth.passwordNeedsNumber);
    expect(validateNimbusNewPassword(t, 'Aa1aaaaa'), t.nimbus.auth.passwordNeedsSymbol);
    expect(validateNimbusNewPassword(t, 'Aa1 aaaa'), t.nimbus.auth.passwordNeedsSymbol);
  });
}
