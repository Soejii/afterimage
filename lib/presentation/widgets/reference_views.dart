import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/notes_models.dart';

double _share(int count, int total) => total > 0 ? count / total : 0;
String _percent(double value) => '${(value * 100).round()}%';
Color _referenceColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: .6);

class SpotReferenceView extends StatelessWidget {
  const SpotReferenceView(
      {super.key,
      required this.player,
      required this.spot,
      required this.reference});
  final String player;
  final SituationSpot spot;
  final CardReference reference;

  @override
  Widget build(BuildContext context) {
    final match =
        reference.spots.where((item) => item.kind == spot.kind).firstOrNull;
    final theme = Theme.of(context);
    final own = {
      for (final row in spot.playerRows.where((row) => row.seen)) row.name: row
    };
    final other = {
      if (match != null)
        for (final row in match.playerRows)
          if (row.name != null) row.name!: row
    };
    final names = {...own.keys, ...other.keys}.toList()
      ..sort((a, b) => math
          .max(_share(own[b]?.count ?? 0, spot.count),
              _share(other[b]?.count ?? 0, match?.count ?? 0))
          .compareTo(math.max(_share(own[a]?.count ?? 0, spot.count),
              _share(other[a]?.count ?? 0, match?.count ?? 0))));
    return Padding(
      key: const ValueKey('spot-reference'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('What high-level $player picked here',
                  style: theme.textTheme.titleSmall),
              if (match != null && (match.count ?? 0) < 5)
                Text('small sample',
                    key: const ValueKey('reference-small-sample'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
        if (match == null)
          Text('High-level $player was not seen in this spot.')
        else ...[
          _ReferenceLegend(player: player, count: match.count),
          for (final name in names.take(7))
            _ComparisonRow(
              key: ValueKey('reference-pick-$name'),
              label: name,
              player: player,
              ownValue: _share(own[name]?.count ?? 0, spot.count),
              referenceValue: _share(other[name]?.count ?? 0, match.count ?? 0),
              ownText:
                  '${own[name]?.count ?? 0} of ${spot.count}${(own[name]?.hit ?? 0) > 0 ? ' · hit ${own[name]!.hit}' : ''}',
              referenceText:
                  '${other[name]?.count ?? 0} of ${match.count ?? 0}${(other[name]?.hit ?? 0) > 0 ? ' · hit ${other[name]!.hit}' : ''}',
            ),
        ],
      ]),
    );
  }
}

class _ReferenceLegend extends StatelessWidget {
  const _ReferenceLegend({required this.player, this.count});
  final String player;
  final int? count;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        Widget item(String label, Color color) =>
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 5, color: color),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(label,
                      style: Theme.of(context).textTheme.bodySmall)),
            ]);
        final you = item('You', AfterimageTheme.accent);
        final high = item(
            'High-level $player${count == null ? '' : ' ($count times)'}',
            _referenceColor(context));
        return Padding(
            key: const ValueKey('reference-legend'),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: constraints.maxWidth >= 760
                ? Row(children: [
                    const SizedBox(width: 200),
                    Expanded(child: you),
                    Expanded(child: high)
                  ])
                : Wrap(spacing: 20, runSpacing: 3, children: [you, high]));
      });
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow(
      {super.key,
      required this.label,
      required this.player,
      required this.ownValue,
      required this.referenceValue,
      required this.ownText,
      required this.referenceText});
  final String label;
  final String player;
  final double ownValue;
  final double referenceValue;
  final String ownText;
  final String referenceText;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        Widget cell(double value, String text, Color color, String side) =>
            Row(children: [
              if (!wide)
                SizedBox(
                    width: 135,
                    child: Text(side,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall)),
              Flexible(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: LinearProgressIndicator(
                          value: value.clamp(0, 1),
                          minHeight: 4,
                          color: color))),
              const SizedBox(width: 8),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ]);
        final own = cell(ownValue, ownText, AfterimageTheme.accent, 'You');
        final ref = cell(referenceValue, referenceText,
            _referenceColor(context), 'High-level $player');
        if (!wide) {
          return Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label),
                    own,
                    const SizedBox(height: 3),
                    ref
                  ]));
        }
        return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 26),
            child: Row(children: [
              SizedBox(
                  width: 200,
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(child: own),
              const SizedBox(width: 12),
              Expanded(child: ref),
            ]));
      });
}

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
    final theme = Theme.of(context);
    final refLedger = reference.ledger;
    final own = {
      if (ledger != null)
        for (final category in ledger!.categories) category.key: category
    };
    final other = {
      if (refLedger != null)
        for (final category in refLedger.categories) category.key: category
    };
    final categories = {...own.keys, ...other.keys};
    final after = reference.afterBlock;
    return Card(
        key: const ValueKey('reference-panel'),
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                'Against high-level $player (${reference.replays ?? 0} replays)',
                style: theme.textTheme.titleSmall),
            _ReferenceLegend(player: player),
            if (ledger != null && refLedger != null)
              for (final key in categories)
                if (((own[key]?.share ?? 0) * 100).round() != 0 ||
                    ((other[key]?.share ?? 0) * 100).round() != 0)
                  _ComparisonRow(
                      key: ValueKey('reference-category-$key'),
                      label: own[key]?.label ?? other[key]!.label,
                      player: player,
                      ownValue: own[key]?.share ?? 0,
                      referenceValue: other[key]?.share ?? 0,
                      ownText: _percent(own[key]?.share ?? 0),
                      referenceText: _percent(other[key]?.share ?? 0)),
            if (after?.own != null && after?.reference != null)
              _AfterBlock(
                  player: player,
                  own: after!.own!,
                  reference: after.reference!),
          ]),
        ));
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
    String headline(String label, ReferenceAnswers value) =>
        '$label: ${value.count ?? 0} spots, hit ${value.hits ?? 0} (${_percent(_share(value.hits ?? 0, value.count ?? 0))})';
    String hitRate(SequenceAnswer? answer) =>
        answer == null || answer.count == 0
            ? 'n/a'
            : _percent(_share(answer.gotHit, answer.count));
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

    Widget cell(String text,
            {bool heading = false, bool gap = false, Key? key}) =>
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Text(text,
                key: key,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: gap ? AfterimageTheme.failed : null,
                    fontWeight: heading ? FontWeight.bold : null)));
    return Column(
        key: const ValueKey('reference-after-block'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text('After blocking: what was picked and how often it got hit',
              style: Theme.of(context).textTheme.titleSmall),
          Text(headline('You', own)),
          Text(headline('High-level $player', reference)),
          LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                        width: math.max(650, constraints.maxWidth),
                        child: Column(children: [
                          Row(children: [
                            const Expanded(
                                flex: 3,
                                child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 4),
                                    child: Text('Answer'))),
                            Expanded(
                                flex: 2,
                                child: cell('You picked', heading: true)),
                            Expanded(
                                flex: 2,
                                child: cell('You got hit', heading: true)),
                            Expanded(
                                flex: 2,
                                child: cell('High-level $player picked',
                                    heading: true)),
                            Expanded(
                                flex: 2,
                                child: cell('High-level $player got hit',
                                    heading: true)),
                          ]),
                          for (final name in names.take(7))
                            Row(
                                key: ValueKey('reference-answer-$name'),
                                children: [
                                  Expanded(
                                      flex: 3,
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 4),
                                          child: Text(name))),
                                  Expanded(
                                      flex: 2,
                                      child: cell(_percent(_share(
                                          a[name]?.count ?? 0, totalA)))),
                                  Expanded(
                                      flex: 2,
                                      child: cell(hitRate(a[name]),
                                          gap: hasGap(name),
                                          key: hasGap(name)
                                              ? ValueKey('reference-gap-$name')
                                              : null)),
                                  Expanded(
                                      flex: 2,
                                      child: cell(_percent(_share(
                                          b[name]?.count ?? 0, totalB)))),
                                  Expanded(
                                      flex: 2, child: cell(hitRate(b[name]))),
                                ]),
                        ])),
                  )),
        ]);
  }
}
