import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/afterimage_app.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/services/output_directory_preflight.dart';
import 'package:afterimage/services/batch_output_directory.dart';
import 'package:afterimage/services/setup_service.dart';
import 'package:afterimage/services/replay_batch_engine.dart';

void main() {
  testWidgets('ready backend unlocks start and shows the terminal result',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _FakeBackend();
    final engine = _CompletingEngine();
    final controller = _controller(backend, engine);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();

    final startButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start-batch')),
    );
    expect(startButton.onPressed, isNotNull);
    expect(find.textContaining('Everything is ready.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start-batch')));
    await tester.pumpAndSettle();

    expect(find.text('Batch completed'), findsOneWidget);
    expect(find.text('Existing files are never overwritten.'), findsOneWidget);
    expect(engine.startCalls, 1);
  });

  testWidgets('folder picker keeps the path editable and updates the field',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(_FakeBackend(), _CompletingEngine(),
        picker: () async => '/home/tester/captures');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('browse-output-folder')),
    );
    await tester.tap(find.byKey(const ValueKey('browse-output-folder')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('output-folder')),
    );
    expect(field.controller?.text, '/home/tester/captures');
    expect(find.textContaining('Everything is ready.'), findsOneWidget);
  });

  testWidgets('unsupported controller remains disabled and is not advertised',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _FakeBackend(controllerAvailable: false),
      _CompletingEngine(),
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
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();

    final controllerTile = tester.widget<RadioListTile<InputMode>>(
      find.byKey(const ValueKey('input-mode-virtualController')),
    );
    expect(controllerTile.enabled, isFalse);
    expect(
      find.textContaining('No virtual controller driver is installed.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Not available in the current backend.'),
      findsNothing,
    );
  });

  testWidgets('sidebar follows selected input readiness changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _FakeBackend(controllerAvailable: false),
      _CompletingEngine(),
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
    expect(find.text('Ready to record'), findsOneWidget);

    await controller.setInputMode(InputMode.virtualController);
    await tester.pump();

    expect(find.text('Recording locked'), findsOneWidget);
    expect(find.text('Ready to record'), findsNothing);
  });

  testWidgets('terminal counts a complete capture saved before a later failure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _CompletingEngine(
      terminalResult: const ReplayBatchResult(
        outcome: ReplayBatchOutcome.failed,
        replays: [
          ReplayResult(
            index: 1,
            status: ReplayResultStatus.failed,
            output: OrganizedOutput(
              path: '/tmp/captures/replay_001.mp4',
              partial: false,
              replayIndex: 1,
            ),
            error: 'GGST did not return to the replay list.',
          ),
        ],
        error: 'GGST did not return to the replay list.',
      ),
    );
    final controller = _controller(_FakeBackend(), engine);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _ReadySetupService(),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-batch')));
    await tester.pumpAndSettle();

    expect(
      find.text('1 replay saved.'),
      findsOneWidget,
    );
  });
}

RecorderController _controller(
  _FakeBackend backend,
  _CompletingEngine engine, {
  RecordingOptions options = const RecordingOptions(
    outputDirectory: '/tmp/afterimage',
  ),
  OutputDirectoryPicker? picker,
}) {
  return RecorderController(
    backend: backend,
    options: options,
    directoryPicker: picker ?? () async => null,
    outputPreflight: const _ReadyOutputPreflight(),
    batchDirectories: _MemoryBatchDirectories(),
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
}

class _ReadyOutputPreflight implements OutputDirectoryPreflight {
  const _ReadyOutputPreflight();

  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) async =>
      const OutputDirectoryReadiness.ready();
}

class _ReadySetupService implements SetupService {
  @override
  Future<SetupReport> inspect() async => _readyReport();
}

SetupReport _readyReport() {
  return SetupReport(
    checkedAt: DateTime(2026, 8, 29),
    checks: [
      for (final id in [
        SetupCheckId.supportedPlatform,
        SetupCheckId.runtime,
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
  _FakeBackend({this.controllerAvailable = true});

  final bool controllerAvailable;

  @override
  Future<NativeBackendReadiness> inspect() async =>
      const NativeBackendReadiness(available: true, detail: 'Backend ready.');

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async {
    return NativeBackendReadiness(
      available: inputMode == InputMode.keyboard || controllerAvailable,
      detail: inputMode == InputMode.keyboard
          ? 'Keyboard input ready.'
          : controllerAvailable
              ? 'Controller input ready.'
              : 'No virtual controller driver is installed.',
    );
  }

  @override
  Future<ReplayMonitorPort> openReplayMonitor() async => _FakeMonitor();

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) async => _FakeInput();

  @override
  Future<ObsRecorderPort> openObsRecorder() async => _FakeObs();

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() async => _FakeOrganizer();
}

class _CompletingEngine implements RecordingEngine {
  _CompletingEngine({this.terminalResult});

  final ReplayBatchResult? terminalResult;
  ReplayBatchEventSink? onEvent;
  int startCalls = 0;
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
      ),
    );
    await Future<void>.delayed(Duration.zero);
    _running = false;
    onEvent?.call(
      ReplayBatchEvent(
        type: ReplayBatchEventType.completed,
        progress: ReplayBatchProgress(
          state: ReplayBatchState.completed,
          totalReplays: request.replayCount,
          currentReplay: request.replayCount,
          completedReplays: request.replayCount,
          detail: 'Batch completed.',
        ),
        message: 'Batch completed.',
      ),
    );
    return terminalResult ??
        const ReplayBatchResult(
          outcome: ReplayBatchOutcome.completed,
          replays: [
            ReplayResult(
              index: 1,
              status: ReplayResultStatus.recorded,
              output: OrganizedOutput(
                path: '/tmp/afterimage/replay-1.mp4',
                partial: false,
                replayIndex: 1,
              ),
            ),
          ],
        );
  }

  @override
  Future<void> requestStop() async {}
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

class _MemoryBatchDirectories extends BatchOutputDirectory {
  @override
  Future<BatchOutputReservation> reserve(String outputParent) async =>
      BatchOutputReservation(
          path: '$outputParent/batch-test', name: 'batch-test');
}
