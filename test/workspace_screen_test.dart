import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/notes_models.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_blocker.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/presentation/screens/workspace_screen.dart';
import 'package:afterimage/services/notes_repository.dart';

void main() {
  testWidgets('sequence controls stay disabled while recordings are saved',
      (tester) async {
    final controller = _DoneController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceScreen(
            controller: controller,
            notesRepository: NotesRepository(finderDirectory: '/unused'),
            notesSaving: true,
            isRefreshing: false,
            onRefresh: () async {},
            onOpenNotes: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('open-notes'))).onTap,
      isNull,
    );
    expect(find.byKey(const ValueKey('open-notes-from-done')), findsNothing);
  });

  testWidgets('Sequences stays usable while live capture runs', (tester) async {
    final controller = _LiveController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceScreen(
      controller: controller,
      notesRepository: NotesRepository(finderDirectory: '/unused'),
      showNotes: true,
      isRefreshing: false,
      onRefresh: () async {},
    ))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final list = find.byKey(const ValueKey('notes-list-view'));
    expect(list, findsOneWidget);
    final blocking = find.ancestor(
        of: list,
        matching: find.byWidgetPredicate((widget) =>
            (widget is AbsorbPointer && widget.absorbing) ||
            (widget is IgnorePointer && widget.ignoring)));
    expect(blocking, findsNothing);
    expect(find.byKey(const ValueKey('live-capture-view')), findsNothing);
  });

  testWidgets('the Record tab shows the live page while live capture runs',
      (tester) async {
    final controller = _LiveController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkspaceScreen(
      controller: controller,
      isRefreshing: false,
      onRefresh: () async {},
    ))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('live-capture-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-capture-stop')), findsOneWidget);
    expect(find.byKey(const ValueKey('done-view')), findsNothing);
  });

  testWidgets('header tabs switch views and disappear during a batch',
      (tester) async {
    final controller = _DoneController();
    addTearDown(controller.dispose);
    var showingNotes = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return WorkspaceScreen(
          controller: controller,
          notesRepository: NotesRepository(finderDirectory: '/unused'),
          showNotes: showingNotes,
          isRefreshing: false,
          onRefresh: () async {},
          onOpenNotes: (_) => setState(() => showingNotes = true),
          onCloseNotes: () => setState(() => showingNotes = false),
        );
      },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-notes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('notes-list-view')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-notes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('done-view')), findsOneWidget);
    update(() => controller.currentPhase = RecorderPhase.running);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('open-notes')), findsNothing);
    expect(find.byKey(const ValueKey('close-notes')), findsNothing);
  });
}

class _LiveController extends _DoneController {
  @override
  bool get liveCaptureSupported => true;
  @override
  bool get liveCaptureActive => true;
}

class _DoneController extends RecorderController {
  _DoneController() : super(backend: _NoopBackend());

  RecorderPhase currentPhase = RecorderPhase.done;

  @override
  RecorderPhase get phase => currentPhase;

  @override
  ReplayBatchResult? get result => const ReplayBatchResult(
        outcome: ReplayBatchOutcome.completed,
        replays: <ReplayResult>[],
      );

  @override
  String? get finderBatchLabel => 'batch-done';

  @override
  FinderRunInfo? get finderRun => FinderRunInfo.fromJson({'status': 'done'});
}

class _NoopBackend implements NativeRecorderBackend {
  @override
  Future<NativeBackendReadiness> inspect() async =>
      const NativeBackendReadiness(available: false, detail: 'unused');

  @override
  Future<ReplayMonitorPort> openReplayMonitor() => throw UnimplementedError();

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) =>
      throw UnimplementedError();

  @override
  Future<ObsRecorderPort> openObsRecorder() => throw UnimplementedError();

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() =>
      throw UnimplementedError();
}
