import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/services/notes_repository.dart';

import 'support/ledger_test_data.dart';

void main() {
  test('trend parses sets, independent comparisons and verbatim card text', () {
    final document = SequenceDocument.fromJson(trendDocument());
    final trend = document.trend!;
    expect(trend.sets.first.batchLabel, 'batch-0');
    expect(trend.sets.first.date, '2026-10-01');
    expect(trend.sets.first.replays, 5);
    expect(trend.sets.first.hpReplays, 0);
    expect(trend.sets.first.damagePerReplay, isNull);
    expect(trend.sets.first.current, isFalse);
    expect(trend.sets.last.current, isTrue);
    expect(trend.sets.last.damagePerReplay, 872.4);
    expect(trend.ledger!.previous.date, '2026-10-20');
    expect(trend.ledger!.previous.replays, 6);
    expect(trend.ledger!.total.now, 872.4);
    expect(trend.ledger!.total.before, 910.0);
    expect(trend.ledger!.total.delta, -37.6);
    expect(trend.ledger!.categories.first.key, 'pressing');
    expect(trend.ledger!.categories.first.label, 'Hit while pressing a button');
    expect(trend.ledger!.categories.first.delta, -21.7);
    expect(trend.cards!.previous.batchLabel, 'earlier');
    expect(trend.cards!.gone.single.kind, 'situation');
    expect(trend.cards!.gone.single.title, "Ky blocked I-No's 5H");
    expect(document.cards.first.trendText,
        'Earlier set: ${document.cards.first.id}. Now seen again.');
  });

  test('trend tolerates missing, null and malformed additive data', () {
    expect(SequenceDocument.fromJson(ledgerDocument()).trend, isNull);
    for (final raw in [
      null,
      true,
      3,
      'bad',
      [],
      {},
      {'sets': false},
      {
        'sets': [false, {}]
      }
    ]) {
      expect(
          SequenceDocument.fromJson({...ledgerDocument(), 'trend': raw}).trend,
          isNull);
    }
    final json = trendDocument();
    final raw = json['trend'] as Map;
    (raw['sets'] as List).addAll([
      null,
      false,
      {},
      {'replays': '5'}
    ]);
    ((raw['ledger'] as Map)['categories'] as List).addAll([
      null,
      {},
      {'key': 'bad', 'label': 'bad', 'now': double.nan, 'before': 1, 'delta': 1}
    ]);
    ((raw['cards'] as Map)['gone'] as List).addAll([
      null,
      {},
      {'title': false}
    ]);
    raw['unknown'] = true;
    var trend = SequenceDocument.fromJson(json).trend!;
    expect(trend.sets, hasLength(2));
    expect(trend.ledger!.categories, hasLength(3));
    expect(trend.cards!.gone, hasLength(1));
    for (final invalid in [
      null,
      false,
      {},
      {'text': 1},
      {'previous': {}}
    ]) {
      raw['ledger'] = invalid;
      raw['cards'] = invalid;
      trend = SequenceDocument.fromJson(json).trend!;
      expect(trend.ledger, isNull);
      expect(trend.cards, isNull);
    }
    for (final value in [null, false, 3, [], {}, '  Finder text  ']) {
      expect(SequenceCard.fromJson({'trend_text': value}).trendText,
          value is String ? value : isNull);
    }
    expect(SequenceCard.fromJson({}).trendText, isNull);
  });

  test('event kinds and tolerant ledger card ids stay additive in schema 1',
      () {
    final document = SequenceDocument.fromJson(eventDocument());
    expect(document.cards.where((card) => card.isEventCard), hasLength(5));
    expect(document.cards.first.kind, 'future_kind');
    expect(
        document.ledger!.categories.first.cards, ['missing', 'e1', 'c2', 'c5']);
    for (final raw in [null, false, 3, 'c1', <Object?>[]]) {
      expect(LedgerCategory.fromJson({'cards': raw}).cards, isEmpty);
    }
    expect(
        LedgerCategory.fromJson({
          'cards': [false, 'e1', null, 2]
        }).cards,
        ['e1']);
    expect(
        SequenceDocument.fromJson(ledgerDocument())
            .cards
            .any((card) => card.isEventCard),
        isFalse);
    expect(
        SequenceDocument.fromJson(ledgerDocument())
            .ledger!
            .categories
            .first
            .cards,
        isEmpty);
  });

  test('ledger, focus, answers and reversal note parse without changing schema',
      () {
    final document = SequenceDocument.fromJson(ledgerDocument());
    expect(document.focus, ['c3', 'unknown', 'c1']);
    final ledger = document.ledger!;
    expect([ledger.totalDamage, ledger.replays, ledger.coveredByCards],
        [10469, 12, 2506]);
    final category = ledger.categories.first;
    expect([
      category.key,
      category.label,
      category.damage,
      category.events,
      category.share
    ], [
      'neutral',
      'Hit in neutral',
      3100,
      41,
      0.296
    ]);
    final starter = category.starters.single;
    expect([starter.move, starter.damage, starter.events, starter.counterHits],
        ['j.S', 900, 9, 2]);
    expect(starter.examples.first.videoTime, 512.4);
    expect(starter.examples.last.videoTime, isNull);
    expect([
      starter.examples.first.replay,
      starter.examples.first.round,
      starter.examples.first.damage
    ], [
      3,
      2,
      141
    ]);
    expect(ledger.categories.last.hisMoves.first.move, 'f.S');
    expect(ledger.categories.last.hisMoves.first.events, 4);
    expect(ledger.categories.last.hisMoves.first.damage, 300);
    final answer = document.cards.first.answers.first;
    expect([
      answer.text,
      answer.count,
      answer.gotHit,
      answer.won,
      answer.pressure,
      answer.neutral,
      answer.damage
    ], [
      'Ky blocked',
      9,
      3,
      0,
      5,
      1,
      240
    ]);
    expect(document.cards.first.reversalNote, contains('S Vapor Thrust'));
  });

  test('new optional keys tolerate absence, null, empty and wrong types', () {
    for (final value in [null, false, 3, 'wrong', <Object?>[]]) {
      final document = SequenceDocument.fromJson({
        'schema': 1,
        'focus': value,
        'ledger': value,
        'cards': [
          {'answers': value, 'reversal_note': value}
        ],
      });
      expect(document.focus, isEmpty);
      expect(document.ledger, isNull);
      expect(document.cards.single.answers, isEmpty);
      expect(
          document.cards.single.reversalNote, value is String ? value : isNull);
    }
    final old = SequenceDocument.fromJson(_document());
    expect(old.focus, isEmpty);
    expect(old.ledger, isNull);
    expect(old.cards.single.answers, isEmpty);
    expect(old.cards.single.reversalNote, isNull);
    final malformed = SequenceDocument.fromJson({
      'schema': 1,
      'focus': [false, 'c1', null],
      'ledger': {
        'total_damage': [],
        'replays': false,
        'covered_by_cards': {},
        'categories': [
          null,
          1,
          {
            'damage': 'bad',
            'events': [],
            'share': false,
            'key': 1,
            'label': [],
            'his_moves': [
              false,
              {'move': 3, 'events': {}}
            ],
            'starters': [
              true,
              {
                'counter_hits': [],
                'examples': [
                  4,
                  {'video_time': 'wrong'}
                ]
              }
            ]
          }
        ]
      },
      'cards': [
        {
          'answers': [
            null,
            {'text': 2, 'count': [], 'won': false}
          ],
          'reversal_note': 1
        }
      ],
    });
    expect(malformed.focus, ['c1']);
    expect(malformed.ledger!.totalDamage, 0);
    final category = malformed.ledger!.categories.single;
    expect(category.damage, 0);
    expect(category.share, 0);
    expect(category.key, '');
    expect(category.starters.single.examples.single.videoTime, isNull);
    expect(category.hisMoves.single.move, '');
    expect(malformed.cards.single.answers.single.text, '');
    expect(malformed.cards.single.answers.single.count, 0);
    expect(malformed.cards.single.reversalNote, isNull);
  });

  test(
    'Step 12 parses the supplied H Stroke card and sequence reads',
    () {
      final source = File('test/support/step12/ino_h_stroke.json');
      final document = SequenceDocument.fromJson(
        decodeObject(source.readAsStringSync()),
      );
      final card = document.cards.singleWhere(
        (candidate) =>
            candidate.title == "Ky blocked I-No's H Stroke the Big Tree",
      );
      final read = card.read!;

      expect(read.kind, "player's turn");
      expect(read.adv, 2);
      expect(read.matrix!.rows, isNotEmpty);
      expect(read.mistakes['guess']!.count, 5);
      expect(read.mistakes['unclear']!.count, 1);
      expect(
        card.sequences.any((sequence) =>
            sequence.read?.mistake != null &&
            (sequence.read?.reason?.isNotEmpty ?? false)),
        isTrue,
      );
    },
  );

  test('Step 12 keeps additive fields and unknown spot kinds readable', () {
    final card = SequenceCard.fromJson({
      'id': 'future',
      'read': {
        'kind': 'future spot',
        'adv': 0,
        'scope': 'even',
        'corner': 'near corner',
        'throw_range': {'min': 2, 'max': 4},
        'fuzzy_candidates': ['low then high'],
        'matrix': {
          'player_options': [
            {
              'id': 'Ky 5P',
              'label': '5P',
              'active_frames': [5, 6],
              'guards': ['low', 'high'],
            },
          ],
        },
        'new_finder_field': {'label': 'retain me'},
      },
      'sequences': [
        {
          'id': 'future-s1',
          'read': {
            'kind': 'future point kind',
            'mistake': 'future mistake kind',
            'reason': 'keep the explanation',
            'corner': 'near corner',
            'throw_range_bracket': [2, 4],
            'unknown_point_field': 'still visible',
          },
        },
      ],
    });
    final read = card.read!;
    final sequenceRead = card.sequences.single.read!;

    expect(read.kind, 'future spot');
    expect(read.matrix!.playerOptions.single.activeFrames, [5, 6]);
    expect(read.additionalDetails.join('\n'), contains('corner: near corner'));
    expect(read.additionalDetails.join('\n'), contains('throw_range'));
    expect(read.additionalDetails.join('\n'), contains('fuzzy_candidates'));
    expect(read.additionalDetails.join('\n'), contains('active_frames'));
    expect(read.additionalDetails.join('\n'), contains('guards'));
    expect(read.additionalDetails.join('\n'), contains('new_finder_field'));
    expect(sequenceRead.kind, 'future point kind');
    expect(sequenceRead.mistake, 'future mistake kind');
    expect(sequenceRead.reason, 'keep the explanation');
    expect(sequenceRead.additionalDetails.join('\n'), contains('corner'));
    expect(sequenceRead.additionalDetails.join('\n'), contains('throw_range'));
    expect(
      sequenceRead.additionalDetails.join('\n'),
      contains('unknown_point_field: still visible'),
    );
  });

  group('sequence list', () {
    test('parses cards, sequences, recordings, mixups and clips', () {
      final document = SequenceDocument.fromJson(_document());

      expect(document.opponent, 'May');
      expect(document.strivelabsRecordings, '/game/ue4ss/recordings');
      final card = document.cards.single;
      expect(card.title, 'blocked S Mr. Dolphin Vertical');
      expect(card.flags.single.reason, 'keeps losing: hit 5 of 8');
      expect(
          card.leadIns.map((leadIn) => leadIn.label), ['2K', 'string opener']);
      final sequence = card.sequences.first;
      expect(sequence.where, 'r3 · round 1 · 06:57.1');
      expect(sequence.summary,
          'after 2K · then 5H · you: block crouch · hit · -70');
      expect(sequence.recording?.frames, 129);
      expect(sequence.clip?.file, 'c1-s1.mp4');
      expect(card.sequences.last.recording, isNull);
      expect(card.sequences.last.recordingError, 'no stream');
      expect(card.mixups.single.label, 'after 2K');
      expect(card.mixups.single.files.map((file) => file.followUp),
          ['5H', 'jump back']);
    });

    test('an unknown schema is refused', () {
      expect(
        () => SequenceDocument.fromJson({..._document(), 'schema': 2}),
        throwsFormatException,
      );
    });

    test('only plain .txt names are safe to write', () {
      LabRecording named(String name) =>
          LabRecording(fileName: name, text: '', frames: 5);

      expect(named('May - 2K then 5H r3 06m57.1s.txt').hasSafeFileName, isTrue);
      for (final name in [
        '../escape.txt',
        'sub/dir.txt',
        r'sub\dir.txt',
        '.hidden.txt',
        'not-text.sh',
        '',
      ]) {
        expect(named(name).hasSafeFileName, isFalse, reason: name);
      }
    });
  });

  group('finder status', () {
    test('running with a dead pid is failed, while other statuses parse', () {
      for (final state in [
        FinderRunState.done,
        FinderRunState.nothing,
        FinderRunState.failed,
      ]) {
        final info = FinderRunInfo.fromJson({
          'status': state.name,
          'pid': 99,
        }, isPidAlive: (_) => true);
        expect(info.state, state);
      }
      final dead = FinderRunInfo.fromJson({
        'status': 'running',
        'pid': 99,
      }, isPidAlive: (_) => false);
      expect(dead.state, FinderRunState.failed);
      expect(dead.message, contains('stopped'));
      final missingPid = FinderRunInfo.fromJson(
        {'status': 'running'},
        isPidAlive: (_) => true,
      );
      expect(missingPid.state, FinderRunState.failed);
      expect(missingPid.message, contains('stopped'));
    });
  });

  group('notes repository', () {
    late Directory root;
    late Directory batch;
    late Directory game;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('afterimage-sequences-');
      batch = await Directory('${root.path}/videos/batch-new')
          .create(recursive: true);
      game = await Directory('${root.path}/game/ue4ss').create(recursive: true);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> writeDocument(
      String batchLabel,
      String opponent,
      Map<String, Object?> json,
    ) async {
      final directory =
          Directory('${root.path}/finder/out/$batchLabel/$opponent');
      await directory.create(recursive: true);
      await File('${directory.path}/sequences.json')
          .writeAsString(jsonEncode(json));
    }

    test('lists sequence lists newest first and skips broken ones', () async {
      await writeDocument('batch-old', 'May', {
        ..._document(),
        'created_at': '2026-11-01T10:00:00+07:00',
      });
      await writeDocument('batch-new', 'May', _document());
      await writeDocument('batch-bad', 'Sol', {'schema': 99});
      final legacy = Directory('${root.path}/finder/out/batch-old/I-No');
      await legacy.create(recursive: true);
      await File('${legacy.path}/section.md').writeAsString('### old\n');

      final repository =
          NotesRepository(finderDirectory: '${root.path}/finder');
      final listed = await repository.list();

      expect(listed.map((preview) => preview.batchLabel),
          ['batch-new', 'batch-old']);
      expect(listed.first.cardCount, 1);
      expect(listed.first.flaggedCount, 1);
      final data = await repository.read(listed.first);
      expect(data.document.cards.single.sequences, hasLength(2));
    });

    test('Save writes to the batch folder and StriveLabs', () async {
      final document = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': batch.path,
        'strivelabs_recordings': '${game.path}/recordings',
      });
      final repository = NotesRepository(finderDirectory: root.path);
      final recording = document.cards.single.sequences.first.recording!;

      final result = await repository.saveRecordings(document, [recording]);

      final inBatch = File('${batch.path}/recordings/${recording.fileName}');
      final inGame = File('${game.path}/recordings/${recording.fileName}');
      expect(await inBatch.readAsString(), recording.text);
      expect(await inGame.readAsString(), recording.text);
      expect(result.strivelabsDirectory, '${game.path}/recordings');
      expect(result.message, contains('StriveLabs recordings'));
      // Only the recording is left behind, no temporary files.
      expect(
        Directory('${game.path}/recordings').listSync().map(
              (entity) => entity.path.split(RegExp(r'[\\/]')).last,
            ),
        [recording.fileName],
      );
    });

    test('Save without StriveLabs writes the batch folder only', () async {
      final document = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': batch.path,
        'strivelabs_recordings': '${root.path}/uninstalled/ue4ss/recordings',
      });
      final repository = NotesRepository(finderDirectory: root.path);
      final files = [
        for (final file in document.cards.single.mixups.single.files)
          file.recording,
      ];

      final result = await repository.saveRecordings(document, files);

      expect(result.strivelabsDirectory, isNull);
      expect(result.message, contains('StriveLabs was not found'));
      expect(Directory('${batch.path}/recordings').listSync(), hasLength(2));
      expect(Directory('${root.path}/uninstalled').existsSync(), isFalse);
    });

    test('a StriveLabs failure still leaves the batch copy', () async {
      // A file where the recordings folder should be: creating it fails.
      await File('${game.path}/recordings').writeAsString('not a folder');
      final document = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': batch.path,
        'strivelabs_recordings': '${game.path}/recordings',
      });
      final repository = NotesRepository(finderDirectory: root.path);
      final recording = document.cards.single.sequences.first.recording!;

      final result = await repository.saveRecordings(document, [recording]);

      expect(
        await File('${batch.path}/recordings/${recording.fileName}')
            .readAsString(),
        recording.text,
      );
      expect(result.strivelabsDirectory, isNull);
      expect(result.strivelabsError, isNotNull);
      expect(result.message, contains('but not to StriveLabs'));
    });

    test("Save never writes into the finder's output folder", () async {
      final out = await Directory('${root.path}/finder/out/batch-new/May')
          .create(recursive: true);
      final link = Link('${root.path}/alias');
      await link.create('${root.path}/finder/out/batch-new');
      final repository =
          NotesRepository(finderDirectory: '${root.path}/finder');
      final aimedAtOut = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': batch.path,
        'strivelabs_recordings': '${link.path}/May/recordings',
      });
      final recording = aimedAtOut.cards.single.sequences.first.recording!;

      final result = await repository.saveRecordings(aimedAtOut, [recording]);

      expect(result.strivelabsDirectory, isNull);
      expect(result.strivelabsError, contains("finder's output folder"));
      expect(Directory('${out.path}/recordings').existsSync(), isFalse);

      final batchInOut = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': out.path,
      });
      await expectLater(
        repository.saveRecordings(batchInOut, [recording]),
        throwsStateError,
      );
      expect(Directory('${out.path}/recordings').existsSync(), isFalse);
    });

    test('Save refuses unsafe names and a missing batch folder', () async {
      final repository = NotesRepository(finderDirectory: root.path);
      final document = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': batch.path,
      });

      await expectLater(
        repository.saveRecordings(document, const [
          LabRecording(fileName: '../escape.txt', text: 'x', frames: 5),
        ]),
        throwsFormatException,
      );
      expect(File('${batch.path}/escape.txt').existsSync(), isFalse);

      final gone = SequenceDocument.fromJson({
        ..._document(),
        'batch_folder': '${root.path}/deleted-batch',
      });
      await expectLater(
        repository.saveRecordings(
          gone,
          [gone.cards.single.sequences.first.recording!],
        ),
        throwsStateError,
      );
    });
  });
}

