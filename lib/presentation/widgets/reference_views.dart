import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/notes_models.dart';
import '../ui/ui.dart';

double _share(int count, int total) => total > 0 ? count / total : 0;
String _percent(double value) => '${(value * 100).round()}%';

class ReferencePanel extends StatelessWidget {
  const ReferencePanel(
      {super.key,
      required this.player,
      required this.reference,
      required this.ledger});
  final String player;
  final DocumentReference reference;
  final DamageLedger? ledger;

  @override
  Widget build(BuildContext context) {
    final after = reference.afterBlock;
    if (after?.own == null || after?.reference == null) {
      return const SizedBox(key: ValueKey('reference-panel'));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: UiPanel(
        key: const ValueKey('reference-panel'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: _AfterBlock(
            player: player, own: after!.own!, reference: after.reference!),
      ),
    );
  }
}

class _AfterBlock extends StatelessWidget {
  const _AfterBlock(
      {required this.player, required this.own, required this.reference});
  final String player;
  final ReferenceAnswers own;
  final ReferenceAnswers reference;

  @override
  Widget build(BuildContext context) {
    final a = {for (final answer in own.answers) answer.text: answer};
    final b = {for (final answer in reference.answers) answer.text: answer};
    final totalA =
        own.answers.fold<int>(0, (sum, answer) => sum + answer.count);
    final totalB =
        reference.answers.fold<int>(0, (sum, answer) => sum + answer.count);
    final names = {...a.keys, ...b.keys}.toList()
      ..sort((x, y) => math
          .max(_share(a[y]?.count ?? 0, totalA),
              _share(b[y]?.count ?? 0, totalB))
          .compareTo(math.max(_share(a[x]?.count ?? 0, totalA),
              _share(b[x]?.count ?? 0, totalB))));
    bool hasGap(String name) {
      final own = a[name];
      final reference = b[name];
      return own != null &&
          reference != null &&
          own.count >= 5 &&
          reference.count >= 5 &&
          5 * (own.gotHit * reference.count - reference.gotHit * own.count) >=
              own.count * reference.count;
    }

    Widget rate(SequenceAnswer? answer, Color color,
        {bool gap = false, Key? key}) {
      if (answer == null || answer.count == 0) {
        return Text('n/a', style: Ui.small.copyWith(color: Ui.inkLow));
      }
      return Row(children: [
        UiMeter(
            fraction: _share(answer.gotHit, answer.count),
            color: color,
            width: 44),
        const SizedBox(width: 8),
        Text(_percent(_share(answer.gotHit, answer.count)),
            key: key, style: Ui.figure),
        if (gap)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.arrow_upward_rounded, size: 14, color: Ui.bad),
          ),
      ]);
    }

    Widget picked(SequenceAnswer? answer, int total, Color color) =>
        Row(children: [
          UiMeter(
              fraction: _share(answer?.count ?? 0, total),
              color: color,
              width: 44),
          const SizedBox(width: 8),
          Text(_percent(_share(answer?.count ?? 0, total)), style: Ui.figure),
        ]);

    Widget line(Widget answer, Widget c1, Widget c2, Widget c3, Widget c4) =>
        Row(children: [
          Expanded(child: answer),
          SizedBox(width: 112, child: c1),
          SizedBox(width: 112, child: c2),
          const SizedBox(width: 14),
          SizedBox(width: 112, child: c3),
          SizedBox(width: 112, child: c4),
        ]);

    String summary(ReferenceAnswers value) =>
        '${_percent(_share(value.hits ?? 0, value.count ?? 0))} hit  ·  ${value.hits ?? 0} of ${value.count ?? 0}';

    return Column(
        key: const ValueKey('reference-after-block'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UiCaps('After blocking: what was picked and what it cost'),
          const SizedBox(height: 10),
          Wrap(spacing: 22, runSpacing: 6, children: [
            UiKey(color: Ui.you, label: 'You: ${summary(own)}'),
            UiKey(
                color: Ui.reference,
                label: 'High-level $player: ${summary(reference)}'),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                        width: math.max(700, constraints.maxWidth),
                        child: Column(children: [
                          line(
                              const UiCaps('Answer'),
                              const UiCaps('You picked'),
                              const UiCaps('You got hit'),
                              const UiCaps('High-level picked'),
                              const UiCaps('High-level got hit')),
                          const SizedBox(height: 6),
                          const Divider(height: 1),
                          for (final name in names.take(7))
                            Padding(
                              key: ValueKey('reference-answer-$name'),
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: line(
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Ui.body
                                        .copyWith(fontWeight: FontWeight.w600)),
                                picked(a[name], totalA, Ui.you),
                                rate(a[name], Ui.bad,
                                    gap: hasGap(name),
                                    key: hasGap(name)
                                        ? ValueKey('reference-gap-$name')
                                        : null),
                                picked(b[name], totalB, Ui.reference),
                                rate(b[name], Ui.reference),
                              ),
                            ),
                        ])),
                  )),
        ]);
  }
}
