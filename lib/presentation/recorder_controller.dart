import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/recorder_contracts.dart';
import '../domain/replay_batch.dart';
import '../domain/setup_models.dart';
import '../services/obs_connection_service.dart';
import '../services/batch_output_directory.dart';
import '../services/recorder_preferences.dart';
import '../services/setup_locations.dart';
import '../services/output_launcher.dart';
import '../services/output_directory_picker.dart';
import '../services/output_directory_preflight.dart';
import '../services/replay_batch_engine.dart';
import '../services/summary_writer.dart';

typedef ReplayBatchEngineFactory = RecordingEngine Function({
  required ReplayMonitorPort monitor,
  required MenuInputPort menuInput,
  required ObsRecorderPort obs,
  required OutputOrganizerPort organizer,
  required ReplayBatchEventSink onEvent,
});

typedef OutputDirectoryPicker = Future<String?> Function();

/// A platform-neutral view model for the recorder screen.
///
/// Native adapters are injected through [NativeRecorderBackend]. The
/// controller owns the short-lived ports for a batch, forwards engine events
/// to the UI, and keeps all start/stop lifecycle guards in one place.
class RecorderController extends ChangeNotifier {
  RecorderController({
    this.obsConnection,
    BatchOutputDirectory? batchDirectories,
    this.preferences,
    OutputLauncher? outputLauncher,
    required this.backend,
    this.engineFactory = _createReplayBatchEngine,
    this.directoryPicker = pickOutputDirectory,
    this.outputPreflight = const FileOutputDirectoryPreflight(),
    RecordingOptions options = const RecordingOptions(),
  }) : _options = options,
        batchDirectories = batchDirectories ?? BatchOutputDirectory(),
        outputLauncher = outputLauncher ?? OutputLauncher() {
    obsConnection?.addListener(_onObsChanged);
  }

  final ObsConnectionService? obsConnection;
  final BatchOutputDirectory batchDirectories;
  String? batchOutputDirectory;
  final RecorderPreferences? preferences;
  LocalSetupLocations setupLocations = const LocalSetupLocations();
  final List<String> _recentOutputPaths = [];
  List<String> get recentOutputPaths => List.unmodifiable(_recentOutputPaths);
  String? _recentOutputDirectory;
  bool _initialized = false;
  String? preferenceNotice;

  final OutputLauncher outputLauncher;
  final NativeRecorderBackend backend;
  Completer<void>? _batchDone;

  Future<void> stopAndWait() async {
    final done = _batchDone;
    await requestStop();
    await done?.future;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final before = _options;
    final saved = await preferences?.load();
    if (_disposed || saved == null) return;
    if (identical(before, _options)) {
      T readEnum<T extends Enum>(List<T> values, String key, T fallback) {
        for (final value in values) {
          if (value.name == saved[key]) return value;
        }
        return fallback;
      }

      final path = saved['outputDirectory'];
      final count = saved['customReplayCount'];
      _options = _options.copyWith(
        replayCount: readEnum(
            ReplayCountOption.values, 'replayCount', _options.replayCount),
        videoMode: readEnum(VideoMode.values, 'videoMode', _options.videoMode),
        inputMode: readEnum(InputMode.values, 'inputMode', _options.inputMode),
        customReplayCount:
            count is int && count > 0 && count <= 1000 ? count : 1,
        outputDirectory: _storedPath(path) ?? _options.outputDirectory,
      );
      setupLocations = LocalSetupLocations(
        gameDirectory: _storedPath(saved['gameDirectory']),
        replayDirectory: _storedPath(saved['replayDirectory']),
      );
      final recent = saved['recentOutputs'];
      if (recent is List) {
        _recentOutputPaths
            .addAll(recent.map(_storedPath).whereType<String>().take(20));
      }
      _recentOutputDirectory = _storedPath(saved['recentOutputDirectory']);
    }
    notifyListeners();
  }

