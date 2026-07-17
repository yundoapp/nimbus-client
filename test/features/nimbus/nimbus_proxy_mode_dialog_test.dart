import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_proxy_mode_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('加速模式弹窗在 ${themeMode.name} 模式完整展示并保留交互上下文', (tester) async {
      SharedPreferences.setMockInitialValues({
        'nimbus_proxy_mode': 'auto',
        'nimbus_custom_website_access_enabled': true,
      });
      final preferences = await SharedPreferences.getInstance();
      var manageCount = 0;
      var applyCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
            sharedPreferencesProvider.overrideWith((ref) => preferences),
            connectionNotifierProvider.overrideWith(_FakeConnectionNotifier.new),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeMode,
            home: _TestPage(onManage: () async => manageCount++, onApply: () async => applyCount++),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('打开加速模式'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('加速模式'), findsOneWidget);
      expect(find.text('自动模式'), findsOneWidget);
      expect(find.text('自定义网站访问'), findsOneWidget);
      expect(find.text('已设置 2 个网站'), findsOneWidget);
      expect(find.text('管理'), findsOneWidget);
      expect(find.text('全局模式'), findsOneWidget);
      expect(find.text('更改将在下次加速时生效'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('已设置 2 个网站'), findsOneWidget);
      expect(applyCount, 1);

      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      expect(manageCount, 1);

      await tester.tap(find.text('全局模式'));
      await tester.pumpAndSettle();

      expect(find.text('加速模式'), findsOneWidget);
      expect(find.text('仅在自动模式下生效'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
      expect(applyCount, 2);
      expect(tester.takeException(), isNull);
    });
  }
}

class _FakeConnectionNotifier extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const ConnectionStatus.disconnected());
}

class _TestPage extends ConsumerWidget {
  const _TestPage({required this.onManage, required this.onApply});

  final Future<void> Function() onManage;
  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(sharedPreferencesProvider);
    final translations = ref.watch(translationsProvider);
    return Scaffold(
      body: preferences.hasValue && translations.hasValue
          ? FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => NimbusProxyModeDialog(
                  loadConfiguredSiteCount: () async => 2,
                  openCustomWebsites: (_) => onManage(),
                  applyChanges: onApply,
                ),
              ),
              child: const Text('打开加速模式'),
            )
          : const CircularProgressIndicator(),
    );
  }
}
