import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../domain/recorder_contracts.dart';

/// Linux input event types used by the small virtual gamepad.
abstract final class LinuxUinputEventType {
  static const int syn = 0x00;
  static const int key = 0x01;
}

/// Linux gamepad button codes used by the virtual device.
///
/// The face buttons use the kernel's position-neutral SOUTH/EAST names. On a
/// normal Xbox-style layout these are A and B respectively.
enum LinuxUinputButton {
  south(0x130, 'South / A'),
  east(0x131, 'East / B'),
  north(0x133, 'North / Y'),
  west(0x134, 'West / X'),
  dpadUp(0x220, 'D-pad up'),
  dpadDown(0x221, 'D-pad down'),
  dpadLeft(0x222, 'D-pad left'),
  dpadRight(0x223, 'D-pad right');

  const LinuxUinputButton(this.code, this.label);

  final int code;
  final String label;
}

/// The controller equivalent of the keyboard menu sequences used by GGST.
class LinuxUinputMenuMapping {
  LinuxUinputMenuMapping({
    Map<ReplayMenuAction, Iterable<LinuxUinputButton>>? sequences,
  }) : sequences = _validateSequences(sequences ?? defaultSequences);

  static const Map<ReplayMenuAction, List<LinuxUinputButton>> defaultSequences =
      {
    // Keyboard U,U: confirm the replay-menu entry with A twice.
    ReplayMenuAction.openReplay: <LinuxUinputButton>[
      LinuxUinputButton.south,
      LinuxUinputButton.south,
    ],
    // Keyboard U: use the same confirm button to leave the replay result.
    ReplayMenuAction.exitToReplayList: <LinuxUinputButton>[
      LinuxUinputButton.south,
    ],
    // Keyboard W: move to the next replay with D-pad down.
    ReplayMenuAction.selectNextReplay: <LinuxUinputButton>[
      LinuxUinputButton.dpadDown,
    ],
  };

  final Map<ReplayMenuAction, List<LinuxUinputButton>> sequences;

  List<LinuxUinputButton> sequenceFor(ReplayMenuAction action) {
    final sequence = sequences[action];
    if (sequence == null) {
      throw LinuxUinputException(
        LinuxUinputErrorCode.invalidMapping,
        'No virtual-controller sequence is configured for ${action.name}.',
      );
    }
    return sequence;
  }

  static Map<ReplayMenuAction, List<LinuxUinputButton>> _validateSequences(
    Map<ReplayMenuAction, Iterable<LinuxUinputButton>> supplied,
  ) {
    final validated = <ReplayMenuAction, List<LinuxUinputButton>>{};
    for (final action in ReplayMenuAction.values) {
      final sequence = supplied[action];
      if (sequence == null || sequence.isEmpty) {
        throw LinuxUinputException(
          LinuxUinputErrorCode.invalidMapping,
          'A non-empty virtual-controller sequence is required for ${action.name}.',
        );
      }
      validated[action] = List.unmodifiable(sequence);
    }
    if (supplied.keys.any(
      (action) => !ReplayMenuAction.values.contains(action),
    )) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.invalidMapping,
        'The virtual-controller mapping contains an unknown replay action.',
      );
    }
    return Map.unmodifiable(validated);
  }
}

/// Errors specific to the optional Linux uinput adapter.
enum LinuxUinputErrorCode {
  deviceReady,
  deviceMissing,
  permissionDenied,
  unsupportedIoctl,
  unsupportedPlatform,
  openFailed,
  ioctlFailed,
  writeFailed,
  closeFailed,
  notOpen,
  closed,
  invalidMapping,
  invalidButton,
}

class LinuxUinputException implements Exception {
  const LinuxUinputException(
    this.code,
    this.message, {
    this.errno,
    this.cause,
  });

  final LinuxUinputErrorCode code;
  final String message;
  final int? errno;
  final Object? cause;

  @override
  String toString() => message;
}

/// A readiness result for the optional virtual gamepad.
///
/// [code] intentionally keeps a missing device, an inaccessible device, and
/// an old kernel without the expected ioctl separate. The UI can therefore
/// provide a useful fix instead of telling the user that "the controller
/// failed".
class LinuxUinputReadiness {
  const LinuxUinputReadiness({
    required this.code,
    required this.detail,
    this.devicePath,
  });

