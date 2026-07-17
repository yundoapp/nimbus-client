import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/home/widget/home_page.dart';

void main() {
  group('套餐用量百分比', () {
    test('没有用量时显示 0%', () {
      expect(formatUsagePercent(0), '0%');
    });

    test('有用量但不足 1% 时显示 <1%', () {
      expect(formatUsagePercent(43.2 * 1024 * 1024 / (100 * 1024 * 1024 * 1024)), '<1%');
    });

    test('达到 1% 后显示四舍五入的整数百分比', () {
      expect(formatUsagePercent(0.01), '1%');
      expect(formatUsagePercent(0.432), '43%');
      expect(formatUsagePercent(1), '100%');
    });
  });
}
