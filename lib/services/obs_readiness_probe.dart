import '../domain/obs_models.dart';
import 'obs_config_discovery.dart';
import 'obs_websocket_recorder.dart';

class LocalObsReadinessProbe implements ObsReadinessProbe {
  const LocalObsReadinessProbe({
    this.discovery = const ObsWebSocketConfigDiscovery(),
    this.connectTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 5),
  });

  final ObsWebSocketConfigDiscovery discovery;
  final Duration connectTimeout;
  final Duration requestTimeout;

  @override
  Future<ObsProbeResult> probe() async {
    final discovered = await discovery.discover();
    final config = discovered.config ??
        const ObsWebSocketConfig(
          host: '127.0.0.1',
          port: 4455,
        );

    if (config.authRequired && config.password.isEmpty) {
      return ObsProbeResult.blocked(
        config: config,
        detail:
            'OBS WebSocket authentication is enabled, but its password is missing. In Afterimage Setup, open Connection options and paste the password shown in OBS.',
      );
    }

    final recorder = ObsWebSocketRecorder(
      config,
      connectTimeout: connectTimeout,
      requestTimeout: requestTimeout,
    );
    try {
      await recorder.connect();
      await recorder.assertIdle();
      final source = config.sourcePath == null
          ? 'the default localhost:4455 endpoint'
          : config.sourcePath!;
      return ObsProbeResult.ready(
        config: config,
        detail:
            'OBS WebSocket protocol and authentication are ready at $source.',
      );
    } on ObsAlreadyRecordingException catch (error) {
      return ObsProbeResult.blocked(
        config: config,
        detail: error.message,
      );
    } on ObsAuthenticationException {
      return ObsProbeResult.blocked(
        config: config,
        detail:
            'OBS WebSocket authentication failed. In Afterimage Setup, open Connection options and check the password shown in OBS.',
      );
    } on ObsTimeoutException {
      return ObsProbeResult.blocked(
        config: config,
        detail: 'OBS WebSocket did not answer before the probe timed out.',
      );
    } on ObsClientException {
      return ObsProbeResult.blocked(
        config: config,
        detail:
            'OBS WebSocket protocol check failed. Open OBS and verify its WebSocket server settings.',
      );
    } finally {
      await recorder.close();
    }
  }
}
