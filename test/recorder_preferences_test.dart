import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/services/recorder_preferences.dart';

import 'support/obs_test_support.dart';

void main() {
  group('RecorderPreferences', () {
    test('allowlists recording options and never writes credentials', () async {
      final writes = <Map<String, Object?>>[];
      final preferences = RecorderPreferences(
        write: (values) async => writes.add(values),
      );

      await preferences.save({
        'outputDirectory': '/captures',
        'gameDirectory': '/games/ggst',
        'replayDirectory': '/games/ggst/Saved/Replays',
        'recentOutputs': ['/captures/batch_1/replay_001.mp4'],
        'recentOutputDirectory': '/captures/batch_1',
        'inputMode': 'keyboard',
        'replayCount': 'one',
        'customReplayCount': 1,
        'videoMode': 'separate',
        'password': 'must not persist',
        'obsWebSocketPassword': 'must not persist',
      });

      expect(writes, hasLength(1));
      expect(writes.single, {
        'outputDirectory': '/captures',
        'gameDirectory': '/games/ggst',
        'replayDirectory': '/games/ggst/Saved/Replays',
        'recentOutputs': ['/captures/batch_1/replay_001.mp4'],
        'recentOutputDirectory': '/captures/batch_1',
        'inputMode': 'keyboard',
        'replayCount': 'one',
        'customReplayCount': 1,
        'videoMode': 'separate',
      });
    });

    test('serializes saves and preserves the latest selection order', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final writes = <Map<String, Object?>>[];
      final preferences = RecorderPreferences(
        write: (values) async {
          writes.add(values);
          if (writes.length == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
        },
      );

      final first = preferences.save({'replayCount': 'one'});
      await firstStarted.future;
      final second = preferences.save({'replayCount': 'custom'});
      expect(writes, [
        <String, Object?>{'replayCount': 'one'},
      ]);

      releaseFirst.complete();
      await Future.wait([first, second]);

      expect(writes, [
        <String, Object?>{'replayCount': 'one'},
        <String, Object?>{'replayCount': 'custom'},
      ]);
    });

    test('load falls back when storage is unavailable', () async {
      final preferences = RecorderPreferences(
        read: () async => throw const FileSystemException('locked'),
      );

      expect(await preferences.load(), isNull);
    });
  });

  group('FileRecorderPreferencesStore', () {
    test('returns null for a malformed preferences document', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/preferences.json');
      await file.writeAsString('{not-json');

      expect(await FileRecorderPreferencesStore(filePath: file.path).read(),
          isNull);
    });

    test('writes and reads a JSON document atomically', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/nested/preferences.json');
      final store = FileRecorderPreferencesStore(filePath: file.path);

      await store.write({'replayCount': 'one', 'customReplayCount': 1});

      expect(await store.read(), {
        'replayCount': 'one',
        'customReplayCount': 1,
      });
      expect(await file.exists(), isTrue);
      expect(
        await Directory(file.parent.path)
            .list()
            .where((entity) => entity.path.contains('.tmp-'))
            .toList(),
        isEmpty,
      );
    });
  });

  group('recorderPreferencesPath', () {
    test('uses APPDATA on Windows', () {
      expect(
        recorderPreferencesPath(
          isWindows: true,
          environment: {'APPDATA': r'C:\Users\Suji\AppData\Roaming'},
        ),
        r'C:\Users\Suji\AppData\Roaming\afterimage\preferences.json',
      );
    });

    test('uses XDG_CONFIG_HOME on Linux', () {
      expect(
        recorderPreferencesPath(
          isWindows: false,
          environment: {'XDG_CONFIG_HOME': '/home/suji/.config'},
        ),
        '/home/suji/.config/afterimage/preferences.json',
      );
    });

    test('uses a file below the working directory when app data is absent', () {
      expect(
        recorderPreferencesPath(
          isWindows: false,
          environment: const <String, String>{},
        ),
        endsWith('/.afterimage/preferences.json'),
      );
    });
  });
}
