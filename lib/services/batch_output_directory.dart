import 'dart:io';

/// Creates an isolated directory for each recording batch.
///
/// A batch directory prevents the fixed replay names used by the organizer
/// from colliding with an earlier batch. The directory is created with the
/// operating system's temporary-directory primitive, which claims a fresh
/// child atomically and leaves no marker file in the user's output.
/// Returns the newly created directory path, or null when the candidate could
/// not be reserved. The callback owns creation and must never replace an
/// existing path. It is primarily a seam for controller tests.
typedef BatchDirectoryReserveAttempt = Future<String?> Function(
  String parent,
  String prefix,
);

class BatchOutputReservation {
  const BatchOutputReservation({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;

  Directory get directory => Directory(path);
}

class BatchOutputDirectoryException implements Exception {
  const BatchOutputDirectoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reserves a fresh child directory below the user's selected output folder.
///
/// [reserveAttempt] is an injectable seam for controller tests. It must return
/// the path of a directory it has exclusively created, or null when the
/// candidate was unavailable. The default implementation delegates to
/// [Directory.createTemp], so it never overwrites an existing output
/// directory.
class BatchOutputDirectory {
  BatchOutputDirectory({
    DateTime Function()? now,
    BatchDirectoryReserveAttempt? reserveAttempt,
    this.maxAttempts = 32,
  })  : _now = now ?? DateTime.now,
        _reserveAttempt = reserveAttempt ?? _reserveWithIo {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'must be greater than zero',
      );
    }
  }

  final DateTime Function() _now;
  final BatchDirectoryReserveAttempt _reserveAttempt;
  final int maxAttempts;

  /// Returns a unique child directory below [outputParent].
  Future<BatchOutputReservation> reserve(
    String outputParent,
  ) async {
    final parent = outputParent.trim();
    if (parent.isEmpty) {
      throw ArgumentError.value(
        outputParent,
        'outputParent',
        'must not be empty',
      );
    }

    try {
      await Directory(parent).create(recursive: true);
    } on FileSystemException catch (error) {
      throw BatchOutputDirectoryException(
        'The output folder could not be prepared: ${error.message}',
      );
    }

    final now = _now();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final prefix = _defaultPrefix(now, attempt);
      String? path;
      try {
        path = await _reserveAttempt(parent, prefix);
      } on FileSystemException catch (error) {
        throw BatchOutputDirectoryException(
          'The batch output folder could not be created: ${error.message}',
        );
      }
      if (path != null && path.trim().isNotEmpty) {
        return BatchOutputReservation(path: path, name: _basename(path));
      }
    }

    throw const BatchOutputDirectoryException(
      'Afterimage could not find a free batch output folder. Choose another output folder and try again.',
    );
  }

  static String _defaultPrefix(DateTime now, int attempt) {
    final local = now.toLocal();
    final stamp = '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}_'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}'
        '${local.second.toString().padLeft(2, '0')}_'
        '${local.microsecond.toString().padLeft(6, '0')}';
    return 'batch_$stamp${attempt == 0 ? '' : '_$attempt'}';
  }

  static Future<String?> _reserveWithIo(String parent, String prefix) async {
    final directory = await Directory(parent).createTemp(prefix);
    return directory.path;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
