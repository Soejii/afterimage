import 'dart:io';

import '../domain/recorder_contracts.dart';
import '../domain/replay_batch.dart';

class OutputOrganizationException implements Exception {
  const OutputOrganizationException({
    required this.message,
    required this.sourcePath,
    required this.destinationPath,
    this.operation,
    this.cause,
  });

  final String message;
  final String sourcePath;
  final String destinationPath;
  final String? operation;
  final FileSystemException? cause;

  @override
  String toString() => '$message Source was left at $sourcePath.'
      '${operation == null ? '' : ' Operation: $operation. Destination: $destinationPath.'}'
      '${cause == null ? '' : ' Filesystem detail: $cause'}';
}

class FileOutputOrganizer implements OutputOrganizerPort {
  const FileOutputOrganizer();

  @override
  Future<OrganizedOutput> organizeReplay({
    required RecordedOutput source,
    required String outputDirectory,
    required int replayIndex,
    required bool partial,
  }) async {
    if (replayIndex <= 0) {
      throw ArgumentError.value(
        replayIndex,
        'replayIndex',
        'must be greater than zero',
      );
    }
    final destination = _destination(
      outputDirectory,
      'replay_${replayIndex.toString().padLeft(3, '0')}',
      source.path,
      partial: partial,
    );
    await _move(source.path, destination);
    return OrganizedOutput(
      path: destination,
      partial: partial,
      replayIndex: replayIndex,
    );
  }

  @override
  Future<OrganizedOutput> organizeCombined({
    required RecordedOutput source,
    required String outputDirectory,
    required bool partial,
  }) async {
    final destination = _destination(
      outputDirectory,
      'replays_combined',
      source.path,
      partial: partial,
    );
    await _move(source.path, destination);
    return OrganizedOutput(
      path: destination,
      partial: partial,
    );
  }

  Future<void> _move(String sourcePath, String destinationPath) async {
    if (sourcePath.trim().isEmpty) {
      throw OutputOrganizationException(
        message: 'OBS returned an empty output path.',
        sourcePath: sourcePath,
        destinationPath: destinationPath,
      );
    }

    final source = File(sourcePath);
    final destination = File(destinationPath);
    var operation = 'create destination folder';
    try {
      await Directory(destination.parent.path).create(recursive: true);
      operation = 'check source file';
      if (!await source.exists()) {
        throw OutputOrganizationException(
          message: 'The OBS output file does not exist.',
          sourcePath: sourcePath,
          destinationPath: destinationPath,
        );
      }
      try {
        operation = 'claim destination file';
        // Claim the destination with an exclusive create before copying. A
        // plain rename can overwrite a destination created by another
        // process between the existence check and the rename.
        await destination.create(exclusive: true);
      } on FileSystemException {
        if (await destination.exists()) {
          throw OutputOrganizationException(
            message: 'Refusing to overwrite an existing output file.',
            sourcePath: sourcePath,
            destinationPath: destinationPath,
          );
        }
        rethrow;
      }
      // The destination is already exclusively claimed, so this copy cannot
      // replace another file. If copying or source cleanup fails, both paths
      // remain available for recovery and the partial destination is kept.
      operation = 'copy recording';
      await source
          .openRead()
          .pipe(destination.openWrite(mode: FileMode.append));
      operation = 'delete source after copying';
      await source.delete();
    } on OutputOrganizationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw OutputOrganizationException(
        message: 'Could not move the OBS output to the selected folder.',
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        operation: operation,
        cause: error,
      );
    }
  }

  String _destination(
    String outputDirectory,
    String stem,
    String sourcePath, {
    required bool partial,
  }) {
    if (outputDirectory.trim().isEmpty) {
      throw ArgumentError.value(
        outputDirectory,
        'outputDirectory',
        'must not be empty',
      );
    }
    final suffix = partial ? '_partial' : '';
    return _join(
      outputDirectory,
      '$stem$suffix${_extension(sourcePath)}',
    );
  }

  String _extension(String sourcePath) {
    final normalized = sourcePath.replaceAll('\\', '/');
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '.mp4';
    }
    return name.substring(dot);
  }

  String _join(String directory, String name) {
    if (directory.endsWith('/') || directory.endsWith('\\')) {
      return '$directory$name';
    }
    return '$directory${Platform.pathSeparator}$name';
  }
}
