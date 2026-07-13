import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_input_validation.dart';

void main() {
  group('云渡密码字节限制', () {
    test('按 UTF-8 字节数执行 bcrypt 72 字节边界', () {
      expect(isNimbusPasswordWithinByteLimit(List.filled(72, 'a').join()), isTrue);
      expect(isNimbusPasswordWithinByteLimit(List.filled(73, 'a').join()), isFalse);
      expect(isNimbusPasswordWithinByteLimit('Aa1!${List.filled(22, '中').join()}'), isTrue);
      expect(isNimbusPasswordWithinByteLimit('Aa1!${List.filled(23, '中').join()}'), isFalse);
    });
  });

  group('云渡网站域名校验', () {
    test('接受标准域名、多级域名和 Punycode', () {
      expect(normalizeNimbusDomain(' OpenAI.COM '), 'openai.com');
      expect(normalizeNimbusDomain('api.example.co.uk'), 'api.example.co.uk');
      expect(normalizeNimbusDomain('xn--fiqs8s.example'), 'xn--fiqs8s.example');
    });

    test('拒绝 URL、路径、端口、通配符和 IP', () {
      expect(normalizeNimbusDomain('https://openai.com'), isNull);
      expect(normalizeNimbusDomain('openai.com/path'), isNull);
      expect(normalizeNimbusDomain('openai.com:443'), isNull);
      expect(normalizeNimbusDomain('*.openai.com'), isNull);
      expect(normalizeNimbusDomain('127.0.0.1'), isNull);
    });

    test('拒绝非法标签、内部名称和超长域名', () {
      expect(normalizeNimbusDomain('localhost'), isNull);
      expect(normalizeNimbusDomain('bad_label.example'), isNull);
      expect(normalizeNimbusDomain('-bad.example'), isNull);
      expect(normalizeNimbusDomain('bad-.example'), isNull);
      expect(normalizeNimbusDomain('${List.filled(64, 'a').join()}.example'), isNull);
      expect(normalizeNimbusDomain('${List.filled(250, 'a').join()}.com'), isNull);
    });
  });
}