  final LinuxUinputErrorCode code;
  final String detail;
  final String? devicePath;

  bool get ready => code == LinuxUinputErrorCode.deviceReady;
}

/// A compact description written with UI_DEV_SETUP.
class LinuxUinputDeviceDescription {
  const LinuxUinputDeviceDescription({
    this.name = 'Afterimage Replay Controller',
    this.busType = 0x06,
    this.vendor = 0x0001,
    this.product = 0x0001,
    this.version = 1,
    this.forceFeedbackEffects = 0,
  });

  final String name;
  final int busType;
  final int vendor;
  final int product;
  final int version;
  final int forceFeedbackEffects;
}

/// The small native seam used by [LinuxUinputMenuInput] and
/// [LinuxUinputReadinessProbe]. Tests provide a fake implementation, so a
/// Linux unit test never opens /dev/uinput.
abstract interface class LinuxUinputDevicePort {
  void setEventBit(int eventType);

  void setKeyBit(int keyCode);

  void setup(LinuxUinputDeviceDescription description);

  void create();

  void press(int buttonCode);

  void release(int buttonCode);

  void destroy();

  void close();
}

abstract interface class LinuxUinputDeviceFactory {
  LinuxUinputDevicePort open(String path);
}

/// The default Linux device paths, in the order used by common udev rules.
const List<String> linuxUinputDevicePaths = <String>[
  '/dev/uinput',
  '/dev/input/uinput',
];

/// Checks uinput availability without creating a virtual controller.
class LinuxUinputReadinessProbe {
  LinuxUinputReadinessProbe({
    LinuxUinputDeviceFactory? factory,
    Iterable<String> devicePaths = linuxUinputDevicePaths,
  })  : factory = factory ?? const LinuxUinputNativeDeviceFactory(),
        devicePaths = List.unmodifiable(devicePaths);

  final LinuxUinputDeviceFactory factory;
  final List<String> devicePaths;

  LinuxUinputReadiness inspect() {
    if (!Platform.isLinux) {
      return const LinuxUinputReadiness(
        code: LinuxUinputErrorCode.unsupportedPlatform,
        detail:
            'The uinput controller is available only in a Linux desktop build.',
      );
    }
    if (devicePaths.isEmpty) {
      return const LinuxUinputReadiness(
        code: LinuxUinputErrorCode.deviceMissing,
        detail: 'No Linux uinput device path was configured.',
      );
    }

    final failures = <LinuxUinputException>[];
    for (final path in devicePaths) {
      LinuxUinputDevicePort? device;
      try {
        device = factory.open(path);
        // UI_SET_EVBIT is a harmless configuration operation before a device
        // is created. It is also the most direct feature check for uinput.
        device.setEventBit(LinuxUinputEventType.key);
        device.close();
        return LinuxUinputReadiness(
          code: LinuxUinputErrorCode.deviceReady,
          detail: 'Linux uinput is available at $path.',
          devicePath: path,
        );
      } catch (error) {
        final typed =
            _asUinputException(error, operation: 'uinput readiness check');
        failures.add(typed);
        try {
          device?.close();
        } on Object {
          // Readiness must preserve the actionable open/ioctl failure.
        }
      }
    }

    final failure = _preferReadinessFailure(failures);
    return LinuxUinputReadiness(
      code: failure.code,
      detail: failure.message,
    );
  }
}

