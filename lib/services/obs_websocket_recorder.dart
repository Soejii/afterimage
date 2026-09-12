import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/obs_models.dart';
import '../domain/recorder_contracts.dart';
import '../domain/replay_batch.dart';

class ObsClientException implements Exception {
  const ObsClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ObsConnectionException extends ObsClientException {
  const ObsConnectionException(super.message);
}

class ObsDisconnectedException extends ObsClientException {
  const ObsDisconnectedException(super.message);
}

class ObsProtocolException extends ObsClientException {
  const ObsProtocolException(super.message);
}

class ObsAuthenticationException extends ObsClientException {
  const ObsAuthenticationException(super.message);
}

class ObsAlreadyRecordingException extends ObsClientException {
  const ObsAlreadyRecordingException()
      : super('OBS is already recording. Stop it before starting a batch.');
}

class ObsRequestException extends ObsClientException {
  const ObsRequestException({
    required this.requestType,
    required this.code,
  }) : super('OBS rejected request $requestType (code $code).');

  final String requestType;
  final int? code;
}

class ObsTimeoutException extends ObsClientException {
  const ObsTimeoutException(super.message);
}

class ObsCapturePreview {
  const ObsCapturePreview(this.sceneName, this.imageBase64);
  final String sceneName;
  final String imageBase64;
}

class ObsWebSocketRecorder implements ObsRecorderPort {
  ObsWebSocketRecorder(
    this.config, {
    this.connectTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 2),
    this.stopTimeout = const Duration(seconds: 30),
  });

  final ObsWebSocketConfig config;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration closeTimeout;
  final Duration stopTimeout;
  String? _stoppingOutputPath;

  WebSocket? _socket;
  StreamIterator<dynamic>? _messages;
  Future<void>? _connection;
  Future<void> _requestTail = Future<void>.value();
  int _requestNumber = 0;
  bool _identified = false;

  bool get isConnected => _identified && _socket != null;

  /// Read-only snapshot of the current program scene, never changes OBS scenes.
  Future<ObsCapturePreview> capturePreview() async {
    final scene = await _request('GetCurrentProgramScene');
    final name = scene['currentProgramSceneName'] ?? scene['sceneName'];
    if (name is! String || name.isEmpty) {
      throw const ObsProtocolException(
          'OBS did not provide its current scene.');
    }
    final response = await _request('GetSourceScreenshot', {
      'sourceName': name,
      'imageFormat': 'png',
      'imageWidth': 960,
    });
    final data = response['imageData'];
    const prefix = 'data:image/png;base64,';
    if (data is! String || !data.startsWith(prefix) || data.length > 8000000) {
      throw const ObsProtocolException(
          'OBS returned an invalid preview image.');
    }
    final encoded = data.substring(prefix.length);
    final decoded = base64Decode(encoded);
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (decoded.length < 8 ||
        List.generate(8, (index) => index)
            .any((index) => decoded[index] != signature[index])) {
      throw const ObsProtocolException('OBS returned an invalid PNG image.');
    }
    return ObsCapturePreview(name, encoded);
  }

