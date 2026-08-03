import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  final translations = Translations();

  test('desktop navigation destinations match every desktop shell branch', () {
    final actions = shellRouteActions(translations, false, false);
    expect(actions, hasLength(3));
    expect(actions.map((action) => action.title), [
      translations.pages.home.title,
      translations.nimbus.routeHistory.menuTitle,
      translations.pages.settings.title,
    ]);
    expect(shellRouteActions(translations, true, false), hasLength(3));
  });

  test('mobile navigation keeps only home and settings destinations', () {
    expect(shellRouteActions(translations, false, true), hasLength(2));
    expect(shellRouteActions(translations, true, true), hasLength(2));
  });

  test('route history entry uses the short menu title in settings', () {
    final settingsPage = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();

    expect(settingsPage, contains('title: Text(t.nimbus.routeHistory.menuTitle)'));
    expect(settingsPage, isNot(contains('title: Text(t.nimbus.routeHistory.title)')));
    expect(settingsPage, isNot(contains('title: Text(t.pages.logs.title)')));
  });

  test('desktop shell branches follow home history settings order', () {
    final routingConfig = File('lib/core/router/go_router/routing_config_notifier.dart').readAsStringSync();
    final homeIndex = routingConfig.indexOf("name: 'home'");
    final historyIndex = routingConfig.indexOf("name: 'routeHistory'");
    final settingsIndex = routingConfig.indexOf("name: 'settings'");

    expect(homeIndex, greaterThanOrEqualTo(0));
    expect(historyIndex, greaterThan(homeIndex));
    expect(settingsIndex, greaterThan(historyIndex));
  });
}
