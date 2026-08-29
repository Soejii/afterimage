import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'windows_native_errors.dart';

const String ggstWindowsExecutable = 'GGST-Win64-Shipping.exe';

const int windowsUWorldGameStateOffset = 0x130;
const int windowsGameStateEngineOffset = 0xC38;
const int windowsEngineGameFrameOffset = 0x3E7C;
const int windowsGameStateEventsOffset = 0xC58;
const int windowsEventsArrayOffset = 0x8;
const int windowsEventsCountOffset = 0xA8;
const int windowsEventSize = 0x10;
const int windowsMatchResultEventType = 15;
const int windowsMaxEventCount = 10;

const int _th32csSnapProcess = 0x00000002;
const int _th32csSnapModule = 0x00000008;
const int _th32csSnapModule32 = 0x00000010;
const int _processVmRead = 0x0010;
const int _processQueryInformation = 0x0400;
const int _errorAccessDenied = 5;
const int _errorInvalidParameter = 87;
const int _errorBadLength = 24;
const int _memCommit = 0x1000;
const int _pageNoAccess = 0x01;
const int _pageReadOnly = 0x02;
const int _pageReadWrite = 0x04;
const int _pageWriteCopy = 0x08;
const int _pageExecuteRead = 0x20;
const int _pageExecuteReadWrite = 0x40;
const int _pageExecuteWriteCopy = 0x80;
const int _pageGuard = 0x100;

/// One module image returned by Tool Help.
class WindowsModule {
  const WindowsModule({
    required this.name,
    required this.baseAddress,
    required this.sizeOfImage,
  })  : assert(baseAddress >= 0),
        assert(sizeOfImage > 0);

  final String name;
  final int baseAddress;
  final int sizeOfImage;

  // Compatibility names for code that mirrors the Windows API.
  int get lpBaseOfDll => baseAddress;

  // ignore: non_constant_identifier_names
  int get SizeOfImage => sizeOfImage;
}

/// A committed, readable region returned by VirtualQueryEx.
///
/// Regions are kept separate from [WindowsModule] because a PE image can
/// contain inaccessible gaps or guard pages between readable sections.
class WindowsMemoryRegion {
  const WindowsMemoryRegion({
    required this.baseAddress,
    required this.size,
  })  : assert(baseAddress >= 0),
        assert(size > 0);

  final int baseAddress;
  final int size;

  int get endAddress => baseAddress + size;
}

/// The native seam around the small Win32 surface used by the recorder.
///
/// Tests inject this interface, so Linux test runs never need to load a
/// Windows DLL. The production implementation binds kernel32 lazily.
abstract interface class WindowsNativeApi {
  int findProcessId(String processName);

  Pointer<Void> openProcess(int processId);

  WindowsModule moduleFromName(
    Pointer<Void> processHandle,
    int processId,
    String moduleName,
  );

  List<WindowsMemoryRegion> readableMemoryRegions(
    Pointer<Void> processHandle,
    WindowsModule module,
  );

  List<int> readProcessMemory(
    Pointer<Void> processHandle,
    int address,
    int length,
  );

  void closeHandle(Pointer<Void> handle);
}

abstract interface class WindowsMemorySession {
  int get processId;

  WindowsModule moduleFromName(String moduleName);

  List<WindowsMemoryRegion> readableMemoryRegions(WindowsModule module);

  List<int> readBytes(int address, int length);

  void close();
}

typedef WindowsMemorySessionFactory = WindowsMemorySession Function(
  String processName,
);

/// A read-only GGST process-memory session backed by ReadProcessMemory.
///
/// No native function is looked up by the constructor. [SystemWindowsNativeApi]
/// binds kernel32 only after a Windows operation is requested.
class WindowsProcessMemory implements WindowsMemorySession {
  WindowsProcessMemory._({
    required this.processId,
    required WindowsNativeApi api,
    required Pointer<Void> processHandle,
  })  : _api = api,
        _processHandle = processHandle;

