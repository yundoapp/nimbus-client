import 'dart:async';
import 'dart:io';

typedef MacOSProxyProbeAttempt =
    Future<void> Function({required Uri uri, required int proxyPort, required Duration timeout});
typedef MacOSNetworkCapabilities = ({bool ipv4Available, bool ipv6Available});

class MacOSNetworkCapabilityProbe {
  MacOSNetworkCapabilityProbe({MacOSProxyProbeAttempt? attempt, this.timeout = const Duration(seconds: 3)})
    : _attempt = attempt ?? _attemptThroughHttpProxy;

  static final ipv4ProbeUri = Uri.parse('https://1.1.1.1/');
  static final ipv6ProbeUri = Uri.parse('https://[2606:4700:4700::1111]/');

  final MacOSProxyProbeAttempt _attempt;
  final Duration timeout;

  Future<MacOSNetworkCapabilities> probe({required int proxyPort}) async {
    final results = await Future.wait([_isAvailable(ipv4ProbeUri, proxyPort), _isAvailable(ipv6ProbeUri, proxyPort)]);
    return (ipv4Available: results[0], ipv6Available: results[1]);
  }

  Future<bool> _isAvailable(Uri uri, int proxyPort) async {
    try {
      await _attempt(uri: uri, proxyPort: proxyPort, timeout: timeout).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _attemptThroughHttpProxy({
    required Uri uri,
    required int proxyPort,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    client.badCertificateCallback = (_, _, _) => true;
    try {
      final request = await client.openUrl('HEAD', uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
