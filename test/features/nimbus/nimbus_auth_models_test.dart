import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

void main() {
  test('解析套餐名称、有效期和月额度', () {
    final subscription = NimbusSubscription.fromJson({
      'status': 'active',
      'planName': '1 个月',
      'startedAt': '2026-07-08T01:47:05.633Z',
      'expiresAt': '2026-08-08T01:47:05.633Z',
      'quotaBytes': 107374182400,
    });

    expect(subscription.planName, '1 个月');
    expect(subscription.startedAt, DateTime.parse('2026-07-08T01:47:05.633Z').toLocal());
    expect(subscription.expiresAt, DateTime.parse('2026-08-08T01:47:05.633Z').toLocal());
    expect(subscription.quotaBytes, 107374182400);
  });

  group('节点地区名称', () {
    const location = NimbusLocation(code: 'jp', displayName: '日本', displayNames: {'zh-CN': '日本', 'en': 'Japan'});

    test('中文使用英文名和中文名', () {
      expect(location.displayNameForLanguage('zh'), 'Japan · 日本');
      expect(location.displayNameForLanguage('zh-CN'), 'Japan · 日本');
    });

    test('非中文只使用英文名', () {
      expect(location.displayNameForLanguage('en'), 'Japan');
      expect(location.displayNameForLanguage('fr'), 'Japan');
    });
  });
}
