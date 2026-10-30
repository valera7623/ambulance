abstract class SqlExecutor {
  Future<void> execute(String sql, [List<Object?> args = const []]);

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]);

  Future<void> close();
}
