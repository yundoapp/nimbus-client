import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/nimbus/auth/model/nimbus_rules_config.dart';

Future<void> main(List<String> args) async {
  final filter = args.join(' ').trim().toLowerCase();
  final socket = await WebSocket.connect(
    'ws://$nimbusRouteDiagnosticsController/connections',
    headers: {'Authorization': 'Bearer $nimbusRouteDiagnosticsSecret'},
  );
  final seenConnections = <String>{};
  late final StreamSubscription<dynamic> messages;
  final done = Completer<void>();

  Future<void> stop() async {
    if (done.isCompleted) return;
    done.complete();
    await messages.cancel();
    await socket.close();
  }

  final signals = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(stop())),
    ProcessSignal.sigterm.watch().listen((_) => unawaited(stop())),
  ];

  stdout.writeln(filter.isEmpty ? '正在监听云渡路由决策，按 Ctrl+C 结束。' : '正在监听“$filter”的路由决策，按 Ctrl+C 结束。');

  messages = socket.listen(
    (message) {
      final payload = jsonDecode(message as String) as Map<String, dynamic>;
      final connections = payload['connections'];
      if (connections is! List) return;
      for (final raw in connections.whereType<Map>()) {
        final connection = Map<String, dynamic>.from(raw);
        final id = connection['id'] as String?;
        if (id == null || !seenConnections.add(id)) continue;
        final metadata = Map<String, dynamic>.from(connection['metadata'] as Map? ?? const {});
        final host = (metadata['host'] as String? ?? '').trim();
        final destinationIP = (metadata['destinationIP'] as String? ?? '').trim();
        final destinationPort = metadata['destinationPort']?.toString() ?? '';
        final target = host.isNotEmpty ? host : destinationIP;
        if (filter.isNotEmpty && !target.toLowerCase().contains(filter)) continue;

        final chains = (connection['chains'] as List? ?? const []).whereType<String>().toList();
        final isDirect = chains.contains('nimbus-direct');
        final decision = isDirect ? '直连' : '加速';
        final rule = (connection['rule'] as String? ?? '').trim();
        final rulePayload = (connection['rulePayload'] as String? ?? '').trim();
        final ruleDescription = [rule, rulePayload].where((value) => value.isNotEmpty).join(' / ');
        final endpoint = destinationPort.isEmpty ? target : '$target:$destinationPort';
        stdout.writeln(
          '$decision  $endpoint  规则：${ruleDescription.isEmpty ? "最终出口" : ruleDescription}  出站：${chains.join(" -> ")}',
        );
      }
    },
    onError: (Object error) {
      stderr.writeln('路由诊断连接中断：$error');
      unawaited(stop());
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );

  await done.future;
  for (final signal in signals) {
    await signal.cancel();
  }
}
