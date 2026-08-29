import 'package:flutter/widgets.dart';

import 'app/afterimage_app.dart';
import 'services/platform_native_backend.dart';
import 'services/setup_service.dart';

void main() {
  final backend = createPlatformNativeRecorderBackend();
  runApp(
    AfterimageApp(
      setupService: LocalSetupService(nativeBackend: backend),
      recorderBackend: backend,
    ),
  );
}