  factory WindowsProcessMemory.open(
    String processName, {
    WindowsNativeApi? api,
  }) {
    if (!Platform.isWindows && api == null) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'The Windows native recorder can only open GGST in a Windows desktop build.',
      );
    }
    final native = api ?? SystemWindowsNativeApi();
    final processId = native.findProcessId(processName);
    final processHandle = native.openProcess(processId);
    try {
      if (_isInvalidHandle(processHandle)) {
        throw const WindowsNativeException(
          WindowsNativeErrorCode.processMemoryDenied,
          'Windows returned an invalid GGST process handle. Check process permissions and try again.',
        );
      }
      return WindowsProcessMemory._(
        processId: processId,
        api: native,
        processHandle: processHandle,
      );
    } catch (_) {
      native.closeHandle(processHandle);
      rethrow;
    }
  }

  @override
  final int processId;
  final WindowsNativeApi _api;
  Pointer<Void>? _processHandle;
  bool _closed = false;

  @override
  WindowsModule moduleFromName(String moduleName) {
    final handle = _ensureOpen();
    return _api.moduleFromName(handle, processId, moduleName);
  }

  @override
  List<WindowsMemoryRegion> readableMemoryRegions(WindowsModule module) {
    final handle = _ensureOpen();
    return _api.readableMemoryRegions(handle, module);
  }

  @override
  List<int> readBytes(int address, int length) {
    _ensureOpen();
    if (address < 0 || length < 0) {
      throw ArgumentError('Memory address and length must not be negative.');
    }
    if (length == 0) {
      return const <int>[];
    }
    return _api.readProcessMemory(_processHandle!, address, length);
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    final handle = _processHandle;
    _processHandle = null;
    if (handle != null) {
      try {
        _api.closeHandle(handle);
      } on Object {
        // Closing is best effort. It must not hide a primary recorder error.
      }
    }
  }

  Pointer<Void> _ensureOpen() {
    final handle = _processHandle;
    if (_closed || handle == null) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.closed,
        'The Windows process-memory session is closed.',
      );
    }
    return handle;
  }
}

/// Lazy Win32 implementation of [WindowsNativeApi].
///
/// This class intentionally contains no top-level DLL lookup. Constructing it
/// on Linux is safe; calling it on Linux returns a typed availability error.
class SystemWindowsNativeApi implements WindowsNativeApi {
  SystemWindowsNativeApi();

  bool _bound = false;

