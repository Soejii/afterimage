import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/obs_models.dart';
import 'obs_config_discovery.dart';
import 'obs_websocket_recorder.dart';

/// One in-memory connection choice shared by setup, preview and recording.
/// Credentials are never included in preferences, diagnostics or history.
class ObsConnectionService extends ChangeNotifier implements ObsReadinessProbe {
  ObsConnectionService({
    this.discovery = const ObsWebSocketConfigDiscovery(),
    this.fallbackConfig = const ObsWebSocketConfig(),
    ObsWebSocketRecorder Function(ObsWebSocketConfig)? recorderFactory,
  }) : recorderFactory = recorderFactory ?? ObsWebSocketRecorder.new;

  final ObsWebSocketConfigDiscovery discovery;
  final ObsWebSocketConfig? fallbackConfig;
  final ObsWebSocketRecorder Function(ObsWebSocketConfig) recorderFactory;
  ObsWebSocketConfig? _manual;
  ObsProbeResult? _manualError;
  ObsWebSocketConfig? _selected;
  Future<ObsProbeResult>? _pending;
  bool _disposed = false;
  bool isChecking = false;
  ObsProbeResult? result;
  Uint8List? previewBytes;
  String? previewSceneName;
  String? previewError;
  bool get isManual => _manual != null;

  Future<void> connect({String? password, String? port}) async {
    if (isChecking) return;
    if (password != null || port != null) {
      final enteredPort = port?.trim();
      final parsed = int.tryParse(
          enteredPort == null || enteredPort.isEmpty ? '4455' : enteredPort);
      if (parsed == null || parsed < 1 || parsed > 65535) {
        result = const ObsProbeResult.blocked(
          detail: 'Enter the server port shown in OBS, from 1 to 65535.',
        );
        _manualError = result;
        _selected = null;
        _notify();
        return;
      }
      _manualError = null;
      _manual = ObsWebSocketConfig(
        port: parsed,
        password: password ?? '',
        authRequired: password?.isNotEmpty ?? false,
      );
    }
    await probe();
  }

  Future<void> useAutomaticConnection() async {
    if (isChecking) return;
    _manual = null;
    _manualError = null;
    await probe();
  }

  Future<ObsWebSocketConfig> configuration() async {
    final ready = await probe();
    if (!ready.ready || _selected == null) {
      throw ObsConnectionException(ready.detail);
    }
    return _selected!;
  }

  @override
  Future<ObsProbeResult> probe() {
    final pending = _pending;
    if (pending != null) return pending;
    final future = _probe();
    _pending = future;
    return future.whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
  }

  Future<ObsProbeResult> _probe() async {
    isChecking = true;
    _selected = null;
    previewBytes = null;
    previewSceneName = null;
    previewError = null;
    _notify();
    ObsProbeResult? failure;
    try {
      if (_manualError != null) {
        result = _manualError;
        return result!;
      }
      final candidates = _manual != null
          ? [_manual!]
          : [
              ...await discovery.discoverAll(),
              if (fallbackConfig != null) fallbackConfig!
            ];
      for (final config in candidates) {
        final client = recorderFactory(config);
        try {
          await client.connect();
          await client.assertIdle();
          _selected = config;
          result = ObsProbeResult.ready(
            config: config,
            detail: 'Connected to OBS. Check your picture and sound next.',
          );
          return result!;
        } on ObsAlreadyRecordingException {
          // Do not bypass an active OBS session by trying another installation.
          result = ObsProbeResult.blocked(
              config: config,
              detail:
                  'OBS is already recording. Finish that recording in OBS before starting here.');
          return result!;
        } on ObsAuthenticationException {
          failure = ObsProbeResult.blocked(
              config: config,
              detail:
                  'OBS needs its server password. Open Connection options below and paste the password from OBS.');
        } on Object {
          failure ??= const ObsProbeResult.blocked(
              detail:
                  'Open OBS, then enable Tools > WebSocket Server Settings > Enable WebSocket server. Return here and select Connect OBS.');
        } finally {
          await client.close();
        }
      }
      result = failure ??
          const ObsProbeResult.blocked(
              detail: 'Could not connect to OBS. Open OBS and try again.');
      return result!;
    } on Object {
      result = const ObsProbeResult.blocked(
          detail:
              'Could not read the OBS connection. Open Connection options to enter the port and password shown in OBS.');
      return result!;
    } finally {
      isChecking = false;
      _notify();
    }
  }

  Future<void> refreshPreview() async {
    if (isChecking) return;
    final config = _selected;
    if (config == null) {
      previewError = 'Connect OBS before checking the picture.';
      _notify();
      return;
    }
    isChecking = true;
    previewBytes = null;
    previewError = null;
    _notify();
    final client = recorderFactory(config);
    try {
      await client.connect();
      final preview = await client.capturePreview();
      previewBytes = base64Decode(preview.imageBase64);
      previewSceneName = preview.sceneName;
    } on Object {
      previewError =
          'Could not load the OBS picture. Check the OBS preview directly, then try one replay to verify picture and sound.';
    } finally {
      await client.close();
      isChecking = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _manual = null;
    _selected = null;
    super.dispose();
  }
}
