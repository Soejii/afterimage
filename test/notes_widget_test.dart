import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/theme.dart';
import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/presentation/notes_pages.dart';
import 'package:afterimage/presentation/widgets/notes_clip_player.dart';
import 'package:afterimage/services/notes_repository.dart';

void main() {
  testWidgets('flagged cards show flags, lead-ins and mixups; others collapse',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final repository = _FakeNotesRepository(preview, _data(preview));

    await tester.pumpWidget(_app(NotesPage(
      repository: repository,
      preview: preview,
      onBack: () {},
      playerFactory: (_) => _FakeClipSession(),
    )));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('sequence-card-c1')));

    expect(find.text('blocked S Mr. Dolphin Vertical'), findsOneWidget);
    expect(find.text('keeps losing: hit 2 of 3'), findsOneWidget);
    expect(find.text('lead-ins: 2K x2, string opener x1'), findsOneWidget);
    expect(find.text('mixup after 2K: 5H x1, jump back x1'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-c1-s1')), findsOneWidget);
    // The unflagged card starts collapsed.
    expect(find.byKey(const ValueKey('save-c2-s1')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('show-sequences-c2')));
    await tester.tap(find.byKey(const ValueKey('show-sequences-c2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('save-c2-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('strivelabs-notice')), findsOneWidget);
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
    await _pumpUntilFound(tester, find.byKey(const ValueKey('save-c1-s1')));
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
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('save-mixup-c1-0')));
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
    await _pumpUntilFound(tester, find.byKey(const ValueKey('save-c1-s3')));

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
    await _pumpUntilFound(tester, find.byKey(const ValueKey('save-c1-s1')));
    await tester.tap(find.byKey(const ValueKey('save-c1-s1')));
    await tester.pump();

    for (final key in ['save-c1-s1', 'save-c1-s2', 'save-mixup-c1-0']) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
        reason: '$key while saving',
      );
    }
    expect(
      tester
          .widget<OutlinedButton>(
              find.byKey(const ValueKey('back-from-sequences')))
          .onPressed,
      isNull,
    );
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
    await _pumpUntilFound(tester, find.byKey(const ValueKey('clip-player-c1')));
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

  testWidgets('the list shows each opponent with flagged counts',
      (tester) async {
    final preview = _preview(directory: '/out/batch-a/May');
    final opened = <NotePreview>[];

    await tester.pumpWidget(_app(NotesListPage(
      repository: _FakeNotesRepository(preview, _data(preview)),
      onOpen: opened.add,
      onClose: () {},
    )));
    await _pumpUntilFound(tester, find.text('vs May'));

    expect(find.text('2 situations  ·  1 flagged'), findsOneWidget);
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
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AfterimageTheme.dark(),
    home: Scaffold(body: home),
  );
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
