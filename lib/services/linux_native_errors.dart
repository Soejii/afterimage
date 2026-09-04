import 'dart:io';

/// Stable error categories used by the Linux native integration.
///
/// The UI can use these values to give a useful recovery instruction without
/// parsing an exception's human-readable message.
enum LinuxNativeErrorCode {
  gameAbsent,
  gameModuleMissing,
  processMemoryDenied,
  signatureMismatch,
  memoryReadFailed,
  missingX11,
  missingXTest,
  gamescopeDisplayMissing,
  invalidDisplay,
  displayUnavailable,
  invalidKey,
  unsupportedController,
  obsUnavailable,
  closed,
  notAttached,
}

/// A typed failure from the Linux-only native adapter.
class LinuxNativeException implements Exception {
  const LinuxNativeException(
    this.code,
    this.message, {
    this.cause,
  });

  final LinuxNativeErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// A single preflight result. It is intentionally separate from
/// [NativeBackendReadiness] so the Linux adapter can expose all actionable
/// failures while the existing domain contract remains platform-neutral.
class LinuxReadinessCheck {
  const LinuxReadinessCheck({
    required this.code,
    required this.title,
    required this.detail,
    required this.ready,
  });

  final LinuxNativeErrorCode? code;
  final String title;
  final String detail;
  final bool ready;
}

class LinuxReadinessReport {
  const LinuxReadinessReport({
    required this.checks,
  });

  final List<LinuxReadinessCheck> checks;

  bool get ready => checks.every((check) => check.ready);

  List<LinuxReadinessCheck> get blockingChecks =>
      checks.where((check) => !check.ready).toList(growable: false);

  String get detail {
    if (ready) {
      return 'Linux native replay monitor and selected input are ready.';
    }
    return blockingChecks.map((check) => check.detail).join(' ');
  }
}

LinuxNativeException linuxMemoryException(
  Object error, {
  String operation = 'The Linux process-memory operation failed.',
}) {
  if (error is LinuxNativeException) {
    return error;
  }
  final osError = switch (error) {
    OSError value => value,
    FileSystemException value => value.osError,
    _ => null,
  };
  if (osError != null && (osError.errorCode == 1 || osError.errorCode == 13)) {
    return LinuxNativeException(
      LinuxNativeErrorCode.processMemoryDenied,
      'GGST memory access was denied. Check the safe per-user ptrace policy described in the Linux runtime guide.',
      cause: osError,
    );
  }
  return LinuxNativeException(
    LinuxNativeErrorCode.memoryReadFailed,
    operation,
    cause: error,
  );
}
