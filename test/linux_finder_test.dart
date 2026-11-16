import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/services/linux_finder.dart';

void main() {
  test('adds reference flag only when requested', () async {
    final root = await Directory.systemTemp.createTemp('afterimage-finder-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/scripts/lab_sequences.py').create(recursive: true);
    final commands = <String>[];
    final finder = LinuxFinder(
      finderDirectory: root.path,
      isLinux: true,
      processStarter: (executable, arguments,
          {required mode, required environment}) async {
        commands.add(arguments.last);
      },
    );
    await finder.startBatch('${root.path}/batch');
    await finder.startBatch('${root.path}/batch', reference: true);
    expect(commands.first, isNot(contains('--reference')));
    expect(commands.last,
        contains("'${finder.scriptPath}' '--reference' '${root.path}/batch'"));
  });
  test('prepends local bin to PATH with the PATH list separator', () async {
    final root = await Directory.systemTemp.createTemp('afterimage-finder-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/scripts/lab_sequences.py').create(recursive: true);
    Map<String, String>? startedEnvironment;
    final finder = LinuxFinder(
      finderDirectory: root.path,
      isLinux: true,
      processStarter: (
        executable,
        arguments, {
        required mode,
        required environment,
      }) async {
        startedEnvironment = Map<String, String>.of(environment);
      },
    );

    await finder.startBatch('${root.path}/batch');

    final home = Platform.environment['HOME'];
    final oldPath = Platform.environment['PATH'];
    expect(home, isNotNull);
    expect(oldPath, isNotNull);
    expect(startedEnvironment?['PATH'], '$home/.local/bin:$oldPath');
  }, skip: !Platform.isLinux);
}
