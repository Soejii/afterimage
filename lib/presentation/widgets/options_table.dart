import 'package:flutter/material.dart';

import '../../domain/notes_models.dart';
import '../ui/ui.dart';
import 'move_card_views.dart';

/// One row per option the player has in a spot: how often it was picked, what
/// happened, how often high-level players pick it, and what it beats on paper.
class OptionsTable extends StatelessWidget {
  const OptionsTable({
    super.key,
    required this.spot,
    required this.player,
    required this.opponent,
    required this.moves,
    this.reference,
    this.recommended = const {},
    this.recommendedProven = true,
  });

  final SituationSpot spot;
  final String player;
  final String opponent;
  final Map<String, MoveCard> moves;

  /// The card's comparison, when the list has one.
  final CardReference? reference;

  /// Rows the verdict names. They are shown even when never tried.
  final Set<String> recommended;

  /// False when the verdict only holds on paper.
  final bool recommendedProven;

  static const _maxRows = 8;

  @override
  Widget build(BuildContext context) {
    final match =
        reference?.spots.where((item) => item.kind == spot.kind).firstOrNull;
    final theirs = {
      if (match != null)
        for (final row in match.playerRows)
          if (row.name != null) row.name!: row
    };
    final own = {for (final row in spot.playerRows) row.name: row};
    final seen = spot.playerRows.where((row) => row.seen).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final names = <String>[
      for (final row in seen) row.name,
      for (final name in recommended)
        if (own.containsKey(name) && !own[name]!.seen) name,
      ...(theirs.keys.where((name) => !(own[name]?.seen ?? false)).toList()
        ..sort((a, b) =>
            (theirs[b]!.count ?? 0).compareTo(theirs[a]!.count ?? 0))),
    ];
    final rows = <String>[];
    for (final name in names) {
      if (!rows.contains(name)) rows.add(name);
    }
    final shown = rows.take(_maxRows).toList();
    final shownOpponent = [
      for (final row in spot.opponentRows)
        if (row.count > 0) row.name
    ];
    final hasReference = reference != null;

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final table = Column(
        key: const ValueKey('options-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            key: hasReference ? const ValueKey('reference-legend') : null,
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const UiKey(color: Ui.you, label: 'You'),
              if (hasReference)
                UiKey(
                    color: Ui.reference,
                    label: match == null
                        ? 'High-level $player'
                        : 'High-level $player (${Ui.times(match.count ?? 0)})'),
              if (match != null && (match.count ?? 0) < 5)
                const UiPill(
                    key: ValueKey('reference-small-sample'),
                    label: 'small sample'),
              const SizedBox(width: 6),
              const UiKey(color: Ui.bad, label: 'got hit'),
              const UiKey(color: Ui.warn, label: 'blocked'),
              const UiKey(color: Ui.idle, label: 'reset'),
              const UiKey(color: Ui.good, label: 'won'),
            ],
          ),
          const SizedBox(height: 12),
          _line(
            wide: wide,
            hasReference: hasReference,
            option: const UiCaps('Option'),
            you: const UiCaps('You picked'),
            outcome: const UiCaps('What happened'),
            reference: UiCaps('High-level',
                key: hasReference ? const ValueKey('spot-reference') : null),
            paper: const UiCaps('On paper'),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          for (final name in shown)
            _row(context, name, own[name], theirs[name], match,
                shownOpponent: shownOpponent,
                wide: wide,
                hasReference: hasReference),
          if (hasReference && match == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('High-level $player was not seen in this spot.',
                  style: Ui.small),
            ),
        ],
      );
      if (wide) return table;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: 760, child: table),
      );
    });
  }

  Widget _line({
    required bool wide,
    required bool hasReference,
    required Widget option,
    required Widget you,
    required Widget outcome,
    required Widget reference,
    required Widget paper,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 196, child: option),
          const SizedBox(width: 12),
          SizedBox(width: 138, child: you),
          const SizedBox(width: 12),
          SizedBox(width: 138, child: outcome),
          if (hasReference) ...[
            const SizedBox(width: 12),
            SizedBox(width: 150, child: reference),
          ],
          const SizedBox(width: 12),
          Expanded(child: paper),
        ],
      );

  Widget _row(
    BuildContext context,
    String name,
    SituationSummaryRow? mine,
    ReferenceRow? theirs,
    ReferenceSpot? match, {
    required List<String> shownOpponent,
    required bool wide,
    required bool hasReference,
  }) {
    final move =
        mine?.moves.map((id) => moves[id]).whereType<MoveCard>().firstOrNull;
    final picked = mine?.seen ?? false;
    final count = picked ? mine!.count : 0;

    // What happened, summed over every opponent option this met.
    var won = 0, lost = 0, pressure = 0, neutral = 0;
    for (final seen in mine?.seenVs.values ?? const <SituationSeen>[]) {
      won += seen.won;
      lost += seen.lost;
      pressure += seen.pressure;
      neutral += seen.neutral;
    }
    if (won + lost + pressure + neutral == 0 && picked) {
      lost = mine!.hit;
      neutral = (count - lost).clamp(0, count);
    }
    final outcomeText = lost > 0
        ? 'hit $lost'
        : won > 0
            ? 'won $won'
            : 'not hit';

    final wins = [
      for (final other in shownOpponent)
        if (mine != null &&
            mine.beats.contains(other) &&
            !mine.disproved.containsKey(other))
          other
    ];
    final losses = [
      for (final other in shownOpponent)
        if (mine != null && mine.losesTo.contains(other)) other
    ];
    final disproved = mine?.disproved.keys.toList() ?? const <String>[];
    final isRecommended = recommended.contains(name);

    final paper = <Widget>[];
    if (mine == null) {
      paper.add(const Text('no rule for it', style: Ui.small));
    } else if (wins.isEmpty && losses.isEmpty && disproved.isEmpty) {
      paper.add(const Text('not settled', style: Ui.small));
    } else {
      if (wins.isNotEmpty) {
        paper.add(_PaperLine(
          icon: Icons.check_rounded,
          color: Ui.good,
          text: shownOpponent.isNotEmpty && wins.length == shownOpponent.length
              ? 'beats all $opponent showed'
              : 'beats ${wins.join(', ')}',
        ));
      }
      if (losses.isNotEmpty) {
        paper.add(_PaperLine(
            icon: Icons.close_rounded,
            color: Ui.bad,
            text: 'loses to ${losses.join(', ')}'));
      }
      if (disproved.isNotEmpty) {
        paper.add(_PaperLine(
            icon: Icons.warning_amber_rounded,
            color: Ui.warn,
            text: 'lost to ${disproved.join(', ')} here'));
      }
    }

    return Container(
      key: ValueKey('option-row-$name'),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1F2827)))),
      child: _line(
        wide: wide,
        hasReference: hasReference,
        option: Row(children: [
          SizedBox(
            width: 36,
            height: 36,
            child: move == null
                ? null
                : FittedBox(child: MoveThumb(move: move, size: 36)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ui.body.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (isRecommended) ...[
                    const SizedBox(width: 6),
                    Icon(
                        recommendedProven
                            ? Icons.star_rounded
                            : Icons.science_outlined,
                        size: 15,
                        color: recommendedProven ? Ui.good : Ui.warn),
                  ],
                ]),
                if ((mine?.how ?? '').isNotEmpty)
                  Tooltip(
                    message: mine!.how,
                    child: Text(mine.how,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ui.small.copyWith(color: Ui.inkLow)),
                  ),
              ],
            ),
          ),
        ]),
        you: picked
            ? _Share(
                color: Ui.you,
                fraction: spot.count > 0 ? count / spot.count : 0,
                text: '$count of ${spot.count}')
            : Text('not tried', style: Ui.small.copyWith(color: Ui.inkLow)),
        outcome: picked
            ? Row(children: [
                UiSplitBar(width: 64, parts: [
                  (lost, Ui.bad),
                  (pressure, Ui.warn),
                  (neutral, Ui.idle),
                  (won, Ui.good),
                ]),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(outcomeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ui.small.copyWith(color: Ui.ink))),
              ])
            : const SizedBox.shrink(),
        reference: KeyedSubtree(
          key: ValueKey('reference-pick-$name'),
          child: match == null
              ? const SizedBox.shrink()
              : _Share(
                  color: Ui.reference,
                  fraction: (match.count ?? 0) > 0
                      ? (theirs?.count ?? 0) / match.count!
                      : 0,
                  text: '${theirs?.count ?? 0} of ${match.count ?? 0}'
                      '${(theirs?.hit ?? 0) > 0 ? ' · hit ${theirs!.hit}' : ''}'),
        ),
        paper: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: paper,
        ),
      ),
    );
  }
}

class _Share extends StatelessWidget {
  const _Share(
      {required this.color, required this.fraction, required this.text});
  final Color color;
  final double fraction;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        UiMeter(fraction: fraction, color: color, width: 56),
        const SizedBox(width: 8),
        Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ui.small.copyWith(
                    color: Ui.ink,
                    fontFeatures: const [FontFeature.tabularFigures()]))),
      ]);
}

class _PaperLine extends StatelessWidget {
  const _PaperLine(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: text,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ui.small.copyWith(color: Ui.ink))),
        ]),
      );
}
