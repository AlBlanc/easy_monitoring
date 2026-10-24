## 0.1.1

* **Fix Windows GPU Usage**: Resolved an issue where GPU utilization percentage stayed at 0% on Windows with Intel graphics (and other non-NVIDIA GPUs) by implementing continuous WDDM hardware engine aggregation (`\GPU Engine(*)\Utilization Percentage`) in `rust/src/windows_gpu.rs`.
* **Integrated VRAM & Shared Memory Fallback**: On GPUs without dedicated on-board GDDR (Intel Arc, Iris Xe, UHD, AMD APUs, Apple Silicon), memory usage seamlessly falls back to active shared system memory and maps total capacity to the allocatable system memory pool.
* **Linux & Android GPU Enhancements**: Added support for Intel DRM sysfs, GT frequency scaling ratio (`rps_act_freq_mhz / rps_max_freq_mhz`), Linux DRM client process nanosecond engine sampling, and Android `devfreq` paths.
* **Example Project Improvements**: Added hardware engine sampling info and memory architecture classification (Unified / Shared System Memory vs Dedicated VRAM).
* Updated native Rust library and platform specifications to version 0.1.1.

## 0.1.0

* Initial release of `easy_monitoring` for Windows, macOS, and Linux.
* Real-time CPU, RAM/Swap, and GPU consumption monitoring powered by Rust (`sysinfo` and `gfxinfo`).
* Exposes non-blocking Dart broadcast Streams (`metricsStream`, `cpuStream`, `memoryStream`, `gpuStream`) and one-shot async snapshots via a background `Isolate`.
* Zero-Rust consumer setup via precompiled binaries (`prebuilt/` + GitHub Releases fallback).
