import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/presentation/widgets/options_table.dart';
import 'package:afterimage/presentation/widgets/reference_views.dart';
import 'package:afterimage/presentation/widgets/sequence_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hit gap requires both samples and includes the twenty point boundary',
      () {
    expect(hitGap(1, 5, 0, 5), isTrue);
    expect(hitGap(1, 5, 0, 6), isTrue);
    expect(hitGap(1, 6, 0, 5), isFalse);
    expect(hitGap(1, 4, 0, 5), isFalse);
    expect(hitGap(1, 5, 0, 4), isFalse);
    expect(hitGap(1, 5, null, 5), isFalse);
    expect(hitGap(1, 5, 0, null), isFalse);
  });

  test('button phases are read from the finder header in phase order', () {
    expect(buttonPhases('5 times · 490 damage · 2 in startup, 3 in recovery'),
        [('startup', 2), ('recovery', 3)]);
    expect(
        buttonPhases('9 times · 638 damage · 2 in recovery, 1 while active, '
            '6 in startup'),
        [('startup', 6), ('active', 1), ('recovery', 2)]);
    expect(buttonPhases('6 times · 678 damage · 6 in recovery'),
        [('recovery', 6)]);
    expect(buttonPhases('13 times · 844 damage'), isNull);
    expect(buttonPhases(null), isNull);
  });

  testWidgets('gap requires five picks and includes exactly twenty points',
      (tester) async {
    final reference = DocumentReference.fromJson({
      'after_block': {
        'own': {
          'answers': [
            {'text': 'boundary', 'count': 5, 'got_hit': 1},
            {'text': 'too small', 'count': 4, 'got_hit': 4},
            {'text': 'unseen', 'count': 0, 'got_hit': 0},
          ]
        },
        'reference': {
          'answers': [
            {'text': 'boundary', 'count': 5, 'got_hit': 0},
            {'text': 'too small', 'count': 5, 'got_hit': 0},
            {'text': 'unseen', 'count': 5, 'got_hit': 0},
          ]
        },
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReferencePanel(
                player: 'Ky', reference: reference, ledger: null))));
    expect(
        find.byKey(const ValueKey('reference-gap-boundary')), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-gap-too small')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('reference-answer-unseen')),
            matching: find.text('n/a')),
        findsOneWidget);
  });

  testWidgets('spot comparison includes own and reference-only picks',
      (tester) async {
    final spot = SituationSpot.fromJson({
      'kind': 'turn',
      'count': 14,
      'player_rows': [
        {'name': 'walk forward', 'seen': true, 'count': 5},
        {'name': '6P', 'seen': false, 'count': 0},
      ],
    });
    final reference = CardReference.fromJson({
      'spots': [
        {
          'kind': 'turn',
          'count': 4,
          'player_rows': [
            {'name': 'walk forward', 'count': 1},
            {'name': 'f.S', 'count': 1}
          ]
        }
      ]
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OptionsTable(
                player: 'Ky',
                opponent: 'Elphelt',
                moves: const {},
                spot: spot,
                reference: reference,
                recommended: const {'6P'}))));
    expect(
        find.byKey(const ValueKey('reference-small-sample')), findsOneWidget);
    final walk = find.byKey(const ValueKey('reference-pick-walk forward'));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-row-walk forward')),
            matching: find.text('5 of 14')),
        findsOneWidget);
    expect(find.descendant(of: walk, matching: find.text('1 of 4')),
        findsOneWidget);
    final fs = find.byKey(const ValueKey('reference-pick-f.S'));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-row-f.S')),
            matching: find.text('not tried')),
        findsOneWidget);
    expect(
        find.descendant(of: fs, matching: find.text('1 of 4')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('option-row-6P')),
            matching: find.text('not tried')),
        findsOneWidget);
  });

  for (final width in [700.0, 1400.0]) {
    testWidgets('after-block reference panel fits at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reference = DocumentReference.fromJson({
        'replays': 15,
        'after_block': {
          'own': {
            'count': 220,
            'hits': 57,
            'answers': [
              {'text': 'block', 'count': 10, 'got_hit': 2}
            ]
          },
          'reference': {
            'count': 169,
            'hits': 40,
            'answers': [
              {'text': 'block', 'count': 8, 'got_hit': 1}
            ]
          },
        },
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReferencePanel(
                  player: 'Ky', reference: reference, ledger: null))));
      expect(find.text('You: 26% hit  ·  57 of 220'), findsOneWidget);
      expect(find.text('High-level Ky: 24% hit  ·  40 of 169'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('reference-answer-block')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
