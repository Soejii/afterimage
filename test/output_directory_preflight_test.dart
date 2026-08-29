import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/services/output_directory_preflight.dart';

import 'support/obs_test_support.dart';

void main() {
  group('FileOutputDirectoryPreflight', () {
    test('creates a missing directory and confirms it is writable', () async {
      final parent = await createTempDirectory();
      addTearDown(() => parent.delete(recursive: true));
      final directory = Directory('${parent.path}/captures/new');

      final result =
          await const FileOutputDirectoryPreflight().check(directory.path);

      expect(result.ready, isTrue);
      expect(await directory.exists(), isTrue);
      expect(
        directory
            .listSync()
            .where((entity) => entity.path.contains('.afterimage-write-test')),
        isEmpty,
      );
    });

    test('rejects a path that points to a file', () async {
      final parent = await createTempDirectory();
      addTearDown(() => parent.delete(recursive: true));
      final file = File('${parent.path}/not-a-folder');
      await file.writeAsString('keep me');

      final result =
          await const FileOutputDirectoryPreflight().check(file.path);

      expect(result.ready, isFalse);
      expect(result.detail, contains('not a folder'));
      expect(await file.readAsString(), 'keep me');
    });

    test('rejects an empty destination with an actionable message', () async {
      final result = await const FileOutputDirectoryPreflight().check('  ');

      expect(result.ready, isFalse);
      expect(result.detail, contains('Choose an output folder'));
    });
  });
}
