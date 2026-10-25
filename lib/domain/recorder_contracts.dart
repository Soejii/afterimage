import 'replay_batch.dart';
import 'replay_summary.dart';
import 'setup_models.dart';

class NativeBackendReadiness {
  const NativeBackendReadiness({
    required this.available,
    required this.detail,
  });

  final bool available;
  final String detail;
}

/// Reads the live GGST process. Platform adapters implement this contract for
/// Windows and Linux; the batch engine never reads process memory directly.
abstract interface class ReplayMonitorPort {
  Future<void> attach();

  Future<BattleSnapshot> snapshot();

  Future<void> close();
}

/// Optional monitor detail that lets frame capture reuse the resolved static
/// GWorld pointer address without making the engine depend on Linux adapters.
abstract interface class ReplayMonitorGWorldPointerPort {
  int? get gWorldPointerAddress;
}

/// Semantic actions keep the engine independent of keyboard and controller
/// details. Each platform/input adapter maps these actions to its own device.
enum ReplayMenuAction {
  /// Opens the replay's context menu with one confirm press.
  openReplayMenu,

  /// Confirms the highlighted item in the context menu.
  confirmMenuItem,
  exitToReplayList,
  selectNextReplay,
}

enum ScreenCheck {
  replayList,
  replayMenuViewHighlighted,
}

class ScreenCheckResult {
  const ScreenCheckResult({
    required this.matched,
    required this.score,
    this.error,
  });

  final bool matched;
  final double score;
  final Object? error;
}

abstract interface class ScreenGuardPort {
  Future<ScreenCheckResult> check(ScreenCheck check);
}

class NoopScreenGuard implements ScreenGuardPort {
  const NoopScreenGuard();

  @override
  Future<ScreenCheckResult> check(ScreenCheck check) async =>
      const ScreenCheckResult(matched: true, score: 0);
}

class UnavailableScreenGuard implements ScreenGuardPort {
  const UnavailableScreenGuard(this.detail);

  final String detail;

  @override
  Future<ScreenCheckResult> check(ScreenCheck check) async =>
      ScreenCheckResult(matched: false, score: 255, error: detail);
}

abstract interface class InputSafetyPort {
  void assertInputSafe();
}

abstract interface class MenuInputPort {
  Future<void> perform(ReplayMenuAction action);
}

/// Optional lifecycle extension for native input ports. Existing test and
/// platform adapters that do not own native resources can implement only
/// [MenuInputPort].
abstract interface class ClosableMenuInputPort {
  Future<void> close();
}

/// The OBS adapter owns the connection and returns the source file produced by
/// StopRecord. It must never take over an active recording unexpectedly.
abstract interface class ObsRecorderPort {
  Future<void> connect();

  Future<void> assertIdle();

  Future<void> startRecording();

  Future<RecordedOutput> stopRecording();

  Future<void> close();
}

/// Organizers move completed or partial OBS outputs without deleting an output
/// when a destination already exists or the move cannot be completed.
abstract interface class OutputOrganizerPort {
  Future<OrganizedOutput> organizeReplay({
    required RecordedOutput source,
    required String outputDirectory,
    required int replayIndex,
    required bool partial,
  });

  Future<OrganizedOutput> organizeCombined({
    required RecordedOutput source,
    required String outputDirectory,
    required bool partial,
  });
}

/// Persists a checkpoint after each replay and a terminal batch state. A
/// writer must never serialize connection credentials.
abstract interface class SummaryWriterPort {
  Future<void> write({
    required String outputDirectory,
    required ReplayBatchSummary summary,
  });
}

abstract interface class ClosableSummaryWriterPort
    implements SummaryWriterPort {
  Future<void> close();
}

/// Optional replay frame capture. Capture data is auxiliary, so implementations
/// report their own failure instead of changing the recording result.
abstract interface class FrameCapturePort {
  Future<void> start({
    required int replayIndex,
    required String outputPath,
    int? gWorldPointerAddress,
  });

  Future<FrameCaptureResult> stop({required FrameCaptureEndReason reason});

  Future<void> close();
}

/// Optional emergency stop used when a capture isolate does not respond to a
/// normal stop request within the batch safety bound.
abstract interface class AbortableFrameCapturePort {
  Future<FrameCaptureResult> abort();
}

class NoopFrameCapturePort implements FrameCapturePort {
  const NoopFrameCapturePort();

  @override
  Future<void> start({
    required int replayIndex,
    required String outputPath,
    int? gWorldPointerAddress,
  }) async {}

  @override
  Future<FrameCaptureResult> stop(
          {required FrameCaptureEndReason reason}) async =>
      const FrameCaptureResult();

  @override
  Future<void> close() async {}
}

/// Optional extension for platform backends that implement frame capture.
/// Existing backend fakes and unsupported platforms need not implement it.
abstract interface class FrameCaptureAwareNativeRecorderBackend {
  bool get supportsFrameCapture;

  String? get frameCaptureUnsupportedReason;

  Future<FrameCapturePort> openFrameCapture();
}

/// Optional engine extension so existing engine factories remain compatible.
abstract interface class FrameCaptureAwareRecordingEngine
    implements RecordingEngine {
  void configureFrameCapture(FrameCapturePort port);
}

/// Optional engine extension so existing engine factories remain compatible.
abstract interface class ScreenGuardAwareRecordingEngine
    implements RecordingEngine {
  void configureScreenGuard(ScreenGuardPort port);
}

class FailedFrameCapturePort implements FrameCapturePort {
  const FailedFrameCapturePort(this.failure);

  final Object failure;

  @override
  Future<void> start({
    required int replayIndex,
    required String outputPath,
    int? gWorldPointerAddress,
  }) async {
    throw failure;
  }

  @override
  Future<FrameCaptureResult> stop(
          {required FrameCaptureEndReason reason}) async =>
      FrameCaptureResult(error: failure.toString());

  @override
  Future<void> close() async {}
}

class NoopSummaryWriter implements SummaryWriterPort {
  const NoopSummaryWriter();

  @override
  Future<void> write({
    required String outputDirectory,
    required ReplayBatchSummary summary,
  }) async {}
}

/// A monotonic clock makes timeout and poll behavior testable without waiting
/// in wall-clock time.
abstract interface class ReplayClock {
  Duration get elapsed;

  Future<void> delay(Duration duration);
}

/// Platform-specific memory, input, and recording integration is assembled by
/// this contract once the native implementation exists.
abstract interface class NativeRecorderBackend {
  Future<NativeBackendReadiness> inspect();

  Future<ReplayMonitorPort> openReplayMonitor();

  Future<MenuInputPort> openMenuInput(InputMode mode);

  Future<ObsRecorderPort> openObsRecorder();

  Future<OutputOrganizerPort> openOutputOrganizer();
}

/// Optional extension for backends that can report support for each input
/// mode without opening a native input session. Older backends can keep using
/// [NativeRecorderBackend] and the recorder controller will probe the selected
/// input port as a safe fallback.
abstract interface class InputModeAwareNativeRecorderBackend {
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode);
}

abstract interface class RecordingEngine {
  bool get isRunning;

  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request);

  Future<void> requestStop();
}

class RecorderUnavailableException implements Exception {
  const RecorderUnavailableException([
    this.message = 'The native recorder backend is not available yet.',
  ]);

  final String message;

  @override
  String toString() => message;
}
