import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/theme.dart';
import 'package:afterimage/presentation/widgets/obs_connection_card.dart';
import 'package:afterimage/presentation/widgets/obs_setup_guide.dart';
import 'package:afterimage/services/obs_connection_service.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AfterimageTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('ObsSetupGuide', () {
    testWidgets('a disabled server is told to switch it on', (tester) async {
      await tester.pumpWidget(
        host(const ObsSetupGuide(stage: ObsSetupStage.serverDisabled)),
      );
      await tester.pumpAndSettle();

      expect(
          find.textContaining('Tick Enable WebSocket server'), findsOneWidget);

      // The pictures of the OBS menu and dialog belong to this stage only.
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets(
        'an unreachable server is not told to switch on a server it '
        'has just been told is already on', (tester) async {
      await tester.pumpWidget(
        host(const ObsSetupGuide(stage: ObsSetupStage.unreachable)),
      );
      await tester.pumpAndSettle();

      // These two stages must not share instructions. Telling someone whose
      // server is already enabled to enable it is how a user concludes the
      // application is broken.
      expect(find.textContaining('Tick Enable WebSocket server'), findsNothing);
      expect(find.textContaining('Check that OBS is open'), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a missing OBS is offered the download, others are not',
        (tester) async {
      await tester.pumpWidget(
        host(ObsSetupGuide(
          stage: ObsSetupStage.configNotFound,
          onOpenObsDownload: () async {},
        )),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('get-obs-studio')), findsOneWidget);

      await tester.pumpWidget(
        host(ObsSetupGuide(
          stage: ObsSetupStage.serverDisabled,
          onOpenObsDownload: () async {},
        )),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('get-obs-studio')), findsNothing);
    });
  });

  group('ObsConnectionCard', () {
    testWidgets('a stage change to authRequired reveals the password field',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(const ObsConnectionCard(stage: ObsSetupStage.unreachable)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('obs-password')), findsNothing);

      // The card is already mounted. ExpansionTile reads `initiallyExpanded`
      // only when its state is created, so without a keyed reset this
      // transition leaves the password box collapsed at the exact moment it
      // is the only thing that helps.
      await tester.pumpWidget(
        host(const ObsConnectionCard(stage: ObsSetupStage.authRequired)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('obs-password')), findsOneWidget);
    });
  });
}
