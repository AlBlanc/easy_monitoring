import '../utils/byte_formatter.dart';

/// Active GPU hardware information and real-time utilization metrics
/// collected via `gfxinfo`.
class GpuMetrics {
  const GpuMetrics({
    required this.available,
    required this.vendor,
    required this.model,
    required this.family,
    required this.deviceId,
    required this.usagePercent,
    required this.usedVramBytes,
    required this.totalVramBytes,
    required this.vramUsagePercent,
    this.temperatureCelsius,
  });

  factory GpuMetrics.fromJson(Map<String, dynamic> json) {
    return GpuMetrics(
      available: (json['available'] as bool?) ?? false,
      vendor: (json['vendor'] as String?) ?? 'Unavailable',
      model: (json['model'] as String?) ?? 'Unknown GPU',
      family: (json['family'] as String?) ?? 'N/A',
      deviceId: (json['device_id'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      usedVramBytes: (json['used_vram_bytes'] as num?)?.toInt() ?? 0,
      totalVramBytes: (json['total_vram_bytes'] as num?)?.toInt() ?? 0,
      vramUsagePercent: (json['vram_usage_percent'] as num?)?.toDouble() ?? 0.0,
      temperatureCelsius: (json['temperature_celsius'] as num?)?.toDouble(),
    );
  }

  /// Whether an active GPU was detected on the host machine.
  final bool available;

  /// GPU vendor name (e.g., `NVIDIA`, `AMD`, `Intel`, `Apple`).
  final String vendor;

  /// GPU model name (e.g., `GeForce RTX 4090`, `Radeon RX 7900 XTX`, `Apple M5 Ultra`).
  final String model;

  /// GPU architecture / family name.
  final String family;

  /// PCI / hardware device ID.
  final int deviceId;

  /// Real-time GPU core utilization percentage in `[0.0, 100.0]`.
  final double usagePercent;

  /// Used VRAM in bytes (absolute value).
  final int usedVramBytes;

  /// Total VRAM in bytes (absolute value).
  final int totalVramBytes;

  /// VRAM utilization percentage in `[0.0, 100.0]`.
  final double vramUsagePercent;

  /// GPU temperature in degrees Celsius, or `null` if not reported by the driver/OS.
  final double? temperatureCelsius;

  /// Used VRAM in GiB.
  double get usedVramGb => ByteFormatter.toGigabytes(usedVramBytes);

  /// Total VRAM in GiB.
  double get totalVramGb => ByteFormatter.toGigabytes(totalVramBytes);

  /// Used VRAM in MiB.
  double get usedVramMb => ByteFormatter.toMegabytes(usedVramBytes);

  /// Total VRAM in MiB.
  double get totalVramMb => ByteFormatter.toMegabytes(totalVramBytes);

  /// Formatted `used / total` VRAM string (e.g. `2.40 GB / 16.00 GB`).
  String get formattedVramUsage =>
      ByteFormatter.formatRatio(usedVramBytes, totalVramBytes);

  Map<String, dynamic> toJson() => {
        'available': available,
        'vendor': vendor,
        'model': model,
        'family': family,
        'device_id': deviceId,
        'usage_percent': usagePercent,
        'used_vram_bytes': usedVramBytes,
        'total_vram_bytes': totalVramBytes,
        'vram_usage_percent': vramUsagePercent,
        'temperature_celsius': temperatureCelsius,
      };

  @override
  String toString() =>
      'GpuMetrics($vendor $model, load: ${usagePercent.toStringAsFixed(1)}%, '
      'VRAM: ${vramUsagePercent.toStringAsFixed(1)}% [$formattedVramUsage], '
      'temp: ${temperatureCelsius != null ? "${temperatureCelsius!.toStringAsFixed(1)}°C" : "N/A"})';
}
