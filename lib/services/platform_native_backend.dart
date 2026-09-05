import 'dart:io';

import '../domain/recorder_contracts.dart';
import '../domain/obs_models.dart';
import '../presentation/recorder_controller.dart';
import 'linux_native_backend.dart';
import 'windows_native_backend.dart';

NativeRecorderBackend createPlatformNativeRecorderBackend({
  Future<ObsWebSocketConfig> Function()? obsConfigProvider,
}) {
  if (Platform.isLinux) {
    return LinuxNativeRecorderBackend(obsConfigProvider: obsConfigProvider);
  }
  if (Platform.isWindows) {
    return WindowsNativeRecorderBackend(obsConfigProvider: obsConfigProvider);
  }
  return const UnavailableNativeRecorderBackend();
}
