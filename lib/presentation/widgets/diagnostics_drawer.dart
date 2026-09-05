import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/setup_models.dart';
import 'setup_check_tile.dart';

/// The full list of local checks, collapsed by default.
///
/// These used to sit permanently on the setup screen as a nine-tile grid titled
/// "Computer details", which put a system-shaped debugging view on the primary
/// screen next to a task-shaped one. They are genuinely useful when something
/// is wrong and pure noise the rest of the time, so they live here.
class DiagnosticsDrawer extends StatelessWidget {
  const DiagnosticsDrawer({
    super.key,
    required this.report,
    this.isRefreshing = false,
    this.onRefresh,
    this.onBrowseGameDirectory,
    this.onBrowseReplayDirectory,
    this.onUseAutomaticLocations,
  });

  final SetupReport? report;
  final bool isRefreshing;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onBrowseGameDirectory;
  final Future<void> Function()? onBrowseReplayDirectory;
  final Future<void> Function()? onUseAutomaticLocations;

  @override
  Widget build(BuildContext context) {
    final currentReport = report;
    return Card(
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: const ValueKey('diagnostics-drawer'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text('Details and troubleshooting'),
          subtitle: const Text(
            'Everything Afterimage checked on this computer.',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            if (currentReport == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 4),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 2 : 1;
                  const gap = 12.0;
                  final itemWidth = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - gap) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final check in currentReport.checks)
                        SizedBox(
                          width: itemWidth,
                          child: SetupCheckTile(
                            check: check,
                            showTechnicalDetail:
                                check.status != SetupCheckStatus.ready,
                          ),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                if (onRefresh != null)
                  OutlinedButton.icon(
                    key: const ValueKey('refresh-checks'),
                    onPressed:
                        isRefreshing ? null : () => unawaited(onRefresh!()),
                    icon: isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(isRefreshing ? 'Checking…' : 'Check again'),
                  ),
                if (onBrowseGameDirectory != null)
                  OutlinedButton.icon(
                    key: const ValueKey('browse-game-directory'),
                    onPressed: isRefreshing
                        ? null
                        : () => unawaited(onBrowseGameDirectory!()),
                    icon: const Icon(Icons.sports_esports_outlined),
                    label: const Text('Locate game'),
                  ),
                if (onBrowseReplayDirectory != null)
                  OutlinedButton.icon(
                    key: const ValueKey('browse-replay-directory'),
                    onPressed: isRefreshing
                        ? null
                        : () => unawaited(onBrowseReplayDirectory!()),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Locate saved replays'),
                  ),
                if (onUseAutomaticLocations != null)
                  TextButton(
                    key: const ValueKey('use-automatic-locations'),
                    onPressed: isRefreshing
                        ? null
                        : () => unawaited(onUseAutomaticLocations!()),
                    child: const Text('Find them automatically'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 17,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'These checks only read local status. Afterimage does not '
                    'install anything or change your game and OBS settings.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
