import 'dart:convert';

import 'card_format.dart';
import 'database.dart';
import 'models.dart';
import 'snapshot.dart';

class ContentRepository {
  ContentRepository(this.db);

  final AppDatabase db;

  Future<void> ensureBundled(String snapshotJson) async {
    final rows = await db.query('SELECT COUNT(*) AS n FROM diagnoses');
    if (rows.isNotEmpty && _int(rows.single['n']) > 0) return;
    await replaceContent(
      Snapshot.fromJson(jsonDecode(snapshotJson) as Map<String, dynamic>),
    );
  }

  Future<void> replaceContent(Snapshot snapshot) async {
    final medsByDiagnosis = <int, List<String>>{};
    for (final medication in snapshot.medications) {
      medsByDiagnosis
          .putIfAbsent(medication.diagnosisId, () => [])
          .add(medication.nameNormalized);
    }

    await db.transaction(() async {
      await db.execute('DELETE FROM medications');
      await db.execute('DELETE FROM tactics');
      await db.execute('DELETE FROM treatments');
      await db.execute('DELETE FROM subconditions');
      await db.execute('DELETE FROM diagnoses');
      await db.execute('DELETE FROM departments');
      if (db.ftsReady) {
        await db.execute('DELETE FROM diagnosis_fts');
      }

      for (final row in snapshot.departments) {
        await db.execute(
          '''
INSERT INTO departments(
  id, slug, title, sort_order, card_label_diagnosis, card_label_care, card_label_tactic
) VALUES (?, ?, ?, ?, ?, ?, ?)
''',
          [
            row.id,
            row.slug,
            row.title,
            row.sortOrder,
            row.cardLabelDiagnosis,
            row.cardLabelCare,
            row.cardLabelTactic,
          ],
        );
      }
      for (final row in snapshot.diagnoses) {
        await db.execute(
          '''
INSERT INTO diagnoses(
  id, stable_key, department_id, display_code, title, conditions_note, branch_prompt,
  mnn_hints, is_emergency, include_in_shock_coma, search_blob, source_file,
  department_sort_order, ingest_sequence, list_sort_tail
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
          [
            row.id,
            row.stableKey,
            row.departmentId,
            row.displayCode,
            row.title,
            row.conditionsNote,
            row.branchPrompt,
            row.mnnHints,
            row.isEmergency ? 1 : 0,
            row.includeInShockComa ? 1 : 0,
            row.searchBlob,
            row.sourceFile,
            row.departmentSortOrder,
            row.ingestSequence,
            row.listSortTail ? 1 : 0,
          ],
        );
      }
      for (final row in snapshot.subconditions) {
        await db.execute(
          '''
INSERT INTO subconditions(
  id, diagnosis_id, code_label, title, conditions_detail, sort_order
) VALUES (?, ?, ?, ?, ?, ?)
''',
          [
            row.id,
            row.diagnosisId,
            row.codeLabel,
            row.title,
            row.conditionsDetail,
            row.sortOrder,
          ],
        );
      }
      for (final row in snapshot.treatments) {
        await db.execute(
          '''
INSERT INTO treatments(id, body, diagnosis_id, subcondition_id)
VALUES (?, ?, ?, ?)
''',
          [row.id, row.body, row.diagnosisId, row.subconditionId],
        );
      }
      for (final row in snapshot.tactics) {
        await db.execute(
          '''
INSERT INTO tactics(id, body, diagnosis_id, subcondition_id)
VALUES (?, ?, ?, ?)
''',
          [row.id, row.body, row.diagnosisId, row.subconditionId],
        );
      }
      for (final row in snapshot.medications) {
        await db.execute(
          '''
INSERT INTO medications(
  id, name_normalized, diagnosis_id, subcondition_id, source_hint
) VALUES (?, ?, ?, ?, ?)
''',
          [
            row.id,
            row.nameNormalized,
            row.diagnosisId,
            row.subconditionId,
            row.sourceHint,
          ],
        );
      }

      if (db.ftsReady) {
        for (final row in snapshot.diagnoses) {
          final names = (medsByDiagnosis[row.id] ?? []).join(' ');
          await db.execute(
            '''
INSERT INTO diagnosis_fts(stable_key, title, search_blob, medication_names)
VALUES (?, ?, ?, ?)
''',
            [row.stableKey, row.title, row.searchBlob, names],
          );
        }
      }

      await _setMetaInside('fingerprint', snapshot.fingerprint);
      await _setMetaInside('exported_at', snapshot.exportedAt);
    });
  }

  Future<List<Department>> departments() async {
    final rows = await db.query(
      'SELECT * FROM departments ORDER BY sort_order, id',
    );
    return [for (final row in rows) Department.fromRow(row)];
  }

  Future<Department?> departmentBySlug(String slug) async {
    final rows = await db.query(
      'SELECT * FROM departments WHERE slug = ? LIMIT 1',
      [slug],
    );
    if (rows.isEmpty) return null;
    return Department.fromRow(rows.single);
  }

  Future<List<Diagnosis>> diagnosesInDepartment(int departmentId) async {
    final rows = await db.query(
      '''
SELECT * FROM diagnoses
WHERE department_id = ?
ORDER BY list_sort_tail, department_sort_order, ingest_sequence, id
''',
      [departmentId],
    );
    return [for (final row in rows) Diagnosis.fromRow(row)];
  }

  Future<Diagnosis?> diagnosisByKey(String stableKey) async {
    final rows = await db.query(
      'SELECT * FROM diagnoses WHERE stable_key = ? LIMIT 1',
      [stableKey],
    );
    if (rows.isEmpty) return null;
    return Diagnosis.fromRow(rows.single);
  }

  Future<List<Subcondition>> subconditionsOf(int diagnosisId) async {
    final rows = await db.query(
      '''
SELECT * FROM subconditions
WHERE diagnosis_id = ?
ORDER BY sort_order, id
''',
      [diagnosisId],
    );
    return [for (final row in rows) Subcondition.fromRow(row)];
  }

  Future<List<Diagnosis>> search(String raw) async {
    final query = raw.trim();
    if (query.length < 2) return [];
    final match = _ftsQuery(query);
    if (match.isEmpty) return [];
    if (db.ftsReady) {
      try {
        final rows = await db.query(
          '''
SELECT diagnoses.stable_key AS stable_key
FROM diagnosis_fts
JOIN diagnoses ON diagnoses.stable_key = diagnosis_fts.stable_key
WHERE diagnosis_fts MATCH ?
LIMIT 40
''',
          [match],
        );
        return await _diagnosesByKeys(rows.map((row) => row['stable_key'] as String));
      } catch (_) {}
    }
    final like = '%${query.toLowerCase()}%';
    final rows = await db.query(
      '''
SELECT DISTINCT d.stable_key AS stable_key
FROM diagnoses d
LEFT JOIN medications m ON m.diagnosis_id = d.id
WHERE lower(d.title) LIKE ?
   OR lower(d.search_blob) LIKE ?
   OR lower(ifnull(m.name_normalized, '')) LIKE ?
LIMIT 40
''',
      [like, like, like],
    );
    return _diagnosesByKeys(rows.map((row) => row['stable_key'] as String));
  }

  Future<bool> isFavorite(String stableKey) async {
    final rows = await db.query(
      'SELECT stable_key FROM favorites WHERE stable_key = ? LIMIT 1',
      [stableKey],
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleFavorite(String stableKey) async {
    if (await isFavorite(stableKey)) {
      await db.execute('DELETE FROM favorites WHERE stable_key = ?', [stableKey]);
      return false;
    }
    await db.execute('INSERT INTO favorites(stable_key) VALUES (?)', [stableKey]);
    return true;
  }

  Future<List<Diagnosis>> favorites() async {
    final rows = await db.query(
      '''
SELECT d.stable_key AS stable_key
FROM favorites f
JOIN diagnoses d ON d.stable_key = f.stable_key
ORDER BY f.created_at DESC
''',
    );
    return _diagnosesByKeys(rows.map((row) => row['stable_key'] as String));
  }

  Future<int> storedFavoriteCount() async {
    final rows = await db.query('SELECT COUNT(*) AS n FROM favorites');
    if (rows.isEmpty) return 0;
    return _int(rows.single['n']);
  }

  Future<CardContent?> cardFor(String stableKey, {int? subId}) async {
    final diagnosis = await diagnosisByKey(stableKey);
    if (diagnosis == null) return null;
    final departments = await db.query(
      'SELECT * FROM departments WHERE id = ? LIMIT 1',
      [diagnosis.departmentId],
    );
    final department = Department.fromRow(departments.single);
    Subcondition? sub;
    if (subId != null) {
      final rows = await db.query(
        'SELECT * FROM subconditions WHERE id = ? LIMIT 1',
        [subId],
      );
      if (rows.isNotEmpty) sub = Subcondition.fromRow(rows.single);
    }
    final careMain = await _body('treatments', diagnosisId: diagnosis.id);
    final tacticMain = await _body('tactics', diagnosisId: diagnosis.id);
    final careSub = sub == null ? '' : await _body('treatments', subconditionId: sub.id);
    final tacticSub = sub == null ? '' : await _body('tactics', subconditionId: sub.id);
    return buildCard(
      stableKey: diagnosis.stableKey,
      title: diagnosis.title,
      displayCode: diagnosis.displayCode,
      conditionsNote: diagnosis.conditionsNote,
      mnnHints: diagnosis.mnnHints,
      cardLabelDiagnosis: department.cardLabelDiagnosis,
      cardLabelCare: department.cardLabelCare,
      cardLabelTactic: department.cardLabelTactic,
      careMain: careMain,
      tacticMain: tacticMain,
      subCode: sub?.codeLabel,
      subTitle: sub?.title,
      subDetail: sub?.conditionsDetail,
      careSub: careSub,
      tacticSub: tacticSub,
    );
  }

  Future<List<CardContent>> continuousCards(String slug) async {
    final department = await departmentBySlug(slug);
    if (department == null) return [];
    final diagnoses = await diagnosesInDepartment(department.id);
    final cards = <CardContent>[];
    for (final diagnosis in diagnoses) {
      final subs = await subconditionsOf(diagnosis.id);
      if (subs.isEmpty) {
        final card = await cardFor(diagnosis.stableKey);
        if (card != null) cards.add(card);
      } else {
        for (final sub in subs) {
          final card = await cardFor(diagnosis.stableKey, subId: sub.id);
          if (card != null) cards.add(card);
        }
      }
    }
    return cards;
  }

  Future<String?> meta(String key) async {
    final rows = await db.query(
      'SELECT value FROM local_meta WHERE key = ? LIMIT 1',
      [key],
    );
    if (rows.isEmpty) return null;
    return rows.single['value'] as String?;
  }

  Future<void> setMeta(String key, String value) => _setMetaInside(key, value);

  Future<void> deleteMeta(String key) {
    return db.execute('DELETE FROM local_meta WHERE key = ?', [key]);
  }

  Future<void> _setMetaInside(String key, String value) {
    return db.execute(
      '''
INSERT INTO local_meta(key, value) VALUES (?, ?)
ON CONFLICT(key) DO UPDATE SET value = excluded.value
''',
      [key, value],
    );
  }

  Future<String> _body(
    String table, {
    int? diagnosisId,
    int? subconditionId,
  }) async {
    final rows = diagnosisId != null
        ? await db.query(
            'SELECT body FROM $table WHERE diagnosis_id = ? LIMIT 1',
            [diagnosisId],
          )
        : await db.query(
            'SELECT body FROM $table WHERE subcondition_id = ? LIMIT 1',
            [subconditionId],
          );
    if (rows.isEmpty) return '';
    return rows.single['body'] as String? ?? '';
  }

  Future<List<Diagnosis>> _diagnosesByKeys(Iterable<String> keys) async {
    final result = <Diagnosis>[];
    for (final key in keys) {
      final diagnosis = await diagnosisByKey(key);
      if (diagnosis != null) result.add(diagnosis);
    }
    return result;
  }

  String _ftsQuery(String raw) {
    final parts = <String>[];
    for (final token in raw.toLowerCase().split(RegExp(r'\s+'))) {
      final cleaned = token.replaceAll('"', '').replaceAll('*', '');
      if (cleaned.isEmpty) continue;
      parts.add('"$cleaned"*');
    }
    return parts.join(' ');
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
