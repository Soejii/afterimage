import 'package:flutter/material.dart';

import '../../domain/notes_models.dart';
import '../../services/notes_repository.dart';
import '../recorder_blocker.dart';
import '../recorder_controller.dart';
import '../views/blocked_view.dart';
import '../views/done_view.dart';
import '../views/ready_view.dart';
import '../views/running_view.dart';
import '../notes_pages.dart';
import '../widgets/afterimage_brand.dart';
import '../widgets/live_capture_panel.dart';
import '../ui/ui.dart';
import '../widgets/phase_indicator.dart';

/// Afterimage's only screen.
///
/// The application used to be two navigation destinations, Setup and Recorder,
/// which asked the user to decide where to go. Setup was never a peer of the
/// recorder; it was a precondition of it. There is now one screen that changes
/// state, so the interface always answers the single question this application
/// exists to answer: can I record right now, and if not, what do I fix.
class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    this.obsConnectionCard,
    required this.isRefreshing,
    required this.onRefresh,
    this.errorMessage,
    this.notesRepository,
    this.showNotes = false,
    this.selectedNote,
    this.notesSaving = false,
    this.onOpenNotes,
    this.onBackToNotesList,
    this.onCloseNotes,
    this.onNotesSavingChanged,
  });

  final RecorderController controller;
  final Widget? obsConnectionCard;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  /// A failure raised by the shell's own setup checks. Failures raised by the
  /// controller are read inside the listener below, not passed in, so that a
  /// change to them actually reaches the screen.
  final String? errorMessage;
  final NotesRepository? notesRepository;
  final bool showNotes;
  final NotePreview? selectedNote;

  /// Recordings are being written; leaving the page waits for that.
  final bool notesSaving;
  final ValueChanged<NotePreview?>? onOpenNotes;
  final VoidCallback? onBackToNotesList;
  final VoidCallback? onCloseNotes;
  final ValueChanged<bool>? onNotesSavingChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.phase;
        // Order matters. A recording failure outranks "your choices could not
        // be remembered", which is persistent and would otherwise mask it.
        final message = errorMessage ??
            controller.error?.toString() ??
            controller.preferenceNotice;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceHeader(
              phase: phase,
              controller: controller,
              notesAvailable:
                  notesRepository != null && phase != RecorderPhase.running,
              notesSaving: notesSaving,
              showingNotes: showNotes && phase != RecorderPhase.running,
              onOpenNotes: () => onOpenNotes?.call(null),
              onCloseNotes: onCloseNotes ?? () {},
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                // Pages start at the top. The default centres a short page in
                // the window, which left content floating mid-screen.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
                child: _page(phase, message),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The recorder page, with the live capture switch above it when the
  /// backend supports live capture. Sequences pages are returned as they are.
  Widget _page(RecorderPhase phase, String? message) {
    final notes =
        showNotes && notesRepository != null && phase != RecorderPhase.running;
    if (notes || !controller.liveCaptureSupported) {
      return _body(phase, message);
    }
    if (controller.liveCaptureActive) {
      return SingleChildScrollView(
        key: const ValueKey('live-page'),
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Capturing your matches', style: Ui.h1),
                const SizedBox(height: 4),
                const Text('The batch recorder is paused until you stop.',
                    style: Ui.bodyMid),
                const SizedBox(height: 20),
                LiveCaptureCard(controller: controller),
                const SizedBox(height: 16),
                LiveCaptureView(controller: controller),
              ],
            ),
          ),
        ),
      );
    }
    if (phase == RecorderPhase.running || phase == RecorderPhase.checking) {
      return _body(phase, message);
    }
    return Column(
      key: ValueKey('recorder-page-${phase.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: LiveCaptureCard(controller: controller),
            ),
          ),
        ),
        Expanded(child: _body(phase, message)),
      ],
    );
  }

  Widget _body(RecorderPhase phase, String? message) {
    if (showNotes &&
        notesRepository != null &&
        phase != RecorderPhase.running) {
      final selected = selectedNote;
      if (selected == null) {
        return NotesListPage(
          key: const ValueKey('notes-list-view'),
          repository: notesRepository!,
          onOpen: (preview) => onOpenNotes?.call(preview),
          onClose: onCloseNotes ?? () {},
        );
      }
      return NotesPage(
        key: ValueKey('notes-page-view-${selected.documentPath}'),
        repository: notesRepository!,
        preview: selected,
        onBack: onBackToNotesList ?? () {},
        onSavingChanged: onNotesSavingChanged,
      );
    }
    switch (phase) {
      case RecorderPhase.checking:
        return const _CheckingView(key: ValueKey('checking-view'));
      case RecorderPhase.blocked:
        return BlockedView(
          key: const ValueKey('blocked-view'),
          controller: controller,
          obsConnectionCard: obsConnectionCard,
          isRefreshing: isRefreshing,
          onRefresh: onRefresh,
          errorMessage: message,
        );
      case RecorderPhase.ready:
        return ReadyView(
          key: const ValueKey('ready-view'),
          controller: controller,
          isRefreshing: isRefreshing,
          onRefresh: onRefresh,
          errorMessage: message,
        );
      case RecorderPhase.running:
        return RunningView(
          key: const ValueKey('running-view'),
          controller: controller,
        );
      case RecorderPhase.done:
        return DoneView(
          key: const ValueKey('done-view'),
          controller: controller,
          notesRepository: notesRepository,
          onOpenNotes: notesSaving ? null : () => onOpenNotes?.call(null),
        );
    }
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.phase,
    required this.controller,
    required this.notesAvailable,
    required this.notesSaving,
    required this.showingNotes,
    required this.onOpenNotes,
    required this.onCloseNotes,
  });

  final RecorderPhase phase;
  final RecorderController controller;
  final bool notesAvailable;
  final bool notesSaving;
  final bool showingNotes;
  final VoidCallback onOpenNotes;
  final VoidCallback onCloseNotes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const AfterimageBrand(),
          const SizedBox(width: 26),
          if (notesAvailable) ...[
            _NavTab(
              tabKey: const ValueKey('close-notes'),
              label: 'Record',
              icon: Icons.fiber_manual_record_rounded,
              selected: !showingNotes,
              onTap: notesSaving || !showingNotes ? null : onCloseNotes,
            ),
            const SizedBox(width: 4),
            _NavTab(
              tabKey: const ValueKey('open-notes'),
              label: 'Sequences',
              icon: Icons.insights_rounded,
              selected: showingNotes,
              onTap: notesSaving ? null : onOpenNotes,
            ),
          ],
          const Spacer(),
          PhaseIndicator(phase: phase, controller: controller),
        ],
      ),
    );
  }
}

/// One of the two places in the application: recording, and reviewing.
class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.tabKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final Key tabKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1E2827) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: tabKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? Ui.ink : Ui.inkLow),
            const SizedBox(width: 8),
            Text(label,
                style: Ui.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? Ui.ink : Ui.inkMid)),
          ]),
        ),
      ),
    );
  }
}

/// Cold start, before the local checks have reported.
///
/// This is deliberately the blocked layout with a skeleton in it rather than a
/// fifth design, because it is on screen for well under a second and a distinct
/// layout would only make the application appear to flash between pages.
class _CheckingView extends StatelessWidget {
  const _CheckingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checking this computer',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 4),
            const SizedBox(height: 14),
            Text(
              'Looking for the game, your saved replays, and OBS. Nothing is '
              'installed or changed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
