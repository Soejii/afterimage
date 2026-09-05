enum SetupCheckId {
  supportedPlatform,
  runtime,
  gameInstall,
  gameRunning,
  obsWebSocket,
  replayLibrary,
  keyboardInput,
  controllerInput,
  nativeRecorderBackend,
}

enum SetupCheckStatus {
  ready,
  blocked,
  notice,
}

class SetupCheck {
  const SetupCheck({
    required this.id,
    required this.title,
    required this.detail,
    required this.status,
    required this.required,
    this.value,
  });

  final SetupCheckId id;
  final String title;
  final String detail;
  final SetupCheckStatus status;
  final bool required;
  final String? value;

  bool get isReady => status == SetupCheckStatus.ready;
}

class SetupReport {
  const SetupReport({
    required this.checks,
    required this.checkedAt,
    this.replayCount,
  });

  final List<SetupCheck> checks;
  final DateTime checkedAt;
  final int? replayCount;

  Iterable<SetupCheck> get requiredChecks =>
      checks.where((check) => check.required);

  List<SetupCheck> get blockingChecks =>
      requiredChecks.where((check) => !check.isReady).toList(growable: false);

  bool get canRecord => blockingChecks.isEmpty;

  SetupCheck? checkFor(SetupCheckId id) {
    for (final check in checks) {
      if (check.id == id) {
        return check;
      }
    }
    return null;
  }
}

enum ReplayCountOption {
  one,
  custom,
  five,
  ten,
  twenty,
  all,
}

extension ReplayCountOptionLabel on ReplayCountOption {
  String get label {
    switch (this) {
      case ReplayCountOption.one:
        return '1';
      case ReplayCountOption.custom:
        return 'Custom';
      case ReplayCountOption.five:
        return '5';
      case ReplayCountOption.ten:
        return '10';
      case ReplayCountOption.twenty:
        return '20';
      case ReplayCountOption.all:
        return 'All';
    }
  }

  String get description {
    switch (this) {
      case ReplayCountOption.one:
        return 'Try the highlighted replay first.';
      case ReplayCountOption.custom:
        return 'Choose how many replays to record, moving upward.';
      case ReplayCountOption.five:
        return 'Record five replays, starting at the highlighted replay.';
      case ReplayCountOption.ten:
        return 'Record ten replays, starting at the highlighted replay.';
      case ReplayCountOption.twenty:
        return 'Record twenty replays, starting at the highlighted replay.';
      case ReplayCountOption.all:
        return 'Capture every replay in the library.';
    }
  }
}

enum VideoMode {
  separate,
  combined,
}

extension VideoModeLabel on VideoMode {
  String get label {
    switch (this) {
      case VideoMode.separate:
        return 'Separate videos';
      case VideoMode.combined:
        return 'One combined video';
    }
  }

  String get description {
    switch (this) {
      case VideoMode.separate:
        return 'One output file per replay.';
      case VideoMode.combined:
        return 'Join the batch into one output file.';
    }
  }
}

enum InputMode {
  keyboard,
  virtualController,
}

extension InputModeLabel on InputMode {
  String get label {
    switch (this) {
      case InputMode.keyboard:
        return 'Keyboard input';
      case InputMode.virtualController:
        return 'Virtual controller';
    }
  }

  String get description {
    switch (this) {
      case InputMode.keyboard:
        return 'Use a mapped keyboard layout during playback.';
      case InputMode.virtualController:
        return 'Use a separate virtual gamepad; your physical controller stays connected.';
    }
  }
}

class RecordingOptions {
  const RecordingOptions({
    this.replayCount = ReplayCountOption.one,
    this.customReplayCount = 1,
    this.videoMode = VideoMode.separate,
    this.inputMode = InputMode.keyboard,
    this.outputDirectory = '',
  });

  final ReplayCountOption replayCount;
  final int customReplayCount;
  final VideoMode videoMode;
  final InputMode inputMode;
  final String outputDirectory;

  RecordingOptions copyWith({
    ReplayCountOption? replayCount,
    int? customReplayCount,
    VideoMode? videoMode,
    InputMode? inputMode,
    String? outputDirectory,
  }) {
    return RecordingOptions(
      replayCount: replayCount ?? this.replayCount,
      customReplayCount: customReplayCount ?? this.customReplayCount,
      videoMode: videoMode ?? this.videoMode,
      inputMode: inputMode ?? this.inputMode,
      outputDirectory: outputDirectory ?? this.outputDirectory,
    );
  }
}
