import 'sections.dart';

final _doseLine = RegExp(
  r'(мг|мл|UI|МЕ|%|мм\s*рт|п/мин|капель|таб|амп|фл|руб|ст\.|ст\.)',
  caseSensitive: false,
);
final _numberedLine = RegExp(r'^\d+[\.\)]\s+');

bool emphasizeLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return false;
  return _doseLine.hasMatch(trimmed) || _numberedLine.hasMatch(trimmed);
}

class CardContent {
  CardContent({
    required this.stableKey,
    required this.diagnosisLabel,
    required this.exportDiagnosisLabel,
    required this.title,
    required this.careLabel,
    required this.exportCareLabel,
    required this.care,
    required this.tacticLabel,
    required this.exportTacticLabel,
    required this.tactic,
    required this.plainText,
    this.code,
    this.conditionHeading,
    this.conditionBody,
    this.mnn,
  });

  final String stableKey;
  final String diagnosisLabel;
  final String exportDiagnosisLabel;
  final String title;
  final String? code;
  final String? conditionHeading;
  final String? conditionBody;
  final String careLabel;
  final String exportCareLabel;
  final String care;
  final String tacticLabel;
  final String exportTacticLabel;
  final String tactic;
  final String? mnn;
  final String plainText;
}

String _customOr(String? custom, String fallback) {
  final trimmed = custom?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

String? _blank(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String mergeCare(String main, String sub) {
  final parent = main.trim();
  final child = sub.trim();
  if (parent.isNotEmpty && child.isNotEmpty) return '$parent\n\n$child';
  if (child.isNotEmpty) return child;
  return parent;
}

String mergeTactic(String main, String sub, {required bool hasSub}) {
  if (!hasSub) return main.trim();
  final child = sub.trim();
  return child.isNotEmpty ? child : main.trim();
}

CardContent buildCard({
  required String stableKey,
  required String title,
  required String? displayCode,
  required String? conditionsNote,
  required String? mnnHints,
  required String? cardLabelDiagnosis,
  required String? cardLabelCare,
  required String? cardLabelTactic,
  required String careMain,
  required String tacticMain,
  String? subCode,
  String? subTitle,
  String? subDetail,
  String careSub = '',
  String tacticSub = '',
}) {
  final hasSub = subCode != null;
  final diagnosisLabel = _customOr(cardLabelDiagnosis, 'ДИАГНОЗ');
  final careLabel = _customOr(cardLabelCare, 'ОБЪЁМ ПОМОЩИ');
  final tacticLabel = _customOr(cardLabelTactic, 'ТАКТИКА');
  final exportDiagnosisLabel = _customOr(cardLabelDiagnosis, 'Диагноз');
  final exportCareLabel = _customOr(cardLabelCare, 'Объём помощи');
  final exportTacticLabel = _customOr(cardLabelTactic, 'Тактика');

  String? conditionHeading;
  String? conditionBody;
  if (hasSub) {
    conditionHeading = 'УСЛОВИЕ: $subCode — $subTitle';
    conditionBody = _blank(subDetail);
  } else {
    conditionBody = _blank(conditionsNote);
    if (conditionBody != null) {
      conditionHeading = 'УСЛОВИЕ / ГРАДАЦИЯ';
    }
  }

  final care = mergeCare(careMain, hasSub ? careSub : '');
  final tactic = mergeTactic(tacticMain, tacticSub, hasSub: hasSub);
  final mnn = _blank(mnnHints);
  final card = CardContent(
    stableKey: stableKey,
    diagnosisLabel: diagnosisLabel,
    exportDiagnosisLabel: exportDiagnosisLabel,
    title: title,
    code: _blank(displayCode),
    conditionHeading: conditionHeading,
    conditionBody: conditionBody,
    careLabel: careLabel,
    exportCareLabel: exportCareLabel,
    care: care,
    tacticLabel: tacticLabel,
    exportTacticLabel: exportTacticLabel,
    tactic: tactic,
    mnn: mnn,
    plainText: '',
  );
  return CardContent(
    stableKey: card.stableKey,
    diagnosisLabel: card.diagnosisLabel,
    exportDiagnosisLabel: card.exportDiagnosisLabel,
    title: card.title,
    code: card.code,
    conditionHeading: card.conditionHeading,
    conditionBody: card.conditionBody,
    careLabel: card.careLabel,
    exportCareLabel: card.exportCareLabel,
    care: card.care,
    tacticLabel: card.tacticLabel,
    exportTacticLabel: card.exportTacticLabel,
    tactic: card.tactic,
    mnn: card.mnn,
    plainText: _plain(card),
  );
}

String _plain(CardContent card) {
  final buffer = StringBuffer();
  final code = card.code == null ? '' : ' (${card.code})';
  buffer.writeln('${card.exportDiagnosisLabel}: ${card.title}$code');
  if (card.conditionHeading != null) {
    buffer.writeln();
    buffer.writeln(card.conditionHeading);
    if (card.conditionBody != null) buffer.writeln(card.conditionBody);
  }
  if (card.care.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('${card.exportCareLabel}:');
    buffer.writeln(card.care.trim());
  }
  if (card.tactic.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('${card.exportTacticLabel}:');
    buffer.writeln(card.tactic.trim());
  }
  if (card.mnn != null) {
    buffer.writeln();
    buffer.writeln('МНН: ${card.mnn}');
  }
  buffer.writeln();
  buffer.writeln(kDisclaimer);
  return buffer.toString().trim();
}
