import 'package:flutter_test/flutter_test.dart';

import 'package:smp_guide/data/card_format.dart';

void main() {
  test('care of a subcondition is appended and tactic falls back to the parent', () {
    final card = buildCard(
      stableKey: 'k',
      title: 'Преэклампсия',
      displayCode: 'O14',
      conditionsNote: 'Общая градация',
      mnnHints: 'methyldopa',
      cardLabelDiagnosis: null,
      cardLabelCare: null,
      cardLabelTactic: 'Путь эвакуации',
      careMain: 'Базовый объём',
      tacticMain: 'Тактика родителя',
      subCode: '1.1',
      subTitle: 'Тяжёлая',
      subDetail: 'АД высокое',
      careSub: 'Магния сульфат 25% 20 мл',
      tacticSub: '',
    );

    expect(card.diagnosisLabel, 'ДИАГНОЗ');
    expect(card.careLabel, 'ОБЪЁМ ПОМОЩИ');
    expect(card.tacticLabel, 'Путь эвакуации');
    expect(card.exportTacticLabel, 'Путь эвакуации');
    expect(card.care, 'Базовый объём\n\nМагния сульфат 25% 20 мл');
    expect(card.tactic, 'Тактика родителя');
    expect(card.conditionHeading, 'УСЛОВИЕ: 1.1 — Тяжёлая');
    expect(card.plainText, contains('Объём помощи:'));
    expect(card.plainText, contains('Материалы носят справочный характер'));
    expect(emphasizeLine('Магния сульфат 25% 20 мл'), isTrue);
    expect(emphasizeLine('1. Осмотреть'), isTrue);
    expect(emphasizeLine('Контроль дыхания'), isFalse);
  });
}
