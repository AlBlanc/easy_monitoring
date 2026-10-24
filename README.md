# easy_monitoring

Cross-platform Flutter library (**Windows**, **macOS**, **Linux**, **Android**, **iOS**) for retrieving real-time **CPU**, **RAM / Swap**, **GPU**, and **Current Process** resource consumption via **Rust** ([`sysinfo`](https://crates.io/crates/sysinfo) and specialized platform graphics monitors), exposed as non-blocking **Dart Streams** powered by a dedicated background `Isolate`.

---

## Platform Feature Matrix

| Category | Metric / Feature | Windows | macOS | Linux | Android | iOS |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **System CPU** | Global utilization (`usagePercent` in `%`) | ✅ | ✅ | ✅ | ⚠️ *(1)* | ✅ |
| **System CPU** | Per-logical-core utilization (`cores[i].usagePercent`) | ✅ | ✅ | ✅ | ⚠️ *(1)* | ✅ |
| **System CPU** | Per-core, average, and max clock frequencies (`MHz` / `GHz`) | ✅ | ✅ | ✅ | ✅ | ⚠️ *(2)* |
| **System CPU** | Brand (`brand`), vendor (`vendorId`), physical & logical core counts | ✅ | ✅ | ✅ | ✅ | ✅ |
| **System RAM** | Used / Total / Free / Available RAM (`%`, bytes, MB, GB) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **System Swap** | Used / Total / Free Swap (`%`, bytes, MB, GB) | ✅ | ✅ | ✅ | ✅ | ⚠️ *(3)* |
| **System GPU** | Model (`model`), vendor (`vendor`), architecture (`family`) | ✅ | ✅ | ✅ | ✅ *(4)* | ✅ |
| **System GPU** | Global GPU core load (`usagePercent` in `%`) | ✅ *(5)* | ✅ | ✅ *(6)* | ✅ *(4)* | ❌ *(7)* |
| **System GPU** | Used / Total VRAM (`%`, bytes, MB, GB) | ✅ *(8)* | ✅ *(9)* | ✅ *(6)* | ✅ *(4)* | ⚠️ *(9)* |
| **System GPU** | GPU temperature (`temperatureCelsius` in `°C`) | ⚠️ *(10)* | ⚠️ *(10)* | ✅ *(6)* | ❌ | ❌ |
| **Current Process** | PID (`pid`), name (`name`), status (`status`), uptime (`runTime`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Current Process** | Process CPU usage (`cpuUsagePercent` & `rawCpuUsagePercent`) | ✅ | ✅ | ✅ | ✅ | ✅ *(11)* |
| **Current Process** | Physical RAM (RSS) & virtual memory (`%`, bytes, MB, GB) | ✅ | ✅ | ✅ | ✅ | ✅ *(11)* |
| **Current Process** | Process GPU core load (`gpuUsagePercent` in `%`) | ✅ *(5)* | ⚠️ *(12)* | ✅ *(13)* | ❌ | ❌ |
| **Current Process** | Process VRAM usage (`%`, bytes, MB, GB) | ✅ *(8)* | ⚠️ *(12)* | ✅ *(13)* | ❌ | ❌ |

### Platform Technical Notes:
1. **Android (System CPU)**: Starting with Android 8+ (SELinux), access to `/proc/stat` is restricted on some non-rooted devices; however, **current process** CPU usage (`/proc/self/stat`) and per-core CPU clock frequencies remain available.
2. **iOS (CPU Frequency)**: Apple does not expose instantaneous CPU clock frequencies in MHz on iOS/mobile Apple Silicon.
3. **iOS (Swap)**: iOS does not expose traditional user-space swap metrics.
4. **Android (GPU)**: Queried via sysfs (`/sys/class/kgsl/kgsl-3d0/...` on Qualcomm Adreno, `/sys/class/misc/mali0/...` on ARM Mali, and `/sys/class/devfreq/.../load`) when allowed by vendor SELinux policies.
5. **Windows (GPU Usage & Process Load)**: Monitored across all GPU vendors (**Intel Arc / Iris Xe / UHD**, **NVIDIA**, **AMD**, Qualcomm Snapdragon X) through persistent WDDM performance counter engine aggregation (`\GPU Engine(*)\Utilization Percentage`). Calculates live time deltas across 3D, Compute, Copy, and Video hardware engines.
6. **Linux (GPU Usage & VRAM)**: Comprehensive support for **NVIDIA** (via NVML), **AMD** (via `libdrm_amdgpu_sys` & `/sys/class/drm/card*/device/gpu_busy_percent`), and **Intel** (via DRM sysfs & GT frequency scaling ratio `rps_act_freq_mhz / rps_max_freq_mhz`).
7. **iOS (System GPU)**: The iOS App Sandbox blocks global `IOAccelerator` queries, unlike macOS.
8. **Windows (VRAM & Shared Memory)**: Queries `\GPU Adapter Memory(*)\Dedicated Usage`. On integrated architectures (such as Intel Arc/Iris or AMD APUs) where dedicated on-board GDDR is 0 bytes, seamlessly falls back to active `Shared Usage` and maps total capacity to the allocatable system memory pool.
9. **macOS / iOS (Apple Silicon Unified Memory)**: On unified memory architectures, total VRAM reflects the allocatable GPU/system memory pool and used VRAM reflects `In use system memory` (`IOAccelerator`).
10. **GPU Temperature (Windows / macOS)**: Available on Windows with NVIDIA GPUs (via NVML) and on Macs exposing `Temperature(C)` in `IOAccelerator`; returns `null` when not reported by the hardware driver.
11. **iOS (Current Process)**: Implemented via public Mach kernel APIs (`mach_task_self()`, `task_info(MACH_TASK_BASIC_INFO)`, and `task_threads(THREAD_BASIC_INFO)`), 100% App Store compliant.
12. **macOS (Per-Process GPU)**: Computed by inspecting child IOKit `IOUserClient` entries under `IOAccelerator` (`IOUserClientCreator` matching the target PID).
13. **Linux (Per-Process GPU Load & VRAM)**: Supported on NVIDIA (via NVML `process_utilization_stats`) and AMD/Intel via Linux 5.4+ `/proc/<pid>/fdinfo/*` DRM engine time (`drm-engine-*`) and client memory (`drm-resident-memory`).

---

## Quick Start

```dart
import 'package:easy_monitoring/easy_monitoring.dart';

void main() async {
  final monitor = EasyMonitoring.instance;

  // 1. Listen to the unified stream (System CPU + RAM + GPU + Current Process) every second
  final sub = monitor
      .metricsStream(interval: const Duration(seconds: 1))
      .listen((SystemMetrics metrics) {
    print('System CPU: ${metrics.cpu.usagePercent.toStringAsFixed(1)}% (${metrics.cpu.brand})');
    print('System RAM: ${metrics.memory.usagePercent.toStringAsFixed(1)}% (${metrics.memory.formattedUsage})');
    print('System GPU: ${metrics.gpu.usagePercent.toStringAsFixed(1)}% (${metrics.gpu.vendor} ${metrics.gpu.model})');
    print('System VRAM: ${metrics.gpu.formattedVramUsage} (${metrics.gpu.vramUsagePercent.toStringAsFixed(1)}%)');
    print('Current Process (PID ${metrics.currentProcess.pid}): '
        'CPU ${metrics.currentProcess.cpuUsagePercent.toStringAsFixed(2)}%, '
        'RAM ${metrics.currentProcess.formattedMemoryUsage}, '
        'GPU ${metrics.currentProcess.gpuUsagePercent.toStringAsFixed(1)}%');
  });

  // 2. Or subscribe to a specific metric stream:
  // monitor.currentProcessStream(interval: const Duration(milliseconds: 500))
  // monitor.cpuStream(interval: const Duration(milliseconds: 500))
  // monitor.memoryStream()
  // monitor.gpuStream()

  // 3. Or fetch a one-shot snapshot (Future):
  final procSnapshot = await monitor.getCurrentProcessMetrics();
  print('Current process RAM: ${procSnapshot.formattedMemory}');
}
```

---

## Architecture & Zero-Rust Distribution (`prebuilt/` + SwiftPM + CMake + Gradle)

The compiled release Rust library (`lto = true`, `opt-level = "s"`, `strip = true`) weighs only **~460 KB per platform**.

`easy_monitoring` uses a **Single FFI Plugin (`ffiPlugin: true`)** with precompiled binary resolution:
- **macOS & iOS**: Full **Swift Package Manager** support (`macos/easy_monitoring/Package.swift` and `ios/easy_monitoring/Package.swift`) + **CocoaPods** backward compatibility (`*.podspec`).
- **Windows & Linux**: **CMake** integration (`windows/CMakeLists.txt` and `linux/CMakeLists.txt`) that uses `prebuilt/` first, falls back to downloading from GitHub Releases, or builds from source via `cargo` during local development.
- **Android**: **Gradle `jniLibs`** integration (`android/build.gradle`) that automatically bundles `prebuilt/android/{arm64-v8a,armeabi-v7a,x86_64}/libeasy_monitoring.so`.
- **GitHub Actions CI/CD (`.github/workflows/release_binaries.yml`)**: Automatically builds and publishes precompiled binaries for all 5 platforms (**Windows**, **macOS Universal**, **Linux**, **Android**, **iOS**).
