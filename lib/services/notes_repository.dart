import 'dart:io';

import '../domain/notes_models.dart';

class NotesProcessResult {
  const NotesProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef NotesProcessRunner = Future<NotesProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Reads finder output and owns the only writes Afterimage makes under `out/`.
class NotesRepository {
  NotesRepository({
    required this.finderDirectory,
    NotesProcessRunner? processRunner,
    bool Function(int pid)? pidAlive,
  })  : _processRunner = processRunner ?? _runProcess,
        _pidAlive = pidAlive ?? _processAlive;

  final String finderDirectory;
  final NotesProcessRunner _processRunner;
  final bool Function(int pid) _pidAlive;

  Directory get outDirectory => Directory(_join(finderDirectory, 'out'));

  String runDirectory(String batchLabel) =>
      _join(_join(finderDirectory, 'out'), batchLabel);

  String runLogPath(String batchLabel) =>
      _join(runDirectory(batchLabel), 'run.log');

  Future<List<NotePreview>> list() async {
    if (!await outDirectory.exists()) return const <NotePreview>[];
    final previews = <NotePreview>[];
    await for (final batchEntity in outDirectory.list(followLinks: false)) {
      if (batchEntity is! Directory) continue;
      final batchLabel = _basename(batchEntity.path);
      await for (final opponentEntity in batchEntity.list(followLinks: false)) {
        if (opponentEntity is! Directory) continue;
        final section = File(_join(opponentEntity.path, 'section.md'));
        if (!await section.exists()) continue;
        final sectionText = await section.readAsString();
        final document = splitNoteSection(sectionText);
        final metadata = await _readMetadata(opponentEntity);
        final stat = await section.stat();
        previews.add(
          NotePreview(
            batchLabel: batchLabel,
            opponent: metadata?.opponent.isNotEmpty == true
                ? metadata!.opponent
                : _basename(opponentEntity.path),
            directoryPath: opponentEntity.path,
            sectionPath: section.path,
            metadata: metadata,
            cardCount: document.cards.length,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
    previews.sort((left, right) {
      if (left.isLegacy != right.isLegacy) {
        return left.isLegacy ? 1 : -1;
      }
      final leftDate = left.createdAt;
      final rightDate = right.createdAt;
      if (leftDate == null && rightDate != null) return 1;
      if (leftDate != null && rightDate == null) return -1;
      if (leftDate != null && rightDate != null) {
        final comparison = rightDate.compareTo(leftDate);
        if (comparison != 0) return comparison;
      }
      final batch = right.batchLabel.compareTo(left.batchLabel);
      if (batch != 0) return batch;
      return left.opponent.compareTo(right.opponent);
    });
    return previews;
  }

  Future<NoteSectionData> read(NotePreview preview) async {
    final section = File(preview.sectionPath);
    final document = splitNoteSection(await section.readAsString());
    final warningsFile = File(_join(preview.directoryPath, 'warnings.txt'));
    final warnings = await warningsFile.exists()
        ? (await warningsFile.readAsLines())
            .where((line) => line.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final clipsFile = File(
      _join(_join(preview.directoryPath, 'clips'), 'index.json'),
    );
    ClipIndex? clipIndex;
    if (await clipsFile.exists()) {
      try {
        clipIndex =
            ClipIndex.fromJson(decodeObject(await clipsFile.readAsString()));
      } on Object {
        // A broken clip index should not hide the editable notes.
      }
    }
    return NoteSectionData(
      preview: preview,
      document: document,
      warnings: warnings,
      clipIndex: clipIndex,
    );
  }

  Future<NotePreview?> refreshPreview(NotePreview preview) async {
    final previews = await list();
    for (final candidate in previews) {
      if (candidate.sectionPath == preview.sectionPath) return candidate;
    }
    return null;
  }

  /// Saves the whole section after making the one-time original backup.
  Future<void> write(NotePreview preview, NoteSectionDocument document) async {
    final target = File(preview.sectionPath);
    if (!await target.exists()) {
      throw StateError('The notes draft is no longer on disk.');
    }
    final original = File(_join(preview.directoryPath, 'section.orig.md'));
    if (!await original.exists()) {
      await target.copy(original.path);
    }
    await _atomicWrite(target, document.toMarkdown());
  }

  Future<ApplySectionResult> apply(NotePreview preview) async {
    final script =
        File(_join(_join(finderDirectory, 'scripts'), 'apply_section.py'));
    if (!await script.exists()) {
      return ApplySectionResult.fromExitCode(
        1,
        opponent: preview.opponent,
        stderr: 'The notes apply script is not available.',
      );
    }
    try {
      final result = await _processRunner(
        '/usr/bin/python3',
        <String>[script.path, preview.directoryPath],
      );
      return ApplySectionResult.fromExitCode(
        result.exitCode,
        opponent: preview.opponent,
        stderr: result.stderr,
      );
    } on Object catch (error) {
      return ApplySectionResult.fromExitCode(
        1,
        opponent: preview.opponent,
        stderr: error.toString(),
      );
    }
  }

  Future<FinderRunInfo?> readRun(String batchLabel) async {
    final file = File(_join(runDirectory(batchLabel), 'run.json'));
    if (!await file.exists()) return null;
    try {
      final json = decodeObject(await file.readAsString());
      return FinderRunInfo.fromJson(json, isPidAlive: _pidAlive);
    } on Object catch (error) {
      return FinderRunInfo(
        state: FinderRunState.failed,
        pid: null,
        batchFolder: null,
        startedAt: null,
        finishedAt: null,
        opponents: const <FinderOpponentRun>[],
        message: 'The notes status could not be read: $error',
      );
    }
  }

  Future<NoteMetadata?> _readMetadata(Directory directory) async {
    final file = File(_join(directory.path, 'meta.json'));
    if (!await file.exists()) return null;
    try {
      return NoteMetadata.fromJson(decodeObject(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  Future<void> _atomicWrite(File target, String contents) async {
    final temporary = File(
      '${target.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsString(contents, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
      final backup = File(
        '${target.path}.bak-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      await target.rename(backup.path);
      try {
        await temporary.rename(target.path);
        try {
          await backup.delete();
        } on FileSystemException {
          // The replacement is valid. Keep a recoverable backup if cleanup is blocked.
        }
      } on Object {
        try {
          await backup.rename(target.path);
        } on Object {
          // The old file remains at the backup path for manual recovery.
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Keep a failed temporary document for recovery.
        }
      }
    }
  }

  static Future<NotesProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return NotesProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  static bool _processAlive(int processId) =>
      Platform.isLinux && Directory('/proc/$processId').existsSync();

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}

String _join(String base, String child) {
  if (base.endsWith('/') || base.endsWith('\\')) return '$base$child';
  return '$base${Platform.pathSeparator}$child';
}
