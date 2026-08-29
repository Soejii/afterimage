import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/setup_models.dart';

void main() {
  test('required checks control recording readiness', () {
    final report = SetupReport(
      checkedAt: DateTime(2026, 8, 29),
      checks: [
        _check(SetupCheckId.supportedPlatform),
        _check(
          SetupCheckId.nativeRecorderBackend,
          status: SetupCheckStatus.blocked,
        ),
        _check(
          SetupCheckId.controllerInput,
          status: SetupCheckStatus.notice,
          required: false,
        ),
      ],
    );

    expect(report.canRecord, isFalse);
    expect(report.blockingChecks, hasLength(1));
    expect(
      report.checkFor(SetupCheckId.nativeRecorderBackend)?.isReady,
      isFalse,
    );
  });

  test('optional notices do not block an otherwise ready report', () {
    final report = SetupReport(
      checkedAt: DateTime(2026, 8, 29),
      checks: [
        _check(SetupCheckId.supportedPlatform),
        _check(
          SetupCheckId.keyboardInput,
          status: SetupCheckStatus.notice,
          required: false,
        ),
        _check(
          SetupCheckId.controllerInput,
          status: SetupCheckStatus.blocked,
          required: false,
        ),
      ],
    );

    expect(report.canRecord, isTrue);
    expect(report.blockingChecks, isEmpty);
  });

  test('recording options copyWith changes only the requested value', () {
    const original = RecordingOptions(
      replayCount: ReplayCountOption.five,
      videoMode: VideoMode.separate,
      inputMode: InputMode.keyboard,
      outputDirectory: '/tmp/captures',
    );
    final changed = original.copyWith(replayCount: ReplayCountOption.all);

    expect(changed.replayCount, ReplayCountOption.all);
    expect(changed.videoMode, VideoMode.separate);
    expect(changed.inputMode, InputMode.keyboard);
    expect(changed.outputDirectory, '/tmp/captures');
  });
}

SetupCheck _check(
  SetupCheckId id, {
  SetupCheckStatus status = SetupCheckStatus.ready,
  bool required = true,
}) {
  return SetupCheck(
    id: id,
    title: id.name,
    detail: 'test detail',
    status: status,
    required: required,
  );
}
