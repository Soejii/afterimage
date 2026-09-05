import '../domain/recorder_contracts.dart';
import '../domain/replay_batch.dart';
import '../domain/replay_summary.dart';
import '../domain/setup_models.dart';
import 'replay_clock.dart';

typedef ReplayBatchEventSink = void Function(ReplayBatchEvent event);

class ReplayBatchEngine implements RecordingEngine {
  ReplayBatchEngine({
    required this.monitor,
    required this.menuInput,
    required this.obs,
    required this.organizer,
    ReplayClock? clock,
    SummaryWriterPort? summaryWriter,
    this.onEvent,
  })  : clock = clock ?? SystemReplayClock(),
        summaryWriter = summaryWriter ?? const NoopSummaryWriter();

  final ReplayMonitorPort monitor;
  final MenuInputPort menuInput;
  final ObsRecorderPort obs;
  final OutputOrganizerPort organizer;
  final ReplayClock clock;
  final SummaryWriterPort summaryWriter;
  final ReplayBatchEventSink? onEvent;

  bool _isRunning = false;
  bool _stopRequested = false;
  int _totalReplays = 0;
  int _currentReplay = 0;
  int _completedReplays = 0;
  ReplayBatchState _state = ReplayBatchState.idle;
  String? _detail;
  String? _currentOutputPath;

  @override
  bool get isRunning => _isRunning;

  ReplayBatchProgress get progress => _progress;

  ReplayBatchProgress get _progress => ReplayBatchProgress(
        state: _state,
        totalReplays: _totalReplays,
        currentReplay: _currentReplay,
        completedReplays: _completedReplays,
        detail: _detail,
        outputPath: _currentOutputPath,
      );

  @override
  Future<void> requestStop() async {
    if (_isRunning) {
      _stopRequested = true;
    }
  }

