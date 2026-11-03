import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'data/sections.dart';
import 'data/sync.dart';

class ContentController extends ChangeNotifier {
  ContentController({
    required this.repository,
    required SnapshotSource source,
  }) : _sync = ContentSync(source);

  final ContentRepository repository;
  final ContentSync _sync;

  bool syncing = false;
  bool loggedIn = false;
  int generation = 0;
  double textScale = 1;
  ThemeMode themeMode = ThemeMode.system;
  String apiBase = defaultApiBase;
  String fingerprint = '';
  String exportedAt = '';
  SyncOutcome? lastOutcome;
  String? lastError;

  String get statusLine {
    if (syncing) return 'Обновление протоколов…';
    final when = exportedAt.isEmpty ? '' : ' Протоколы от $exportedAt.';
    switch (lastOutcome) {
      case SyncOutcome.offline:
        return 'Нет сети. Показан сохранённый справочник.$when';
      case SyncOutcome.authRequired:
        return 'Показан сохранённый справочник.$when';
      case SyncOutcome.upToDate:
        return 'Протоколы актуальны.$when';
      case SyncOutcome.updated:
        return 'Протоколы обновлены.$when';
      case SyncOutcome.error:
        return 'Не удалось обновить. Показан сохранённый справочник.$when';
      case null:
        return exportedAt.isEmpty
            ? 'Локальный справочник'
            : 'Протоколы от $exportedAt.';
    }
  }

  Future<void> load({bool syncOnStart = true}) async {
    textScale = _scale(await repository.meta('text_scale'));
    themeMode = _theme(await repository.meta('theme_mode'));
    apiBase = await repository.meta('api_base') ?? defaultApiBase;
    fingerprint = await repository.meta('fingerprint') ?? '';
    exportedAt = await repository.meta('exported_at') ?? '';
    loggedIn = (await repository.meta('auth_token') ?? '').isNotEmpty;
    notifyListeners();
    if (syncOnStart && loggedIn) {
      await syncNow();
    }
  }

  Future<String?> login(String password) async {
    syncing = true;
    notifyListeners();
    try {
      final token = await _sync.source.login(apiBase, password);
      await repository.setMeta('auth_token', token);
      loggedIn = true;
      lastError = null;
      await syncNow();
      return null;
    } on AuthException {
      return 'Неверный мастер-пароль';
    } on SyncTransportException catch (error) {
      return error.offline ? 'Нет сети' : error.message;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await repository.deleteMeta('auth_token');
    loggedIn = false;
    lastOutcome = SyncOutcome.authRequired;
    notifyListeners();
  }

  Future<void> syncNow() async {
    syncing = true;
    notifyListeners();
    final token = await repository.meta('auth_token');
    final outcome = await _sync.run(
      baseUrl: apiBase,
      token: token,
      localFingerprint: await repository.meta('fingerprint'),
      replace: (snapshot) async {
        await repository.replaceContent(snapshot);
        generation += 1;
        fingerprint = snapshot.fingerprint;
        exportedAt = snapshot.exportedAt;
      },
      clearToken: () async {
        await repository.deleteMeta('auth_token');
        loggedIn = false;
      },
    );
    lastOutcome = outcome;
    loggedIn = (await repository.meta('auth_token') ?? '').isNotEmpty;
    syncing = false;
    notifyListeners();
  }

  Future<void> setApiBase(String value) async {
    final trimmed = value.trim().isEmpty ? defaultApiBase : value.trim();
    apiBase = trimmed;
    await repository.setMeta('api_base', trimmed);
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    textScale = value;
    await repository.setMeta('text_scale', value.toString());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await repository.setMeta('theme_mode', mode.name);
    notifyListeners();
  }

  double _scale(String? raw) {
    final parsed = double.tryParse(raw ?? '');
    const allowed = [1.0, 1.15, 1.3];
    if (parsed == null) return 1;
    for (final value in allowed) {
      if ((parsed - value).abs() < 0.01) return value;
    }
    return 1;
  }

  ThemeMode _theme(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
