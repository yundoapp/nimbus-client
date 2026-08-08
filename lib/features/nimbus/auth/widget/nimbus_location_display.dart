import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

const nimbusLocationIconSize = 28.0;

String nimbusLocationDisplayName(Translations translations, NimbusLocation location, String languageCode) {
  if (location.code == 'auto') return translations.nimbus.home.locationAuto;

  final builtInName = switch (location.code) {
    'hk' || 'hong_kong' || 'hong-kong' => translations.nimbus.home.locationNames.hongKong,
    'jp' || 'japan' => translations.nimbus.home.locationNames.japan,
    'sg' || 'singapore' => translations.nimbus.home.locationNames.singapore,
    'us' || 'united_states' || 'united-states' => translations.nimbus.home.locationNames.unitedStates,
    _ => null,
  };
  return builtInName ?? location.displayNameForLanguage(languageCode);
}

String? nimbusLocationCountryCode(String locationCode) => switch (locationCode) {
  'hk' || 'hong_kong' || 'hong-kong' => 'hk',
  'jp' || 'japan' => 'jp',
  'sg' || 'singapore' => 'sg',
  'us' || 'united_states' || 'united-states' => 'us',
  _ => null,
};

Widget nimbusLocationFlag(NimbusLocation location, {double size = nimbusLocationIconSize}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final countryCode = nimbusLocationCountryCode(location.code);
      return ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: countryCode == null
              ? Icon(Icons.public_rounded, size: size, color: theme.colorScheme.primary)
              : CircleFlag(
                  countryCode,
                  size: size,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.28)),
                ),
        ),
      );
    },
  );
}
