import 'package:flutter/material.dart';

import '../recorder_controller.dart';
import '../ui/ui.dart';

/// The "Capture my matches" switch with what it does, in the content column.
class LiveCaptureCard extends StatelessWidget {
  const LiveCaptureCard({super.key, required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.liveCaptureActive;
    return UiPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      border: active ? Ui.you.withValues(alpha: 0.55) : Ui.track,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.sensors_rounded,
              size: 22, color: active ? Ui.you : Ui.inkLow),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Capture my matches', style: Ui.h2),
                const SizedBox(height: 3),
                Text(
                  active
                      ? 'Capturing your matches. '
                          '${controller.liveCaptureGames} '
                          '${controller.liveCaptureGames == 1 ? 'game' : 'games'} so far.'
                      : 'Saves the frame data of every online game you play. '
                          'No video and no OBS.',
                  style: Ui.small,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            key: const ValueKey('live-capture'),
            value: active,
            onChanged: controller.isBusy || controller.liveCaptureStopping
                ? null
                : (value) => controller.setLiveCapture(value),
          ),
        ],
      ),
    );
  }
}

/// The Record tab while a live session runs: what is happening and how to
/// stop. Replaces the batch form, which cannot be used meanwhile.
class LiveCaptureView extends StatelessWidget {
  const LiveCaptureView({super.key, required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final games = controller.liveCaptureGames;
    final stopping = controller.liveCaptureStopping;
    return Column(
      key: const ValueKey('live-capture-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiPanel(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const UiCaps('How it works'),
              const SizedBox(height: 10),
              for (final line in const [
                'Play online as usual. Each game is saved when it ends.',
                'Training mode and offline games are skipped.',
                'A game already running when you switched this on is skipped.',
                'When you switch this off, the games become one set on the '
                    'Sequences page, without clips.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 10),
                        child: SizedBox(
                            width: 5,
                            height: 5,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Ui.inkLow, shape: BoxShape.circle))),
                      ),
                      Expanded(child: Text(line, style: Ui.bodyMid)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        UiPanel(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Row(
            children: [
              Expanded(
                child: UiStat(
                  key: const ValueKey('live-capture-games'),
                  label: 'Games saved',
                  marker: Ui.you,
                  value: '$games',
                  unit: stopping ? 'finishing up' : 'this session',
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('live-capture-stop'),
                onPressed:
                    stopping ? null : () => controller.setLiveCapture(false),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: Text(stopping ? 'Stopping' : 'Stop capturing'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
