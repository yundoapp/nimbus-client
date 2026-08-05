import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_rule_set_diagnostic.dart';

void main() {
  const tags = ['geosite-cn', 'geoip-cn'];

  test('extracts remote rule-set tags from the effective core config', () {
    final tags = nimbusRemoteRuleSetTagsFromConfig({
      'route': {
        'rule_set': [
          {'tag': 'geosite-cn', 'type': 'remote'},
          {'tag': 'geoip-cn', 'type': 'local'},
          {'tag': 'geosite-gfw', 'type': 'remote'},
        ],
      },
    });

    expect(tags, {'geosite-cn', 'geosite-gfw'});
  });

  test('recognizes cached and freshly updated rule sets', () {
    final result = parseNimbusRuleSetDiagnostics(
      tags: tags,
      logMessages: [
        'INFO router: rule-set geosite-cn: loaded from cache',
        'INFO router: rule-set geoip-cn: download started',
        'INFO router: updated rule-set geoip-cn',
      ],
    );

    expect(result.hasFailure, isFalse);
    expect(result.allResolved, isTrue);
    expect(result.items.map((item) => item.status), [
      NimbusRuleSetDiagnosticStatus.loaded,
      NimbusRuleSetDiagnosticStatus.loaded,
    ]);
  });

  test('recognizes a failed initial download with a core log prefix', () {
    final result = parseNimbusRuleSetDiagnostics(
      tags: tags,
      logMessages: const ['ERROR router: rule-set geosite-cn: download failed: read: operation timed out'],
    );

    expect(result.hasFailure, isTrue);
    expect(result.firstFailure?.tag, 'geosite-cn');
    expect(result.firstFailure?.detail, 'download failed: read: operation timed out');
    expect(result.items.singleWhere((item) => item.tag == 'geoip-cn').status, NimbusRuleSetDiagnosticStatus.pending);
  });

  test('keeps a cached rule set usable when its background update fails', () {
    final result = parseNimbusRuleSetDiagnostics(
      tags: const ['geoip-cn'],
      logMessages: const [
        'INFO router: rule-set geoip-cn: loaded from cache',
        'INFO router: rule-set geoip-cn: download started',
        'ERROR router: rule-set geoip-cn: download failed: context canceled',
      ],
    );

    expect(result.hasFailure, isFalse);
    expect(result.allResolved, isTrue);
    expect(result.firstUpdateFailure?.detail, 'download failed: context canceled');
  });

  test('keeps parsing the upstream failure wording for older Core logs', () {
    final result = parseNimbusRuleSetDiagnostics(
      tags: const ['geoip-cn'],
      logMessages: const ['ERROR router: fetch rule-set geoip-cn: context canceled'],
    );

    expect(result.hasFailure, isTrue);
    expect(result.firstFailure?.detail, 'context canceled');
  });

  test('leaves a rule set pending when no lifecycle marker was emitted', () {
    final result = parseNimbusRuleSetDiagnostics(
      tags: const ['geosite-cn'],
      logMessages: const ['INFO router: initialize rule-set'],
    );

    expect(result.hasFailure, isFalse);
    expect(result.allResolved, isFalse);
    expect(result.items.single.status, NimbusRuleSetDiagnosticStatus.pending);
  });
}
