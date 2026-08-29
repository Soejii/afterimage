import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/services/output_organizer.dart';

import 'support/obs_test_support.dart';

void main() {
  group('FileOutputOrganizer', () {
    test('creates nested complete replay output and preserves its extension',
        () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/obs-capture.MKV');
      await source.writeAsString('video');
      final outputDirectory = '${directory.path}/captures/nested';

      final output = await const FileOutputOrganizer().organizeReplay(
        source: RecordedOutput(source.path),
        outputDirectory: outputDirectory,
        replayIndex: 1,
        partial: false,
      );

      expect(File(output.path).uri.pathSegments.last, 'replay_001.MKV');
      expect(await File(output.path).readAsString(), 'video');
      expect(await Directory(outputDirectory).exists(), isTrue);
      expect(await source.exists(), isFalse);
      expect(output.partial, isFalse);
    });

    test('uses a distinct partial replay name', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/obs-capture.mp4');
      await source.writeAsString('partial replay');

      final output = await const FileOutputOrganizer().organizeReplay(
        source: RecordedOutput(source.path),
        outputDirectory: directory.path,
        replayIndex: 12,
        partial: true,
      );

      expect(File(output.path).uri.pathSegments.last, 'replay_012_partial.mp4');
      expect(await File(output.path).readAsString(), 'partial replay');
      expect(output.partial, isTrue);
    });

    test('uses complete and partial combined names', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final completeSource = File('${directory.path}/combined.webm');
      await completeSource.writeAsString('complete');
      final complete = await const FileOutputOrganizer().organizeCombined(
        source: RecordedOutput(completeSource.path),
        outputDirectory: directory.path,
        partial: false,
      );

      final partialSource = File('${directory.path}/combined-2');
      await partialSource.writeAsString('partial');
      final partial = await const FileOutputOrganizer().organizeCombined(
        source: RecordedOutput(partialSource.path),
        outputDirectory: directory.path,
        partial: true,
      );

      expect(
          File(complete.path).uri.pathSegments.last, 'replays_combined.webm');
      expect(File(partial.path).uri.pathSegments.last,
          'replays_combined_partial.mp4');
      expect(await completeSource.exists(), isFalse);
      expect(await partialSource.exists(), isFalse);
    });

    test('defaults an extensionless OBS output to mp4', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/obs-capture');
      await source.writeAsString('video');

      final output = await const FileOutputOrganizer().organizeReplay(
        source: RecordedOutput(source.path),
        outputDirectory: directory.path,
        replayIndex: 3,
        partial: false,
      );

      expect(File(output.path).uri.pathSegments.last, 'replay_003.mp4');
    });

    test('refuses a destination collision and leaves both files unchanged',
        () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/obs-capture.mp4');
      final destination = File('${directory.path}/replay_001.mp4');
      await source.writeAsString('new');
      await destination.writeAsString('existing');

      await expectLater(
        const FileOutputOrganizer().organizeReplay(
          source: RecordedOutput(source.path),
          outputDirectory: directory.path,
          replayIndex: 1,
          partial: false,
        ),
        throwsA(isA<OutputOrganizationException>()),
      );
      expect(await source.readAsString(), 'new');
      expect(await destination.readAsString(), 'existing');
    });

    test('reports a missing source without fabricating output', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final missing = '${directory.path}/missing.mp4';

      final error = await captureError(
        () => const FileOutputOrganizer().organizeReplay(
          source: RecordedOutput(missing),
          outputDirectory: directory.path,
          replayIndex: 4,
          partial: true,
        ),
      );

      expect(error, isA<OutputOrganizationException>());
      expect((error! as OutputOrganizationException).sourcePath, missing);
      expect(await File(missing).exists(), isFalse);
      expect(await File('${directory.path}/replay_004_partial.mp4').exists(),
          isFalse);
    });

    test('keeps source when the destination cannot be created', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/obs-capture.mp4');
      await source.writeAsString('recover me');
      final blockedParent = File('${directory.path}/blocked-parent');
      await blockedParent.writeAsString('not a directory');
      final outputDirectory = '${blockedParent.path}/nested';

      final error = await captureError(
        () => const FileOutputOrganizer().organizeReplay(
          source: RecordedOutput(source.path),
          outputDirectory: outputDirectory,
          replayIndex: 5,
          partial: true,
        ),
      );

      expect(error, isA<OutputOrganizationException>());
      expect(await source.exists(), isTrue);
      expect(await source.readAsString(), 'recover me');
      expect(
        await File('$outputDirectory/replay_005_partial.mp4').exists(),
        isFalse,
      );
    });
  });
}
