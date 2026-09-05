import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/obs_connection_service.dart';

/// Teaches the one OBS step Afterimage will not do for the user.
///
/// Afterimage reads the OBS WebSocket configuration and never writes it, so
/// switching the server on is a one-time action only the user can take. That
/// makes it the single wall between a new user and their first recording, which
/// is why it gets a picture rather than a sentence.
///
/// The written instruction is chosen from [ObsSetupStage], so someone who has
/// never installed OBS is not told to look in a Tools menu that isn't there.
class ObsSetupGuide extends StatelessWidget {
  const ObsSetupGuide({
    super.key,
    required this.stage,
    this.onOpenObsDownload,
    this.onConnect,
    this.isBusy = false,
  });

  final ObsSetupStage stage;
  final Future<void> Function()? onOpenObsDownload;
  final Future<void> Function()? onConnect;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only the "switch it on" instruction is worth pictures. Every other
    // stage is either about a different application or about a value the user
    // types, and a picture of the same dialog would not help.
    final showsPictures = stage == ObsSetupStage.serverDisabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        if (_steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var index = 0; index < _steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AfterimageTheme.ready,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _steps[index],
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (showsPictures) ...[
          const SizedBox(height: 14),
          const _HelpImage(asset: 'assets/help/obs-tools-menu.png'),
          const SizedBox(height: 10),
          const _HelpImage(asset: 'assets/help/obs-websocket-settings.png'),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onConnect != null)
              FilledButton.icon(
                key: const ValueKey('obs-connect'),
                onPressed: isBusy ? null : () => unawaited(onConnect!()),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connect to OBS'),
              ),
            if (stage == ObsSetupStage.configNotFound &&
                onOpenObsDownload != null)
              OutlinedButton.icon(
                key: const ValueKey('get-obs-studio'),
                onPressed:
                    isBusy ? null : () => unawaited(onOpenObsDownload!()),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Get OBS Studio'),
              ),
          ],
        ),
      ],
    );
  }

  String get _title {
    switch (stage) {
      case ObsSetupStage.configNotFound:
        return 'Afterimage needs OBS Studio';
      case ObsSetupStage.serverDisabled:
        return 'Switch on the OBS WebSocket server';
      case ObsSetupStage.authRequired:
        return 'OBS asked for its password';
      case ObsSetupStage.alreadyRecording:
        return 'OBS is already recording';
      case ObsSetupStage.unreachable:
        return 'OBS did not answer';
      case ObsSetupStage.ready:
        return 'OBS is connected';
    }
  }

  String get _body {
    switch (stage) {
      case ObsSetupStage.configNotFound:
        return 'Afterimage records through OBS Studio, so OBS has to be '
            'installed and opened once. Use version 28 or newer. Afterimage '
            'does not change your OBS scenes, sources, or settings.';
      case ObsSetupStage.serverDisabled:
        return 'OBS is installed, but the connection Afterimage uses to start '
            'and stop recording is switched off. You only have to do this '
            'once.';
      case ObsSetupStage.authRequired:
        return 'OBS is protecting its connection with a password and '
            'Afterimage could not read it. Open Connection options below and '
            'paste the password shown in the same OBS dialog.';
      case ObsSetupStage.alreadyRecording:
        return 'Afterimage will not start while OBS is already recording, '
            'because that recording would be interrupted. Stop it in OBS '
            'first.';
      case ObsSetupStage.unreachable:
        return 'The OBS connection is switched on, but OBS did not answer. '
            'Check that OBS is open on this computer.';
      case ObsSetupStage.ready:
        return 'Afterimage can start and stop your recordings.';
    }
  }

  List<String> get _steps {
    switch (stage) {
      case ObsSetupStage.configNotFound:
        return const [
          'Install OBS Studio 28 or newer.',
          'Open OBS once, so it creates its settings.',
          'Set up a scene that shows the game with its sound.',
        ];
      case ObsSetupStage.serverDisabled:
        return const [
          'In OBS, open the Tools menu.',
          'Choose WebSocket Server Settings.',
          'Tick Enable WebSocket server, then select Apply.',
        ];
      case ObsSetupStage.unreachable:
        return const [
          'Check that OBS is open on this computer.',
          'Check that no firewall is blocking the local connection.',
          'If OBS uses a different port, open Connection options below.',
        ];
      case ObsSetupStage.authRequired:
      case ObsSetupStage.alreadyRecording:
      case ObsSetupStage.ready:
        return const [];
    }
  }
}

/// One picture of the OBS interface.
///
/// Deliberately uncaptioned. The numbered steps above already name the menu and
/// the checkbox, so a caption would repeat them, and it would survive an
/// `errorBuilder` that only replaces the image, leaving a label pointing at a
/// picture that is not there. With no caption, a missing or undecodable asset
/// collapses to nothing and the written steps carry the instruction alone.
class _HelpImage extends StatelessWidget {
  const _HelpImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }
}
