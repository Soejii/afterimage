import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:afterimage/services/obs_connection_service.dart';
import 'package:afterimage/services/obs_config_discovery.dart';
import 'support/obs_test_support.dart';

void main() {
  test('automatic connection tries active OBS after stale credentials',
      () async {
    final stale =
        FakeObsServer(requireAuthentication: true, password: 'old-secret');
    final live = FakeObsServer();
    final stalePort = await stale.start();
    final livePort = await live.start();
    addTearDown(stale.dispose);
    addTearDown(live.dispose);
    final directory =
        await Directory.systemTemp.createTemp('afterimage-obs-discovery-');
    addTearDown(() => directory.delete(recursive: true));
    final paths = <String>[];
    for (final port in [stalePort, livePort]) {
      final path = '${directory.path}/$port.json';
      paths.add(path);
      await File(path).writeAsString(jsonEncode({
        'server_enabled': true,
        'server_port': port,
        'auth_required': port == stalePort,
        'server_password': 'wrong-secret',
      }));
    }
    final service = ObsConnectionService(
        discovery: ObsWebSocketConfigDiscovery(candidatePaths: paths),
        fallbackConfig: null);
    addTearDown(service.dispose);
    final result = await service.probe();
    expect(result.ready, isTrue,
        reason:
            'The active second OBS configuration must be tried after stale credentials');
    expect(result.config?.port, livePort);
    expect(stale.requestTypes, isEmpty);
    expect(live.requestTypes, ['GetRecordStatus']);
  });

  test('invalid manual port stays blocked until explicitly corrected',
      () async {
    final service = ObsConnectionService(fallbackConfig: null);
    addTearDown(service.dispose);
    await service.connect(port: '70000', password: 'private');
    expect(service.result?.ready, isFalse);
    final refreshed = await service.probe();
    expect(refreshed.ready, isFalse);
    expect(refreshed.detail, contains('1 to 65535'));
    expect(refreshed.detail, isNot(contains('private')));
  });

  test('manual password connects without exposing the password', () async {
    final server =
        FakeObsServer(requireAuthentication: true, password: 'session-secret');
    final port = await server.start();
    addTearDown(server.dispose);
    final service = ObsConnectionService(fallbackConfig: null);
    addTearDown(service.dispose);
    await service.connect(port: '$port', password: 'session-secret');
    expect(service.result?.ready, isTrue);
    expect(server.authVerified, isTrue);
    expect(service.result?.detail, isNot(contains('session-secret')));
    expect(
        service.result?.config.toString(), isNot(contains('session-secret')));
  });

  test('preview is read-only and identifies the current program scene',
      () async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6l1sAAAAASUVORK5CYII=';
    final server = FakeObsServer(responses: {
      'GetCurrentProgramScene': {'currentProgramSceneName': 'GGST capture'},
      'GetSourceScreenshot': {'imageData': 'data:image/png;base64,$png'},
    });
    final port = await server.start();
    addTearDown(server.dispose);
    final service = ObsConnectionService(fallbackConfig: null);
    addTearDown(service.dispose);
    await service.connect(port: '$port');
    await service.refreshPreview();
    expect(service.previewSceneName, 'GGST capture');
    expect(service.previewBytes, isNotEmpty);
    expect(server.requestTypes,
        ['GetRecordStatus', 'GetCurrentProgramScene', 'GetSourceScreenshot']);
  });

  test('active recording blocks instead of trying another OBS installation',
      () async {
    final server = FakeObsServer(initiallyRecording: true);
    final port = await server.start();
    addTearDown(server.dispose);
    final service = ObsConnectionService(fallbackConfig: null);
    addTearDown(service.dispose);
    await service.connect(port: '$port');
    expect(service.result?.ready, isFalse);
    expect(service.result?.detail, contains('already recording'));
    expect(server.requestTypes, ['GetRecordStatus']);
  });
}
