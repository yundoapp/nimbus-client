import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  final translations = Translations();

  test('desktop navigation destinations match every desktop shell branch', () {
    final actions = shellRouteActions(translations, false, false);
    expect(actions, hasLength(3));
    expect(actions.last.title, translations.nimbus.routeHistory.menuTitle);
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
  });
}
