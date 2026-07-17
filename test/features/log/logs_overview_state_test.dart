import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/overview/logs_overview_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('日志概览在尚无日志时直接进入空数据状态', () {
    const state = LogsOverviewState();

    expect(state.logs, isA<AsyncData<List<LogEntity>>>());
    expect(state.logs.requireValue, isEmpty);
  });
}
