import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../domain/recorder_contracts.dart';
import 'linux_process_memory.dart';

/// Linux input event types used by an already-existing controller device.
abstract final class LinuxEvdevEventType {
  static const int syn = 0x00;
  static const int key = 0x01;
  static const int abs = 0x03;
}

/// Linux input codes used by the GGST controller menu mapping.
abstract final class LinuxEvdevEventCode {
  static const int btnSouth = 0x130;
  static const int absHat0Y = 0x11;
  static const int syn = 0x00;
  static const int synReport = 0x00;
}

/// The Linux `input_event` size, including its native-width timeval fields.
int get linuxInputEventSize => sizeOf<IntPtr>() * 2 + 8;

/// Encodes one Linux `input_event` using host byte order.
Uint8List encodeLinuxInputEvent({
  required int type,
  required int code,
  required int value,
}) {
  final event = Uint8List(linuxInputEventSize);
  final data = ByteData.sublistView(event);
  final eventOffset = sizeOf<IntPtr>() * 2;
  data.setUint16(eventOffset, type, Endian.host);
  data.setUint16(eventOffset + 2, code, Endian.host);
  data.setInt32(eventOffset + 4, value, Endian.host);
  return event;
}

/// Checks a bit in a `/proc/bus/input/devices` bitmap.
///
/// Procfs prints 64-bit words most-significant first. The index therefore has
/// to be calculated from the right edge of the words that were printed. A
/// device can omit trailing zero words, so an out-of-range bit is simply not
/// present.
bool linuxProcBitmapHasBit(String bitmap, int bit) {
  if (bit < 0) {
    return false;
  }
  final words = bitmap
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return false;
  }
  final wordIndex = words.length - 1 - (bit ~/ 64);
  if (wordIndex < 0 || wordIndex >= words.length) {
    return false;
  }
  final wordText = words[wordIndex];
  final lowStart = wordText.length > 8 ? wordText.length - 8 : 0;
  final high = lowStart == 0
      ? 0
      : int.tryParse(wordText.substring(0, lowStart), radix: 16);
  final low = int.tryParse(wordText.substring(lowStart), radix: 16);
  if (high == null || low == null) {
    return false;
  }
  final bitInWord = bit % 64;
  final half = bitInWord < 32 ? low : high;
  final halfBit = bitInWord < 32 ? bitInWord : bitInWord - 32;
  return (half & (1 << halfBit)) != 0;
}

/// One input device record from `/proc/bus/input/devices`.
class LinuxEvdevInputDevice {
  const LinuxEvdevInputDevice({
    required this.eventNumbers,
    required this.vendor,
    required this.product,
    required this.keyBitmap,
    required this.absBitmap,
    this.name = '',
  });

  final List<int> eventNumbers;
  final int vendor;
  final int product;
  final String keyBitmap;
  final String absBitmap;
  final String name;

  bool get isGamepad =>
      linuxProcBitmapHasBit(keyBitmap, LinuxEvdevEventCode.btnSouth) &&
      linuxProcBitmapHasBit(absBitmap, LinuxEvdevEventCode.absHat0Y);

  String get vendorProduct =>
      '0x${vendor.toRadixString(16).padLeft(4, '0')}/0x${product.toRadixString(16).padLeft(4, '0')}';
}

/// Parses the input-device records exported by the Linux kernel.
List<LinuxEvdevInputDevice> parseLinuxInputDevices(String text) {
  final devices = <LinuxEvdevInputDevice>[];
  _LinuxEvdevInputDeviceBuilder? current;

  void finish() {
    final builder = current;
    if (builder == null) {
      return;
    }
    devices.add(builder.build());
    current = null;
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      finish();
      continue;
    }
    if (line.startsWith('I:')) {
      finish();
      current = _LinuxEvdevInputDeviceBuilder();
      final vendor = RegExp(r'\bVendor=([0-9a-fA-F]+)').firstMatch(line);
      final product = RegExp(r'\bProduct=([0-9a-fA-F]+)').firstMatch(line);
      current!
        ..vendor = int.tryParse(vendor?.group(1) ?? '', radix: 16) ?? 0
        ..product = int.tryParse(product?.group(1) ?? '', radix: 16) ?? 0;
      continue;
    }
    final builder = current;
    if (builder == null) {
      continue;
    }
    if (line.startsWith('N:')) {
      final match = RegExp(r'^N:\s+Name="(.*)"$').firstMatch(line);
      if (match != null) {
        builder.name = match.group(1)!;
      }
    } else if (line.startsWith('H:')) {
      final handlers = RegExp(r'^H:\s+Handlers=(.*)$').firstMatch(line);
      if (handlers != null) {
        for (final match
            in RegExp(r'\bevent(\d+)\b').allMatches(handlers.group(1)!)) {
          final eventNumber = int.tryParse(match.group(1)!);
          if (eventNumber != null) {
            builder.eventNumbers.add(eventNumber);
          }
        }
      }
    } else if (line.startsWith('B: KEY=')) {
      builder.keyBitmap = line.substring('B: KEY='.length).trim();
    } else if (line.startsWith('B: ABS=')) {
      builder.absBitmap = line.substring('B: ABS='.length).trim();
    }
  }
  finish();
  return List.unmodifiable(devices);
}

