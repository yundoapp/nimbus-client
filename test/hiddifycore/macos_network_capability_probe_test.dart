import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_network_capability_probe.dart';

void main() {
  test('retries transient proxy failures independently for IPv4 and IPv6', () async {
    final attempts = <String, int>{};
    final probe = MacOSNetworkCapabilityProbe(
      maxAttempts: 3,
      retryDelay: Duration.zero,
      attempt:
          ({
            required uri,
            required proxyHost,
            required proxyPort,
            required proxyUsername,
            required proxyPassword,
            required timeout,
          }) async {
            expect(proxyHost, '127.0.0.1');
            expect(proxyUsername, isNull);
            expect(proxyPassword, isNull);
            final count = (attempts[uri.host] ?? 0) + 1;
            attempts[uri.host] = count;
            if (uri.host == '1.1.1.1' && count == 3) return;
            throw StateError('probe unavailable');
          },
    );

    final capabilities = await probe.probe(proxyHost: '127.0.0.1', proxyPort: 12334);

    expect(capabilities.ipv4Available, isTrue);
    expect(capabilities.ipv6Available, isFalse);
    expect(attempts, {'1.1.1.1': 3, '2606:4700:4700::1111': 3});
  });

  test('rechecks IPv4 after a transient failure without repeating IPv6', () async {
    final attempts = <String, int>{};
    final probe = MacOSNetworkCapabilityProbe(
      retryDelay: Duration.zero,
      ipv4RecoveryDelay: Duration.zero,
      attempt:
          ({
            required uri,
            required proxyHost,
            required proxyPort,
            required proxyUsername,
            required proxyPassword,
            required timeout,
          }) async {
            final count = (attempts[uri.host] ?? 0) + 1;
            attempts[uri.host] = count;
            if (uri.host == '1.1.1.1' && count == 3) return;
            throw StateError('probe unavailable');
          },
    );

    final capabilities = await probe.probeWithIpv4Recovery(proxyHost: '127.0.0.1', proxyPort: 12334);

    expect(capabilities.ipv4Available, isTrue);
    expect(capabilities.ipv6Available, isFalse);
    expect(attempts, {'1.1.1.1': 3, '2606:4700:4700::1111': 2});
  });

  test('does not run IPv4 recovery after the initial probe succeeds', () async {
    final attempts = <String, int>{};
    final probe = MacOSNetworkCapabilityProbe(
      maxAttempts: 1,
      retryDelay: Duration.zero,
      ipv4RecoveryDelay: Duration.zero,
      attempt:
          ({
            required uri,
            required proxyHost,
            required proxyPort,
            required proxyUsername,
            required proxyPassword,
            required timeout,
          }) async {
            attempts[uri.host] = (attempts[uri.host] ?? 0) + 1;
            if (uri.host != '1.1.1.1') throw StateError('IPv6 unavailable');
          },
    );

    final capabilities = await probe.probeWithIpv4Recovery(proxyHost: '127.0.0.1', proxyPort: 12334);

    expect(capabilities.ipv4Available, isTrue);
    expect(capabilities.ipv6Available, isFalse);
    expect(attempts, {'1.1.1.1': 1, '2606:4700:4700::1111': 1});
  });

  test('probes the same SOCKS5 IPv4 path used by the privileged tunnel', () async {
    final destinations = <String>[];
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final handlers = <Future<void>>[];
    final subscription = server.listen((socket) {
      handlers.add(_serveSocksProbe(socket, destinations));
    });
    try {
      final capabilities = await MacOSNetworkCapabilityProbe(
        maxAttempts: 1,
        timeout: const Duration(seconds: 1),
        retryDelay: Duration.zero,
      ).probe(proxyHost: InternetAddress.loopbackIPv4.address, proxyPort: server.port);

      expect(capabilities.ipv4Available, isTrue);
      expect(capabilities.ipv6Available, isFalse);
      expect(destinations, contains('1:1.1.1.1'));
      expect(destinations, contains('4:2606:4700:4700::1111'));
      expect(MacOSNetworkCapabilityProbe.ipv4ProbeUri.scheme, 'http');
      expect(MacOSNetworkCapabilityProbe.ipv6ProbeUri.scheme, 'http');
    } finally {
      await subscription.cancel();
      await server.close();
      await Future.wait(handlers);
    }
  });

  test('does not allow tunnel takeover when accelerated IPv4 is unavailable', () {
    expect(
      selectMacOSTunnelNetworkMode((ipv4Available: false, ipv6Available: false)),
      MacOSTunnelNetworkSelection.unavailable,
    );
    expect(
      selectMacOSTunnelNetworkMode((ipv4Available: false, ipv6Available: true)),
      MacOSTunnelNetworkSelection.unavailable,
    );
  });

  test('uses IPv4 fallback only when IPv4 works and IPv6 does not', () {
    expect(
      selectMacOSTunnelNetworkMode((ipv4Available: true, ipv6Available: false)),
      MacOSTunnelNetworkSelection.ipv4Fallback,
    );
    expect(
      selectMacOSTunnelNetworkMode((ipv4Available: true, ipv6Available: true)),
      MacOSTunnelNetworkSelection.dualStack,
    );
  });
}

Future<void> _serveSocksProbe(Socket socket, List<String> destinations) async {
  final reader = _TestSocketReader(socket);
  try {
    final greeting = await reader.readExactly(2);
    await reader.readExactly(greeting[1]);
    socket.add([0x05, 0x00]);
    await socket.flush();

    final request = await reader.readExactly(4);
    final addressType = request[3];
    final addressLength = addressType == 0x01 ? 4 : 16;
    final rawAddress = await reader.readExactly(addressLength);
    await reader.readExactly(2);
    final address = InternetAddress.fromRawAddress(rawAddress).address;
    destinations.add('$addressType:$address');

    if (addressType == 0x04) {
      socket.add([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await socket.flush();
      return;
    }

    socket.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    await socket.flush();
    expect(String.fromCharCodes(await reader.readExactly(5)), 'GET /');
    socket.add('HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n'.codeUnits);
    await socket.flush();
  } finally {
    await reader.cancel();
    socket.destroy();
  }
}

class _TestSocketReader {
  _TestSocketReader(Stream<Uint8List> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<Uint8List> _iterator;
  Uint8List? _chunk;
  int _offset = 0;

  Future<Uint8List> readExactly(int length) async {
    final result = BytesBuilder(copy: false);
    while (result.length < length) {
      final chunk = _chunk;
      if (chunk == null || _offset >= chunk.length) {
        if (!await _iterator.moveNext()) throw StateError('socket closed');
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
