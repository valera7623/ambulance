class Snapshot {
  Snapshot({
    required this.formatVersion,
    required this.fingerprint,
    required this.exportedAt,
    required this.departments,
    required this.diagnoses,
    required this.subconditions,
    required this.treatments,
    required this.tactics,
    required this.medications,
  });

  final int formatVersion;
  final String fingerprint;
  final String exportedAt;
  final List<DepartmentSeed> departments;
  final List<DiagnosisSeed> diagnoses;
  final List<SubconditionSeed> subconditions;
  final List<TextBlockSeed> treatments;
  final List<TextBlockSeed> tactics;
  final List<MedicationSeed> medications;

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    final version = json['format_version'];
    if (version != 1) {
      throw FormatException('Unsupported snapshot format: $version');
    }
    return Snapshot(
      formatVersion: 1,
      fingerprint: json['fingerprint'] as String,
      exportedAt: json['exported_at'] as String,
      departments: [
        for (final row in json['departments'] as List<dynamic>)
          DepartmentSeed.fromJson(row as Map<String, dynamic>),
      ],
      diagnoses: [
        for (final row in json['diagnoses'] as List<dynamic>)
          DiagnosisSeed.fromJson(row as Map<String, dynamic>),
      ],
      subconditions: [
        for (final row in json['subconditions'] as List<dynamic>)
          SubconditionSeed.fromJson(row as Map<String, dynamic>),
      ],
      treatments: [
        for (final row in json['treatments'] as List<dynamic>)
          TextBlockSeed.fromJson(row as Map<String, dynamic>),
      ],
      tactics: [
        for (final row in json['tactics'] as List<dynamic>)
          TextBlockSeed.fromJson(row as Map<String, dynamic>),
      ],
      medications: [
        for (final row in json['medications'] as List<dynamic>)
          MedicationSeed.fromJson(row as Map<String, dynamic>),
      ],
    );
  }
}

class ContentManifest {
  ContentManifest({
    required this.formatVersion,
    required this.fingerprint,
    required this.exportedAt,
    required this.diagnosisCount,
  });

  final int formatVersion;
  final String fingerprint;
  final String exportedAt;
  final int diagnosisCount;

  factory ContentManifest.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>? ?? {};
    return ContentManifest(
      formatVersion: json['format_version'] as int? ?? 1,
      fingerprint: json['fingerprint'] as String,
      exportedAt: json['exported_at'] as String? ?? '',
      diagnosisCount: counts['diagnoses'] as int? ?? 0,
    );
  }
}

class DepartmentSeed {
  DepartmentSeed({
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

  factory DepartmentSeed.fromJson(Map<String, dynamic> json) {
    return DepartmentSeed(
      id: json['id'] as int,
      slug: json['slug'] as String,
      title: json['title'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
      cardLabelDiagnosis: json['card_label_diagnosis'] as String?,
      cardLabelCare: json['card_label_care'] as String?,
      cardLabelTactic: json['card_label_tactic'] as String?,
    );
  }
}

class DiagnosisSeed {
  DiagnosisSeed({
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

  factory DiagnosisSeed.fromJson(Map<String, dynamic> json) {
    return DiagnosisSeed(
      id: json['id'] as int,
      stableKey: json['stable_key'] as String,
      departmentId: json['department_id'] as int,
      displayCode: json['display_code'] as String?,
      title: json['title'] as String,
      conditionsNote: json['conditions_note'] as String?,
      branchPrompt: json['branch_prompt'] as String?,
      mnnHints: json['mnn_hints'] as String?,
      isEmergency: json['is_emergency'] as bool? ?? false,
      includeInShockComa: json['include_in_shock_coma'] as bool? ?? false,
      searchBlob: json['search_blob'] as String? ?? '',
      sourceFile: json['source_file'] as String?,
      departmentSortOrder: json['department_sort_order'] as int? ?? 0,
      ingestSequence: json['ingest_sequence'] as int? ?? 0,
      listSortTail: json['list_sort_tail'] as bool? ?? false,
    );
  }
}

class SubconditionSeed {
  SubconditionSeed({
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

  factory SubconditionSeed.fromJson(Map<String, dynamic> json) {
    return SubconditionSeed(
      id: json['id'] as int,
      diagnosisId: json['diagnosis_id'] as int,
      codeLabel: json['code_label'] as String,
      title: json['title'] as String,
      conditionsDetail: json['conditions_detail'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class TextBlockSeed {
  TextBlockSeed({
    required this.id,
    required this.body,
    this.diagnosisId,
    this.subconditionId,
  });

  final int id;
  final int? diagnosisId;
  final int? subconditionId;
  final String body;

  factory TextBlockSeed.fromJson(Map<String, dynamic> json) {
    return TextBlockSeed(
      id: json['id'] as int,
      diagnosisId: json['diagnosis_id'] as int?,
      subconditionId: json['subcondition_id'] as int?,
      body: json['body'] as String? ?? '',
    );
  }
}

class MedicationSeed {
  MedicationSeed({
    required this.id,
    required this.nameNormalized,
    required this.diagnosisId,
    this.subconditionId,
    this.sourceHint,
  });

  final int id;
  final String nameNormalized;
  final int diagnosisId;
  final int? subconditionId;
  final String? sourceHint;

  factory MedicationSeed.fromJson(Map<String, dynamic> json) {
    return MedicationSeed(
      id: json['id'] as int,
      nameNormalized: json['name_normalized'] as String,
      diagnosisId: json['diagnosis_id'] as int,
      subconditionId: json['subcondition_id'] as int?,
      sourceHint: json['source_hint'] as String?,
    );
  }
}
