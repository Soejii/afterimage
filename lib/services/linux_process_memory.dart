import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'linux_native_errors.dart';

const String ggstLinuxExecutable = 'GGST-Win64-Shipping.exe';

const int _errnoOperationNotPermitted = 1; // EPERM
const int _errnoNoSuchProcess = 3; // ESRCH
const int _errnoInputOutput = 5; // EIO
const int _errnoPermissionDenied = 13; // EACCES
const int _errnoFunctionNotImplemented = 38; // ENOSYS

/// One line from `/proc/<pid>/maps`.
class LinuxMapping {
  const LinuxMapping({
    required this.start,
    required this.end,
    required this.permissions,
    this.path = '',
  }) : assert(end >= start);

  final int start;
  final int end;
  final String permissions;
  final String path;

  int get length => end - start;

  bool get readable => permissions.contains('r');

  bool get executable => permissions.contains('x');

  /// Parses the stable address/permission prefix of a procfs maps line.
  ///
  /// The pathname is optional. A malformed line is ignored by
  /// [parseLinuxMappings] instead of preventing the remaining mappings from
  /// being inspected.
  static LinuxMapping? parse(String line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 2) {
      return null;
    }
    final range = fields[0].split('-');
    if (range.length != 2 || fields[1].length < 4) {
      return null;
    }
    final start = int.tryParse(range[0], radix: 16);
    final end = int.tryParse(range[1], radix: 16);
    if (start == null || end == null || end < start) {
      return null;
    }
    return LinuxMapping(
      start: start,
      end: end,
      permissions: fields[1],
      path: fields.length > 5 ? fields.sublist(5).join(' ') : '',
    );
  }

  @override
  String toString() =>
      '${start.toRadixString(16)}-${end.toRadixString(16)} $permissions $path';
}

List<LinuxMapping> parseLinuxMappings(String mapsText) {
  final mappings = <LinuxMapping>[];
  for (final line in mapsText.split('\n')) {
    final mapping = LinuxMapping.parse(line);
    if (mapping != null) {
      mappings.add(mapping);
    }
  }
  mappings.sort((a, b) => a.start.compareTo(b.start));
  return List.unmodifiable(mappings);
}

/// All contiguous mappings belonging to one Wine PE image.
class LinuxModule {
  factory LinuxModule(Iterable<LinuxMapping> mappings) {
    final sorted = List<LinuxMapping>.from(mappings)..sort(_compareMappings);
    if (sorted.isEmpty) {
      throw ArgumentError.value(mappings, 'mappings', 'must not be empty');
    }
    return LinuxModule._(sorted);
  }

  LinuxModule._(List<LinuxMapping> mappings)
      : mappings = List.unmodifiable(mappings),
        baseAddress = mappings.first.start,
        sizeOfImage = _sumLength(mappings);

  final List<LinuxMapping> mappings;
  final int baseAddress;
  final int sizeOfImage;

  /// Compatibility names for code that mirrors the Windows module API.
  int get lpBaseOfDll => baseAddress;

  // ignore: non_constant_identifier_names
  int get SizeOfImage => sizeOfImage;

  static LinuxModule? fromMappings(
    Iterable<LinuxMapping> allMappings,
    String moduleName,
  ) {
    final sorted = List<LinuxMapping>.from(allMappings)..sort(_compareMappings);
    final matchingIndices = <int>[];
    for (var index = 0; index < sorted.length; index++) {
      if (_pathMatchesModule(sorted[index].path, moduleName)) {
        matchingIndices.add(index);
      }
    }
    if (matchingIndices.isEmpty) {
      return null;
    }

    final selected = <LinuxMapping>[];
    final selectedRanges = <(int, int)>{};
    for (final matchIndex in matchingIndices) {
      var expectedStart = sorted[matchIndex].start;
      for (var index = matchIndex; index < sorted.length; index++) {
        final mapping = sorted[index];
        if (mapping.start != expectedStart) {
          break;
        }
        final range = (mapping.start, mapping.end);
        if (selectedRanges.add(range)) {
          selected.add(mapping);
        }
        expectedStart = mapping.end;
      }
    }
    return LinuxModule(selected);
  }

