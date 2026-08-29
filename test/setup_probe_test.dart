import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/obs_models.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/obs_config_discovery.dart';
import 'package:afterimage/services/obs_readiness_probe.dart';
import 'package:afterimage/services/setup_service.dart';

import 'support/obs_test_support.dart';

void main() {
  group('LocalObsReadinessProbe', () {
    test('blocks a configured authenticated server with no password', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final configFile = File('${directory.path}/config.json');
      await configFile.writeAsString(
        jsonEncode({
          'server_enabled': true,
          'server_port': 4455,
          'auth_required': true,
          'server_password': '',
        }),
      );

      final result = await LocalObsReadinessProbe(
        discovery: ObsWebSocketConfigDiscovery(
          candidatePaths: [configFile.path],
        ),
      ).probe();

      expect(result.ready, isFalse);
      expect(result.detail, contains('password'));
    });

    test('does not treat a raw open TCP port as OBS readiness', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..close();
      });
      addTearDown(() => server.close(force: true));
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final configFile = File('${directory.path}/config.json');
      await configFile.writeAsString(
        jsonEncode({
          'server_enabled': true,
          'server_port': server.port,
          'auth_required': false,
        }),
      );

      final result = await LocalObsReadinessProbe(
        discovery: ObsWebSocketConfigDiscovery(
          candidatePaths: [configFile.path],
        ),
        connectTimeout: const Duration(milliseconds: 300),
        requestTimeout: const Duration(milliseconds: 300),
      ).probe();

      expect(result.ready, isFalse);
      expect(result.detail, contains('protocol'));
    });

    test('keeps malformed OBS protocol responses blocked', () async {
      final server = FakeObsServer(
        protocolFault: FakeObsProtocolFault.malformedHello,
      );
      final port = await server.start();
      addTearDown(server.dispose);
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final configFile = File('${directory.path}/config.json');
      await configFile.writeAsString(
        jsonEncode({
          'server_enabled': true,
          'server_port': port,
          'auth_required': false,
        }),
      );

      final result = await LocalObsReadinessProbe(
        discovery: ObsWebSocketConfigDiscovery(
          candidatePaths: [configFile.path],
        ),
        connectTimeout: const Duration(seconds: 1),
        requestTimeout: const Duration(milliseconds: 300),
      ).probe();

      expect(result.ready, isFalse);
      expect(result.detail, contains('protocol'));
    });

    test('keeps authentication failures blocked without exposing passwords',
        () async {
      const expectedPassword = 'server-password';
      const suppliedPassword = 'wrong-password';
      final server = FakeObsServer(
        requireAuthentication: true,
        password: expectedPassword,
      );
      final port = await server.start();
      addTearDown(server.dispose);
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final configFile = File('${directory.path}/config.json');
      await configFile.writeAsString(
        jsonEncode({
          'server_enabled': true,
          'server_port': port,
          'auth_required': true,
          'server_password': suppliedPassword,
        }),
      );

      final result = await LocalObsReadinessProbe(
        discovery: ObsWebSocketConfigDiscovery(
          candidatePaths: [configFile.path],
        ),
        connectTimeout: const Duration(seconds: 1),
        requestTimeout: const Duration(milliseconds: 300),
      ).probe();

      expect(result.ready, isFalse);
      expect(result.detail, contains('authentication'));
      expect(result.detail, isNot(contains(expectedPassword)));
      expect(result.detail, isNot(contains(suppliedPassword)));
    });
  });

  test('LocalSetupService keeps OBS blocked when its probe is blocked',
      () async {
    const service = LocalSetupService(
      obsProbe: FakeObsProbe(
        ObsProbeResult.blocked(
          detail: 'OBS WebSocket authentication requires a password.',
        ),
      ),
    );

    final report = await service.inspect();
    final obsCheck = report.checkFor(SetupCheckId.obsWebSocket);

    expect(obsCheck?.status, SetupCheckStatus.blocked);
    expect(obsCheck?.detail, contains('password'));
  });

  test('LocalSetupService publishes native and controller readiness', () async {
    const service = LocalSetupService(
      obsProbe: FakeObsProbe(
        ObsProbeResult.blocked(detail: 'OBS is closed.'),
      ),
      nativeBackend: _ReadyNativeBackend(),
    );

    final report = await service.inspect();

    expect(
      report.checkFor(SetupCheckId.nativeRecorderBackend)?.status,
      SetupCheckStatus.ready,
    );
    expect(
      report.checkFor(SetupCheckId.keyboardInput)?.detail,
      'Keyboard backend ready.',
    );
    expect(
      report.checkFor(SetupCheckId.controllerInput)?.status,
      SetupCheckStatus.notice,
    );
    expect(
      report.checkFor(SetupCheckId.controllerInput)?.detail,
      'Virtual controller unavailable.',
    );
  });

  test('LocalSetupService continues past an empty replay root', () async {
    final emptyRoot = await createTempDirectory();
    final populatedRoot = await createTempDirectory();
    addTearDown(() => emptyRoot.delete(recursive: true));
    addTearDown(() => populatedRoot.delete(recursive: true));
    await File('${populatedRoot.path}/REP001.sav').writeAsBytes([1, 2, 3]);

    final service = LocalSetupService(
      obsProbe: const FakeObsProbe(
        ObsProbeResult.blocked(detail: 'OBS is closed.'),
      ),
      replayRootCandidates: [emptyRoot.path, populatedRoot.path],
    );

    final report = await service.inspect();
    final replayCheck = report.checkFor(SetupCheckId.replayLibrary);

    expect(report.replayCount, 1);
    expect(replayCheck?.status, SetupCheckStatus.ready);
    expect(replayCheck?.value, populatedRoot.path);
    expect(replayCheck?.detail, contains('1 REP###.sav file found'));
  });
}

class _ReadyNativeBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  const _ReadyNativeBackend();

  @override
  Future<NativeBackendReadiness> inspect() async =>
      const NativeBackendReadiness(
        available: true,
        detail: 'Keyboard backend ready.',
      );

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async =>
      inputMode == InputMode.keyboard
          ? const NativeBackendReadiness(
              available: true,
              detail: 'Keyboard backend ready.',
            )
          : const NativeBackendReadiness(
              available: false,
              detail: 'Virtual controller unavailable.',
            );

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) =>
      throw UnimplementedError();

  @override
  Future<ObsRecorderPort> openObsRecorder() => throw UnimplementedError();

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() =>
      throw UnimplementedError();

  @override
  Future<ReplayMonitorPort> openReplayMonitor() => throw UnimplementedError();
}
