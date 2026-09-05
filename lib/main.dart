import 'package:flutter/widgets.dart';

import 'app/afterimage_app.dart';
import 'presentation/recorder_controller.dart';
import 'services/obs_connection_service.dart';
import 'services/platform_native_backend.dart';
import 'services/setup_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final obs = ObsConnectionService();
  final backend =
      createPlatformNativeRecorderBackend(obsConfigProvider: obs.configuration);
  final controller = RecorderController(
    backend: backend,
    obsConnection: obs,
  );
  final setup = LocalSetupService(
    nativeBackend: backend,
    obsProbe: obs,
  );
  runApp(AfterimageApp(
    setupService: setup,
    recorderBackend: backend,
    recorderController: controller,
  ));
}
