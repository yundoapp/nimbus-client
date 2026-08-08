// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';

void main() {
  test('uses the development API for local debug tests', () {
    expect(nimbusApiBaseUrl, nimbusDevelopmentApiBaseUrl);
    expect(nimbusApiBaseUrl, startsWith('http://127.0.0.1:4000/'));
  });
}
