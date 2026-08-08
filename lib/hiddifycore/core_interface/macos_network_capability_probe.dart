import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef MacOSProxyProbeAttempt =
    Future<void> Function({
      required Uri uri,
      required String proxyHost,
      required int proxyPort,
      required String? proxyUsername,
      required String? proxyPassword,
      required Duration timeout,
    });
typedef MacOSNetworkCapabilities = ({bool ipv4Available, bool ipv6Available});

enum MacOSTunnelNetworkSelection { unavailable, ipv4Fallback, dualStack }

MacOSTunnelNetworkSelection selectMacOSTunnelNetworkMode(MacOSNetworkCapabilities capabilities) {
  if (!capabilities.ipv4Available) return MacOSTunnelNetworkSelection.unavailable;
  if (!capabilities.ipv6Available) return MacOSTunnelNetworkSelection.ipv4Fallback;
  return MacOSTunnelNetworkSelection.dualStack;
}

class MacOSNetworkCapabilityProbe {
  MacOSNetworkCapabilityProbe({
    MacOSProxyProbeAttempt? attempt,
    this.timeout = const Duration(milliseconds: 1500),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 200),
    this.ipv4RecoveryDelay = const Duration(milliseconds: 400),
  }) : _attempt = attempt ?? _attemptThroughSocks5;

  // Literal HTTP targets isolate the destination address family. TLS, DNS,
  // certificate validation and HTTP CONNECT are deliberately excluded because
  // they are not part of the Helper -> SOCKS5 -> user Core data path.
  static final ipv4ProbeUri = Uri.parse('http://1.1.1.1/');
  static final ipv6ProbeUri = Uri.parse('http://[2606:4700:4700::1111]/');

  final MacOSProxyProbeAttempt _attempt;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  final Duration ipv4RecoveryDelay;

  Future<MacOSNetworkCapabilities> probe({
    required String proxyHost,
    required int proxyPort,
    String? proxyUsername,
    String? proxyPassword,
  }) async {
    final results = await Future.wait([
      _isAvailable(ipv4ProbeUri, proxyHost, proxyPort, proxyUsername, proxyPassword),
      _isAvailable(ipv6ProbeUri, proxyHost, proxyPort, proxyUsername, proxyPassword),
    ]);
    return (ipv4Available: results[0], ipv6Available: results[1]);
  }

  /// Rechecks IPv4 only when the first capability probe fails. Rapid node
  /// switches can briefly leave the new outbound unable to answer the HTTP
  /// probe even though the Core process is already running. Normal starts do
  /// not pay for this extra check, and a confirmed failure still fails closed.
  Future<MacOSNetworkCapabilities> probeWithIpv4Recovery({
    required String proxyHost,
    required int proxyPort,
    String? proxyUsername,
    String? proxyPassword,
  }) async {
    final initial = await probe(
      proxyHost: proxyHost,
      proxyPort: proxyPort,
      proxyUsername: proxyUsername,
      proxyPassword: proxyPassword,
    );
    if (initial.ipv4Available) return initial;

    if (ipv4RecoveryDelay > Duration.zero) {
      await Future<void>.delayed(ipv4RecoveryDelay);
    }
    final recoveredIpv4 = await _isAvailable(ipv4ProbeUri, proxyHost, proxyPort, proxyUsername, proxyPassword);
    return (ipv4Available: recoveredIpv4, ipv6Available: initial.ipv6Available);
  }

  Future<bool> _isAvailable(
    Uri uri,
    String proxyHost,
    int proxyPort,
    String? proxyUsername,
    String? proxyPassword,
  ) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _attempt(
          uri: uri,
          proxyHost: proxyHost,
          proxyPort: proxyPort,
          proxyUsername: proxyUsername,
          proxyPassword: proxyPassword,
          timeout: timeout,
        ).timeout(timeout);
        return true;
      } catch (_) {
        if (attempt + 1 < maxAttempts && retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    return false;
  }

  static Future<void> _attemptThroughSocks5({
    required Uri uri,
    required String proxyHost,
    required int proxyPort,
    required String? proxyUsername,
    required String? proxyPassword,
    required Duration timeout,
  }) async {
    final destination = InternetAddress.tryParse(uri.host);
    if (destination == null) {
      throw const FormatException('network capability probe requires a literal IP address');
    }

    final socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
    final reader = _SocketReader(socket);
    try {
      final username = proxyUsername ?? '';
      final password = proxyPassword ?? '';
      final hasCredentials = username.isNotEmpty || password.isNotEmpty;
      socket.add([0x05, if (hasCredentials) 0x02 else 0x01, 0x00, if (hasCredentials) 0x02]);
      await socket.flush().timeout(timeout);

      final greeting = await reader.readExactly(2, timeout);
      if (greeting[0] != 0x05 || greeting[1] == 0xff) {
        throw StateError('SOCKS5 authentication negotiation failed');
      }
      if (greeting[1] == 0x02) {
        await _authenticate(socket, reader, username, password, timeout);
      } else if (greeting[1] != 0x00) {
        throw StateError('SOCKS5 selected an unsupported authentication method');
      }

      final addressType = destination.type == InternetAddressType.IPv4 ? 0x01 : 0x04;
      socket.add([0x05, 0x01, 0x00, addressType, ...destination.rawAddress, (uri.port >> 8) & 0xff, uri.port & 0xff]);
      await socket.flush().timeout(timeout);

      final connectReply = await reader.readExactly(4, timeout);
      if (connectReply[0] != 0x05 || connectReply[1] != 0x00) {
        throw StateError('SOCKS5 connection failed with code ${connectReply[1]}');
      }
      await _discardBoundAddress(reader, connectReply[3], timeout);

      final hostHeader = destination.type == InternetAddressType.IPv6 ? '[${uri.host}]' : uri.host;
      socket.add(
        ascii.encode(
          'GET ${uri.path.isEmpty ? '/' : uri.path} HTTP/1.1\r\n'
          'Host: $hostHeader\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      await socket.flush().timeout(timeout);
      final responsePrefix = ascii.decode(await reader.readExactly(5, timeout), allowInvalid: true);
      if (responsePrefix != 'HTTP/') {
        throw StateError('SOCKS5 probe received an invalid HTTP response');
      }
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }

  static Future<void> _authenticate(
    Socket socket,
    _SocketReader reader,
    String username,
    String password,
    Duration timeout,
  ) async {
    final usernameBytes = utf8.encode(username);
    final passwordBytes = utf8.encode(password);
    if (usernameBytes.length > 255 || passwordBytes.length > 255) {
      throw const FormatException('SOCKS5 credentials are too long');
    }
    socket.add([0x01, usernameBytes.length, ...usernameBytes, passwordBytes.length, ...passwordBytes]);
    await socket.flush().timeout(timeout);
    final response = await reader.readExactly(2, timeout);
    if (response[0] != 0x01 || response[1] != 0x00) {
      throw StateError('SOCKS5 authentication failed');
    }
  }

  static Future<void> _discardBoundAddress(_SocketReader reader, int addressType, Duration timeout) async {
    switch (addressType) {
      case 0x01:
        await reader.readExactly(4 + 2, timeout);
      case 0x04:
        await reader.readExactly(16 + 2, timeout);
      case 0x03:
        final length = (await reader.readExactly(1, timeout)).single;
        await reader.readExactly(length + 2, timeout);
      default:
        throw StateError('SOCKS5 returned an unsupported address type');
    }
  }
}

class _SocketReader {
  _SocketReader(Stream<Uint8List> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<Uint8List> _iterator;
  Uint8List? _chunk;
  int _offset = 0;

  Future<Uint8List> readExactly(int length, Duration timeout) async {
    final result = BytesBuilder(copy: false);
    while (result.length < length) {
      final chunk = _chunk;
      if (chunk == null || _offset >= chunk.length) {
        if (!await _iterator.moveNext().timeout(timeout)) {
          throw const SocketException('SOCKS5 connection closed unexpectedly');
        }
        _chunk = _iterator.current;
        _offset = 0;
        continue;
      }
      final remaining = length - result.length;
      final count = remaining < chunk.length - _offset ? remaining : chunk.length - _offset;
      result.add(chunk.sublist(_offset, _offset + count));
      _offset += count;
    }
    return result.takeBytes();
  }

  Future<void> cancel() => _iterator.cancel();
}
