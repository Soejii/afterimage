import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/theme.dart';
import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/presentation/notes_pages.dart';
import 'package:afterimage/presentation/widgets/notes_clip_player.dart';
import 'package:afterimage/services/notes_repository.dart';

void main() {
  late NotePreview preview;
  late NoteSectionData data;

  setUp(() {
    preview = _preview(
      batchLabel: 'batch-new',
      opponent: 'I-No',
      sectionPath: '/out/batch-new/I-No/section.md',
    );
    data = NoteSectionData(
      preview: preview,
      document: const NoteSectionDocument(
        preamble: '',
        cards: [NoteCard('### blocked [[I-No 2S]]\nlab: late 6P')],
      ),
      warnings: const <String>[],
      clipIndex: null,
    );
  });

  testWidgets('page shows cards and apply, delete then undo restores the card',
      (tester) async {
    final repository = _FakeNotesRepository(preview, data);
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: preview, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    expect(find.byKey(const ValueKey('apply-notes')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-note-0')));
    await _pumpUntilFound(
      tester,
      find.text('There are no situations left in this draft.'),
    );
    expect(find.text('Undo'), findsOneWidget);

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));
  });

  testWidgets('apply confirms, maps success, and replaces the button',
      (tester) async {
    final repository = _FakeNotesRepository(preview, data);
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: preview, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    await tester.tap(find.byKey(const ValueKey('apply-notes')));
    await _pumpUntilFound(tester, find.text('Apply notes?'));
    await tester.tap(find.text('Apply').last);
    await _pumpUntilFound(tester, find.text('Applied to the I-No note.'));

    expect(find.byKey(const ValueKey('notes-applied')), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-notes')), findsNothing);
  });

  testWidgets('apply is disabled while editing and does not run',
      (tester) async {
    final repository = _FakeNotesRepository(preview, data);
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: preview, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    await tester.tap(find.byKey(const ValueKey('edit-note-0')));
    await tester.pump();

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('apply-notes')),
    );
    expect(apply.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('apply-notes')));
    await tester.pump();

    expect(find.text('Apply notes?'), findsNothing);
    expect(repository.applyCalls, 0);
  });

  testWidgets('editing locks other cards and preserves typed text',
      (tester) async {
    final twoCardData = NoteSectionData(
      preview: preview,
      document: NoteSectionDocument(
        preamble: data.document.preamble,
        cards: [
          ...data.document.cards,
          const NoteCard('### second\nsecond body'),
        ],
      ),
      warnings: data.warnings,
      clipIndex: data.clipIndex,
    );
    final repository = _FakeNotesRepository(preview, twoCardData);
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: preview, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-1')));

    await tester.tap(find.byKey(const ValueKey('edit-note-0')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('note-edit-field')), 'typed');

    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('edit-note-1')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('delete-note-1')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-edit-field')))
          .controller!
          .text,
      'typed',
    );
  });

  testWidgets('discard does not leave the page while editing', (tester) async {
    var backCalls = 0;
    await tester.pumpWidget(_app(
      NotesPage(
        repository: _FakeNotesRepository(preview, data),
        preview: preview,
        onBack: () => backCalls++,
      ),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    await tester.tap(find.byKey(const ValueKey('edit-note-0')));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('discard-notes')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('discard-notes')));
    await tester.pump();

    expect(backCalls, 0);
    expect(find.byKey(const ValueKey('note-edit-field')), findsOneWidget);
  });

  testWidgets('editor is read-only during a slow save', (tester) async {
    final repository = _FakeNotesRepository(preview, data)
      ..writeCompleter = Completer<void>();
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: preview, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    await tester.tap(find.byKey(const ValueKey('edit-note-0')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('note-edit-field')), 'edited');
    await tester.tap(find.byKey(const ValueKey('save-note-edit')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('note-edit-field')),
    );
    expect(field.readOnly, isTrue);
    await tester.enterText(
        find.byKey(const ValueKey('note-edit-field')), 'mutated');
    expect(field.controller!.text, 'edited');

    repository.writeCompleter!.complete();
    await _pumpUntilFound(tester, find.text('edited'));
  });

  testWidgets('undo after the page is disposed does not update its state',
      (tester) async {
    final repository = _FakeNotesRepository(preview, data);
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: preview, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    await tester.tap(find.byKey(const ValueKey('delete-note-0')));
    await _pumpUntilFound(
      tester,
      find.text('There are no situations left in this draft.'),
    );
    final undo = tester.widget<SnackBarAction>(find.byType(SnackBarAction));

    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump();
    undo.onPressed();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(repository.writeCalls, 1);
  });

  testWidgets('clip playback is lazy and uses the player seam', (tester) async {
    final session = _FakeClipSession();
    var factoryCalls = 0;
    final clipDirectory = _createTempDirectory('afterimage-lazy-clips');
    Directory('${clipDirectory.path}/clips').createSync();
    File('${clipDirectory.path}/clips/s1-1.mp4').createSync();
    addTearDown(() => _deleteTempEntity(clipDirectory));
    final clipPreview = _preview(
      batchLabel: 'batch-lazy',
      opponent: 'I-No',
      sectionPath: '${clipDirectory.path}/section.md',
    );
    final clipData = NoteSectionData(
      preview: clipPreview,
      document: data.document,
      warnings: const <String>[],
      clipIndex: const ClipIndex(
        video: null,
        situations: [
          ClipSituation(
            heading: '### blocked [[I-No 2S]]',
            entry: 'block',
            posture: 'ground',
            herMoveLink: 'I-No 2S',
            clips: [
              NoteClip(
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
            ],
          ),
        ],
        errors: <String>[],
      ),
    );
    final repository = _FakeNotesRepository(clipPreview, clipData);

    await tester.pumpWidget(_app(
      NotesPage(
        repository: repository,
        preview: clipPreview,
        onBack: () {},
        playerFactory: (_) {
          factoryCalls++;
          return session;
        },
      ),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('clip-player')));

    expect(session.created, isFalse);
    expect(factoryCalls, 0);
    await tester.ensureVisible(find.byKey(const ValueKey('clip-play')));
    await tester.tap(find.byKey(const ValueKey('clip-play')));
    await _flushIo(tester);
    await tester.pump();
    expect(factoryCalls, 1);
    expect(session.playCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(session.disposeCalls, 1);
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
    await _flushIo(tester);
    await tester.pump();

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
    tester.widget<Switch>(find.byType(Switch)).onChanged!(false);
    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-play')))
        .onPressed!();
    await _flushIo(tester);
    await tester.pump();

    expect(session.rateCalls, 1);
    expect(session.lastRate, 0.5);
    expect(session.loopCalls, 1);
    expect(session.lastLoop, isFalse);
  });

  testWidgets('list orders metadata previews and greys legacy entries',
      (tester) async {
    final legacy = _preview(
      batchLabel: 'batch-old',
      opponent: 'Ky',
      sectionPath: '/out/batch-old/Ky/section.md',
      legacy: true,
    );
    final repository = _FakeNotesRepository(
      preview,
      data,
      previews: [preview, legacy],
    );

    NotePreview? opened;
    await tester.pumpWidget(_app(
      NotesListPage(
        repository: repository,
        onOpen: (value) => opened = value,
        onClose: () {},
      ),
    ));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('notes-entry-/out/batch-new/I-No/section.md')),
    );

    final newOffset = tester
        .getTopLeft(find.byKey(
            const ValueKey('notes-entry-/out/batch-new/I-No/section.md')))
        .dy;
    final oldOffset = tester
        .getTopLeft(find
            .byKey(const ValueKey('notes-entry-/out/batch-old/Ky/section.md')))
        .dy;
    expect(newOffset, lessThan(oldOffset));
    expect(find.text('made before the notes page; cannot be applied'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('open-notes-entry')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('open-legacy-notes-entry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-legacy-notes-entry')));
    expect(opened?.sectionPath, legacy.sectionPath);
  });

  testWidgets('legacy preview opens read-only', (tester) async {
    final legacy = _preview(
      batchLabel: 'batch-old',
      opponent: 'Ky',
      sectionPath: '/out/batch-old/Ky/section.md',
      legacy: true,
    );
    final repository = _FakeNotesRepository(
      legacy,
      NoteSectionData(
        preview: legacy,
        document: data.document,
        warnings: const <String>[],
        clipIndex: data.clipIndex,
      ),
    );
    await tester.pumpWidget(_app(
      NotesPage(repository: repository, preview: legacy, onBack: () {}),
    ));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('note-card-0')));

    expect(
      find.text('Made before the notes page; cannot be applied.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('edit-note-0')), findsNothing);
    expect(find.byKey(const ValueKey('delete-note-0')), findsNothing);
    expect(find.byKey(const ValueKey('apply-notes')), findsNothing);
  });

  testWidgets('restarting a clip pauses the other card', (tester) async {
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
    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-pause')).at(1))
        .onPressed!();
    await tester.pump();
    tester.widget<IconButton>(play.at(0)).onPressed!();
    await _flushIo(tester);
    await tester.pump();
    final pausesBeforeRestart = sessions[0].pauseCalls;
    tester
        .widget<IconButton>(find.byKey(const ValueKey('clip-restart')).at(1))
        .onPressed!();
    await _flushIo(tester);
    await tester.pump();

    expect(sessions, hasLength(2));
    expect(sessions[0].pauseCalls, pausesBeforeRestart + 1);
  });

  testWidgets('deleting an earlier card preserves the later clip state',
      (tester) async {
    final clipDirectory = _createTempDirectory('afterimage-stable-clips');
    final clipsDirectory = Directory('${clipDirectory.path}/clips')
      ..createSync();
    final firstFile = File('${clipsDirectory.path}/first.mp4')..createSync();
    final secondFile = File('${clipsDirectory.path}/second-a.mp4')
      ..createSync();
    final secondFileB = File('${clipsDirectory.path}/second-b.mp4')
      ..createSync();
    addTearDown(() => _deleteTempEntity(clipDirectory));

    final stablePreview = _preview(
      batchLabel: 'batch-stable',
      opponent: 'I-No',
      sectionPath: '${clipDirectory.path}/section.md',
    );
    const firstClip = NoteClip(
      file: 'first.mp4',
      poster: null,
      replay: 1,
      videoTime: '00:01',
      videoTimeMs: 1000,
      startMs: 0,
      endMs: 1000,
      herNext: null,
      answer: 'first',
      outcome: 'hit',
      counterHit: false,
    );
    const secondClip = NoteClip(
      file: 'second-a.mp4',
      poster: null,
      replay: 2,
      videoTime: '00:02',
      videoTimeMs: 2000,
      startMs: 1000,
      endMs: 2000,
      herNext: null,
      answer: 'second-a',
      outcome: 'hit',
      counterHit: false,
    );
    const secondClipB = NoteClip(
      file: 'second-b.mp4',
      poster: null,
      replay: 3,
      videoTime: '00:03',
      videoTimeMs: 3000,
      startMs: 2000,
      endMs: 3000,
      herNext: null,
      answer: 'second-b',
      outcome: 'hit',
      counterHit: false,
    );
    final stableData = NoteSectionData(
      preview: stablePreview,
      document: const NoteSectionDocument(
        preamble: '',
        cards: [
          NoteCard('### first', id: 'first'),
          NoteCard('### second', id: 'second'),
        ],
      ),
      warnings: const <String>[],
      clipIndex: const ClipIndex(
        video: null,
        situations: [
          ClipSituation(
            heading: '### first',
            entry: 'block',
            posture: 'ground',
            herMoveLink: null,
            clips: [firstClip],
          ),
          ClipSituation(
            heading: '### second',
            entry: 'block',
            posture: 'ground',
            herMoveLink: null,
            clips: [secondClip, secondClipB],
          ),
        ],
        errors: <String>[],
      ),
    );
    final sessions = <_FakeClipSession>[];
    final repository = _FakeNotesRepository(stablePreview, stableData);

    expect(firstFile.existsSync(), isTrue);
    expect(secondFile.existsSync(), isTrue);
    expect(secondFileB.existsSync(), isTrue);
    await tester.pumpWidget(_app(
      NotesPage(
        repository: repository,
        preview: stablePreview,
        onBack: () {},
        playerFactory: (_) {
          final session = _FakeClipSession();
          sessions.add(session);
          return session;
        },
      ),
    ));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('note-card-second')),
    );

    final secondClipChip = find.byKey(const ValueKey('clip-chip-second-1'));
    await tester.ensureVisible(secondClipChip);
    await tester.tap(secondClipChip);
    await tester.pump();
    final secondPlay = find.byKey(const ValueKey('clip-play')).at(1);
    await tester.ensureVisible(secondPlay);
    await tester.tap(secondPlay);
    await _flushIo(tester);
    await tester.pump();
    expect(sessions, hasLength(1));
    expect(sessions.single.playCalls, 1);

    final deleteFirst = find.byKey(const ValueKey('delete-note-0'));
    await tester.ensureVisible(deleteFirst);
    await tester.tap(deleteFirst);
    await _pumpUntilFound(
      tester,
      find.text('Situation deleted.'),
    );

    final selected = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('clip-chip-second-1')),
    );
    expect(selected.selected, isTrue);
    expect(sessions, hasLength(1));
    expect(sessions.single.playCalls, 1);
  });
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AfterimageTheme.dark(),
    home: Scaffold(body: home),
  );
}