  static bool _pathMatchesModule(String path, String moduleName) {
    final normalized = path.replaceAll(' (deleted)', '');
    return normalized == moduleName || normalized.endsWith('/$moduleName');
  }

  static int _compareMappings(LinuxMapping a, LinuxMapping b) =>
      a.start.compareTo(b.start);

  static int _sumLength(Iterable<LinuxMapping> mappings) =>
      mappings.fold(0, (total, mapping) => total + mapping.length);
}

/// A small seam around procfs, used by both memory and gamescope discovery.
/// Implementations must only read procfs.
abstract interface class LinuxProcFileSystem {
  Iterable<int> processIds();

  List<int> readFile(int processId, String name);

  Iterable<String> fdTargets(int processId);

  String readInputDevices();

  String memoryPath(int processId) => '/proc/$processId/mem';
}

class SystemLinuxProcFileSystem implements LinuxProcFileSystem {
  const SystemLinuxProcFileSystem({this.root = '/proc'});

  final String root;

  @override
  Iterable<int> processIds() {
    final entries = Directory(root).listSync(followLinks: false);
    return entries
        .whereType<Directory>()
        .map((entry) => int.tryParse(_basename(entry.path)))
        .whereType<int>()
        .toList(growable: false);
  }

  @override
  List<int> readFile(int processId, String name) {
    return File('$root/$processId/$name').readAsBytesSync();
  }

  @override
  Iterable<String> fdTargets(int processId) {
    final directory = Directory('$root/$processId/fd');
    final targets = <String>[];
    for (final entry in directory.listSync(followLinks: false)) {
      if (entry is Link) {
        targets.add(entry.targetSync());
      }
    }
    return List.unmodifiable(targets);
  }

  @override
  String readInputDevices() =>
      File('$root/bus/input/devices').readAsStringSync();

  @override
  String memoryPath(int processId) => '$root/$processId/mem';
}

class LinuxProcessLocator {
  const LinuxProcessLocator(this.procFileSystem);

  final LinuxProcFileSystem procFileSystem;

  int findByName(String processName) {
    final expected = _basename(processName);
    try {
      for (final processId in procFileSystem.processIds()) {
        try {
          final commandLine = _decodeProcText(
            procFileSystem.readFile(processId, 'cmdline'),
          );
          final comm = _decodeProcText(
            procFileSystem.readFile(processId, 'comm'),
          ).trim();
          if (_commandLineHasExecutable(commandLine, expected) ||
              comm == expected) {
            return processId;
          }
        } on FileSystemException {
          // Processes can disappear, or procfs can hide one process while the
          // rest of the scan remains readable.
        } on OSError {
          // Same race, expressed as an OSError by a custom procfs provider.
        }
      }
    } on FileSystemException catch (error) {
      throw LinuxNativeException(
        LinuxNativeErrorCode.processMemoryDenied,
        'Linux process information could not be read. Check /proc access for the current user.',
        cause: error,
      );
    }
    throw LinuxNativeException(
      LinuxNativeErrorCode.gameAbsent,
      '$expected is not running. Start GGST before recording.',
    );
  }

  static bool _commandLineHasExecutable(String commandLine, String expected) {
    final arguments = commandLine.split('\u0000');
    return arguments.any(
      (argument) =>
          _basename(argument) == expected || argument.contains(expected),
    );
  }
}

