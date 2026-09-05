import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/afterimage_app.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_blocker.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/presentation/replay_timeline.dart';
import 'package:afterimage/services/batch_output_directory.dart';
import 'package:afterimage/services/output_directory_preflight.dart';
import 'package:afterimage/services/replay_batch_engine.dart';
import 'package:afterimage/services/setup_service.dart';

/// Regressions found by external review of the single-screen rework.
void main() {
  testWidgets(
      'an invalid replay count keeps the field on screen so it can be fixed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('replay-count-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-replay-count')),
      '1001',
    );
    await tester.pumpAndSettle();

    // A value typed into the batch form must never take the batch form away.
    // Doing so removes the only control that can correct it, and the user is
    // stuck until they restart the application.
    expect(find.byKey(const ValueKey('custom-replay-count')), findsOneWidget);
    expect(find.byKey(const ValueKey('lead-blocker')), findsNothing);
    expect(find.byKey(const ValueKey('option-blockers')), findsOneWidget);
    // Both the inline blocker and the field's own helper text say this, which
    // is the message sitting next to the control that fixes it.
    expect(find.textContaining('1 to 1000'), findsWidgets);

    final start = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start-batch')),
    );
    expect(start.onPressed, isNull);

    // And it must be recoverable in place.
    await tester.enterText(
      find.byKey(const ValueKey('custom-replay-count')),
      '20',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('option-blockers')), findsNothing);
  });

  testWidgets('the blocked screen never names a control it does not show',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The game is missing AND no output folder is chosen, so both an
    // environment blocker and an option blocker exist at once. The blocked
    // screen has no batch form on it, so naming the output folder there points
    // at a control the user cannot see.
    final controller = RecorderController(backend: _ReadyBackend());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _BlockedGameSetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.optionBlockers, isNotEmpty);
    expect(find.byKey(const ValueKey('lead-blocker')), findsOneWidget);
    expect(find.text('Output folder'), findsNothing);
    expect(find.textContaining('where Afterimage should save'), findsNothing);
  });

  testWidgets('a refresh in progress is not reported as user action needed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gate = Completer<SetupReport>();
    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
    )..setSetupReport(_readyReport());
    addTearDown(controller.dispose);
    await controller.refreshAllReadiness();

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('READY'), findsOneWidget);

    // Start a refresh that has not answered yet. `canStart` goes false purely
    // because checking is in progress, but nothing is being asked of the user,
    // so the header must not say so.
    controller.setupInspector = () => gate.future;
    unawaited(controller.refreshAllReadiness());
    await tester.pump();

    expect(controller.canStart, isFalse);
    expect(find.text('ACTION NEEDED'), findsNothing);

    gate.complete(_readyReport());
    await tester.pumpAndSettle();
  });

  testWidgets('a stop whose output could not be saved is not dressed up',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = _StopWithSaveErrorEngine();
    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
      outputPreflight: const _ReadyPreflight(),
      batchDirectories: _MemoryBatchDirectories(),
      engineFactory: ({
        required monitor,
        required menuInput,
        required obs,
        required organizer,
        required onEvent,
      }) =>
          engine..onEvent = onEvent,
    )..setSetupReport(_readyReport());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-batch')));
    await tester.pumpAndSettle();

    // The header badge and the result panel must agree. They used to disagree,
    // showing an amber STOPPED above a red "saving needs attention".
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('Stopped, but saving needs attention'), findsOneWidget);
    expect(find.text('FINISHED'), findsNothing);
    expect(find.text('STOPPED'), findsNothing);
  });

  testWidgets(
      'a failure before the engine starts is shown, and the header '
      'stops claiming READY', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
      outputPreflight: const _FailingPreflight(),
      batchDirectories: _MemoryBatchDirectories(),
    )..setSetupReport(_readyReport());
    addTearDown(controller.dispose);

    // A persistent preferences notice must not mask a recording failure.
    controller.preferenceNotice = 'Your choices could not be remembered.';

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-batch')));
    await tester.pumpAndSettle();

    // The batch never started, so there is no result and the phase is still
    // `ready`. The header must not say READY while a failure is on screen and
    // pressing Start again would simply repeat it.
    expect(controller.error, isNotNull);
    expect(find.text('READY'), findsNothing);
    expect(find.text('NOT READY'), findsOneWidget);
    expect(
        find.textContaining('That folder cannot be written'), findsOneWidget);
    expect(find.textContaining('could not be remembered'), findsNothing);
  });

  test('an environment blocker replaces the form, an option blocker does not',
      () async {
    final controller = RecorderController(
      backend: _ReadyBackend(),
      setupInspector: () async => _blockedGameReport(),
    );
    addTearDown(controller.dispose);
    await controller.refreshAllReadiness();

    expect(
      controller.environmentBlockers.map((blocker) => blocker.id),
      contains(RecorderBlockerId.gameInstall),
    );
    expect(
      controller.optionBlockers.map((blocker) => blocker.id),
      contains(RecorderBlockerId.outputFolder),
    );
    expect(controller.phase, RecorderPhase.blocked);
    expect(controller.leadBlocker?.id, RecorderBlockerId.gameInstall);
  });

  test('replay outcomes survive the controller\'s bounded event buffer',
      () async {
    // The controller keeps only the most recent 200 events. Deriving the
    // timeline from that buffer made a long batch silently revert its earliest
    // finished replays to "waiting" while the counters kept climbing. This
    // drives a real controller past that cap rather than building an outcome
    // map by hand, so removing `_replayOutcomes` fails it.
    final engine = _ChattyEngine(replays: 60);
    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(
        outputDirectory: '/tmp/captures',
        replayCount: ReplayCountOption.custom,
        customReplayCount: 60,
      ),
      outputPreflight: const _ReadyPreflight(),
      batchDirectories: _MemoryBatchDirectories(),
      engineFactory: ({
        required monitor,
        required menuInput,
        required obs,
        required organizer,
        required onEvent,
      }) =>
          engine..onEvent = onEvent,
    )..setSetupReport(_readyReport());
    addTearDown(controller.dispose);
    await controller.refreshAllReadiness();

    await controller.startBatch();

    // The buffer really did overflow, otherwise this proves nothing.
    expect(engine.emitted, greaterThan(200));
    expect(controller.events.length, 200);

    // ...and every replay's outcome is still known.
    expect(controller.replayOutcomes.length, 60);
    expect(controller.replayOutcomes[1]?.status, ReplayRowStatus.done);

    final rows = timelineFromOutcomes(
      controller.replayOutcomes,
      const ReplayBatchProgress(
        state: ReplayBatchState.completed,
        totalReplays: 60,
        currentReplay: 60,
        completedReplays: 60,
      ),
    );
    expect(rows.first.status, ReplayRowStatus.done);
    expect(rows.where((row) => row.status == ReplayRowStatus.pending), isEmpty);
  });

  testWidgets('a batch whose video was never saved reports no saves',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Combined mode keeps per-replay results as `recorded` and finalizes one
    // video separately. If finalizing fails there is no file, and counting the
    // replay results would claim saves that do not exist.
    final engine = _NoVideoEngine();
    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
      outputPreflight: const _ReadyPreflight(),
      batchDirectories: _MemoryBatchDirectories(),
      engineFactory: ({
        required monitor,
        required menuInput,
        required obs,
        required organizer,
        required onEvent,
      }) =>
          engine..onEvent = onEvent,
    )..setSetupReport(_readyReport());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-batch')));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(find.textContaining('replays saved'), findsNothing);
    expect(find.textContaining('No video file was produced'), findsOneWidget);
  });

  test('a finished batch stops accumulating elapsed time', () async {
    final engine = _ChattyEngine(replays: 1);
    final controller = RecorderController(
      backend: _ReadyBackend(),
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
      outputPreflight: const _ReadyPreflight(),
      batchDirectories: _MemoryBatchDirectories(),
      engineFactory: ({
        required monitor,
        required menuInput,
        required obs,
        required organizer,
        required onEvent,
      }) =>
          engine..onEvent = onEvent,
    )..setSetupReport(_readyReport());
    addTearDown(controller.dispose);
    await controller.refreshAllReadiness();

    await controller.startBatch();
    final first = controller.elapsed;
    expect(first, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.elapsed, first);
  });
}

