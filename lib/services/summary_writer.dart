import 'dart:convert';
import 'dart:io';

import '../domain/recorder_contracts.dart';
import '../domain/replay_summary.dart';

typedef SummaryFileRename = Future<File> Function(
  File source,
  String destinationPath,
);

class SummaryWriteException implements Exception {
  const SummaryWriteException({
    required this.message,
    required this.targetPath,
    required this.temporaryPath,
  });

  final String message;
  final String targetPath;
  final String temporaryPath;

  @override
  String toString() => '$message Temporary summary remains at $temporaryPath.';
}

class SummaryOwnershipException extends SummaryWriteException {
  const SummaryOwnershipException({
    required super.message,
    required super.targetPath,
    required super.temporaryPath,
  });

  @override
  String toString() => message;
}

class FileSummaryWriter implements ClosableSummaryWriterPort {
  FileSummaryWriter({
    this.fileName = 'summary.json',
    SummaryFileRename? rename,
    String? batchId,
  })  : _rename = rename ?? _renameWithIo,
        _batchId = batchId ?? _newBatchId();

  final String fileName;
  final SummaryFileRename _rename;
  final String _batchId;
  int _writeNumber = 0;
  static int _batchNumber = 0;
  static final Set<String> _claimedLockPaths = <String>{};
  RandomAccessFile? _lockHandle;
  String? _claimedLockPath;
  bool _hasWritten = false;
  bool _closed = false;

  @override
  Future<void> write({
    required String outputDirectory,
    required ReplayBatchSummary summary,
  }) async {
    if (_closed) {
      throw StateError('The batch summary writer is closed.');
    }
    if (outputDirectory.trim().isEmpty) {
      throw ArgumentError.value(
        outputDirectory,
        'outputDirectory',
        'must not be empty',
      );
    }
    if (fileName.isEmpty || fileName.contains('/') || fileName.contains('\\')) {
      throw ArgumentError.value(fileName, 'fileName', 'must be a file name');
    }

    final target = File(_join(outputDirectory, fileName));
    final directory = Directory(outputDirectory);
    try {
      await directory.create(recursive: true);
    } on FileSystemException {
      throw SummaryWriteException(
        message: 'Could not create the batch summary directory.',
        targetPath: target.path,
        temporaryPath: '${target.path}.tmp',
      );
    }
    await _ensureExclusiveClaim(target);
    try {
      await _claimTarget(target);
      final temporary = await _createTemporaryFile(target);
      final payload = Map<String, Object?>.from(summary.toJson())
        ..['afterimageWriter'] = <String, String>{
          'owner': 'afterimage',
          'batchId': _batchId,
        };
      final encoded =
          '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
      await temporary.writeAsString(encoded, flush: true);
      await _replaceSafely(temporary, target);
      _hasWritten = true;
    } on SummaryWriteException {
      if (!_hasWritten) {
        await _releaseClaim();
      }
      rethrow;
    } on FileSystemException {
      final temporaryPath = '${target.path}.tmp';
      if (!_hasWritten) {
        await _releaseClaim();
      }
      throw SummaryWriteException(
        message: 'Could not update the batch summary safely.',
        targetPath: target.path,
        temporaryPath: temporaryPath,
      );
    }
  }

  Future<void> _ensureExclusiveClaim(File target) async {
    final lockPath = '${target.absolute.path}.afterimage.lock';
    final claimed = _claimedLockPath;
    if (claimed != null) {
      if (claimed == lockPath) {
        return;
      }
      throw StateError(
        'One summary writer cannot own more than one output directory.',
      );
    }
    if (!_claimedLockPaths.add(lockPath)) {
      throw _activeBatchError(target);
    }

    RandomAccessFile? handle;
    try {
      handle = await File(lockPath).open(mode: FileMode.append);
      if (await handle.length() == 0) {
        await handle.writeByte(0);
        await handle.flush();
      }
      await handle.lock(FileLock.exclusive, 0, 1);
      _lockHandle = handle;
      _claimedLockPath = lockPath;
    } on Object {
      try {
        await handle?.close();
      } on Object {
        // The ownership error is the actionable failure.
      }
      _claimedLockPaths.remove(lockPath);
      throw _activeBatchError(target);
    }
  }

