import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/constants.dart';

void main() {
  test('开源和法律入口指向公开 fork 的独立页面', () {
    expect(Constants.githubUrl, 'https://github.com/wintion/nimbus-client/tree/develop');
    expect(Constants.licenseUrl, 'https://github.com/wintion/nimbus-client/blob/develop/LICENSE.md');
    expect(
      Constants.privacyPolicyUrl,
      'https://github.com/wintion/nimbus-client/blob/develop/docs/legal/privacy-policy.md',
    );
    expect(
      Constants.termsAndConditionsUrl,
      'https://github.com/wintion/nimbus-client/blob/develop/docs/legal/terms-of-service.md',
    );
  });
}
