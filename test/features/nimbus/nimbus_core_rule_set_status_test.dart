import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/rules/data/nimbus_core_rule_set_status.dart';

void main() {
  test('parses core rule-set timestamps without inventing missing values', () {
    final statuses = parseNimbusCoreRuleSetStatusResponse({
      'providers': [
        {'name': 'geosite-cn', 'updated_at': '2026-08-07T03:00:00Z'},
        {'name': 'geosite-gfw'},
        {'name': '  '},
      ],
    });

    expect(statuses['geosite-cn'], DateTime.utc(2026, 8, 7, 3));
    expect(statuses.containsKey('geosite-gfw'), isTrue);
    expect(statuses['geosite-gfw'], isNull);
    expect(statuses.length, 2);
  });

  test('returns no status for an incompatible core response', () {
    expect(parseNimbusCoreRuleSetStatusResponse(const {'providers': []}), isEmpty);
    expect(parseNimbusCoreRuleSetStatusResponse(const {'rules': []}), isEmpty);
    expect(parseNimbusCoreRuleSetStatusResponse(null), isEmpty);
  });
}
