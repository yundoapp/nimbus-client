import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_location_display.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_route_preferences_dialog.dart';

void main() {
  group('Nimbus location display', () {
    test('does not combine English and Chinese location names', () {
      const location = NimbusLocation(code: 'japan', displayName: '日本', displayNames: {'en': 'Japan', 'zh-CN': '日本'});

      expect(location.displayNameForLanguage('zh-CN'), '日本');
      expect(location.displayNameForLanguage('en'), 'Japan');
      expect(location.displayNameForLanguage('id'), 'Japan');
    });

    test('maps built-in locations to their country flag codes', () {
      expect(nimbusLocationCountryCode('hong_kong'), 'hk');
      expect(nimbusLocationCountryCode('japan'), 'jp');
      expect(nimbusLocationCountryCode('singapore'), 'sg');
      expect(nimbusLocationCountryCode('united_states'), 'us');
      expect(nimbusLocationCountryCode('auto'), isNull);
    });

    testWidgets('uses one icon size without a decorative card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              nimbusLocationFlag(const NimbusLocation(code: 'auto', displayName: '')),
              nimbusLocationFlag(const NimbusLocation(code: 'singapore', displayName: 'Singapore')),
            ],
          ),
        ),
      );

      final iconSizes = tester.getSize(find.byType(SizedBox).at(0));
      final flagSize = tester.getSize(find.byType(CircleFlag));

      expect(iconSizes, const Size.square(nimbusLocationIconSize));
      expect(flagSize, const Size.square(nimbusLocationIconSize));
      expect(find.byType(DecoratedBox), findsNothing);
    });
  });

  test('uses a target-specific rule placeholder', () {
    final translations = Translations();

    expect(nimbusRouteTargetHint(translations, 'domain'), contains('domain'));
    expect(nimbusRouteTargetHint(translations, 'ip'), contains('IP address'));
    expect(nimbusRouteTargetHint(translations, 'cidr'), contains('CIDR'));
  });
}