final class _LinuxEvdevInputDeviceBuilder {
  final List<int> eventNumbers = <int>[];
  int vendor = 0;
  int product = 0;
  String keyBitmap = '';
  String absBitmap = '';
  String name = '';

  LinuxEvdevInputDevice build() => LinuxEvdevInputDevice(
        eventNumbers: List.unmodifiable(eventNumbers),
        vendor: vendor,
        product: product,
        keyBitmap: keyBitmap,
        absBitmap: absBitmap,
        name: name,
      );
}

/// A controller node that is already held by a process in GGST's Wine prefix.
class LinuxEvdevControllerNode {
  const LinuxEvdevControllerNode({
    required this.eventNumber,
    required this.vendor,
    required this.product,
    this.name = '',
  });

  final int eventNumber;
  final int vendor;
  final int product;
  final String name;

  String get path => '/dev/input/event$eventNumber';

  String get vendorProduct =>
      '0x${vendor.toRadixString(16).padLeft(4, '0')}/0x${product.toRadixString(16).padLeft(4, '0')}';

  String get detail {
    final nameDetail = name.isEmpty ? '' : ' "$name"';
    return 'Using controller node $path$nameDetail ($vendorProduct).';
  }
}

/// Finds the controller device that GGST's Wine processes are reading.
class LinuxEvdevControllerDiscovery {
  const LinuxEvdevControllerDiscovery({
    this.processName = ggstLinuxExecutable,
    LinuxProcFileSystem? procFileSystem,
  }) : procFileSystem = procFileSystem ?? const SystemLinuxProcFileSystem();

  final String processName;
  final LinuxProcFileSystem procFileSystem;

  LinuxEvdevControllerNode discover() {
    final game = _findGameProcess();
    final heldEvents = <int>{};
    try {
      for (final processId in procFileSystem.processIds()) {
        try {
          final environment = _parseEnvironment(
            procFileSystem.readFile(processId, 'environ'),
          );
          if (_normaliseWinePrefix(environment['WINEPREFIX']) != game.prefix) {
            continue;
          }
          for (final target in procFileSystem.fdTargets(processId)) {
            final match = RegExp(r'^/dev/input/event(\d+)$').firstMatch(target);
            final eventNumber = int.tryParse(match?.group(1) ?? '');
            if (eventNumber != null) {
              heldEvents.add(eventNumber);
            }
          }
        } on FileSystemException {
          // A Wine helper can exit while its proc entry is being inspected.
        } on OSError {
          // Restricted or disappearing proc entries do not stop the scan.
        }
      }
    } on FileSystemException {
      // Treat an unreadable process list like an unavailable controller.
    } on OSError {
      // Treat an unreadable process list like an unavailable controller.
    }

    late final List<LinuxEvdevInputDevice> inputDevices;
    try {
      inputDevices = parseLinuxInputDevices(procFileSystem.readInputDevices());
    } on Object catch (error) {
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.controllerNotReading,
        'GGST is not reading a controller because Linux input-device information could not be read.',
        cause: error,
      );
    }

    final candidates = <LinuxEvdevControllerNode>[];
    final seenEvents = <int>{};
    for (final device in inputDevices) {
      if (!device.isGamepad) {
        continue;
      }
      for (final eventNumber in device.eventNumbers) {
        if (heldEvents.contains(eventNumber) && seenEvents.add(eventNumber)) {
          candidates.add(
            LinuxEvdevControllerNode(
              eventNumber: eventNumber,
              vendor: device.vendor,
              product: device.product,
              name: device.name,
            ),
          );
        }
      }
    }

