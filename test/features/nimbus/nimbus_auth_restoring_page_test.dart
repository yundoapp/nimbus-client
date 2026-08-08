import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_auth_restoring_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('shows the real app icon and automatic sign-in state without login fields', (tester) async {
    final t = Translations();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => t),
          environmentProvider.overrideWithValue(Environment.dev),
        ],
        child: const MaterialApp(home: NimbusAuthRestoringPage()),
      ),
    );

    expect(find.byKey(const Key('nimbusAuthRestoringLogo')), findsOneWidget);
    expect(find.byKey(const Key('nimbusAuthRestoringProgress')), findsOneWidget);
    final logo = tester.widget<Image>(find.byKey(const Key('nimbusAuthRestoringLogo')));
    expect(logo.image, isA<AssetImage>());
    expect((logo.image as AssetImage).assetName, 'assets/images/app_icon.png');
    expect(find.text(t.common.devAppTitle), findsOneWidget);
    expect(find.text(t.nimbus.auth.signingIn), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
