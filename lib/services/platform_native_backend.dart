import 'dart:io';

import '../domain/recorder_contracts.dart';
import '../presentation/recorder_controller.dart';
import 'linux_native_backend.dart';
import 'windows_native_backend.dart';

NativeRecorderBackend createPlatformNativeRecorderBackend() {
  if (Platform.isLinux) {
    return LinuxNativeRecorderBackend();
  }
  if (Platform.isWindows) {
    return WindowsNativeRecorderBackend();
  }
  return const UnavailableNativeRecorderBackend();
}