  late final Pointer<Void> Function(int, int) _createToolhelpSnapshot;
  late final int Function(Pointer<Void>, Pointer<_ProcessEntry32W>)
      _process32First;
  late final int Function(Pointer<Void>, Pointer<_ProcessEntry32W>)
      _process32Next;
  late final int Function(Pointer<Void>, Pointer<_ModuleEntry32W>)
      _module32First;
  late final int Function(Pointer<Void>, Pointer<_ModuleEntry32W>)
      _module32Next;
  late final Pointer<Void> Function(int, int, int) _openProcess;
  late final int Function(Pointer<Void>) _closeHandle;
  late final int Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>, int, Pointer<UintPtr>)
      _readProcessMemory;
  late final int Function(
          Pointer<Void>, Pointer<Void>, Pointer<_MemoryBasicInformation>, int)
      _virtualQueryEx;
  late final int Function() _getLastError;
  late final Pointer<Void> Function() _getProcessHeap;
  late final Pointer<Void> Function(Pointer<Void>, int, int) _heapAlloc;
  late final int Function(Pointer<Void>, int, Pointer<Void>) _heapFree;

  @override
  int findProcessId(String processName) {
    _bind();
    final snapshot = _createToolhelpSnapshot(_th32csSnapProcess, 0);
    if (_isInvalidHandle(snapshot)) {
      _throwLastError('enumerate running Windows processes');
    }

    Pointer<_ProcessEntry32W>? entry;
    try {
      final allocated = _allocate<_ProcessEntry32W>(sizeOf<_ProcessEntry32W>());
      entry = allocated;
      allocated.ref.dwSize = sizeOf<_ProcessEntry32W>();
      var found = _process32First(snapshot, allocated);
      while (found != 0) {
        final name = _utf16Array(allocated.ref.szExeFile, 260);
        if (_sameExecutable(name, processName)) {
          return allocated.ref.th32ProcessID;
        }
        found = _process32Next(snapshot, allocated);
      }
    } on WindowsNativeException {
      rethrow;
    } finally {
      _free(entry?.cast<Void>());
      _closeSnapshot(snapshot);
    }

    throw WindowsNativeException(
      WindowsNativeErrorCode.gameAbsent,
      '${_basename(processName)} is not running. Start GGST before recording.',
    );
  }

  @override
  Pointer<Void> openProcess(int processId) {
    _bind();
    final handle = _openProcess(
      _processVmRead | _processQueryInformation,
      0,
      processId,
    );
    if (_isInvalidHandle(handle)) {
      final error = _lastError();
      if (error == _errorInvalidParameter) {
        throw WindowsNativeException(
          WindowsNativeErrorCode.gameAbsent,
          'GGST exited before Afterimage could open its process.',
          systemError: error,
        );
      }
      throw windowsSystemException(
        error,
        operation: 'open the GGST process',
      );
    }
    return handle;
  }

  @override
  WindowsModule moduleFromName(
    Pointer<Void> processHandle,
    int processId,
    String moduleName,
  ) {
    _bind();
    Pointer<Void>? snapshot;
    Pointer<_ModuleEntry32W>? entry;
    try {
      // ERROR_BAD_LENGTH is documented as transient while the module list is
      // changing. Retry a few times before reporting a real failure.
      for (var attempt = 0; attempt < 3; attempt++) {
        snapshot = _createToolhelpSnapshot(
          _th32csSnapModule | _th32csSnapModule32,
          processId,
        );
        if (!_isInvalidHandle(snapshot)) {
          break;
        }
        final error = _lastError();
        _closeSnapshot(snapshot);
        snapshot = null;
        if (error != _errorBadLength || attempt == 2) {
          _throwModuleSnapshotError(error);
        }
      }

      final allocated = _allocate<_ModuleEntry32W>(sizeOf<_ModuleEntry32W>());
      entry = allocated;
      allocated.ref.dwSize = sizeOf<_ModuleEntry32W>();
      var found = _module32First(snapshot!, allocated);
      while (found != 0) {
        final name = _utf16Array(allocated.ref.szModule, 256);
        if (_sameExecutable(name, moduleName)) {
          final base = allocated.ref.modBaseAddr.address;
          final size = allocated.ref.modBaseSize;
          if (base > 0 && size > 0) {
            return WindowsModule(
              name: name,
              baseAddress: base,
              sizeOfImage: size,
            );
          }
        }
        found = _module32Next(snapshot, allocated);
      }
    } finally {
      _free(entry?.cast<Void>());
      _closeSnapshot(snapshot);
    }

    throw WindowsNativeException(
      WindowsNativeErrorCode.gameModuleMissing,
      'GGST is running, but $moduleName is not mapped. The game may still be starting or its process architecture may not match this build.',
    );
  }

  @override
  List<WindowsMemoryRegion> readableMemoryRegions(
    Pointer<Void> processHandle,
    WindowsModule module,
  ) {
    _bind();
    if (module.sizeOfImage <= 0) {
      return const <WindowsMemoryRegion>[];
    }
    final moduleEnd = module.baseAddress + module.sizeOfImage;
    final information = _allocate<_MemoryBasicInformation>(
      sizeOf<_MemoryBasicInformation>(),
    );
    final regions = <WindowsMemoryRegion>[];
    try {
      var cursor = module.baseAddress;
      while (cursor < moduleEnd) {
        final queried = _virtualQueryEx(
          processHandle,
          Pointer<Void>.fromAddress(cursor),
          information,
          sizeOf<_MemoryBasicInformation>(),
        );
        if (queried == 0) {
          _throwLastError('query GGST memory regions');
        }

        final nativeBase = information.ref.baseAddress.address;
        final nativeSize = information.ref.regionSize;
        final nativeEnd = nativeBase + nativeSize;
        if (nativeSize <= 0 || nativeEnd <= cursor) {
          throw const WindowsNativeException(
            WindowsNativeErrorCode.memoryReadFailed,
            'Windows returned an invalid GGST memory region while scanning the module.',
          );
        }
        final start = math.max(cursor, nativeBase);
        final end = math.min(moduleEnd, nativeEnd);
        if (end > start &&
            information.ref.state == _memCommit &&
            _isReadableProtection(information.ref.protect)) {
          regions.add(
            WindowsMemoryRegion(
              baseAddress: start,
              size: end - start,
            ),
          );
        }
        cursor = nativeEnd > cursor ? nativeEnd : cursor + 1;
      }
    } finally {
      _free(information.cast<Void>());
    }
    return List.unmodifiable(regions);
  }

  @override
  List<int> readProcessMemory(
    Pointer<Void> processHandle,
    int address,
    int length,
  ) {
    _bind();
    if (address < 0 || length < 0) {
      throw ArgumentError('Memory address and length must not be negative.');
    }
    if (length == 0) {
      return const <int>[];
    }

    final heap = _getProcessHeap();
    if (heap.address == 0) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Windows did not provide a process heap for a safe memory read.',
      );
    }
    final buffer = _heapAlloc(heap, 0, length);
    final bytesRead = _heapAlloc(heap, 0, sizeOf<UintPtr>());
    if (buffer.address == 0 || bytesRead.address == 0) {
      _free(buffer);
      _free(bytesRead);
      throw const WindowsNativeException(
        WindowsNativeErrorCode.memoryReadFailed,
        'Windows could not allocate a temporary buffer for the GGST memory read.',
      );
    }

    try {
      bytesRead.cast<UintPtr>().value = 0;
      final succeeded = _readProcessMemory(
            processHandle,
            Pointer<Void>.fromAddress(address),
            buffer,
            length,
            bytesRead.cast<UintPtr>(),
          ) !=
          0;
      if (!succeeded) {
        _throwLastError('read GGST process memory');
      }
      final count = bytesRead.cast<UintPtr>().value;
      if (count != length) {
        throw WindowsNativeException(
          WindowsNativeErrorCode.memoryReadFailed,
          'Windows returned only $count of $length bytes while reading GGST memory. The process may be changing or this build may not match GGST.',
        );
      }
      return List<int>.from(buffer.cast<Uint8>().asTypedList(length));
    } finally {
      _free(buffer);
      _free(bytesRead);
    }
  }

  @override
  void closeHandle(Pointer<Void> handle) {
    if (!_bound) {
      return;
    }
    if (!_isInvalidHandle(handle)) {
      _closeHandle(handle);
    }
  }

  void _bind() {
    if (_bound) {
      return;
    }
    if (!Platform.isWindows) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Windows native functions are available only in a Windows desktop build.',
      );
    }
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _createToolhelpSnapshot = kernel32.lookupFunction<
          Pointer<Void> Function(Uint32, Uint32),
          Pointer<Void> Function(int, int)>('CreateToolhelp32Snapshot');
      _process32First = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<_ProcessEntry32W>),
          int Function(
              Pointer<Void>, Pointer<_ProcessEntry32W>)>('Process32FirstW');
      _process32Next = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<_ProcessEntry32W>),
          int Function(
              Pointer<Void>, Pointer<_ProcessEntry32W>)>('Process32NextW');
      _module32First = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<_ModuleEntry32W>),
          int Function(
              Pointer<Void>, Pointer<_ModuleEntry32W>)>('Module32FirstW');
      _module32Next = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<_ModuleEntry32W>),
          int Function(
              Pointer<Void>, Pointer<_ModuleEntry32W>)>('Module32NextW');
      _openProcess = kernel32.lookupFunction<
          Pointer<Void> Function(Uint32, Int32, Uint32),
          Pointer<Void> Function(int, int, int)>('OpenProcess');
      _closeHandle = kernel32.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('CloseHandle');
      _readProcessMemory = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, UintPtr,
              Pointer<UintPtr>),
          int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, int,
              Pointer<UintPtr>)>('ReadProcessMemory');
      _virtualQueryEx = kernel32.lookupFunction<
          UintPtr Function(Pointer<Void>, Pointer<Void>,
              Pointer<_MemoryBasicInformation>, UintPtr),
          int Function(Pointer<Void>, Pointer<Void>,
              Pointer<_MemoryBasicInformation>, int)>('VirtualQueryEx');
      _getLastError = kernel32
          .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
      _getProcessHeap = kernel32.lookupFunction<Pointer<Void> Function(),
          Pointer<Void> Function()>('GetProcessHeap');
      _heapAlloc = kernel32.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr),
          Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
      _heapFree = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
          int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
      _bound = true;
    } on Object catch (error) {
      throw WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Afterimage could not load the Windows process APIs. Reinstall the Windows desktop runtime and try again.',
        cause: error,
      );
    }
  }

  Pointer<T> _allocate<T extends NativeType>(int size) {
    final heap = _getProcessHeap();
    if (heap.address == 0) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Windows did not provide a process heap for native metadata.',
      );
    }
    final pointer = _heapAlloc(heap, 0, size);
    if (pointer.address == 0) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.memoryReadFailed,
        'Windows could not allocate native process metadata.',
      );
    }
    return pointer.cast<T>();
  }

  void _free(Pointer<Void>? pointer) {
    if (pointer == null || pointer.address == 0 || !_bound) {
      return;
    }
    final heap = _getProcessHeap();
    if (heap.address != 0) {
      _heapFree(heap, 0, pointer);
    }
  }

  void _closeSnapshot(Pointer<Void>? snapshot) {
    if (snapshot != null && !_isInvalidHandle(snapshot)) {
      _closeHandle(snapshot);
    }
  }

  int _lastError() => _getLastError();

  Never _throwLastError(String operation) {
    final error = _lastError();
    throw windowsSystemException(error, operation: operation);
  }

  Never _throwModuleSnapshotError(int error) {
    if (error == _errorAccessDenied) {
      throw windowsSystemException(
        error,
        operation: 'enumerate GGST modules',
      );
    }
    throw WindowsNativeException(
      WindowsNativeErrorCode.gameModuleMissing,
      'Windows could not enumerate GGST modules (Win32 error $error). Restart GGST and try again.',
      systemError: error,
    );
  }
}

