import '../utils/byte_formatter.dart';

/// Physical RAM and Swap consumption metrics collected via `sysinfo`.
///
/// Provides both relative percentages (`usagePercent`, `swapUsagePercent`) and
/// absolute byte/MB/GB values (`usedMemoryBytes`, `totalMemoryBytes`, etc.).
class MemoryMetrics {
  const MemoryMetrics({
    required this.totalMemoryBytes,
    required this.usedMemoryBytes,
    required this.freeMemoryBytes,
    required this.availableMemoryBytes,
    required this.usagePercent,
    required this.totalSwapBytes,
    required this.usedSwapBytes,
    required this.freeSwapBytes,
    required this.swapUsagePercent,
  });

  factory MemoryMetrics.fromJson(Map<String, dynamic> json) {
    return MemoryMetrics(
      totalMemoryBytes: (json['total_memory_bytes'] as num?)?.toInt() ?? 0,
      usedMemoryBytes: (json['used_memory_bytes'] as num?)?.toInt() ?? 0,
      freeMemoryBytes: (json['free_memory_bytes'] as num?)?.toInt() ?? 0,
      availableMemoryBytes:
          (json['available_memory_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      totalSwapBytes: (json['total_swap_bytes'] as num?)?.toInt() ?? 0,
      usedSwapBytes: (json['used_swap_bytes'] as num?)?.toInt() ?? 0,
      freeSwapBytes: (json['free_swap_bytes'] as num?)?.toInt() ?? 0,
      swapUsagePercent: (json['swap_usage_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Total physical RAM in bytes (absolute value).
  final int totalMemoryBytes;

  /// Used physical RAM in bytes (absolute value).
  final int usedMemoryBytes;

  /// Free physical RAM in bytes (absolute value).
  final int freeMemoryBytes;

  /// Available physical RAM in bytes (absolute value).
  final int availableMemoryBytes;

  /// Physical RAM consumption percentage in `[0.0, 100.0]`.
  final double usagePercent;

  /// Total swap space in bytes (absolute value).
  final int totalSwapBytes;

  /// Used swap space in bytes (absolute value).
  final int usedSwapBytes;

  /// Free swap space in bytes (absolute value).
  final int freeSwapBytes;

  /// Swap consumption percentage in `[0.0, 100.0]`.
  final double swapUsagePercent;

  /// Total physical RAM in GiB.
  double get totalMemoryGb => ByteFormatter.toGigabytes(totalMemoryBytes);

  /// Used physical RAM in GiB.
  double get usedMemoryGb => ByteFormatter.toGigabytes(usedMemoryBytes);

  /// Available physical RAM in GiB.
  double get availableMemoryGb =>
      ByteFormatter.toGigabytes(availableMemoryBytes);

  /// Free physical RAM in GiB.
  double get freeMemoryGb => ByteFormatter.toGigabytes(freeMemoryBytes);

  /// Total physical RAM in MiB.
  double get totalMemoryMb => ByteFormatter.toMegabytes(totalMemoryBytes);

  /// Used physical RAM in MiB.
  double get usedMemoryMb => ByteFormatter.toMegabytes(usedMemoryBytes);

  /// Total swap in GiB.
  double get totalSwapGb => ByteFormatter.toGigabytes(totalSwapBytes);

  /// Used swap in GiB.
  double get usedSwapGb => ByteFormatter.toGigabytes(usedSwapBytes);

  /// Formatted `used / total` RAM string (e.g. `14.20 GB / 32.00 GB`).
  String get formattedUsage =>
      ByteFormatter.formatRatio(usedMemoryBytes, totalMemoryBytes);

  /// Formatted `used / total` Swap string (e.g. `1.10 GB / 8.00 GB`).
  String get formattedSwapUsage =>
      ByteFormatter.formatRatio(usedSwapBytes, totalSwapBytes);

  Map<String, dynamic> toJson() => {
        'total_memory_bytes': totalMemoryBytes,
        'used_memory_bytes': usedMemoryBytes,
        'free_memory_bytes': freeMemoryBytes,
        'available_memory_bytes': availableMemoryBytes,
        'usage_percent': usagePercent,
        'total_swap_bytes': totalSwapBytes,
        'used_swap_bytes': usedSwapBytes,
        'free_swap_bytes': freeSwapBytes,
        'swap_usage_percent': swapUsagePercent,
      };

  @override
  String toString() =>
      'MemoryMetrics(RAM: ${usagePercent.toStringAsFixed(1)}% [$formattedUsage], '
      'Swap: ${swapUsagePercent.toStringAsFixed(1)}% [$formattedSwapUsage])';
}
