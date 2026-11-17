import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/notes_models.dart';
import '../ui/ui.dart';
import 'move_card_views.dart';

// The landing of one matchup: the numbers that sum it up, the situations to
// work on, and a table of the rest. Each row opens the situation.

/// "Ky blocked" becomes "blocked", so a line can start with "You".
String stripPlayer(String text, String? player) {
  if (player != null && player.isNotEmpty && text.startsWith('$player ')) {
    return text.substring(player.length + 1);
  }
  return text;
}

/// When the batch was recorded, read from its `batch_YYYYMMDD_HHMMSS` label.
DateTime? batchPlayedAt(String label) {
  final match = RegExp(r'^batch_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})')
      .firstMatch(label);
  if (match == null) return null;
  int part(int index) => int.parse(match[index]!);
  return DateTime(part(1), part(2), part(3), part(4), part(5), part(6));
}

String formatPlayedDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String games(int count) => count == 1 ? '1 game' : '$count games';

/// True when the user is hit clearly more often than the reference, with
/// enough of both to mean something.
bool hitGap(int ownHits, int ownCount, int? refHits, int? refCount) {
  if (refHits == null || refCount == null) return false;
  if (ownCount < 5 || refCount < 5) return false;
  return 5 * (ownHits * refCount - refHits * ownCount) >= ownCount * refCount;
}

/// The two or three numbers that sum up a matchup.
class MatchupStats extends StatelessWidget {
  const MatchupStats({super.key, required this.document});
  final SequenceDocument document;

  @override
  Widget build(BuildContext context) {
    final ledger = document.ledger;
    final reference = document.isReference ? null : document.reference;
    final player = document.player ?? 'player';
    final tiles = <Widget>[];

    // The reference value, and how far above it the user is when that matters.
    Widget versus(String text, {String? above}) => Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              UiKey(color: Ui.reference, label: 'High-level $player $text'),
              if (above != null)
                Tooltip(
                  message: 'You are $above above high-level $player',
                  child: UiPill(
                      label: above,
                      color: Ui.bad,
                      icon: Icons.arrow_upward_rounded),
                ),
            ]);

    if (ledger != null && ledger.totalDamage > 0) {
      final own = ledger.damagePerReplay ??
          (ledger.replays > 0 ? ledger.totalDamage / ledger.replays : null);
      final other = reference?.ledger?.damagePerReplay;
      if (own != null) {
        tiles.add(UiStat(
          key: const ValueKey('stat-damage'),
          label: 'Health lost per game',
          value: Ui.thousands(own),
          detail: other == null
              ? null
              : versus(Ui.thousands(other),
                  above: own - other > 50
                      ? '+${Ui.thousands(own - other)}'
                      : null),
        ));
      }
    }

    final block = reference?.afterBlock;
    final ownBlock = block?.own;
    final refBlock = block?.reference;
    if (ownBlock?.count != null && (ownBlock!.count ?? 0) > 0) {
      tiles.add(UiStat(
        key: const ValueKey('stat-after-block'),
        label: 'Hit after blocking',
        value: Ui.percent(ownBlock.hits ?? 0, ownBlock.count!),
        unit: '${ownBlock.hits ?? 0} of ${ownBlock.count}',
        detail: refBlock?.count == null || refBlock!.count == 0
            ? null
            : versus(Ui.percent(refBlock.hits ?? 0, refBlock.count!),
                above: hitGap(ownBlock.hits ?? 0, ownBlock.count!,
                        refBlock.hits, refBlock.count)
                    ? '+${(100 * ((ownBlock.hits ?? 0) / ownBlock.count! - (refBlock.hits ?? 0) / refBlock.count!)).round()} pts'
                    : null),
      ));
    } else {
      final situations =
          document.cards.where((card) => !card.isEventCard).toList();
      tiles.add(UiStat(
        key: const ValueKey('stat-situations'),
        label: 'Situations found',
        value: '${situations.length}',
        unit: '${situations.where((card) => card.flagged).length} flagged',
      ));
    }

    if (ledger != null && ledger.categories.isNotEmpty) {
      final top = [...ledger.categories]
        ..sort((a, b) => b.damage.compareTo(a.damage));
      final category = top.first;
      final other = reference?.ledger?.categories
          .where((item) => item.key == category.key)
          .firstOrNull;
      tiles.add(UiStat(
        key: const ValueKey('stat-top-source'),
        label: 'Biggest source of damage',
        value: '${(category.share * 100).round()}%',
        unit: category.label.toLowerCase(),
        detail: other == null
            ? null
            : versus('${(other.share * 100).round()}%',
                above: category.share - other.share >= 0.1
                    ? '+${((category.share - other.share) * 100).round()} pts'
                    : null),
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();
    return UiPanel(
      key: const ValueKey('matchup-stats'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < tiles.length; index++) ...[
                if (index > 0) const SizedBox(height: 18),
                tiles[index],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < tiles.length; index++) ...[
                if (index > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22),
                    child: VerticalDivider(
                        width: 1, color: AfterimageTheme.hairline),
                  ),
                Expanded(child: tiles[index]),
              ],
            ],
          ),
        );
      }),
    );
  }
}

