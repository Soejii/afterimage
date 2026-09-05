import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afterimage/app/theme.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/screens/recorder_screen.dart';

void main() {
  testWidgets('custom replay count is visible only when selected',
      (tester) async {
    RecordingOptions? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AfterimageTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) {
            var options = changed ?? const RecordingOptions();
            return Scaffold(
              body: RecorderScreen(
                report: _readyReport(),
                options: options,
                onOptionsChanged: (value) {
                  changed = value;
                  setState(() => options = value);
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('custom-replay-count')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('replay-count-custom')));
    await tester.pump();
    expect(find.byKey(const ValueKey('custom-replay-count')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('custom-replay-count')),
      '12',
    );
    await tester.pump();
    expect(changed?.customReplayCount, 12);
  });

}

SetupReport _readyReport({
  bool keyboardReady = true,
  bool controllerReady = true,
}) {
  return SetupReport(
    checkedAt: DateTime(2026, 9, 5),
    replayCount: 12,
    checks: [
      for (final id in SetupCheckId.values)
        SetupCheck(
          id: id,
          title: id.name,
          detail: id == SetupCheckId.replayLibrary
              ? '12 saved replay files found.'
              : id == SetupCheckId.keyboardInput && !keyboardReady
                  ? 'backend unavailable'
                  : id == SetupCheckId.controllerInput && !controllerReady
                      ? 'backend unavailable'
                      : 'Ready.',
          status: id == SetupCheckId.keyboardInput
              ? keyboardReady
                  ? SetupCheckStatus.ready
                  : SetupCheckStatus.notice
              : id == SetupCheckId.controllerInput
                  ? controllerReady
                      ? SetupCheckStatus.ready
                      : SetupCheckStatus.notice
                  : SetupCheckStatus.ready,
          required: id != SetupCheckId.keyboardInput &&
              id != SetupCheckId.controllerInput,
        ),
    ],
  );
}