  @override
  Future<ReplayBatchResult> startBatch(ReplayBatchRequest request) async {
    if (_isRunning) {
      throw StateError('A replay batch is already running.');
    }

    _isRunning = true;
    _stopRequested = false;
    _totalReplays = request.replayCount;
    _currentReplay = 0;
    _completedReplays = 0;
    _state = ReplayBatchState.idle;
    _detail = null;
    _currentOutputPath = null;

    final replayResults = <ReplayResult>[];
    var combinedRecordingActive = false;
    OrganizedOutput? combinedOutput;
    RecordedOutput? combinedSourceOutput;

    try {
      try {
        _validateRequest(request);
      } catch (error) {
        return await _finishFailure(
          request,
          replayResults,
          error,
          detail: 'Batch configuration is invalid.',
        );
      }

      _emit(ReplayBatchEventType.started, message: 'Batch started.');
      _setState(
        ReplayBatchState.preparing,
        'Checking the monitor and OBS before the batch starts.',
      );
      await monitor.attach();
      await obs.connect();
      await obs.assertIdle();
      if (_stopRequested) {
        return await _finishStopped(
          request,
          replayResults,
          combinedOutput: combinedOutput,
          combinedSourceOutput: combinedSourceOutput,
        );
      }

      var remaining = request.timing.startupDelay;
      while (remaining > Duration.zero && !_stopRequested) {
        final seconds = (remaining.inMilliseconds / 1000).ceil();
        _setState(
            ReplayBatchState.preparing,
            menuInput is InputSafetyPort
                ? 'Switch to GGST now. Starting in $seconds… Keep the game active while recording.'
                : 'Starting in $seconds… Leave Saved Replays selected and do not use the game controls.');
        final step = remaining > const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : remaining;
        await clock.delay(step);
        remaining -= step;
      }
      if (_stopRequested) {
        return await _finishStopped(
          request,
          replayResults,
          combinedOutput: combinedOutput,
          combinedSourceOutput: combinedSourceOutput,
        );
      }

      _assertInputSafe();
      if (request.options.videoMode == VideoMode.combined) {
        _setState(
          ReplayBatchState.startingRecording,
          'Starting the combined OBS recording.',
        );
        await obs.startRecording();
        combinedRecordingActive = true;
      }

      for (var index = 1; index <= request.replayCount; index++) {
        if (_stopRequested) {
          Object? stopError;
          if (combinedRecordingActive) {
            final stopped = await _stopCombined(
              request,
              partial: true,
            );
            combinedRecordingActive = false;
            combinedOutput = stopped.output;
            combinedSourceOutput = stopped.source;
            stopError = stopped.error;
          }
          return await _finishStopped(
            request,
            replayResults,
            combinedOutput: combinedOutput,
            combinedSourceOutput: combinedSourceOutput,
            error: stopError,
          );
        }

        _currentReplay = index;
        final result = await _runReplay(
          request,
          index,
          combinedRecordingActive: combinedRecordingActive,
        );
        replayResults.add(result);
        await _writeSummary(
          request,
          replayResults,
          outcome: ReplaySummaryOutcome.running,
          combinedOutput: combinedOutput,
          combinedSourceOutput: combinedSourceOutput,
        );

        if (result.status != ReplayResultStatus.recorded) {
          Object? stopError;
          if (combinedRecordingActive) {
            final stopped = await _stopCombined(
              request,
              partial: true,
            );
            combinedRecordingActive = false;
            combinedOutput = stopped.output;
            combinedSourceOutput = stopped.source;
            stopError = stopped.error;
          }

          if (result.status == ReplayResultStatus.stopped) {
            return await _finishStopped(
              request,
              replayResults,
              combinedOutput: combinedOutput,
              combinedSourceOutput: combinedSourceOutput,
              error: _combineOptionalErrors(result.error, stopError),
            );
          }
          return await _finishFailure(
            request,
            replayResults,
            _combineErrors(
              result.error ?? StateError('Replay $index failed.'),
              stopError,
            ),
            combinedOutput: combinedOutput,
            combinedSourceOutput: combinedSourceOutput,
            detail: 'Stopped after the first replay failure.',
          );
        }

        _completedReplays++;
        if (index < request.replayCount) {
          await clock.delay(request.timing.menuDelay);
          if (_stopRequested) {
            Object? stopError;
            if (combinedRecordingActive) {
              final stopped = await _stopCombined(
                request,
                partial: true,
              );
              combinedRecordingActive = false;
              combinedOutput = stopped.output;
              combinedSourceOutput = stopped.source;
              stopError = stopped.error;
            }
            return await _finishStopped(
              request,
              replayResults,
              combinedOutput: combinedOutput,
              combinedSourceOutput: combinedSourceOutput,
              error: stopError,
            );
          }
          await menuInput.perform(ReplayMenuAction.selectNextReplay);
          await clock.delay(request.timing.actionDelay);
        }
      }

      if (combinedRecordingActive) {
        if (_stopRequested) {
          final stopped = await _stopCombined(
            request,
            partial: true,
          );
          combinedRecordingActive = false;
          combinedOutput = stopped.output;
          combinedSourceOutput = stopped.source;
          return await _finishStopped(
            request,
            replayResults,
            combinedOutput: combinedOutput,
            combinedSourceOutput: combinedSourceOutput,
            error: stopped.error,
          );
        }
        final stopped = await _stopCombined(
          request,
          partial: false,
        );
        combinedRecordingActive = false;
        combinedOutput = stopped.output;
        combinedSourceOutput = stopped.source;
        if (stopped.error != null) {
          return await _finishFailure(
            request,
            replayResults,
            stopped.error!,
            combinedOutput: combinedOutput,
            combinedSourceOutput: combinedSourceOutput,
            detail:
                'The combined recording was stopped but could not be finalized.',
          );
        }
      }

      try {
        await _writeSummary(
          request,
          replayResults,
          outcome: ReplaySummaryOutcome.completed,
          combinedOutput: combinedOutput,
          combinedSourceOutput: combinedSourceOutput,
        );
      } catch (summaryError) {
        return await _finishFailure(
          request,
          replayResults,
          summaryError,
          combinedOutput: combinedOutput,
          combinedSourceOutput: combinedSourceOutput,
          detail: 'The batch completed but its summary could not be saved.',
        );
      }

      _setState(ReplayBatchState.completed, 'Batch completed.');
      _emit(ReplayBatchEventType.completed, message: 'Batch completed.');
      return ReplayBatchResult(
        outcome: ReplayBatchOutcome.completed,
        replays: List.unmodifiable(replayResults),
        combinedOutput: combinedOutput,
        combinedSourceOutput: combinedSourceOutput,
      );
    } catch (error) {
      var finalError = error;
      if (combinedRecordingActive) {
        final stopped = await _stopCombined(
          request,
          partial: true,
        );
        combinedRecordingActive = false;
        combinedOutput = stopped.output;
        combinedSourceOutput = stopped.source;
        finalError = _combineErrors(finalError, stopped.error);
      }
      return await _finishFailure(
        request,
        replayResults,
        finalError,
        combinedOutput: combinedOutput,
        combinedSourceOutput: combinedSourceOutput,
        detail: 'The batch stopped safely after an unexpected failure.',
      );
    } finally {
      try {
        await monitor.close();
      } catch (_) {
        // Closing a monitor must not hide the batch result.
      }
      if (menuInput case final ClosableMenuInputPort closableInput) {
        try {
          await closableInput.close();
        } catch (_) {
          // Closing native input must not hide the batch result.
        }
      }
      try {
        await obs.close();
      } catch (_) {
        // Closing OBS must not hide the batch result.
      }
      if (summaryWriter case final ClosableSummaryWriterPort closableWriter) {
        try {
          await closableWriter.close();
        } catch (_) {
          // Releasing a summary lease must not hide the batch result.
        }
      }
      _isRunning = false;
    }
  }