Map<String, Object?> _document() => {
      'schema': 1,
      'opponent': 'May',
      'player': 'Ky',
      'batch_label': 'batch-new',
      'batch_folder': '/videos/batch-new',
      'created_at': '2026-11-09T23:00:00+07:00',
      'strivelabs_recordings': '/game/ue4ss/recordings',
      'warnings': <String>[],
      'clip_errors': <String>[],
      'cards': [
        {
          'id': 'c1',
          'title': 'blocked S Mr. Dolphin Vertical',
          'move': 'S Mr. Dolphin Vertical',
          'posture': 'ground',
          'entry': 'block',
          'flagged': true,
          'damage': 211,
          'hits': 5,
          'decided': 8,
          'count': 2,
          'flags': [
            {
              'kind': 'keeps_losing',
              'reason': 'keeps losing: hit 5 of 8',
              'player': null,
              'count': 8,
            },
          ],
          'lead_ins': [
            {'move': '2K', 'count': 1},
            {'move': null, 'count': 1},
          ],
          'sequences': [
            {
              'id': 'c1-s1',
              'replay': 3,
              'round': 1,
              'video_time': '06:57.1',
              'video_time_ms': 417100,
              'lead_in': '2K',
              'follow_up': '5H',
              'answer': 'block crouch',
              'outcome': 'hit',
              'counter_hit': false,
              'damage': 70,
              'flags': ['keeps_losing'],
              'recording': {
                'file_name': 'May - 2K then S Mr. Dolphin Vertical then 5H.txt',
                'text': '# header\n[1]+[K] W8\n',
                'frames': 129,
              },
              'recording_error': null,
              'clip': {
                'file': 'c1-s1.mp4',
                'poster': 'c1-s1.jpg',
                'video_time': '06:57.1',
                'outcome': 'hit',
              },
            },
            {
              'id': 'c1-s2',
              'replay': 1,
              'round': 2,
              'video_time': '01:02.0',
              'video_time_ms': 62000,
              'lead_in': null,
              'follow_up': 'jump back',
              'answer': 'block',
              'outcome': 'reset',
              'counter_hit': false,
              'damage': 0,
              'flags': <String>[],
              'recording': null,
              'recording_error': 'no stream',
              'clip': null,
            },
          ],
          'mixups': [
            {
              'lead_in': '2K',
              'files': [
                {
                  'file_name': 'May - mixup 1 of 2 (5H).txt',
                  'text': '# one\nW10\n',
                  'frames': 10,
                  'follow_up': '5H',
                  'count': 1,
                  'sequence_id': 'c1-s1',
                },
                {
                  'file_name': 'May - mixup 2 of 2 (jump back).txt',
                  'text': '# two\nW12\n',
                  'frames': 12,
                  'follow_up': 'jump back',
                  'count': 1,
                  'sequence_id': 'c1-s2',
                },
              ],
            },
          ],
        },
      ],
    };
