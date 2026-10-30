import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smp_guide/app.dart';
import 'package:smp_guide/controller.dart';
import 'package:smp_guide/data/database.dart';
import 'package:smp_guide/data/repository.dart';
import 'package:smp_guide/data/sections.dart';
import 'package:smp_guide/data/snapshot.dart';
import 'package:smp_guide/data/stable_key.dart';
import 'package:smp_guide/data/sync.dart';

void main() {
  test('bundled snapshot uses the bot stable key', () async {
    final file = File('assets/snapshot.json');
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final snapshot = Snapshot.fromJson(json);
    final gynecology = snapshot.departments.firstWhere((row) => row.slug == 'gynecology');
    final o14 = snapshot.diagnoses.firstWhere((row) => row.displayCode == 'O14');
    expect(o14.departmentId, gynecology.id);
    expect(o14.stableKey, makeStableKey('gynecology', 'O14', o14.title));
    expect(snapshot.departments.map((row) => row.slug), contains('shock_coma'));
    expect(
      snapshot.departments.map((row) => row.slug),
      contains(continuousSectionSlug),
    );
  });

  test('search, shock section, neonatal text, and favorites survive a new snapshot', () async {
    final database = await AppDatabase.memory();
    final repository = ContentRepository(database);
    await repository.replaceContent(_fixture());

    final shock = await repository.departmentBySlug('shock_coma');
    final shockRows = await repository.diagnosesInDepartment(shock!.id);
    expect(shockRows.map((row) => row.title), ['Анафилактический шок']);

    final neonatal = await repository.continuousCards(continuousSectionSlug);
    expect(neonatal.single.care, 'Вентиляция 5 мл');

    final found = await repository.search('methyldopa');
    expect(found.single.displayCode, 'O15');

    expect(await repository.toggleFavorite('fav-key'), isTrue);
    final updated = _fixture(title: 'Эклампсия обновлённая', fingerprint: 'fp-2');
    await repository.replaceContent(updated);
    expect(await repository.storedFavoriteCount(), 1);
    final favorites = await repository.favorites();
    expect(favorites.single.title, 'Эклампсия обновлённая');

    final removed = _fixture(title: 'Другой диагноз');
    final withoutFavorite = Snapshot(
      formatVersion: removed.formatVersion,
      fingerprint: 'fp-3',
      exportedAt: removed.exportedAt,
      departments: removed.departments,
      diagnoses: removed.diagnoses.where((row) => row.stableKey != 'fav-key').toList(),
      subconditions: const [],
      treatments: removed.treatments,
      tactics: removed.tactics,
      medications: const [],
    );
    await repository.replaceContent(withoutFavorite);
    expect(await repository.storedFavoriteCount(), 1);
    expect(await repository.favorites(), isEmpty);
    await database.close();
  });

  test('sync keeps the local copy when offline and skips an unchanged fingerprint', () async {
    final database = await AppDatabase.memory();
    final repository = ContentRepository(database);
    await repository.replaceContent(_fixture());
    await repository.toggleFavorite('fav-key');
    final source = _MemorySource(_fixture());
    final sync = ContentSync(source);
    await repository.setMeta('auth_token', 'token');

    final same = await sync.run(
      baseUrl: 'http://station.local',
      token: 'token',
      localFingerprint: 'fp-1',
      replace: repository.replaceContent,
      clearToken: () => repository.deleteMeta('auth_token'),
    );
    expect(same, SyncOutcome.upToDate);
    expect(source.downloads, 0);

    source.snapshot = _fixture(title: 'После синхронизации', fingerprint: 'fp-2');
    final changed = await sync.run(
      baseUrl: 'http://station.local',
      token: 'token',
      localFingerprint: await repository.meta('fingerprint'),
      replace: repository.replaceContent,
      clearToken: () => repository.deleteMeta('auth_token'),
    );
    expect(changed, SyncOutcome.updated);
    expect(source.downloads, 1);
    expect((await repository.favorites()).single.title, 'После синхронизации');

    source.online = false;
    final offline = await sync.run(
      baseUrl: 'http://station.local',
      token: 'token',
      localFingerprint: 'other',
      replace: repository.replaceContent,
      clearToken: () => repository.deleteMeta('auth_token'),
    );
    expect(offline, SyncOutcome.offline);
    expect((await repository.diagnosisByKey('fav-key'))!.title, 'После синхронизации');

    final locked = await sync.run(
      baseUrl: 'http://station.local',
      token: null,
      localFingerprint: null,
      replace: repository.replaceContent,
      clearToken: () => repository.deleteMeta('auth_token'),
    );
    expect(locked, SyncOutcome.authRequired);
    await database.close();
  });

  testWidgets('home opens a section, shock list, and neonatal document', (tester) async {
    final database = await AppDatabase.memory();
    final repository = ContentRepository(database);
    await repository.replaceContent(_fixture());
    final controller = ContentController(
      repository: repository,
      source: _MemorySource(_fixture()),
    );
    await controller.load(syncOnStart: false);
    await tester.pumpWidget(SmpApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('ГИНЕКОЛОГИЯ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('department-shock_coma')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Анафилактический шок'), findsOneWidget);
    expect(find.textContaining('Только кардиология'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('department-neonatal_resuscitation')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Вентиляция 5 мл'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('department-gynecology')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Эклампсия'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.1'), findsOneWidget);
    await tester.tap(find.textContaining('1.1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('25%'), findsOneWidget);
    await database.close();
  });
}

Snapshot _fixture({String title = 'Эклампсия', String fingerprint = 'fp-1'}) {
  return Snapshot(
    formatVersion: 1,
    fingerprint: fingerprint,
    exportedAt: '2026-01-01T00:00:00+00:00',
    departments: [
      DepartmentSeed(id: 3, slug: 'cardiology', title: 'КАРДИОЛОГИЯ', sortOrder: 0),
      DepartmentSeed(id: 1, slug: 'gynecology', title: 'ГИНЕКОЛОГИЯ', sortOrder: 1),
      DepartmentSeed(id: 2, slug: 'shock_coma', title: 'ШОКИ / КОМЫ', sortOrder: 2),
      DepartmentSeed(
        id: 4,
        slug: continuousSectionSlug,
        title: 'РЕАНИМАЦИЯ НОВОРОЖДЕННЫХ',
        sortOrder: 3,
      ),
    ],
    diagnoses: [
      DiagnosisSeed(
        id: 10,
        stableKey: 'fav-key',
        departmentId: 1,
        title: title,
        displayCode: 'O15',
        searchBlob: 'эклампсия methyldopa',
        mnnHints: 'methyldopa',
      ),
      DiagnosisSeed(
        id: 11,
        stableKey: 'shock-key',
        departmentId: 2,
        title: 'Анафилактический шок',
        searchBlob: 'шок',
        includeInShockComa: true,
      ),
      DiagnosisSeed(
        id: 12,
        stableKey: 'cardio-key',
        departmentId: 3,
        title: 'Только кардиология',
        searchBlob: 'кардио',
        includeInShockComa: true,
      ),
      DiagnosisSeed(
        id: 13,
        stableKey: 'neo-key',
        departmentId: 4,
        title: 'Стартовая вентиляция',
        searchBlob: 'вентиляция',
      ),
    ],
    subconditions: [
      SubconditionSeed(
        id: 100,
        diagnosisId: 10,
        codeLabel: '1.1',
        title: 'Тяжёлая',
        sortOrder: 0,
      ),
    ],
    treatments: [
      TextBlockSeed(id: 1, diagnosisId: 10, body: 'Базовый объём'),
      TextBlockSeed(id: 2, subconditionId: 100, body: 'Магния сульфат 25% 20 мл'),
      TextBlockSeed(id: 3, diagnosisId: 13, body: 'Вентиляция 5 мл'),
      TextBlockSeed(id: 4, diagnosisId: 11, body: 'Адреналин'),
    ],
    tactics: [
      TextBlockSeed(id: 1, diagnosisId: 10, body: 'Эвакуация'),
      TextBlockSeed(id: 2, subconditionId: 100, body: ''),
      TextBlockSeed(id: 3, diagnosisId: 13, body: 'В стационар'),
    ],
    medications: [
      MedicationSeed(id: 1, nameNormalized: 'methyldopa', diagnosisId: 10),
    ],
  );
}

class _MemorySource implements SnapshotSource {
  _MemorySource(this.snapshot);

  Snapshot snapshot;
  int downloads = 0;
  bool online = true;

  @override
  Future<Snapshot> download(String baseUrl, String token) async {
    if (!online) throw SyncTransportException('offline', offline: true);
    if (token != 'token') throw AuthException();
    downloads += 1;
    return snapshot;
  }

  @override
  Future<String> login(String baseUrl, String password) async {
    if (!online) throw SyncTransportException('offline', offline: true);
    return 'token';
  }

  @override
  Future<ContentManifest> manifest(String baseUrl, String token) async {
    if (!online) throw SyncTransportException('offline', offline: true);
    if (token != 'token') throw AuthException();
    return ContentManifest(
      formatVersion: 1,
      fingerprint: snapshot.fingerprint,
      exportedAt: snapshot.exportedAt,
      diagnosisCount: snapshot.diagnoses.length,
    );
  }
}
