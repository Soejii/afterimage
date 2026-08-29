import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/services/obs_config_discovery.dart';

import 'support/obs_test_support.dart';

void main() {
  group('ObsWebSocketConfigDiscovery', () {
    test('lists native Linux and Flatpak Linux candidate paths', () {
      const discovery = ObsWebSocketConfigDiscovery(
        environment: {'HOME': '/home/tester'},
        isWindows: false,
        pathSeparator: '/',
      );

      expect(discovery.paths, [
        '/home/tester/.config/obs-studio/plugin_config/obs-websocket/config.json',
        '/home/tester/.var/app/com.obsproject.Studio/config/obs-studio/plugin_config/obs-websocket/config.json',
      ]);
    });

    test('lists the common Windows roaming config path', () {
      const discovery = ObsWebSocketConfigDiscovery(
        environment: {
          'APPDATA': r'C:\Users\tester\AppData\Roaming',
        },
        isWindows: true,
        pathSeparator: r'\',
      );

      expect(
        discovery.paths.single,
        r'C:\Users\tester\AppData\Roaming\obs-studio\plugin_config\obs-websocket\config.json',
      );
    });

    test('uses the Windows user profile fallback when APPDATA is absent', () {
      const discovery = ObsWebSocketConfigDiscovery(
        environment: {'USERPROFILE': r'C:\Users\tester'},
        isWindows: true,
        pathSeparator: r'\',
      );

      expect(
        discovery.paths.single,
        r'C:\Users\tester\AppData\Roaming\obs-studio\plugin_config\obs-websocket\config.json',
      );
    });

    test('falls back from empty environment paths', () {
      const discovery = ObsWebSocketConfigDiscovery(
        environment: {
          'HOME': '/home/tester',
          'XDG_CONFIG_HOME': '',
        },
        isWindows: false,
        pathSeparator: '/',
      );

      expect(
        discovery.paths.first,
        '/home/tester/.config/obs-studio/plugin_config/obs-websocket/config.json',
      );
    });

    test('skips malformed configs and parses a later valid config', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final malformed = File('${directory.path}/malformed.json');
      final valid = File('${directory.path}/valid.json');
      await malformed.writeAsString('{not-json');
      await valid.writeAsString(
        jsonEncode({
          'server_enabled': true,
          'server_port': '4457',
          'auth_required': true,
          'server_password': 'secret-do-not-log',
        }),
      );

      final result = await ObsWebSocketConfigDiscovery(
        candidatePaths: [malformed.path, valid.path],
      ).discover();

      expect(result.config?.port, 4457);
      expect(result.config?.authRequired, isTrue);
      expect(result.config?.password, 'secret-do-not-log');
      expect(
        result.diagnostics,
        contains('An OBS WebSocket config contained malformed JSON.'),
      );
      expect(result.detail, isNot(contains('secret-do-not-log')));
      expect(result.config.toString(), isNot(contains('secret-do-not-log')));
    });

    test('treats an absent or disabled config as a non-fatal miss', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final disabled = File('${directory.path}/disabled.json');
      await disabled.writeAsString(
        jsonEncode({
          'server_enabled': false,
          'server_port': 4455,
        }),
      );

      final result = await ObsWebSocketConfigDiscovery(
        candidatePaths: [disabled.path, '${directory.path}/missing.json'],
      ).discover();

      expect(result.config, isNull);
      expect(result.found, isFalse);
      expect(result.diagnostics, isNotEmpty);
      expect(result.searchedPaths, hasLength(2));
    });

    test('rejects invalid ports without trying to use them', () async {
      final result = await _discoverSingle({
        'server_enabled': true,
        'server_port': 70000,
      });

      expect(result.config, isNull);
      expect(result.detail, contains('port is invalid'));
    });

    test('rejects invalid authentication values without leaking them',
        () async {
      final result = await _discoverSingle({
        'server_enabled': true,
        'server_port': 4455,
        'auth_required': 'yes',
      });

      expect(result.config, isNull);
      expect(result.detail, contains('auth setting is invalid'));
      expect(result.detail, isNot(contains('yes')));
    });

    test('rejects non-string passwords without logging the value', () async {
      final result = await _discoverSingle({
        'server_enabled': true,
        'server_port': 4455,
        'auth_required': true,
        'server_password': 12345,
      });

      expect(result.config, isNull);
      expect(result.detail, contains('password is invalid'));
      expect(result.detail, isNot(contains('12345')));
    });

    test('preserves an empty authenticated password for the readiness probe',
        () async {
      final result = await _discoverSingle({
        'server_enabled': true,
        'server_port': 4455,
        'auth_required': true,
        'server_password': '',
      });

      expect(result.config?.authRequired, isTrue);
      expect(result.config?.password, isEmpty);
    });
  });
}

Future<dynamic> _discoverSingle(Map<String, Object?> values) async {
  final directory = await createTempDirectory();
  final file = File('${directory.path}/config.json');
  await file.writeAsString(jsonEncode(values));
  final result = await ObsWebSocketConfigDiscovery(
    candidatePaths: [file.path],
  ).discover();
  await directory.delete(recursive: true);
  return result;
}
