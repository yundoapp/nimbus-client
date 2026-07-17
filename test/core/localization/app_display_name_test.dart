import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/environment.dart';

void main() {
  test('简体中文开发版和正式版使用不同显示名称', () async {
    final translations = await AppLocale.zhCn.build();

    expect(appDisplayName(translations, Environment.dev), 'Yundo · 云渡开发版');
    expect(appDisplayName(translations, Environment.prod), 'Yundo · 云渡');
  });

  test('英文开发版和正式版使用不同显示名称', () {
    final translations = AppLocale.en.buildSync();

    expect(appDisplayName(translations, Environment.dev), 'Yundo Dev');
    expect(appDisplayName(translations, Environment.prod), 'Yundo');
  });
}