/// A bounded wildcard pattern used by the GGST GWorld locator.
class WindowsBytePattern {
  WindowsBytePattern({
    required Iterable<int> bytes,
    required String mask,
  })  : bytes = List.unmodifiable(bytes),
        mask = mask {
    if (this.bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    if (this.bytes.length != mask.length) {
      throw ArgumentError.value(mask, 'mask', 'must match the byte length');
    }
    if (this.bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError.value(bytes, 'bytes', 'must contain bytes');
    }
    if (mask.split('').any((value) => value != 'x' && value != '?')) {
      throw ArgumentError.value(mask, 'mask', 'must contain only x and ?');
    }
  }

  const WindowsBytePattern._const(this.bytes, this.mask);

  final List<int> bytes;
  final String mask;

  int get length => bytes.length;

  bool matchesAt(List<int> data, int offset) {
    if (offset < 0 || offset + length > data.length) {
      return false;
    }
    for (var index = 0; index < length; index++) {
      if (mask[index] == 'x' && data[offset + index] != bytes[index]) {
        return false;
      }
    }
    return true;
  }

  int? find(List<int> data) {
    final lastStart = data.length - length;
    for (var offset = 0; offset <= lastStart; offset++) {
      if (matchesAt(data, offset)) {
        return offset;
      }
    }
    return null;
  }
}

const WindowsBytePattern ggstWindowsGWorldPattern = WindowsBytePattern._const(
  <int>[
    0x0F,
    0x2E,
    0x00,
    0x74,
    0x00,
    0x48,
    0x8B,
    0x1D,
    0x00,
    0x00,
    0x00,
    0x00,
    0x48,
    0x85,
    0xDB,
    0x74,
  ],
  'xx?x?xxx????xxxx',
);

int resolveWindowsRipRelativeAddress(
        int instructionAddress, int displacement) =>
    instructionAddress + 12 + displacement;

int decodeWindowsSignedInt32(List<int> bytes) {
  if (bytes.length < 4) {
    throw ArgumentError.value(bytes, 'bytes', 'must contain four bytes');
  }
  final unsigned =
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  return unsigned >= 0x80000000 ? unsigned - 0x100000000 : unsigned;
}

class WindowsPatternScanResult {
  const WindowsPatternScanResult({
    required this.address,
    required this.readableRanges,
    required this.inaccessibleReads,
    required this.permissionDeniedReads,
    required this.architectureMismatchReads,
  });

