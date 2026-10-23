import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/finder_contracts.dart';
import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/presentation/views/done_view.dart';
import 'package:afterimage/services/batch_output_directory.dart';
import 'package:afterimage/services/notes_repository.dart';
import 'package:afterimage/services/output_directory_preflight.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('afterimage-finder-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('starts after a completed Linux batch with a capture file', () async {
    final finder = _FakeFinder();
    final controller = _controller(root, finder);
    addTearDown(controller.dispose);
    await controller.refreshReadiness();

    final result = await controller.startBatch();
    await _waitUntil(() => finder.startedFolders.length == 1);

    expect(result?.outcome, ReplayBatchOutcome.completed);
    expect(finder.startedFolders.single, '${root.path}/batch-run');
    expect(controller.error, isNull);
  });

  test('does not start on Windows, without captures, or without the finder',
      () async {
    final windowsFinder = _FakeFinder();
    final windows = _controller(
      root,
      windowsFinder,
      platformIsLinux: false,
    );
    addTearDown(windows.dispose);
    await windows.refreshReadiness();
    await windows.startBatch();
    expect(windowsFinder.startedFolders, isEmpty);

    final noCaptureFinder = _FakeFinder();
    final noCapture = _controller(
      root,
      noCaptureFinder,
      capture: false,
    );
    addTearDown(noCapture.dispose);
    await noCapture.refreshReadiness();
    await noCapture.startBatch();
    expect(noCaptureFinder.startedFolders, isEmpty);

    final unavailableFinder = _FakeFinder(available: false);
    final unavailable = _controller(root, unavailableFinder);
    addTearDown(unavailable.dispose);
    await unavailable.refreshReadiness();
    await unavailable.startBatch();
    expect(unavailableFinder.startedFolders, isEmpty);
  });

  test('finder startup failure does not replace the batch result', () async {
    final finder = _FakeFinder(failure: StateError('finder unavailable'));
    final controller = _controller(root, finder);
    addTearDown(controller.dispose);
    await controller.refreshReadiness();

    final result = await controller.startBatch();
    await _waitUntil(() => controller.finderError != null);

    expect(result?.outcome, ReplayBatchOutcome.completed);
    expect(controller.result?.outcome, ReplayBatchOutcome.completed);
    expect(controller.error, isNull);
    expect(controller.finderError, contains('finder unavailable'));
  });

  testWidgets('done view fails when run.json is missing after one minute',
      (tester) async {
    final startedAt = DateTime(2026, 10, 3, 10, 18);
    final controller = _DoneController(startedAt);
    addTearDown(controller.dispose);
    final now = startedAt.add(const Duration(seconds: 61));
    final repository = _MissingRunRepository(root.path);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoneView(
            controller: controller,
            notesRepository: repository,
            onOpenNotes: () {},
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
        find.textContaining('The notes finder did not start.'), findsOneWidget);
    expect(
      find.text('Log: ${repository.runLogPath(controller.finderBatchLabel!)}'),
      findsOneWidget,
    );
  });

  testWidgets('done view stops polling after the timeout failure',
      (tester) async {
    final startedAt = DateTime(2026, 10, 3, 10, 18);
    final controller = _DoneController(startedAt);
    addTearDown(controller.dispose);
    final repository = _MissingRunRepository(root.path);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoneView(
            controller: controller,
            notesRepository: repository,
            onOpenNotes: () {},
            now: () => startedAt.add(const Duration(seconds: 61)),
          ),
        ),
      ),
    );
    await tester.pump();
    final refreshCalls = controller.refreshCalls;
    await tester.pump(const Duration(seconds: 6));

    expect(refreshCalls, greaterThanOrEqualTo(1));
    expect(controller.refreshCalls, refreshCalls);
  });

  testWidgets('done view stops polling after a terminal finder status',
      (tester) async {
    final startedAt = DateTime(2026, 10, 3, 10, 18);
    final controller = _DoneController(
      startedAt,
      run: FinderRunInfo.fromJson({'status': 'done'}),
    );
    addTearDown(controller.dispose);
    final repository = _MissingRunRepository(root.path);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoneView(
            controller: controller,
            notesRepository: repository,
            onOpenNotes: () {},
            now: () => startedAt,
          ),
        ),
      ),
    );
    await tester.pump();
    final refreshCalls = controller.refreshCalls;
    await tester.pump(const Duration(seconds: 6));

    expect(refreshCalls, greaterThanOrEqualTo(1));
    expect(controller.refreshCalls, refreshCalls);
  });
}

RecorderController _controller(
  Directory root,
  _FakeFinder finder, {
  bool platformIsLinux = true,
  bool capture = true,
}) {
  return RecorderController(
    backend: _CaptureBackend(),
    finder: finder,
    platformIsLinux: () => platformIsLinux,
    options: RecordingOptions(
      outputDirectory: root.path,
      captureFrameData: capture,
    ),
    batchDirectories: _BatchDirectories(root),
    outputPreflight: const _ReadyPreflight(),
    engineFactory: ({
      required monitor,
      required menuInput,
      required obs,
      required organizer,
      required onEvent,
    }) =>
        _CompletingEngine(),
  )..setSetupReport(_readyReport());
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true in time.');
}

