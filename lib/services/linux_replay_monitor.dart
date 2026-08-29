import 'dart:io';

import '../domain/replay_batch.dart';
import '../domain/recorder_contracts.dart';
import 'linux_native_errors.dart';
import 'linux_process_memory.dart';

const int linuxUWorldGameStateOffset = 0x130;
const int linuxGameStateEngineOffset = 0xC38;
const int linuxEngineGameFrameOffset = 0x3E7C;
const int linuxGameStateEventsOffset = 0xC58;
const int linuxEventsArrayOffset = 0x8;
const int linuxEventsCountOffset = 0xA8;
const int linuxEventSize = 0x10;
const int linuxMatchResultEventType = 15;
const int linuxMaxEventCount = 10;

typedef LinuxReadOnlyMemoryFactory = LinuxMemorySession Function(
  String processName,
);

/// Reads only the small GGST state chain needed by the batch completion
/// detector. This adapter never exposes or writes game memory.
class LinuxReplayMonitor implements ReplayMonitorPort {
  LinuxReplayMonitor({
    this.processName = ggstLinuxExecutable,
    LinuxReadOnlyMemoryFactory? memoryFactory,
    this.patternScanner = const LinuxPatternScanner(),
  }) : memoryFactory = memoryFactory ?? _openLinuxMemory;

  final String processName;
  final LinuxReadOnlyMemoryFactory memoryFactory;
  final LinuxPatternScanner patternScanner;

  LinuxMemorySession? _memory;
  int? _gWorldPointerAddress;
  bool _closed = false;

  bool get isAttached => _memory != null && !_closed;

  int? get gWorldPointerAddress => _gWorldPointerAddress;

  @override
  Future<void> attach() async {
    await close();
    _closed = false;

    late final LinuxMemorySession memory;
    try {
      memory = memoryFactory(processName);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_monitorError(error), stackTrace);
    }

    try {
      final module = memory.moduleFromName(processName);
      final scan = patternScanner.scan(
        module: module,
        pattern: ggstGWorldPattern,
        read: memory.readBytes,
      );
      final hit = scan.address;
      if (hit == null) {
        if (scan.permissionDeniedReads > 0) {
          throw const LinuxNativeException(
            LinuxNativeErrorCode.processMemoryDenied,
            'GGST memory mappings were found, but reads were denied. Check the safe per-user ptrace policy described in the Linux runtime guide.',
          );
        }
        throw const LinuxNativeException(
          LinuxNativeErrorCode.signatureMismatch,
          'GGST is running, but its GWorld signature was not found. The game may have updated or this build may be unsupported.',
        );
      }

      final displacement = decodeSignedInt32(memory.readBytes(hit + 8, 4));
      _gWorldPointerAddress = resolveRipRelativeAddress(hit, displacement);
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
      throw const LinuxNativeException(
        LinuxNativeErrorCode.notAttached,
        'GGST monitor is not attached.',
      );
    }

    try {
      final uWorld = _readPointer(memory, gWorldPointerAddress);
      if (uWorld == 0) {
        return const BattleSnapshot.empty();
      }
      final gameState =
          _readPointer(memory, uWorld + linuxUWorldGameStateOffset);
      if (gameState == 0) {
        return const BattleSnapshot.empty();
      }
      final engine =
          _readPointer(memory, gameState + linuxGameStateEngineOffset);
      if (engine == 0) {
        return const BattleSnapshot.empty();
      }

      final frame = _readUint32(memory, engine + linuxEngineGameFrameOffset);
      final eventTypes = <int>{};
      final events =
          _readPointer(memory, gameState + linuxGameStateEventsOffset);
      if (events != 0) {
        final count = _readUint32(memory, events + linuxEventsCountOffset)
            .clamp(0, linuxMaxEventCount);
        for (var index = 0; index < count; index++) {
          eventTypes.add(
            _readUint32(
              memory,
              events + linuxEventsArrayOffset + index * linuxEventSize,
            ),
          );
        }
      }
      return BattleSnapshot(
        enginePresent: true,
        frame: frame,
        events: eventTypes,
      );
    } on OSError {
      // A game process can unload a mapping between two pointer reads. The
      // batch detector treats one inaccessible sample as a missing read, but
      // does not mistake a frozen frame for completion.
      return const BattleSnapshot.empty();
    } on LinuxNativeException catch (error) {
      if (error.code == LinuxNativeErrorCode.memoryReadFailed) {
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

  int _readPointer(LinuxMemorySession memory, int address) {
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

  int _readUint32(LinuxMemorySession memory, int address) {
    final bytes = memory.readBytes(address, 4);
    if (bytes.length < 4) {
      throw const OSError('A uint32 read returned fewer than four bytes.');
    }
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }

  LinuxNativeException _monitorError(Object error) {
    if (error is LinuxNativeException) {
      return error;
    }
    if (error is OSError) {
      return linuxMemoryException(error);
    }
    return LinuxNativeException(
      LinuxNativeErrorCode.memoryReadFailed,
      'The Linux GGST monitor could not attach safely.',
      cause: error,
    );
  }
}

LinuxMemorySession _openLinuxMemory(String processName) =>
    LinuxProcessMemory.open(processName);
