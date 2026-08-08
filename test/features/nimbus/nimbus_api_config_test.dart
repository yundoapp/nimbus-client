// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';

void main() {
  test('defaults mobile builds to the production API', () {
    expect(nimbusApiBaseUrl, nimbusProductionApiBaseUrl);
    expect(nimbusApiBaseUrl, startsWith('https://api.yundo.app/'));
  });
}
