import 'dart:io';

import '../domain/finder_contracts.dart';
import 'notes_repository.dart';

const String defaultFinderDirectory = '/home/suji/CODE/ggst-input-tracker';

typedef LinuxFinderProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments, {
  required ProcessStartMode mode,
  required Map<String, String> environment,
});

/// Linux process adapter for the optional notes finder.
class LinuxFinder implements FinderPort {
  LinuxFinder({
    String? finderDirectory,
    bool? isLinux,
    NotesRepository? notes,
    LinuxFinderProcessStarter? processStarter,
  })  : finderDirectory = finderDirectory ?? _defaultFinderDirectory(),
        _isLinux = isLinux ?? Platform.isLinux,
        notes = notes ??
            NotesRepository(
              finderDirectory: finderDirectory ?? _defaultFinderDirectory(),
            ),
        _processStarter = processStarter ?? _startProcess;

  final String finderDirectory;
  final bool _isLinux;
  final NotesRepository notes;
  final LinuxFinderProcessStarter _processStarter;

  String get scriptPath =>
      _join(_join(finderDirectory, 'scripts'), 'write_theory.py');

  @override
  bool get available => _isLinux && File(scriptPath).existsSync();

  @override
  Future<void> startBatch(String batchFolder) async {
    if (!available) {
      throw StateError('The notes finder is not available on this computer.');
    }
    final batchLabel = _basename(batchFolder);
    final runDirectory = Directory(notes.runDirectory(batchLabel));
    await runDirectory.create(recursive: true);
    final logPath = notes.runLogPath(batchLabel);
    final command = [
      '/usr/bin/nice',
      '-n',
      '19',
      '/usr/bin/python3',
      scriptPath,
      batchFolder,
    ].map(_shellQuote).join(' ');
    final shellCommand = '$command > ${_shellQuote(logPath)} 2>&1';
    final environment = <String, String>{
      ...Platform.environment,
    };
    final home = environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final localBin = _join(home, '.local/bin');
      final path = environment['PATH'];
      environment['PATH'] =
          path == null || path.isEmpty ? localBin : '$localBin:$path';
    }

    await _processStarter(
      '/bin/sh',
      <String>['-c', shellCommand],
      mode: ProcessStartMode.detached,
      environment: environment,
    );
  }
}

Future<void> _startProcess(
  String executable,
  List<String> arguments, {
  required ProcessStartMode mode,
  required Map<String, String> environment,
}) async {
  await Process.start(
    executable,
    arguments,
    mode: mode,
    environment: environment,
  );
}

String _defaultFinderDirectory() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return defaultFinderDirectory;
  return _join(home, 'CODE/ggst-input-tracker');
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _join(String base, String child) {
  if (base.endsWith('/') || base.endsWith('\\')) return '$base$child';
  return '$base${Platform.pathSeparator}$child';
}
