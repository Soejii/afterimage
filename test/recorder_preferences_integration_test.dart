import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/recorder_controller.dart';
import 'package:afterimage/services/recorder_preferences.dart';

void main() {
  test('initialization restores valid recording preferences', () async {
    final outputDirectory = Directory.systemTemp.path;
    final preferences = _PreferencesHarness({
      'replayCount': 'custom',
      'customReplayCount': 12,
      'inputMode': 'virtualController',
      'videoMode': 'combined',
      'outputDirectory': outputDirectory,
    });
    final controller = RecorderController(
      backend: _PreferencesBackend(),
      preferences: preferences.preferences,
    );

    await controller.initialize();

    expect(controller.options.replayCount, ReplayCountOption.custom);
    expect(controller.options.customReplayCount, 12);
    expect(controller.options.inputMode, InputMode.virtualController);
    expect(controller.options.videoMode, VideoMode.combined);
    expect(controller.options.outputDirectory, outputDirectory);
    controller.dispose();
  });

  test('initialization falls back from invalid enum and custom count values',
      () async {
    final preferences = _PreferencesHarness({
      'replayCount': 'does-not-exist',
      'customReplayCount': 1001,
      'inputMode': 'does-not-exist',
      'videoMode': 'does-not-exist',
      'outputDirectory': 'relative/path',
    });
    final controller = RecorderController(
      backend: _PreferencesBackend(),
      preferences: preferences.preferences,
    );

    await controller.initialize();

    expect(controller.options.replayCount, ReplayCountOption.one);
    expect(controller.options.customReplayCount, 1);
    expect(controller.options.inputMode, InputMode.keyboard);
    expect(controller.options.videoMode, VideoMode.separate);
    expect(controller.options.outputDirectory, isEmpty);
    controller.dispose();
  });

  test('updating options persists only the supported recording values',
      () async {
    final preferences = _PreferencesHarness({
      'password': 'must-not-be-reused',
      'obsWebSocketPassword': 'must-not-be-reused',
    });
    final controller = RecorderController(
      backend: _PreferencesBackend(),
      preferences: preferences.preferences,
    );

    final changed = controller.updateOptions(
      RecordingOptions(
        replayCount: ReplayCountOption.custom,
        customReplayCount: 8,
        inputMode: InputMode.virtualController,
        videoMode: VideoMode.combined,
        outputDirectory: Directory.systemTemp.path,
      ),
    );
    await preferences.preferences.flush();

    expect(changed, isTrue);
    expect(preferences.writes, hasLength(1));
    expect(preferences.writes.single, {
      'outputDirectory': Directory.systemTemp.path,
      'inputMode': 'virtualController',
      'replayCount': 'custom',
      'customReplayCount': 8,
      'videoMode': 'combined',
      'gameDirectory': null,
      'replayDirectory': null,
      'recentOutputs': <String>[],
      'recentOutputDirectory': null,
    });
    expect(preferences.writes.single, isNot(contains('password')));
    expect(preferences.writes.single, isNot(contains('obsWebSocketPassword')));
    controller.dispose();
  });

  test('initialization restores at most twenty recent outputs', () async {
    final recent = List<String>.generate(
      25,
      (index) => '${Directory.systemTemp.path}/afterimage-recent-$index.mp4',
    );
    final preferences = _PreferencesHarness({'recentOutputs': recent});
    final controller = RecorderController(
      backend: _PreferencesBackend(),
      preferences: preferences.preferences,
    );

    await controller.initialize();

    expect(controller.recentOutputPaths, recent.take(20).toList());
    controller.dispose();
  });
}

class _PreferencesHarness {
  _PreferencesHarness([Map<String, Object?>? initial]) {
    preferences = RecorderPreferences(
      read: () async => initial,
      write: (values) async => writes.add(values),
    );
  }

  final List<Map<String, Object?>> writes = [];
  late final RecorderPreferences preferences;
}

class _PreferencesBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  int inspectCalls = 0;

  @override
  Future<NativeBackendReadiness> inspect() async {
    inspectCalls++;
    return const NativeBackendReadiness(
      available: true,
      detail: 'Fake recorder is ready.',
    );
  }

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async {
    return const NativeBackendReadiness(
      available: true,
      detail: 'Fake input is ready.',
    );
  }

  @override
  Future<ReplayMonitorPort> openReplayMonitor() => throw UnimplementedError();

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) =>
      throw UnimplementedError();

  @override
  Future<ObsRecorderPort> openObsRecorder() => throw UnimplementedError();

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() =>
      throw UnimplementedError();
}
