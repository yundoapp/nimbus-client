import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  test('Chinese locale names distinguish simplified and traditional Chinese', () {
    expect(AppLocale.zhCn.localeName, '简体中文');
    expect(AppLocale.zhTw.localeName, '繁体中文');
  });
}