class _ReadySetupService implements SetupService {
  @override
  Future<SetupReport> inspect() async => SetupReport(
        checkedAt: DateTime(2026, 9, 5),
        checks: const [
          SetupCheck(
            id: SetupCheckId.supportedPlatform,
            title: 'Supported desktop OS',
            detail: 'Linux is supported.',
            status: SetupCheckStatus.ready,
            required: true,
          ),
          SetupCheck(
            id: SetupCheckId.gameInstall,
            title: 'GGST installation',
            detail: 'Found.',
            status: SetupCheckStatus.ready,
            required: true,
          ),
          SetupCheck(
            id: SetupCheckId.gameRunning,
            title: 'GGST process',
            detail: 'Running.',
            status: SetupCheckStatus.ready,
            required: true,
          ),
          SetupCheck(
            id: SetupCheckId.obsWebSocket,
            title: 'OBS connection',
            detail: 'Connected.',
            status: SetupCheckStatus.ready,
            required: true,
          ),
          SetupCheck(
            id: SetupCheckId.replayLibrary,
            title: 'Replay library',
            detail: '40 files found.',
            status: SetupCheckStatus.ready,
            required: true,
            value: '40',
          ),
          SetupCheck(
            id: SetupCheckId.nativeRecorderBackend,
            title: 'Recording support',
            detail: 'Available.',
            status: SetupCheckStatus.ready,
            required: true,
          ),
        ],
      );
}

