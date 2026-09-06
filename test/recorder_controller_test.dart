import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_blocker.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/services/output_directory_preflight.dart';
import 'package:afterimage/services/replay_batch_engine.dart';

void main() {
  test('readiness checks each input mode and does not claim unsupported input',
      () async {
    final backend = _FakeBackend(
      inputReadiness: {
        InputMode.keyboard: const NativeBackendReadiness(
          available: true,
          detail: 'Keyboard input is ready.',
        ),
        InputMode.controller: const NativeBackendReadiness(
          available: false,
          detail: 'No virtual controller driver is installed.',
        ),
      },
    );
    final controller = RecorderController(backend: backend);

    await controller.refreshReadiness();

    expect(controller.isInputModeAvailable(InputMode.keyboard), isTrue);
    expect(
      controller.isInputModeAvailable(InputMode.controller),
      isFalse,
    );
    expect(backend.inspectedModes, containsAll(InputMode.values));
    expect(
      controller.blockers.map((blocker) => blocker.id),
      contains(RecorderBlockerId.outputFolder),
    );
    controller.dispose();
  });

  test('a second start is rejected before opening another native session',
      () async {
    final backend = _FakeBackend();
    final engine = _FakeEngine();
    final controller = RecorderController(
      backend: backend,
      options: const RecordingOptions(outputDirectory: '/tmp/afterimage'),
      engineFactory: ({
        required monitor,
        required menuInput,
        required obs,
        required organizer,
        required onEvent,
      }) {
        return engine..onEvent = onEvent;
      },
    )..setSetupReport(_readyReport());
    await controller.refreshReadiness();

    final first = controller.startBatch();
    await _waitUntil(() => engine.startCalls == 1);
    final second = await controller.startBatch();

    expect(second, isNull);
    expect(controller.error.toString(), contains('already running'));
    expect(backend.monitorOpens, 1);
    expect(backend.menuInputOpens, 1);
    expect(backend.obsOpens, 1);

    engine.complete(const ReplayBatchResult(
      outcome: ReplayBatchOutcome.completed,
      replays: <ReplayResult>[],
    ));
    final result = await first;
    expect(result?.outcome, ReplayBatchOutcome.completed);
    expect(controller.isBusy, isFalse);
    controller.dispose();
  });

  test('stop is forwarded to the active engine and terminal result is exposed',
      () async {
    final backend = _FakeBackend();
    final engine = _FakeEngine();
    final controller = RecorderController(
      backend: backend,
      options: const RecordingOptions(outputDirectory: '/tmp/afterimage'),
      engineFactory: ({
        required monitor,
        required menuInput,
        required obs,
        required organizer,
        required onEvent,
      }) {
        return engine..onEvent = onEvent;
      },
    )..setSetupReport(_readyReport());
    await controller.refreshReadiness();

    final run = controller.startBatch();
    await _waitUntil(() => engine.startCalls == 1);
    await controller.requestStop();

    expect(engine.stopCalls, 1);
    expect(controller.isStopping, isTrue);
    engine.complete(const ReplayBatchResult(
      outcome: ReplayBatchOutcome.stopped,
      replays: <ReplayResult>[],
    ));
    await run;

    expect(controller.result?.outcome, ReplayBatchOutcome.stopped);
    expect(controller.isBusy, isFalse);
    controller.dispose();
  });

  test('stop during preparation prevents opening recorder ports', () async {
    final backend = _FakeBackend();
    final preflight = _PendingPreflight();
    final controller = RecorderController(
      backend: backend,
      outputPreflight: preflight,
      engineFactory: (
              {required monitor,
              required menuInput,
              required obs,
              required organizer,
              required onEvent}) =>
          _ImmediateEngine(),
      options: const RecordingOptions(outputDirectory: '/tmp/afterimage'),
    )..setSetupReport(_readyReport());
    await controller.refreshReadiness();
    final run = controller.startBatch();
    await preflight.started.future;
    await controller.requestStop();
    preflight.completion.complete(const OutputDirectoryReadiness.ready());
    await run;
    expect(backend.monitorOpens, 0,
        reason:
            'Stop during preparation must prevent opening the game monitor');
    expect(backend.obsOpens, 0);
    expect(controller.result?.outcome, ReplayBatchOutcome.stopped);
    controller.dispose();
  });

  test('folder picker updates the editable output path', () async {
    final controller = RecorderController(
      backend: _FakeBackend(),
      directoryPicker: () async => '/home/tester/recordings',
    );

    await controller.browseOutputDirectory();

    expect(controller.options.outputDirectory, '/home/tester/recordings');
    expect(controller.isPickingDirectory, isFalse);
    controller.dispose();
  });

  test('batch size is capped to the saved replays that actually exist', () {
    final controller = RecorderController(
      backend: _FakeBackend(),
      options: const RecordingOptions(
        replayCount: ReplayCountOption.twenty,
      ),
    )..setSetupReport(
        SetupReport(
          checkedAt: DateTime(2026, 8, 29),
          replayCount: 3,
          checks: const <SetupCheck>[],
        ),
      );

    expect(controller.replayCountFromReport(), 3);
    controller.dispose();
  });

  test('output preflight blocks before any OBS connection opens', () async {
    final backend = _FakeBackend();
    final controller = RecorderController(
      backend: backend,
      outputPreflight: const _BlockingOutputPreflight(),
      options: const RecordingOptions(outputDirectory: '/tmp/not-writable'),
    )..setSetupReport(_readyReport());
    await controller.refreshReadiness();

    final result = await controller.startBatch();

    expect(result, isNull);
    expect(controller.error.toString(), contains('not writable'));
    expect(backend.monitorOpens, 0);
    expect(backend.obsOpens, 0);
    controller.dispose();
  });

  test('folder picker does not overwrite a path edited while it is open',
      () async {
    final pickerResult = Completer<String?>();
    final controller = RecorderController(
      backend: _FakeBackend(),
      directoryPicker: () => pickerResult.future,
      options: const RecordingOptions(outputDirectory: '/tmp/original'),
    );

    final browse = controller.browseOutputDirectory();
    controller.updateOptions(
      controller.options.copyWith(outputDirectory: '/tmp/typed-by-user'),
    );
    pickerResult.complete('/tmp/picked-later');
    await browse;

    expect(controller.options.outputDirectory, '/tmp/typed-by-user');
    controller.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
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

class _FakeBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  _FakeBackend({
    Map<InputMode, NativeBackendReadiness>? inputReadiness,
  }) : inputReadiness = inputReadiness ??
            {
              for (final mode in InputMode.values)
                mode: const NativeBackendReadiness(
                  available: true,
                  detail: 'Input is ready.',
                ),
            };

  final Map<InputMode, NativeBackendReadiness> inputReadiness;
  final List<InputMode> inspectedModes = [];
  int monitorOpens = 0;
  int menuInputOpens = 0;
  int obsOpens = 0;

  @override
  Future<NativeBackendReadiness> inspect() async {
    return const NativeBackendReadiness(
      available: true,
      detail: 'Backend is ready.',
    );
  }

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async {
    inspectedModes.add(inputMode);
    return inputReadiness[inputMode]!;
  }

  @override
  Future<ReplayMonitorPort> openReplayMonitor() async {
    monitorOpens++;
    return _FakeMonitor();
  }

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) async {
    menuInputOpens++;
    return _FakeInput();
  }

  @override
  Future<ObsRecorderPort> openObsRecorder() async {
    obsOpens++;
    return _FakeObs();
  }

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() async => _FakeOrganizer();
}

class _BlockingOutputPreflight implements OutputDirectoryPreflight {
  const _BlockingOutputPreflight();

  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) async {
    return const OutputDirectoryReadiness.blocked(
      detail: 'The selected output folder is not writable.',
    );
  }
}

