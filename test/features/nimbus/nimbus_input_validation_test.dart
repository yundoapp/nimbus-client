import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_input_validation.dart';

void main() {
  group('Nimbus rule target validation', () {
    test('normalizes domains, IPv4, IPv6, and CIDR targets', () {
      expect(normalizeNimbusRuleTarget(' WWW.Example.com ', 'domain'), 'www.example.com');
      expect(normalizeNimbusRuleTarget('1.1.1.1', 'ip'), '1.1.1.1');
      expect(normalizeNimbusRuleTarget('2001:DB8::1', 'ip'), '2001:db8::1');
      expect(normalizeNimbusRuleTarget('1.1.1.0/24', 'cidr'), '1.1.1.0/24');
      expect(normalizeNimbusRuleTarget('2001:db8::/48', 'cidr'), '2001:db8::/48');
    });

    test('rejects invalid target values and unsupported rule libraries', () {
      expect(normalizeNimbusRuleTarget('1.1.1.1/24', 'ip'), isNull);
      expect(normalizeNimbusRuleTarget('1.1.1.0/33', 'cidr'), isNull);
      expect(normalizeNimbusRuleTarget('geosite-cn', 'geosite'), isNull);
    });
  });
}
