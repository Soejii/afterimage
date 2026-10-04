import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/services/notes_repository.dart';

void main() {
  group('notes cards', () {
    test('split and join keep the preamble and card order', () {
      const source = '# I-No notes\n\nintro\n\n'
          '### blocked [[I-No 2S]]\n'
          'lab: late 6P\n\n'
          '### staggered [[I-No S Stroke the Big Tree]]\n'
          'seen: 00:17\n';

      final document = splitNoteSection(source);

      expect(document.preamble, '# I-No notes\n\nintro');
      expect(document.cards, hasLength(2));
      expect(document.toMarkdown(), source);
      expect(
        document.removeCard(0).toMarkdown(),
        '# I-No notes\n\nintro\n\n'
        '### staggered [[I-No S Stroke the Big Tree]]\n'
        'seen: 00:17\n',
      );
      expect(
        document
            .replaceCard(0, const NoteCard('### edited\nnew body'))
            .toMarkdown(),
        '# I-No notes\n\nintro\n\n### edited\nnew body\n\n'
        '### staggered [[I-No S Stroke the Big Tree]]\n'
        'seen: 00:17\n',
      );
    });
  });

  group('clip matching', () {
    final hit = NoteClip.fromJson({
      'file': 'hit.mp4',
      'video_time': '00:54',
      'answer': 'Ky 6P',
      'outcome': 'hit',
      'counter_hit': true,
    });
    final trade = NoteClip.fromJson({
      'file': 'trade.mp4',
      'video_time': '01:01',
      'answer': 'Ky 5P',
      'outcome': 'trade',
    });
    final index = ClipIndex(
      video: '/tmp/replays.mp4',
      situations: [
        ClipSituation(
          heading: '### exact [[I-No 2S]]',
          entry: 'block',
          posture: 'ground',
          herMoveLink: 'I-No 2S',
          clips: [trade, hit],
        ),
        ClipSituation(
          heading: null,
          entry: 'block',
          posture: 'ground',
          herMoveLink: 'I-No 5H',
          clips: [hit],
        ),
        ClipSituation(
          heading: null,
          entry: 'stagger',
          posture: 'ground',
          herMoveLink: 'I-No S Stroke the Big Tree',
          clips: [trade],
        ),
      ],
      errors: const [],
    );

    test('exact heading wins and hits come first', () {
      final clips = matchClipsForCard(
        const NoteCard('### exact [[I-No 2S]]\nbody'),
        index,
      );
      expect(clips.map((clip) => clip.file), ['hit.mp4', 'trade.mp4']);
      expect(clips.first.caption(), '00:54 · Ky 6P · hit (CH)');
    });

    test('rule fallback distinguishes stagger from block', () {
      expect(
        matchClipsForCard(
          const NoteCard('### blocked [[I-No 5H]]'),
          index,
        ).single.file,
        'hit.mp4',
      );
      expect(
        matchClipsForCard(
          const NoteCard('### staggered [[I-No S Stroke the Big Tree]]'),
          index,
        ).single.file,
        'trade.mp4',
      );
    });

    test('cards without a matching situation have no clips', () {
      expect(
        matchClipsForCard(const NoteCard('### blocked [[I-No Sweep]]'), index),
        isEmpty,
      );
    });
  });

  group('situation tables', () {
    const body = 'she is -13 at range\n'
        '\n'
        '| her option | times | beats | loses to | you did |\n'
        '| --- | --- | --- | --- | --- |\n'
        '| [[Elphelt 2H]] | 2 | backdash | dash, [[Ky 2P]] | backdash hit x2 |\n'
        '| no attack | 1 | untested | untested | dash won |\n'
        '\n'
        'habit: backdash 2 of 2 hit\n'
        'lab: record MC > 2H\n'
        'seen: batch_x 01:34, 03:39';

    test('a card body splits into lines and one table with row options', () {
      final blocks = parseNoteBody(body);

      expect(blocks, hasLength(7));
      expect((blocks[0] as NoteTextLine).text, 'she is -13 at range');
      final table = blocks[2] as NoteTable;
      expect(table.header,
          ['her option', 'times', 'beats', 'loses to', 'you did']);
      expect(table.rows.map((row) => row.option), ['Elphelt 2H', 'no attack']);
      expect(table.rows.first.cells[3], 'dash, [[Ky 2P]]');
      expect((blocks[4] as NoteTextLine).label, 'habit');
      expect((blocks[4] as NoteTextLine).rest, 'backdash 2 of 2 hit');
      expect((blocks[5] as NoteTextLine).label, 'lab');
    });

    test('a wikilink alias pipe inside a cell does not split the cell', () {
      final table = parseNoteBody(
        '| her option | times |\n'
        '| --- | --- |\n'
        '| [[Elphelt 2H|2H]] | 2 |',
      ).single as NoteTable;

      expect(table.rows.single.cells, ['[[Elphelt 2H|2H]]', '2']);
      expect(table.rows.single.option, 'Elphelt 2H');
    });

    test('rows take the clips cut for their option', () {
      NoteClip clip(String file, String? option, String? herNext) =>
          NoteClip.fromJson({
            'file': file,
            'option': option,
            'her_next': herNext,
            'outcome': 'hit',
          });
      final clips = [
        clip('a.mp4', 'Elphelt 2H', 'Elphelt 2H'),
        clip('b.mp4', 'no attack', null),
        clip('c.mp4', null, 'Elphelt 2H'),
        clip('d.mp4', null, null),
      ];

      expect(clipsForOption(clips, 'Elphelt 2H').map((c) => c.file),
          ['a.mp4', 'c.mp4']);
      expect(clipsForOption(clips, 'no attack').map((c) => c.file),
          ['b.mp4', 'd.mp4']);
    });

    test('a situation keeps every clip, not only four', () {
      final clips = [
        for (var index = 0; index < 9; index++)
          NoteClip.fromJson({'file': '$index.mp4', 'outcome': 'hit'}),
      ];
      final index = ClipIndex(
        video: null,
        situations: [
          ClipSituation(
            heading: '### blocked [[Elphelt 2H]]',
            entry: 'block',
            posture: 'ground',
            herMoveLink: 'Elphelt 2H',
            clips: clips,
          ),
        ],
        errors: const [],
      );

      expect(
        matchClipsForCard(const NoteCard('### blocked [[Elphelt 2H]]'), index),
        hasLength(9),
      );
    });
  });

  group('finder status and apply mapping', () {
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

    test('apply exit codes preserve the contract messages', () {
      expect(
        ApplySectionResult.fromExitCode(0, opponent: 'I-No').message,
        'Applied to the I-No note.',
      );
      expect(
        ApplySectionResult.fromExitCode(2, opponent: 'I-No').state,
        ApplySectionState.changed,
      );
      expect(
        ApplySectionResult.fromExitCode(3,
                opponent: 'I-No', stderr: 'bad draft')
            .message,
        'bad draft',
      );
      expect(
        ApplySectionResult.fromExitCode(1, opponent: 'I-No', stderr: 'io')
            .state,
        ApplySectionState.failed,
      );
    });
  });

  group('notes repository', () {
    late Directory root;
    late NotePreview preview;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('afterimage-notes-');
      final directory = Directory('${root.path}/out/batch-new/I-No');
      await directory.create(recursive: true);
      await File('${directory.path}/section.md').writeAsString(
        'preamble\n\n### blocked [[I-No 2S]]\nlab: test\n',
      );
      await File('${directory.path}/meta.json').writeAsString(jsonEncode({
        'schema': 1,
        'opponent': 'I-No',
        'player': 'Ky',
        'batch_label': 'batch-new',
        'created_at': '2026-10-03T10:18:00+07:00',
        'status': 'draft',
      }));
      preview = const NotePreview(
        batchLabel: 'batch-new',
        opponent: 'I-No',
        directoryPath: '',
        sectionPath: '',
        metadata: null,
        cardCount: 0,
        modifiedAt: null,
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('write is atomic and creates the original only once', () async {
      final repository = NotesRepository(finderDirectory: root.path);
      final listed = await repository.list();
      preview = listed.single;
      final original = File('${preview.directoryPath}/section.orig.md');
      final legacyOriginal = File('${preview.sectionPath}.orig.md');
      final first = await repository.read(preview);

      await repository.write(
        preview,
        first.document.replaceCard(0, const NoteCard('### edited\nnew text')),
      );
      final savedOriginal = await original.readAsString();
      await repository.write(
        preview,
        (await repository.read(preview)).document.replaceCard(
              0,
              const NoteCard('### edited again'),
            ),
      );

      expect(savedOriginal, contains('### blocked [[I-No 2S]]'));
      expect(await original.readAsString(), savedOriginal);
      expect(await legacyOriginal.exists(), isFalse);
      expect(await File(preview.sectionPath).readAsString(),
          'preamble\n\n### edited again\n');
    });

    test('legacy previews are listed after metadata-backed previews', () async {
      final legacy = Directory('${root.path}/out/batch-old/Ky');
      await legacy.create(recursive: true);
      await File('${legacy.path}/section.md').writeAsString('### old\n');
      final repository = NotesRepository(finderDirectory: root.path);
      final listed = await repository.list();

      expect(listed, hasLength(2));
      expect(listed.first.isLegacy, isFalse);
      expect(listed.last.isLegacy, isTrue);
    });
  });
}
