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

  test('路由诊断接口仅在开发版监听本机地址', () {
    final debugConfig = buildNimbusExperimentalConfig(isDebugBuild: true);
    final releaseConfig = buildNimbusExperimentalConfig(isDebugBuild: false);

    expect(debugConfig['clash_api'], {
      'external_controller': nimbusRouteDiagnosticsController,
      'secret': nimbusRouteDiagnosticsSecret,
    });
    expect(releaseConfig, isNot(contains('clash_api')));
  });

  test('当前 core 默认使用 legacy download_detour 下载远程规则库', () {
    final httpClients = buildNimbusHttpClients('nimbus-proxy');
    final ruleSets = buildNimbusRuleSets(const [
      NimbusRulePackageItem(
        kind: 'rule_set',
        pattern: 'geosite-google',
        patternType: 'geosite',
        action: 'accelerate',
        sourceUrl: 'https://rules.example/geosite-google.srs',
      ),
    ], 'nimbus-proxy');

    expect(httpClients, isEmpty);
    expect(ruleSets.single['download_detour'], 'nimbus-proxy');
    expect(ruleSets.single, isNot(contains('http_client')));
  });

  test('远程规则库可切换为 sing-box http_client 下载', () {
    final httpClients = buildNimbusHttpClients('nimbus-proxy', mode: NimbusRuleSetDownloadMode.httpClient);
    final ruleSets = buildNimbusRuleSets(
      const [
        NimbusRulePackageItem(
          kind: 'rule_set',
          pattern: 'geosite-google',
          patternType: 'geosite',
          action: 'accelerate',
          sourceUrl: 'https://rules.example/geosite-google.srs',
        ),
      ],
      'nimbus-proxy',
      mode: NimbusRuleSetDownloadMode.httpClient,
    );

    expect(httpClients, [
      {'tag': nimbusRuleSetHttpClientTag, 'detour': 'nimbus-proxy'},
    ]);
    expect(ruleSets, [
      {
        'tag': 'geosite-google',
        'type': 'remote',
        'format': 'binary',
        'url': 'https://rules.example/geosite-google.srs',
        'update_interval': '1d',
        'http_client': nimbusRuleSetHttpClientTag,
      },
    ]);
    expect(ruleSets.single, isNot(contains('download_detour')));
  });

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

  group('自定义网站规则出站', () {
    test('加速访问生成代理出站', () {
      final rules = buildNimbusRouteRules(const [
        NimbusRulePackageItem(pattern: 'api.ipify.org', patternType: 'domain', action: 'accelerate'),
      ], 'nimbus-proxy');

      expect(rules, [
        {
          'domain_suffix': ['api.ipify.org'],
          'outbound': 'nimbus-proxy',
        },
      ]);
    });

    test('直连访问生成直连出站', () {
      final rules = buildNimbusRouteRules(const [
        NimbusRulePackageItem(pattern: 'myip.ipip.net', patternType: 'domain', action: 'direct'),
      ], 'nimbus-proxy');

      expect(rules, [
        {
          'domain_suffix': ['myip.ipip.net'],
          'outbound': 'nimbus-direct',
        },
      ]);
    });
  });
}
