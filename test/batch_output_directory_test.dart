import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/services/batch_output_directory.dart';
import 'package:afterimage/services/output_organizer.dart';

import 'support/obs_test_support.dart';

void main() {
  group('BatchOutputDirectory', () {
    test('reserves a new child directory for every batch', () async {
      final parent = await createTempDirectory();
      addTearDown(() => parent.delete(recursive: true));
      final service = BatchOutputDirectory(
        now: () => DateTime(2026, 9, 5, 12, 30, 40, 123, 456),
      );

      final first = await service.reserve(parent.path);
      final second = await service.reserve(parent.path);

      expect(first.path, isNot(second.path));
      expect(await Directory(first.path).exists(), isTrue);
      expect(await Directory(second.path).exists(), isTrue);
      expect(
        await File('${first.path}/.afterimage-batch.json').exists(),
        isFalse,
      );
    });

    test('retries when an injected reservation factory reports a collision',
        () async {
      final parent = await createTempDirectory();
      addTearDown(() => parent.delete(recursive: true));
      var attempts = 0;
      final prefixes = <String>[];

      final service = BatchOutputDirectory(
        now: () => DateTime(2026, 9, 5),
        reserveAttempt: (parent, prefix) async {
          attempts++;
          prefixes.add(prefix);
          if (attempts == 1) {
            return null;
          }
          return (await Directory(parent).createTemp(prefix)).path;
        },
      );
      final reservation = await service.reserve(parent.path);

      expect(attempts, 2);
      expect(prefixes, hasLength(2));
      expect(prefixes.first, isNot(prefixes.last));
      expect(reservation.name, startsWith('batch_20260905'));
      expect(await Directory(reservation.path).exists(), isTrue);
    });

    test('rejects an empty output parent', () async {
      final service = BatchOutputDirectory();

      expect(
        () => service.reserve('  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('keeps organizer filenames separate across reserved batches',
        () async {
      final parent = await createTempDirectory();
      addTearDown(() => parent.delete(recursive: true));
      final batches = BatchOutputDirectory(
        now: () => DateTime(2026, 9, 5, 12, 30, 40, 123, 456),
      );
      const organizer = FileOutputOrganizer();
      final outputs = <OrganizedOutput>[];

      for (var batch = 1; batch <= 2; batch++) {
        final reservation = await batches.reserve(parent.path);
        final source = File('${parent.path}/obs-capture.mp4');
        await source.writeAsString('batch $batch');
        outputs.add(
          await organizer.organizeReplay(
            source: RecordedOutput(source.path),
            outputDirectory: reservation.path,
            replayIndex: 1,
            partial: false,
          ),
        );
      }

      expect(outputs.map((output) => output.path), hasLength(2));
      expect(outputs[0].path, isNot(outputs[1].path));
      expect(
        outputs
            .map((output) => File(output.path).uri.pathSegments.last)
            .toList(),
        ['replay_001.mp4', 'replay_001.mp4'],
      );
      expect(await File(outputs[0].path).readAsString(), 'batch 1');
      expect(await File(outputs[1].path).readAsString(), 'batch 2');
    });
  });
}