String _decodeProcText(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

abstract interface class LinuxMemorySession {
  int get processId;

  LinuxModule moduleFromName(String moduleName);

  List<int> readBytes(int address, int length);

  void close();
}

typedef LinuxMemorySessionFactory = LinuxMemorySession Function(
  String processName,
);

/// Native iovec layout on Linux x86_64.
final class _LinuxIOVec extends Struct {
  external Pointer<Void> base;

  @Size()
  external int length;
}

typedef _ProcessVmReadvNative = IntPtr Function(
  Int32 pid,
  Pointer<_LinuxIOVec> localIov,
  UintPtr localIovCount,
  Pointer<_LinuxIOVec> remoteIov,
  UintPtr remoteIovCount,
  UintPtr flags,
);
typedef _ProcessVmReadvDart = int Function(
  int pid,
  Pointer<_LinuxIOVec> localIov,
  int localIovCount,
  Pointer<_LinuxIOVec> remoteIov,
  int remoteIovCount,
  int flags,
);

typedef _MallocNative = Pointer<Void> Function(UintPtr size);
typedef _MallocDart = Pointer<Void> Function(int size);
typedef _FreeNative = Void Function(Pointer<Void> pointer);
typedef _FreeDart = void Function(Pointer<Void> pointer);

/// A read-only process memory session.
///
/// `process_vm_readv` is attempted first. `/proc/<pid>/mem` is opened only for
/// the read-only fallback, and no write descriptor or write API is exposed.
class LinuxProcessMemory implements LinuxMemorySession {
  LinuxProcessMemory._({
    required this.processId,
    required LinuxProcFileSystem procFileSystem,
    RandomAccessFile? memoryFile,
    _ProcessVmReadvDart? processVmReadv,
    _MallocDart? malloc,
    _FreeDart? free,
  })  : _procFileSystem = procFileSystem,
        _memoryFile = memoryFile,
        _processVmReadv = processVmReadv,
        _malloc = malloc,
        _free = free;

  factory LinuxProcessMemory(
    String processName, {
    String procRoot = '/proc',
  }) {
    return LinuxProcessMemory.open(
      processName,
      procFileSystem: SystemLinuxProcFileSystem(root: procRoot),
    );
  }

  factory LinuxProcessMemory.open(
    String processName, {
    LinuxProcFileSystem? procFileSystem,
  }) {
    final proc = procFileSystem ?? const SystemLinuxProcFileSystem();
    final processId = LinuxProcessLocator(proc).findByName(processName);
    return LinuxProcessMemory.fromPid(
      processId,
      procFileSystem: proc,
    );
  }

  factory LinuxProcessMemory.fromPid(
    int processId, {
    LinuxProcFileSystem? procFileSystem,
  }) {
    if (processId <= 0) {
      throw ArgumentError.value(processId, 'processId', 'must be positive');
    }
    final proc = procFileSystem ?? const SystemLinuxProcFileSystem();
    RandomAccessFile? memoryFile;
    try {
      memoryFile = File(proc.memoryPath(processId)).openSync(
        mode: FileMode.read,
      );
    } on OSError {
      // process_vm_readv may work even if procfs memory is restricted.
    } on FileSystemException {
      // Delay the typed permission error until the first read actually needs
      // the fallback.
    }

    _ProcessVmReadvDart? processVmReadv;
    _MallocDart? malloc;
    _FreeDart? free;
    try {
      final libc = DynamicLibrary.process();
      processVmReadv =
          libc.lookupFunction<_ProcessVmReadvNative, _ProcessVmReadvDart>(
              'process_vm_readv');
      malloc = libc.lookupFunction<_MallocNative, _MallocDart>('malloc');
      free = libc.lookupFunction<_FreeNative, _FreeDart>('free');
    } on Object {
      // A platform without the symbol can still use procfs memory.
      processVmReadv = null;
      malloc = null;
      free = null;
    }
    return LinuxProcessMemory._(
      processId: processId,
      procFileSystem: proc,
      memoryFile: memoryFile,
      processVmReadv: processVmReadv,
      malloc: malloc,
      free: free,
    );
  }

  @override
  final int processId;
  final LinuxProcFileSystem _procFileSystem;
  RandomAccessFile? _memoryFile;
  _ProcessVmReadvDart? _processVmReadv;
  final _MallocDart? _malloc;
  final _FreeDart? _free;
  bool _processVmEnabled = true;
  bool _closed = false;

  List<LinuxMapping> readMappings() {
    _ensureOpen();
    final text = utf8.decode(
      _procFileSystem.readFile(processId, 'maps'),
      allowMalformed: true,
    );
    return parseLinuxMappings(text);
  }

  @override
  LinuxModule moduleFromName(String moduleName) {
    final module = LinuxModule.fromMappings(readMappings(), moduleName);
    if (module == null) {
      throw LinuxNativeException(
        LinuxNativeErrorCode.gameModuleMissing,
        'GGST is running, but $moduleName is not mapped. The game may still be starting or its Wine process changed.',
      );
    }
    return module;
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
    if (_processVmEnabled && _processVmReadv != null && _malloc != null) {
      try {
        return _readWithProcessVm(address, length);
      } on OSError catch (error) {
        if (error.errorCode != _errnoFunctionNotImplemented &&
            error.errorCode != _errnoOperationNotPermitted &&
            error.errorCode != _errnoPermissionDenied) {
          rethrow;
        }
        // Some ptrace policies reject process_vm_readv but allow an already
        // opened procfs descriptor. Keep the fallback strictly read-only.
        _processVmEnabled = false;
      }
    }
    return _readWithProcfs(address, length);
  }

  List<int> _readWithProcessVm(int address, int length) {
    final processVmReadv = _processVmReadv;
    final malloc = _malloc;
    final free = _free;
    if (processVmReadv == null || malloc == null || free == null) {
      throw const OSError(
        'process_vm_readv is unavailable',
        _errnoFunctionNotImplemented,
      );
    }

    final localBuffer = malloc(length).cast<Uint8>();
    final localIov = malloc(sizeOf<_LinuxIOVec>()).cast<_LinuxIOVec>();
    final remoteIov = malloc(sizeOf<_LinuxIOVec>()).cast<_LinuxIOVec>();
    if (localBuffer.address == 0 ||
        localIov.address == 0 ||
        remoteIov.address == 0) {
      if (localBuffer.address != 0) {
        free(localBuffer.cast<Void>());
      }
      if (localIov.address != 0) {
        free(localIov.cast<Void>());
      }
      if (remoteIov.address != 0) {
        free(remoteIov.cast<Void>());
      }
      throw const OSError('Could not allocate process memory read buffers.');
    }

    localIov.ref
      ..base = localBuffer.cast<Void>()
      ..length = length;
    remoteIov.ref
      ..base = Pointer<Void>.fromAddress(address)
      ..length = length;

    try {
      final result = processVmReadv(
        processId,
        localIov,
        1,
        remoteIov,
        1,
        0,
      );
      if (result < 0) {
        final errorCode = _lastErrno();
        throw OSError(
          'process_vm_readv failed: ${_errnoDescription(errorCode)}',
          errorCode,
        );
      }
      if (result != length) {
        throw OSError(
          'Short process_vm_readv read: $result of $length bytes.',
          _errnoInputOutput,
        );
      }
      return List<int>.from(localBuffer.asTypedList(length));
    } finally {
      free(localBuffer.cast<Void>());
      free(localIov.cast<Void>());
      free(remoteIov.cast<Void>());
    }
  }

  List<int> _readWithProcfs(int address, int length) {
    final memoryFile = _memoryFile;
    if (memoryFile == null) {
      throw OSError(
        'Cannot read /proc/$processId/mem. Process memory access was denied.',
        _errnoPermissionDenied,
      );
    }
    try {
      memoryFile.setPositionSync(address);
      final bytes = memoryFile.readSync(length);
      if (bytes.length != length) {
        throw OSError(
          'Short /proc/$processId/mem read: ${bytes.length} of $length bytes.',
          _errnoInputOutput,
        );
      }
      return bytes;
    } on OSError {
      rethrow;
    } on FileSystemException catch (error) {
      throw OSError(error.message, error.osError?.errorCode ?? 0);
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    final memoryFile = _memoryFile;
    _memoryFile = null;
    if (memoryFile != null) {
      try {
        memoryFile.closeSync();
      } on Object {
        // Closing is best effort and idempotent. It must not resurrect a
        // session or mask a primary monitor error.
      }
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.closed,
        'The Linux process-memory session is closed.',
      );
    }
  }

  int _lastErrno() {
    // errno is exposed by the FFI call itself only through `NativeApi` on
    // newer SDKs. Reading it through libc keeps this adapter compatible with
    // the pinned Dart SDK and is only used after a failed syscall.
    try {
      final libc = DynamicLibrary.process();
      final location = libc.lookupFunction<Pointer<Int32> Function(),
          Pointer<Int32> Function()>('__errno_location');
      return location().value;
    } on Object {
      return _errnoOperationNotPermitted;
    }
  }

  String _errnoDescription(int code) {
    return switch (code) {
      _errnoOperationNotPermitted => 'operation not permitted',
      _errnoPermissionDenied => 'permission denied',
      _errnoNoSuchProcess => 'the process exited',
      _errnoFunctionNotImplemented => 'not implemented',
      _ => 'errno $code',
    };
  }
}

class LinuxBytePattern {
  LinuxBytePattern({
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

  const LinuxBytePattern._const(this.bytes, this.mask);

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

const LinuxBytePattern ggstGWorldPattern = LinuxBytePattern._const(
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

int resolveRipRelativeAddress(int instructionAddress, int displacement) =>
    instructionAddress + 12 + displacement;

int decodeSignedInt32(List<int> bytes) {
  if (bytes.length < 4) {
    throw ArgumentError.value(bytes, 'bytes', 'must contain four bytes');
  }
  final unsigned =
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  return unsigned >= 0x80000000 ? unsigned - 0x100000000 : unsigned;
}

class LinuxPatternScanResult {
  const LinuxPatternScanResult({
    required this.address,
    required this.readableMappings,
    required this.inaccessibleReads,
    required this.permissionDeniedReads,
  });

  final int? address;
  final int readableMappings;
  final int inaccessibleReads;
  final int permissionDeniedReads;

  bool get found => address != null;
}

class LinuxPatternScanner {
  const LinuxPatternScanner({
    this.chunkSize = 8 * 1024 * 1024,
  });

  final int chunkSize;

  LinuxPatternScanResult scan({
    required LinuxModule module,
    required LinuxBytePattern pattern,
    required List<int> Function(int address, int length) read,
  }) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
    var readableMappings = 0;
    var inaccessibleReads = 0;
    var permissionDeniedReads = 0;
    final overlap = pattern.length - 1;

    for (final mapping in module.mappings) {
      if (!mapping.readable || mapping.length < pattern.length) {
        continue;
      }
      readableMappings++;
      for (var offset = 0; offset < mapping.length; offset += chunkSize) {
        final readOffset = math.max(0, offset - overlap);
        final readLength = math.min(
          chunkSize + overlap,
          mapping.length - readOffset,
        );
        late final List<int> bytes;
        try {
          bytes = read(mapping.start + readOffset, readLength);
        } on Object catch (error) {
          inaccessibleReads++;
          if (error is OSError &&
              (error.errorCode == _errnoOperationNotPermitted ||
                  error.errorCode == _errnoPermissionDenied)) {
            permissionDeniedReads++;
          }
          continue;
        }
        final hit = pattern.find(bytes);
        if (hit != null) {
          return LinuxPatternScanResult(
            address: mapping.start + readOffset + hit,
            readableMappings: readableMappings,
            inaccessibleReads: inaccessibleReads,
            permissionDeniedReads: permissionDeniedReads,
          );
        }
      }
    }
    return LinuxPatternScanResult(
      address: null,
      readableMappings: readableMappings,
      inaccessibleReads: inaccessibleReads,
      permissionDeniedReads: permissionDeniedReads,
    );
  }
}