  SummaryOwnershipException _activeBatchError(File target) {
    return SummaryOwnershipException(
      message: 'Another Afterimage batch is already using this output folder.',
      targetPath: target.path,
      temporaryPath: '${target.path}.tmp',
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _releaseClaim();
  }

  Future<void> _releaseClaim() async {
    final handle = _lockHandle;
    final lockPath = _claimedLockPath;
    _lockHandle = null;
    _claimedLockPath = null;
    if (lockPath != null) {
      _claimedLockPaths.remove(lockPath);
    }
    if (handle == null) {
      return;
    }
    try {
      await handle.unlock(0, 1);
    } finally {
      await handle.close();
    }
  }

  Future<void> _claimTarget(File target) async {
    if (!await target.exists()) {
      return;
    }

    Map<String, dynamic>? existing;
    try {
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is Map<String, dynamic>) {
        existing = decoded;
      }
    } on Object {
      // Invalid JSON is still an unrelated file. It must remain untouched.
    }

    final marker = existing?['afterimageWriter'];
    final owned = marker is Map && marker['owner'] == 'afterimage';
    if (owned) {
      return;
    }

    throw SummaryOwnershipException(
      message: 'Refusing to overwrite an unrelated summary.json.',
      targetPath: target.path,
      temporaryPath: '${target.path}.tmp',
    );
  }

  static String _newBatchId() {
    _batchNumber++;
    return '$pid-${DateTime.now().microsecondsSinceEpoch}-$_batchNumber';
  }

  Future<File> _createTemporaryFile(File target) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      _writeNumber++;
      final temporary = File(
        '${target.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}-$_writeNumber',
      );
      try {
        return await temporary.create(exclusive: true);
      } on FileSystemException {
        // A unique temporary name is retried without touching any existing
        // summary or recording.
      }
    }
    throw SummaryWriteException(
      message: 'Could not create a temporary batch summary.',
      targetPath: target.path,
      temporaryPath: '${target.path}.tmp',
    );
  }

  Future<void> _replaceSafely(File temporary, File target) async {
    try {
      await _rename(temporary, target.path);
      return;
    } on FileSystemException {
      // POSIX rename replaces the target atomically. Some platforms reject
      // replacing an existing target, so use a durable backup/restore
      // sequence there. The fallback is safe and recoverable, but is not an
      // atomic replacement.
      if (!await target.exists()) {
        rethrow;
      }

      final backup = await _uniqueBackup(target, temporary.path);
      try {
        await _rename(target, backup.path);
      } on FileSystemException {
        throw SummaryWriteException(
          message: 'Could not protect the existing batch summary.',
          targetPath: target.path,
          temporaryPath: temporary.path,
        );
      }

      try {
        await _rename(temporary, target.path);
      } on FileSystemException {
        try {
          await _rename(backup, target.path);
        } on FileSystemException {
          throw SummaryWriteException(
            message:
                'Could not replace the batch summary. The previous summary is preserved at ${backup.path}.',
            targetPath: target.path,
            temporaryPath: temporary.path,
          );
        }
        throw SummaryWriteException(
          message:
              'Could not replace the batch summary. The previous summary was restored.',
          targetPath: target.path,
          temporaryPath: temporary.path,
        );
      }

      try {
        await backup.delete();
      } on FileSystemException {
        // The new summary is valid. Keep the old backup as a recoverable
        // artifact rather than deleting anything that we do not own.
      }
    }
  }

  Future<File> _uniqueBackup(File target, String temporaryPath) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final backup = File(
        '${target.path}.bak-$pid-${DateTime.now().microsecondsSinceEpoch}-$attempt',
      );
      if (!await backup.exists()) {
        return backup;
      }
    }
    throw SummaryWriteException(
      message: 'Could not create a recovery name for the existing summary.',
      targetPath: target.path,
      temporaryPath: temporaryPath,
    );
  }

  static Future<File> _renameWithIo(File source, String destinationPath) {
    return source.rename(destinationPath);
  }

  String _join(String directory, String name) {
    if (directory.endsWith('/') || directory.endsWith('\\')) {
      return '$directory$name';
    }
    return '$directory${Platform.pathSeparator}$name';
  }
}
