import 'sql_executor.dart';
import 'sqlite_channel.dart';
import 'sqlite_ffi.dart';

class AppDatabase {
  AppDatabase(this._sql);

  final SqlExecutor _sql;
  var ftsReady = false;

  static Future<AppDatabase> memory() async {
    final sql = FfiSqlite();
    await sql.openFile(':memory:');
    final database = AppDatabase(sql);
    await database._ensureSchema();
    return database;
  }

  static Future<AppDatabase> openFile(String path) async {
    final sql = FfiSqlite();
    await sql.openFile(path);
    final database = AppDatabase(sql);
    await database._ensureSchema();
    return database;
  }

  static Future<AppDatabase> openMobile() async {
    final sql = ChannelSql();
    await sql.open();
    final database = AppDatabase(sql);
    await database._ensureSchema();
    return database;
  }

  Future<void> execute(String sql, [List<Object?> args = const []]) {
    return _sql.execute(sql, args);
  }

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) {
    return _sql.query(sql, args);
  }

  Future<void> transaction(Future<void> Function() action) async {
    await execute('BEGIN');
    try {
      await action();
      await execute('COMMIT');
    } catch (_) {
      try {
        await execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> close() => _sql.close();

  Future<void> _ensureSchema() async {
    await execute('''
CREATE TABLE IF NOT EXISTS departments (
  id INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  card_label_diagnosis TEXT,
  card_label_care TEXT,
  card_label_tactic TEXT
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS diagnoses (
  id INTEGER PRIMARY KEY,
  stable_key TEXT NOT NULL UNIQUE,
  department_id INTEGER NOT NULL,
  display_code TEXT,
  title TEXT NOT NULL,
  conditions_note TEXT,
  branch_prompt TEXT,
  mnn_hints TEXT,
  is_emergency INTEGER NOT NULL DEFAULT 0,
  include_in_shock_coma INTEGER NOT NULL DEFAULT 0,
  search_blob TEXT NOT NULL DEFAULT '',
  source_file TEXT,
  department_sort_order INTEGER NOT NULL DEFAULT 0,
  ingest_sequence INTEGER NOT NULL DEFAULT 0,
  list_sort_tail INTEGER NOT NULL DEFAULT 0
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS subconditions (
  id INTEGER PRIMARY KEY,
  diagnosis_id INTEGER NOT NULL,
  code_label TEXT NOT NULL,
  title TEXT NOT NULL,
  conditions_detail TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS treatments (
  id INTEGER PRIMARY KEY,
  diagnosis_id INTEGER,
  subcondition_id INTEGER,
  body TEXT NOT NULL DEFAULT ''
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS tactics (
  id INTEGER PRIMARY KEY,
  diagnosis_id INTEGER,
  subcondition_id INTEGER,
  body TEXT NOT NULL DEFAULT ''
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS medications (
  id INTEGER PRIMARY KEY,
  name_normalized TEXT NOT NULL,
  diagnosis_id INTEGER NOT NULL,
  subcondition_id INTEGER,
  source_hint TEXT
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS favorites (
  stable_key TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
)''');
    await execute('''
CREATE TABLE IF NOT EXISTS local_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''');
    try {
      await execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS diagnosis_fts USING fts5(
  stable_key UNINDEXED,
  title,
  search_blob,
  medication_names,
  tokenize = 'unicode61 remove_diacritics 0'
)''');
      ftsReady = true;
    } catch (_) {
      ftsReady = false;
    }
  }
}