  final int? address;
  final int readableRanges;
  final int inaccessibleReads;
  final int permissionDeniedReads;
  final int architectureMismatchReads;

  bool get found => address != null;
}

/// Scans only the mapped GGST image, in bounded reads with pattern overlap.
class WindowsPatternScanner {
  const WindowsPatternScanner({
    this.chunkSize = 8 * 1024 * 1024,
  });

  final int chunkSize;

  WindowsPatternScanResult scan({
    required WindowsModule module,
    required WindowsBytePattern pattern,
    required List<int> Function(int address, int length) read,
    Iterable<WindowsMemoryRegion>? readableRegions,
  }) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
    var readableRanges = 0;
    var inaccessibleReads = 0;
    var permissionDeniedReads = 0;
    var architectureMismatchReads = 0;
    final overlap = pattern.length - 1;
    final regions = readableRegions ??
        <WindowsMemoryRegion>[
          WindowsMemoryRegion(
            baseAddress: module.baseAddress,
            size: module.sizeOfImage,
          ),
        ];

    for (final region in regions) {
      final regionStart = math.max(module.baseAddress, region.baseAddress);
      final regionEnd = math.min(
        module.baseAddress + module.sizeOfImage,
        region.endAddress,
      );
      if (regionEnd <= regionStart) {
        continue;
      }
      readableRanges++;
      for (var offset = regionStart; offset < regionEnd; offset += chunkSize) {
        final readOffset = math.max(regionStart, offset - overlap);
        final readLength = math.min(
          chunkSize + overlap,
          regionEnd - readOffset,
        );
        late final List<int> bytes;
        try {
          bytes = read(readOffset, readLength);
        } on Object catch (error) {
          inaccessibleReads++;
          final typed = windowsMemoryException(error);
          if (typed.code == WindowsNativeErrorCode.processMemoryDenied) {
            permissionDeniedReads++;
          }
          if (typed.code == WindowsNativeErrorCode.architectureMismatch) {
            architectureMismatchReads++;
          }
          continue;
        }
        final hit = pattern.find(bytes);
        if (hit != null) {
          return WindowsPatternScanResult(
            address: readOffset + hit,
            readableRanges: readableRanges,
            inaccessibleReads: inaccessibleReads,
            permissionDeniedReads: permissionDeniedReads,
            architectureMismatchReads: architectureMismatchReads,
          );
        }
      }
    }
    return WindowsPatternScanResult(
      address: null,
      readableRanges: readableRanges,
      inaccessibleReads: inaccessibleReads,
      permissionDeniedReads: permissionDeniedReads,
      architectureMismatchReads: architectureMismatchReads,
    );
  }
}

