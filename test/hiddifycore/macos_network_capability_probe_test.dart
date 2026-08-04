import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_network_capability_probe.dart';

void main() {
  test('retries transient proxy failures independently for IPv4 and IPv6', () async {
    final attempts = <String, int>{};
    final probe = MacOSNetworkCapabilityProbe(
      maxAttempts: 3,
      retryDelay: Duration.zero,
      attempt: ({required uri, required proxyPort, required timeout}) async {
        final count = (attempts[uri.host] ?? 0) + 1;
        attempts[uri.host] = count;
        if (uri.host == '1.1.1.1' && count == 3) return;
        throw StateError('probe unavailable');
      },
    );

    final capabilities = await probe.probe(proxyPort: 12334);

    expect(capabilities.ipv4Available, isTrue);
    expect(capabilities.ipv6Available, isFalse);
    expect(attempts, {'1.1.1.1': 3, '2606:4700:4700::1111': 3});
  });
}
