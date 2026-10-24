import '../utils/byte_formatter.dart';

/// Real-time CPU, RAM, and GPU consumption metrics for a specific process
/// (by default the current running process).
class ProcessMetrics {
  const ProcessMetrics({
    required this.pid,
    required this.name,
    required this.status,
    required this.runTimeSeconds,
    required this.cpuUsagePercent,
    required this.rawCpuUsagePercent,
    required this.memoryBytes,
    required this.virtualMemoryBytes,
    required this.totalSystemMemoryBytes,
    required this.memoryUsagePercent,
    required this.gpuUsagePercent,
    required this.gpuUsedVramBytes,
    required this.gpuTotalVramBytes,
    required this.gpuVramUsagePercent,
  });

  factory ProcessMetrics.fromJson(Map<String, dynamic> json) {
    return ProcessMetrics(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? 'Unknown Process',
      status: (json['status'] as String?) ?? 'Unknown',
      runTimeSeconds: (json['run_time_seconds'] as num?)?.toInt() ?? 0,
      cpuUsagePercent: (json['cpu_usage_percent'] as num?)?.toDouble() ?? 0.0,
      rawCpuUsagePercent:
          (json['raw_cpu_usage_percent'] as num?)?.toDouble() ?? 0.0,
      memoryBytes: (json['memory_bytes'] as num?)?.toInt() ?? 0,
      virtualMemoryBytes: (json['virtual_memory_bytes'] as num?)?.toInt() ?? 0,
      totalSystemMemoryBytes:
          (json['total_system_memory_bytes'] as num?)?.toInt() ?? 0,
      memoryUsagePercent:
          (json['memory_usage_percent'] as num?)?.toDouble() ?? 0.0,
      gpuUsagePercent: (json['gpu_usage_percent'] as num?)?.toDouble() ?? 0.0,
      gpuUsedVramBytes: (json['gpu_used_vram_bytes'] as num?)?.toInt() ?? 0,
      gpuTotalVramBytes: (json['gpu_total_vram_bytes'] as num?)?.toInt() ?? 0,
      gpuVramUsagePercent:
          (json['gpu_vram_usage_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Operating system Process ID (PID).
  final int pid;

  /// Process executable / task name.
  final String name;

  /// OS process status (e.g., `Run`, `Runnable`, `Sleep`).
  final String status;

  /// Process uptime in seconds.
  final int runTimeSeconds;

  /// Normalized CPU consumption of this process across all logical cores
  /// in `[0.0, 100.0]` (%).
  final double cpuUsagePercent;

  /// Raw `sysinfo` CPU consumption where `100.0%` corresponds to 1 full logical core
  /// (can reach `100.0 * logicalCores` %, matching `top` / Activity Monitor).
  final double rawCpuUsagePercent;

  /// Physical RAM (Resident Set Size / RSS) used by this process in bytes (absolute value).
  final int memoryBytes;

  /// Virtual memory allocated by this process in bytes (absolute value).
  final int virtualMemoryBytes;

  /// Total physical system RAM in bytes (absolute value).
  final int totalSystemMemoryBytes;

  /// Percentage of total physical system RAM used by this process in `[0.0, 100.0]` (%).
  final double memoryUsagePercent;

  /// GPU core utilization percentage attributed to this process in `[0.0, 100.0]` (%).
  final double gpuUsagePercent;

  /// GPU VRAM used by this process in bytes (absolute value).
  final int gpuUsedVramBytes;

  /// Total GPU VRAM in bytes (absolute value).
  final int gpuTotalVramBytes;

  /// Percentage of total GPU VRAM used by this process in `[0.0, 100.0]` (%).
  final double gpuVramUsagePercent;

  /// Process uptime as a [Duration].
  Duration get runTime => Duration(seconds: runTimeSeconds);

  /// Physical RAM used by this process in MiB.
  double get memoryMb => ByteFormatter.toMegabytes(memoryBytes);

  /// Physical RAM used by this process in GiB.
  double get memoryGb => ByteFormatter.toGigabytes(memoryBytes);

  /// Virtual memory used by this process in MiB.
  double get virtualMemoryMb => ByteFormatter.toMegabytes(virtualMemoryBytes);

  /// Virtual memory used by this process in GiB.
  double get virtualMemoryGb => ByteFormatter.toGigabytes(virtualMemoryBytes);

  /// Formatted physical RAM used by this process (e.g. `142.50 MB`).
  String get formattedMemory => ByteFormatter.format(memoryBytes);

  /// Formatted `process RAM / total system RAM` ratio string (e.g. `0.14 GB / 32.00 GB`).
  String get formattedMemoryUsage =>
      '${ByteFormatter.format(memoryBytes)} / ${ByteFormatter.format(totalSystemMemoryBytes)}';

  /// GPU VRAM used by this process in MiB.
  double get gpuUsedVramMb => ByteFormatter.toMegabytes(gpuUsedVramBytes);

  /// GPU VRAM used by this process in GiB.
  double get gpuUsedVramGb => ByteFormatter.toGigabytes(gpuUsedVramBytes);

  /// Formatted GPU VRAM used by this process (e.g. `64.00 MB`).
  String get formattedGpuVram => ByteFormatter.format(gpuUsedVramBytes);

  /// Formatted `process VRAM / total GPU VRAM` ratio string.
  String get formattedGpuVramUsage =>
      '${ByteFormatter.format(gpuUsedVramBytes)} / ${ByteFormatter.format(gpuTotalVramBytes)}';

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'name': name,
        'status': status,
        'run_time_seconds': runTimeSeconds,
        'cpu_usage_percent': cpuUsagePercent,
        'raw_cpu_usage_percent': rawCpuUsagePercent,
        'memory_bytes': memoryBytes,
        'virtual_memory_bytes': virtualMemoryBytes,
        'total_system_memory_bytes': totalSystemMemoryBytes,
        'memory_usage_percent': memoryUsagePercent,
        'gpu_usage_percent': gpuUsagePercent,
        'gpu_used_vram_bytes': gpuUsedVramBytes,
        'gpu_total_vram_bytes': gpuTotalVramBytes,
        'gpu_vram_usage_percent': gpuVramUsagePercent,
      };

  @override
  String toString() =>
      'ProcessMetrics(PID $pid "$name": CPU ${cpuUsagePercent.toStringAsFixed(2)}% '
      '[raw ${rawCpuUsagePercent.toStringAsFixed(1)}%], '
      'RAM ${memoryUsagePercent.toStringAsFixed(2)}% [$formattedMemoryUsage], '
      'GPU ${gpuUsagePercent.toStringAsFixed(1)}% [VRAM $formattedGpuVramUsage])';
}
