import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/afterimage_app.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/setup_service.dart';

void main() {
  testWidgets('a blocked computer shows one next step, not a batch form',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeSetupService(_lockedReport());

    await tester.pumpWidget(AfterimageApp(setupService: service));
    await tester.pumpAndSettle();

    expect(find.text('AFTERIMAGE'), findsOneWidget);
    expect(find.text('SETUP NEEDED'), findsOneWidget);
    expect(find.byKey(const ValueKey('lead-blocker')), findsOneWidget);
    expect(service.inspectCalls, 1);
  });

  testWidgets('recording is unreachable while a required check is blocked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AfterimageApp(setupService: _FakeSetupService(_lockedReport())),
    );
    await tester.pumpAndSettle();

    // The batch form is not merely disabled while blocked, it is not on
    // screen at all. Start is reachable only from the ready state.
    expect(find.byKey(const ValueKey('start-batch')), findsNothing);
    expect(find.byKey(const ValueKey('replay-count-one')), findsNothing);
  });

  testWidgets('readiness is stated exactly once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AfterimageApp(setupService: _FakeSetupService(_lockedReport())),
    );
    await tester.pumpAndSettle();

    // This guards the defect the single-screen rework existed to fix: the
    // same readiness fact used to be rendered in eight places at once, by
    // eight separate derivations of it.
    expect(find.byKey(const ValueKey('phase-indicator')), findsOneWidget);
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