NotePreview _preview({
  required String batchLabel,
  required String opponent,
  required String sectionPath,
  NoteMetadata? metadata,
  bool legacy = false,
}) {
  final resolvedMetadata = legacy
      ? null
      : metadata ??
          NoteMetadata(
            opponent: opponent,
            player: 'Ky',
            batchLabel: batchLabel,
            batchFolder: '/out/$batchLabel',
            notePath: '/notes/$opponent.md',
            createdAt: DateTime(2026, 10, 3, 10, 18),
            previous: null,
            status: NoteMetadataStatus.draft,
            appliedAt: null,
          );
  return NotePreview(
    batchLabel: batchLabel,
    opponent: opponent,
    directoryPath: sectionPath.substring(0, sectionPath.lastIndexOf('/')),
    sectionPath: sectionPath,
    metadata: resolvedMetadata,
    cardCount: 1,
    modifiedAt: DateTime(2026, 10, 3, 10, 18),
  );
}

class _FakeNotesRepository extends NotesRepository {
  _FakeNotesRepository(this.preview, this.data, {List<NotePreview>? previews})
      : _previews = previews ?? [preview],
        super(finderDirectory: '/unused');

  final NotePreview preview;
  NoteSectionData data;
  final List<NotePreview> _previews;
  Completer<void>? writeCompleter;
  int writeCalls = 0;
  int applyCalls = 0;

  @override
  Future<List<NotePreview>> list() async => _previews;

  @override
  Future<NoteSectionData> read(NotePreview preview) async => data;

  @override
  Future<void> write(NotePreview preview, NoteSectionDocument document) async {
    writeCalls++;
    if (writeCompleter != null) await writeCompleter!.future;
    data = NoteSectionData(
      preview: data.preview,
      document: document,
      warnings: data.warnings,
      clipIndex: data.clipIndex,
    );
  }

  @override
  Future<ApplySectionResult> apply(NotePreview preview) async {
    applyCalls++;
    return ApplySectionResult.fromExitCode(0, opponent: preview.opponent);
  }

  @override
  Future<NotePreview?> refreshPreview(NotePreview preview) async => preview;
}

class _FakeClipSession implements NotesClipPlayerSession {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
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
  Future<void> play() async {
    created = true;
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRate(double rate) async {
    rateCalls++;
    lastRate = rate;
  }

  @override
  Future<void> setLoop(bool loop) async {
    loopCalls++;
    lastLoop = loop;
  }

  @override
  Future<Duration> currentPosition() async => Duration.zero;

  @override
  Widget buildVideo(BuildContext context) =>
      const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _position.close();
    await _duration.close();
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
