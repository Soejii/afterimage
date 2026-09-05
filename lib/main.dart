import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app/afterimage_app.dart';
import 'presentation/recorder_controller.dart';
import 'services/obs_connection_service.dart';
import 'services/platform_native_backend.dart';
import 'services/recorder_preferences.dart';
import 'services/setup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  final obs = ObsConnectionService();
  final backend =
      createPlatformNativeRecorderBackend(obsConfigProvider: obs.configuration);
  final controller = RecorderController(
    backend: backend,
    obsConnection: obs,
    enforceGuidedChecks: true,
    preferences: RecorderPreferences.appLocal(),
  );
  await controller.initialize();
  final setup = LocalSetupService(
    nativeBackend: backend,
    obsProbe: obs,
    locationProvider: () => controller.setupLocations,
  );
  controller.setupInspector = setup.inspect;
  runApp(AfterimageApp(
    setupService: setup,
    recorderBackend: backend,
    recorderController: controller,
    enableWindowGuard: true,
  ));
}
