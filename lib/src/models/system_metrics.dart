import 'cpu_metrics.dart';
import 'gpu_metrics.dart';
import 'memory_metrics.dart';
import 'process_metrics.dart';

/// Complete hardware consumption snapshot combining global [CpuMetrics],
/// [MemoryMetrics], [GpuMetrics], and the current process's [ProcessMetrics]
/// at a given point in time.
class SystemMetrics {
  const SystemMetrics({
    required this.cpu,
    required this.memory,
    required this.gpu,
    required this.currentProcess,
    required this.timestampMs,
  });

  factory SystemMetrics.fromJson(Map<String, dynamic> json) {
    return SystemMetrics(
      cpu: CpuMetrics.fromJson(
        (json['cpu'] as Map<String, dynamic>?) ?? const {},
      ),
      memory: MemoryMetrics.fromJson(
        (json['memory'] as Map<String, dynamic>?) ?? const {},
      ),
      gpu: GpuMetrics.fromJson(
        (json['gpu'] as Map<String, dynamic>?) ?? const {},
      ),
      currentProcess: ProcessMetrics.fromJson(
        (json['current_process'] as Map<String, dynamic>?) ?? const {},
      ),
      timestampMs: (json['timestamp_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Global CPU consumption metrics (global %, per-core %, frequency, core counts).
  final CpuMetrics cpu;

  /// Global RAM & Swap consumption metrics (used/total bytes, GB, MB, and %).
  final MemoryMetrics memory;

  /// Global GPU consumption metrics (core load %, used/total VRAM bytes, GB, MB, %, temperature).
  final GpuMetrics gpu;

  /// CPU, RAM, and GPU consumption metrics for the current running process.
  final ProcessMetrics currentProcess;

  /// Unix epoch timestamp in milliseconds when this snapshot was captured.
  final int timestampMs;

  /// [DateTime] representation of [timestampMs].
  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  Map<String, dynamic> toJson() => {
        'cpu': cpu.toJson(),
        'memory': memory.toJson(),
        'gpu': gpu.toJson(),
        'current_process': currentProcess.toJson(),
        'timestamp_ms': timestampMs,
      };

  @override
  String toString() =>
      'SystemMetrics(at: ${timestamp.toIso8601String()}, cpu: $cpu, memory: $memory, '
      'gpu: $gpu, currentProcess: $currentProcess)';
}
