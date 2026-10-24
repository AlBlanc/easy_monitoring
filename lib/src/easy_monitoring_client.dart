import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'ffi/native_bindings.dart';
import 'models/cpu_metrics.dart';
import 'models/gpu_metrics.dart';
import 'models/memory_metrics.dart';
import 'models/process_metrics.dart';
import 'models/system_metrics.dart';

/// Main entry point for real-time CPU, RAM, and GPU hardware monitoring
/// (both system-wide and for the current process) powered by Rust
/// (`sysinfo` & `gfxinfo`).
///
/// All native FFI polling is executed inside a dedicated background [Isolate]
/// so the Flutter UI thread remains completely jank-free.
class EasyMonitoring {
  EasyMonitoring({
    this.defaultInterval = const Duration(seconds: 1),
  });

  /// Shared singleton instance of [EasyMonitoring].
  static final EasyMonitoring instance = EasyMonitoring();

  /// Default polling interval used when none is passed to stream methods.
  final Duration defaultInterval;

  final Map<int, _IntervalStreamWorker> _workersByIntervalMs = {};
  bool _isDisposed = false;

  /// Broadcast stream of complete [SystemMetrics] (system CPU, Memory, GPU,
  /// and current process consumption) emitted every [interval]
  /// (defaults to [defaultInterval], 1 second).
  ///
  /// The underlying Rust engine only polls when at least one listener is
  /// subscribed to the stream.
  Stream<SystemMetrics> metricsStream({Duration? interval}) {
    _ensureNotDisposed();
    final effectiveInterval = interval ?? defaultInterval;
    final ms = effectiveInterval.inMilliseconds.clamp(100, 3600000);
    final worker = _workersByIntervalMs.putIfAbsent(
      ms,
      () => _IntervalStreamWorker(Duration(milliseconds: ms)),
    );
    return worker.stream;
  }

  /// Convenience broadcast stream emitting system-wide [CpuMetrics]
  /// (global %, per-core %, frequencies, core counts) every [interval].
  Stream<CpuMetrics> cpuStream({Duration? interval}) {
    return metricsStream(interval: interval).map((snapshot) => snapshot.cpu);
  }

  /// Convenience broadcast stream emitting system-wide [MemoryMetrics]
  /// (used/total RAM and Swap in bytes, MB, GB, and %) every [interval].
  Stream<MemoryMetrics> memoryStream({Duration? interval}) {
    return metricsStream(interval: interval).map((snapshot) => snapshot.memory);
  }

  /// Convenience broadcast stream emitting system-wide [GpuMetrics]
  /// (GPU load %, used/total VRAM in bytes, MB, GB, %, and temperature)
  /// every [interval].
  Stream<GpuMetrics> gpuStream({Duration? interval}) {
    return metricsStream(interval: interval).map((snapshot) => snapshot.gpu);
  }

  /// Convenience broadcast stream emitting [ProcessMetrics] (CPU %, RAM used/%,
  /// and GPU load % / VRAM used) for the **current running process** every [interval].
  Stream<ProcessMetrics> currentProcessStream({Duration? interval}) {
    return metricsStream(interval: interval)
        .map((snapshot) => snapshot.currentProcess);
  }

  /// Alias for [currentProcessStream].
  Stream<ProcessMetrics> processStream({Duration? interval}) =>
      currentProcessStream(interval: interval);

  /// Fetches a single [SystemMetrics] snapshot asynchronously on a background isolate.
  Future<SystemMetrics> getSystemMetrics() {
    _ensureNotDisposed();
    return Isolate.run(() {
      final bindings = EasyMonitoringBindings();
      final engine = bindings.createEngine();
      try {
        return bindings.pollMetrics(engine);
      } finally {
        bindings.destroyEngine(engine);
      }
    });
  }

  /// Fetches a single system-wide [CpuMetrics] snapshot asynchronously.
  Future<CpuMetrics> getCpuMetrics() async => (await getSystemMetrics()).cpu;

  /// Fetches a single system-wide [MemoryMetrics] snapshot asynchronously.
  Future<MemoryMetrics> getMemoryMetrics() async =>
      (await getSystemMetrics()).memory;

  /// Fetches a single system-wide [GpuMetrics] snapshot asynchronously.
  Future<GpuMetrics> getGpuMetrics() async => (await getSystemMetrics()).gpu;

  /// Fetches a single [ProcessMetrics] snapshot (CPU, RAM, GPU) for the
  /// current running process (or a specific [pid] if provided) asynchronously.
  Future<ProcessMetrics> getCurrentProcessMetrics({int? pid}) {
    _ensureNotDisposed();
    final targetPid = pid ?? 0;
    return Isolate.run(() {
      final bindings = EasyMonitoringBindings();
      final engine = bindings.createEngine();
      try {
        return bindings.pollProcessMetrics(engine, pid: targetPid);
      } finally {
        bindings.destroyEngine(engine);
      }
    });
  }

