import 'dart:io';

/// Stable error categories used by the Windows native integration.
///
/// The UI can use these values to provide a recovery instruction without
/// parsing a human-readable exception message.
enum WindowsNativeErrorCode {
  gameAbsent,
  gameModuleMissing,
  processMemoryDenied,
  architectureMismatch,
  signatureMismatch,
  memoryReadFailed,
  nativeApiUnavailable,
  inputUnavailable,
  invalidKey,
  unsupportedController,
  closed,
  notAttached,
}

/// A typed failure from the Windows-only native adapter.
class WindowsNativeException implements Exception {
  const WindowsNativeException(
    this.code,
    this.message, {
    this.cause,
    this.systemError,
  });

  final WindowsNativeErrorCode code;
  final String message;
  final Object? cause;
  final int? systemError;

  @override
  String toString() => message;
}

/// Converts a Win32 last-error value to a user-actionable native exception.
///
/// The operation is included in the message because the same error code can
/// mean different things while discovering a process and while reading it.
WindowsNativeException windowsSystemException(
  int errorCode, {
  required String operation,
  Object? cause,
}) {
  final code = switch (errorCode) {
    5 => WindowsNativeErrorCode.processMemoryDenied, // ERROR_ACCESS_DENIED
    299 => WindowsNativeErrorCode.architectureMismatch, // ERROR_PARTIAL_COPY
    6 => WindowsNativeErrorCode.memoryReadFailed, // ERROR_INVALID_HANDLE
    87 => WindowsNativeErrorCode.memoryReadFailed, // ERROR_INVALID_PARAMETER
    998 => WindowsNativeErrorCode.memoryReadFailed, // ERROR_NOACCESS
    _ => WindowsNativeErrorCode.memoryReadFailed,
  };

  final detail = switch (code) {
    WindowsNativeErrorCode.processMemoryDenied =>
      'Windows denied read access to the GGST process. Run Afterimage and GGST as the same user and close tools that hold the process open.',
    WindowsNativeErrorCode.architectureMismatch =>
      'Windows could not copy GGST memory. Use the Afterimage build that matches GGST (the supported target is 64-bit Windows).',
    _ =>
      'The Windows native recorder could not $operation (Win32 error $errorCode).',
  };
  return WindowsNativeException(
    code,
    detail,
    cause: cause,
    systemError: errorCode,
  );
}

WindowsNativeException windowsMemoryException(
  Object error, {
  String operation = 'read GGST process memory',
}) {
  if (error is WindowsNativeException) {
    return error;
  }
  final errorCode = switch (error) {
    OSError value => value.errorCode,
    _ => null,
  };
  if (errorCode != null) {
    return windowsSystemException(
      errorCode,
      operation: operation,
      cause: error,
    );
  }
  return WindowsNativeException(
    WindowsNativeErrorCode.memoryReadFailed,
    'The Windows native recorder could not $operation.',
    cause: error,
  );
}