SequenceAnswer? _topAnswer(List<SequenceAnswer> answers) {
  SequenceAnswer? top;
  for (final answer in answers) {
    if (top == null || answer.count > top.count) top = answer;
  }
  return top;
}

/// One line: whose answer it is, what it was, how often, and what it cost.
class _AnswerLine extends StatelessWidget {
  const _AnswerLine({
    required this.color,
    required this.who,
    required this.answer,
    required this.total,
    required this.player,
  });
  final Color color;
  final String who;
  final SequenceAnswer answer;
  final int total;
  final String? player;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$who mostly  '),
                TextSpan(
                    text: stripPlayer(answer.text, player),
                    style: const TextStyle(
                        color: Ui.ink, fontWeight: FontWeight.w600)),
                TextSpan(
                    text: '   ${answer.count} of $total'
                        '${answer.gotHit > 0 ? ', hit ${answer.gotHit}' : ''}'),
              ]),
              style: Ui.small.copyWith(fontSize: 13.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

/// A rate with its count, stacked, for the right side of a situation row.
class _Rate extends StatelessWidget {
  const _Rate({
    required this.label,
    required this.hits,
    required this.count,
    required this.color,
    this.flag = false,
  });
  final String label;
  final int hits;
  final int count;
  final Color color;
  final bool flag;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          UiCaps(label),
          const SizedBox(height: 5),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(Ui.percent(hits, count),
                style: Ui.display.copyWith(fontSize: 24)),
            if (flag) ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_upward_rounded, size: 16, color: Ui.bad),
            ],
          ]),
          const SizedBox(height: 5),
          UiMeter(
              fraction: count > 0 ? hits / count : 0, color: color, width: 92),
          const SizedBox(height: 4),
          Text('$hits of $count', style: Ui.small),
        ],
      );
}

/// A situation to work on: what it is, what each side usually does, and how
/// often it costs health.
class LeakRow extends StatelessWidget {
  const LeakRow({
    super.key,
    required this.card,
    required this.document,
    required this.onOpen,
    this.number,
  });
  final SequenceCard card;
  final SequenceDocument document;
  final VoidCallback onOpen;
  final int? number;