final class _MemoryBasicInformation extends Struct {
  external Pointer<Void> baseAddress;

  external Pointer<Void> allocationBase;

  @Uint32()
  external int allocationProtect;

  @Uint16()
  external int partitionId;

  @Size()
  external int regionSize;

  @Uint32()
  external int state;

  @Uint32()
  external int protect;

  @Uint32()
  external int type;
}

bool _isReadableProtection(int protection) {
  if (protection == _pageNoAccess || protection & _pageGuard != 0) {
    return false;
  }
  final basic = protection & 0xFF;
  return basic == _pageReadOnly ||
      basic == _pageReadWrite ||
      basic == _pageWriteCopy ||
      basic == _pageExecuteRead ||
      basic == _pageExecuteReadWrite ||
      basic == _pageExecuteWriteCopy;
}

final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;

  @Uint32()
  external int cntUsage;

  @Uint32()
  external int th32ProcessID;

  external Pointer<Void> th32DefaultHeapID;

  @Uint32()
  external int th32ModuleID;

  @Uint32()
  external int cntThreads;

  @Uint32()
  external int th32ParentProcessID;

  @Int32()
  external int pcPriClassBase;

  @Uint32()
  external int dwFlags;

  @Array<Uint16>(260)
  external Array<Uint16> szExeFile;
}

final class _ModuleEntry32W extends Struct {
  @Uint32()
  external int dwSize;

  @Uint32()
  external int th32ModuleID;

  @Uint32()
  external int th32ProcessID;

  @Uint32()
  external int glblcntUsage;

  @Uint32()
  external int proccntUsage;

  external Pointer<Uint8> modBaseAddr;

  @Uint32()
  external int modBaseSize;

  external Pointer<Void> hModule;

  @Array<Uint16>(256)
  external Array<Uint16> szModule;

  @Array<Uint16>(260)
  external Array<Uint16> szExePath;
}

String _utf16Array(Array<Uint16> value, int length) {
  final chars = List<int>.generate(length, (index) => value[index]);
  var end = 0;
  while (end < chars.length && chars[end] != 0) {
    end++;
  }
  return String.fromCharCodes(chars.sublist(0, end));
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

bool _sameExecutable(String actual, String expected) =>
    _basename(actual).toLowerCase() == _basename(expected).toLowerCase();

bool _isInvalidHandle(Pointer<Void> handle) =>
    handle.address == 0 ||
    handle.address == -1 ||
    handle.address == 0xFFFFFFFF ||
    handle.address == 0xFFFFFFFFFFFFFFFF;

/// Exposed for ABI verification without loading a Windows DLL.
int get windowsProcessEntrySize => sizeOf<_ProcessEntry32W>();
