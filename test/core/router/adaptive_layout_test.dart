import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  final translations = Translations();

  test('desktop navigation destinations match every desktop shell branch', () {
    final actions = shellRouteActions(translations, false, false);
    expect(actions, hasLength(4));
    expect(actions.map((action) => action.title), [
      translations.pages.home.title,
      translations.nimbus.routeHistory.menuTitle,
      translations.nimbus.rules.menuTitle,
      translations.pages.settings.title,
    ]);
    expect(actions[1].icon, Icons.rocket_launch_rounded);
    expect(shellRouteActions(translations, true, false), hasLength(4));
  });

  test('mobile navigation has the same four destinations as desktop', () {
    expect(shellRouteActions(translations, false, true), hasLength(4));
    expect(shellRouteActions(translations, true, true), hasLength(4));
  });

  test('route history is no longer duplicated inside settings', () {
    final settingsPage = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();

    expect(settingsPage, isNot(contains('routeHistory')));
    expect(settingsPage, isNot(contains('title: Text(t.pages.logs.title)')));
  });

  test('shell branches follow home history rules settings order', () {
    final routingConfig = File('lib/core/router/go_router/routing_config_notifier.dart').readAsStringSync();
    final homeIndex = routingConfig.indexOf("name: 'home'");
    final historyIndex = routingConfig.indexOf("name: 'routeHistory'");
    final rulesIndex = routingConfig.indexOf("name: 'rules'");
    final settingsIndex = routingConfig.indexOf("name: 'settings'");

    expect(homeIndex, greaterThanOrEqualTo(0));
    expect(historyIndex, greaterThan(homeIndex));
    expect(rulesIndex, greaterThan(historyIndex));
    expect(settingsIndex, greaterThan(rulesIndex));
  });

  test('authenticated users skip the legacy intro page', () {
    final routingConfig = File('lib/core/router/go_router/routing_config_notifier.dart').readAsStringSync();
    final authPage = File('lib/features/nimbus/auth/widget/nimbus_auth_page.dart').readAsStringSync();

    expect(routingConfig, isNot(contains("name: 'intro'")));
    expect(routingConfig, isNot(contains("'/intro")));
    expect(authPage, contains("context.go('/home')"));
  });

  test('settings no longer exposes the acceleration and access group', () {
    final settingsPage = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();

    expect(settingsPage, isNot(contains('accessSection')));
    expect(settingsPage, isNot(contains('NimbusRoutePreferencesDialog')));
  });
}