    if (candidates.isEmpty) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.controllerNotReading,
        'GGST is not reading a controller. Connect a controller through Steam Input, then refresh setup checks.',
      );
    }

    var surviving = candidates;
    final ignored = _parseIgnoredDevices(game.ignoredDevices);
    surviving = surviving
        .where((node) => !ignored.contains(node.vendorProduct))
        .toList(growable: false);
    if (surviving.isEmpty) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.controllerNotReading,
        'GGST is not reading a controller. Every controller node held by its Wine prefix is in GGST\'s SDL ignore list.',
      );
    }

    if (surviving.length > 1) {
      final details = surviving
          .map((node) => '${node.path} (${node.vendorProduct})')
          .join(', ');
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.ambiguousController,
        'Multiple controller nodes are held by GGST: $details. Disconnect the other controller and refresh setup checks.',
      );
    }
    return surviving.single;
  }

  _LinuxGameProcess _findGameProcess() {
    final expected = _linuxProcessBasename(processName);
    final truncatedComm = expected.substring(
      0,
      expected.length > 15 ? 15 : expected.length,
    );
    var foundGame = false;
    _LinuxGameProcess? selected;

    try {
      for (final processId in procFileSystem.processIds()) {
        try {
          var commandLine = '';
          try {
            commandLine = _decodeProc(
              procFileSystem.readFile(processId, 'cmdline'),
            );
          } on FileSystemException {
            // The comm name can still identify the process.
          } on OSError {
            // The comm name can still identify the process.
          }
          var comm = '';
          try {
            comm = _decodeProc(procFileSystem.readFile(processId, 'comm'))
                .replaceAll('\u0000', '')
                .trim();
          } on FileSystemException {
            // cmdline is sufficient when comm is unavailable.
          } on OSError {
            // cmdline is sufficient when comm is unavailable.
          }
          if (!_containsExecutable(commandLine, expected) &&
              comm != expected &&
              comm != truncatedComm &&
              !(comm.isNotEmpty &&
                  comm.length <= 15 &&
                  expected.startsWith(comm))) {
            continue;
          }
          foundGame = true;
          final environment = _parseEnvironment(
            procFileSystem.readFile(processId, 'environ'),
          );
          final prefix = _normaliseWinePrefix(environment['WINEPREFIX']);
          if (prefix != null && selected == null) {
            selected = _LinuxGameProcess(
              processId: processId,
              prefix: prefix,
              ignoredDevices: environment['SDL_GAMECONTROLLER_IGNORE_DEVICES'],
            );
          }
        } on FileSystemException {
          // Processes can disappear while procfs is enumerated.
        } on OSError {
          // A restricted or disappearing proc entry should not abort discovery.
        }
      }
    } on FileSystemException catch (error) {
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.gameAbsent,
        'GGST could not be inspected through Linux procfs.',
        cause: error,
      );
    } on OSError catch (error) {
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.gameAbsent,
        'GGST could not be inspected through Linux procfs.',
        cause: error,
      );
    }

    if (!foundGame) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.gameAbsent,
        'GGST is not running, so its controller cannot be discovered.',
      );
    }
    if (selected == null) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.winePrefixUnknown,
        'GGST is running, but its WINEPREFIX could not be read. Launch GGST through Proton and refresh setup checks.',
      );
    }
    return selected;
  }

  static Set<String> parseIgnoredDevices(String? value) =>
      _parseIgnoredDevices(value);

  static String? normaliseWinePrefix(String? value) =>
      _normaliseWinePrefix(value);

  static bool _containsExecutable(String commandLine, String expected) {
    return commandLine.split('\u0000').any(
          (argument) =>
              _linuxProcessBasename(argument) == expected ||
              argument.contains(expected),
        );
  }
}

final class _LinuxGameProcess {
  const _LinuxGameProcess({
    required this.processId,
    required this.prefix,
    required this.ignoredDevices,
  });

  final int processId;
  final String prefix;
  final String? ignoredDevices;
}

