import 'dart:async';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/finder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/presentation/screens/workspace_screen.dart';
import 'package:afterimage/services/batch_output_directory.dart';
import 'package:afterimage/services/output_directory_preflight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live switch updates count and locks batch start',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _Backend();
    final controller = _controller(backend);
    addTearDown(controller.dispose);
    await controller.refreshReadiness();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceScreen(
      controller: controller,
      isRefreshing: false,
      onRefresh: () async {},
    ))));
    final toggle = find.byKey(const ValueKey('live-capture'));
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.liveCaptureActive, isTrue);
    backend.live.onGame!(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.text('Capturing your matches. 2 games so far.'), findsOneWidget);
    expect(controller.canStart, isFalse);
    // The batch form is replaced while a session runs.
    expect(find.byKey(const ValueKey('start-batch')), findsNothing);
    expect(find.byKey(const ValueKey('live-capture-view')), findsOneWidget);
    expect(await controller.startBatch(), isNull);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();
    expect(controller.liveCaptureActive, isFalse);
  });

  testWidgets('finder starts once when a nonempty live session ends',
      (tester) async {
    final backend = _Backend();
    final finder = _Finder();
    final controller = _controller(backend, finder: finder);
    addTearDown(controller.dispose);
    final session = controller.setLiveCapture(true);
    await tester.pump();
    backend.live.finish('/tmp/live-test');
    await tester.pump();
    await session;
    expect(finder.calls, 1);
    expect(finder.reference, isFalse);
    expect(finder.clips, isFalse);
  });

  testWidgets('switch is not offered while a batch starts', (tester) async {
    final backend = _Backend();
    final controller = _controller(backend);
    addTearDown(controller.dispose);
    await controller.refreshReadiness();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceScreen(
      controller: controller,
      isRefreshing: false,
      onRefresh: () async {},
    ))));
    unawaited(controller.startBatch());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // A running batch replaces the page, so there is no switch to press.
    expect(controller.isBusy, isTrue);
    expect(find.byKey(const ValueKey('live-capture')), findsNothing);
    expect(controller.liveCaptureActive, isFalse);
    backend.monitor.complete(_Monitor());
  });
}

class _Monitor implements ReplayMonitorPort {
  @override
  Future<void> attach() async {}
  @override
  Future<void> close() async {}
  @override
  Future<BattleSnapshot> snapshot() async => const BattleSnapshot.empty();
}

RecorderController _controller(_Backend backend, {FinderPort? finder}) {
  final controller = RecorderController(
    backend: backend,
    finder: finder,
    platformIsLinux: () => true,
    outputPreflight: _ReadyOutput(),
    batchDirectories: BatchOutputDirectory(
        reserveAttempt: (parent, prefix) async => '$parent/test-batch'),
    options: const RecordingOptions(outputDirectory: '/tmp'),
  );
  controller
      .setSetupReport(SetupReport(checkedAt: DateTime.now(), checks: const []));
  return controller;
}

class _ReadyOutput implements OutputDirectoryPreflight {
  @override
  Future<OutputDirectoryReadiness> check(String path) async =>
      const OutputDirectoryReadiness.ready();
}

class _Live implements LiveCapturePort {
  final Completer<String?> _finished = Completer<String?>();
  void Function(int)? onGame;
  void finish(String? directory) => _finished.complete(directory);
  @override
  Future<String?> get finished => _finished.future;
  @override
  Future<void> start(
      {required String outputParent,
      required void Function(int) onGame}) async {
    this.onGame = onGame;
  }

  @override
  Future<void> stop() async {
    if (!_finished.isCompleted) _finished.complete(null);
  }
}

class _Finder implements FinderPort {
  int calls = 0;
  bool? reference;
  bool? clips;
  @override
  bool get available => true;
  @override
  Future<void> startBatch(String batchFolder,
      {bool reference = false, bool clips = true}) async {
    calls++;
    this.reference = reference;
    this.clips = clips;
  }
}

class _Backend
    implements
        NativeRecorderBackend,
        InputModeAwareNativeRecorderBackend,
        FrameCaptureAwareNativeRecorderBackend,
        LiveCaptureAwareNativeRecorderBackend {
  final live = _Live();
  final monitor = Completer<ReplayMonitorPort>();
  @override
  bool get supportsFrameCapture => true;
  @override
  String? get frameCaptureUnsupportedReason => null;
  @override
  Future<LiveCapturePort> openLiveCapture() async => live;
  @override
  Future<NativeBackendReadiness> inspect() async =>
      const NativeBackendReadiness(available: true, detail: 'ready');
  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode mode) => inspect();
  @override
  Future<ReplayMonitorPort> openReplayMonitor() => monitor.future;
  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) =>
      throw StateError('input opened');
  @override
  Future<ObsRecorderPort> openObsRecorder() => throw StateError('OBS opened');
  @override
  Future<OutputOrganizerPort> openOutputOrganizer() =>
      throw StateError('organizer opened');
  @override
  Future<FrameCapturePort> openFrameCapture() =>
      throw StateError('capture opened');
}
