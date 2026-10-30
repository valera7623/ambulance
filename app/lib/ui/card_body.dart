import 'package:flutter/material.dart';

import '../data/card_format.dart';
import '../data/sections.dart';

class CardBody extends StatelessWidget {
  const CardBody({required this.card, super.key});

  final CardContent card;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[
      _heading(context, card.diagnosisLabel),
      Text(
        card.code == null ? card.title : '${card.title}  ${card.code}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ];
    if (card.conditionHeading != null) {
      blocks
        ..add(const SizedBox(height: 16))
        ..add(_heading(context, card.conditionHeading!));
      if (card.conditionBody != null) blocks.add(_prose(context, card.conditionBody!));
    }
    if (card.care.trim().isNotEmpty) {
      blocks
        ..add(const SizedBox(height: 16))
        ..add(_heading(context, card.careLabel))
        ..add(_prose(context, card.care));
    }
    if (card.tactic.trim().isNotEmpty) {
      blocks
        ..add(const SizedBox(height: 16))
        ..add(_heading(context, card.tacticLabel))
        ..add(_prose(context, card.tactic));
    }
    if (card.mnn != null) {
      blocks
        ..add(const SizedBox(height: 16))
        ..add(_heading(context, 'МНН'))
        ..add(Text(card.mnn!, style: Theme.of(context).textTheme.bodyLarge));
    }
    blocks
      ..add(const SizedBox(height: 28))
      ..add(Text(kDisclaimer, style: Theme.of(context).textTheme.bodySmall));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: blocks,
    );
  }

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
      ),
    );
  }

  Widget _prose(BuildContext context, String text) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final children = <Widget>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line.trim(),
            style: emphasizeLine(line)
                ? style?.copyWith(fontWeight: FontWeight.w700)
                : style,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
