import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily, {TargetPlatform? platform}) : platform = platform ?? defaultTargetPlatform;

  final AppThemeMode mode;
  final String fontFamily;
  final TargetPlatform platform;

  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    final ColorScheme scheme = lightColorScheme ?? ColorScheme.fromSeed(seedColor: const Color(0xFF293CA0));
    return _buildTheme(scheme: scheme, extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light});
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    final ColorScheme scheme =
        darkColorScheme ?? ColorScheme.fromSeed(seedColor: const Color(0xFF293CA0), brightness: Brightness.dark);
    return _buildTheme(
      scheme: scheme,
      scaffoldBackgroundColor: mode.trueBlack ? Colors.black : scheme.surface,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData _buildTheme({
    required ColorScheme scheme,
    Color? scaffoldBackgroundColor,
    required Set<ThemeExtension<dynamic>> extensions,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      extensions: extensions,
    );
    return base.copyWith(textTheme: _comfortableTextTheme(base.textTheme));
  }

  TextTheme _comfortableTextTheme(TextTheme base) {
    final isMobile = platform == TargetPlatform.iOS || platform == TargetPlatform.android;
    return base.copyWith(
      labelSmall: base.labelSmall?.copyWith(fontSize: isMobile ? 13 : 12, height: 1.25),
      labelMedium: base.labelMedium?.copyWith(fontSize: isMobile ? 14 : 13, height: 1.25),
      labelLarge: base.labelLarge?.copyWith(fontSize: isMobile ? 15 : 14, height: 1.25),
      bodySmall: base.bodySmall?.copyWith(fontSize: isMobile ? 14 : 13, height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: isMobile ? 16 : 15, height: 1.4),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: isMobile ? 17 : 16, height: 1.45),
      titleSmall: base.titleSmall?.copyWith(fontSize: isMobile ? 17 : 15, height: 1.3),
      titleMedium: base.titleMedium?.copyWith(fontSize: isMobile ? 19 : 17, height: 1.3),
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);
    // final def = CupertinoThemeData(brightness: Brightness.dark);

    // return def;
    final defaultMaterialTheme = isDark ? darkTheme(darkColorScheme) : lightTheme(lightColorScheme);
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
