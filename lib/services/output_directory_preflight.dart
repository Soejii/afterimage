import 'dart:io';

class OutputDirectoryReadiness {
  const OutputDirectoryReadiness({
    required this.ready,
    required this.detail,
  });

  const OutputDirectoryReadiness.ready({
    this.detail = 'The output folder is ready.',
  }) : ready = true;

  const OutputDirectoryReadiness.blocked({required this.detail})
      : ready = false;

  final bool ready;
  final String detail;
}

/// Checks and prepares the destination before the recorder opens OBS.
///
/// The write probe creates a uniquely named temporary file and removes only
/// that file. It catches read-only folders and paths that resolve to files,
/// while allowing a missing destination to be created for the user.
abstract interface class OutputDirectoryPreflight {
  Future<OutputDirectoryReadiness> check(String outputDirectory);
}

class FileOutputDirectoryPreflight implements OutputDirectoryPreflight {
  const FileOutputDirectoryPreflight();

  @override
  Future<OutputDirectoryReadiness> check(String outputDirectory) async {
    final trimmed = outputDirectory.trim();
    if (trimmed.isEmpty) {
      return const OutputDirectoryReadiness.blocked(
        detail: 'Choose an output folder before starting a batch.',
      );
    }

    final directory = Directory(trimmed);
    try {
      final existingType = await FileSystemEntity.type(directory.path);
      if (existingType != FileSystemEntityType.notFound &&
          existingType != FileSystemEntityType.directory) {
        return const OutputDirectoryReadiness.blocked(
          detail: 'The selected output path is not a folder.',
        );
      }
      await directory.create(recursive: true);
      final type = await FileSystemEntity.type(directory.path);
      if (type != FileSystemEntityType.directory) {
        return const OutputDirectoryReadiness.blocked(
          detail: 'The selected output path is not a folder.',
        );
      }

      final probe = await _createProbe(directory);
      try {
        await probe.writeAsString('Afterimage output check\n', flush: true);
      } finally {
        try {
          await probe.delete();
        } catch (_) {
          // The write probe succeeded. Keep the readiness result even if a
          // cleanup race prevents deleting our uniquely named probe.
        }
      }
      return const OutputDirectoryReadiness.ready();
    } on FileSystemException catch (error) {
      return OutputDirectoryReadiness.blocked(
        detail: _detailFor(error),
      );
    } on IOException catch (error) {
      return OutputDirectoryReadiness.blocked(
        detail: 'The output folder could not be checked: $error',
      );
    }
  }

  Future<File> _createProbe(Directory directory) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final path = '${directory.path}/.afterimage-write-test-$pid-'
          '${DateTime.now().microsecondsSinceEpoch}-$attempt';
      try {
        return await File(path).create(exclusive: true);
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        if (code == 1 || code == 13) {
          rethrow;
        }
        // A collision is harmless. Try a new name without touching the file
        // that already exists.
      }
    }
    throw const FileSystemException('Could not create a unique write probe.');
  }

  String _detailFor(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 13 || code == 1) {
      return 'The output folder is not writable. Choose a folder where you have write access.';
    }
    return 'The output folder could not be created or checked. Choose another folder and try again.';
  }
}
