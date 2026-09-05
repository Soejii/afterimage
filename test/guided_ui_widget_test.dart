import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/theme.dart';
import 'package:afterimage/app/afterimage_app.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/presentation/screens/recorder_screen.dart';
import 'package:afterimage/presentation/screens/setup_screen.dart';
import 'package:afterimage/presentation/widgets/obs_connection_card.dart';
import 'package:afterimage/services/setup_service.dart';

void main() {
  testWidgets('setup presents the beginner path in recording order',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AfterimageTheme.dark(),
        home: SetupScreen(
          report: _readyReport(),
          isRefreshing: false,
          errorMessage: null,
          onRefresh: () async {},
          onOpenRecorder: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect OBS'), findsOneWidget);
    expect(find.text('Check picture and sound'), findsOneWidget);
    expect(find.text('Prepare your saved replays'), findsOneWidget);
    expect(find.text('Record your replays'), findsOneWidget);
    expect(find.text('Safe preflight'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'OBS connection form leaves credentials and validation to the service',
      (tester) async {
    String? capturedPassword;
    String? capturedPort;
    await tester.pumpWidget(
      MaterialApp(
        theme: AfterimageTheme.dark(),
        home: Scaffold(
          body: ObsConnectionCard(
            onConnect: ({String? password, String? port}) async {
              capturedPassword = password;
              capturedPort = port;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('obs-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('obs-port')), '4455');
    await tester.enterText(
        find.byKey(const ValueKey('obs-password')), 'secret');
    await tester.tap(find.byKey(const ValueKey('obs-connect')));
    await tester.pump();

    expect(capturedPort, '4455');
    expect(capturedPassword, 'secret');
  });

  testWidgets('custom replay count is visible only when selected',
      (tester) async {
    RecordingOptions? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AfterimageTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) {
            var options = changed ?? const RecordingOptions();
            return Scaffold(
              body: RecorderScreen(
                report: _readyReport(),
                options: options,
                onOptionsChanged: (value) {
                  changed = value;
                  setState(() => options = value);
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('custom-replay-count')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('replay-count-custom')));
    await tester.pump();
    expect(find.byKey(const ValueKey('custom-replay-count')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('custom-replay-count')),
      '12',
    );
    await tester.pump();
    expect(changed?.customReplayCount, 12);
  });

  testWidgets('refreshing setup also refreshes recorder readiness',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _MutableBackend();
    final controller = RecorderController(
      backend: backend,
      options: const RecordingOptions(outputDirectory: '/tmp/captures'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AfterimageApp(
        setupService: _MutableSetupService(backend),
        recorderController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('start-batch')))
          .onPressed,
      isNotNull,
    );

    backend.available = false;
    await tester.tap(find.byKey(const ValueKey('nav-setup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('refresh-checks')));
    await tester.pumpAndSettle();
    expect(controller.readinessFor(InputMode.keyboard)?.available, isFalse);
    expect(controller.canStart, isFalse);
    await tester.tap(find.byKey(const ValueKey('nav-recorder')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('start-batch')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Recorder readiness is still'), findsNothing);
    expect(find.textContaining('backend unavailable'), findsWidgets);
  });
}

class _MutableSetupService implements SetupService {
  const _MutableSetupService(this.backend);

  final _MutableBackend backend;

  @override
  Future<SetupReport> inspect() async => _readyReport(
        keyboardReady: backend.available,
        controllerReady: backend.available,
      );
}

class _MutableBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  bool available = true;

  @override
  Future<NativeBackendReadiness> inspect() async => _readiness;

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async =>
      _readiness;

  NativeBackendReadiness get _readiness => NativeBackendReadiness(
        available: available,
        detail: available ? 'Backend ready.' : 'backend unavailable',
      );

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

SetupReport _readyReport({
  bool keyboardReady = true,
  bool controllerReady = true,
}) {
  return SetupReport(
    checkedAt: DateTime(2026, 9, 5),
    replayCount: 12,
    checks: [
      for (final id in SetupCheckId.values)
        SetupCheck(
          id: id,
          title: id.name,
          detail: id == SetupCheckId.replayLibrary
              ? '12 saved replay files found.'
              : id == SetupCheckId.keyboardInput && !keyboardReady
                  ? 'backend unavailable'
                  : id == SetupCheckId.controllerInput && !controllerReady
                      ? 'backend unavailable'
                      : 'Ready.',
          status: id == SetupCheckId.keyboardInput
              ? keyboardReady
                  ? SetupCheckStatus.ready
                  : SetupCheckStatus.notice
              : id == SetupCheckId.controllerInput
                  ? controllerReady
                      ? SetupCheckStatus.ready
                      : SetupCheckStatus.notice
                  : SetupCheckStatus.ready,
          required: id != SetupCheckId.keyboardInput &&
              id != SetupCheckId.controllerInput,
        ),
    ],
  );
}