SetupReport _blockedGameReport() => SetupReport(
      checkedAt: DateTime(2026, 9, 5),
      checks: const [
        SetupCheck(
          id: SetupCheckId.gameInstall,
          title: 'GGST installation',
          detail: 'No GGST installation was found.',
          status: SetupCheckStatus.blocked,
          required: true,
        ),
      ],
    );

class _ReadyBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  @override
  Future<NativeBackendReadiness> inspect() async =>
      const NativeBackendReadiness(available: true, detail: 'Ready.');

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async =>
      const NativeBackendReadiness(available: true, detail: 'Ready.');

  @override
  Future<ReplayMonitorPort> openReplayMonitor() async => _FakeMonitor();

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) async => _FakeInput();

  @override
  Future<ObsRecorderPort> openObsRecorder() async => _FakeObs();

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() async => _FakeOrganizer();
}

class _ReadyPreflight implements OutputDirectoryPreflight {
  const _ReadyPreflight();

  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) async =>
      const OutputDirectoryReadiness.ready();
}

class _MemoryBatchDirectories extends BatchOutputDirectory {
  @override
  Future<BatchOutputReservation> reserve(String outputParent) async =>
      BatchOutputReservation(
        path: '$outputParent/batch-test',
        name: 'batch-test',
      );
}

/// Emits the same shape of event stream the real engine does: several events
/// per replay, enough of them to overflow the controller's 200-event buffer.
class _ChattyEngine implements RecordingEngine {
  _ChattyEngine({required this.replays});

  final int replays;
  ReplayBatchEventSink? onEvent;
  int emitted = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async {
    _running = true;
    final results = <ReplayResult>[];
    for (var replay = 1; replay <= replays; replay++) {
      final progress = ReplayBatchProgress(
        state: ReplayBatchState.recordingReplay,
        totalReplays: replays,
        currentReplay: replay,
        completedReplays: replay - 1,
      );
      for (final type in [
        ReplayBatchEventType.replayStarted,
        ReplayBatchEventType.battleStarted,
        ReplayBatchEventType.stateChanged,
        ReplayBatchEventType.replayCompleted,
        ReplayBatchEventType.outputSaved,
      ]) {
        emitted++;
        onEvent?.call(
          ReplayBatchEvent(
            type: type,
            progress: progress,
            replayIndex: replay,
          ),
        );
      }
      results.add(
        ReplayResult(index: replay, status: ReplayResultStatus.recorded),
      );
    }
    _running = false;
    return ReplayBatchResult(
      outcome: ReplayBatchOutcome.completed,
      replays: results,
      combinedOutput: const OrganizedOutput(
        path: '/tmp/captures/batch-test/combined.mp4',
        partial: false,
      ),
    );
  }

