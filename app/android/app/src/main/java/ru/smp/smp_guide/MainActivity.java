package ru.smp.smp_guide;

import android.content.Intent;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteStatement;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class MainActivity extends FlutterActivity {
    private static final String SQL_CHANNEL = "ru.smp.smp_guide/sql";
    private static final String SHARE_CHANNEL = "ru.smp.smp_guide/share";
    private SQLiteDatabase database;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SQL_CHANNEL)
            .setMethodCallHandler(this::onSql);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHARE_CHANNEL)
            .setMethodCallHandler(this::onShare);
    }

    private void onShare(MethodCall call, MethodChannel.Result result) {
        if (!"share".equals(call.method)) {
            result.notImplemented();
            return;
        }
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, String.valueOf(call.arguments));
        startActivity(Intent.createChooser(send, "Поделиться"));
        result.success(null);
    }

    private void onSql(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "open":
                    database = openOrCreateDatabase("smp_guide.sqlite", MODE_PRIVATE, null);
                    result.success(null);
                    break;
                case "exec":
                    exec(call.argument("sql"), call.argument("args"));
                    result.success(null);
                    break;
                case "query":
                    result.success(query(call.argument("sql"), call.argument("args")));
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception error) {
            result.error("sqlite", error.getMessage(), null);
        }
    }

    private void exec(String sql, List<Object> args) {
        String trimmed = sql.trim().toUpperCase(Locale.US);
        if (trimmed.startsWith("BEGIN")) {
            database.beginTransaction();
            return;
        }
        if (trimmed.startsWith("COMMIT")) {
            database.setTransactionSuccessful();
            database.endTransaction();
            return;
        }
        if (trimmed.startsWith("ROLLBACK")) {
            database.endTransaction();
            return;
        }
        if (args == null || args.isEmpty()) {
            database.execSQL(sql);
            return;
        }
        SQLiteStatement statement = database.compileStatement(sql);
        try {
            bind(statement, args);
            statement.execute();
        } finally {
            statement.close();
        }
    }

    private List<Map<String, Object>> query(String sql, List<Object> args) {
        String[] bind = new String[args == null ? 0 : args.size()];
        if (args != null) {
            for (int i = 0; i < args.size(); i++) {
                Object value = args.get(i);
                bind[i] = value == null ? null : String.valueOf(value);
            }
        }
        Cursor cursor = database.rawQuery(sql, bind);
        List<Map<String, Object>> rows = new ArrayList<>();
        try {
            while (cursor.moveToNext()) {
                Map<String, Object> row = new HashMap<>();
                for (int i = 0; i < cursor.getColumnCount(); i++) {
                    String name = cursor.getColumnName(i);
                    switch (cursor.getType(i)) {
                        case Cursor.FIELD_TYPE_NULL:
                            row.put(name, null);
                            break;
                        case Cursor.FIELD_TYPE_INTEGER:
                            row.put(name, cursor.getLong(i));
                            break;
                        case Cursor.FIELD_TYPE_FLOAT:
                            row.put(name, cursor.getDouble(i));
                            break;
                        default:
                            row.put(name, cursor.getString(i));
                            break;
                    }
                }
                rows.add(row);
            }
        } finally {
            cursor.close();
        }
        return rows;
    }

    private void bind(SQLiteStatement statement, List<Object> args) {
        for (int i = 0; i < args.size(); i++) {
            Object value = args.get(i);
            int index = i + 1;
            if (value == null) {
                statement.bindNull(index);
            } else if (value instanceof Integer) {
                statement.bindLong(index, ((Integer) value).longValue());
            } else if (value instanceof Long) {
                statement.bindLong(index, (Long) value);
            } else if (value instanceof Double) {
                statement.bindDouble(index, (Double) value);
            } else if (value instanceof Boolean) {
                statement.bindLong(index, Boolean.TRUE.equals(value) ? 1L : 0L);
            } else {
                statement.bindString(index, String.valueOf(value));
            }
        }
    }
}
