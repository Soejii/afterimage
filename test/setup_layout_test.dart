import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afterimage/app/theme.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/screens/setup_screen.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('setup at 1280x720, text scale $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1010, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: AfterimageTheme.dark(),
          home: MediaQuery(
              data: MediaQueryData(
                  size: const Size(1010, 720),
                  textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                  body: SetupScreen(
                      report:
                          SetupReport(checkedAt: DateTime(2026), checks: const [
                        SetupCheck(
                            id: SetupCheckId.obsWebSocket,
                            title: 'OBS WebSocket protocol',
                            detail:
                                'OBS WebSocket authentication is enabled, but its password is missing. Add the OBS WebSocket password to Afterimage settings.',
                            status: SetupCheckStatus.blocked,
                            required: true)
                      ]),
                      isRefreshing: false,
                      errorMessage: null,
                      onRefresh: () async {},
                      onOpenRecorder: () {})))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final details = find.byKey(const ValueKey('computer-details'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Long actionable details must fit at text scale $scale');
    });
  }
}
