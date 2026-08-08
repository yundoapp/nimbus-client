import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/constants.dart';

void main() {
  test('Yundo legal links never fall back to Hiddify', () {
    final legalUrls = [Constants.termsAndConditionsUrl, Constants.privacyPolicyUrl];

    for (final legalUrl in legalUrls) {
      final uri = Uri.parse(legalUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, startsWith('/yundoapp/nimbus-client/blob/'));
      expect(uri.path, contains('/docs/legal/'));
      expect(legalUrl, isNot(contains('hiddify.com')));
    }
  });
}
