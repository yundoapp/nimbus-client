import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_route_preferences_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('新增网站完成应用前保持原列表和输入内容', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final reapplyGate = Completer<void>();
    final repository = _FakeNimbusAuthRepository(sharedPreferences);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
          nimbusAuthRepositoryProvider.overrideWithValue(repository),
          nimbusAuthControllerProvider.overrideWith(_FakeNimbusAuthController.new),
          connectionNotifierProvider.overrideWith(_FakeConnectionNotifier.new),
          nimbusConnectionControllerProvider.overrideWith(() => _FakeNimbusConnectionController(reapplyGate.future)),
        ],
        child: const MaterialApp(home: _TestPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('打开自定义网站'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(find.byType(ListView)).semanticChildCount, 1);

    await tester.enterText(find.byType(TextField), 'rawya.ai');
    final addButton = find.ancestor(
      of: find.text('添加'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump();

    expect(find.descendant(of: addButton, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(tester.widget<ListView>(find.byType(ListView)).semanticChildCount, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'rawya.ai');

    reapplyGate.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<ListView>(find.byType(ListView)).semanticChildCount, 2);
    expect(find.text('rawya.ai'), findsOneWidget);
    expect(find.descendant(of: addButton, matching: find.byType(CircularProgressIndicator)), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
  });
}

class _TestPage extends ConsumerWidget {
  const _TestPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    return Scaffold(
      body: translations.hasValue
          ? FilledButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const NimbusRoutePreferencesDialog()),
              child: const Text('打开自定义网站'),
            )
          : const CircularProgressIndicator(),
    );
  }
}

class _FakeNimbusAuthController extends NimbusAuthController {
  @override
  NimbusAuthState build() => const NimbusAuthState.authenticated(
    session: NimbusAuthSession(
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
      device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'macos', deviceName: 'Test Mac'),
    ),
  );

  @override
  Future<void> restore() async {}
}

class _FakeConnectionNotifier extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const ConnectionStatus.disconnected());
}

class _FakeNimbusConnectionController extends NimbusConnectionController {
  _FakeNimbusConnectionController(this.reapplyFuture);

  final Future<void> reapplyFuture;

  @override
  NimbusConnectionState build() => const NimbusConnectionState();

  @override
  Future<bool> reapplyIfConnected({bool userRulesOnly = false}) async {
    await reapplyFuture;
    return true;
  }
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

  final List<NimbusRoutePreference> _items = [
    NimbusRoutePreference(
      id: 'existing-id',
      type: 'direct',
      targetType: 'domain',
      value: 'existing.test',
      createdAt: DateTime(2026, 7, 16, 19),
    ),
  ];

  @override
  Future<NimbusRoutePreferencesList> fetchRoutePreferences(NimbusAuthSession session) async {
    return NimbusRoutePreferencesList(limit: 100, items: List.unmodifiable(_items));
  }

  @override
  Future<NimbusRoutePreference> createRoutePreference({
    required NimbusAuthSession session,
    required String type,
    required String input,
  }) async {
    final preference = NimbusRoutePreference(
      id: 'created-id',
      type: type,
      targetType: 'domain',
      value: input,
      createdAt: DateTime(2026, 7, 16, 19, 14),
    );
    _items.insert(0, preference);
    return preference;
  }
}
