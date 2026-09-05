import '../domain/setup_models.dart';

/// One reason recording is locked, in a form the interface can act on.
///
/// The recorder used to expose blockers as a flat `List<String>`, which forced
/// every screen to render them as an undifferentiated bullet list and made it
/// easy to paste the same list into two places. A blocker now carries its own
/// identity, a short label, a sentence for the user, and the single action that
/// resolves it, so one view can lead with the most important blocker and still
/// summarise the rest.
enum RecorderBlockerId {
  // Ordered by the sequence a new user has to resolve them in. The declaration
  // order is the priority order; `index` decides which blocker leads.
  platformUnsupported,
  recorderBackend,
  checksRunning,
  gameInstall,
  obsConnection,
  gameRunning,
  replayLibrary,
  inputUnavailable,
  inputChecking,
  outputFolder,
  replayCountUnavailable,
  replayCountInvalid,
}

/// Where a blocker comes from, which decides where it is shown.
///
/// A blocker caused by the environment belongs on the blocked screen, because
/// nothing in the batch form can fix it. A blocker caused by the batch form
/// itself must NOT take that form off screen, or the control that resolves it
/// disappears along with it and the user is trapped until they restart.
enum RecorderBlockerSource {
  /// The computer, the game, or OBS. Resolved outside the batch form.
  environment,

  /// A value the user chose in the batch form. Resolved by editing that form.
  options,
}

/// The single thing the interface offers to resolve a blocker.
enum RecorderBlockerAction {
  none,
  refreshChecks,
  connectObs,
  chooseOutputFolder,
  locateGame,
  locateReplays,
  openAdvancedOptions,
}

class RecorderBlocker implements Comparable<RecorderBlocker> {
  const RecorderBlocker({
    required this.id,
    required this.label,
    required this.message,
    this.source = RecorderBlockerSource.environment,
    this.action = RecorderBlockerAction.none,
  });

  /// Which blocker this is. Also its priority, through [RecorderBlockerId.index].
  final RecorderBlockerId id;

  /// Whether the batch form can resolve this, which decides where it is shown.
  final RecorderBlockerSource source;

  /// Two or three words naming the subject, for the status strip.
  final String label;

  /// One sentence telling the user what is wrong and what to do.
  final String message;

  /// The action that resolves it, or [RecorderBlockerAction.none] when only the
  /// user can resolve it outside Afterimage.
  final RecorderBlockerAction action;

  @override
  int compareTo(RecorderBlocker other) => id.index.compareTo(other.id.index);

  @override
  String toString() => '$label: $message';
}

/// Maps a blocked setup check onto its blocker identity and label.
///
/// Returns null for a check that does not block recording on its own, which
/// keeps optional checks such as the unselected input mode out of the list.
RecorderBlocker? blockerForCheck(SetupCheck check) {
  switch (check.id) {
    case SetupCheckId.supportedPlatform:
      return RecorderBlocker(
        id: RecorderBlockerId.platformUnsupported,
        label: 'This computer',
        message: check.detail,
      );
    case SetupCheckId.nativeRecorderBackend:
      return RecorderBlocker(
        id: RecorderBlockerId.recorderBackend,
        label: 'Recording support',
        message: check.detail,
      );
    case SetupCheckId.gameInstall:
      return RecorderBlocker(
        id: RecorderBlockerId.gameInstall,
        label: 'Game',
        message: check.detail,
        action: RecorderBlockerAction.locateGame,
      );
    case SetupCheckId.gameRunning:
      return RecorderBlocker(
        id: RecorderBlockerId.gameRunning,
        label: 'Game',
        message: check.detail,
        action: RecorderBlockerAction.refreshChecks,
      );
    case SetupCheckId.obsWebSocket:
      return RecorderBlocker(
        id: RecorderBlockerId.obsConnection,
        label: 'OBS',
        message: check.detail,
        action: RecorderBlockerAction.connectObs,
      );
    case SetupCheckId.replayLibrary:
      return RecorderBlocker(
        id: RecorderBlockerId.replayLibrary,
        label: 'Saved replays',
        message: check.detail,
        action: RecorderBlockerAction.locateReplays,
      );
    case SetupCheckId.keyboardInput:
    case SetupCheckId.controllerInput:
      // Input readiness blocks only for the mode the user actually selected,
      // which the controller adds separately. A blocked check for the other
      // mode is information, not a blocker.
      return null;
  }
}

/// Which of the workspace's states is on screen.
///
/// Afterimage is one screen that changes state, not a set of pages. The
/// controller derives this so no widget has to reconstruct it from a handful
/// of booleans and get it subtly wrong.
enum RecorderPhase {
  /// Cold start: the local checks have not reported yet.
  checking,

  /// Something prevents recording. The user is shown the leading blocker.
  blocked,

  /// Everything passed. The batch form is on screen.
  ready,

  /// A batch is running. Progress takes the whole window.
  running,

  /// A batch finished, was stopped, or failed, and its result is on screen.
  done,
}
