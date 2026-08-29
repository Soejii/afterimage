import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/replay_summary.dart';
import 'package:afterimage/services/summary_writer.dart';

import 'support/obs_test_support.dart';

void main() {
  group('FileSummaryWriter', () {
    test('writes incremental valid JSON with result paths and errors',
        () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final writer = FileSummaryWriter();
      addTearDown(writer.close);
      const first = ReplayResult(
        index: 1,
        status: ReplayResultStatus.recorded,
        sourceOutput: RecordedOutput('/tmp/obs-1.mkv'),
        output: OrganizedOutput(
          path: '/captures/replay_001.mkv',
          partial: false,
          replayIndex: 1,
        ),
      );
      final second = ReplayResult(
        index: 2,
        status: ReplayResultStatus.failed,
        sourceOutput: const RecordedOutput('/tmp/obs-2.mkv'),
        error: StateError('monitor stopped'),
      );

      await writer.write(
        outputDirectory: directory.path,
        summary: ReplayBatchSummary.fromResults(
          updatedAt: DateTime(2026, 8, 29),
          outcome: ReplaySummaryOutcome.running,
          replays: [first],
        ),
      );
      final summaryFile = File('${directory.path}/summary.json');
      final firstJson =
          jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
      expect(firstJson['schemaVersion'], 1);
      expect(firstJson['outcome'], 'running');
      expect((firstJson['replays'] as List<dynamic>), hasLength(1));
      expect((firstJson['replays'] as List<dynamic>).single['output'],
          '/captures/replay_001.mkv');

      await writer.write(
        outputDirectory: directory.path,
        summary: ReplayBatchSummary.fromResults(
          updatedAt: DateTime(2026, 8, 29, 0, 0, 1),
          outcome: ReplaySummaryOutcome.failed,
          replays: [first, second],
          combinedSourceOutput: const RecordedOutput('/tmp/combined.mkv'),
          error: StateError('batch stopped safely'),
        ),
      );
      final secondText = await summaryFile.readAsString();
      final secondJson = jsonDecode(secondText) as Map<String, dynamic>;
      expect(secondJson['outcome'], 'failed');
      expect(secondJson['combinedSource'], '/tmp/combined.mkv');
      expect(secondJson['error'], contains('batch stopped safely'));
      final entries = secondJson['replays'] as List<dynamic>;
      expect(entries, hasLength(2));
      expect(entries[1]['source'], '/tmp/obs-2.mkv');
      expect(entries[1]['status'], 'failed');
      expect(entries[1]['error'], contains('monitor stopped'));
      expect(secondText, isNot(contains('memory-only-password')));
      expect(_temporaryFiles(directory), isEmpty);
    });

    test('restores the last valid summary when replacement fails', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final targetPath = '${directory.path}/summary.json';
      final initialSummary = ReplayBatchSummary.fromResults(
        updatedAt: DateTime(2026, 8, 29),
        outcome: ReplaySummaryOutcome.running,
        replays: const [
          ReplayResult(
            index: 1,
            status: ReplayResultStatus.recorded,
            sourceOutput: RecordedOutput('/tmp/old.mkv'),
          ),
        ],
      );
      var failedReplacements = 0;
      var injectFailure = false;
      Future<File> renameWithFailure(File source, String destinationPath) {
        if (injectFailure &&
            destinationPath == targetPath &&
            source.path.contains('.tmp-')) {
          failedReplacements++;
          if (failedReplacements <= 2) {
            throw const FileSystemException('simulated replacement failure');
          }
        }
        return source.rename(destinationPath);
      }

      final writer = FileSummaryWriter(rename: renameWithFailure);
      addTearDown(writer.close);
      await writer.write(
        outputDirectory: directory.path,
        summary: initialSummary,
      );
      injectFailure = true;
      final error = await captureError(
        () => writer.write(
          outputDirectory: directory.path,
          summary: ReplayBatchSummary.fromResults(
            updatedAt: DateTime(2026, 8, 29, 0, 0, 2),
            outcome: ReplaySummaryOutcome.completed,
            replays: const [
              ReplayResult(
                index: 1,
                status: ReplayResultStatus.recorded,
                sourceOutput: RecordedOutput('/tmp/new.mkv'),
              ),
            ],
          ),
        ),
      );

      expect(error, isA<SummaryWriteException>());
      expect(error.toString(), contains('previous summary was restored'));
      final restored = jsonDecode(await File(targetPath).readAsString())
          as Map<String, dynamic>;
      expect(restored['outcome'], 'running');
      expect((restored['replays'] as List<dynamic>).single['source'],
          '/tmp/old.mkv');
      expect(_temporaryFiles(directory), isNotEmpty);
      expect(error.toString(), isNot(contains('memory-only-password')));
    });

    test('keeps a recoverable backup if restoration also fails', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final targetPath = '${directory.path}/summary.json';
      final initialSummary = ReplayBatchSummary.fromResults(
        updatedAt: DateTime(2026, 8, 29),
        outcome: ReplaySummaryOutcome.running,
        replays: const [],
      );

      var injectFailure = false;
      Future<File> alwaysFailReplacement(File source, String destinationPath) {
        if (injectFailure &&
            (destinationPath == targetPath || source.path.contains('.bak-'))) {
          throw const FileSystemException('simulated replacement failure');
        }
        return source.rename(destinationPath);
      }

      final writer = FileSummaryWriter(rename: alwaysFailReplacement);
      addTearDown(writer.close);
      await writer.write(
        outputDirectory: directory.path,
        summary: initialSummary,
      );
      injectFailure = true;

      final error = await captureError(
        () => writer.write(
          outputDirectory: directory.path,
          summary: ReplayBatchSummary.fromResults(
            updatedAt: DateTime(2026, 8, 29),
            outcome: ReplaySummaryOutcome.failed,
            replays: const [],
          ),
        ),
      );

      expect(error, isA<SummaryWriteException>());
      expect(error.toString(), contains('previous summary is preserved'));
      final backups = directory
          .listSync()
          .where((entity) => entity.uri.pathSegments.last.contains('.bak-'));
      expect(backups, hasLength(1));
      expect(await File(backups.single.path).readAsString(),
          contains('"outcome": "running"'));
    });

    test('does not overwrite an unrelated pre-existing summary', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final targetPath = '${directory.path}/summary.json';
      await File(targetPath).writeAsString('{"owner":"another-tool"}\n');

      final error = await captureError(
        () => FileSummaryWriter().write(
          outputDirectory: directory.path,
          summary: ReplayBatchSummary.fromResults(
            updatedAt: DateTime(2026, 8, 29),
            outcome: ReplaySummaryOutcome.completed,
            replays: const [],
          ),
        ),
      );

      expect(error, isA<SummaryOwnershipException>());
      expect(error.toString(), contains('unrelated summary.json'));
      expect(
          await File(targetPath).readAsString(), '{"owner":"another-tool"}\n');
      expect(_temporaryFiles(directory), isEmpty);
    });

    test('a new batch can replace an Afterimage-owned summary', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final targetPath = '${directory.path}/summary.json';
      final firstWriter = FileSummaryWriter(batchId: 'first-batch');
      final secondWriter = FileSummaryWriter(batchId: 'second-batch');
      addTearDown(secondWriter.close);

      await firstWriter.write(
        outputDirectory: directory.path,
        summary: ReplayBatchSummary.fromResults(
          updatedAt: DateTime(2026, 8, 29),
          outcome: ReplaySummaryOutcome.completed,
          replays: const [],
        ),
      );
      await firstWriter.close();
      await secondWriter.write(
        outputDirectory: directory.path,
        summary: ReplayBatchSummary.fromResults(
          updatedAt: DateTime(2026, 8, 30),
          outcome: ReplaySummaryOutcome.running,
          replays: const [],
        ),
      );

      final decoded = jsonDecode(await File(targetPath).readAsString())
          as Map<String, dynamic>;
      expect(decoded['outcome'], 'running');
      expect(
        (decoded['afterimageWriter'] as Map<String, dynamic>)['batchId'],
        'second-batch',
      );
    });

    test('rejects a concurrent writer for the same output directory', () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final firstWriter = FileSummaryWriter(batchId: 'active-batch');
      final secondWriter = FileSummaryWriter(batchId: 'competing-batch');
      addTearDown(firstWriter.close);
      addTearDown(secondWriter.close);
      final summary = ReplayBatchSummary.fromResults(
        updatedAt: DateTime(2026, 8, 29),
        outcome: ReplaySummaryOutcome.running,
        replays: const [],
      );

      await firstWriter.write(
        outputDirectory: directory.path,
        summary: summary,
      );
      final error = await captureError(
        () => secondWriter.write(
          outputDirectory: directory.path,
          summary: summary,
        ),
      );

      expect(error, isA<SummaryOwnershipException>());
      expect(error.toString(), contains('Another Afterimage batch'));
    });

    test('reports a directory failure without replacing an existing file',
        () async {
      final directory = await createTempDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final blockedParent = File('${directory.path}/blocked-parent');
      await blockedParent.writeAsString('not a directory');

      final error = await captureError(
        () => FileSummaryWriter().write(
          outputDirectory: '${blockedParent.path}/nested',
          summary: ReplayBatchSummary.fromResults(
            updatedAt: DateTime(2026, 8, 29),
            outcome: ReplaySummaryOutcome.failed,
            replays: const [],
          ),
        ),
      );

      expect(error, isA<SummaryWriteException>());
      expect(error.toString(), contains('summary directory'));
      expect(await blockedParent.readAsString(), 'not a directory');
    });
  });
}

Iterable<FileSystemEntity> _temporaryFiles(Directory directory) {
  return directory.listSync().where((entity) {
    final name = entity.uri.pathSegments.last;
    return name.contains('.tmp-') || name.contains('.bak-');
  });
}
