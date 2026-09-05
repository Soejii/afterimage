import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/services/output_launcher.dart';

void main() {
  test('opens a folder with explorer.exe and passes the path as one argument',
      () async {
    String? executable;
    List<String>? arguments;
    final launcher = OutputLauncher(
      isWindows: true,
      processRunner: (actualExecutable, actualArguments) async {
        executable = actualExecutable;
        arguments = actualArguments;
        return ProcessResult(1, 0, '', '');
      },
    );

    await launcher.openFolder(r'C:\Captures\My Replay Folder');

    expect(executable, 'explorer.exe');
    expect(arguments, [r'C:\Captures\My Replay Folder']);
  });

  test('opens a video through xdg-open without a shell', () async {
    String? executable;
    List<String>? arguments;
    final launcher = OutputLauncher(
      isWindows: false,
      isMacOS: false,
      processRunner: (actualExecutable, actualArguments) async {
        executable = actualExecutable;
        arguments = actualArguments;
        return ProcessResult(2, 0, '', '');
      },
    );

    await launcher.openVideo('/tmp/captures/replay 001.mp4');

    expect(executable, 'xdg-open');
    expect(arguments, ['/tmp/captures/replay 001.mp4']);
  });

  test('reports a launcher failure', () async {
    final launcher = OutputLauncher(
      isWindows: false,
      processRunner: (_, __) async => ProcessResult(3, 1, '', 'not found'),
    );

    expect(
      () => launcher.openFolder('/tmp/captures'),
      throwsA(isA<OutputLaunchException>()),
    );
  });

  test('does not launch an empty path', () async {
    var launches = 0;
    final launcher = OutputLauncher(
      processRunner: (_, __) async {
        launches++;
        return ProcessResult(4, 0, '', '');
      },
    );

    expect(() => launcher.openVideo('  '), throwsA(isA<ArgumentError>()));
    expect(launches, 0);
  });
}
