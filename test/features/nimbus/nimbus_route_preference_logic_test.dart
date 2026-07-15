import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_route_preference_logic.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';

void main() {
  const existing = NimbusRoutePreference(
    id: 'preference-id',
    type: 'accelerate',
    targetType: 'domain',
    value: 'openai.com',
    createdAt: null,
  );

  test('同类重复不会创建新规则', () {
    final result = resolveNimbusRoutePreference(
      items: const [existing],
      limit: 100,
      domain: 'openai.com',
      requestedType: 'accelerate',
    );
    expect(result.decision, NimbusRoutePreferenceDecision.duplicate);
    expect(result.existing, same(existing));
  });

  test('跨分类重复进入切换确认', () {
    final result = resolveNimbusRoutePreference(
      items: const [existing],
      limit: 100,
      domain: 'openai.com',
      requestedType: 'direct',
    );
    expect(result.decision, NimbusRoutePreferenceDecision.switchType);
    expect(result.existing, same(existing));
  });

  test('达到上限后仍允许识别并切换已有规则', () {
    final result = resolveNimbusRoutePreference(
      items: const [existing],
      limit: 1,
      domain: 'openai.com',
      requestedType: 'direct',
    );
    expect(result.decision, NimbusRoutePreferenceDecision.switchType);
  });

  test('达到上限后拒绝新增域名', () {
    final result = resolveNimbusRoutePreference(
      items: const [existing],
      limit: 1,
      domain: 'example.com',
      requestedType: 'direct',
    );
    expect(result.decision, NimbusRoutePreferenceDecision.limitReached);
  });

  group('自定义网站规则启用状态', () {
    const rules = [NimbusRulePackageItem(pattern: 'openai.com', patternType: 'domain', action: 'proxy')];

    test('自动模式且开关开启时应用用户规则', () {
      final result = selectActiveNimbusUserRules(
        isAutomaticMode: true,
        customWebsiteAccessEnabled: true,
        userRules: rules,
      );
      expect(result, same(rules));
    });

    test('自动模式关闭开关时保留数据但不应用规则', () {
      final result = selectActiveNimbusUserRules(
        isAutomaticMode: true,
        customWebsiteAccessEnabled: false,
        userRules: rules,
      );
      expect(result, isEmpty);
      expect(rules, hasLength(1));
    });

    test('全局模式不应用用户规则', () {
      final result = selectActiveNimbusUserRules(
        isAutomaticMode: false,
        customWebsiteAccessEnabled: true,
        userRules: rules,
      );
      expect(result, isEmpty);
    });
  });
}