  @override
  Future<void> connect() async {
    if (isConnected) {
      return;
    }
    final connection = _connection;
    if (connection != null) {
      await connection;
      return;
    }

    final attempt = _connectInternal();
    _connection = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_connection, attempt)) {
        _connection = null;
      }
    }
  }

  Future<void> _connectInternal() async {
    _validateConfig();
    if (config.authRequired && config.password.isEmpty) {
      throw const ObsAuthenticationException(
        'OBS WebSocket authentication is enabled, but no password is configured.',
      );
    }

    var serverRequestedAuthentication = false;
    try {
      final connecting = WebSocket.connect(config.uri.toString());
      final socket = await connecting.timeout(
        connectTimeout,
        onTimeout: () {
          // Future.timeout does not cancel the underlying socket handshake.
          // Close a socket that completes after the timeout so a late
          // connection cannot leak outside this client.
          unawaited(_closeLateSocket(connecting));
          throw const ObsTimeoutException(
            'Timed out connecting to OBS WebSocket.',
          );
        },
      );
      _socket = socket;
      _messages = StreamIterator<dynamic>(socket);

      final hello = await _readMessageWithTimeout('OBS Hello');
      final helloData = _mapValue(hello['d'], 'Hello data');
      final helloAuth = helloData['authentication'];
      final identifyData = <String, Object?>{
        'rpcVersion': _rpcVersion(helloData['rpcVersion']),
        // RecordStateChanged confirms that OBS has finished closing its output.
        'eventSubscriptions': 64,
      };
      if (helloAuth != null) {
        serverRequestedAuthentication = true;
        final auth = _mapValue(helloAuth, 'Hello authentication data');
        final salt = _stringValue(auth['salt'], 'Hello salt');
        final challenge = _stringValue(auth['challenge'], 'Hello challenge');
        if (config.password.isEmpty) {
          throw const ObsAuthenticationException(
            'OBS WebSocket requires a password. Add it to the OBS connection settings.',
          );
        }
        identifyData['authentication'] = _authentication(
          password: config.password,
          salt: salt,
          challenge: challenge,
        );
      }
      if (_intValue(hello['op']) != 0) {
        throw const ObsProtocolException('OBS did not send a Hello message.');
      }

      await _sendMessage({'op': 1, 'd': identifyData});
      while (true) {
        final response = await _readMessageWithTimeout('OBS Identify response');
        final operation = _intValue(response['op']);
        if (operation == 2) {
          _identified = true;
          return;
        }
        if (operation == 5) {
          continue;
        }
        if (operation == 8) {
          throw const ObsDisconnectedException(
            'OBS closed the WebSocket during identification.',
          );
        }
        throw const ObsProtocolException(
          'OBS did not confirm the WebSocket identification.',
        );
      }
    } catch (error, stackTrace) {
      await _closeInternal();
      if (serverRequestedAuthentication && error is ObsDisconnectedException) {
        Error.throwWithStackTrace(
          const ObsAuthenticationException(
            'OBS WebSocket authentication failed. Check the configured password.',
          ),
          stackTrace,
        );
      }
      if (error is ObsClientException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw const ObsConnectionException(
          'Could not establish the OBS WebSocket connection.');
    }
  }

  @override
  Future<void> assertIdle() async {
    final response = await _request('GetRecordStatus');
    if (response['outputActive'] == true) {
      throw const ObsAlreadyRecordingException();
    }
  }

  @override
  Future<void> startRecording() async {
    await _request('StartRecord');
  }

  @override
  Future<RecordedOutput> stopRecording() async {
    final response = await _request('StopRecord');
    final outputPath = response['outputPath'];
    if (outputPath is! String || outputPath.trim().isEmpty) {
      throw const ObsProtocolException(
        'OBS stopped recording without returning an output path.',
      );
    }
    return RecordedOutput(outputPath);
  }

  @override
  Future<void> close() async {
    final connection = _connection;
    if (connection != null) {
      try {
        await connection;
      } catch (_) {
        // The caller that started the connection owns its primary error.
      }
    }
    await _closeInternal();
  }

  Future<void> dispose() => close();

  Future<Map<String, dynamic>> _request(
    String requestType, [
    Map<String, Object?> requestData = const <String, Object?>{},
  ]) async {
    final previous = _requestTail;
    final release = Completer<void>();
    _requestTail = release.future;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed request must not permanently poison the request queue.
      }
      await connect();
      if (requestType == 'StopRecord') _stoppingOutputPath = null;
      try {
        return await _requestUnserialized(requestType, requestData).timeout(
          requestType == 'StopRecord' ? stopTimeout : requestTimeout,
          onTimeout: () => throw ObsTimeoutException(
            'Timed out waiting for OBS request $requestType.'
            '${requestType == 'StopRecord' ? _stopRecoveryDetail : ''}',
          ),
        );
      } catch (error, stackTrace) {
        if (error is ObsTimeoutException || error is ObsDisconnectedException) {
          await _closeInternal();
        }
        if (requestType == 'StopRecord' && error is ObsDisconnectedException) {
          Error.throwWithStackTrace(
              ObsDisconnectedException('${error.message}$_stopRecoveryDetail'),
              stackTrace);
        }
        if (error is ObsClientException) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        throw const ObsConnectionException('The OBS WebSocket request failed.');
      }
    } finally {
      release.complete();
    }
  }

  String get _stopRecoveryDetail =>
      ' Recording completion was not confirmed; no output was moved. '
      'Check OBS${_stoppingOutputPath == null ? '.' : ' and $_stoppingOutputPath.'}';

  Future<Map<String, dynamic>> _requestUnserialized(
    String requestType,
    Map<String, Object?> requestData,
  ) async {
    final requestId = 'afterimage-${++_requestNumber}';
    await _sendMessage({
      'op': 6,
      'd': {
        'requestType': requestType,
        'requestId': requestId,
        'requestData': requestData,
      },
    });

    Map<String, dynamic>? stopResponse;
    final stoppedPaths = <String>{};
    while (true) {
      final message = await _readMessage();
      final operation = _intValue(message['op']);
      if (operation == 5) {
        if (requestType == 'StopRecord') {
          final event = message['d'];
          if (event is Map && event['eventType'] == 'RecordStateChanged') {
            final data = event['eventData'];
            if (data is Map &&
                data['outputState'] == 'OBS_WEBSOCKET_OUTPUT_STOPPED' &&
                data['outputPath'] is String) {
              stoppedPaths.add(data['outputPath'] as String);
            }
          }
          if (stopResponse != null &&
              stoppedPaths.contains(stopResponse['outputPath'])) {
            return stopResponse;
          }
        }
        continue;
      }
      if (operation != 7) {
        throw const ObsProtocolException('OBS sent an unexpected response.');
      }
      final data = _mapValue(message['d'], 'OBS response data');
      if (data['requestId'] != requestId) {
        continue;
      }
      final status = _mapValue(data['requestStatus'], 'OBS request status');
      if (status['result'] != true) {
        throw ObsRequestException(
          requestType: requestType,
          code: _nullableInt(status['code']),
        );
      }
      final responseData = data['responseData'];
      if (responseData == null) {
        return <String, dynamic>{};
      }
      final response = _mapValue(responseData, 'OBS response data');
      if (requestType == 'StopRecord' &&
          response['outputPath'] is String &&
          (response['outputPath'] as String).trim().isNotEmpty) {
        _stoppingOutputPath = response['outputPath'] as String;
        if (!stoppedPaths.contains(_stoppingOutputPath)) {
          stopResponse = response;
          continue;
        }
      }
      return response;
    }
  }

  Future<Map<String, dynamic>> _readMessageWithTimeout(String operation) async {
    try {
      return await _readMessage().timeout(
        requestTimeout,
        onTimeout: () => throw ObsTimeoutException(
          'Timed out waiting for $operation.',
        ),
      );
    } on ObsClientException {
      rethrow;
    } catch (_) {
      throw ObsDisconnectedException('$operation was interrupted.');
    }
  }

  Future<Map<String, dynamic>> _readMessage() async {
    final messages = _messages;
    if (messages == null) {
      throw const ObsDisconnectedException('OBS WebSocket is not connected.');
    }
    try {
      if (!await messages.moveNext()) {
        throw const ObsDisconnectedException('OBS closed the WebSocket.');
      }
      return _decodeMessage(messages.current);
    } on ObsClientException {
      rethrow;
    } catch (_) {
      throw const ObsDisconnectedException(
          'OBS closed the WebSocket unexpectedly.');
    }
  }

  Future<void> _sendMessage(Map<String, Object?> message) async {
    final socket = _socket;
    if (socket == null || !_identified && message['op'] != 1) {
      throw const ObsDisconnectedException('OBS WebSocket is not connected.');
    }
    try {
      socket.add(jsonEncode(message));
    } catch (_) {
      throw const ObsDisconnectedException('OBS WebSocket rejected a message.');
    }
  }

  Future<void> _closeInternal() async {
    final messages = _messages;
    final socket = _socket;
    _messages = null;
    _socket = null;
    _identified = false;

    if (socket != null) {
      try {
        await socket.close().timeout(closeTimeout);
      } catch (_) {
        // A dead socket is already safe to discard.
      }
    }
    if (messages != null) {
      try {
        await messages.cancel().timeout(closeTimeout);
      } catch (_) {
        // A cancelled stream must not hide the recording result.
      }
    }
  }

  Map<String, dynamic> _decodeMessage(Object? raw) {
    late final dynamic decoded;
    try {
      decoded = switch (raw) {
        String value => jsonDecode(value),
        List<int> value => jsonDecode(utf8.decode(value)),
        _ => throw const ObsProtocolException('OBS sent a non-text message.'),
      };
    } on FormatException {
      throw const ObsProtocolException('OBS sent malformed JSON.');
    }
    if (decoded is! Map) {
      throw const ObsProtocolException('OBS sent a non-object message.');
    }
    try {
      return Map<String, dynamic>.from(decoded);
    } on TypeError {
      throw const ObsProtocolException('OBS sent an invalid object.');
    }
  }

  Map<String, dynamic> _mapValue(Object? value, String field) {
    if (value is! Map) {
      throw ObsProtocolException('OBS sent invalid $field.');
    }
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw ObsProtocolException('OBS sent invalid $field.');
    }
  }

  Future<void> _closeLateSocket(Future<WebSocket> connecting) async {
    try {
      final socket = await connecting;
      await socket.close();
    } catch (_) {
      // A failed handshake has no socket to close.
    }
  }

  String _stringValue(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw ObsProtocolException('OBS sent invalid $field.');
    }
    return value;
  }

  int _rpcVersion(Object? value) {
    final version = _nullableInt(value);
    if (version == null || version < 1) {
      throw const ObsProtocolException('OBS sent an invalid RPC version.');
    }
    return version;
  }

  int _intValue(Object? value) {
    final result = _nullableInt(value);
    if (result == null) {
      throw const ObsProtocolException('OBS sent an invalid operation code.');
    }
    return result;
  }

  int? _nullableInt(Object? value) {
    return switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
  }

  String _authentication({
    required String password,
    required String salt,
    required String challenge,
  }) {
    final secret = base64.encode(
      sha256.convert(utf8.encode(password + salt)).bytes,
    );
    return base64.encode(
      sha256.convert(utf8.encode(secret + challenge)).bytes,
    );
  }

  void _validateConfig() {
    if (config.host.trim().isEmpty ||
        config.port < 1 ||
        config.port > 65535 ||
        connectTimeout <= Duration.zero ||
        requestTimeout <= Duration.zero ||
        closeTimeout <= Duration.zero) {
      throw const ObsConnectionException(
          'OBS WebSocket connection settings are invalid.');
    }
  }
}
