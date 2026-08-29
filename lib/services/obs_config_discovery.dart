import 'dart:convert';
import 'dart:io';

import '../domain/obs_models.dart';

class ObsWebSocketConfigDiscovery {
  const ObsWebSocketConfigDiscovery({
    this.environment,
    this.isWindows,
    this.homeDirectory,
    this.candidatePaths,
    this.pathSeparator,
  });

  final Map<String, String>? environment;
  final bool? isWindows;
  final String? homeDirectory;
  final Iterable<String>? candidatePaths;
  final String? pathSeparator;

  List<String> get paths {
    final supplied = candidatePaths;
    if (supplied != null) {
      return _unique(supplied);
    }

    final env = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;
    final separator = pathSeparator ?? Platform.pathSeparator;
    final home = _firstNonEmpty([
      homeDirectory,
      env['HOME'],
      env['USERPROFILE'],
    ]);
    const suffix = [
      'obs-studio',
      'plugin_config',
      'obs-websocket',
      'config.json',
    ];

    if (windows) {
      final appData = _firstNonEmpty([
        env['APPDATA'],
        _join(home, ['AppData', 'Roaming'], separator),
      ]);
      return _unique([
        _join(appData, suffix, separator),
      ]);
    }

    final configHome = _firstNonEmpty([
      env['XDG_CONFIG_HOME'],
      _join(home, ['.config'], separator),
    ]);
    return _unique([
      _join(configHome, suffix, separator),
      _join(
        home,
        [
          '.var',
          'app',
          'com.obsproject.Studio',
          'config',
          ...suffix,
        ],
        separator,
      ),
    ]);
  }

  Future<ObsConfigDiscoveryResult> discover() async {
    final searched = <String>[];
    final diagnostics = <String>[];

    for (final path in paths) {
      if (path.isEmpty) {
        continue;
      }
      searched.add(path);
      final file = File(path);
      try {
        if (!await file.exists()) {
          continue;
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          diagnostics.add('An OBS WebSocket config was not a JSON object.');
          continue;
        }
        final values = Map<String, dynamic>.from(decoded);
        final config = _parse(values, path, diagnostics);
        if (config != null) {
          return ObsConfigDiscoveryResult(
            config: config,
            searchedPaths: List.unmodifiable(searched),
            diagnostics: List.unmodifiable(diagnostics),
          );
        }
      } on FileSystemException {
        diagnostics.add('An OBS WebSocket config could not be read.');
      } on FormatException {
        diagnostics.add('An OBS WebSocket config contained malformed JSON.');
      }
    }

    return ObsConfigDiscoveryResult(
      config: null,
      searchedPaths: List.unmodifiable(searched),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  ObsWebSocketConfig? _parse(
    Map<String, dynamic> values,
    String sourcePath,
    List<String> diagnostics,
  ) {
    if (values['server_enabled'] != true) {
      diagnostics.add('OBS WebSocket is disabled in the discovered config.');
      return null;
    }

    final port = _port(values['server_port']);
    if (port == null) {
      diagnostics.add('The discovered OBS WebSocket port is invalid.');
      return null;
    }

    final authValue = values['auth_required'];
    if (authValue != null && authValue is! bool) {
      diagnostics.add('The discovered OBS WebSocket auth setting is invalid.');
      return null;
    }
    final authRequired = authValue == true;
    final passwordValue = values['server_password'];
    if (passwordValue != null && passwordValue is! String) {
      diagnostics.add('The discovered OBS WebSocket password is invalid.');
      return null;
    }

    return ObsWebSocketConfig(
      port: port,
      password: passwordValue as String? ?? '',
      authRequired: authRequired,
      sourcePath: sourcePath,
    );
  }

  int? _port(Object? value) {
    final port = switch (value) {
      int value => value,
      String value => int.tryParse(value),
      _ => null,
    };
    if (port == null || port < 1 || port > 65535) {
      return null;
    }
    return port;
  }

  List<String> _unique(Iterable<String> values) {
    return values.where((value) => value.isNotEmpty).toSet().toList();
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _join(String base, List<String> parts, String separator) {
    if (base.isEmpty) {
      return '';
    }
    var result = base;
    for (final part in parts) {
      if (result.endsWith(separator)) {
        result += part;
      } else {
        result += '$separator$part';
      }
    }
    return result;
  }
}