String _decodeProc(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

Map<String, String> _parseEnvironment(List<int> bytes) {
  final values = <String, String>{};
  for (final item in _decodeProc(bytes).split('\u0000')) {
    final equals = item.indexOf('=');
    if (equals <= 0) {
      continue;
    }
    values[item.substring(0, equals)] = item.substring(equals + 1);
  }
  return values;
}

String? _normaliseWinePrefix(String? value) {
  if (value == null) {
    return null;
  }
  var normalised = value.trim();
  if (normalised.isEmpty) {
    return null;
  }
  while (normalised.length > 1 && normalised.endsWith('/')) {
    normalised = normalised.substring(0, normalised.length - 1);
  }
  return normalised;
}

Set<String> _parseIgnoredDevices(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const <String>{};
  }
  final ignored = <String>{};
  final pattern = RegExp(
    r'^0x([0-9a-f]{1,4})/0x([0-9a-f]{1,4})$',
    caseSensitive: false,
  );
  for (final raw in value.split(',')) {
    final match = pattern.firstMatch(raw.trim());
    if (match == null) {
      continue;
    }
    final vendor = match.group(1)!.toLowerCase().padLeft(4, '0');
    final product = match.group(2)!.toLowerCase().padLeft(4, '0');
    ignored.add('0x$vendor/0x$product');
  }
  return ignored;
}

