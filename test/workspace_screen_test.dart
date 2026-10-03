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
  testWidgets('notes controls stay disabled while a card is being edited',
      (tester) async {
    final controller = _DoneController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceScreen(
            controller: controller,
            notesRepository: NotesRepository(finderDirectory: '/unused'),
            notesEditing: true,
            isRefreshing: false,
            onRefresh: () async {},
            onOpenNotes: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('open-notes')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('open-notes-from-done')), findsNothing);
  });
}

class _DoneController extends RecorderController {
  _DoneController() : super(backend: _NoopBackend());

  @override
  RecorderPhase get phase => RecorderPhase.done;

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
