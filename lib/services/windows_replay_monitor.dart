import 'dart:io';

import '../domain/replay_batch.dart';
import '../domain/recorder_contracts.dart';
import 'windows_native_errors.dart';
import 'windows_process_memory.dart';

typedef WindowsReadOnlyMemoryFactory = WindowsMemorySession Function(
  String processName,
);

/// Reads only the GGST state chain needed by the batch completion detector.
/// This adapter never exposes or writes game memory.
class WindowsReplayMonitor implements ReplayMonitorPort {
  WindowsReplayMonitor({
    this.processName = ggstWindowsExecutable,
    WindowsReadOnlyMemoryFactory? memoryFactory,
    this.patternScanner = const WindowsPatternScanner(),
  }) : memoryFactory = memoryFactory ?? _openWindowsMemory;

  final String processName;
  final WindowsReadOnlyMemoryFactory memoryFactory;
  final WindowsPatternScanner patternScanner;

  WindowsMemorySession? _memory;
  int? _gWorldPointerAddress;
  bool _closed = false;

  bool get isAttached => _memory != null && !_closed;

  int? get gWorldPointerAddress => _gWorldPointerAddress;

  @override
  Future<void> attach() async {
    await close();
    _closed = false;

    late final WindowsMemorySession memory;
    try {
      memory = memoryFactory(processName);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_monitorError(error), stackTrace);
    }

    try {
      final module = memory.moduleFromName(processName);
      final readableRegions = memory.readableMemoryRegions(module);
      final scan = patternScanner.scan(
        module: module,
        pattern: ggstWindowsGWorldPattern,
        read: memory.readBytes,
        readableRegions: readableRegions,
      );
      final hit = scan.address;
      if (hit == null) {
        if (scan.architectureMismatchReads > 0) {
          throw const WindowsNativeException(
            WindowsNativeErrorCode.architectureMismatch,
            'Windows could not read the GGST module. Use the Afterimage build that matches GGST (the supported target is 64-bit Windows).',
          );
        }
        if (scan.permissionDeniedReads > 0) {
          throw const WindowsNativeException(
            WindowsNativeErrorCode.processMemoryDenied,
            'GGST memory mappings were found, but Windows denied their contents. Check process permissions and use a matching 64-bit Afterimage build.',
          );
        }
        throw const WindowsNativeException(
          WindowsNativeErrorCode.signatureMismatch,
          'GGST is running, but its GWorld signature was not found. The game may have updated or this build may be unsupported.',
        );
      }

      final displacement =
          decodeWindowsSignedInt32(memory.readBytes(hit + 8, 4));
      _gWorldPointerAddress =
          resolveWindowsRipRelativeAddress(hit, displacement);
      _memory = memory;
    } catch (error, stackTrace) {
      memory.close();
      Error.throwWithStackTrace(_monitorError(error), stackTrace);
    }
  }

  @override
  Future<BattleSnapshot> snapshot() async {
    final memory = _memory;
    final gWorldPointerAddress = _gWorldPointerAddress;
    if (_closed || memory == null || gWorldPointerAddress == null) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.notAttached,
        'GGST monitor is not attached.',
      );
    }

    try {
      final uWorld = _readPointer(memory, gWorldPointerAddress);
      if (uWorld == 0) {
        return const BattleSnapshot.empty();
      }
      final gameState =
          _readPointer(memory, uWorld + windowsUWorldGameStateOffset);
      if (gameState == 0) {
        return const BattleSnapshot.empty();
      }
      final engine =
          _readPointer(memory, gameState + windowsGameStateEngineOffset);
      if (engine == 0) {
        return const BattleSnapshot.empty();
      }

      final frame = _readUint32(memory, engine + windowsEngineGameFrameOffset);
      final eventTypes = <int>{};
      final events =
          _readPointer(memory, gameState + windowsGameStateEventsOffset);
      if (events != 0) {
        final count = _readUint32(memory, events + windowsEventsCountOffset)
            .clamp(0, windowsMaxEventCount);
        for (var index = 0; index < count; index++) {
          eventTypes.add(
            _readUint32(
              memory,
              events + windowsEventsArrayOffset + index * windowsEventSize,
            ),
          );
        }
      }
      return BattleSnapshot(
        enginePresent: true,
        frame: frame,
        events: eventTypes,
      );
    } on OSError catch (error) {
      final typed = windowsMemoryException(error);
      if (typed.code == WindowsNativeErrorCode.memoryReadFailed) {
        // A game process can unload a mapping between two pointer reads. The
        // batch detector treats one inaccessible sample as a missing read, but
        // does not mistake a frozen frame for completion.
        return const BattleSnapshot.empty();
      }
      throw typed;
    } on WindowsNativeException catch (error) {
      if (error.code == WindowsNativeErrorCode.memoryReadFailed) {
        return const BattleSnapshot.empty();
      }
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    final memory = _memory;
    _memory = null;
    _gWorldPointerAddress = null;
    _closed = true;
    memory?.close();
  }

  int _readPointer(WindowsMemorySession memory, int address) {
    final bytes = memory.readBytes(address, 8);
    if (bytes.length < 8) {
      throw const OSError('A pointer read returned fewer than eight bytes.');
    }
    return bytes[0] |
        (bytes[1] << 8) |
        (bytes[2] << 16) |
        (bytes[3] << 24) |
        (bytes[4] << 32) |
        (bytes[5] << 40) |
        (bytes[6] << 48) |
        (bytes[7] << 56);
  }

  int _readUint32(WindowsMemorySession memory, int address) {
    final bytes = memory.readBytes(address, 4);
    if (bytes.length < 4) {
      throw const OSError('A uint32 read returned fewer than four bytes.');
    }
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }

  WindowsNativeException _monitorError(Object error) {
    if (error is WindowsNativeException) {
      return error;
    }
    if (error is OSError) {
      return windowsMemoryException(error);
    }
    return WindowsNativeException(
      WindowsNativeErrorCode.memoryReadFailed,
      'The Windows GGST monitor could not attach safely.',
      cause: error,
    );
  }
}

WindowsMemorySession _openWindowsMemory(String processName) =>
    WindowsProcessMemory.open(processName);
