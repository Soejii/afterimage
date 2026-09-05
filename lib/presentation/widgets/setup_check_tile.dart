import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';

class SetupCheckTile extends StatelessWidget {
  const SetupCheckTile({
    super.key,
    required this.check,
    this.showTechnicalDetail = false,
  });

  final SetupCheck check;
  final bool showTechnicalDetail;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AfterimageTheme.panelRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_checkIcon, color: statusColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _friendlyTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (check.required)
                      Text(
                        'NEEDED',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _friendlyDetail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _friendlyTitle {
    switch (check.id) {
      case SetupCheckId.supportedPlatform:
        return 'Your computer';
      case SetupCheckId.gameInstall:
        return 'Guilty Gear -Strive-';
      case SetupCheckId.gameRunning:
        return 'Game is open';
      case SetupCheckId.obsWebSocket:
        return 'OBS is connected';
      case SetupCheckId.replayLibrary:
        return 'Saved replays';
      case SetupCheckId.keyboardInput:
        return 'Keyboard controls';
      case SetupCheckId.controllerInput:
        return 'Controller support';
      case SetupCheckId.nativeRecorderBackend:
        return 'Recording support';
    }
  }

  String get _friendlyDetail {
    if (showTechnicalDetail) {
      return check.detail;
    }

    switch (check.id) {
      case SetupCheckId.supportedPlatform:
        return check.isReady
            ? 'This computer can run Afterimage.'
            : 'Afterimage runs on Linux and Windows desktop computers.';
      case SetupCheckId.gameInstall:
        return check.isReady
            ? 'Your game installation was found.'
            : 'Install the game through Steam, then check again.';
      case SetupCheckId.gameRunning:
        return check.isReady
            ? 'Afterimage can see the game running.'
            : 'Open the game before you start recording.';
      case SetupCheckId.obsWebSocket:
        return check.isReady
            ? 'Afterimage can control OBS.'
            : 'Open OBS and connect it above.';
      case SetupCheckId.replayLibrary:
        return check.isReady
            ? _replayCountLabel
            : 'Save at least one replay in the game first.';
      case SetupCheckId.keyboardInput:
        return check.isReady
            ? 'Keyboard controls are ready.'
            : 'Keyboard control is unavailable on this computer.';
      case SetupCheckId.controllerInput:
        return check.isReady
            ? 'Optional controller support is ready.'
            : 'Optional controller support is unavailable.';
      case SetupCheckId.nativeRecorderBackend:
        return check.isReady
            ? 'The recording engine is ready.'
            : 'The recording engine needs attention before recording.';
    }
  }

  String get _replayCountLabel {
    final count = RegExp(r'\d+').firstMatch(check.detail)?.group(0);
    return count == null
        ? 'Your saved replay list was found.'
        : '$count saved replay files found.';
  }

  Color get _statusColor {
    switch (check.status) {
      case SetupCheckStatus.ready:
        return AfterimageTheme.accent;
      case SetupCheckStatus.blocked:
        return const Color(0xFFFFC67A);
      case SetupCheckStatus.notice:
        return const Color(0xFF91B8FF);
    }
  }

  IconData get _checkIcon {
    switch (check.status) {
      case SetupCheckStatus.ready:
        return Icons.check_rounded;
      case SetupCheckStatus.blocked:
        return Icons.lock_outline_rounded;
      case SetupCheckStatus.notice:
        return Icons.info_outline_rounded;
    }
  }
}
