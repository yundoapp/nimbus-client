import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/mobile_orientation.dart';

void main() {
  test('mobile clients only allow the standard portrait orientation', () {
    expect(mobilePreferredOrientations, const [DeviceOrientation.portraitUp]);
  });
}
