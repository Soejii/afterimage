import 'dart:io';

import '../domain/recorder_contracts.dart';
import '../services/recorder_preferences.dart';
import 'bmp_image.dart';

abstract interface class ObsThumbnailSource {
  Future<RgbImage> captureThumbnail();
}

abstract interface class ScreenReferenceStore {
  Future<List<int>?> readBmp(ScreenCheck check);

  Future<void> writeBmp(ScreenCheck check, List<int> bytes);
}

/// Stores one user-taught OBS image per screen check.
class FileScreenReferenceStore implements ScreenReferenceStore {
  FileScreenReferenceStore({String? directoryPath})
      : directory = Directory(directoryPath ?? _defaultDirectoryPath());

  final Directory directory;

  File fileFor(ScreenCheck check) =>
      File('${directory.path}${Platform.pathSeparator}${check.name}.bmp');

  @override
  Future<List<int>?> readBmp(ScreenCheck check) async {
    final file = fileFor(check);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> writeBmp(ScreenCheck check, List<int> bytes) async {
    decodeBmpImage(bytes);
    await directory.create(recursive: true);
    final file = fileFor(check);
    final nonce = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File('${file.path}.tmp-$nonce');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(file.path);
      } on FileSystemException {
        if (!await file.exists()) {
          rethrow;
        }
        await _replaceWithBackup(file, temporary, nonce);
      }
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Keep an interrupted write available for recovery.
        }
      }
    }
  }

  Future<void> _replaceWithBackup(
    File target,
    File temporary,
    String nonce,
  ) async {
    final backup = File('${target.path}.bak-$nonce');
    await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      try {
        await backup.delete();
      } on FileSystemException {
        // The new reference is valid; a leftover backup is recoverable.
      }
    } on FileSystemException {
      if (!await target.exists()) {
        try {
          await backup.rename(target.path);
        } on FileSystemException {
          // Keep the previous reference at its backup path for manual recovery.
        }
      }
      rethrow;
    }
  }

  static String _defaultDirectoryPath() {
    final preferences = File(recorderPreferencesPath());
    return '${preferences.parent.path}${Platform.pathSeparator}screen-references';
  }
}

class ObsScreenGuard implements ScreenGuardPort {
  const ObsScreenGuard({
    required this.source,
    required this.references,
    this.threshold = 25,
  });

  static const double defaultThreshold = 25;

  final ObsThumbnailSource source;
  final ScreenReferenceStore references;
  final double threshold;

  @override
  Future<ScreenCheckResult> check(ScreenCheck check) async {
    try {
      final referenceBytes = await references.readBmp(check);
      if (referenceBytes == null) {
        return ScreenCheckResult(
          matched: false,
          score: 255,
          error: 'The ${check.name} screen has not been taught.',
        );
      }
      final reference = decodeBmpImage(referenceBytes);
      final live = await source.captureThumbnail();
      final score = screenCheckScore(check, live, reference);
      return ScreenCheckResult(
        matched: score <= threshold,
        score: score,
      );
    } on Object catch (error) {
      return ScreenCheckResult(matched: false, score: 255, error: error);
    }
  }
}

double screenCheckScore(
  ScreenCheck check,
  RgbImage live,
  RgbImage reference,
) {
  if (live.width != reference.width || live.height != reference.height) {
    throw const FormatException(
      'The live screenshot and taught screen reference have different sizes.',
    );
  }
  final region = _screenCheckRegion(check);
  final x0 = (live.width * region.x0).floor();
  final y0 = (live.height * region.y0).floor();
  final x1 = (live.width * region.x1).ceil().clamp(0, live.width);
  final y1 = (live.height * region.y1).ceil().clamp(0, live.height);
  if (x0 >= x1 || y0 >= y1) {
    throw const FormatException('The screen-check region is empty.');
  }

  var difference = 0;
  var channelCount = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      for (var channel = 0; channel < 3; channel++) {
        difference +=
            (live.channelAt(x, y, channel) - reference.channelAt(x, y, channel))
                .abs();
        channelCount++;
      }
    }
  }
  return difference / channelCount;
}

_ScreenCheckRegion _screenCheckRegion(ScreenCheck check) => switch (check) {
      ScreenCheck.replayList => const _ScreenCheckRegion(
          0.047,
          0.185,
          0.953,
          0.269,
        ),
      ScreenCheck.replayMenuViewHighlighted => const _ScreenCheckRegion(
          0.25,
          0.40,
          0.734,
          0.445,
        ),
    };

class _ScreenCheckRegion {
  const _ScreenCheckRegion(this.x0, this.y0, this.x1, this.y1);

  final double x0;
  final double y0;
  final double x1;
  final double y1;
}