/// Sends the semantic replay-menu actions through a private virtual gamepad.
///
/// The device is created lazily on the first action and is never opened while
/// this library is imported. Every tap releases its button in a finally block;
/// a failed sequence closes the device, which releases any remaining buttons
/// and destroys the uinput device before closing its file descriptor.
/// [registrationDelay] defaults to one second. The Linux kernel uinput guide
/// uses a one-second pause after UI_DEV_CREATE so userspace can discover and
/// initialize the new device before the first event is sent.
class LinuxUinputMenuInput implements MenuInputPort, ClosableMenuInputPort {
  LinuxUinputMenuInput({
    LinuxUinputDeviceFactory? factory,
    Iterable<String> devicePaths = linuxUinputDevicePaths,
    LinuxUinputMenuMapping? mapping,
    this.description = const LinuxUinputDeviceDescription(),
    this.registrationDelay = const Duration(seconds: 1),
    this.buttonHold = const Duration(milliseconds: 80),
    this.buttonDelay = const Duration(milliseconds: 800),
    LinuxUinputDelay? delay,
  })  : factory = factory ?? const LinuxUinputNativeDeviceFactory(),
        devicePaths = List.unmodifiable(devicePaths),
        mapping = mapping ?? LinuxUinputMenuMapping(),
        delay = delay ?? Future<void>.delayed {
    if (registrationDelay < Duration.zero ||
        buttonHold < Duration.zero ||
        buttonDelay < Duration.zero) {
      throw ArgumentError.value(
        registrationDelay < Duration.zero
            ? registrationDelay
            : buttonHold < Duration.zero
                ? buttonHold
                : buttonDelay,
        registrationDelay < Duration.zero
            ? 'registrationDelay'
            : buttonHold < Duration.zero
                ? 'buttonHold'
                : 'buttonDelay',
        'must not be negative',
      );
    }
  }

  final LinuxUinputDeviceFactory factory;
  final List<String> devicePaths;
  final LinuxUinputMenuMapping mapping;
  final LinuxUinputDeviceDescription description;
  final Duration registrationDelay;
  final Duration buttonHold;
  final Duration buttonDelay;
  final LinuxUinputDelay delay;

  LinuxUinputDevicePort? _device;
  bool _closed = false;