  @override
  Widget build(BuildContext context) {
    final player = document.player;
    final move = document.moves[card.moveId];
    final reference = document.isReference ? null : card.reference;
    final own = _topAnswer(card.answers);
    final other = reference == null ? null : _topAnswer(reference.answers);
    final ownTotal = card.answers.fold<int>(0, (sum, a) => sum + a.count);
    final otherTotal =
        reference?.answers.fold<int>(0, (sum, a) => sum + a.count) ?? 0;
    final gap =
        hitGap(card.hits, card.count, reference?.hits, reference?.count);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: UiPanel(
        onTap: onOpen,
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 72,
              child: move != null
                  ? IgnorePointer(
                      child: FittedBox(child: MoveThumb(move: move, size: 72)))
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                          color: AfterimageTheme.panelRaised,
                          borderRadius: BorderRadius.all(Radius.circular(8))),
                      child: Icon(Icons.shield_outlined,
                          color: Ui.inkLow, size: 26)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(card.title,
                      style: Ui.h2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                      '${Ui.times(card.count)}'
                      '${card.damage > 0 ? '  ·  ${Ui.thousands(card.damage)} damage' : ''}',
                      style: Ui.small),
                  if (own != null) ...[
                    const SizedBox(height: 9),
                    _AnswerLine(
                        color: Ui.you,
                        who: 'You',
                        answer: own,
                        total: ownTotal,
                        player: player),
                  ],
                  if (other != null) ...[
                    const SizedBox(height: 4),
                    _AnswerLine(
                        color: Ui.reference,
                        who: 'High-level ${player ?? 'player'}',
                        answer: other,
                        total: otherTotal,
                        player: player),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 104,
              child: _Rate(
                  label: 'You got hit',
                  hits: card.hits,
                  count: card.count,
                  color: Ui.bad,
                  flag: gap),
            ),
            if (reference != null &&
                reference.hits != null &&
                (reference.count ?? 0) > 0) ...[
              const SizedBox(width: 14),
              SizedBox(
                width: 104,
                child: _Rate(
                    label: 'High-level',
                    hits: reference.hits!,
                    count: reference.count!,
                    color: Ui.reference),
              ),
            ],
            const SizedBox(width: 6),
            const UiChevron(),
          ],
        ),
      ),
    );
  }
}

/// A table that keeps its columns and scrolls sideways in a narrow window.
Widget _minWidth(double width, Widget child) => LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= width
          ? child
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: width, child: child)),
    );

enum _Sort { order, times, hit, damage }

/// Every situation of the matchup in one scannable table.
class SituationsTable extends StatefulWidget {
  const SituationsTable({
    super.key,
    required this.cards,
    required this.document,
    required this.onOpen,
  });
  final List<SequenceCard> cards;
  final SequenceDocument document;
  final ValueChanged<SequenceCard> onOpen;

  @override
  State<SituationsTable> createState() => _SituationsTableState();
}

class _SituationsTableState extends State<SituationsTable> {
  _Sort _sort = _Sort.order;

  double _hitRate(SequenceCard card) =>
      card.count > 0 ? card.hits / card.count : 0;

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final showReference = !document.isReference &&
        widget.cards.any((card) => (card.reference?.count ?? 0) > 0);
    final cards = [...widget.cards];
    switch (_sort) {
      case _Sort.order:
        break;
      case _Sort.times:
        cards.sort((a, b) => b.count.compareTo(a.count));
      case _Sort.hit:
        cards.sort((a, b) => _hitRate(b).compareTo(_hitRate(a)));
      case _Sort.damage:
        cards.sort((a, b) => b.damage.compareTo(a.damage));
    }

    Widget head(String text, _Sort sort, double width, {bool end = false}) {
      final active = _sort == sort;
      return SizedBox(
        width: width,
        child: InkWell(
          key: ValueKey('sort-${sort.name}'),
          onTap: () => setState(() => _sort = active ? _Sort.order : sort),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment:
                  end ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Flexible(
                    child: UiCaps(text, color: active ? Ui.ink : Ui.inkLow)),
                if (active)
                  const Icon(Icons.arrow_drop_down_rounded,
                      size: 16, color: Ui.ink),
              ],
            ),
          ),
        ),
      );
    }

    return UiPanel(
      key: const ValueKey('situations-table'),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: _minWidth(
          showReference ? 760 : 600,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Row(children: [
                  const Expanded(child: UiCaps('Situation')),
                  head('Times', _Sort.times, 56, end: true),
                  const SizedBox(width: 20),
                  head('You got hit', _Sort.hit, 132),
                  if (showReference) ...[
                    const SizedBox(width: 12),
                    const SizedBox(width: 150, child: UiCaps('High-level')),
                  ],
                  const SizedBox(width: 8),
                  head('Damage', _Sort.damage, 64, end: true),
                  const SizedBox(width: 26),
                ]),
              ),
              const Divider(height: 1),
              for (final card in cards)
                _SituationRow(
                  card: card,
                  document: document,
                  showReference: showReference,
                  onOpen: () => widget.onOpen(card),
                ),
            ],
          )),
    );
  }
}

