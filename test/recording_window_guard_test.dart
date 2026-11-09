import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/presentation/widgets/recording_window_guard.dart';

void main() {
  testWidgets('close asks while recordings are being saved', (tester) async {
    final controller = RecorderController(backend: _NoopBackend());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingWindowGuard(
          controller: controller,
          notesSaving: true,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    tester
        .state<RecordingWindowGuardState>(
          find.byType(RecordingWindowGuard),
        )
        .onWindowClose();
    await tester.pump();

    expect(find.text('Recordings are still being saved'), findsOneWidget);
    expect(find.text('Close anyway'), findsOneWidget);
    await tester.tap(find.text('Keep open'));
  });
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