  String? _storedPath(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 32767 ||
        value.contains('\u0000')) {
      return null;
    }
    if (!File(value).isAbsolute) return null;
    return value;
  }

  void _savePreferences() {
    final store = preferences;
    if (store == null) return;
    unawaited(store.save({
      'outputDirectory': _options.outputDirectory,
      'inputMode': _options.inputMode.name,
      'replayCount': _options.replayCount.name,
      'customReplayCount': _options.customReplayCount,
      'videoMode': _options.videoMode.name,
      'gameDirectory': setupLocations.gameDirectory,
      'replayDirectory': setupLocations.replayDirectory,
      'recentOutputs': List<String>.of(_recentOutputPaths),
      'recentOutputDirectory': _recentOutputDirectory,
    }).catchError((Object _) {
      preferenceNotice =
          'Your choices could not be remembered. You can still record in this session.';
      notifyListeners();
    }));
  }

  Future<void> openObsDownload() async {
    try {
      await outputLauncher.openObsDownload();
    } catch (error) {
      _error = StateError(
          'Could not open your browser. Visit obsproject.com/download to get OBS Studio.');
      notifyListeners();
    }
  }

  Future<void> openOutputFolder() async {
    final path = batchOutputDirectory ??
        _recentOutputDirectory ??
        _options.outputDirectory;
    try {
      if (!await Directory(path).exists()) {
        throw StateError(
            'This folder is no longer available. Choose another output folder.');
      }
      await outputLauncher.openFolder(Directory(path).absolute.path);
    } catch (error) {
      _error = StateError(_friendlyError(error));
      notifyListeners();
    }
  }

  Future<void> openOutput(String path) async {
    try {
      if (!_outputPaths.contains(path) && !_recentOutputPaths.contains(path)) {
        throw StateError('Choose a recording listed by Afterimage.');
      }
      final extension = path.split('.').last.toLowerCase();
      if (!const {
        'mp4',
        'mkv',
        'mov',
        'webm',
        'flv',
        'avi',
        'm4v',
        'ts',
        'mpeg',
        'mpg'
      }.contains(extension)) {
        throw StateError(
            'Open the output folder to inspect this recording format.');
      }
      if (!await File(path).exists()) {
        throw StateError(
            'This recording was moved or deleted. Open the output folder to look for it.');
      }
      await outputLauncher.openVideo(File(path).absolute.path);
    } catch (error) {
      _error = StateError(_friendlyError(error));
      notifyListeners();
    }
  }

  final ReplayBatchEngineFactory engineFactory;
  final OutputDirectoryPicker directoryPicker;
  final OutputDirectoryPreflight outputPreflight;

  RecordingOptions _options;
  SetupReport? _setupReport;
  NativeBackendReadiness? _backendReadiness;
  final Map<InputMode, NativeBackendReadiness> _inputReadiness = {};
  bool _isChecking = false;
  bool _isPickingDirectory = false;
  bool _isBusy = false;
  bool _stopRequested = false;
  ReplayBatchState _state = ReplayBatchState.idle;
  ReplayBatchProgress _progress = const ReplayBatchProgress(
    state: ReplayBatchState.idle,
    totalReplays: 0,
    currentReplay: 0,
    completedReplays: 0,
  );
  final List<ReplayBatchEvent> _events = [];
  final List<String> _outputPaths = [];
  ReplayBatchResult? _result;
  Object? _error;
  RecordingEngine? _activeEngine;
  Future<void>? _readinessFuture;
  int _readinessGeneration = 0;
  bool _disposed = false;

  void _onObsChanged() => notifyListeners();

  @override
  void dispose() {
    obsConnection?.removeListener(_onObsChanged);
    unawaited(requestStop());
    _disposed = true;
    _readinessGeneration++;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  RecordingOptions get options => _options;

  SetupReport? get setupReport => _setupReport;

  NativeBackendReadiness? get backendReadiness => _backendReadiness;

  NativeBackendReadiness? readinessFor(InputMode inputMode) =>
      _inputReadiness[inputMode];

  bool get isChecking => _isChecking || (obsConnection?.isChecking ?? false);

  bool get isPickingDirectory => _isPickingDirectory;

  bool get isBusy => _isBusy;

  bool get isRunning => _activeEngine?.isRunning ?? _isBusy;

  bool get isStopping => _stopRequested;

  ReplayBatchState get state => _state;

  ReplayBatchProgress get progress => _progress;

  List<ReplayBatchEvent> get events => List.unmodifiable(_events);

  List<String> get outputPaths => List.unmodifiable(_outputPaths);

  ReplayBatchResult? get result => _result;

  Object? get error => _error;

  String? get latestMessage {
    for (var index = _events.length - 1; index >= 0; index--) {
      final message = _events[index].message;
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }
    return _progress.detail;
  }

  /// Returns the actionable reasons the Start action is currently blocked.
  List<String> get blockers {
    final reasons = <String>[];
    final report = _setupReport;
    if (report == null) {
      reasons.add('Local checks are still running.');
    } else {
      reasons.addAll(
        report.blockingChecks.map(
          (check) => '${check.title}: ${check.detail}',
        ),
      );
    }

    if (obsConnection != null && obsConnection!.result?.ready != true) {
      reasons.add(obsConnection!.result?.detail ??
          'Connect OBS in Setup before recording.');
    }
    final readiness = readinessFor(_options.inputMode);
    if (readiness == null) {
      reasons.add('Recorder readiness is still being checked.');
    } else if (!readiness.available) {
      reasons.add(readiness.detail);
    }

    if (_options.outputDirectory.trim().isEmpty) {
      reasons.add('Choose an output folder before starting a batch.');
    }
    if (_options.replayCount == ReplayCountOption.all &&
        replayCountFromReport() == null) {
      reasons.add(
        'The replay library count is not available. Refresh setup checks before choosing All.',
      );
    }
    if (_options.replayCount == ReplayCountOption.custom &&
        (_options.customReplayCount < 1 || _options.customReplayCount > 1000)) {
      reasons.add('Choose a replay count from 1 to 1000.');
    }
    return _uniqueNonEmpty(reasons);
  }

  bool get canStart => !_isBusy && blockers.isEmpty;

  bool isInputModeAvailable(InputMode inputMode) {
    final readiness = readinessFor(inputMode);
    return readiness?.available ?? false;
  }

  void setSetupReport(SetupReport? report) {
    _setupReport = report;
    notifyListeners();
  }

  /// Updates options without allowing a running batch to be reconfigured.
  bool updateOptions(RecordingOptions options) {
    if (_isBusy) {
      return false;
    }
    final inputModeChanged = options.inputMode != _options.inputMode;
    _options = options;
    _savePreferences();
    _error = null;
    notifyListeners();
    if (inputModeChanged) {
      unawaited(refreshReadiness());
    }
    return true;
  }

  /// Selects an input mode and refreshes support for both visible choices.
  Future<void> setInputMode(InputMode inputMode) async {
    if (_isBusy) {
      return;
    }
    if (_options.inputMode != inputMode) {
      _options = _options.copyWith(inputMode: inputMode);
      _savePreferences();
      _error = null;
      notifyListeners();
    }
    await refreshReadiness();
  }

  /// Runs backend readiness checks. A second caller shares the current check,
  /// so rapid taps cannot publish stale readiness after a newer selection.
  Future<void> refreshReadiness() {
    final inFlight = _readinessFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final generation = ++_readinessGeneration;
    _isChecking = true;
    _error = null;
    notifyListeners();
    final future = _refreshReadiness(generation);
    _readinessFuture = future;
    return future.whenComplete(() {
      if (identical(_readinessFuture, future)) {
        _readinessFuture = null;
      }
    });
  }

  Future<void> _refreshReadiness(int generation) async {
    NativeBackendReadiness? backendReadiness;
    try {
      backendReadiness = await backend.inspect();
    } catch (error) {
      backendReadiness = NativeBackendReadiness(
        available: false,
        detail: _friendlyError(
          error,
          fallback: 'The native recorder readiness check failed.',
        ),
      );
    }
    if (_isStale(generation)) {
      return;
    }

    final nextInputReadiness = <InputMode, NativeBackendReadiness>{};
    for (final inputMode in InputMode.values) {
      nextInputReadiness[inputMode] = await _readInputReadiness(
        inputMode,
        backendReadiness,
      );
      if (_isStale(generation)) {
        return;
      }
    }

    _backendReadiness = backendReadiness;
    _inputReadiness
      ..clear()
      ..addAll(nextInputReadiness);
    _isChecking = false;
    notifyListeners();
  }

  Future<NativeBackendReadiness> _readInputReadiness(
    InputMode inputMode,
    NativeBackendReadiness base,
  ) async {
    if (backend case final InputModeAwareNativeRecorderBackend aware) {
      try {
        return await aware.inspectForInput(inputMode);
      } catch (error) {
        return NativeBackendReadiness(
          available: false,
          detail: _friendlyInputError(inputMode, error),
        );
      }
    }

    if (!base.available) {
      return base;
    }

    // The older backend contract has no per-input inspection method. Opening
    // and immediately closing an input port is the safest compatibility probe.
    try {
      final input = await backend.openMenuInput(inputMode);
      if (input case final ClosableMenuInputPort closable) {
        await closable.close();
      }
      return base;
    } catch (error) {
      return NativeBackendReadiness(
        available: false,
        detail: _friendlyInputError(inputMode, error),
      );
    }
  }

  /// Opens the native folder picker, while leaving the text field available
  /// for users who prefer to paste a path manually.
  Future<void> browseOutputDirectory() async {
    if (_isBusy || _isPickingDirectory) {
      return;
    }
    _isPickingDirectory = true;
    _error = null;
    final pathBeforePicker = _options.outputDirectory;
    notifyListeners();
    try {
      final directory = await directoryPicker();
      if (directory != null &&
          directory.trim().isNotEmpty &&
          !_isBusy &&
          _options.outputDirectory == pathBeforePicker) {
        _options = _options.copyWith(outputDirectory: directory.trim());
        _savePreferences();
      }
    } catch (error) {
      _error = StateError(
        'Could not open a folder picker. You can paste an output path manually. ${_friendlyError(error)}',
      );
    } finally {
      _isPickingDirectory = false;
      notifyListeners();
    }
  }

  /// Starts one batch. The synchronous guard is set before the first await,
  /// so two rapid Start taps cannot open duplicate monitor or OBS sessions.
  Future<ReplayBatchResult?> startBatch() async {
    if (_isBusy) {
      _error = StateError('A recording batch is already running.');
      notifyListeners();
      return null;
    }
    final currentBlockers = blockers;
    if (currentBlockers.isNotEmpty) {
      _error = StateError(currentBlockers.first);
      notifyListeners();
      return null;
    }

    final replayCount = replayCountFromReport();
    if (replayCount == null || replayCount <= 0) {
      _error = StateError(
        'The selected replay count is not available. Refresh setup checks and try again.',
      );
      notifyListeners();
      return null;
    }

    _isBusy = true;
    _batchDone = Completer<void>();
    _stopRequested = false;
    _state = ReplayBatchState.preparing;
    _progress = ReplayBatchProgress(
      state: ReplayBatchState.preparing,
      totalReplays: replayCount,
      currentReplay: 0,
      completedReplays: 0,
      detail: 'Opening the recorder connections safely.',
    );
    _events.clear();
    _outputPaths.clear();
    batchOutputDirectory = null;
    _result = null;
    _error = null;
    notifyListeners();

    ReplayMonitorPort? monitor;
    MenuInputPort? menuInput;
    ObsRecorderPort? obs;
    var engineStarted = false;
    try {
      _options = _options.copyWith(
        outputDirectory:
            Directory(_options.outputDirectory.trim()).absolute.path,
      );
      _savePreferences();
      final outputReadiness =
          await outputPreflight.check(_options.outputDirectory);
      if (!outputReadiness.ready) {
        throw StateError(outputReadiness.detail);
      }
      _throwIfCancelled();
      final reservation =
          await batchDirectories.reserve(_options.outputDirectory);
      batchOutputDirectory = reservation.path;
      _throwIfCancelled();
      monitor = await backend.openReplayMonitor();
      _throwIfCancelled();
      menuInput = await backend.openMenuInput(_options.inputMode);
      _throwIfCancelled();
      obs = await backend.openObsRecorder();
      _throwIfCancelled();
      final organizer = await backend.openOutputOrganizer();
      _throwIfCancelled();
      final engine = engineFactory(
        monitor: monitor,
        menuInput: menuInput,
        obs: obs,
        organizer: organizer,
        onEvent: _onEngineEvent,
      );
      _activeEngine = engine;
      notifyListeners();
      engineStarted = true;
      final result = await engine.startBatch(
        ReplayBatchRequest(
          replayCount: replayCount,
          options: _options.copyWith(outputDirectory: batchOutputDirectory),
        ),
      );
      _result = result;
      _state = switch (result.outcome) {
        ReplayBatchOutcome.completed => ReplayBatchState.completed,
        ReplayBatchOutcome.failed => ReplayBatchState.failed,
        ReplayBatchOutcome.stopped => ReplayBatchState.stopped,
      };
      if (result.error != null) {
        _error = result.error;
      }
      _collectResultOutputs(result);
      if (_outputPaths.isNotEmpty) {
        _recentOutputPaths
          ..removeWhere(_outputPaths.contains)
          ..insertAll(0, _outputPaths);
        if (_recentOutputPaths.length > 20) {
          _recentOutputPaths.removeRange(20, _recentOutputPaths.length);
        }
        _recentOutputDirectory = batchOutputDirectory;
        _savePreferences();
      }
      return result;
    } on _PreparationCancelled {
      _state = ReplayBatchState.stopped;
      _result = const ReplayBatchResult(
          outcome: ReplayBatchOutcome.stopped, replays: []);
      _progress = ReplayBatchProgress(
          state: ReplayBatchState.stopped,
          totalReplays: replayCount,
          currentReplay: 0,
          completedReplays: 0,
          detail: 'Stopped before recording started.');
      return _result;
    } catch (error) {
      _state = ReplayBatchState.failed;
      _error = error;
      _progress = ReplayBatchProgress(
        state: ReplayBatchState.failed,
        totalReplays: replayCount,
        currentReplay: _progress.currentReplay,
        completedReplays: _progress.completedReplays,
        detail: _friendlyError(
          error,
          fallback: 'The batch could not be started safely.',
        ),
        outputPath: _progress.outputPath,
      );
      return null;
    } finally {
      if (!engineStarted) {
        await _closePort(monitor);
        await _closePort(menuInput);
        await _closePort(obs);
      }
      _activeEngine = null;
      _isBusy = false;
      _stopRequested = false;
      _batchDone?.complete();
      notifyListeners();
    }
  }

  Future<void> requestStop() async {
    final engine = _activeEngine;
    if (!_isBusy) {
      return;
    }
    _stopRequested = true;
    _state = ReplayBatchState.stopped;
    _progress = ReplayBatchProgress(
      state: ReplayBatchState.stoppingRecording,
      totalReplays: _progress.totalReplays,
      currentReplay: _progress.currentReplay,
      completedReplays: _progress.completedReplays,
      detail: 'Stopping safely and preserving the current output.',
      outputPath: _progress.outputPath,
    );
    notifyListeners();
    try {
      await engine?.requestStop();
    } catch (error) {
      _error = StateError(
        'The stop request could not be sent. The recorder will still close its connections. ${_friendlyError(error)}',
      );
      notifyListeners();
    }
  }

  void _throwIfCancelled() {
    if (_stopRequested || _disposed) throw const _PreparationCancelled();
  }

  int? replayCountFromReport() {
    final available = _availableReplayCount();
    switch (_options.replayCount) {
      case ReplayCountOption.one:
        return _boundedReplayCount(1, available);
      case ReplayCountOption.custom:
        return _boundedReplayCount(_options.customReplayCount, available);
      case ReplayCountOption.five:
        return _boundedReplayCount(5, available);
      case ReplayCountOption.ten:
        return _boundedReplayCount(10, available);
      case ReplayCountOption.twenty:
        return _boundedReplayCount(20, available);
      case ReplayCountOption.all:
        return available;
    }
  }

  int? _availableReplayCount() {
    final report = _setupReport;
    final count = report?.replayCount;
    if (count != null) {
      return count;
    }
    final detail = report?.checkFor(SetupCheckId.replayLibrary)?.detail;
    if (detail == null) {
      return null;
    }
    final match = RegExp(r'(\d+)\s+REP###\.sav').firstMatch(detail);
    return int.tryParse(match?.group(1) ?? '');
  }

  int _boundedReplayCount(int requested, int? available) {
    if (available == null || available <= 0) {
      return requested;
    }
    return available < requested ? available : requested;
  }

  void _onEngineEvent(ReplayBatchEvent event) {
    _progress = event.progress;
    _state = event.progress.state;
    if (_events.length >= 200) {
      _events.removeAt(0);
    }
    _events.add(event);
    final output = event.output;
    if (output != null) {
      _addOutputPath(output.path);
    }
    if (event.error != null) {
      _error = event.error;
    }
    notifyListeners();
  }

  void _collectResultOutputs(ReplayBatchResult result) {
    for (final replay in result.replays) {
      final output = replay.output;
      if (output != null) {
        _addOutputPath(output.path);
      } else if (replay.sourceOutput != null) {
        _addOutputPath(replay.sourceOutput!.path);
      }
    }
    if (result.combinedOutput case final output?) {
      _addOutputPath(output.path);
    } else if (result.combinedSourceOutput != null) {
      _addOutputPath(result.combinedSourceOutput!.path);
    }
  }

  void _addOutputPath(String path) {
    if (path.isNotEmpty && !_outputPaths.contains(path)) {
      _outputPaths.add(path);
    }
  }

  Future<void> _closePort(Object? port) async {
    try {
      switch (port) {
        case ReplayMonitorPort value:
          await value.close();
        case ObsRecorderPort value:
          await value.close();
        case ClosableMenuInputPort value:
          await value.close();
      }
    } catch (_) {
      // A failed pre-start cleanup must not hide the original error.
    }
  }

  bool _isStale(int generation) =>
      _disposed || generation != _readinessGeneration;

  String _friendlyInputError(InputMode inputMode, Object error) {
    final inputName = inputMode == InputMode.keyboard
        ? 'keyboard input'
        : 'virtual controller input';
    return 'The backend cannot provide $inputName on this machine. ${_friendlyError(error)}';
  }

  String _friendlyError(
    Object error, {
    String fallback = 'Please refresh setup checks and try again.',
  }) {
    final text = error.toString().trim();
    if (text.isEmpty || text == 'null') {
      return fallback;
    }
    return text;
  }

  List<String> _uniqueNonEmpty(Iterable<String> values) {
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !result.contains(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }
}

RecordingEngine _createReplayBatchEngine({
  required ReplayMonitorPort monitor,
  required MenuInputPort menuInput,
  required ObsRecorderPort obs,
  required OutputOrganizerPort organizer,
  required ReplayBatchEventSink onEvent,
}) {
  return ReplayBatchEngine(
    monitor: monitor,
    menuInput: menuInput,
    obs: obs,
    organizer: organizer,
    onEvent: onEvent,
    summaryWriter: FileSummaryWriter(),
  );
}

/// Keeps the preview honest when the app has not selected a platform adapter.
class UnavailableNativeRecorderBackend implements NativeRecorderBackend {
  const UnavailableNativeRecorderBackend();

  static const _message =
      'The native recorder backend is not connected in this build yet.';

  @override
  Future<NativeBackendReadiness> inspect() async {
    return const NativeBackendReadiness(available: false, detail: _message);
  }

  @override
  Future<ReplayMonitorPort> openReplayMonitor() =>
      Future.error(const RecorderUnavailableException(_message));

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) =>
      Future.error(const RecorderUnavailableException(_message));

  @override
  Future<ObsRecorderPort> openObsRecorder() =>
      Future.error(const RecorderUnavailableException(_message));

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() =>
      Future.error(const RecorderUnavailableException(_message));
}

class _PreparationCancelled implements Exception {
  const _PreparationCancelled();
}
