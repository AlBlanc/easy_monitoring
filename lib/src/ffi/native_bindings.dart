import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../models/process_metrics.dart';
import '../models/system_metrics.dart';

/// Opaque native struct pointer representing `EasyMonitoringEngine` in Rust.
final class NativeEasyMonitoringEngine extends ffi.Opaque {}

typedef _CreateNative = ffi.Pointer<NativeEasyMonitoringEngine> Function();
typedef _CreateDart = ffi.Pointer<NativeEasyMonitoringEngine> Function();

typedef _DestroyNative = ffi.Void Function(
  ffi.Pointer<NativeEasyMonitoringEngine> handle,
);
typedef _DestroyDart = void Function(
  ffi.Pointer<NativeEasyMonitoringEngine> handle,
);

typedef _PollJsonNative = ffi.Pointer<Utf8> Function(
  ffi.Pointer<NativeEasyMonitoringEngine> handle,
);
typedef _PollJsonDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<NativeEasyMonitoringEngine> handle,
);

typedef _PollProcessJsonNative = ffi.Pointer<Utf8> Function(
  ffi.Pointer<NativeEasyMonitoringEngine> handle,
  ffi.Uint32 pid,
);
typedef _PollProcessJsonDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<NativeEasyMonitoringEngine> handle,
  int pid,
);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8> ptr);

typedef _VersionNative = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

/// Low-level `dart:ffi` bindings to the native Rust `easy_monitoring` library.
class EasyMonitoringBindings {
  EasyMonitoringBindings({ffi.DynamicLibrary? library})
      : _lib = library ?? _openDynamicLibrary() {
    _create = _lib
        .lookup<ffi.NativeFunction<_CreateNative>>('easy_monitoring_create')
        .asFunction<_CreateDart>();
    _destroy = _lib
        .lookup<ffi.NativeFunction<_DestroyNative>>('easy_monitoring_destroy')
        .asFunction<_DestroyDart>();
    _pollJson = _lib
        .lookup<ffi.NativeFunction<_PollJsonNative>>(
          'easy_monitoring_poll_json',
        )
        .asFunction<_PollJsonDart>();
    _pollProcessJson = _lib
        .lookup<ffi.NativeFunction<_PollProcessJsonNative>>(
          'easy_monitoring_poll_process_json',
        )
        .asFunction<_PollProcessJsonDart>();
    _freeString = _lib
        .lookup<ffi.NativeFunction<_FreeStringNative>>(
          'easy_monitoring_free_string',
        )
        .asFunction<_FreeStringDart>();
    _version = _lib
        .lookup<ffi.NativeFunction<_VersionNative>>('easy_monitoring_version')
        .asFunction<_VersionDart>();
  }

  final ffi.DynamicLibrary _lib;
  late final _CreateDart _create;
  late final _DestroyDart _destroy;
  late final _PollJsonDart _pollJson;
  late final _PollProcessJsonDart _pollProcessJson;
  late final _FreeStringDart _freeString;
  late final _VersionDart _version;

  /// Creates a new stateful native `EasyMonitoringEngine` instance.
  ffi.Pointer<NativeEasyMonitoringEngine> createEngine() => _create();

  /// Destroys a native `EasyMonitoringEngine` instance.
  void destroyEngine(ffi.Pointer<NativeEasyMonitoringEngine> handle) {
    if (handle != ffi.nullptr) {
      _destroy(handle);
    }
  }

  /// Polls a [SystemMetrics] snapshot from the native `EasyMonitoringEngine`.
  SystemMetrics pollMetrics(ffi.Pointer<NativeEasyMonitoringEngine> handle) {
    final jsonPtr = _pollJson(handle);
    if (jsonPtr == ffi.nullptr) {
      throw StateError(
        'Native easy_monitoring_poll_json returned a null pointer.',
      );
    }
    try {
      final jsonStr = jsonPtr.toDartString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SystemMetrics.fromJson(decoded);
    } finally {
      _freeString(jsonPtr);
    }
  }

  /// Polls a [ProcessMetrics] snapshot for [pid] (or `0` for the current process).
  ProcessMetrics pollProcessMetrics(
    ffi.Pointer<NativeEasyMonitoringEngine> handle, {
    int pid = 0,
  }) {
    final jsonPtr = _pollProcessJson(handle, pid);
    if (jsonPtr == ffi.nullptr) {
      throw StateError(
        'Native easy_monitoring_poll_process_json returned a null pointer.',
      );
    }
    try {
      final jsonStr = jsonPtr.toDartString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ProcessMetrics.fromJson(decoded);
    } finally {
      _freeString(jsonPtr);
    }
  }

  /// Returns the semantic version of the loaded Rust library.
  String getVersion() {
    final ptr = _version();
    if (ptr == ffi.nullptr) {
      return 'unknown';
    }
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  static String get _libraryFileName {
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libeasy_monitoring.dylib';
    } else if (Platform.isLinux || Platform.isAndroid) {
      return 'libeasy_monitoring.so';
    } else if (Platform.isWindows) {
      return 'easy_monitoring.dll';
    }
    throw UnsupportedError(
      'easy_monitoring only supports Windows, macOS, Linux, Android, and iOS '
      '(current platform: ${Platform.operatingSystem}).',
    );
  }

  static String get _platformSubdir {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  static ffi.DynamicLibrary _openDynamicLibrary() {
    if (Platform.isIOS) {
      try {
        final procLib = ffi.DynamicLibrary.process();
        procLib.lookup('easy_monitoring_create');
        return procLib;
      } catch (_) {
        try {
          return ffi.DynamicLibrary.executable();
        } catch (_) {}
      }
    }

    final libName = _libraryFileName;
    final platformDir = _platformSubdir;

    final envOverride = Platform.environment['EASY_MONITORING_LIB_PATH'];
    final candidatePaths = <String>[
      if (envOverride != null && envOverride.isNotEmpty) envOverride,
      libName,
      if (Platform.isMacOS) ...[
        '@executable_path/../Frameworks/$libName',
        '@executable_path/../Resources/easy_monitoring_easy_monitoring.bundle/Contents/Resources/$libName',
        '@executable_path/../Resources/easy_monitoring_easy_monitoring.bundle/$libName',
        '@executable_path/easy_monitoring_easy_monitoring.bundle/Contents/Resources/$libName',
        '@executable_path/../Resources/$libName',
      ],
      'prebuilt/$platformDir/$libName',
      '../prebuilt/$platformDir/$libName',
      'rust/target/release/$libName',
      '../rust/target/release/$libName',
      'rust/target/debug/$libName',
      '../rust/target/debug/$libName',
    ];

    Object? lastError;
    for (final path in candidatePaths) {
      try {
        if (path == libName || path.startsWith('@executable_path')) {
          return ffi.DynamicLibrary.open(path);
        }
        if (File(path).existsSync()) {
          return ffi.DynamicLibrary.open(File(path).absolute.path);
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw StateError(
      'Failed to load native library "$libName" for ${Platform.operatingSystem}. '
      'Ensure prebuilt binaries exist in prebuilt/$platformDir/$libName or '
      'Rust is compiled. Last error: $lastError',
    );
  }
}