String _linuxProcessBasename(String value) {
  final normalized = value.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

enum LinuxEvdevErrorCode {
  gameAbsent,
  winePrefixUnknown,
  controllerNotReading,
  ambiguousController,
  nodeNotWritable,
  writeFailed,
  closeFailed,
  closed,
  unsupportedPlatform,
  invalidEvent,
}

class LinuxEvdevException implements Exception {
  const LinuxEvdevException(
    this.code,
    this.message, {
    this.errno,
    this.cause,
  });

  final LinuxEvdevErrorCode code;
  final String message;
  final int? errno;
  final Object? cause;

  @override
  String toString() => message;
}

class LinuxEvdevReadiness {
  const LinuxEvdevReadiness({
    required this.code,
    required this.detail,
    this.node,
  });

  final LinuxEvdevErrorCode? code;
  final String detail;
  final LinuxEvdevControllerNode? node;

  bool get ready => code == null;
}

/// Checks discovery and write permission without injecting an input event.
class LinuxEvdevReadinessProbe {
  LinuxEvdevReadinessProbe({
    LinuxEvdevControllerDiscovery? discovery,
    LinuxEvdevDeviceFactory? factory,
  })  : discovery = discovery ?? const LinuxEvdevControllerDiscovery(),
        factory = factory ?? const LinuxEvdevNativeDeviceFactory();

  final LinuxEvdevControllerDiscovery discovery;
  final LinuxEvdevDeviceFactory factory;

  LinuxEvdevReadiness inspect() {
    if (!Platform.isLinux) {
      return const LinuxEvdevReadiness(
        code: LinuxEvdevErrorCode.unsupportedPlatform,
        detail:
            'The existing-controller input mode is available only on Linux.',
      );
    }

    late final LinuxEvdevControllerNode node;
    try {
      node = discovery.discover();
    } on LinuxEvdevException catch (error) {
      return LinuxEvdevReadiness(code: error.code, detail: error.message);
    }

    LinuxEvdevDevicePort? device;
    try {
      device = factory.open(node.path);
      device.close();
      return LinuxEvdevReadiness(
        code: null,
        detail: '${node.detail} The node is writable by Afterimage.',
        node: node,
      );
    } catch (error) {
      try {
        device?.close();
      } on Object {
        // Preserve the actionable open failure.
      }
      final typed = _asEvdevException(
        error,
        operation: 'The controller node ${node.path} could not be opened',
      );
      return LinuxEvdevReadiness(
        code: typed.code,
        detail: '${typed.message} ${node.detail}',
        node: node,
      );
    }
  }
}

abstract interface class LinuxEvdevDevicePort {
  void write(List<int> bytes);

  void close();
}

abstract interface class LinuxEvdevDeviceFactory {
  LinuxEvdevDevicePort open(String path);
}

typedef LinuxEvdevDelay = Future<void> Function(Duration duration);

/// Sends menu events into the existing evdev node read by GGST's Wine device.
class LinuxEvdevMenuInput implements MenuInputPort, ClosableMenuInputPort {
  LinuxEvdevMenuInput({
    LinuxEvdevControllerDiscovery? discovery,
    LinuxEvdevDeviceFactory? factory,
    this.buttonHold = const Duration(milliseconds: 80),
    this.buttonDelay = const Duration(milliseconds: 800),
    LinuxEvdevDelay? delay,
  })  : discovery = discovery ?? const LinuxEvdevControllerDiscovery(),
        factory = factory ?? const LinuxEvdevNativeDeviceFactory(),
        delay = delay ?? Future<void>.delayed {
    if (buttonHold < Duration.zero || buttonDelay < Duration.zero) {
      throw ArgumentError.value(
        buttonHold < Duration.zero ? buttonHold : buttonDelay,
        buttonHold < Duration.zero ? 'buttonHold' : 'buttonDelay',
        'must not be negative',
      );
    }
  }

  final LinuxEvdevControllerDiscovery discovery;
  final LinuxEvdevDeviceFactory factory;
  final Duration buttonHold;
  final Duration buttonDelay;
  final LinuxEvdevDelay delay;

  LinuxEvdevDevicePort? _device;
  bool _closed = false;

  @override
  Future<void> perform(ReplayMenuAction action) async {
    if (_closed) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.closed,
        'The Linux existing-controller input port is closed.',
      );
    }

    try {
      final device = await _ensureDevice();
      switch (action) {
        case ReplayMenuAction.openReplay:
          await _tap(device);
          await delay(buttonDelay);
          await _tap(device);
        case ReplayMenuAction.exitToReplayList:
          await _tap(device);
        case ReplayMenuAction.selectNextReplay:
          _emit(device, LinuxEvdevEventType.abs, LinuxEvdevEventCode.absHat0Y,
              -1);
          await delay(buttonHold);
          _emit(
              device, LinuxEvdevEventType.abs, LinuxEvdevEventCode.absHat0Y, 0);
      }
    } catch (error, stackTrace) {
      try {
        await _closeDevice(reportFailure: true);
      } catch (cleanupError) {
        final action = error is LinuxEvdevException ? error : null;
        final cleanupMessage = cleanupError is LinuxEvdevException
            ? cleanupError.message
            : cleanupError.toString();
        final cleanupDetail = cleanupError is LinuxEvdevException &&
                cleanupError.code == LinuxEvdevErrorCode.closeFailed
            ? 'The controller could not be closed.'
            : 'The controller could not be returned to a neutral state and may still be holding an input.';
        final combined = LinuxEvdevException(
          action?.code ?? LinuxEvdevErrorCode.writeFailed,
          '${action?.message ?? error} $cleanupDetail Cleanup error: $cleanupMessage',
          errno: action?.errno,
          cause: error,
        );
        Error.throwWithStackTrace(
          combined,
          stackTrace,
        );
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
    await _closeDevice(reportFailure: true);
  }

  Future<LinuxEvdevDevicePort> _ensureDevice() async {
    final existing = _device;
    if (existing != null) {
      return existing;
    }
    final node = discovery.discover();
    late final LinuxEvdevDevicePort device;
    try {
      device = factory.open(node.path);
    } catch (error, stackTrace) {
      final typed = _asEvdevException(
        error,
        operation: 'The controller node ${node.path} could not be opened',
      );
      Error.throwWithStackTrace(typed, stackTrace);
    }
    _device = device;
    return device;
  }

  Future<void> _tap(LinuxEvdevDevicePort device) async {
    var pressed = false;
    Object? bodyFailure;
    StackTrace? bodyStack;
    try {
      _emit(device, LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 1);
      pressed = true;
      await delay(buttonHold);
    } catch (error, stackTrace) {
      bodyFailure = error;
      bodyStack = stackTrace;
    }
    if (pressed) {
      try {
        _emit(device, LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 0);
      } catch (releaseError, releaseStack) {
        if (bodyFailure != null) {
          final action =
              bodyFailure is LinuxEvdevException ? bodyFailure : null;
          final releaseMessage = releaseError is LinuxEvdevException
              ? releaseError.message
              : releaseError.toString();
          final combined = LinuxEvdevException(
            action?.code ?? LinuxEvdevErrorCode.writeFailed,
            '${action?.message ?? bodyFailure} The controller release event could not be sent. Release error: $releaseMessage',
            errno: action?.errno,
            cause: bodyFailure,
          );
          Error.throwWithStackTrace(combined, bodyStack!);
        }
        Error.throwWithStackTrace(releaseError, releaseStack);
      }
    }
    if (bodyFailure != null) {
      Error.throwWithStackTrace(bodyFailure, bodyStack!);
    }
  }

  void _emit(LinuxEvdevDevicePort device, int type, int code, int value) {
    device.write(
      encodeLinuxInputEvent(type: type, code: code, value: value),
    );
    device.write(
      encodeLinuxInputEvent(
        type: LinuxEvdevEventType.syn,
        code: LinuxEvdevEventCode.synReport,
        value: 0,
      ),
    );
  }

  Future<void> _closeDevice({required bool reportFailure}) async {
    final device = _device;
    _device = null;
    if (device == null) {
      return;
    }

    Object? failure;
    StackTrace? failureStack;
    Object? closeFailure;
    StackTrace? closeStack;
    try {
      _neutralise(device);
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    try {
      device.close();
    } catch (error, stackTrace) {
      closeFailure = error;
      closeStack = stackTrace;
    }
    if (failure != null && closeFailure != null) {
      final neutralisation = failure is LinuxEvdevException ? failure : null;
      final closeMessage = closeFailure is LinuxEvdevException
          ? closeFailure.message
          : closeFailure.toString();
      failure = LinuxEvdevException(
        neutralisation?.code ?? LinuxEvdevErrorCode.writeFailed,
        '${neutralisation?.message ?? failure} The controller could not be returned to a neutral state and may still be holding an input. The controller could not be closed. Close error: $closeMessage',
        errno: neutralisation?.errno,
        cause: closeFailure,
      );
    } else if (failure == null && closeFailure != null) {
      failure = closeFailure;
      failureStack = closeStack;
    }
    if (failure != null && reportFailure) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }

  void _neutralise(LinuxEvdevDevicePort device) {
    Object? failure;
    StackTrace? failureStack;
    try {
      _emit(device, LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 0);
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    try {
      _emit(device, LinuxEvdevEventType.abs, LinuxEvdevEventCode.absHat0Y, 0);
    } catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }
}

class LinuxEvdevNativeDeviceFactory implements LinuxEvdevDeviceFactory {
  const LinuxEvdevNativeDeviceFactory();

  @override
  LinuxEvdevDevicePort open(String path) => LinuxEvdevNativeDevice.open(path);
}

/// Direct libc implementation of the evdev writer seam.
class LinuxEvdevNativeDevice implements LinuxEvdevDevicePort {
  LinuxEvdevNativeDevice._({
    required _LinuxEvdevRuntime runtime,
    required int fileDescriptor,
  })  : _runtime = runtime,
        _fileDescriptor = fileDescriptor;

  factory LinuxEvdevNativeDevice.open(String path) {
    if (!Platform.isLinux) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.unsupportedPlatform,
        'Linux evdev input cannot be opened on this operating system.',
      );
    }
    final runtime = _LinuxEvdevRuntime.load();
    final pathBytes = utf8.encode(path);
    final pathPointer = runtime.malloc(pathBytes.length + 1).cast<Uint8>();
    if (pathPointer.address == 0) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.nodeNotWritable,
        'Could not allocate the Linux controller node path.',
      );
    }
    try {
      final target = pathPointer.asTypedList(pathBytes.length + 1);
      target.setAll(0, pathBytes);
      target[pathBytes.length] = 0;
      final fileDescriptor = runtime.open(pathPointer.cast<Int8>(), _oWronly);
      if (fileDescriptor < 0) {
        final errno = runtime.errno;
        final code = errno == 1 || errno == 13
            ? LinuxEvdevErrorCode.nodeNotWritable
            : LinuxEvdevErrorCode.controllerNotReading;
        throw LinuxEvdevException(
          code,
          code == LinuxEvdevErrorCode.nodeNotWritable
              ? 'The controller node $path is not writable by Afterimage (errno $errno).'
              : 'The controller node $path is no longer available (errno $errno).',
          errno: errno,
        );
      }
      return LinuxEvdevNativeDevice._(
        runtime: runtime,
        fileDescriptor: fileDescriptor,
      );
    } finally {
      runtime.free(pathPointer.cast<Void>());
    }
  }

  final _LinuxEvdevRuntime _runtime;
  final int _fileDescriptor;
  bool _closed = false;

  @override
  void write(List<int> bytes) {
    _ensureOpen();
    if (bytes.length != linuxInputEventSize) {
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.invalidEvent,
        'A Linux input event must be $linuxInputEventSize bytes.',
      );
    }
    final pointer = _runtime.malloc(bytes.length).cast<Uint8>();
    if (pointer.address == 0) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.writeFailed,
        'Could not allocate a Linux controller input event.',
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
          final errno = _runtime.errno;
          throw LinuxEvdevException(
            LinuxEvdevErrorCode.writeFailed,
            'The controller node rejected an input event (errno $errno).',
            errno: errno,
          );
        }
        if (written == 0) {
          throw const LinuxEvdevException(
            LinuxEvdevErrorCode.writeFailed,
            'The controller node wrote zero bytes for an input event.',
          );
        }
        offset += written;
      }
    } finally {
      _runtime.free(pointer.cast<Void>());
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    try {
      if (_runtime.close(_fileDescriptor) < 0) {
        final errno = _runtime.errno;
        throw LinuxEvdevException(
          LinuxEvdevErrorCode.closeFailed,
          'The Linux controller node could not be closed (errno $errno).',
          errno: errno,
        );
      }
    } finally {
      _closed = true;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.closed,
        'The Linux controller node is closed.',
      );
    }
  }
}

