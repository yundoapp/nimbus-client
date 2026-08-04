import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/route_history/model/nimbus_route_history.dart';
import 'package:hiddify/features/nimbus/route_history/widget/nimbus_route_history_page.dart';

void main() {
  test('route history uses the shared acceleration and direct access icons', () {
    expect(nimbusRouteHistoryDecisionIcon(NimbusRouteDecision.accelerated), Icons.rocket_launch_rounded);
    expect(nimbusRouteHistoryDecisionIcon(NimbusRouteDecision.direct), Icons.language_rounded);
  });
}
