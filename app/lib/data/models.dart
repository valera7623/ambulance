class Department {
  Department({
    required this.id,
    required this.slug,
    required this.title,
    required this.sortOrder,
    this.cardLabelDiagnosis,
    this.cardLabelCare,
    this.cardLabelTactic,
  });

  final int id;
  final String slug;
  final String title;
  final int sortOrder;
  final String? cardLabelDiagnosis;
  final String? cardLabelCare;
  final String? cardLabelTactic;

  factory Department.fromRow(Map<String, Object?> row) {
    return Department(
      id: asInt(row['id']),
      slug: row['slug'] as String,
      title: row['title'] as String,
      sortOrder: asInt(row['sort_order']),
      cardLabelDiagnosis: row['card_label_diagnosis'] as String?,
      cardLabelCare: row['card_label_care'] as String?,
      cardLabelTactic: row['card_label_tactic'] as String?,
    );
  }
}

class Diagnosis {
  Diagnosis({
    required this.id,
    required this.stableKey,
    required this.departmentId,
    required this.title,
    required this.searchBlob,
    this.displayCode,
    this.conditionsNote,
    this.branchPrompt,
    this.mnnHints,
    this.isEmergency = false,
    this.includeInShockComa = false,
    this.sourceFile,
    this.departmentSortOrder = 0,
    this.ingestSequence = 0,
    this.listSortTail = false,
  });

  final int id;
  final String stableKey;
  final int departmentId;
  final String? displayCode;
  final String title;
  final String? conditionsNote;
  final String? branchPrompt;
  final String? mnnHints;
  final bool isEmergency;
  final bool includeInShockComa;
  final String searchBlob;
  final String? sourceFile;
  final int departmentSortOrder;
  final int ingestSequence;
  final bool listSortTail;

  factory Diagnosis.fromRow(Map<String, Object?> row) {
    return Diagnosis(
      id: asInt(row['id']),
      stableKey: row['stable_key'] as String,
      departmentId: asInt(row['department_id']),
      displayCode: row['display_code'] as String?,
      title: row['title'] as String,
      conditionsNote: row['conditions_note'] as String?,
      branchPrompt: row['branch_prompt'] as String?,
      mnnHints: row['mnn_hints'] as String?,
      isEmergency: asBool(row['is_emergency']),
      includeInShockComa: asBool(row['include_in_shock_coma']),
      searchBlob: row['search_blob'] as String? ?? '',
      sourceFile: row['source_file'] as String?,
      departmentSortOrder: asInt(row['department_sort_order']),
      ingestSequence: asInt(row['ingest_sequence']),
      listSortTail: asBool(row['list_sort_tail']),
    );
  }
}

class Subcondition {
  Subcondition({
    required this.id,
    required this.diagnosisId,
    required this.codeLabel,
    required this.title,
    this.conditionsDetail,
    this.sortOrder = 0,
  });

  final int id;
  final int diagnosisId;
  final String codeLabel;
  final String title;
  final String? conditionsDetail;
  final int sortOrder;

  factory Subcondition.fromRow(Map<String, Object?> row) {
    return Subcondition(
      id: asInt(row['id']),
      diagnosisId: asInt(row['diagnosis_id']),
      codeLabel: row['code_label'] as String,
      title: row['title'] as String,
      conditionsDetail: row['conditions_detail'] as String?,
      sortOrder: asInt(row['sort_order']),
    );
  }
}

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw StateError('Expected an integer, got $value');
}

bool asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return false;
}