SetupReport _readyReport() {
  return SetupReport(
    checkedAt: DateTime(2026, 8, 29),
    checks: [
      for (final id in [
        SetupCheckId.supportedPlatform,
        SetupCheckId.gameInstall,
        SetupCheckId.gameRunning,
        SetupCheckId.obsWebSocket,
        SetupCheckId.replayLibrary,
        SetupCheckId.nativeRecorderBackend,
      ])
        SetupCheck(
          id: id,
          title: id.name,
          detail: 'Ready.',
          status: SetupCheckStatus.ready,
          required: true,
        ),
    ],
  );
}

class _FakeFinder implements FinderPort {
  _FakeFinder({this.available = true, this.failure});

  @override
  final bool available;
  final Object? failure;
  final List<String> startedFolders = <String>[];

  @override
  Future<void> startBatch(String batchFolder) async {
    if (failure != null) throw failure!;
    startedFolders.add(batchFolder);
  }
}

class _MissingRunRepository extends NotesRepository {
  _MissingRunRepository(String finderDirectory)
      : super(finderDirectory: finderDirectory);

  @override
  Future<List<NotePreview>> list() async => const <NotePreview>[];
}

class _DoneController extends RecorderController {
  _DoneController(this.startedAt, {this.run})
      : super(backend: _CaptureBackend());

  final DateTime startedAt;
  final FinderRunInfo? run;
  int refreshCalls = 0;

  @override
  ReplayBatchResult? get result => const ReplayBatchResult(
        outcome: ReplayBatchOutcome.completed,
        replays: <ReplayResult>[],
      );

  @override
  DateTime? get finderStartedAt => startedAt;

  @override
  String? get finderBatchLabel => 'batch-missing';

  @override
  FinderRunInfo? get finderRun => run;

  @override
  Future<void> refreshFinderStatus() async {
    refreshCalls++;
  }
}

class _BatchDirectories extends BatchOutputDirectory {
  _BatchDirectories(this.root);

  final Directory root;

  @override
  Future<BatchOutputReservation> reserve(String outputParent) async {
    final directory = Directory('${root.path}/batch-run');
    await directory.create(recursive: true);
    return BatchOutputReservation(path: directory.path, name: 'batch-run');
  }
}

class _ReadyPreflight implements OutputDirectoryPreflight {
  const _ReadyPreflight();

  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) async =>
      const OutputDirectoryReadiness.ready();
}

class _CaptureBackend
    implements
        NativeRecorderBackend,
        InputModeAwareNativeRecorderBackend,
        FrameCaptureAwareNativeRecorderBackend {
  @override
  bool get supportsFrameCapture => true;

  @override
  String? get frameCaptureUnsupportedReason => null;

  @override
  Future<FrameCapturePort> openFrameCapture() async =>
      const NoopFrameCapturePort();

  @override
  Future<NativeBackendReadiness> inspect() async =>
      const NativeBackendReadiness(available: true, detail: 'Ready.');

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async =>
      const NativeBackendReadiness(available: true, detail: 'Ready.');

  @override
  Future<ReplayMonitorPort> openReplayMonitor() async => _Monitor();

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) async => _Input();

  @override
  Future<ObsRecorderPort> openObsRecorder() async => _Obs();

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() async => _Organizer();
}

class _CompletingEngine implements RecordingEngine {
  @override
  bool get isRunning => false;

  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async {
    final capture =
        File('${request.options.outputDirectory}/replay_001.frames.jsonl');
    await capture.writeAsString('frame\n');
    return const ReplayBatchResult(
      outcome: ReplayBatchOutcome.completed,
      replays: [
        ReplayResult(
          index: 1,
          status: ReplayResultStatus.recorded,
          capture: ReplayCaptureSummary(
            videoOffsetMs: 0,
            rows: 1,
            frameGaps: 0,
            maxFrameGap: 0,
            path: 'replay_001.frames.jsonl',
          ),
        ),
      ],
    );
  }

  @override
  Future<void> requestStop() async {}
}

class _Monitor implements ReplayMonitorPort {
  @override
  Future<void> attach() async {}

  @override
  Future<BattleSnapshot> snapshot() async => const BattleSnapshot.empty();

  @override
  Future<void> close() async {}
}

class _Input implements MenuInputPort {
  @override
  Future<void> perform(ReplayMenuAction action) async {}
}

class _Obs implements ObsRecorderPort {
  @override
  Future<void> connect() async {}

  @override
  Future<void> assertIdle() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<RecordedOutput> stopRecording() async =>
      const RecordedOutput('/tmp/recording.mp4');

  @override
  Future<void> close() async {}
}

class _Organizer implements OutputOrganizerPort {
  @override
  Future<OrganizedOutput> organizeReplay({
    required RecordedOutput source,
    required String outputDirectory,
    required int replayIndex,
    required bool partial,
  }) async =>
      OrganizedOutput(
        path: '$outputDirectory/replay.mp4',
        partial: partial,
        replayIndex: replayIndex,
      );

  @override
  Future<OrganizedOutput> organizeCombined({
    required RecordedOutput source,
    required String outputDirectory,
    required bool partial,
  }) async =>
      OrganizedOutput(path: '$outputDirectory/combined.mp4', partial: partial);
}
