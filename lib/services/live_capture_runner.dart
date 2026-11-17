import 'dart:io';

import '../domain/finder_contracts.dart';
import '../domain/recorder_contracts.dart';
import '../domain/replay_batch.dart';
import '../domain/replay_summary.dart';
import '../domain/setup_models.dart';
import 'linux_frame_capture.dart';
import 'summary_writer.dart';

/// Read-only state used by the live watcher. Failed reads must throw, not
/// return zero, because zero is a game boundary.
abstract interface class LiveCaptureSource implements LinuxFrameCaptureSource {
  int readWriteSolid();
  bool get processAlive;
}

class ForbiddenLiveInput implements MenuInputPort {
  const ForbiddenLiveInput();
  @override
  Future<void> perform(ReplayMenuAction action) =>
      throw StateError('Live capture must never send input.');
}

class ForbiddenLiveObs implements ObsRecorderPort {
  const ForbiddenLiveObs();
  Never _forbidden() => throw StateError('Live capture must never use OBS.');
  @override
  Future<void> connect() => _forbidden();
  @override
  Future<void> assertIdle() => _forbidden();
  @override
  Future<void> startRecording() => _forbidden();
  @override
  Future<RecordedOutput> stopRecording() => _forbidden();
  @override
  Future<void> close() => _forbidden();
}

/// Runs a single live session on an isolate that owns the memory source.
/// [reserveDirectory] must atomically reserve a new, empty directory.
class LiveCaptureRunner {
  LiveCaptureRunner({
    required this.source,
    required this.clock,
    required this.reserveDirectory,
    required this.menuInput,
    required this.obs,
    this.finder,
    this.onGame,
  });

  final LiveCaptureSource source;
  final ReplayClock clock;
  final Future<String> Function() reserveDirectory;
  final MenuInputPort menuInput;
  final ObsRecorderPort obs;
  final FinderPort? finder;
  final void Function(int count)? onGame;
  bool _stop = false;
  void requestStop() => _stop = true;

  Future<String?> run() async {
    String? directory;
    final entries = <ReplaySummaryEntry>[];
    final writer = FileSummaryWriter();
    Future<void> checkpoint(ReplaySummaryOutcome outcome) async {
      await writer.write(
        outputDirectory: directory!,
        summary: ReplayBatchSummary(
          updatedAt: DateTime.now(),
          outcome: outcome,
          replays: List.of(entries),
          videoMode: VideoMode.none,
          source: 'live',
        ),
      );
    }

    try {
      var armed = false;
      while (!_stop && source.processAlive) {
        if (source.readWriteSolid() == 0) {
          armed = true;
          await clock.delay(const Duration(milliseconds: 16));
          continue;
        }
        if (!armed) {
          await clock.delay(const Duration(milliseconds: 16));
          continue;
        }
        armed = false;
        directory ??= await reserveDirectory();
        final index = entries.length + 1;
        final name = 'replay_${index.toString().padLeft(3, '0')}.frames.jsonl';
        final path = '$directory${Platform.pathSeparator}$name';
        final sink = await LinuxFrameCaptureFileSink.create(path);
        final captureStart = clock.elapsed;
        var reason = FrameCaptureEndReason.completed;
        var lastCheck = clock.elapsed - const Duration(milliseconds: 16);
        bool finished() {
          if (_stop) {
            reason = FrameCaptureEndReason.stopped;
            return true;
          }
          if (clock.elapsed - lastCheck < const Duration(milliseconds: 16)) {
            return false;
          }
          lastCheck = clock.elapsed;
          if (!source.processAlive) {
            reason = FrameCaptureEndReason.aborted;
            return true;
          }
          try {
            if (source.readWriteSolid() == 0) return true;
          } catch (_) {
            if (!source.processAlive) {
              reason = FrameCaptureEndReason.aborted;
              return true;
            }
            rethrow;
          }
          return false;
        }

        final result = await runLinuxFrameCaptureSession(
          replayIndex: index,
          source: source,
          sink: sink,
          elapsed: () => clock.elapsed - captureStart,
          delay: clock.delay,
          startedUtc: DateTime.now().toUtc().toIso8601String(),
          live: true,
          shouldStop: finished,
          endReason: () => reason,
          outputPath: path,
        );
        entries.add(ReplaySummaryEntry(
          index: index,
          status: result.error != null
              ? 'failed'
              : reason == FrameCaptureEndReason.completed
                  ? 'recorded'
                  : 'stopped',
          capture: ReplayCaptureSummary(
            path: name,
            videoOffsetMs: 0,
            rows: result.rows,
            frameGaps: result.frameGaps,
            maxFrameGap: result.maxFrameGap,
            error: result.error,
          ),
        ));
        await checkpoint(ReplaySummaryOutcome.running);
        onGame?.call(entries.length);
        if (result.error != null) throw StateError(result.error!);
        if (reason != FrameCaptureEndReason.completed) break;
        armed = true;
      }
      if (directory != null) {
        await checkpoint(ReplaySummaryOutcome.completed);
        final finder = this.finder;
        if (finder != null && finder.available) {
          await finder.startBatch(directory, reference: false, clips: false);
        }
      }
      return directory;
    } finally {
      await writer.close();
    }
  }
}
