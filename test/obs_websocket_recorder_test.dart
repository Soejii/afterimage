import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/obs_models.dart';
import 'package:afterimage/services/obs_websocket_recorder.dart';

import 'support/obs_test_support.dart';

void main() {
  group('ObsWebSocketRecorder', () {
    test('does not release output for moving before OBS has stopped', () async {
      final server = FakeObsServer(autoFinishRecording: false);
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);
      addTearDown(recorder.close);
      await recorder.startRecording();
      var releasedForMoving = false;
      final stopping = recorder.stopRecording().then((output) {
        releasedForMoving = true;
        return output;
      });
      await server.stopRequested.future;
      server.sendRecordEvent('OBS_WEBSOCKET_OUTPUT_STOPPING');
      server.sendRecordEvent('OBS_WEBSOCKET_OUTPUT_STOPPED',
          path: '/other.mkv');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(releasedForMoving, isFalse,
          reason:
              'OBS still owns the recording: StopRecord response must not release output for moving');
      server.finishRecording();
      expect((await stopping).path, '/tmp/afterimage-obs-1.mkv');
    });

    test('accepts the stopped event arriving before the stop response',
        () async {
      final server = FakeObsServer(stopEventBeforeResponse: true);
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);
      addTearDown(recorder.close);
      await recorder.startRecording();
      expect(
          (await recorder.stopRecording()).path, '/tmp/afterimage-obs-1.mkv');
    });
    test('missing stopped event times out without releasing the output',
        () async {
      final server = FakeObsServer(autoFinishRecording: false);
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = ObsWebSocketRecorder(ObsWebSocketConfig(port: port),
          stopTimeout: const Duration(milliseconds: 150));
      addTearDown(recorder.close);
      await recorder.startRecording();
      await expectLater(
          recorder.stopRecording(),
          throwsA(
            isA<ObsTimeoutException>().having((error) => error.message,
                'recovery path', contains('/tmp/afterimage-obs-1.mkv')),
          ));
      expect(recorder.isConnected, isFalse);
    });

    test('completes the unauthenticated OBS v5 recording lifecycle', () async {
      final server = FakeObsServer();
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);
      addTearDown(recorder.close);

      await recorder.connect();
      await recorder.assertIdle();
      await recorder.startRecording();
      final output = await recorder.stopRecording();

      expect(output.path, '/tmp/afterimage-obs-1.mkv');
      expect(server.authVerified, isFalse);
      expect(server.requestTypes, [
        'GetRecordStatus',
        'StartRecord',
        'StopRecord',
      ]);
      expect(
        server.requests
            .map((request) =>
                (request['d'] as Map<String, dynamic>)['requestId'])
            .toList(),
        ['afterimage-1', 'afterimage-2', 'afterimage-3'],
      );
      expect(recorder.isConnected, isTrue);
    });

    test('validates the exact OBS v5 authentication challenge response',
        () async {
      const password = 'memory-only-password';
      final server = FakeObsServer(
        requireAuthentication: true,
        password: password,
      );
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(
        port: port,
        config: ObsWebSocketConfig(
          port: port,
          password: password,
          authRequired: true,
        ),
      );
      addTearDown(recorder.close);

      await recorder.connect();

      expect(server.authVerified, isTrue);
      expect(
        (server.identifyMessage?['d']
            as Map<String, dynamic>)['authentication'],
        server.expectedAuthentication,
      );
      expect(server.identifyMessage.toString(), isNot(contains(password)));
      expect(recorder.isConnected, isTrue);
      expect(recorder.config.toString(), isNot(contains(password)));
    });

    test('does not expose a password when authentication fails', () async {
      const expectedPassword = 'server-only-secret';
      const suppliedPassword = 'wrong-client-secret';
      final server = FakeObsServer(
        requireAuthentication: true,
        password: expectedPassword,
      );
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(
        port: port,
        config: ObsWebSocketConfig(
          port: port,
          password: suppliedPassword,
          authRequired: true,
        ),
      );
      addTearDown(recorder.close);

      final error = await captureError(recorder.connect);

      expect(error, isA<ObsAuthenticationException>());
      expect(error.toString(), isNot(contains(expectedPassword)));
      expect(error.toString(), isNot(contains(suppliedPassword)));
      expect(recorder.config.toString(), isNot(contains(suppliedPassword)));
    });

    test('refuses to take over an OBS recording already in progress', () async {
      final server = FakeObsServer(initiallyRecording: true);
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);
      addTearDown(recorder.close);

      await recorder.connect();

      await expectLater(
        recorder.assertIdle(),
        throwsA(isA<ObsAlreadyRecordingException>()),
      );
      expect(server.requestTypes, ['GetRecordStatus']);
    });

    test('surfaces a rejected OBS request without exposing credentials',
        () async {
      const password = 'must-not-be-logged';
      final server = FakeObsServer(failRequest: 'StartRecord');
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(
        port: port,
        config: ObsWebSocketConfig(port: port, password: password),
      );
      addTearDown(recorder.close);

      await recorder.connect();
      final error = await captureError(recorder.startRecording);

      expect(error, isA<ObsRequestException>());
      expect((error! as ObsRequestException).code, 400);
      expect(error.toString(), isNot(contains(password)));
    });

    test('rejects malformed and unexpected protocol responses', () async {
      final malformedServer = FakeObsServer(
        protocolFault: FakeObsProtocolFault.malformedHello,
      );
      final malformedPort = await malformedServer.start();
      addTearDown(malformedServer.dispose);
      final malformedRecorder = _recorder(port: malformedPort);
      addTearDown(malformedRecorder.close);

      await expectLater(
        malformedRecorder.connect(),
        throwsA(isA<ObsProtocolException>()),
      );

      final unexpectedServer = FakeObsServer(
        protocolFault: FakeObsProtocolFault.unexpectedResponse,
      );
      final unexpectedPort = await unexpectedServer.start();
      addTearDown(unexpectedServer.dispose);
      final unexpectedRecorder = _recorder(port: unexpectedPort);
      addTearDown(unexpectedRecorder.close);
      await unexpectedRecorder.connect();

      await expectLater(
        unexpectedRecorder.assertIdle(),
        throwsA(isA<ObsProtocolException>()),
      );
    });

    test('reports malformed response data as a protocol failure', () async {
      final server = FakeObsServer(
        protocolFault: FakeObsProtocolFault.malformedResponse,
      );
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);
      addTearDown(recorder.close);
      await recorder.connect();

      await expectLater(
        recorder.assertIdle(),
        throwsA(isA<ObsProtocolException>()),
      );
    });

    test('reports a server disconnect while waiting for a response', () async {
      final server = FakeObsServer(disconnectRequest: 'GetRecordStatus');
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);
      addTearDown(recorder.close);

      await recorder.connect();

      await expectLater(
        recorder.assertIdle(),
        throwsA(isA<ObsDisconnectedException>()),
      );
      expect(recorder.isConnected, isFalse);
    });

    test('times out and closes the socket when OBS does not answer', () async {
      final server = FakeObsServer(ignoreRequest: 'StartRecord');
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(
        port: port,
        requestTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(recorder.close);

      await recorder.connect();

      await expectLater(
        recorder.startRecording(),
        throwsA(isA<ObsTimeoutException>()),
      );
      expect(recorder.isConnected, isFalse);
    });

    test('close is explicit, idempotent, and closes the server socket',
        () async {
      final server = FakeObsServer();
      final port = await server.start();
      addTearDown(server.dispose);
      final recorder = _recorder(port: port);

      await recorder.connect();
      await recorder.close();
      await recorder.close();
      await server.waitForSocketClose();

      expect(recorder.isConnected, isFalse);
    });

    test('rejects an explicitly authenticated config without a password',
        () async {
      final recorder = _recorder(
        config: const ObsWebSocketConfig(
          authRequired: true,
        ),
      );

      final error = await captureError(recorder.connect);

      expect(error, isA<ObsAuthenticationException>());
      expect(error.toString(), isNot(contains('password:')));
    });
  });
}

ObsWebSocketRecorder _recorder({
  int port = 4455,
  ObsWebSocketConfig? config,
  Duration requestTimeout = const Duration(seconds: 1),
}) {
  return ObsWebSocketRecorder(
    config ?? ObsWebSocketConfig(port: port),
    connectTimeout: const Duration(seconds: 1),
    requestTimeout: requestTimeout,
  );
}
