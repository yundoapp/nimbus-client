import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';

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

Widget nimbusLocationFlag(NimbusLocation location, {double size = 30}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final countryCode = nimbusLocationCountryCode(location.code);
      final flag = countryCode == null
          ? Icon(Icons.public_rounded, size: size, color: theme.colorScheme.primary)
          : IPCountryFlag(countryCode: countryCode, size: size);
      return Container(
        width: size + 12,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72)),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: flag,
      );
    },
  );
}