const int _oWronly = 0x0001;

LinuxEvdevException _asEvdevException(
  Object error, {
  required String operation,
}) {
  if (error is LinuxEvdevException) {
    return error;
  }
  final osError = switch (error) {
    OSError value => value,
    FileSystemException value => value.osError,
    _ => null,
  };
  if (osError != null) {
    final errno = osError.errorCode;
    final code = errno == 1 || errno == 13
        ? LinuxEvdevErrorCode.nodeNotWritable
        : errno == 2 || errno == 6 || errno == 19
            ? LinuxEvdevErrorCode.controllerNotReading
            : LinuxEvdevErrorCode.nodeNotWritable;
    return LinuxEvdevException(
      code,
      '$operation failed (errno $errno).',
      errno: errno,
      cause: error,
    );
  }
  return LinuxEvdevException(
    LinuxEvdevErrorCode.nodeNotWritable,
    '$operation failed.',
    cause: error,
  );
}

final class _LinuxEvdevRuntime {
  _LinuxEvdevRuntime._({required DynamicLibrary library})
      : _malloc = library.lookupFunction<Pointer<Void> Function(UintPtr),
            Pointer<Void> Function(int)>('malloc'),
        _free = library.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('free'),
        _open = library.lookupFunction<Int32 Function(Pointer<Int8>, Int32),
            int Function(Pointer<Int8>, int)>('open'),
        _write = library.lookupFunction<
            IntPtr Function(Int32, Pointer<Void>, UintPtr),
            int Function(int, Pointer<Void>, int)>('write'),
        _close =
            library.lookupFunction<Int32 Function(Int32), int Function(int)>(
          'close',
        ),
        _errnoLocation = library.lookupFunction<Pointer<Int32> Function(),
            Pointer<Int32> Function()>('__errno_location');

  factory _LinuxEvdevRuntime.load() {
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
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.nodeNotWritable,
        'The Linux C runtime needed for evdev input is unavailable.',
        cause: failure,
      );
    }
    try {
      return _LinuxEvdevRuntime._(library: library);
    } on Object catch (error) {
      throw LinuxEvdevException(
        LinuxEvdevErrorCode.nodeNotWritable,
        'The Linux C runtime does not expose the evdev input calls.',
        cause: error,
      );
    }
  }

  final Pointer<Void> Function(int) _malloc;
  final void Function(Pointer<Void>) _free;
  final int Function(Pointer<Int8>, int) _open;
  final int Function(int, Pointer<Void>, int) _write;
  final int Function(int) _close;
  final Pointer<Int32> Function() _errnoLocation;

  Pointer<Void> malloc(int size) => _malloc(size);

  void free(Pointer<Void> pointer) => _free(pointer);

  int open(Pointer<Int8> path, int flags) => _open(path, flags);

  int write(int fileDescriptor, Pointer<Void> buffer, int length) =>
      _write(fileDescriptor, buffer, length);

  int close(int fileDescriptor) => _close(fileDescriptor);

  int get errno => _errnoLocation().value;
}
