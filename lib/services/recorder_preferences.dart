import 'dart:convert';
import 'dart:io';

/// The only option and location keys that Afterimage persists. Values are
/// decoded and validated by the caller, so this service never decides whether
/// an enum, count, or path is acceptable.
const Set<String> recorderPreferenceKeys = <String>{
  'gameDirectory',
  'replayDirectory',
  'recentOutputs',
  'recentOutputDirectory',
  'outputDirectory',
  'inputMode',
  'replayCount',
  'customReplayCount',
  'videoMode',
};

/// Storage mechanics for encoded preference values.
///
/// Implementations return null for a missing or unusable document. They must
/// not return connection credentials or other secrets.
abstract interface class RecorderPreferencesStore {
  Future<Map<String, Object?>?> read();

  Future<void> write(Map<String, Object?> values);
}

typedef RecorderPreferencesRead = Future<Map<String, Object?>?> Function();
typedef RecorderPreferencesWrite = Future<void> Function(
  Map<String, Object?> values,
);

/// Persists the encoded option map while keeping writes in order.
///
/// The controller owns encoding and validation of [RecordingOptions]. The
/// service only filters to the supported option and location keys and
/// serializes writes, which prevents a slower earlier write from finishing
/// after a newer selection and restoring stale settings.
class RecorderPreferences {
  RecorderPreferences({
    RecorderPreferencesStore? store,
    RecorderPreferencesRead? read,
    RecorderPreferencesWrite? write,
  })  : assert(
          store == null || (read == null && write == null),
          'Use either store or read/write callbacks.',
        ),
        _read = store?.read ?? read ?? _missingRead,
        _write = store?.write ?? write ?? _missingWrite;

  factory RecorderPreferences.appLocal({String appName = 'afterimage'}) {
    return RecorderPreferences(
      store: FileRecorderPreferencesStore(appName: appName),
    );
  }

  final RecorderPreferencesRead _read;
  final RecorderPreferencesWrite _write;
  Future<void> _saveTail = Future<void>.value();

  /// Loads raw, allowlisted option values. Invalid or missing files return
  /// null so the caller can fall back to its normal defaults.
  Future<Map<String, Object?>?> load() async {
    try {
      try {
        await _saveTail;
      } on Object {
        // A failed pending write must not prevent loading the last readable
        // preferences document.
      }
      final values = await _read();
      return _allowlisted(values);
    } on Object {
      return null;
    }
  }

  /// Queues an allowlisted snapshot for durable storage.
  Future<void> save(Map<String, Object?> values) {
    final snapshot = _allowlisted(values) ?? <String, Object?>{};
    final operation = _runAfterPrevious(_saveTail, () => _write(snapshot));
    _saveTail = operation.catchError((Object _) {});
    return operation;
  }

  /// Waits until all queued saves have completed. A write failure is
  /// rethrown so the caller can report it during an explicit shutdown.
  Future<void> flush() => _saveTail;

  Future<void> _runAfterPrevious(
    Future<void> previous,
    Future<void> Function() operation,
  ) async {
    try {
      await previous;
    } on Object {
      // A failed write must not prevent a later user selection from saving.
    }
    await operation();
  }

  static Map<String, Object?>? _allowlisted(Map<String, Object?>? values) {
    if (values == null) {
      return null;
    }
    return <String, Object?>{
      for (final entry in values.entries)
        if (recorderPreferenceKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  static Future<Map<String, Object?>?> _missingRead() async => null;

  static Future<void> _missingWrite(Map<String, Object?> values) async {
    throw StateError('Recorder preferences have no storage backend.');
  }
}

/// JSON-backed preferences stored below the current user's app-data folder.
///
/// [filePath] is injectable for tests and portable deployments. When omitted,
/// Linux uses XDG_CONFIG_HOME or ~/.config, and Windows uses APPDATA (then
/// LOCALAPPDATA) with an `afterimage/preferences.json` child path.
class FileRecorderPreferencesStore implements RecorderPreferencesStore {
  FileRecorderPreferencesStore({
    String? filePath,
    String appName = 'afterimage',
    Map<String, String>? environment,
    bool? isWindows,
  }) : file = File(
          filePath ??
              recorderPreferencesPath(
                appName: appName,
                environment: environment,
                isWindows: isWindows,
              ),
        );

  final File file;

  @override
  Future<Map<String, Object?>?> read() async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final values = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is String) {
          values[entry.key as String] = entry.value;
        }
      }
      return _allowlistedPreferenceValues(values);
    } on Object {
      // Preferences are convenience state. A corrupt or inaccessible file
      // should leave the recorder usable with defaults.
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    final parent = file.parent;
    await parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    final safeValues = _allowlistedPreferenceValues(values);
    final encoded =
        '${const JsonEncoder.withIndent('  ').convert(safeValues)}\n';
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException {
      // Windows does not replace an existing file with rename. Keep the
      // fallback recoverable if replacement or restoration fails.
      if (!await file.exists()) {
        rethrow;
      }
      final backup = File(
        '${file.path}.bak-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      await file.rename(backup.path);
      try {
        await temporary.rename(file.path);
        try {
          await backup.delete();
        } on FileSystemException {
          // Keep the backup if cleanup is blocked. The new document is valid.
        }
      } on FileSystemException {
        try {
          await backup.rename(file.path);
        } on FileSystemException {
          // The old file remains at the backup path for manual recovery.
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Preserve a failed temporary document for recovery.
        }
      }
    }
  }
}

String recorderPreferencesPath({
  String appName = 'afterimage',
  Map<String, String>? environment,
  bool? isWindows,
}) {
  final env = environment ?? Platform.environment;
  final windows = isWindows ?? Platform.isWindows;
  final base = windows
      ? (env['APPDATA'] ?? env['LOCALAPPDATA'] ?? env['USERPROFILE'])
      : (env['XDG_CONFIG_HOME'] ??
          (env['HOME'] == null
              ? null
              : _join(env['HOME'], '.config', windows: false)));
  if (base == null || base.trim().isEmpty) {
    return _join(
      _join(Directory.current.path, '.$appName', windows: windows),
      'preferences.json',
      windows: windows,
    );
  }
  return _join(
    _join(base, appName, windows: windows),
    'preferences.json',
    windows: windows,
  );
}

Map<String, Object?> _allowlistedPreferenceValues(
  Map<String, Object?> values,
) {
  return <String, Object?>{
    for (final entry in values.entries)
      if (recorderPreferenceKeys.contains(entry.key)) entry.key: entry.value,
  };
}

String _join(String? directory, String name, {bool? windows}) {
  final base = directory ?? '';
  if (base.isEmpty) {
    return name;
  }
  if (base.endsWith('/') || base.endsWith('\\')) {
    return '$base$name';
  }
  final separator = (windows ?? Platform.isWindows) ? '\\' : '/';
  return '$base$separator$name';
}