  @override
  Future<void> requestStop() async {}
}

SetupReport _readyReport() => SetupReport(
      checkedAt: DateTime(2026, 9, 5),
      checks: const [
        SetupCheck(
          id: SetupCheckId.replayLibrary,
          title: 'Replay library',
          detail: '80 files found.',
          status: SetupCheckStatus.ready,
          required: true,
          value: '80',
        ),
      ],
    );

class _FakeMonitor implements ReplayMonitorPort {
  @override
  Future<void> attach() async {}

  @override
  Future<BattleSnapshot> snapshot() async => const BattleSnapshot.empty();

  @override
  Future<void> close() async {}
}

class _FakeInput implements MenuInputPort {
  @override
  Future<void> perform(ReplayMenuAction action) async {}
}

class _FakeObs implements ObsRecorderPort {
  @override
  Future<void> connect() async {}

  @override
  Future<void> assertIdle() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<RecordedOutput> stopRecording() async =>
      const RecordedOutput('/tmp/afterimage.mp4');

  @override
  Future<void> close() async {}
}

class _FakeOrganizer implements OutputOrganizerPort {
  @override
  Future<OrganizedOutput> organizeReplay({
    required RecordedOutput source,
    required String outputDirectory,
    required int replayIndex,
    required bool partial,
  }) async =>
      OrganizedOutput(
        path: '$outputDirectory/replay-$replayIndex.mp4',
        partial: partial,
        replayIndex: replayIndex,
      );

  @override
  Future<OrganizedOutput> organizeCombined({
    required RecordedOutput source,
    required String outputDirectory,
    required bool partial,
  }) async =>
      OrganizedOutput(
        path: '$outputDirectory/combined.mp4',
        partial: partial,
      );
}

/// Finishes every replay, then fails to produce the combined video.
class _NoVideoEngine implements RecordingEngine {
  ReplayBatchEventSink? onEvent;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async {
    _running = true;
    const progress = ReplayBatchProgress(
      state: ReplayBatchState.completed,
      totalReplays: 3,
      currentReplay: 3,
      completedReplays: 3,
    );
    for (var replay = 1; replay <= 3; replay++) {
      onEvent?.call(
        ReplayBatchEvent(
          type: ReplayBatchEventType.replayCompleted,
          progress: progress,
          replayIndex: replay,
        ),
      );
    }
    _running = false;
    return const ReplayBatchResult(
      outcome: ReplayBatchOutcome.failed,
      replays: [
        ReplayResult(index: 1, status: ReplayResultStatus.recorded),
        ReplayResult(index: 2, status: ReplayResultStatus.recorded),
        ReplayResult(index: 3, status: ReplayResultStatus.recorded),
      ],
      error: 'The combined recording could not be stopped.',
    );
  }

  @override
  Future<void> requestStop() async {}
}

class _BlockedGameSetupService implements SetupService {
  @override
  Future<SetupReport> inspect() async => _blockedGameReport();
}

/// Stops as requested, but cannot preserve what OBS produced.
class _StopWithSaveErrorEngine implements RecordingEngine {
  ReplayBatchEventSink? onEvent;

  @override
  bool get isRunning => false;

  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async {
    return const ReplayBatchResult(
      outcome: ReplayBatchOutcome.stopped,
      replays: [ReplayResult(index: 1, status: ReplayResultStatus.stopped)],
      error: 'The partial recording could not be preserved.',
    );
  }

  @override
  Future<void> requestStop() async {}
}

class _FailingPreflight implements OutputDirectoryPreflight {
  const _FailingPreflight();

  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) async =>
      const OutputDirectoryReadiness.blocked(
        detail: 'That folder cannot be written to.',
      );
}