  /// Alias for [getCurrentProcessMetrics].
  Future<ProcessMetrics> getProcessMetrics({int? pid}) =>
      getCurrentProcessMetrics(pid: pid);

  /// Returns the version string of the loaded native Rust library.
  String get nativeVersion {
    _ensureNotDisposed();
    return EasyMonitoringBindings().getVersion();
  }

  /// Stops all active background isolates and closes all streams managed by
  /// this [EasyMonitoring] instance.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    final workers = _workersByIntervalMs.values.toList(growable: false);
    _workersByIntervalMs.clear();
    for (final worker in workers) {
      await worker.dispose();
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('EasyMonitoring instance has been disposed.');
    }
  }
}

/// Manages a dedicated background [Isolate] that holds a stateful Rust
/// `EasyMonitoringEngine` and streams snapshots at a given [interval].
class _IntervalStreamWorker {
  _IntervalStreamWorker(this.interval) {
    _controller = StreamController<SystemMetrics>.broadcast(
      onListen: _startWorkerIsolate,
      onCancel: _stopWorkerIsolate,
    );
  }

  final Duration interval;
  late final StreamController<SystemMetrics> _controller;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _workerStopPort;
  bool _starting = false;

  Stream<SystemMetrics> get stream => _controller.stream;

  Future<void> _startWorkerIsolate() async {
    if (_isolate != null || _starting) return;
    _starting = true;

    final receivePort = ReceivePort();
    _receivePort = receivePort;

    receivePort.listen((message) {
      if (message is SendPort) {
        _workerStopPort = message;
      } else if (message is Map<String, dynamic>) {
        if (!_controller.isClosed && _controller.hasListener) {
          _controller.add(SystemMetrics.fromJson(message));
        }
      } else if (message is List && message.length == 2 && message[0] == 'err') {
        if (!_controller.isClosed && _controller.hasListener) {
          _controller.addError(StateError(message[1].toString()));
        }
      }
    });

    try {
      _isolate = await Isolate.spawn<_WorkerInitMessage>(
        _isolateEntry,
        _WorkerInitMessage(
          sendPort: receivePort.sendPort,
          intervalMs: interval.inMilliseconds,
        ),
        debugName: 'EasyMonitoringWorker(${interval.inMilliseconds}ms)',
      );
    } catch (e, st) {
      _starting = false;
      receivePort.close();
      _receivePort = null;
      if (!_controller.isClosed) {
        _controller.addError(e, st);
      }
      return;
    }

    _starting = false;
    if (!_controller.hasListener) {
      await _stopWorkerIsolate();
    }
  }

  Future<void> _stopWorkerIsolate() async {
    _workerStopPort?.send('stop');
    _workerStopPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _starting = false;
  }

  Future<void> dispose() async {
    await _stopWorkerIsolate();
    await _controller.close();
  }

  static void _isolateEntry(_WorkerInitMessage init) {
    final stopPort = ReceivePort();
    init.sendPort.send(stopPort.sendPort);

    EasyMonitoringBindings? bindings;
    ffi.Pointer<NativeEasyMonitoringEngine> engine = ffi.nullptr;
    Timer? timer;

    void cleanup() {
      timer?.cancel();
      timer = null;
      if (bindings != null && engine != ffi.nullptr) {
        bindings.destroyEngine(engine);
        engine = ffi.nullptr;
      }
      stopPort.close();
    }

    try {
      bindings = EasyMonitoringBindings();
      engine = bindings.createEngine();

      void emitSample() {
        if (engine == ffi.nullptr || bindings == null) return;
        try {
          final snapshot = bindings.pollMetrics(engine);
          init.sendPort.send(snapshot.toJson());
        } catch (e) {
          init.sendPort.send(['err', e.toString()]);
        }
      }

      // Emit the first sample immediately so listeners don't wait a full tick.
      emitSample();

      timer = Timer.periodic(
        Duration(milliseconds: init.intervalMs),
        (_) => emitSample(),
      );
    } catch (e) {
      init.sendPort.send(['err', e.toString()]);
      cleanup();
      return;
    }

    stopPort.listen((message) {
      if (message == 'stop') {
        cleanup();
        Isolate.current.kill();
      }
    });
  }
}

class _WorkerInitMessage {
  const _WorkerInitMessage({
    required this.sendPort,
    required this.intervalMs,
  });

  final SendPort sendPort;
  final int intervalMs;
}
