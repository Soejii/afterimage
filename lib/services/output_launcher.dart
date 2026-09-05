import 'dart:io';

typedef OutputProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class OutputLaunchException implements Exception {
  const OutputLaunchException({
    required this.message,
    required this.executable,
    required this.arguments,
    this.exitCode,
    this.stderr,
  });

  final String message;
  final String executable;
  final List<String> arguments;
  final int? exitCode;
  final Object? stderr;

  @override
  String toString() => message;
}

/// Opens a saved output through the operating system's native file launcher.
///
/// The path is passed as a process argument. No shell or interpolated command
/// string is used, so spaces and shell metacharacters remain ordinary path
/// characters. The process runner is injectable so tests never launch a
/// desktop process.
class OutputLauncher {
  OutputLauncher({
    OutputProcessRunner? processRunner,
    bool? isWindows,
    bool? isMacOS,
  })  : _processRunner = processRunner ?? _runProcess,
        _isWindows = isWindows ?? Platform.isWindows,
        _isMacOS = isMacOS ?? Platform.isMacOS;

  final OutputProcessRunner _processRunner;
  final bool _isWindows;
  final bool _isMacOS;

  Future<void> openFolder(String path) => _open(path);

  Future<void> openVideo(String path) => _open(path);

  Future<void> openObsDownload() => _open('https://obsproject.com/download');

  Future<void> _open(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }

    final executable = _isWindows
        ? 'explorer.exe'
        : _isMacOS
            ? 'open'
            : 'xdg-open';
    final arguments = <String>[path];
    late ProcessResult result;
    try {
      result = await _processRunner(executable, arguments);
    } on Object catch (error) {
      throw OutputLaunchException(
        message: 'Afterimage could not open the selected output.',
        executable: executable,
        arguments: arguments,
        stderr: error,
      );
    }
    if (result.exitCode != 0) {
      throw OutputLaunchException(
        message: 'The operating system could not open the selected output.',
        executable: executable,
        arguments: arguments,
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments, runInShell: false);
  }
}
