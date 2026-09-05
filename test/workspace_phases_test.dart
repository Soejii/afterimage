import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/afterimage_app.dart';
import 'package:afterimage/app/theme.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/presentation/replay_timeline.dart';
import 'package:afterimage/presentation/widgets/replay_list.dart';
import 'package:afterimage/services/setup_service.dart';

void main() {
  group('blocked state', () {
    testWidgets('leads with one blocker and lists the rest without hiding them',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        AfterimageApp(setupService: _FakeSetupService(_multiBlockedReport())),
      );
      await tester.pumpAndSettle();

      // The game installation outranks the saved replay library, because you
      // cannot resolve the second before the first.
      expect(find.byKey(const ValueKey('lead-blocker')), findsOneWidget);
      expect(find.text('Game'), findsOneWidget);
      expect(find.textContaining('No GGST installation'), findsOneWidget);

      // Hiding the remainder entirely turns every fix into a fresh unexpected
      // wall, so the rest stay visible as a strip.
      expect(find.byKey(const ValueKey('remaining-blockers')), findsOneWidget);
      expect(find.text('Saved replays'), findsOneWidget);
    });

    testWidgets('the full check list stays available but collapsed',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        AfterimageApp(setupService: _FakeSetupService(_multiBlockedReport())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('diagnostics-drawer')), findsOneWidget);
      // Collapsed: the per-check technical detail is not on the main screen.
      expect(find.text('Supported desktop OS'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('diagnostics-drawer')));
      await tester.pumpAndSettle();
      expect(find.text('Your computer'), findsOneWidget);
    });
  });

  group('replay timeline list', () {
    testWidgets('shows a row per replay and an honest count line',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AfterimageTheme.dark(),
          home: const Scaffold(
            body: ReplayList(
              rows: [
                ReplayRow(index: 1, status: ReplayRowStatus.done),
                ReplayRow(index: 2, status: ReplayRowStatus.failed),
                ReplayRow(index: 3, status: ReplayRowStatus.active),
                ReplayRow(index: 4, status: ReplayRowStatus.pending),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 saved · 1 failed · 1 to go'), findsOneWidget);
      expect(find.text('Replay 1'), findsOneWidget);
      expect(find.text('Recording now'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
    });

    testWidgets('a long batch does not build every row at once',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AfterimageTheme.dark(),
          home: Scaffold(
            body: ReplayList(
              rows: [
                for (var index = 1; index <= 200; index++)
                  ReplayRow(index: index, status: ReplayRowStatus.pending),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The list is virtualised, so a 200-replay batch stays cheap. If this
      // ever renders all 200, the running view has become a scroll hazard.
      expect(find.text('Replay 1'), findsOneWidget);
      expect(find.text('Replay 200'), findsNothing);
      expect(find.textContaining('200 to go'), findsOneWidget);
    });
  });
}

class _FakeSetupService implements SetupService {
  _FakeSetupService(this.report);

  final SetupReport report;

  @override
  Future<SetupReport> inspect() async => report;
}

SetupReport _multiBlockedReport() {
  return SetupReport(
    checkedAt: DateTime(2026, 9, 5),
    checks: const [
      SetupCheck(
        id: SetupCheckId.supportedPlatform,
        title: 'Supported desktop OS',
        detail: 'Linux is supported.',
        status: SetupCheckStatus.ready,
        required: true,
      ),
      SetupCheck(
        id: SetupCheckId.gameInstall,
        title: 'GGST installation',
        detail: 'No GGST installation was found in your Steam libraries.',
        status: SetupCheckStatus.blocked,
        required: true,
      ),
      SetupCheck(
        id: SetupCheckId.replayLibrary,
        title: 'Replay library',
        detail: 'No saved replays were found.',
        status: SetupCheckStatus.blocked,
        required: true,
      ),
    ],
  );
}
