import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/theme.dart';
import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/presentation/notes_pages.dart';
import 'package:afterimage/presentation/ui/ui.dart';
import 'package:afterimage/presentation/widgets/move_card_views.dart';
import 'package:afterimage/presentation/widgets/notes_clip_player.dart';
import 'package:afterimage/services/notes_repository.dart';

import 'support/ledger_test_data.dart';

Future<void> _pumpLedger(WidgetTester tester, Map<String, Object?> json,
    {double width = 1280, double height = 900, String? tab}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final preview = _preview(directory: '/out/batch-a/I-No');
  await tester.pumpWidget(_app(NotesPage(
    key: UniqueKey(),
    repository: _FakeNotesRepository(
        preview,
        NoteSequenceData(
            preview: preview, document: SequenceDocument.fromJson(json))),
    preview: preview,
    onBack: () {},
    playerFactory: (_) => _FakeClipSession(),
  )));
  await _pumpUntilFound(tester, find.byKey(const ValueKey('notes-page')));
  await tester.pumpAndSettle();
  if (tab != null) await _openTab(tester, tab);
}

/// Opens a page tab (`spots`, `hits`, `damage`) when the page shows it.
Future<void> _openTab(WidgetTester tester, String tab) async {
  final finder = find.byKey(ValueKey('tab-$tab'));
  if (finder.evaluate().isEmpty) return;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  final tile = find.descendant(of: finder, matching: find.byType(ListTile));
  final target = tile.evaluate().isEmpty ? finder : tile.first;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openSituation(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey('situation-row-$id'));
  await _pumpUntilFound(tester, row);
  await tester.ensureVisible(row);
  final rect = tester.getRect(row);
  await tester.tapAt(Offset(rect.left + 24, rect.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  Map<String, Object?> step13() => decodeObject(
      File('test/support/step13/elphelt_2h.json').readAsStringSync());
  Map<String, Object?> step14() => decodeObject(
      File('test/support/step14/elphelt_2h_reference.json').readAsStringSync());

  testWidgets('landing shows matchup numbers without rendering cards',
      (tester) async {
    await _pumpLedger(tester, step14(), width: 936, height: 1006);
    expect(find.byKey(const ValueKey('matchup-stats')), findsOneWidget);
    expect(_textWithin(tester, find.byKey(const ValueKey('stat-after-block'))),
        contains('26%'));
    expect(_textWithin(tester, find.byKey(const ValueKey('stat-after-block'))),
        contains('57 of 220'));
    expect(find.byKey(const ValueKey('sequence-card-c14')), findsNothing);
  });

  testWidgets('landing stat tiles show damage, hit rate and biggest source',
      (tester) async {
    final json = step14();
    json['ledger'] = {
      'total_damage': 1200,
      'replays': 12,
      'categories': [
        {'key': 'pressing', 'label': 'Pressing', 'damage': 900, 'share': .75},
      ],
    };
    await _pumpLedger(tester, json, width: 1400, height: 1000);
    expect(_textWithin(tester, find.byKey(const ValueKey('stat-damage'))),
        contains('100'));
    expect(_textWithin(tester, find.byKey(const ValueKey('stat-after-block'))),
        contains('26%'));
    expect(_textWithin(tester, find.byKey(const ValueKey('stat-top-source'))),
        contains('75%'));
  });

  testWidgets('far more often pill requires a twenty point hit gap',
      (tester) async {
    for (final hits in [7, 6]) {
      final json = step14();
      final card = (json['cards'] as List).single as Map;
      card['count'] = 10;
      card['hits'] = hits;
      card['reference'] = {'count': 10, 'hits': 5};
      await _pumpLedger(tester, json, width: 1400, height: 1000);
      await _tapKey(tester, 'focus-row-c14');
      expect(find.text('far more often than high-level'),
          hits == 7 ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('set list groups own and reference sets newest first',
      (tester) async {
    NotePreview preview(String name, String date, bool reference) =>
        NotePreview(
          batchLabel: 'batch_${date}_120000',
          opponent: name,
          directoryPath: '/$name',
          documentPath: '/$name/sequences.json',
          cardCount: 2,
          flaggedCount: 0,
          createdAt: DateTime(2027),
          modifiedAt: null,
          isReference: reference,
        );
    final entries = [
      preview('Own old', '20261101', false),
      preview('Ref old', '20261102', true),
      preview('Own new', '20261113', false),
      preview('Ref new', '20261114', true),
    ];
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(NotesListPage(
        repository: _ListNotesRepository(entries),
        onOpen: (_) {},
        onClose: () {})));
    await tester.pumpAndSettle();
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('YOUR SETS'), lessThan(y('vs Own new')));
    expect(y('vs Own new'), lessThan(y('vs Own old')));
    expect(y('vs Own old'), lessThan(y('HIGH-LEVEL REFERENCE SETS')));
    expect(y('HIGH-LEVEL REFERENCE SETS'), lessThan(y('vs Ref new')));
    expect(y('vs Ref new'), lessThan(y('vs Ref old')));
  });

  for (final size in [const Size(936, 1006), const Size(700, 1000)]) {
    testWidgets('focus row opens and returns without overflow at $size',
        (tester) async {
      await _pumpLedger(tester, step14(),
          width: size.width, height: size.height);
      expect(tester.takeException(), isNull);
      await _tapKey(tester, 'focus-row-c14');
      expect(find.byKey(const ValueKey('detail-title-c14')), findsOneWidget);
      expect(find.byKey(const ValueKey('sequence-card-c14')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tapKey(tester, 'back-to-situations');
      expect(find.byKey(const ValueKey('focus-row-c14')), findsOneWidget);
      expect(find.byKey(const ValueKey('sequence-card-c14')), findsNothing);
    });
  }

  testWidgets('situation navigation stays within kind and stops at ends',
      (tester) async {
    await _pumpLedger(tester, eventDocument(), width: 1400, height: 1000);
    await _tapKey(tester, 'situation-row-c1');
    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('previous-situation').onPressed, isNull);
    for (var i = 2; i <= 6; i++) {
      await _tapKey(tester, 'next-situation');
      expect(find.byKey(ValueKey('detail-title-c$i')), findsOneWidget);
    }
    expect(button('next-situation').onPressed, isNull);
    await _tapKey(tester, 'previous-situation');
    expect(find.byKey(const ValueKey('detail-title-c5')), findsOneWidget);
  });

  testWidgets('sorting situations toggles back to original order',
      (tester) async {
    final json = ledgerDocument();
    final cards = json['cards'] as List;
    for (var i = 0; i < cards.length; i++) {
      (cards[i] as Map)['count'] = i + 1;
    }
    await _pumpLedger(tester, json, width: 1400, height: 1000);
    double y(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('situation-row-$id'))).dy;
    expect(y('c1'), lessThan(y('c6')));
    await _tapKey(tester, 'sort-times');
    expect(y('c6'), lessThan(y('c1')));
    await _tapKey(tester, 'sort-times');
    expect(y('c1'), lessThan(y('c6')));
  });

  testWidgets('card header shows reference hit count and rate', (tester) async {
    await _pumpLedger(tester, step14(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    final reference = find.byKey(const ValueKey('card-reference-c14'));
    expect(reference, findsOneWidget);
    expect(_textWithin(tester, reference), contains('22%'));
    expect(_textWithin(tester, reference), contains('2 of 9'));
  });

  testWidgets('spot comparison shows shares and small sample', (tester) async {
    await _pumpLedger(tester, step14(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    expect(find.byKey(const ValueKey('spot-reference')), findsOneWidget);
    final walk = find.byKey(const ValueKey('reference-pick-walk forward'));
    expect(
        _textWithin(
            tester, find.byKey(const ValueKey('option-row-walk forward'))),
        contains('5 of 14'));
    expect(_textWithin(tester, walk), contains('1 of 4'));
    expect(
        find.byKey(const ValueKey('reference-small-sample')), findsOneWidget);
  });

  testWidgets('spot comparison is compact at desktop width', (tester) async {
    await _pumpLedger(tester, step14(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    final spot = find.byKey(const ValueKey('options-table'));
    expect(
        find.descendant(
            of: spot, matching: find.byKey(const ValueKey('reference-legend'))),
        findsOneWidget);
    final row = find.byKey(const ValueKey('option-row-walk forward'));
    final you =
        find.descendant(of: row, matching: find.textContaining('5 of 14'));
    final other = find.descendant(of: row, matching: find.text('1 of 4'));
    expect(tester.getTopLeft(you).dy, tester.getTopLeft(other).dy);
    final bars = tester
        .widgetList<UiMeter>(
            find.descendant(of: row, matching: find.byType(UiMeter)))
        .toList();
    expect(bars, hasLength(2));
    expect(bars[0].color, Ui.you);
    expect(bars[1].color, Ui.reference);
  });

  testWidgets('spot comparison scrolls without overflow at 700px',
      (tester) async {
    await _pumpLedger(tester, step14(), width: 700, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    final row = find.byKey(const ValueKey('option-row-walk forward'));
    final you =
        find.descendant(of: row, matching: find.textContaining('5 of 14'));
    final other = find.descendant(of: row, matching: find.text('1 of 4'));
    expect(tester.getTopLeft(you).dy, tester.getTopLeft(other).dy);
    expect(
        find.ancestor(
            of: row,
            matching: find.byWidgetPredicate((w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference-only pick shows zero for the user', (tester) async {
    await _pumpLedger(tester, step14(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    expect(_textWithin(tester, find.byKey(const ValueKey('option-row-f.S'))),
        contains('not tried'));
  });

  testWidgets('switching spots changes the reference picks', (tester) async {
    await _pumpLedger(tester, step14(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    await _tapKey(tester, 'spot-chip-1');
    expect(find.byKey(const ValueKey('reference-pick-stand block')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reference-pick-c.S')), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-pick-f.S')), findsNothing);
  });

  for (final width in [1400.0, 700.0]) {
    testWidgets('damage reference panel and answers fit at $width',
        (tester) async {
      await _pumpLedger(tester, step14(),
          width: width, height: 1000, tab: 'damage');
      expect(find.byKey(const ValueKey('reference-panel')), findsOneWidget);
      expect(find.text('You: 26% hit  ·  57 of 220'), findsOneWidget);
      expect(find.text('High-level Ky: 24% hit  ·  40 of 169'), findsOneWidget);
      for (final text in ['block', 'walk forward', '2P']) {
        expect(find.byKey(ValueKey('reference-answer-$text')), findsOneWidget);
      }
      expect(
          find.byKey(const ValueKey('reference-after-block')), findsOneWidget);
      expect(find.byKey(const ValueKey('reference-gap-block')), findsOneWidget);
      expect(find.byKey(const ValueKey('reference-gap-2P')), findsNothing);
      final gap = tester
          .widget<Text>(find.byKey(const ValueKey('reference-gap-block')));
      expect(gap.style?.color, Ui.ink);
      expect(gap.data, '40%');
      final arrow = find.descendant(
          of: find.byKey(const ValueKey('reference-answer-block')),
          matching: find.byIcon(Icons.arrow_upward_rounded));
      expect(tester.widget<Icon>(arrow).color, Ui.bad);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'reference ledger follows own category order and appends new categories',
      (tester) async {
    final json = step14();
    json['ledger'] = {
      'total_damage': 1000,
      'replays': 15,
      'categories': [
        {'key': 'own', 'label': 'Own only', 'damage': 300, 'share': .3},
        {'key': 'pressing', 'label': 'Pressing', 'damage': 700, 'share': .7},
        {'key': 'tiny', 'label': 'Tiny', 'damage': 1, 'share': .004},
      ],
    };
    await _pumpLedger(tester, json, width: 1400, height: 1000, tab: 'damage');
    final own = find.byKey(const ValueKey('reference-category-own'));
    final pressing = find.byKey(const ValueKey('reference-category-pressing'));
    final referenceOnly =
        find.byKey(const ValueKey('reference-category-throw'));
    expect(tester.getTopLeft(own).dy, lessThan(tester.getTopLeft(pressing).dy));
    expect(referenceOnly, findsOneWidget);
    expect(tester.getTopLeft(pressing).dy,
        lessThan(tester.getTopLeft(referenceOnly).dy));
    final pressingRow = find.byKey(const ValueKey('ledger-category-pressing'));
    expect(_textWithin(tester, pressingRow), contains('70%'));
    expect(_textWithin(tester, pressingRow), contains('60%'));
  });

  testWidgets('old step13 list shows no reference UI', (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    for (final key in [
      'reference-notice',
      'card-reference-c14',
      'spot-reference',
      'reference-small-sample',
      'reference-panel',
      'reference-after-block'
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
  });

  testWidgets('reference list shows notice and badge from repository',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('reference-list-');
    addTearDown(() => root.deleteSync(recursive: true));
    final json = step14()..['is_reference'] = true;
    final file =
        File('${root.path}/out/batch-reference/Elphelt/sequences.json');
    file.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(json));
    final repository = NotesRepository(finderDirectory: root.path);
    final previews = await tester.runAsync(repository.list);
    final preview = previews!.single;
    final data = await tester.runAsync(() => repository.read(preview));
    final fake = _FakeNotesRepository(preview, data!);
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        _app(NotesListPage(repository: fake, onOpen: (_) {}, onClose: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reference-badge-batch-reference')),
        findsOneWidget);
    expect(find.text('vs Elphelt Valentine'), findsOneWidget);
    await tester.pumpWidget(_app(NotesPage(
        repository: fake,
        preview: preview,
        onBack: () {},
        playerFactory: (_) => _FakeClipSession())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reference-notice')), findsOneWidget);
    expect(
        find.text(
            'High-level Ky reference set. Not counted in your own history.'),
        findsOneWidget);
  });

  testWidgets('grid stays within its card and scrolls only on narrow screens',
      (tester) async {
    for (final width in [1400.0, 700.0]) {
      await _pumpLedger(tester, step13(), width: width, height: 1000);
      await _tapKey(tester, 'focus-row-c14');
      await _tapKey(tester, 'toggle-unseen');
      final table = find.byKey(const ValueKey('rps-table'));
      final card = find.byKey(const ValueKey('sequence-card-c14'));
      final scroll = find.ancestor(
          of: table,
          matching: find.byWidgetPredicate((w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal));
      if (width == 1400) {
        expect(tester.getSize(table).width,
            lessThanOrEqualTo(tester.getSize(card).width),
            reason: 'grid must not be wider than its card');
        expect(scroll, findsNothing, reason: 'wide grid must not scroll');
      } else {
        expect(scroll, findsOneWidget, reason: 'narrow grid must scroll');
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('headline answer remains visible before showing unseen options',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    expect(find.byKey(const ValueKey('row-label-5P')), findsOneWidget);
  });

  testWidgets('all player row labels have equal height', (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    await _tapKey(tester, 'toggle-unseen');
    final labels = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('row-label-'));
    final heights = labels
        .evaluate()
        .map((e) => tester.getSize(find.byWidget(e.widget)).height)
        .toSet();
    expect(heights, hasLength(1));
  });

  testWidgets('paper wins and rule wins have distinct icons and legend entries',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    await _tapKey(tester, 'toggle-unseen');
    final paper = tester
        .widget<Icon>(find.byKey(const ValueKey('cell-proof-5P|f.S-paper')));
    final rule = tester.widget<Icon>(
        find.byKey(const ValueKey('cell-proof-block|Juganto Da Parfeo-rule')));
    expect(paper.icon, Icons.check_circle_outline_rounded);
    expect(rule.icon, Icons.check_circle_rounded);
    expect(find.text('on paper win'), findsOneWidget);
    expect(find.text('proven win'), findsOneWidget);
  });

  testWidgets('unsettled walk forward versus f.S displays hit 3',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    expect(
        _textWithin(
            tester, find.byKey(const ValueKey('cell-walk forward|f.S-open'))),
        contains('hit 3'));
  });

  testWidgets('Watch lists exactly c14-s19 and Show all restores 33 clips',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    final disproved = find.byKey(const ValueKey('disproved-2P|f.S'));
    final watch = find.descendant(of: disproved, matching: find.text('Watch'));
    await tester.ensureVisible(watch);
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clip-filter-c14')), findsOneWidget);
    expect(_textWithin(tester, find.byKey(const ValueKey('clip-filter-c14'))),
        contains('Showing 1 of 33 clips: 2P vs f.S'));
    expect(find.byKey(const ValueKey('reversal-note-c14')), findsNothing);
    expect(find.byKey(const ValueKey('answers-c14')), findsNothing);
    expect(find.textContaining('What Elphelt did before 2H:'), findsNothing);
    expect(find.byKey(const ValueKey('save-mixup-c14-0')), findsNothing);
    final sequences = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('sequence-c14-s'));
    expect(sequences, findsOneWidget,
        reason: 'Watch must list exactly c14-s19');
    expect(find.byKey(const ValueKey('sequence-c14-s19')), findsOneWidget);
    await _tapKey(tester, 'clip-filter-clear-c14');
    expect(sequences, findsNWidgets(33));
    expect(find.byKey(const ValueKey('answers-c14')), findsOneWidget);
    expect(find.textContaining('What Elphelt did before 2H:'), findsOneWidget);
  });

  testWidgets('context uses character names and column bars sort by frequency',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    final text =
        _textWithin(tester, find.byKey(const ValueKey('read-summary')));
    expect(text, contains('Where: far 13 · close 1 · Ky cornered 7'));
    expect(text, isNot(contains('player cornered')));
    expect(find.byKey(const ValueKey('opponent-strip')), findsNothing);
    final first = find.byKey(const ValueKey('opponent-bar-f.S'));
    expect(first, findsOneWidget);
    expect(
        tester.widget<LinearProgressIndicator>(first).value, closeTo(.5, .001));
    final bar = find.byKey(const ValueKey('opponent-bar-5H'));
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(bar).dx));
    final label = find.byKey(const ValueKey('row-label-2P'));
    expect(tester.getSize(label).width, 190);
  });

  testWidgets('spot chips and unread count account for all 33 occurrences',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    expect(_textWithin(tester, find.byKey(const ValueKey('spot-chip-0'))),
        contains('14 times'));
    expect(_textWithin(tester, find.byKey(const ValueKey('spot-chip-1'))),
        contains('12 times'));
    expect(_textWithin(tester, find.byKey(const ValueKey('spot-unread'))),
        contains('7 not read'));
  });

  testWidgets('Clips does not expose raw opponent timing or section center',
      (tester) async {
    await _pumpLedger(tester, step13(), width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    await _tapKey(tester, 'card-tab-clips-c14');
    final text =
        _textWithin(tester, find.byKey(const ValueKey('sequence-card-c14')));
    expect(text, isNot(contains('opponent_timing:')));
    expect(text, isNot(contains('section_center_raw:')));
  });

  testWidgets('old summary without new fields retains lines and solid icons',
      (tester) async {
    final json = step13();
    final card = (json['cards'] as List).single as Map;
    final summary = ((card['read'] as Map)['summary'] as Map);
    for (final spot in summary['spots'] as List) {
      (spot as Map).remove('notes');
      for (final row in spot['player_rows'] as List) {
        (row as Map).remove('proof');
        row.remove('seen_vs');
      }
    }
    await _pumpLedger(tester, json, width: 1400, height: 1000);
    await _tapKey(tester, 'focus-row-c14');
    expect(_textWithin(tester, find.byKey(const ValueKey('spot-verdict'))),
        contains('Habit:'));
    final cell = find.byKey(const ValueKey('cell-5P|f.S-win'));
    await _tapKey(tester, 'toggle-unseen');
    expect(
        find.descendant(
            of: cell, matching: find.byIcon(Icons.check_circle_rounded)),
        findsOneWidget);
  });
  testWidgets(
      'situation reads show compact matchup rows, mistake counts and row reasons at 360 px',
      (tester) async {
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    card['read'] = _step12ReadFixture();
    final sequences = [
      for (final value in card['sequences'] as List)
        Map<String, Object?>.from(value as Map),
    ];
    sequences.first['read'] = {
      'sequence_id': 'c1-s1',
      'kind': "player's turn",
      'adv': 2,
      'mistake': 'guess',
      'reason': 'Ky dashed and I-No 2P beat the dash.',
    };
    card['sequences'] = sequences;

    await _pumpLedger(tester, json, width: 360);

    await _openSituation(tester, 'c1');

    expect(find.byKey(const ValueKey('read-headline')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('read-headline'))).data,
        "Ky's turn (+2)");
    final rows = find.byKey(const ValueKey('read-rows'));
    expect(rows, findsOneWidget);
    expect(find.descendant(of: rows, matching: find.byType(Text)), findsWidgets,
        reason: 'the compact seen row and never-works line are visible');
    final rowText = tester
        .widgetList<Text>(
            find.descendant(of: rows, matching: find.byType(Text)))
        .map((widget) => widget.data ?? '')
        .join('\n');
    expect(rowText, contains('Wins vs: active first vs I-No 2P'));
    expect(rowText, contains('Loses to'));
    expect(rowText, contains('Unresolved'));
    expect(rowText, contains('seen 2'));
    expect(find.byKey(const ValueKey('read-metered')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('read-metered'))).data,
      contains('Tension unknown for: Ky Sacred Edge'),
    );
    expect(rowText, contains('Never works here: Ky 2H'));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('read-mistakes'))).data,
      'Mistakes · knowledge 1 · execution 2 · guess 3 · unc check 4 · unclear 5',
    );

    expect(
      find.text('Mistake: guess · Ky dashed and I-No 2P beat the dash.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'H Stroke read stays compact by default and expands to every option',
    (tester) async {
      const sourcePath = 'test/support/step12/ino_h_stroke.json';
      final sourceDocument = _singleCardDocument(
        sourcePath,
        "Ky blocked I-No's H Stroke the Big Tree",
      );
      final card = SequenceDocument.fromJson(sourceDocument).cards.single;
      final matrix = card.read!.matrix!;

      await _pumpLedger(tester, sourceDocument, width: 1280);

      await _openSituation(tester, card.id);

      final panel = find.byKey(const ValueKey('situation-read'));
      final defaultText = _textWithin(tester, panel);
      expect(
        defaultText.length,
        lessThan(1500),
        reason:
            'The default H Stroke read text was ${defaultText.length} characters:\n$defaultText',
      );
      expect(find.byKey(const ValueKey('read-show-all')), findsOneWidget);
      expect(
        find.text(
          'Show every option (${matrix.rows.length} Ky, '
          '${matrix.opponentOptions.length} I-No)',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('read-full-rows')), findsNothing);

      await _tapKey(tester, 'read-show-all');

      final fullRows = find.byKey(const ValueKey('read-full-rows'));
      expect(fullRows, findsOneWidget);
      for (var index = 0; index < matrix.rows.length; index++) {
        expect(
          find.byKey(ValueKey('read-full-row-$index')),
          findsOneWidget,
        );
      }
      final fullText = _textWithin(tester, fullRows);
      for (final option in matrix.opponentOptions) {
        final label = option.label.isEmpty ? option.id : option.label;
        expect(fullText, contains(label), reason: 'Expanded detail: $label');
      }
      final optionGroups = <String, List<SituationOption>>{};
      for (final option in matrix.opponentOptions) {
        final signature = matrix.rows
            .map((row) =>
                '${row.cells[option.id]?.value}\u001f${row.cells[option.id]?.winner}')
            .join('\u001e');
        (optionGroups[signature] ??= []).add(option);
      }
      final mergedGroup = optionGroups.values.firstWhere(
        (options) => options.length > 1,
      );
      final mergedLabel = 'I-No ${mergedGroup.first.label}, '
          '${mergedGroup.skip(1).map((option) => option.label).join(', ')}';
      expect(fullText, contains(mergedLabel));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real Elphelt Bomb-Bomb read shows measured options and fuzzy pairs compactly',
    (tester) async {
      const sourcePath = 'test/support/step12/elphelt_bomb_bomb.json';
      final sourceDocument = _singleCardDocument(
        sourcePath,
        "Ky blocked Elphelt's Bomb-Bomb Chocolat",
      );

      await _pumpLedger(tester, sourceDocument, width: 1280);

      await _openSituation(
          tester, SequenceDocument.fromJson(sourceDocument).cards.single.id);

      final panel = find.byKey(const ValueKey('situation-read'));
      final defaultText = _textWithin(tester, panel);
      expect(
        defaultText,
        contains('Elphelt 2K: low, active at 4 (seen 1)'),
        reason: 'the default read must show observed opponent timing and guard',
      );
      expect(defaultText, contains("Elphelt's turn"));
      expect(defaultText, contains('Even ×'));
      expect(defaultText, contains('Ky cornered'));
      expect(
        defaultText,
        contains('Elphelt Ground Throw: throw, active at 7 (seen 1)'),
      );
      expect(defaultText, isNot(contains('Elphelt Elphelt Air Throw')));
      expect(defaultText, contains('possible fuzzy, check in lab'));
      expect(defaultText, contains('Elphelt 2K (low, active at 4)'));
      expect(defaultText, contains('throw range'));
      expect(defaultText, contains('no corner'));
      expect(
        defaultText,
        isNot(contains('farthest connection')),
        reason: 'raw throw brackets belong behind Show every option',
      );
      final matrix =
          SequenceDocument.fromJson(sourceDocument).cards.single.read!.matrix!;
      int rowText(String optionLabel, String assertion) {
        final option = matrix.playerOptions.singleWhere(
          (candidate) => candidate.label.toLowerCase() == optionLabel,
        );
        final index = matrix.rows.indexWhere(
          (row) => row.options.contains(option.id),
        );
        expect(index, greaterThanOrEqualTo(0));
        final text = _textWithin(
          tester,
          find.byKey(ValueKey('read-default-row-$index')),
        );
        expect(text, contains(assertion));
        return index;
      }

      String rowLine(int index, String prefix) => tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey('read-default-row-$index')),
            matching: find.byType(Text),
          ))
          .singleWhere((line) => (line.data ?? '').startsWith(prefix))
          .data!;

      final standBlockIndex = rowText('stand block', 'Wins vs:');
      final standBlockWins = rowLine(standBlockIndex, 'Wins vs:');
      expect(standBlockWins, contains('block wins vs'));
      expect(standBlockWins, contains('Elphelt j.H (seen 4)'));
      final standBlockLosses = rowLine(standBlockIndex, 'Loses to:');
      expect(standBlockLosses, contains('wrong guard vs Elphelt 2K'));

      final crouchBlockIndex = rowText('crouch block', 'Wins vs:');
      final crouchBlockWins = rowLine(crouchBlockIndex, 'Wins vs:');
      expect(crouchBlockWins, contains('block wins vs Elphelt 2K'));
      expect(defaultText, contains('Throw in range at 3 of 14 spots'));
      expect(defaultText, isNot(contains('Throws:')));
      expect(
        defaultText.length,
        lessThan(1500),
        reason:
            'The default Elphelt Bomb-Bomb read was ${defaultText.length} characters.',
      );

      await _tapKey(tester, 'read-show-all');
      final fullSpots = find.byKey(const ValueKey('read-full-spots'));
      expect(fullSpots, findsOneWidget);
      expect(
        _textWithin(tester, fullSpots),
        contains('farthest connection distance'),
      );
      expect(find.byKey(const ValueKey('read-full-throws')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('read-full-throws')))
            .data,
        contains('Throws:'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'expanded read keeps options apart when their mixed results differ',
      (tester) async {
    // Peer review P2: two "varies" cells with different distributions must not be
    // merged under one label, or the expanded view hides which option beats Ky.
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    final read = _step12ReadFixture();
    final cells = (((read['matrix'] as Map)['rows'] as List).first
        as Map)['cells'] as Map;
    cells['I-No backdash'] = {
      'value': 'varies',
      'winner': null,
      'values': {'block wins': 3},
    };
    cells['I-No Megalo'] = {
      'value': 'varies',
      'winner': null,
      'values': {'wrong guard': 3},
    };
    card['read'] = read;

    await _pumpLedger(tester, json, width: 1280);
    await _openSituation(tester, 'c1');
    await tester.ensureVisible(find.byKey(const ValueKey('read-show-all')));
    await tester.tap(find.byKey(const ValueKey('read-show-all')));
    await tester.pumpAndSettle();

    final text =
        _textWithin(tester, find.byKey(const ValueKey('situation-read')));
    expect(text, contains('I-No backdash (block wins, 3 spots)'));
    expect(text, contains('I-No Megalo (wrong guard, 3 spots)'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read with a summary opens on the RPS, not on the frame grid',
      (tester) async {
    // 2026-11-13: the card showed a grid of "varies" cells and never said who
    // beats who. The summary states it, and the grid moves behind an expander.
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    final read = _step12ReadFixture();
    read['summary'] = {
      'version': 1,
      'note': 'Timing and guard only.',
      'spots': [
        {
          'kind': "player's turn",
          'title': "Ky's turn · I-No is -2",
          'count': 14,
          'context': 'H Stroke leaves I-No at -2.',
          'where': ['far 10', 'close 4'],
          'player': 'Ky',
          'opponent': 'I-No',
          'opponent_rows': [
            {
              'name': 'backdash',
              'count': 7,
              'of': 14,
              'seen': true,
              'how': '',
              'beats': ['2K', '5P'],
              'loses_to': ['dash-up button'],
              'theory': false,
              'hit': 0,
            },
            {
              'name': '2P / 5P',
              'count': 3,
              'of': 14,
              'seen': true,
              'how': 'mid, 5f',
              'beats': <String>[],
              'loses_to': <String>[],
              'theory': false,
              'hit': 0,
            },
            {
              'name': 'Roman Cancel',
              'count': 0,
              'of': 14,
              'seen': false,
              'how': '50 tension',
              'beats': <String>[],
              'loses_to': <String>[],
              'theory': false,
              'hit': 0,
            },
          ],
          'player_rows': [
            {
              'name': '2K',
              'count': 9,
              'of': 14,
              'seen': true,
              'how': '6f',
              'beats': <String>[],
              'loses_to': ['backdash'],
              'theory': false,
              'hit': 2,
              'disproved': {'2P / 5P': 1},
            },
          ],
          'lines': ['Habit: I-No picked backdash 7 of 14.'],
        },
        {
          'kind': 'punish',
          'title': 'Punish · I-No is -7',
          'count': 1,
          'context': 'I-No cannot act for 7 frames.',
          'where': <String>[],
          'player': 'Ky',
          'opponent': 'I-No',
          'opponent_rows': <Object>[],
          'player_rows': <Object>[],
          'lines': ['Fast enough: c.S (7f).'],
        },
      ],
    };
    card['read'] = read;

    for (final width in [1280.0, 700.0]) {
      await _pumpLedger(tester, json, width: width);
      expect(tester.takeException(), isNull);
      final id = card['id'];

      // Cards are opened from their situation row.
      expect(find.byKey(const ValueKey('read-summary')), findsNothing);
      await _openSituation(tester, id as String);

      // Read tab: verdict first, then the who-beats-who table.
      final text =
          _textWithin(tester, find.byKey(const ValueKey('read-summary')));
      expect(text, contains("Ky's turn · I-No is -2 · 14 times"));
      expect(text, contains('Habit: I-No picked backdash 7 of 14.'));
      expect(text, contains('7 of 14'));
      expect(text, contains('9 of 14'));
      expect(text, contains('hit 2'));
      expect(
          find.byKey(const ValueKey('cell-2K|backdash-lose')), findsOneWidget);
      expect(find.byKey(const ValueKey('cell-2K|2P / 5P-disproved')),
          findsOneWidget);
      expect(text, isNot(contains('Roman Cancel')),
          reason: 'options nobody used start hidden');
      await _tapKey(tester, 'toggle-unseen');
      expect(_textWithin(tester, find.byKey(const ValueKey('read-summary'))),
          contains('Roman Cancel'));
      expect(find.byKey(const ValueKey('cell-2K|Roman Cancel-open')),
          findsOneWidget);

      // The second spot is one tap away.
      await _tapKey(tester, 'spot-chip-1');
      expect(_textWithin(tester, find.byKey(const ValueKey('read-summary'))),
          contains('Fast enough: c.S (7f).'));

      // Clips and the old frame grid are tabs of the card.
      expect(find.byKey(const ValueKey('read-headline')), findsNothing);
      await _tapKey(tester, 'card-tab-grid-$id');
      expect(find.byKey(const ValueKey('read-headline')), findsOneWidget);
      expect(find.byKey(const ValueKey('read-summary')), findsNothing);
      await _tapKey(tester, 'card-tab-clips-$id');
      expect(find.byKey(ValueKey('sequence-$id-s1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cards show the vault note behind a move and open it in full',
      (tester) async {
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    card['move_id'] = 'I-No H Stroke';
    json['moves'] = {
      'I-No H Stroke': {
        'id': 'I-No H Stroke',
        'name': 'H Stroke',
        'character': 'I-No',
        'input': '236H',
        'startup': '28',
        'on_block': '-2',
        'guard': 'Low',
        'images': ['/vault/assets/ino_assets/missing.png'],
        'note_path': '/vault/character/ino/I-No H Stroke.md',
        'dustloop_notes': ['At -2 I-No can effectively RPS.'],
        'my_notes': 'Instant block it, then throw.',
      },
    };

    await _pumpLedger(tester, json, width: 1280);
    await _openSituation(tester, card['id'] as String);
    final strip = find.byKey(ValueKey('move-strip-${card['id']}'));
    final text = _textWithin(tester, strip);
    expect(text, contains('Situation 1'));
    expect(text, contains('Startup 28'));
    expect(text, contains('On block -2'));
    expect(text, contains('My note: Instant block it, then throw.'));

    await tester.ensureVisible(find.byType(MoveThumb).first);
    await tester.tap(find.byType(MoveThumb).first);
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('move-dialog-I-No H Stroke'));
    final full = _textWithin(tester, dialog);
    expect(full, contains('I-No H Stroke · 236H'));
    expect(full, contains('Guard Low'));
    expect(full, contains('MY NOTES'));
    expect(full, contains('Instant block it, then throw.'));
    expect(full, contains('• At -2 I-No can effectively RPS.'));
    await tester.tap(find.byKey(const ValueKey('close-move-dialog')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    // A picture the vault no longer has must not break the page.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hit-out-of-a-button card says how the button was lost',
      (tester) async {
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    card['event_read'] = [
      'How it was lost: Elphelt had already started when Ky pressed 5 of 9.',
      'Ky pressed into a move that was already coming.',
    ];

    await _pumpLedger(tester, json, width: 1280);

    await _openSituation(tester, card['id'] as String);

    final text =
        _textWithin(tester, find.byKey(ValueKey('event-read-${card['id']}')));
    expect(text, contains('How it was lost: Elphelt had already started'));
    expect(text, contains('Ky pressed into a move that was already coming.'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reactable seen opponent options are marked as unc check',
      (tester) async {
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    final read = _step12ReadFixture();
    read['kind'] = "opponent's turn";
    read['scope'] = "opponent's turn";
    final matrix = read['matrix'] as Map;
    final option = (matrix['opponent_options'] as List).first as Map;
    option['guard'] = 'high';
    option['active_frames'] = [
      {'frame': 29, 'count': 2},
    ];
    matrix['routes'] = [
      {
        'timings': [
          {
            'option': 'I-No 2P',
            'base_option': 'I-No 2P',
            'reactable': true,
          },
        ],
      },
    ];
    card['read'] = read;

    await _pumpLedger(tester, json, width: 1280);

    await _openSituation(tester, card['id'] as String);

    expect(
      find.byKey(const ValueKey('read-opponent-options')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('read-opponent-options')))
          .data,
      contains('I-No 2P: high, active at 29 (seen 2) (unc check)'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real Elphelt wakeup cards identify the wakeup turn and options',
    (tester) async {
      const sourcePath = 'test/support/step12/elphelt_bomb_bomb.json';
      final sourceDocument = _singleCardDocument(
        sourcePath,
        "Ky woke up after Elphelt's Bomb-Bomb Chocolat",
      );

      await _pumpLedger(tester, sourceDocument, width: 1280);

      await _openSituation(
          tester, SequenceDocument.fromJson(sourceDocument).cards.single.id);

      final panel = find.byKey(const ValueKey('situation-read'));
      final defaultText = _textWithin(tester, panel);
      expect(defaultText, contains('Wakeup'));
      expect(defaultText, contains("Elphelt's turn"));
      expect(
          find.byKey(const ValueKey('read-opponent-options')), findsOneWidget);
      expect(defaultText, contains('active at'));
      expect(defaultText, isNot(contains('he ')));
      expect(defaultText, isNot(contains('she ')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown read kinds and additive keys remain visible as text',
      (tester) async {
    final json = ledgerDocument()..['focus'] = <String>[];
    final card = (json['cards'] as List).first as Map;
    card['read'] = {
      'kind': 'future spot',
      'adv': null,
      'future_summary': 'Keep this finder detail',
      'corner': 'near corner',
      'throw_range': {'min': 2, 'max': 4},
      'fuzzy_candidates': ['low then high'],
    };
    final sequences = [
      for (final value in card['sequences'] as List)
        Map<String, Object?>.from(value as Map),
    ];
    sequences.first['read'] = {'kind': 'future point kind'};
    card['sequences'] = sequences;

    await _pumpLedger(tester, json, width: 360);

    await _openSituation(tester, 'c1');

    expect(find.byKey(const ValueKey('read-headline')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('read-headline'))).data,
        'future spot');
    final details = find.byKey(const ValueKey('read-additional-details'));
    expect(details, findsOneWidget);
    final text = tester.widget<Text>(details).data!;
    expect(text, contains('future_summary: Keep this finder detail'));
    expect(text, contains('corner: near corner'));
    expect(text, contains('throw_range'));
    expect(text, contains('fuzzy_candidates'));
    expect(find.text('Spot: future point kind'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'trend panel shows folded history, signed coloured rows and gone cards',
      (tester) async {
    await _pumpLedger(tester, trendDocument(sets: 6), tab: 'damage');
    expect(find.byKey(const ValueKey('trend-panel')), findsOneWidget);
    final sets =
        tester.widget<Text>(find.byKey(const ValueKey('trend-sets'))).data!;
    expect(sets, startsWith('2 earlier\n2026-10-03 · 5 replays'));
    expect(sets, isNot(contains('2026-10-01')));
    expect(sets,
        contains('2026-10-06 · 12 replays · 872 HP per replay · this set'));
    expect(find.byKey(const ValueKey('trend-ledger')), findsOneWidget);
    for (final entry
        in {'pressing': '-21.7', 'neutral': '+12.3', 'throw': '0.0'}.entries) {
      final row = find.byKey(ValueKey('trend-category-${entry.key}'));
      expect(row, findsOneWidget);
      final delta = find.descendant(of: row, matching: find.text(entry.value));
      expect(delta, findsOneWidget);
      expect(
          tester.widget<Text>(delta).style!.color,
          entry.key == 'pressing'
              ? AfterimageTheme.readyText
              : entry.key == 'neutral'
                  ? AfterimageTheme.failedText
                  : Theme.of(tester.element(row)).textTheme.bodySmall!.color);
    }
    expect(find.text('Now 872.4'), findsOneWidget);
    expect(find.text('Before 910.0'), findsOneWidget);
    expect(find.text('-37.6'), findsOneWidget);
    expect(find.byKey(const ValueKey('trend-gone')), findsOneWidget);
    expect(find.text("Ky blocked I-No's 5H"), findsOneWidget);
    expect(find.text('No longer seen:'), findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('trend-panel'))).dy,
        greaterThan(
            tester.getTopLeft(find.byKey(const ValueKey('damage-ledger'))).dy));
  });

  testWidgets('trend comparisons can be absent independently', (tester) async {
    final json = trendDocument();
    final trend = json['trend'] as Map;
    trend['ledger'] = null;
    await _pumpLedger(tester, json, tab: 'damage');
    expect(find.byKey(const ValueKey('trend-ledger')), findsNothing);
    expect(
        find.text(
            'No earlier set with HP data and at least 3 replays to compare damage with.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('trend-gone')), findsOneWidget);
    (trend['cards'] as Map)['gone'] = <Object?>[];
    await _pumpLedger(tester, json, tab: 'damage');
    expect(find.byKey(const ValueKey('trend-gone')), findsNothing);
    expect(find.text('Cards compared with 2026-10-20 (6 replays)'),
        findsOneWidget);
    trend['ledger'] = (trendDocument()['trend'] as Map)['ledger'];
    trend['cards'] = null;
    await _pumpLedger(tester, json, tab: 'damage');
    expect(find.byKey(const ValueKey('trend-ledger')), findsOneWidget);
    expect(find.byKey(const ValueKey('trend-gone')), findsNothing);
    for (final value in [null, <String, Object?>{}]) {
      await _pumpLedger(tester, {...json, 'trend': value}, tab: 'damage');
      expect(find.byKey(const ValueKey('trend-panel')), findsNothing);
    }
  });

  testWidgets(
      'trend card text survives expanding situation and event cards including focus',
      (tester) async {
    await _pumpLedger(tester, trendDocument());
    for (final id in ['c1', 'c5', 'e1', 'e2']) {
      if (id.startsWith('e')) await _openTab(tester, 'hits');
      await _openSituation(tester, id);
      final line = find.byKey(ValueKey('trend-text-$id'));
      expect(line, findsOneWidget);
      expect(
          tester.widget<Text>(line).data, 'Earlier set: $id. Now seen again.');
      expect(tester.widget<Text>(line).style!.color,
          AfterimageTheme.dark().colorScheme.onSurfaceVariant);
      await _tapKey(tester, 'back-to-situations');
    }
  });

  testWidgets('trend panel fits 360 px with long labels and text',
      (tester) async {
    final json = trendDocument(sets: 6);
    // Isolate the panel from the pre-existing card layout in this surface check.
    json['cards'] = <Object?>[];
    final trend = json['trend'] as Map;
    final ledger = trend['ledger'] as Map;
    ((ledger['categories'] as List).first as Map)['label'] =
        'Hit while pressing a button with a very long description of the situation';
    await _pumpLedger(tester, json, width: 360, tab: 'damage');
    expect(tester.takeException(), isNull);
    for (final key in ['trend-panel', 'trend-ledger', 'trend-gone']) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('events render finder text and reuse Save and clips',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preview = _preview(directory: '/out/batch-a/I-No');
    final repository = _FakeNotesRepository(
        preview,
        NoteSequenceData(
            preview: preview,
            document: SequenceDocument.fromJson(eventDocument(focus: false))));
    await tester.pumpWidget(_app(NotesPage(
        repository: repository,
        preview: preview,
        onBack: () {},
        playerFactory: (_) => _FakeClipSession())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sequence-card-e1')), findsNothing,
        reason: 'event cards live in the Got hit tab');
    await _openTab(tester, 'hits');
    await _openSituation(tester, 'e1');
    final event = find.byKey(const ValueKey('sequence-card-e1'));
    expect(find.text('I-No hit Ky out of pressing'), findsOneWidget);
    expect(
        find.descendant(
            of: event,
            matching: find.text('What beat Ky 6P: j.S x7, 2H x2, 2K x2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('event-more-e1')), findsOneWidget);
    expect(
        find.descendant(
            of: event,
            matching: find.text('Showing the 1 most damaging of 11.')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('sequence-e1-s1')), findsOneWidget);
    expect(find.descendant(of: event, matching: find.text('I-No j.S > Ky 6P')),
        findsOneWidget);
    expect(
        find.descendant(
            of: event,
            matching: find.text(
                'I-No counter-hit Ky (96 damage) · Ky 6P was on frame 5 of 9 startup')),
        findsOneWidget);
    await _tapKey(tester, 'save-e1-s1');
    expect(repository.saved.single.single.fileName, 'e1.txt');
    expect(find.byKey(const ValueKey('save-done')), findsOneWidget);
    await _tapKey(tester, 'play-e1-s1');
    expect(find.byKey(const ValueKey('clip-e1-s1')), findsOneWidget);
    await _tapKey(tester, 'back-to-situations');
    await _openSituation(tester, 'e5');
    expect(find.byKey(const ValueKey('sequence-e5-s1')), findsOneWidget);
  });

  for (final focus in [true, false]) {
    testWidgets('event cards have their own tab, focus $focus', (tester) async {
      await _pumpLedger(tester,
          {...eventDocument(focus: focus), 'ledger': null, 'player': null});
      // The landing has situation rows, while events have their own tab.
      expect(find.byKey(const ValueKey('event-cards')), findsNothing);
      expect(find.byKey(const ValueKey('sequence-card-e5')), findsNothing);
      expect(find.byKey(const ValueKey('situation-row-c6')), findsOneWidget);
      expect(find.byKey(const ValueKey('situation-row-e1')), findsNothing);
      await _openTab(tester, 'hits');
      expect(find.byKey(const ValueKey('sequence-card-c6')), findsNothing);
      final group = find.byKey(const ValueKey('event-cards'));
      final positions = [
        for (final id in ['e5', 'e4', 'e3', 'e2', 'e1'])
          tester
              .getTopLeft(find.descendant(
                  of: group,
                  matching: find.byKey(ValueKey('situation-row-$id'))))
              .dy
      ];
      expect(positions, orderedEquals([...positions]..sort()));
    });
  }

  for (final id in ['e1', 'c2', 'c5']) {
    testWidgets('ledger reveals and scrolls to $id', (tester) async {
      await _pumpLedger(tester, eventDocument(), tab: 'damage');
      await _tapKey(tester, 'ledger-category-neutral');
      expect(find.byKey(const ValueKey('ledger-card-missing')), findsNothing);
      await _tapKey(tester, 'ledger-card-$id');
      expect(find.byKey(ValueKey('sequence-$id-s1')), findsOneWidget);
      expect(find.byKey(ValueKey('show-sequences-$id')), findsNothing);
      final rect = tester.getRect(find.byKey(ValueKey('sequence-card-$id')));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.top, lessThan(900));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1280.0, 700.0]) {
    testWidgets('all event and ledger content expanded fits at $width',
        (tester) async {
      await _pumpLedger(tester, eventDocument(long: true),
          width: width, tab: 'damage');
      expect(tester.takeException(), isNull);
      await _tapKey(tester, 'ledger-category-neutral');
      await _tapKey(tester, 'ledger-category-pressing');
      await _openTab(tester, 'spots');
      for (final id in ['c3', 'c5', 'c6', 'e5', 'e4', 'e3', 'e1']) {
        if (id == 'e5') await _openTab(tester, 'hits');
        await _openSituation(tester, id);
        expect(tester.takeException(), isNull);
        await _tapKey(tester, 'back-to-situations');
      }
    });
  }

  testWidgets('ledger renders totals, proportional bars and expanded evidence',
      (tester) async {
    final json = ledgerDocument();
    final categories = (json['ledger'] as Map)['categories'] as List;
    (categories[1] as Map)['share'] = 0.148;
    await _pumpLedger(tester, json);
    expect(find.byKey(const ValueKey('damage-ledger')), findsNothing,
        reason: 'the ledger lives in the Damage tab');
    await _openTab(tester, 'damage');
    expect(find.byKey(const ValueKey('damage-ledger')), findsOneWidget);
    expect(find.text('WHERE THE DAMAGE CAME FROM'), findsOneWidget);
    expect(
        find.text(
            'Ky lost 10,469 health over 12 games. Situations cover 2,506 of it (24%).'),
        findsOneWidget);
    expect(find.text('3,100'), findsOneWidget);
    final bars = tester
        .widgetList<UiMeter>(find.descendant(
            of: find.byKey(const ValueKey('damage-ledger')),
            matching: find.byType(UiMeter)))
        .toList();
    expect(bars.map((bar) => bar.fraction), [1.0, 0.5]);
    expect(find.byKey(const ValueKey('ledger-starters-neutral')), findsNothing);
    await _tapKey(tester, 'ledger-category-neutral');
    expect(find.text('41 events'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('ledger-starters-neutral')), findsOneWidget);
    expect(find.text('j.S · 9 times · 900 damage · 2 on counter hit'),
        findsOneWidget);
    expect(find.text('replay 3, round 2 at 08:32 (141)'), findsOneWidget);
    expect(find.text('replay 4, round 1 (70)'), findsOneWidget);
    await _tapKey(tester, 'ledger-category-pressing');
    expect(find.text('Ky was pressing: f.S x4, 2K x2'), findsOneWidget);
    expect(find.byType(NotesClipPlayer), findsNothing);
    await _tapKey(tester, 'ledger-category-neutral');
    expect(find.byKey(const ValueKey('ledger-starters-neutral')), findsNothing);
  });

  testWidgets('ledger uses You when the player is missing', (tester) async {
    await _pumpLedger(tester, {...ledgerDocument(), 'player': null},
        tab: 'damage');
    expect(
        find.text(
            'You lost 10,469 health over 12 games. Situations cover 2,506 of it (24%).'),
        findsOneWidget);
    await _tapKey(tester, 'ledger-category-pressing');
    expect(find.text('You were pressing: f.S x4, 2K x2'), findsOneWidget);
  });

  testWidgets('ledger hides for null and zero damage', (tester) async {
    for (final ledger in [
      null,
      {'total_damage': 0}
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpLedger(tester, {...ledgerDocument(), 'ledger': ledger});
      expect(find.byKey(const ValueKey('damage-ledger')), findsNothing);
    }
  });

  testWidgets('focus preserves order and ignores unknown ids', (tester) async {
    await _pumpLedger(tester, {...ledgerDocument(), 'ledger': null});
    final group = find.byKey(const ValueKey('focus-group'));
    expect(find.text('WORK ON THESE'), findsOneWidget);
    final first = find.descendant(
        of: group, matching: find.byKey(const ValueKey('focus-row-c3')));
    final second = find.descendant(
        of: group, matching: find.byKey(const ValueKey('focus-row-c1')));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(find.byKey(const ValueKey('focus-row-missing')), findsNothing);
    for (final id in ['c2', 'c4', 'c5']) {
      expect(find.byKey(ValueKey('situation-row-$id')), findsOneWidget);
    }
  });

  testWidgets('three focus rows follow finder order', (tester) async {
    await _pumpLedger(tester, {
      ...ledgerDocument(),
      'focus': ['c6', 'c3', 'c1'],
      'ledger': null,
    });
    final positions = [
      for (final id in ['c6', 'c3', 'c1'])
        tester.getTopLeft(find.byKey(ValueKey('focus-row-$id'))).dy
    ];
    expect(positions, orderedEquals([...positions]..sort()));
  });

  testWidgets('empty answers and a null reversal note leave no blocks',
      (tester) async {
    final json = ledgerDocument();
    json['cards'] = [
      {'id': 'empty', 'answers': <Object?>[], 'reversal_note': null}
    ];
    await _pumpLedger(tester, json);
    expect(find.byKey(const ValueKey('answers-empty')), findsNothing);
    expect(find.byKey(const ValueKey('reversal-note-empty')), findsNothing);
  });

  testWidgets('empty focus keeps the original situation order', (tester) async {
    await _pumpLedger(
        tester, {...ledgerDocument(), 'focus': <String>[], 'ledger': null});
    expect(find.byKey(const ValueKey('focus-group')), findsNothing);
    expect(find.byKey(const ValueKey('other-flagged')), findsNothing);
    final positions = [
      for (var i = 1; i <= 6; i++)
        tester.getTopLeft(find.byKey(ValueKey('situation-row-c$i'))).dy
    ];
    expect(positions, orderedEquals([...positions]..sort()));
    await _openSituation(tester, 'c2');
    expect(find.byKey(const ValueKey('sequence-c2-s1')), findsOneWidget);
  });

  testWidgets('answer scoreboard and muted reversal note render under flags',
      (tester) async {
    await _pumpLedger(tester, {...ledgerDocument(), 'ledger': null});
    await _tapKey(tester, 'focus-row-c3');
    final answers = find.byKey(const ValueKey('answers-c3'));
    expect(answers, findsOneWidget);
    final row = find.byKey(const ValueKey('answer-row-Ky blocked'));
    final text = _textWithin(tester, row);
    for (final value in ['Ky blocked', '9 times', 'hit 3', '240 damage']) {
      expect(text, contains(value));
    }
    final bar = tester.widget<UiSplitBar>(
        find.descendant(of: row, matching: find.byType(UiSplitBar)));
    expect(bar.parts, [(3, Ui.bad), (5, Ui.warn), (1, Ui.idle), (0, Ui.good)]);
    expect(_textWithin(tester, answers), contains('won 2'));
    final note = find.byKey(const ValueKey('reversal-note-c3'));
    expect(tester.widget<Text>(note).data, contains('S Vapor Thrust'));
    expect(tester.widget<Text>(note).style!.color, Ui.inkMid);
    expect(tester.getTopLeft(find.byKey(const ValueKey('flag-c3-losing'))).dy,
        lessThan(tester.getTopLeft(note).dy));
    expect(tester.getTopLeft(answers).dy, lessThan(tester.getTopLeft(note).dy));
  });

  testWidgets('old cards omit ledger, focus, scoreboard and reversal note',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preview = _preview(directory: '/out/batch-a/May');
    await tester.pumpWidget(_app(NotesPage(
        repository: _FakeNotesRepository(preview, _data(preview)),
        preview: preview,
        onBack: () {})));
    await _openSituation(tester, 'c1');
    for (final key in [
      'damage-ledger',
      'trend-panel',
      'trend-text-c1',
      'focus-group',
      'other-flagged',
      'answers-c1',
      'reversal-note-c1'
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
  });

  for (final width in [1280.0, 700.0]) {
    testWidgets('long ledger and all expanded cards fit at $width px',
        (tester) async {
      await _pumpLedger(tester, ledgerDocument(long: true),
          width: width, tab: 'damage');
      await _tapKey(tester, 'ledger-category-neutral');
      await _tapKey(tester, 'ledger-category-pressing');
      await _openTab(tester, 'spots');
      for (var i = 1; i <= 6; i++) {
        await _openSituation(tester, 'c$i');
        final sequence = find.byKey(ValueKey('sequence-c$i-s1'));
        expect(sequence, findsOneWidget);
        await tester.ensureVisible(sequence);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tapKey(tester, 'back-to-situations');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('flagged cards show flags, lead-ins and mixups', (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final repository = _FakeNotesRepository(preview, _data(preview));

    await tester.pumpWidget(_app(NotesPage(
      repository: repository,
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');

    expect(find.text('blocked S Mr. Dolphin Vertical'), findsOneWidget);
    expect(find.text('keeps losing: hit 2 of 3'), findsOneWidget);
    expect(find.text('lead-ins: 2K x2, string opener x1'), findsOneWidget);
    expect(find.text('mixup after 2K: 5H x1, jump back x1'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-c1-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-c2-s1')), findsNothing);
    expect(find.byKey(const ValueKey('strivelabs-notice')), findsOneWidget);
    await _tapKey(tester, 'back-to-situations');
    await _openSituation(tester, 'c2');
    expect(find.byKey(const ValueKey('save-c2-s1')), findsOneWidget);
  });

  testWidgets('Save writes that sequence and says where it went',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final repository = _FakeNotesRepository(preview, _data(preview));
    final saving = <bool>[];

    await tester.pumpWidget(_app(NotesPage(
      repository: repository,
      preview: preview,
      onBack: () {},
      onSavingChanged: saving.add,
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');
    await tester.tap(find.byKey(const ValueKey('save-c1-s1')));
    await tester.pump();
    await tester.pump();

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.map((r) => r.fileName), ['May - first.txt']);
    expect(saving, [true, false]);
    expect(find.byKey(const ValueKey('save-done')), findsOneWidget);
    expect(find.textContaining('Saved May - first.txt'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('Save mixup writes every file of that mixup', (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final repository = _FakeNotesRepository(preview, _data(preview));

    await tester.pumpWidget(_app(NotesPage(
      repository: repository,
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');
    await tester.tap(find.byKey(const ValueKey('save-mixup-c1-0')));
    await tester.pump();
    await tester.pump();

    expect(repository.saved.single.map((r) => r.fileName), [
      'May - mixup 1 of 2 (5H).txt',
      'May - mixup 2 of 2 (jump back).txt',
    ]);
  });

  testWidgets('a sequence without a recording cannot be saved and says why',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final repository = _FakeNotesRepository(preview, _data(preview));

    await tester.pumpWidget(_app(NotesPage(
      repository: repository,
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');

    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('save-c1-s3')))
          .onPressed,
      isNull,
    );
    expect(
      find.text('cannot save: this capture has no replay input stream'),
      findsOneWidget,
    );
  });

  testWidgets('saves are locked while one runs, and a failure is shown',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final repository = _FakeNotesRepository(preview, _data(preview))
      ..gate = Completer<void>()
      ..failWith = StateError('disk full');

    await tester.pumpWidget(_app(NotesPage(
      repository: repository,
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');
    await tester.tap(find.byKey(const ValueKey('save-c1-s1')));
    await tester.pump();

    for (final key in ['save-c1-s1', 'save-c1-s2', 'save-mixup-c1-0']) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
        reason: '$key while saving',
      );
    }
    await _tapKey(tester, 'back-to-situations');
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('back-from-sequences')))
            .onPressed,
        isNull);
    await _openSituation(tester, 'c1');
    repository.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('save-failed')), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('save-c1-s1')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('clip playback is lazy and plays the sequence that was tapped',
      (tester) async {
    final opened = <String>[];
    final sessions = <_FakeClipSession>[];
    final directory = _createTempDirectory('afterimage-sequence-clips');
    Directory('${directory.path}/clips').createSync();
    for (final name in ['c1-s1.mp4', 'c1-s2.mp4']) {
      File('${directory.path}/clips/$name').createSync();
    }
    addTearDown(() => _deleteTempEntity(directory));
    final preview = _preview(directory: directory.path);

    await tester.pumpWidget(_app(NotesPage(
      repository: _FakeNotesRepository(preview, _data(preview)),
      preview: preview,
      onBack: () {},
      playerFactory: (path) {
        opened.add(path.split(RegExp(r'[\\/]')).last);
        final session = _FakeClipSession();
        sessions.add(session);
        return session;
      },
    )));
    await _openSituation(tester, 'c1');
    expect(find.byType(NotesClipPlayer), findsNothing);
    expect(opened, isEmpty);

    await tester.ensureVisible(find.byKey(const ValueKey('play-c1-s2')));
    await tester.tap(find.byKey(const ValueKey('play-c1-s2')));
    await _settleIo(
      tester,
      () => sessions.isNotEmpty && sessions.single.playCalls == 1,
    );

    expect(opened, ['c1-s2.mp4']);
    expect(sessions.single.playCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(sessions.single.disposeCalls, 1);
  });

  testWidgets('the list shows each opponent and situation counts',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final opened = <NotePreview>[];

    await tester.pumpWidget(_app(NotesListPage(
      repository: _FakeNotesRepository(preview, _data(preview)),
      onOpen: opened.add,
      onClose: () {},
    )));
    await _pumpUntilFound(tester, find.text('vs May'));

    expect(find.textContaining('2 situations'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-notes-entry')));
    expect(opened, [preview]);
  });

  testWidgets('missing clip files show unavailable without opening a session',
      (tester) async {
    var factoryCalls = 0;
    final missingPath =
        '${Directory.systemTemp.path}/afterimage-missing-${DateTime.now().microsecondsSinceEpoch}.mp4';

    await tester.pumpWidget(_app(
      NotesClipPlayer(
        clip: const NoteClip(
          file: 'missing.mp4',
          poster: null,
          replay: 1,
          videoTime: '00:54',
          videoTimeMs: 54989,
          startMs: 53489,
          endMs: 57100,
          herNext: null,
          answer: 'Ky 5P',
          outcome: 'hit',
          counterHit: true,
        ),
        filePath: missingPath,
        playerFactory: (_) {
          factoryCalls++;
          return _FakeClipSession();
        },
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('clip-play')));
    await _settleIo(
      tester,
      () => find.text('Clip unavailable').evaluate().isNotEmpty,
    );

    expect(factoryCalls, 0);
    expect(find.text('Clip unavailable'), findsOneWidget);
  });

  testWidgets('clip settings selected before play are applied on start',
      (tester) async {
    final session = _FakeClipSession();
    final clipFile = File(
      '${Directory.systemTemp.path}/afterimage-settings-clip.mp4',
    )..createSync();
    addTearDown(() => _deleteTempEntity(clipFile));

    await tester.pumpWidget(
      _app(
        NotesClipPlayer(
          clip: const NoteClip(
            file: 's1-1.mp4',
            poster: null,
            replay: 1,
            videoTime: '00:54',
            videoTimeMs: 54989,
            startMs: 53489,
            endMs: 57100,
            herNext: null,
            answer: 'Ky 5P',
            outcome: 'hit',
            counterHit: true,
          ),
          filePath: clipFile.path,
          playerFactory: (_) => session,
        ),
      ),
    );

    tester
        .widget<DropdownButton<double>>(find.byType(DropdownButton<double>))
        .onChanged!(0.5);
    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-loop')))
        .onPressed!();
    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-play')))
        .onPressed!();
    await _settleIo(
      tester,
      () => session.rateCalls == 1 && session.loopCalls == 1,
    );

    expect(session.rateCalls, 1);
    expect(session.lastRate, 0.5);
    expect(session.loopCalls, 1);
    expect(session.lastLoop, isFalse);
  });

  testWidgets('pausing keeps the paused frame on screen, not the poster',
      (tester) async {
    final session = _FakeClipSession();
    final clipFile = File(
      '${Directory.systemTemp.path}/afterimage-pause-frame-clip.mp4',
    )..createSync();
    addTearDown(() => _deleteTempEntity(clipFile));
    await tester.pumpWidget(
      _app(
        NotesClipPlayer(
          clip: _playerClip,
          filePath: clipFile.path,
          playerFactory: (_) => session,
        ),
      ),
    );

    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-play')))
        .onPressed!();
    await _settleIo(
      tester,
      () => find.byKey(_FakeClipSession.videoKey).evaluate().isNotEmpty,
    );
    expect(find.byKey(_FakeClipSession.videoKey), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clip-play')));
    await _flushIo(tester);
    await tester.pump();

    expect(session.pauseCalls, 1);
    expect(find.byKey(_FakeClipSession.videoKey), findsOneWidget);
  });

  testWidgets('frame steps, keys, scrubbing and clicking the video work',
      (tester) async {
    final session = _FakeClipSession();
    final clipFile = File(
      '${Directory.systemTemp.path}/afterimage-player-keys-clip.mp4',
    )..createSync();
    addTearDown(() => _deleteTempEntity(clipFile));
    await tester.pumpWidget(
      _app(
        NotesClipPlayer(
          clip: _playerClip,
          filePath: clipFile.path,
          playerFactory: (_) => session,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('clip-surface')));
    await _settleIo(tester, () => session.playCalls == 1);
    expect(session.playCalls, 1);
    session.emitDuration(const Duration(seconds: 4));
    session.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('0:02.00 / 0:04.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clip-step-forward')));
    await _flushIo(tester);
    await tester.pump();
    expect(session.pauseCalls, 1);
    expect(session.steps, [1]);
    expect(find.byKey(_FakeClipSession.videoKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _flushIo(tester);
    expect(session.steps, [1, -1, 1]);
    expect(session.seeks.last, const Duration(seconds: 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.pump();
    expect(session.playCalls, 2);

    tester.widget<Slider>(find.byKey(const ValueKey('clip-seek'))).onChanged!(
      const Duration(milliseconds: 3500).inMicroseconds.toDouble(),
    );
    await _flushIo(tester);
    expect(session.seeks.last, const Duration(milliseconds: 3500));
  });

  testWidgets('a double click while starting opens one player', (tester) async {
    final sessions = <_FakeClipSession>[];
    final clipFile = File(
      '${Directory.systemTemp.path}/afterimage-double-click-clip.mp4',
    )..createSync();
    addTearDown(() => _deleteTempEntity(clipFile));
    await tester.pumpWidget(_app(NotesClipPlayer(
      clip: _playerClip,
      filePath: clipFile.path,
      playerFactory: (_) {
        final session = _FakeClipSession();
        sessions.add(session);
        return session;
      },
    )));

    final play = tester.widget<IconButton>(
      find.byKey(const ValueKey('clip-play')),
    );
    play.onPressed!();
    play.onPressed!();
    await _settleIo(tester, () => sessions.isNotEmpty);
    await _settleIo(tester, () => false);

    expect(sessions, hasLength(1));
  });

  testWidgets('leaving while a clip starts never opens a player',
      (tester) async {
    var opened = 0;
    final clipFile = File(
      '${Directory.systemTemp.path}/afterimage-leave-early-clip.mp4',
    )..createSync();
    addTearDown(() => _deleteTempEntity(clipFile));
    await tester.pumpWidget(_app(NotesClipPlayer(
      clip: _playerClip,
      filePath: clipFile.path,
      playerFactory: (_) {
        opened++;
        return _FakeClipSession();
      },
    )));

    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-play')))
        .onPressed!();
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleIo(tester, () => false);

    expect(opened, 0);
  });

  testWidgets('the card clicked last wins when two start together',
      (tester) async {
    final sessions = <String, _FakeClipSession>{};
    final gateA = Completer<void>();
    final clipDirectory = _createTempDirectory('afterimage-race-clips');
    final clipA = File('${clipDirectory.path}/a.mp4')..createSync();
    final clipB = File('${clipDirectory.path}/b.mp4')..createSync();
    addTearDown(() => _deleteTempEntity(clipDirectory));
    await tester.pumpWidget(_app(
      _TwoClipHarness(
        clip: _playerClip,
        filePaths: [clipA.path, clipB.path],
        playerFactory: (path) {
          final session = _FakeClipSession();
          if (path.endsWith('a.mp4')) session.gate = gateA;
          return sessions[path.split('/').last] = session;
        },
      ),
    ));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('two-clip-harness')));

    final play = find.byKey(const ValueKey('clip-play'));
    tester.widget<IconButton>(play.at(0)).onPressed!();
    tester.widget<IconButton>(play.at(1)).onPressed!();
    await tester.pump();
    await _settleIo(tester, () => (sessions['b.mp4']?.playCalls ?? 0) == 1);
    // A's startup was slower; it finishes only now, after B is playing.
    gateA.complete();
    await _settleIo(tester, () => false);

    expect(sessions['b.mp4']?.playCalls, 1);
    expect(sessions['b.mp4']?.pauseCalls, 0);
    final a = sessions['a.mp4'];
    expect(a == null || a.playCalls == 0 || a.pauseCalls >= a.playCalls, isTrue,
        reason: 'A started before B but must not keep playing');
  });

  testWidgets('starting a clip pauses the other card', (tester) async {
    final sessions = <_FakeClipSession>[];
    final clipDirectory = _createTempDirectory('afterimage-restart-clips');
    final clipA = File('${clipDirectory.path}/a.mp4')..createSync();
    final clipB = File('${clipDirectory.path}/b.mp4')..createSync();
    addTearDown(() => _deleteTempEntity(clipDirectory));
    const clip = NoteClip(
      file: 's1-1.mp4',
      poster: null,
      replay: 1,
      videoTime: '00:54',
      videoTimeMs: 54989,
      startMs: 53489,
      endMs: 57100,
      herNext: null,
      answer: 'Ky 5P',
      outcome: 'hit',
      counterHit: true,
    );
    await tester.pumpWidget(_app(
      _TwoClipHarness(
        clip: clip,
        filePaths: [clipA.path, clipB.path],
        playerFactory: (_) {
          final session = _FakeClipSession();
          sessions.add(session);
          return session;
        },
      ),
    ));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('two-clip-harness')));

    final play = find.byKey(const ValueKey('clip-play'));
    tester.widget<IconButton>(play.at(0)).onPressed!();
    await tester.pump();
    await _flushIo(tester);
    await tester.pump();
    expect(sessions, hasLength(1));
    tester.widget<IconButton>(play.at(1)).onPressed!();
    await tester.pump();
    await _flushIo(tester);
    await tester.pump();
    expect(sessions, hasLength(2));
    expect(sessions[0].pauseCalls, 1);
    final pausesOfB = sessions[1].pauseCalls;
    tester.widget<IconButton>(play.at(0)).onPressed!();
    await _flushIo(tester);
    await tester.pump();

    expect(sessions, hasLength(2));
    expect(sessions[1].pauseCalls, pausesOfB + 1);
  });

  // v0.3.3: the clip opens under the tapped row; one player on the page.
  testWidgets('the clip opens under the tapped row, moves, and closes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessions = <_FakeClipSession>[];
    final directory = _createTempDirectory('afterimage-row-clips');
    Directory('${directory.path}/clips').createSync();
    for (final name in ['c1-s1.mp4', 'c1-s2.mp4', 'c1-s3.mp4', 'c2-s1.mp4']) {
      File('${directory.path}/clips/$name').createSync();
    }
    addTearDown(() => _deleteTempEntity(directory));
    final preview = _preview(directory: directory.path);

    await tester.pumpWidget(_app(NotesPage(
      repository: _FakeNotesRepository(preview, _data(preview)),
      preview: preview,
      onBack: () {},
      playerFactory: (_) {
        final session = _FakeClipSession();
        sessions.add(session);
        return session;
      },
    )));
    await _openSituation(tester, 'c1');
    expect(find.byType(NotesClipPlayer), findsNothing);

    await tester.tap(find.byKey(const ValueKey('play-c1-s2')));
    await _settleIo(
        tester, () => sessions.isNotEmpty && sessions.last.playCalls == 1);
    final player = find.byKey(const ValueKey('clip-player-c1-s2'));
    expect(player, findsOneWidget);
    expect(sessions.single.playCalls, 1);
    final row = tester.getRect(find.byKey(const ValueKey('sequence-c1-s2')));
    final next = tester.getRect(find.byKey(const ValueKey('sequence-c1-s3')));
    final box = tester.getRect(player);
    expect(box.top, greaterThanOrEqualTo(row.bottom));
    expect(box.bottom, lessThanOrEqualTo(next.top));

    await tester.tap(find.byKey(const ValueKey('play-c1-s1')));
    await _settleIo(
        tester, () => sessions.length == 2 && sessions.last.playCalls == 1);
    expect(find.byKey(const ValueKey('clip-player-c1-s2')), findsNothing);
    expect(find.byKey(const ValueKey('clip-player-c1-s1')), findsOneWidget);
    expect(find.byType(NotesClipPlayer), findsOneWidget);
    expect(sessions.first.disposeCalls, 1);

    await tester.tap(find.byKey(const ValueKey('play-c1-s1')));
    await tester.pump();
    expect(find.byType(NotesClipPlayer), findsNothing);

    await tester.tap(find.byKey(const ValueKey('play-c1-s3')));
    await tester.pump();
    await _tapKey(tester, 'back-to-situations');
    await _openSituation(tester, 'c2');
    await tester.ensureVisible(find.byKey(const ValueKey('play-c2-s1')));
    await tester.tap(find.byKey(const ValueKey('play-c2-s1')));
    await tester.pump();
    expect(find.byType(NotesClipPlayer), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-player-c2-s1')), findsOneWidget);
    await _settleIo(tester, () => false);
  });

  testWidgets('Save buttons have one width whatever the frame count',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    await tester.pumpWidget(_app(NotesPage(
      repository: _FakeNotesRepository(preview, _dataV033(preview)),
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');

    expect(find.text('Save (95f)'), findsOneWidget);
    expect(find.text('Save (798f)'), findsOneWidget);
    final widths = {
      for (final key in ['save-c1-s1', 'save-c1-s2', 'save-mixup-c1-0'])
        tester.getSize(find.byKey(ValueKey(key))).width,
    };
    expect(widths, hasLength(1));
  });

  testWidgets('finder display text is shown as written, with names',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    await tester.pumpWidget(_app(NotesPage(
      repository: _FakeNotesRepository(preview, _dataV033(preview)),
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _openSituation(tester, 'c1');

    expect(find.text("Ky blocked May's j.H"), findsOneWidget);
    final stats =
        _textWithin(tester, find.byKey(const ValueKey('detail-stats-c1')));
    expect(stats, contains('5'));
    expect(stats, contains('1 of 5'));
    expect(stats, contains('78'));
    expect(
      find.text(
          "What May did before j.H: S Mr. Dolphin Horizontal x2, nothing x2, 2S x1"),
      findsOneWidget,
    );
    expect(find.text("May's mixup after S Mr. Dolphin Horizontal > j.H:"),
        findsOneWidget);
    expect(find.text('Ground Throw x1, f.S x1'), findsOneWidget);
    expect(find.text('S Mr. Dolphin Horizontal > j.H > Ground Throw'),
        findsOneWidget);
    expect(find.text('Ky crouch-blocked · May hit Ky (78 damage)'),
        findsOneWidget);
    expect(find.text('r2 · round 1 · 04:17.2'), findsWidgets);
    await _tapKey(tester, 'back-to-situations');
    await _openSituation(tester, 'c2');
    expect(find.text("May's 6H guard-crushed Ky"), findsOneWidget);
    expect(find.byKey(const ValueKey('save-c2-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('show-sequences-c2')), findsNothing);
    expect(find.text('May guard-crushed Ky (59 damage)'), findsOneWidget);
  });
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AfterimageTheme.dark(),
    home: Scaffold(body: home),
  );
}

String _textWithin(WidgetTester tester, Finder parent) => tester
    .widgetList<Text>(find.descendant(of: parent, matching: find.byType(Text)))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
    .join('\n');

Map<String, Object?> _singleCardDocument(String sourcePath, String title) {
  final document = decodeObject(File(sourcePath).readAsStringSync());
  final card = Map<String, Object?>.from(
    (document['cards'] as List).cast<Map>().singleWhere(
          (candidate) => candidate['title'] == title,
        ),
  );
  return {
    ...document,
    'cards': [card],
    'focus': <Object?>[]
  };
}

NotePreview _preview({required String directory}) => NotePreview(
      batchLabel: 'batch-a',
      opponent: 'May',
      directoryPath: directory,
      documentPath: '$directory/sequences.json',
      cardCount: 2,
      flaggedCount: 1,
      createdAt: DateTime(2026, 11, 9, 23),
      modifiedAt: DateTime(2026, 11, 9, 23),
    );

Map<String, Object?> _recording(String name) =>
    {'file_name': name, 'text': '# $name\nW10\n', 'frames': 10};

Map<String, Object?> _step12ReadFixture() => {
      'version': 1,
      'kind': "player's turn",
      'adv': 2,
      'scope': "player's turn",
      'matrix': {
        'player_options': [
          {
            'id': 'Ky 5P',
            'label': '5P',
            'kind': 'button',
            'startup': 5,
            'sources': ['vault', 'seen'],
            'availability': 'available',
          },
          {
            'id': 'Ky Sacred Edge',
            'label': 'Sacred Edge',
            'kind': 'button',
            'availability': 'tension unknown',
          },
        ],
        'opponent_options': [
          {
            'id': 'I-No 2P',
            'label': '2P',
            'sources': ['seen']
          },
          {
            'id': 'I-No backdash',
            'label': 'backdash',
            'sources': ['seen']
          },
          {
            'id': 'I-No Megalo',
            'label': 'Megalo',
            'sources': ['seen']
          },
          {
            'id': 'I-No Roman Cancel',
            'label': 'Roman Cancel',
            'sources': ['seen'],
          },
        ],
        'rows': [
          {
            'options': ['Ky 5P', 'Ky Sacred Edge'],
            'cells': {
              'I-No 2P': {
                'value': 'active first',
                'winner': 'player',
                'seen': {'count': 2, 'won': 1, 'lost': 1},
              },
              'I-No backdash': {
                'value': 'active after',
                'winner': 'opponent',
                'seen': {'count': 1},
              },
              'I-No Megalo': {
                'value': 'check reach',
                'winner': null,
                'seen': {'count': 1},
              },
              'I-No Roman Cancel': {
                'value': 'seen only',
                'winner': null,
                'seen': {'count': 1},
              },
            },
          },
        ],
        'never_works_here': ['Ky 2H', 'Ky 6H'],
        'dominant_rows': [],
      },
      'mistakes': {
        'knowledge': {
          'count': 1,
          'points': ['c1-s1']
        },
        'execution': {
          'count': 2,
          'points': ['c1-s2', 'c1-s3']
        },
        'guess': {
          'count': 3,
          'points': ['c1-s4', 'c1-s5', 'c1-s6']
        },
        'unc check': {
          'count': 4,
          'points': ['c1-s7']
        },
        'unclear': {
          'count': 5,
          'points': ['c1-s8']
        },
      },
    };

Map<String, Object?> _clip(String id) => {
      'file': '$id.mp4',
      'poster': null,
      'replay': 2,
      'video_time': '04:11.6',
      'video_time_ms': 251571,
      'start_ms': 250000,
      'end_ms': 253000,
      'her_next': '5H',
      'option': '5H',
      'answer': 'block crouch',
      'outcome': 'hit',
      'counter_hit': false,
    };

Map<String, Object?> _sequence(
  String id, {
  Map<String, Object?>? recording,
  String? error,
}) =>
    {
      'id': id,
      'replay': 2,
      'round': 1,
      'video_time': '04:11.6',
      'video_time_ms': 251571,
      'lead_in': '2K',
      'follow_up': '5H',
      'answer': 'block crouch',
      'outcome': 'hit',
      'counter_hit': false,
      'damage': 70,
      'flags': ['keeps_losing'],
      'recording': recording,
      'recording_error': error,
      'clip': _clip(id),
    };

NoteSequenceData _data(NotePreview preview) => NoteSequenceData(
      preview: preview,
      document: SequenceDocument.fromJson({
        'schema': 1,
        'opponent': 'May',
        'player': 'Ky',
        'batch_label': 'batch-a',
        'batch_folder': '/videos/batch-a',
        'created_at': '2026-11-09T23:00:00+07:00',
        'strivelabs_recordings': '/game/ue4ss/recordings',
        'warnings': <String>[],
        'clip_errors': <String>[],
        'cards': [
          {
            'id': 'c1',
            'title': 'blocked S Mr. Dolphin Vertical',
            'flagged': true,
            'damage': 140,
            'hits': 2,
            'decided': 3,
            'count': 3,
            'flags': [
              {
                'kind': 'keeps_losing',
                'reason': 'keeps losing: hit 2 of 3',
                'player': null,
                'count': 3,
              },
            ],
            'lead_ins': [
              {'move': '2K', 'count': 2},
              {'move': null, 'count': 1},
            ],
            'sequences': [
              _sequence('c1-s1', recording: _recording('May - first.txt')),
              _sequence('c1-s2', recording: _recording('May - second.txt')),
              _sequence('c1-s3',
                  error: 'this capture has no replay input stream'),
            ],
            'mixups': [
              {
                'lead_in': '2K',
                'files': [
                  {
                    ..._recording('May - mixup 1 of 2 (5H).txt'),
                    'follow_up': '5H',
                    'count': 1,
                    'sequence_id': 'c1-s1',
                  },
                  {
                    ..._recording('May - mixup 2 of 2 (jump back).txt'),
                    'follow_up': 'jump back',
                    'count': 1,
                    'sequence_id': 'c1-s2',
                  },
                ],
              },
            ],
          },
          {
            'id': 'c2',
            'title': 'blocked 5P',
            'flagged': false,
            'damage': 0,
            'hits': 0,
            'decided': 1,
            'count': 1,
            'flags': <Object?>[],
            'lead_ins': <Object?>[],
            'sequences': [
              _sequence('c2-s1', recording: _recording('May - 5P.txt')),
            ],
            'mixups': <Object?>[],
          },
        ],
      }),
    );

class _ListNotesRepository extends NotesRepository {
  _ListNotesRepository(this.entries) : super(finderDirectory: '/unused');

  final List<NotePreview> entries;

  @override
  Future<List<NotePreview>> list() async => entries;
}

class _FakeNotesRepository extends NotesRepository {
  _FakeNotesRepository(this.preview, this.data)
      : super(finderDirectory: '/unused');

  final NotePreview preview;
  final NoteSequenceData data;
  final List<List<LabRecording>> saved = <List<LabRecording>>[];
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<List<NotePreview>> list() async => [preview];

  @override
  Future<NoteSequenceData> read(NotePreview preview) async => data;

  @override
  Future<RecordingSaveResult> saveRecordings(
    SequenceDocument document,
    List<LabRecording> recordings,
  ) async {
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    saved.add(recordings);
    return RecordingSaveResult(
      batchDirectory: '${document.batchFolder}/recordings',
      strivelabsDirectory: document.strivelabsRecordings,
      fileNames: [for (final recording in recordings) recording.fileName],
    );
  }
}

const _playerClip = NoteClip(
  file: 's1-1.mp4',
  poster: null,
  replay: 1,
  videoTime: '00:54',
  videoTimeMs: 54989,
  startMs: 53489,
  endMs: 57100,
  herNext: null,
  answer: 'Ky 5P',
  outcome: 'hit',
  counterHit: true,
);

class _FakeClipSession implements NotesClipPlayerSession {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final List<int> steps = <int>[];
  final List<Duration> seeks = <Duration>[];
  bool created = false;
  int playCalls = 0;
  int disposeCalls = 0;
  int pauseCalls = 0;
  int rateCalls = 0;
  double? lastRate;
  int loopCalls = 0;
  bool? lastLoop;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  void emitPosition(Duration value) => _position.add(value);

  void emitDuration(Duration value) => _duration.add(value);

  @override
  Future<void> play() async {
    created = true;
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> stepFrame(int direction) async => steps.add(direction);

  /// When set, startup waits here, so a test can finish another card first.
  Completer<void>? gate;

  @override
  Future<void> setRate(double rate) async {
    rateCalls++;
    lastRate = rate;
    await gate?.future;
  }

  @override
  Future<void> setLoop(bool loop) async {
    loopCalls++;
    lastLoop = loop;
  }

  @override
  Future<Duration> currentPosition() async => Duration.zero;

  static const videoKey = ValueKey('fake-clip-video');

  @override
  Widget buildVideo(BuildContext context) =>
      const ColoredBox(key: videoKey, color: Colors.black);

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _position.close();
    await _duration.close();
    await _playing.close();
  }
}

class _TwoClipHarness extends StatefulWidget {
  const _TwoClipHarness({
    required this.clip,
    required this.playerFactory,
    this.filePaths = const ['/tmp/a.mp4', '/tmp/b.mp4'],
  });

  final NoteClip clip;
  final NotesClipPlayerSessionFactory playerFactory;
  final List<String> filePaths;

  @override
  State<_TwoClipHarness> createState() => _TwoClipHarnessState();
}

class _TwoClipHarnessState extends State<_TwoClipHarness> {
  int? _playing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('two-clip-harness'),
      child: Column(
        children: [
          NotesClipPlayer(
            key: const ValueKey('clip-a'),
            playerCardKey: const ValueKey('clip-player-a'),
            clip: widget.clip,
            filePath: widget.filePaths[0],
            playerFactory: widget.playerFactory,
            pauseRequested: _playing == 1,
            onStarted: () => setState(() => _playing = 0),
          ),
          NotesClipPlayer(
            key: const ValueKey('clip-b'),
            playerCardKey: const ValueKey('clip-player-b'),
            clip: widget.clip,
            filePath: widget.filePaths[1],
            playerFactory: widget.playerFactory,
            pauseRequested: _playing == 0,
            onStarted: () => setState(() => _playing = 1),
          ),
        ],
      ),
    );
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the requested widget.');
}

/// Lets real file IO finish until [done] holds (bounded), pumping between tries.
Future<void> _settleIo(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 200 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

Future<void> _flushIo(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

Directory _createTempDirectory(String prefix) {
  final directory = Directory(
    '${Directory.systemTemp.path}/$prefix-${DateTime.now().microsecondsSinceEpoch}',
  );
  directory.createSync(recursive: true);
  return directory;
}

void _deleteTempEntity(FileSystemEntity entity) {
  if (entity.existsSync()) entity.deleteSync(recursive: true);
}

Map<String, Object?> _sequenceV033(
  String id, {
  required int frames,
  required String line,
  required String result,
}) =>
    {
      ..._sequence(id,
          recording: {..._recording('May - $id.txt'), 'frames': frames}),
      'video_time': '04:17.2',
      'line': line,
      'answer': 'Ky crouch-blocked',
      'result': result,
    };

NoteSequenceData _dataV033(NotePreview preview) => NoteSequenceData(
      preview: preview,
      document: SequenceDocument.fromJson({
        'schema': 1,
        'opponent': 'May',
        'player': 'Ky',
        'batch_label': 'batch-a',
        'batch_folder': '/videos/batch-a',
        'created_at': '2026-11-09T23:00:00+07:00',
        'strivelabs_recordings': '/game/ue4ss/recordings',
        'warnings': <String>[],
        'clip_errors': <String>[],
        'cards': [
          {
            'id': 'c1',
            'kind': 'situation',
            'title': "Ky blocked May's j.H",
            'flagged': true,
            'damage': 78,
            'hits': 1,
            'decided': 3,
            'count': 5,
            'header': '5 times · May hit Ky 1 time · 78 damage',
            'lead_in_text':
                'What May did before j.H: S Mr. Dolphin Horizontal x2, nothing x2, 2S x1',
            'flags': <Object?>[],
            'lead_ins': [
              {'move': 'S Mr. Dolphin Horizontal', 'count': 2},
            ],
            'sequences': [
              _sequenceV033('c1-s1',
                  frames: 95,
                  line: 'S Mr. Dolphin Horizontal > j.H > Ground Throw',
                  result: 'Ky crouch-blocked · May hit Ky (78 damage)'),
              _sequenceV033('c1-s2',
                  frames: 798,
                  line: 'S Mr. Dolphin Horizontal > j.H > f.S',
                  result: 'Ky crouch-blocked · May kept pressure'),
            ],
            'mixups': [
              {
                'lead_in': 'S Mr. Dolphin Horizontal',
                'label': "May's mixup after S Mr. Dolphin Horizontal > j.H:",
                'files': [
                  {
                    ..._recording('May - mixup 1 of 2 (Ground Throw).txt'),
                    'follow_up': 'Ground Throw',
                    'count': 1,
                  },
                  {
                    ..._recording('May - mixup 2 of 2 (f.S).txt'),
                    'follow_up': 'f.S',
                    'count': 1,
                  },
                ],
              },
            ],
          },
          {
            'id': 'c2',
            'kind': 'guard_crush',
            'title': "May's 6H guard-crushed Ky",
            'flagged': false,
            'damage': 59,
            'hits': 1,
            'decided': 0,
            'count': 1,
            'header': '1 time · 59 damage',
            'lead_in_text': 'What May did before 6H: j.H x1',
            'flags': <Object?>[],
            'lead_ins': [
              {'move': 'j.H', 'count': 1},
            ],
            'sequences': [
              {
                ..._sequenceV033('c2-s1',
                    frames: 74,
                    line: 'j.H > 6H',
                    result: 'May guard-crushed Ky (59 damage)'),
                'answer': '',
                'outcome': 'guard_crush',
              },
            ],
            'mixups': <Object?>[],
          },
        ],
      }),
    );
