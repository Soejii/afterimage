class ObsWebSocketConfig {
  const ObsWebSocketConfig({
    this.host = '127.0.0.1',
    this.port = 4455,
    this.password = '',
    this.authRequired = false,
    this.sourcePath,
  });

  final String host;
  final int port;

  /// Kept in memory for the lifetime of the client only. Do not log this
  /// object or serialize it into application state.
  final String password;

  final bool authRequired;
  final String? sourcePath;

  Uri get uri => Uri(
        scheme: 'ws',
        host: host,
        port: port,
      );

  @override
  String toString() => 'ObsWebSocketConfig(host: $host, port: $port, '
      'authRequired: $authRequired, sourcePath: $sourcePath)';
}

class ObsConfigDiscoveryResult {
  const ObsConfigDiscoveryResult({
    required this.config,
    required this.searchedPaths,
    required this.diagnostics,
  });

  final ObsWebSocketConfig? config;
  final List<String> searchedPaths;
  final List<String> diagnostics;

  bool get found => config != null;

  String get detail {
    if (config != null) {
      return 'OBS WebSocket configuration found.';
    }
    if (diagnostics.isNotEmpty) {
      return diagnostics.last;
    }
    return 'No OBS WebSocket configuration was found.';
  }
}

class ObsProbeResult {
  const ObsProbeResult({
    required this.ready,
    required this.detail,
    this.config,
  });

  const ObsProbeResult.ready({
    required String detail,
    required ObsWebSocketConfig config,
  }) : this(
          ready: true,
          detail: detail,
          config: config,
        );

  const ObsProbeResult.blocked({
    required String detail,
    ObsWebSocketConfig? config,
  }) : this(
          ready: false,
          detail: detail,
          config: config,
        );

  final bool ready;
  final String detail;
  final ObsWebSocketConfig? config;
}

abstract interface class ObsReadinessProbe {
  Future<ObsProbeResult> probe();
}
