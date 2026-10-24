/// Real-time metrics for a single logical CPU core collected via `sysinfo`.
class CpuCoreMetrics {
  const CpuCoreMetrics({
    required this.index,
    required this.name,
    required this.usagePercent,
    required this.frequencyMhz,
  });

  factory CpuCoreMetrics.fromJson(Map<String, dynamic> json) {
    return CpuCoreMetrics(
      index: (json['index'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      frequencyMhz: (json['frequency_mhz'] as num?)?.toInt() ?? 0,
    );
  }

  /// Zero-based index of the logical core.
  final int index;

  /// OS-reported core identifier/name.
  final String name;

  /// Core utilization percentage in the range `[0.0, 100.0]`.
  final double usagePercent;

  /// Core clock frequency in MHz (absolute value).
  final int frequencyMhz;

  /// Core clock frequency in GHz (absolute value).
  double get frequencyGhz => frequencyMhz / 1000.0;

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'usage_percent': usagePercent,
        'frequency_mhz': frequencyMhz,
      };

  @override
  String toString() =>
      'CpuCoreMetrics(#$index "$name": ${usagePercent.toStringAsFixed(1)}% @ $frequencyMhz MHz)';
}

/// Aggregate and per-core CPU consumption metrics collected via `sysinfo`.
class CpuMetrics {
  const CpuMetrics({
    required this.usagePercent,
    required this.brand,
    required this.vendorId,
    required this.physicalCores,
    required this.logicalCores,
    required this.averageFrequencyMhz,
    required this.maxFrequencyMhz,
    required this.cores,
  });

  factory CpuMetrics.fromJson(Map<String, dynamic> json) {
    final rawCores = (json['cores'] as List<dynamic>?) ?? const [];
    return CpuMetrics(
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      brand: (json['brand'] as String?) ?? 'Unknown CPU',
      vendorId: (json['vendor_id'] as String?) ?? 'Unknown',
      physicalCores: (json['physical_cores'] as num?)?.toInt() ?? 0,
      logicalCores: (json['logical_cores'] as num?)?.toInt() ?? 0,
      averageFrequencyMhz:
          (json['average_frequency_mhz'] as num?)?.toInt() ?? 0,
      maxFrequencyMhz: (json['max_frequency_mhz'] as num?)?.toInt() ?? 0,
      cores: rawCores
          .whereType<Map<String, dynamic>>()
          .map(CpuCoreMetrics.fromJson)
          .toList(growable: false),
    );
  }

  /// Global CPU usage across all cores in `[0.0, 100.0]` (%).
  final double usagePercent;

  /// CPU model / brand name (e.g., `Apple M5 Ultra`, `AMD Ryzen 9 7950X`).
  final String brand;

  /// CPU vendor identifier (e.g., `Apple`, `AuthenticAMD`, `GenuineIntel`).
  final String vendorId;

  /// Total number of physical CPU cores (absolute count).
  final int physicalCores;

  /// Total number of logical CPU cores / hardware threads (absolute count).
  final int logicalCores;

  /// Average clock frequency across cores in MHz (absolute value).
  final int averageFrequencyMhz;

  /// Peak clock frequency across cores in MHz (absolute value).
  final int maxFrequencyMhz;

  /// Per-core usage and frequency breakdown.
  final List<CpuCoreMetrics> cores;

  /// Average clock frequency in GHz.
  double get averageFrequencyGhz => averageFrequencyMhz / 1000.0;

  /// Peak clock frequency in GHz.
  double get maxFrequencyGhz => maxFrequencyMhz / 1000.0;

  Map<String, dynamic> toJson() => {
        'usage_percent': usagePercent,
        'brand': brand,
        'vendor_id': vendorId,
        'physical_cores': physicalCores,
        'logical_cores': logicalCores,
        'average_frequency_mhz': averageFrequencyMhz,
        'max_frequency_mhz': maxFrequencyMhz,
        'cores': cores.map((c) => c.toJson()).toList(growable: false),
      };

  @override
  String toString() =>
      'CpuMetrics($brand, usage: ${usagePercent.toStringAsFixed(1)}%, '
      'cores: $physicalCores P / $logicalCores L, avgFreq: $averageFrequencyMhz MHz)';
}