  Future<ReplayResult> _runReplay(
    ReplayBatchRequest request,
    int index, {
    required bool combinedRecordingActive,
  }) async {
    var recordingActive = false;
    RecordedOutput? sourceOutput;
    OrganizedOutput? organizedOutput;

    try {
      _emit(
        ReplayBatchEventType.replayStarted,
        replayIndex: index,
        message: 'Replay $index/${request.replayCount} started.',
      );

      if (!combinedRecordingActive) {
        _setState(
          ReplayBatchState.startingRecording,
          'Starting the OBS recording for replay $index.',
        );
        await obs.startRecording();
        recordingActive = true;
      }

      if (_stopRequested) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }

      _setState(
        ReplayBatchState.openingReplay,
        'Opening replay $index in GGST.',
      );
      await menuInput.perform(ReplayMenuAction.openReplay);
      await clock.delay(request.timing.actionDelay);
      if (_stopRequested) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }

      final detector = ReplayCompletionDetector(
        absentPollsRequired: request.timing.absentPollsRequired,
      );
      _setState(
        ReplayBatchState.waitingForBattleStart,
        'Waiting for frame movement in replay $index.',
      );
      final startStatus = await _waitForBattleStart(detector, request.timing);
      if (startStatus == _WaitStatus.stopped) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }
      if (startStatus == _WaitStatus.timeout) {
        throw TimeoutException('Replay $index did not start.');
      }

      _setState(
        ReplayBatchState.recordingReplay,
        'Replay $index is moving.',
      );
      _emit(
        ReplayBatchEventType.battleStarted,
        replayIndex: index,
        message: 'Replay $index battle started after frame movement.',
      );

      _setState(
        ReplayBatchState.waitingForReplayEnd,
        'Waiting for the match result or a sustained missing read.',
      );
      final endStatus = await _waitForReplayEnd(detector, request.timing);
      if (endStatus == _WaitStatus.stopped) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }
      if (endStatus == _WaitStatus.timeout) {
        throw TimeoutException('Replay $index exceeded its replay timeout.');
      }

      final reason = detector.reason;
      _emit(
        ReplayBatchEventType.replayCompleted,
        replayIndex: index,
        message: 'Replay $index completed by ${_reasonLabel(reason)}.',
      );
      await clock.delay(request.timing.resultDelay);
      if (_stopRequested) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }

      if (!combinedRecordingActive) {
        _setState(
          ReplayBatchState.stoppingRecording,
          'Stopping the OBS recording for replay $index.',
        );
        sourceOutput = await obs.stopRecording();
        _currentOutputPath = sourceOutput.path;
        recordingActive = false;
        organizedOutput = await organizer.organizeReplay(
          source: sourceOutput,
          outputDirectory: request.options.outputDirectory,
          replayIndex: index,
          partial: false,
        );
        _currentOutputPath = organizedOutput.path;
        _emit(
          ReplayBatchEventType.outputSaved,
          replayIndex: index,
          output: organizedOutput,
          message: 'Replay $index output saved.',
        );
      }

      if (_stopRequested) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }

      _setState(
        ReplayBatchState.returningToReplayList,
        'Returning to the replay list before advancing.',
      );
      await menuInput.perform(ReplayMenuAction.exitToReplayList);
      await clock.delay(request.timing.actionDelay);
      final listStatus = await _waitForReplayList(request.timing);
      if (listStatus == _WaitStatus.stopped) {
        return await _stopReplay(
          request,
          index,
          recordingActive: recordingActive,
          sourceOutput: sourceOutput,
          organizedOutput: organizedOutput,
        );
      }
      if (listStatus == _WaitStatus.timeout) {
        throw TimeoutException(
          'GGST did not return to the replay list after replay $index.',
        );
      }

      return ReplayResult(
        index: index,
        status: ReplayResultStatus.recorded,
        output: organizedOutput,
        sourceOutput: sourceOutput,
      );
    } catch (error) {
      return _failReplay(
        request,
        index,
        error,
        recordingActive: recordingActive,
        sourceOutput: sourceOutput,
        organizedOutput: organizedOutput,
      );
    }
  }

  Future<ReplayResult> _failReplay(
    ReplayBatchRequest request,
    int index,
    Object error, {
    required bool recordingActive,
    required RecordedOutput? sourceOutput,
    required OrganizedOutput? organizedOutput,
  }) async {
    var finalError = error;
    var active = recordingActive;
    var source = sourceOutput;
    var organized = organizedOutput;

    if (active) {
      _setState(
        ReplayBatchState.stoppingRecording,
        'Stopping replay $index safely after a failure.',
      );
      try {
        source = await obs.stopRecording();
        _currentOutputPath = source.path;
        active = false;
      } catch (stopError) {
        active = false;
        finalError = _combineErrors(finalError, stopError);
      }
    }
    if (source != null && organized == null) {
      try {
        organized = await organizer.organizeReplay(
          source: source,
          outputDirectory: request.options.outputDirectory,
          replayIndex: index,
          partial: true,
        );
        _currentOutputPath = organized.path;
        _emit(
          ReplayBatchEventType.outputSaved,
          replayIndex: index,
          output: organized,
          message: 'Partial output for replay $index was preserved.',
        );
      } catch (organizeError) {
        finalError = _combineErrors(finalError, organizeError);
      }
    }

    final result = ReplayResult(
      index: index,
      status: ReplayResultStatus.failed,
      output: organized,
      sourceOutput: source,
      error: finalError,
    );
    _emit(
      ReplayBatchEventType.replayFailed,
      replayIndex: index,
      message: 'Replay $index failed safely.',
      error: finalError,
      output: organized,
    );
    return result;
  }

  Future<ReplayResult> _stopReplay(
    ReplayBatchRequest request,
    int index, {
    required bool recordingActive,
    required RecordedOutput? sourceOutput,
    required OrganizedOutput? organizedOutput,
  }) async {
    var active = recordingActive;
    var source = sourceOutput;
    var organized = organizedOutput;
    Object? error;

    if (active) {
      _setState(
        ReplayBatchState.stoppingRecording,
        'Stopping replay $index after the stop request.',
      );
      try {
        source = await obs.stopRecording();
        _currentOutputPath = source.path;
        active = false;
      } catch (stopError) {
        active = false;
        error = stopError;
      }
    }
    if (source != null && organized == null) {
      try {
        organized = await organizer.organizeReplay(
          source: source,
          outputDirectory: request.options.outputDirectory,
          replayIndex: index,
          partial: true,
        );
        _currentOutputPath = organized.path;
        _emit(
          ReplayBatchEventType.outputSaved,
          replayIndex: index,
          output: organized,
          message: 'Partial output for replay $index was preserved.',
        );
      } catch (organizeError) {
        error = _combineErrors(error, organizeError);
      }
    }

    final result = ReplayResult(
      index: index,
      status: ReplayResultStatus.stopped,
      output: organized,
      sourceOutput: source,
      error: error,
    );
    _emit(
      ReplayBatchEventType.replayStopped,
      replayIndex: index,
      message: 'Replay $index stopped safely.',
      error: error,
      output: organized,
    );
    return result;
  }

  void _assertInputSafe() {
    if (!_stopRequested) {
      if (menuInput case final InputSafetyPort guarded) {
        guarded.assertInputSafe();
      }
    }
  }

  Future<_WaitStatus> _waitForBattleStart(
    ReplayCompletionDetector detector,
    ReplayBatchTiming timing,
  ) async {
    final deadline = clock.elapsed + timing.startTimeout;
    while (clock.elapsed < deadline) {
      _assertInputSafe();
      final snapshot = await monitor.snapshot();
      if (_stopRequested) {
        return _WaitStatus.stopped;
      }
      detector.observe(snapshot);
      if (detector.battleStarted) {
        return _WaitStatus.satisfied;
      }
      await clock.delay(timing.pollInterval);
    }
    return _WaitStatus.timeout;
  }

  Future<_WaitStatus> _waitForReplayEnd(
    ReplayCompletionDetector detector,
    ReplayBatchTiming timing,
  ) async {
    final deadline = clock.elapsed + timing.replayTimeout;
    while (clock.elapsed < deadline) {
      _assertInputSafe();
      final snapshot = await monitor.snapshot();
      if (_stopRequested) {
        return _WaitStatus.stopped;
      }
      if (detector.observe(snapshot)) {
        return _WaitStatus.satisfied;
      }
      await clock.delay(timing.pollInterval);
    }
    return _WaitStatus.timeout;
  }

  Future<_WaitStatus> _waitForReplayList(ReplayBatchTiming timing) async {
    final deadline = clock.elapsed + timing.returnToListTimeout;
    var listPolls = 0;
    while (clock.elapsed < deadline) {
      _assertInputSafe();
      final snapshot = await monitor.snapshot();
      if (_stopRequested) {
        return _WaitStatus.stopped;
      }
      if (!snapshot.enginePresent || snapshot.frame == 0) {
        listPolls++;
        if (listPolls >= timing.listConfirmationPolls) {
          return _WaitStatus.satisfied;
        }
      } else {
        listPolls = 0;
      }
      await clock.delay(timing.pollInterval);
    }
    return _WaitStatus.timeout;
  }

  Future<_CombinedStop> _stopCombined(
    ReplayBatchRequest request, {
    required bool partial,
  }) async {
    _setState(
      ReplayBatchState.stoppingRecording,
      partial
          ? 'Stopping the combined recording and preserving partial output.'
          : 'Stopping the combined recording.',
    );
    RecordedOutput? source;
    OrganizedOutput? output;
    Object? error;
    try {
      source = await obs.stopRecording();
      _currentOutputPath = source.path;
    } catch (stopError) {
      error = stopError;
    }
    if (source != null) {
      try {
        output = await organizer.organizeCombined(
          source: source,
          outputDirectory: request.options.outputDirectory,
          partial: partial,
        );
        _currentOutputPath = output.path;
        _emit(
          ReplayBatchEventType.outputSaved,
          output: output,
          message: partial
              ? 'Partial combined output was preserved.'
              : 'Combined output was saved.',
        );
      } catch (organizeError) {
        error = _combineErrors(error, organizeError);
      }
    }
    return _CombinedStop(
      output: output,
      source: source,
      error: error,
    );
  }

  Future<ReplayBatchResult> _finishFailure(
    ReplayBatchRequest request,
    List<ReplayResult> replayResults,
    Object error, {
    OrganizedOutput? combinedOutput,
    RecordedOutput? combinedSourceOutput,
    required String detail,
  }) async {
    var finalError = error;
    try {
      await _writeSummary(
        request,
        replayResults,
        outcome: ReplaySummaryOutcome.failed,
        combinedOutput: combinedOutput,
        combinedSourceOutput: combinedSourceOutput,
        error: error,
      );
    } catch (summaryError) {
      finalError = _combineErrors(finalError, summaryError);
    }
    _setState(ReplayBatchState.failed, detail);
    _emit(
      ReplayBatchEventType.failed,
      message: detail,
      error: finalError,
    );
    return ReplayBatchResult(
      outcome: ReplayBatchOutcome.failed,
      replays: List.unmodifiable(replayResults),
      combinedOutput: combinedOutput,
      combinedSourceOutput: combinedSourceOutput,
      error: finalError,
    );
  }

  Future<ReplayBatchResult> _finishStopped(
    ReplayBatchRequest request,
    List<ReplayResult> replayResults, {
    OrganizedOutput? combinedOutput,
    RecordedOutput? combinedSourceOutput,
    Object? error,
  }) async {
    Object? finalError = error;
    try {
      await _writeSummary(
        request,
        replayResults,
        outcome: ReplaySummaryOutcome.stopped,
        combinedOutput: combinedOutput,
        combinedSourceOutput: combinedSourceOutput,
        error: error,
      );
    } catch (summaryError) {
      finalError = _combineErrors(finalError, summaryError);
    }
    _setState(
        ReplayBatchState.stopped, 'Stop requested. Current output preserved.');
    _emit(
      ReplayBatchEventType.stopped,
      message: 'Stop requested. Current output preserved.',
    );
    return ReplayBatchResult(
      outcome: ReplayBatchOutcome.stopped,
      replays: List.unmodifiable(replayResults),
      combinedOutput: combinedOutput,
      combinedSourceOutput: combinedSourceOutput,
      error: finalError,
    );
  }

  Future<void> _writeSummary(
    ReplayBatchRequest request,
    Iterable<ReplayResult> replayResults, {
    required ReplaySummaryOutcome outcome,
    OrganizedOutput? combinedOutput,
    RecordedOutput? combinedSourceOutput,
    Object? error,
  }) {
    return summaryWriter.write(
      outputDirectory: request.options.outputDirectory,
      summary: ReplayBatchSummary.fromResults(
        updatedAt: DateTime.now(),
        outcome: outcome,
        replays: replayResults,
        combinedOutput: combinedOutput,
        combinedSourceOutput: combinedSourceOutput,
        error: error,
      ),
    );
  }

  void _validateRequest(ReplayBatchRequest request) {
    if (request.replayCount <= 0) {
      throw ArgumentError.value(
        request.replayCount,
        'replayCount',
        'must be greater than zero',
      );
    }
    if (request.options.outputDirectory.trim().isEmpty) {
      throw ArgumentError.value(
        request.options.outputDirectory,
        'outputDirectory',
        'must not be empty',
      );
    }
    final timing = request.timing;
    if (timing.pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        timing.pollInterval,
        'pollInterval',
        'must be greater than zero',
      );
    }
    if (timing.startTimeout < Duration.zero ||
        timing.replayTimeout < Duration.zero ||
        timing.returnToListTimeout < Duration.zero ||
        timing.resultDelay < Duration.zero ||
        timing.startupDelay < Duration.zero ||
        timing.menuDelay < Duration.zero ||
        timing.actionDelay < Duration.zero) {
      throw ArgumentError('Batch timing values must not be negative.');
    }
    if (timing.listConfirmationPolls <= 0) {
      throw ArgumentError.value(
        timing.listConfirmationPolls,
        'listConfirmationPolls',
        'must be greater than zero',
      );
    }
    // Force validation of the duration-derived missing-read threshold.
    timing.absentPollsRequired;
  }

  void _setState(ReplayBatchState state, String detail) {
    _state = state;
    _detail = detail;
    _emit(
      ReplayBatchEventType.stateChanged,
      message: detail,
    );
  }

  void _emit(
    ReplayBatchEventType type, {
    int? replayIndex,
    String? message,
    Object? error,
    OrganizedOutput? output,
  }) {
    final sink = onEvent;
    if (sink == null) {
      return;
    }
    try {
      sink(
        ReplayBatchEvent(
          type: type,
          progress: _progress,
          replayIndex: replayIndex,
          message: message,
          error: error,
          output: output,
        ),
      );
    } catch (_) {
      // A UI listener must not interrupt a recording lifecycle.
    }
  }

  String _reasonLabel(ReplayCompletionReason? reason) {
    switch (reason) {
      case ReplayCompletionReason.matchResultEvent:
        return 'match result event';
      case ReplayCompletionReason.battleStateDisappeared:
        return 'sustained missing battle state';
      case null:
        return 'unknown reason';
    }
  }

  Object _combineErrors(Object? first, Object? second) {
    if (first == null) {
      return second ?? StateError('The batch failed without an error detail.');
    }
    if (second == null) {
      return first;
    }
    return StateError('$first; safe stop/finalize also failed: $second');
  }

  Object? _combineOptionalErrors(Object? first, Object? second) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return _combineErrors(first, second);
  }
}

enum _WaitStatus {
  satisfied,
  timeout,
  stopped,
}

class _CombinedStop {
  const _CombinedStop({
    required this.output,
    required this.source,
    required this.error,
  });

  final OrganizedOutput? output;
  final RecordedOutput? source;
  final Object? error;
}

class TimeoutException implements Exception {
  const TimeoutException(this.message);

  final String message;

  @override
  String toString() => message;
}
