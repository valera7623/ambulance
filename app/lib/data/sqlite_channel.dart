import 'package:flutter/services.dart';

import 'sql_executor.dart';

class ChannelSql implements SqlExecutor {
  ChannelSql() : _channel = const MethodChannel('ru.smp.smp_guide/sql');

  final MethodChannel _channel;

  Future<void> open() {
    return _channel.invokeMethod<void>('open');
  }

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) {
    return _channel.invokeMethod<void>('exec', {
      'sql': sql,
      'args': args,
    });
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final rows = await _channel.invokeMethod<List<dynamic>>('query', {
      'sql': sql,
      'args': args,
    });
    return [
      for (final row in rows ?? const <dynamic>[])
        Map<String, Object?>.from(row as Map),
    ];
  }

  @override
  Future<void> close() async {}
}