  @override
  Future<void> perform(ReplayMenuAction action) async {
    if (_closed) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.closed,
        'The Linux virtual-controller input port is closed.',
      );
    }
    final sequence = mapping.sequenceFor(action);
    try {
      final device = await _ensureDevice();
      for (var index = 0; index < sequence.length; index++) {
        await _tap(device, sequence[index]);
        if (index + 1 < sequence.length) {
          await delay(buttonDelay);
        }
      }
    } catch (error, stackTrace) {
      try {
        await _closeDevice();
      } on Object {
        // Keep the action failure as the useful error. The device close still
        // attempts destruction and descriptor cleanup in its finally block.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _closeDevice();
  }

  Future<LinuxUinputDevicePort> _ensureDevice() async {
    final existing = _device;
    if (existing != null) {
      return existing;
    }
    if (devicePaths.isEmpty) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.deviceMissing,
        'No Linux uinput device path was configured.',
      );
    }

    final failures = <LinuxUinputException>[];
    for (final path in devicePaths) {
      LinuxUinputDevicePort? device;
      try {
        device = factory.open(path);
        device.setEventBit(LinuxUinputEventType.key);
        final buttonCodes = <int>{
          for (final action in ReplayMenuAction.values)
            for (final button in mapping.sequenceFor(action)) button.code,
        };
        for (final code in buttonCodes) {
          device.setKeyBit(code);
        }
        device.setup(description);
        device.create();
        // UI_DEV_CREATE returns before udev and consumers necessarily finish
        // discovering the event device. Keep this delay on first creation
        // only, before the first event, rather than before every action.
        await delay(registrationDelay);
        _device = device;
        return device;
      } catch (error) {
        final typed = _asUinputException(
          error,
          operation: 'virtual controller setup',
        );
        failures.add(typed);
        try {
          device?.close();
        } on Object {
          // Preserve the setup failure as the useful error for the caller.
        }
      }
    }
    throw _preferReadinessFailure(failures);
  }

  Future<void> _tap(
    LinuxUinputDevicePort device,
    LinuxUinputButton button,
  ) async {
    var pressed = false;
    try {
      device.press(button.code);
      pressed = true;
      await delay(buttonHold);
    } finally {
      if (pressed) {
        device.release(button.code);
      }
    }
  }

  Future<void> _closeDevice() async {
    final device = _device;
    _device = null;
    if (device == null) {
      return;
    }

    Object? failure;
    StackTrace? failureStack;
    try {
      // The device port owns the complete cleanup order: release buttons,
      // destroy the virtual device, then close its descriptor.
      device.close();
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    if (failure != null) {
      // Cleanup is best effort when it follows a primary action failure. A
      // direct close still reports a native cleanup error to its caller.
      if (_closed) {
        return;
      }
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }
}

typedef LinuxUinputDelay = Future<void> Function(Duration duration);

/// Direct libc implementation of the uinput device seam.
///
/// It uses the modern UI_DEV_SETUP path and fixed-width byte buffers instead
/// of Dart structs that would silently acquire a different layout on 32-bit
/// Linux. The input_event timestamp fields are sized from the native pointer
/// width, matching Linux's timeval layout on each supported Dart Linux ABI.
class LinuxUinputNativeDeviceFactory implements LinuxUinputDeviceFactory {
  const LinuxUinputNativeDeviceFactory();

  @override
  LinuxUinputDevicePort open(String path) => LinuxUinputNativeDevice.open(path);
}

class LinuxUinputNativeDevice implements LinuxUinputDevicePort {
  LinuxUinputNativeDevice._({
    required _LinuxUinputRuntime runtime,
    required int fileDescriptor,
  })  : _runtime = runtime,
        _fileDescriptor = fileDescriptor;

  factory LinuxUinputNativeDevice.open(String path) {
    if (!Platform.isLinux) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.unsupportedPlatform,
        'Linux uinput cannot be opened on this operating system.',
      );
    }
    final runtime = _LinuxUinputRuntime.load();
    final pathBytes = utf8.encode(path);
    final pathPointer = runtime.malloc(pathBytes.length + 1).cast<Uint8>();
    if (pathPointer.address == 0) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.openFailed,
        'Could not allocate the Linux uinput device path.',
      );
    }
    try {
      final target = pathPointer.asTypedList(pathBytes.length + 1);
      target.setAll(0, pathBytes);
      target[pathBytes.length] = 0;
      final fd = runtime.open(pathPointer.cast<Int8>(), _oWronly | _oNonblock);
      if (fd < 0) {
        throw _nativeFailure(
          runtime,
          LinuxUinputErrorCode.openFailed,
          'Could not open Linux uinput at $path.',
        );
      }
      return LinuxUinputNativeDevice._(
        runtime: runtime,
        fileDescriptor: fd,
      );
    } finally {
      runtime.free(pathPointer.cast<Void>());
    }
  }

  final _LinuxUinputRuntime _runtime;
  final int _fileDescriptor;
  final Set<int> _pressedButtons = <int>{};
  bool _created = false;
  bool _descriptorClosed = false;

  @override
  void setEventBit(int eventType) {
    _ensureOpen();
    _ioctlInt(LinuxUinputIoctl.setEventBit, eventType);
  }

  @override
  void setKeyBit(int keyCode) {
    if (keyCode < 0 || keyCode > 0x7ff) {
      throw LinuxUinputException(
        LinuxUinputErrorCode.invalidButton,
        'Invalid Linux input button code $keyCode.',
      );
    }
    _ensureOpen();
    _ioctlInt(LinuxUinputIoctl.setKeyBit, keyCode);
  }

  @override
  void setup(LinuxUinputDeviceDescription description) {
    _ensureOpen();
    final nameBytes = utf8.encode(description.name);
    if (nameBytes.length > _uinputMaxNameBytes - 1) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.ioctlFailed,
        'The Linux virtual-controller name is longer than 79 UTF-8 bytes.',
      );
    }
    _validateUnsigned(description.busType, 16, 'bus type');
    _validateUnsigned(description.vendor, 16, 'vendor');
    _validateUnsigned(description.product, 16, 'product');
    _validateUnsigned(description.version, 16, 'version');
    _validateUnsigned(
        description.forceFeedbackEffects, 32, 'force-feedback count');

    final buffer = _runtime.malloc(_uinputSetupSize).cast<Uint8>();
    if (buffer.address == 0) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.ioctlFailed,
        'Could not allocate Linux uinput setup data.',
      );
    }
    try {
      final bytes = buffer.asTypedList(_uinputSetupSize);
      bytes.fillRange(0, bytes.length, 0);
      final data = ByteData.sublistView(bytes);
      data.setUint16(0, description.busType, Endian.host);
      data.setUint16(2, description.vendor, Endian.host);
      data.setUint16(4, description.product, Endian.host);
      data.setUint16(6, description.version, Endian.host);
      bytes.setAll(8, nameBytes);
      data.setUint32(88, description.forceFeedbackEffects, Endian.host);
      _ioctlPointer(LinuxUinputIoctl.deviceSetup, buffer.cast<Void>());
    } finally {
      _runtime.free(buffer.cast<Void>());
    }
  }

  @override
  void create() {
    _ensureOpen();
    _ioctlNoArgument(LinuxUinputIoctl.deviceCreate);
    _created = true;
  }

  @override
  void press(int buttonCode) {
    _validateButtonCode(buttonCode);
    _ensureOpen();
    // Track the button before writing. If the kernel accepts the key-down but
    // rejects its SYN_REPORT, close() must still attempt the matching release.
    _pressedButtons.add(buttonCode);
    _emitKey(buttonCode, 1);
  }

  @override
  void release(int buttonCode) {
    _emitKey(buttonCode, 0);
    _pressedButtons.remove(buttonCode);
  }

  @override
  void destroy() {
    if (!_created || _descriptorClosed) {
      return;
    }
    _releasePressedButtons();
    _ioctlNoArgument(LinuxUinputIoctl.deviceDestroy);
    _created = false;
  }

  @override
  void close() {
    if (_descriptorClosed) {
      return;
    }
    Object? failure;
    StackTrace? failureStack;
    try {
      _releasePressedButtons(
        onError: (error, stackTrace) {
          failure ??= error;
          failureStack ??= stackTrace;
        },
      );
    } catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    }
    if (_created) {
      try {
        destroy();
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    try {
      if (_runtime.close(_fileDescriptor) < 0) {
        throw _nativeFailure(
          _runtime,
          LinuxUinputErrorCode.closeFailed,
          'Could not close the Linux uinput file descriptor.',
        );
      }
    } catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    } finally {
      // Closing a uinput descriptor also destroys an unconditionally created
      // device in the kernel, even if UI_DEV_DESTROY was rejected.
      _descriptorClosed = true;
      _created = false;
    }
    final cleanupFailure = failure;
    if (cleanupFailure != null) {
      Error.throwWithStackTrace(
        cleanupFailure,
        failureStack ?? StackTrace.current,
      );
    }
  }

  void _emitKey(int buttonCode, int value) {
    _validateButtonCode(buttonCode);
    _ensureOpen();
    final eventSize = sizeOf<IntPtr>() * 2 + 8;
    final event = Uint8List(eventSize);
    final data = ByteData.sublistView(event);
    final wordSize = sizeOf<IntPtr>();
    data.setUint16(wordSize * 2, LinuxUinputEventType.key, Endian.host);
    data.setUint16(wordSize * 2 + 2, buttonCode, Endian.host);
    data.setInt32(wordSize * 2 + 4, value, Endian.host);
    _writeAll(event);

    final sync = Uint8List(eventSize);
    final syncData = ByteData.sublistView(sync);
    syncData.setUint16(wordSize * 2, LinuxUinputEventType.syn, Endian.host);
    _writeAll(sync);
  }

  void _writeAll(Uint8List bytes) {
    final pointer = _runtime.malloc(bytes.length).cast<Uint8>();
    if (pointer.address == 0) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.writeFailed,
        'Could not allocate a Linux input event.',
      );
    }
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final written = _runtime.write(
          _fileDescriptor,
          (pointer + offset).cast<Void>(),
          bytes.length - offset,
        );
        if (written < 0) {
          throw _nativeFailure(
            _runtime,
            LinuxUinputErrorCode.writeFailed,
            'Linux uinput rejected an input event.',
          );
        }
        if (written == 0) {
          throw const LinuxUinputException(
            LinuxUinputErrorCode.writeFailed,
            'Linux uinput wrote zero bytes for an input event.',
          );
        }
        offset += written;
      }
    } finally {
      _runtime.free(pointer.cast<Void>());
    }
  }

  void _ioctlInt(int request, int argument) {
    final result = _runtime.ioctl(_fileDescriptor, request, argument);
    if (result < 0) {
      throw _nativeFailure(
        _runtime,
        _classifyIoctlErrno(_runtime.errno),
        'Linux uinput rejected ioctl 0x${request.toRadixString(16)}.',
      );
    }
  }

  void _ioctlPointer(int request, Pointer<Void> pointer) {
    final result = _runtime.ioctl(_fileDescriptor, request, pointer.address);
    if (result < 0) {
      throw _nativeFailure(
        _runtime,
        _classifyIoctlErrno(_runtime.errno),
        'Linux uinput rejected ioctl 0x${request.toRadixString(16)}.',
      );
    }
  }

  void _ioctlNoArgument(int request) {
    final result = _runtime.ioctl(_fileDescriptor, request, 0);
    if (result < 0) {
      throw _nativeFailure(
        _runtime,
        _classifyIoctlErrno(_runtime.errno),
        'Linux uinput rejected ioctl 0x${request.toRadixString(16)}.',
      );
    }
  }

  void _ensureOpen() {
    if (_descriptorClosed) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.closed,
        'The Linux uinput device is closed.',
      );
    }
  }

  void _releasePressedButtons({
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    for (final buttonCode in _pressedButtons.toList(growable: false)) {
      try {
        release(buttonCode);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    }
    _pressedButtons.clear();
  }

  void _validateButtonCode(int buttonCode) {
    if (buttonCode < 0 || buttonCode > 0x7ff) {
      throw LinuxUinputException(
        LinuxUinputErrorCode.invalidButton,
        'Invalid Linux input button code $buttonCode.',
      );
    }
  }
}

/// The ioctl numbers are built from Linux's _IOC layout, not copied as
/// architecture-specific magic numbers. The setup/event buffers use fixed
/// width fields and host endianness, matching the native kernel ABI.
abstract final class LinuxUinputIoctl {
  static final int deviceCreate = _ioc(_iocNone, _uinputIoctlBase, 1, 0);
  static final int deviceDestroy = _ioc(_iocNone, _uinputIoctlBase, 2, 0);
  static final int deviceSetup =
      _ioc(_iocWrite, _uinputIoctlBase, 3, _uinputSetupSize);
  static final int setEventBit =
      _ioc(_iocWrite, _uinputIoctlBase, 100, _cIntSize);
  static final int setKeyBit =
      _ioc(_iocWrite, _uinputIoctlBase, 101, _cIntSize);
}

const int _oWronly = 0x0001;
const int _oNonblock = 0x0800;
const int _uinputIoctlBase = 0x55;
const int _uinputMaxNameBytes = 80;
const int _uinputSetupSize = 92;
const int _cIntSize = 4;
const int _iocNone = 0;
const int _iocWrite = 1;
const int _iocNrShift = 0;
const int _iocTypeShift = 8;
const int _iocSizeShift = 16;
const int _iocDirShift = 30;

int _ioc(int direction, int type, int number, int size) =>
    (direction << _iocDirShift) |
    (type << _iocTypeShift) |
    (number << _iocNrShift) |
    (size << _iocSizeShift);

void _validateUnsigned(int value, int bits, String label) {
  final maximum = (1 << bits) - 1;
  if (value < 0 || value > maximum) {
    throw LinuxUinputException(
      LinuxUinputErrorCode.ioctlFailed,
      'The Linux uinput $label must fit in $bits bits.',
    );
  }
}

LinuxUinputErrorCode _classifyIoctlErrno(int errno) {
  return switch (errno) {
    1 || 13 => LinuxUinputErrorCode.permissionDenied,
    22 || 25 || 38 => LinuxUinputErrorCode.unsupportedIoctl,
    _ => LinuxUinputErrorCode.ioctlFailed,
  };
}

LinuxUinputException _nativeFailure(
  _LinuxUinputRuntime runtime,
  LinuxUinputErrorCode fallbackCode,
  String message,
) {
  final errno = runtime.errno;
  final code = switch (fallbackCode) {
    LinuxUinputErrorCode.openFailed => switch (errno) {
        2 || 6 || 19 => LinuxUinputErrorCode.deviceMissing,
        1 || 13 => LinuxUinputErrorCode.permissionDenied,
        _ => fallbackCode,
      },
    LinuxUinputErrorCode.writeFailed ||
    LinuxUinputErrorCode.closeFailed =>
      fallbackCode,
    _ => _classifyIoctlErrno(errno),
  };
  return LinuxUinputException(code, '$message (errno $errno).', errno: errno);
}

LinuxUinputException _asUinputException(
  Object error, {
  required String operation,
}) {
  if (error is LinuxUinputException) {
    return error;
  }
  final osError = switch (error) {
    OSError value => value,
    FileSystemException value => value.osError,
    _ => null,
  };
  if (osError != null) {
    final errno = osError.errorCode;
    final code = switch (errno) {
      2 || 6 || 19 => LinuxUinputErrorCode.deviceMissing,
      1 || 13 => LinuxUinputErrorCode.permissionDenied,
      22 || 25 || 38 => LinuxUinputErrorCode.unsupportedIoctl,
      _ => LinuxUinputErrorCode.openFailed,
    };
    return LinuxUinputException(
      code,
      '$operation failed with errno $errno.',
      errno: errno,
      cause: error,
    );
  }
  return LinuxUinputException(
    LinuxUinputErrorCode.openFailed,
    '$operation failed.',
    cause: error,
  );
}

LinuxUinputException _preferReadinessFailure(
  List<LinuxUinputException> failures,
) {
  for (final code in <LinuxUinputErrorCode>[
    LinuxUinputErrorCode.unsupportedIoctl,
    LinuxUinputErrorCode.permissionDenied,
    LinuxUinputErrorCode.deviceMissing,
  ]) {
    for (final failure in failures) {
      if (failure.code == code) {
        return failure;
      }
    }
  }
  return failures.isEmpty
      ? const LinuxUinputException(
          LinuxUinputErrorCode.deviceMissing,
          'Linux uinput is not available.',
        )
      : failures.first;
}

final class _LinuxUinputRuntime {
  _LinuxUinputRuntime._({required DynamicLibrary library})
      : _malloc = library.lookupFunction<Pointer<Void> Function(UintPtr),
            Pointer<Void> Function(int)>('malloc'),
        _free = library.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('free'),
        _open = library.lookupFunction<Int32 Function(Pointer<Int8>, Int32),
            int Function(Pointer<Int8>, int)>('open'),
        _ioctl = library.lookupFunction<Int32 Function(Int32, UintPtr, IntPtr),
            int Function(int, int, int)>('ioctl'),
        _write = library.lookupFunction<
            IntPtr Function(Int32, Pointer<Void>, UintPtr),
            int Function(int, Pointer<Void>, int)>('write'),
        _close =
            library.lookupFunction<Int32 Function(Int32), int Function(int)>(
          'close',
        ),
        _errnoLocation = library.lookupFunction<Pointer<Int32> Function(),
            Pointer<Int32> Function()>('__errno_location');

  factory _LinuxUinputRuntime.load() {
    DynamicLibrary? library;
    Object? failure;
    for (final name in <String>['libc.so.6', 'libc.so']) {
      try {
        library = DynamicLibrary.open(name);
        break;
      } on Object catch (error) {
        failure = error;
      }
    }
    if (library == null) {
      throw LinuxUinputException(
        LinuxUinputErrorCode.openFailed,
        'The Linux C runtime needed for uinput is unavailable.',
        cause: failure,
      );
    }
    try {
      return _LinuxUinputRuntime._(library: library);
    } on Object catch (error) {
      throw LinuxUinputException(
        LinuxUinputErrorCode.openFailed,
        'The Linux C runtime does not expose the uinput system calls.',
        cause: error,
      );
    }
  }

  final Pointer<Void> Function(int) _malloc;
  final void Function(Pointer<Void>) _free;
  final int Function(Pointer<Int8>, int) _open;
  final int Function(int, int, int) _ioctl;
  final int Function(int, Pointer<Void>, int) _write;
  final int Function(int) _close;
  final Pointer<Int32> Function() _errnoLocation;

  Pointer<Void> malloc(int size) => _malloc(size);

  void free(Pointer<Void> pointer) => _free(pointer);

  int open(Pointer<Int8> path, int flags) => _open(path, flags);

  int ioctl(int fileDescriptor, int request, int argument) =>
      _ioctl(fileDescriptor, request, argument);

  int write(int fileDescriptor, Pointer<Void> buffer, int length) =>
      _write(fileDescriptor, buffer, length);

  int close(int fileDescriptor) => _close(fileDescriptor);

  int get errno => _errnoLocation().value;
}