class _FakeEngine implements RecordingEngine {
  final Completer<ReplayBatchResult> _completion =
      Completer<ReplayBatchResult>();
  ReplayBatchEventSink? onEvent;
  int startCalls = 0;
  int stopCalls = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async {
    startCalls++;
    _running = true;
    onEvent?.call(
      ReplayBatchEvent(
        type: ReplayBatchEventType.started,
        progress: ReplayBatchProgress(
          state: ReplayBatchState.preparing,
          totalReplays: request.replayCount,
          currentReplay: 0,
          completedReplays: 0,
          detail: 'Preparing.',
        ),
        message: 'Started.',
      ),
    );
    final result = await _completion.future;
    _running = false;
    return result;
  }

  @override
  Future<void> requestStop() async {
    stopCalls++;
  }

  void complete(ReplayBatchResult result) {
    if (!_completion.isCompleted) {
      _completion.complete(result);
    }
  }
}

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
  }) async {
    return OrganizedOutput(
      path: '$outputDirectory/replay-$replayIndex.mp4',
      partial: partial,
      replayIndex: replayIndex,
    );
  }

  @override
  Future<OrganizedOutput> organizeCombined({
    required RecordedOutput source,
    required String outputDirectory,
    required bool partial,
  }) async {
    return OrganizedOutput(
      path: '$outputDirectory/combined.mp4',
      partial: partial,
    );
  }
}

class _PendingPreflight implements OutputDirectoryPreflight {
  final started = Completer<void>();
  final completion = Completer<OutputDirectoryReadiness>();
  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) {
    started.complete();
    return completion.future;
  }
}

class _ImmediateEngine implements RecordingEngine {
  @override
  bool get isRunning => false;
  @override
  Future<void> requestStop() async {}
  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async =>
      const ReplayBatchResult(
          outcome: ReplayBatchOutcome.completed, replays: []);
}
