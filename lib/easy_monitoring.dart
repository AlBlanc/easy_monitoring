/// Real-time CPU, RAM, and GPU hardware monitoring library for Flutter
/// (Windows, macOS, and Linux) powered by Rust (`sysinfo` & `gfxinfo`).
library easy_monitoring;

export 'src/easy_monitoring_client.dart';
export 'src/models/cpu_metrics.dart';
export 'src/models/gpu_metrics.dart';
export 'src/models/memory_metrics.dart';
export 'src/models/process_metrics.dart';
export 'src/models/system_metrics.dart';
export 'src/utils/byte_formatter.dart';
