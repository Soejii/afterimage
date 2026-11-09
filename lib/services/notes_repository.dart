import 'dart:io';

import '../domain/notes_models.dart';

/// Reads the finder's sequence lists and writes the recordings Suji saves.
///
/// Afterimage never writes under the finder's `out/` folder. Recordings go to the
/// batch folder and, when the finder found it, StriveLabs' recordings folder.
class NotesRepository {
  NotesRepository({
    required this.finderDirectory,
    bool Function(int pid)? pidAlive,
  }) : _pidAlive = pidAlive ?? _processAlive;

  static const documentName = 'sequences.json';
  static const batchRecordingsFolder = 'recordings';

  final String finderDirectory;
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
        final file = File(_join(opponentEntity.path, documentName));
        if (!await file.exists()) continue;
        SequenceDocument document;
        try {
          document = SequenceDocument.fromJson(
            decodeObject(await file.readAsString()),
          );
        } on Object {
          // A list from an older or broken run is left out, not shown half-read.
          continue;
        }
        final stat = await file.stat();
        previews.add(
          NotePreview(
            batchLabel: batchLabel,
            opponent: document.opponent.isNotEmpty
                ? document.opponent
                : _basename(opponentEntity.path),
            directoryPath: opponentEntity.path,
            documentPath: file.path,
            cardCount: document.cards.length,
            flaggedCount: document.cards.where((card) => card.flagged).length,
            createdAt: document.createdAt,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
    previews.sort((left, right) {
      final leftDate = left.sortDate;
      final rightDate = right.sortDate;
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

  Future<NoteSequenceData> read(NotePreview preview) async {
    final file = File(preview.documentPath);
    final document =
        SequenceDocument.fromJson(decodeObject(await file.readAsString()));
    return NoteSequenceData(preview: preview, document: document);
  }

  /// Writes [recordings] to `<batch>/recordings/` and, when StriveLabs was found
  /// and its `ue4ss` folder still exists, to StriveLabs' recordings folder.
  Future<RecordingSaveResult> saveRecordings(
    SequenceDocument document,
    List<LabRecording> recordings,
  ) async {
    if (recordings.isEmpty) {
      throw ArgumentError('Nothing to save.');
    }
    for (final recording in recordings) {
      if (!recording.hasSafeFileName) {
        throw FormatException(
          'Refused an unsafe recording file name: ${recording.fileName}',
        );
      }
    }
    if (document.batchFolder.isEmpty) {
      throw StateError('The sequence list does not name its batch folder.');
    }
    final batchFolder = Directory(document.batchFolder);
    if (!await batchFolder.exists()) {
      throw StateError('The batch folder is gone: ${document.batchFolder}');
    }
    if (await _insideFinderOutput(batchFolder.path)) {
      throw StateError(
        "Refused to save into the finder's output folder: ${batchFolder.path}",
      );
    }
    final batchRecordings =
        Directory(_join(document.batchFolder, batchRecordingsFolder));
    await batchRecordings.create(recursive: true);
    // The batch copy comes first and must succeed; StriveLabs is a convenience.
    for (final recording in recordings) {
      await _atomicWrite(
        File(_join(batchRecordings.path, recording.fileName)),
        recording.text,
      );
    }

    String? strivelabsDirectory;
    String? strivelabsError;
    final strivelabsPath = document.strivelabsRecordings;
    if (strivelabsPath != null && strivelabsPath.isNotEmpty) {
      final candidate = Directory(strivelabsPath);
      try {
        if (await candidate.parent.exists()) {
          if (await _insideFinderOutput(candidate.parent.path)) {
            throw StateError(
              "the StriveLabs folder is inside the finder's output folder",
            );
          }
          await candidate.create();
          for (final recording in recordings) {
            await _atomicWrite(
              File(_join(candidate.path, recording.fileName)),
              recording.text,
            );
          }
          strivelabsDirectory = candidate.path;
        }
      } on Object catch (error) {
        strivelabsError = error.toString();
      }
    }
    return RecordingSaveResult(
      batchDirectory: batchRecordings.path,
      strivelabsDirectory: strivelabsDirectory,
      strivelabsError: strivelabsError,
      fileNames: [for (final recording in recordings) recording.fileName],
    );
  }

  /// True when [path] (an existing directory) resolves into the finder's `out/`.
  Future<bool> _insideFinderOutput(String path) async {
    if (!await outDirectory.exists()) return false;
    final root = await outDirectory.resolveSymbolicLinks();
    final target = await Directory(path).resolveSymbolicLinks();
    return target == root ||
        target.startsWith('$root${Platform.pathSeparator}');
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
        message: 'The sequence finder status could not be read: $error',
      );
    }
  }

  Future<void> _atomicWrite(File target, String contents) async {
    final temporary = File(
      '${target.parent.path}${Platform.pathSeparator}'
      '.${_basename(target.path)}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // A leftover hidden temporary file is harmless.
        }
      }
    }
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
