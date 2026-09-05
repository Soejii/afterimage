import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/afterimage_app.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/setup_service.dart';

void main() {
  testWidgets('setup screen explains the self-contained locked preview',
      (tester) async {
    final service = _FakeSetupService(_lockedReport());
    await tester.pumpWidget(AfterimageApp(setupService: service));
    await tester.pumpAndSettle();

    expect(find.text('AFTERIMAGE'), findsOneWidget);
    expect(find.text('Workspace setup'), findsOneWidget);
    expect(find.text('Native recorder backend'), findsOneWidget);
    expect(find.textContaining('No Python install is needed'), findsWidgets);
    expect(find.text('Recording locked'), findsOneWidget);
    expect(service.inspectCalls, 1);
  });

  testWidgets('start batch remains disabled while a required check is blocked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AfterimageApp(setupService: _FakeSetupService(_lockedReport())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();

    expect(find.text('Safe preflight'), findsOneWidget);
    expect(find.textContaining('Native recorder backend'), findsWidgets);
    final startButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start-batch')),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('recorder choices update without unlocking the start action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AfterimageApp(setupService: _FakeSetupService(_lockedReport())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();

    final one = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('replay-count-one')),
    );
    expect(one.selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('replay-count-twenty')));
    await tester.pump();

    final twenty = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('replay-count-twenty')),
    );
    expect(twenty.selected, isTrue);
    final startButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start-batch')),
    );
    expect(startButton.onPressed, isNull);
  });
}

class _FakeSetupService implements SetupService {
  _FakeSetupService(this.report);

  final SetupReport report;
  int inspectCalls = 0;

  @override
  Future<SetupReport> inspect() async {
    inspectCalls++;
    return report;
  }
}

SetupReport _lockedReport() {
  return SetupReport(
    checkedAt: DateTime(2026, 8, 29),
    checks: [
      const SetupCheck(
        id: SetupCheckId.supportedPlatform,
        title: 'Supported desktop OS',
        detail: 'Linux is supported.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      const SetupCheck(
        id: SetupCheckId.runtime,
        title: 'Self-contained runtime',
        detail: 'No Python install is needed.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      const SetupCheck(
        id: SetupCheckId.gameInstall,
        title: 'GGST installation',
        detail: 'Found.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      const SetupCheck(
        id: SetupCheckId.gameRunning,
        title: 'GGST process',
        detail: 'Running.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      const SetupCheck(
        id: SetupCheckId.obsWebSocket,
        title: 'OBS WebSocket port',
        detail: 'Port open.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      const SetupCheck(
        id: SetupCheckId.replayLibrary,
        title: 'Replay library',
        detail: '5 files found.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      const SetupCheck(
        id: SetupCheckId.keyboardInput,
        title: 'Keyboard input',
        detail: 'Not ported.',
        status: SetupCheckStatus.notice,
        required: false,
      ),
      const SetupCheck(
        id: SetupCheckId.controllerInput,
        title: 'Virtual controller',
        detail: 'Not available.',
        status: SetupCheckStatus.notice,
        required: false,
      ),
      const SetupCheck(
        id: SetupCheckId.nativeRecorderBackend,
        title: 'Native recorder backend',
        detail: 'Blocked until ported.',
        status: SetupCheckStatus.blocked,
        required: true,
      ),
    ],
  );
}
