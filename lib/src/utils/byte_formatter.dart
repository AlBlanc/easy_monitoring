/// Utility functions for converting and formatting raw byte counts into
/// human-readable units (KB, MB, GB, TB).
class ByteFormatter {
  const ByteFormatter._();

  static const int bytesPerKb = 1024;
  static const int bytesPerMb = 1024 * 1024;
  static const int bytesPerGb = 1024 * 1024 * 1024;

  /// Converts bytes to megabytes (MiB).
  static double toMegabytes(int bytes) => bytes / bytesPerMb;

  /// Converts bytes to gigabytes (GiB).
  static double toGigabytes(int bytes) => bytes / bytesPerGb;

  /// Formats [bytes] into a human-readable string (e.g., `12.45 GB`, `512.0 MB`).
  static String format(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return '0 B';
    if (bytes >= bytesPerGb) {
      return '${toGigabytes(bytes).toStringAsFixed(decimals)} GB';
    }
    if (bytes >= bytesPerMb) {
      return '${toMegabytes(bytes).toStringAsFixed(decimals)} MB';
    }
    if (bytes >= bytesPerKb) {
      return '${(bytes / bytesPerKb).toStringAsFixed(decimals)} KB';
    }
    return '$bytes B';
  }

  /// Formats a `used / total` byte pair into a human-readable ratio string
  /// (e.g., `14.20 GB / 32.00 GB`).
  static String formatRatio(int usedBytes, int totalBytes, {int decimals = 2}) {
    if (totalBytes <= 0) {
      return '${format(usedBytes, decimals: decimals)} / N/A';
    }
    if (totalBytes >= bytesPerGb) {
      return '${toGigabytes(usedBytes).toStringAsFixed(decimals)} GB / '
          '${toGigabytes(totalBytes).toStringAsFixed(decimals)} GB';
    }
    return '${toMegabytes(usedBytes).toStringAsFixed(decimals)} MB / '
        '${toMegabytes(totalBytes).toStringAsFixed(decimals)} MB';
  }
}
