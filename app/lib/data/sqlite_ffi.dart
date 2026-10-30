import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'sql_executor.dart';

const _sqliteOk = 0;
const _sqliteRow = 100;
const _sqliteDone = 101;
const _openReadWrite = 0x00000002;
const _openCreate = 0x00000004;
const _openFullMutex = 0x00010000;
const _typeInteger = 1;
const _typeFloat = 2;
const _typeText = 3;

class FfiSqlite implements SqlExecutor {
  Pointer<Void>? _db;

  Future<void> openFile(String path) async {
    final opened = calloc<Pointer<Void>>();
    final name = _cstr(path);
    try {
      final code = _open(
        name.cast(),
        opened,
        _openReadWrite | _openCreate | _openFullMutex,
        nullptr,
      );
      final db = opened.value;
      if (code != _sqliteOk || db == nullptr) {
        throw SqliteException(code, 'sqlite3_open_v2 failed for $path');
      }
      _db = db;
      _busyTimeout(db, 2000);
    } finally {
      calloc.free(name);
      calloc.free(opened);
    }
  }

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    final stmt = _prepare(sql);
    try {
      _bind(stmt, args);
      final code = _step(stmt);
      if (code != _sqliteDone && code != _sqliteRow) {
        throw SqliteException(code, _errorMessage());
      }
    } finally {
      _finalize(stmt);
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final stmt = _prepare(sql);
    try {
      _bind(stmt, args);
      final rows = <Map<String, Object?>>[];
      while (true) {
        final code = _step(stmt);
        if (code == _sqliteDone) break;
        if (code != _sqliteRow) {
          throw SqliteException(code, _errorMessage());
        }
        final row = <String, Object?>{};
        final columns = _columnCount(stmt);
        for (var index = 0; index < columns; index++) {
          row[_columnName(stmt, index)] = _columnValue(stmt, index);
        }
        rows.add(row);
      }
      return rows;
    } finally {
      _finalize(stmt);
    }
  }

  @override
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) _close(db);
  }

  Pointer<Void> get _handle {
    final db = _db;
    if (db == null) throw StateError('Database is closed');
    return db;
  }

  Pointer<Void> _prepare(String sql) {
    final statement = calloc<Pointer<Void>>();
    final text = _cstr(sql);
    try {
      final code = _prepareV2(_handle, text.cast(), -1, statement, nullptr);
      if (code != _sqliteOk) {
        throw SqliteException(code, _errorMessage());
      }
      final stmt = statement.value;
      if (stmt == nullptr) {
        throw SqliteException(code, 'sqlite3_prepare_v2 returned no statement');
      }
      return stmt;
    } finally {
      calloc.free(text);
      calloc.free(statement);
    }
  }

  void _bind(Pointer<Void> statement, List<Object?> args) {
    for (var index = 0; index < args.length; index++) {
      final value = args[index];
      final position = index + 1;
      final int code;
      if (value == null) {
        code = _bindNull(statement, position);
      } else if (value is int) {
        code = _bindInt64(statement, position, value);
      } else if (value is bool) {
        code = _bindInt64(statement, position, value ? 1 : 0);
      } else if (value is double) {
        code = _bindDouble(statement, position, value);
      } else {
        final text = _cstr(value.toString());
        code = _bindText(statement, position, text, -1, _sqliteTransient);
        calloc.free(text);
      }
      if (code != _sqliteOk) {
        throw SqliteException(code, _errorMessage());
      }
    }
  }

  String _errorMessage() {
    final db = _db;
    if (db == null) return 'sqlite error';
    return _readCString(_errmsg(db));
  }

  String _columnName(Pointer<Void> statement, int index) {
    return _readCString(_columnNamePtr(statement, index));
  }

  Object? _columnValue(Pointer<Void> statement, int index) {
    switch (_columnType(statement, index)) {
      case _typeInteger:
        return _columnInt64(statement, index);
      case _typeFloat:
        return _columnDouble(statement, index);
      case _typeText:
        final pointer = _columnText(statement, index);
        final length = _columnBytes(statement, index);
        if (pointer == nullptr || length == 0) return '';
        return utf8.decode(pointer.asTypedList(length));
      default:
        return null;
    }
  }
}

class SqliteException implements Exception {
  SqliteException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'SqliteException($code): $message';
}

DynamicLibrary? _library;

DynamicLibrary get _lib {
  return _library ??= () {
    if (Platform.isLinux) {
      try {
        return DynamicLibrary.open('libsqlite3.so.0');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so');
      }
    }
    if (Platform.isMacOS) return DynamicLibrary.open('libsqlite3.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('sqlite3.dll');
    return DynamicLibrary.process();
  }();
}

final _open = _lib.lookupFunction<
    Int32 Function(Pointer<Char>, Pointer<Pointer<Void>>, Int32, Pointer<Char>),
    int Function(Pointer<Char>, Pointer<Pointer<Void>>, int, Pointer<Char>)>(
  'sqlite3_open_v2',
);

final _close = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'sqlite3_close',
);

final _busyTimeout = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_busy_timeout');

final _prepareV2 = _lib.lookupFunction<
    Int32 Function(
      Pointer<Void>,
      Pointer<Char>,
      Int32,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Char>>,
    ),
    int Function(
      Pointer<Void>,
      Pointer<Char>,
      int,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Char>>,
    )>('sqlite3_prepare_v2');

final _bindNull = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_bind_null');

final _bindInt64 = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Int64),
    int Function(Pointer<Void>, int, int)>('sqlite3_bind_int64');

final _bindDouble = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Double),
    int Function(Pointer<Void>, int, double)>('sqlite3_bind_double');

final _bindText = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Int32, Pointer<Void>),
    int Function(Pointer<Void>, int, Pointer<Uint8>, int, Pointer<Void>)>(
  'sqlite3_bind_text',
);

final Pointer<Void> _sqliteTransient = Pointer.fromAddress(-1);

final _step = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'sqlite3_step',
);

final _finalize = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'sqlite3_finalize',
);

final _columnCount = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'sqlite3_column_count',
);

final _columnNamePtr = _lib.lookupFunction<
    Pointer<Char> Function(Pointer<Void>, Int32),
    Pointer<Char> Function(Pointer<Void>, int)>('sqlite3_column_name');

final _columnType = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_column_type');

final _columnInt64 = _lib.lookupFunction<
    Int64 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_column_int64');

final _columnDouble = _lib.lookupFunction<
    Double Function(Pointer<Void>, Int32),
    double Function(Pointer<Void>, int)>('sqlite3_column_double');

final _columnText = _lib.lookupFunction<
    Pointer<Uint8> Function(Pointer<Void>, Int32),
    Pointer<Uint8> Function(Pointer<Void>, int)>('sqlite3_column_text');

final _columnBytes = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_column_bytes');

final _errmsg = _lib.lookupFunction<
    Pointer<Char> Function(Pointer<Void>),
    Pointer<Char> Function(Pointer<Void>)>('sqlite3_errmsg');

Pointer<Uint8> _cstr(String value) {
  final units = utf8.encode(value);
  final pointer = calloc<Uint8>(units.length + 1);
  pointer.asTypedList(units.length + 1).setAll(0, units);
  return pointer;
}

String _readCString(Pointer<Char> pointer) {
  if (pointer == nullptr) return '';
  final bytes = pointer.cast<Uint8>();
  final data = <int>[];
  var index = 0;
  while (true) {
    final byte = bytes[index];
    if (byte == 0) break;
    data.add(byte);
    index++;
  }
  return utf8.decode(data);
}
