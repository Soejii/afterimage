import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:afterimage/domain/obs_models.dart';

enum FakeObsProtocolFault {
  none,
  malformedHello,
  unexpectedHello,
  malformedResponse,
  unexpectedResponse,
}

class FakeObsServer {
  FakeObsServer({
    this.requireAuthentication = false,
    this.password = '',
    this.initiallyRecording = false,
    this.failRequest,
    this.disconnectRequest,
    this.ignoreRequest,
    this.protocolFault = FakeObsProtocolFault.none,
    this.responses = const {},
    this.autoFinishRecording = true,
    this.stopEventBeforeResponse = false,
  }) : _recording = initiallyRecording;

  final bool requireAuthentication;
  final String password;
  final bool initiallyRecording;
  final String? failRequest;
  final String? disconnectRequest;
  final String? ignoreRequest;
  final FakeObsProtocolFault protocolFault;
  final Map<String, Map<String, Object?>> responses;
  final bool autoFinishRecording;
  final bool stopEventBeforeResponse;
  final stopRequested = Completer<void>();

  void sendRecordEvent(String state, {String? path}) {
    _socket!.add(jsonEncode({
      'op': 5,
      'd': {
        'eventType': 'RecordStateChanged',
        'eventIntent': 64,
        'eventData': {
          'outputState': state,
          'outputActive': false,
          'outputPath': path ?? '/tmp/afterimage-obs-$_stopCount.mkv',
        },
      },
    }));
  }

  void finishRecording() {
    _recording = false;
    sendRecordEvent('OBS_WEBSOCKET_OUTPUT_STOPPED');
  }

  final List<Map<String, dynamic>> requests = [];
  final String salt = 'afterimage-test-salt';
  final String challenge = 'afterimage-test-challenge';
  final Completer<void> _socketClosed = Completer<void>();
  HttpServer? _server;
  WebSocket? _socket;
  bool _recording;
  bool authVerified = false;
  Map<String, dynamic>? identifyMessage;
  int _stopCount = 0;

  List<String> get requestTypes => requests
      .map((request) => (request['d'] as Map<String, dynamic>)['requestType'])
      .cast<String>()
      .toList(growable: false);

  String get expectedAuthentication {
    final secret = base64.encode(
      sha256.convert(utf8.encode(password + salt)).bytes,
    );
    return base64.encode(
      sha256.convert(utf8.encode(secret + challenge)).bytes,
    );
  }

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) {
      unawaited(_accept(request));
    });
    return _server!.port;
  }

  Future<void> waitForSocketClose() {
    return _socketClosed.future;
  }

  Future<void> _accept(HttpRequest request) async {
    WebSocket? socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
      _socket = socket;
      if (protocolFault == FakeObsProtocolFault.malformedHello) {
        socket.add('{not-json');
      } else if (protocolFault == FakeObsProtocolFault.unexpectedHello) {
        socket.add(jsonEncode({'op': 9, 'd': {}}));
      } else {
        socket.add(jsonEncode({
          'op': 0,
          'd': {
            'obsWebSocketVersion': '5.0.0',
            'rpcVersion': 1,
            if (requireAuthentication)
              'authentication': {
                'salt': salt,
                'challenge': challenge,
              },
          },
        }));
      }

      await for (final raw in socket) {
        if (raw is! String) {
          continue;
        }
        final message = jsonDecode(raw) as Map<String, dynamic>;
        if (message['op'] == 1) {
          final data = message['d'] as Map<String, dynamic>;
          identifyMessage = message;
          if (requireAuthentication) {
            authVerified = data['authentication'] == expectedAuthentication;
            if (!authVerified) {
              await socket.close();
              return;
            }
          }
          socket.add(jsonEncode({
            'op': 2,
            'd': {'negotiatedRpcVersion': 1},
          }));
          continue;
        }
        if (message['op'] != 6) {
          continue;
        }

        final data = message['d'] as Map<String, dynamic>;
        final requestType = data['requestType'] as String;
        requests.add(message);
        if (disconnectRequest == requestType) {
          await socket.close();
          return;
        }
        if (ignoreRequest == requestType) {
          continue;
        }
        if (protocolFault == FakeObsProtocolFault.malformedResponse) {
          socket.add(jsonEncode({
            'op': 7,
            'd': {
              'requestId': data['requestId'],
              'requestStatus': 'not-an-object',
            },
          }));
          continue;
        }
        if (protocolFault == FakeObsProtocolFault.unexpectedResponse) {
          socket.add(jsonEncode({'op': 4, 'd': {}}));
          continue;
        }
        if (failRequest == requestType) {
          _respond(
            socket,
            data,
            result: false,
            code: 400,
          );
          continue;
        }

        if (responses.containsKey(requestType)) {
          _respond(socket, data, responseData: responses[requestType]);
          continue;
        }
        switch (requestType) {
          case 'GetRecordStatus':
            _respond(
              socket,
              data,
              responseData: {'outputActive': _recording},
            );
          case 'StartRecord':
            _recording = true;
            _respond(socket, data);
          case 'StopRecord':
            _stopCount++;
            if (autoFinishRecording && stopEventBeforeResponse) {
              finishRecording();
            }
            _respond(
              socket,
              data,
              responseData: {
                'outputPath': '/tmp/afterimage-obs-$_stopCount.mkv',
              },
            );
            if (autoFinishRecording && !stopEventBeforeResponse) {
              finishRecording();
            }
            if (!stopRequested.isCompleted) stopRequested.complete();
          default:
            _respond(socket, data);
        }
      }
    } catch (_) {
      // The server intentionally closes sockets for failure cases.
    } finally {
      if (!_socketClosed.isCompleted) {
        _socketClosed.complete();
      }
    }
  }

  void _respond(
    WebSocket socket,
    Map<String, dynamic> request, {
    bool result = true,
    int? code,
    Map<String, Object?>? responseData,
  }) {
    socket.add(jsonEncode({
      'op': 7,
      'd': {
        'requestType': request['requestType'],
        'requestId': request['requestId'],
        'requestStatus': {
          'result': result,
          if (code != null) 'code': code,
        },
        if (responseData != null) 'responseData': responseData,
      },
    }));
  }

  Future<void> dispose() async {
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {}
    await _server?.close(force: true);
    _server = null;
    if (!_socketClosed.isCompleted) {
      _socketClosed.complete();
    }
  }
}

Future<Directory> createTempDirectory() {
  return Directory.systemTemp.createTemp('afterimage-test-');
}

Future<Object?> captureError<T>(Future<T> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  return null;
}

class FakeObsProbe implements ObsReadinessProbe {
  const FakeObsProbe(this.result);

  final ObsProbeResult result;

  @override
  Future<ObsProbeResult> probe() async => result;
}
