import 'package:file_selector/file_selector.dart';

/// Opens the native directory picker on supported desktop targets.
///
/// Keeping this small seam separate lets the recorder controller and widget
/// tests provide a deterministic picker without importing platform code.
Future<String?> pickOutputDirectory() {
  return getDirectoryPath(confirmButtonText: 'Use this folder');
}