class _SituationRow extends StatelessWidget {
  const _SituationRow({
    required this.card,
    required this.document,
    required this.showReference,
    required this.onOpen,
  });
  final SequenceCard card;
  final SequenceDocument document;
  final bool showReference;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final move = document.moves[card.moveId];
    final reference = card.reference;
    final gap =
        hitGap(card.hits, card.count, reference?.hits, reference?.count);
    return UiHoverRow(
      key: ValueKey('situation-row-${card.id}'),
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(children: [
        SizedBox(
          width: 40,
          height: 40,
          child: move == null
              ? const Icon(Icons.shield_outlined, size: 18, color: Ui.inkLow)
              : IgnorePointer(
                  child: FittedBox(child: MoveThumb(move: move, size: 40))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Ui.body.copyWith(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        SizedBox(
            width: 56,
            child: Text('${card.count}',
                textAlign: TextAlign.right, style: Ui.figure)),
        const SizedBox(width: 20),
        SizedBox(
          width: 132,
          child: Row(children: [
            UiMeter(
                fraction: card.count > 0 ? card.hits / card.count : 0,
                color: Ui.bad,
                width: 64),
            const SizedBox(width: 8),
            Text(Ui.percent(card.hits, card.count), style: Ui.figure),
            if (gap)
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child:
                    Icon(Icons.arrow_upward_rounded, size: 14, color: Ui.bad),
              ),
          ]),
        ),
        if (showReference) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: reference == null ||
                    reference.hits == null ||
                    (reference.count ?? 0) == 0
                ? Text('not seen', style: Ui.small.copyWith(color: Ui.inkLow))
                : Row(children: [
                    UiMeter(
                        fraction: reference.hits! / reference.count!,
                        color: Ui.reference,
                        width: 56),
                    const SizedBox(width: 8),
                    Text(Ui.percent(reference.hits!, reference.count!),
                        style: Ui.figure),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text('of ${reference.count}',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: Ui.small.copyWith(color: Ui.inkLow)),
                    ),
                  ]),
          ),
        ],
        const SizedBox(width: 8),
        SizedBox(
            width: 64,
            child: Text(card.damage > 0 ? Ui.thousands(card.damage) : '',
                textAlign: TextAlign.right, style: Ui.figure)),
        const SizedBox(width: 4),
        const UiChevron(),
      ]),
    );
  }
}

/// The other ways the player got hit, one row each.
class EventsTable extends StatelessWidget {
  const EventsTable({
    super.key,
    required this.cards,
    required this.document,
    required this.onOpen,
  });
  final List<SequenceCard> cards;
  final SequenceDocument document;
  final ValueChanged<SequenceCard> onOpen;

  @override
  Widget build(BuildContext context) {
    final most = cards.fold<int>(1, (m, c) => c.damage > m ? c.damage : m);
    return UiPanel(
      key: const ValueKey('events-table'),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: _minWidth(
          560,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(children: [
                  Expanded(child: UiCaps('How the hit happened')),
                  SizedBox(
                      width: 56,
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: UiCaps('Times'))),
                  SizedBox(width: 20),
                  SizedBox(width: 190, child: UiCaps('Damage')),
                  SizedBox(width: 26),
                ]),
              ),
              const Divider(height: 1),
              for (final card in cards)
                UiHoverRow(
                  key: ValueKey('situation-row-${card.id}'),
                  onTap: () => onOpen(card),
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: switch (card.moveIds
                          .map((id) => document.moves[id])
                          .whereType<MoveCard>()
                          .firstOrNull) {
                        final move? => IgnorePointer(
                            child: FittedBox(
                                child: MoveThumb(move: move, size: 40))),
                        null => const Icon(Icons.flash_on_rounded,
                            size: 18, color: Ui.inkLow),
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(card.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Ui.body.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                        width: 56,
                        child: Text('${card.count}',
                            textAlign: TextAlign.right, style: Ui.figure)),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 190,
                      child: Row(children: [
                        UiMeter(
                            fraction: card.damage / most,
                            color: Ui.bad,
                            width: 120),
                        const SizedBox(width: 8),
                        Text(Ui.thousands(card.damage), style: Ui.figure),
                      ]),
                    ),
                    const SizedBox(width: 4),
                    const UiChevron(),
                  ]),
                ),
            ],
          )),
    );
  }
}
