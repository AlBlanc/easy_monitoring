## 0.1.0

* Initial release of `easy_monitoring` for Windows, macOS, and Linux.
* Real-time CPU, RAM/Swap, and GPU consumption monitoring powered by Rust (`sysinfo` and `gfxinfo`).
* Exposes non-blocking Dart broadcast Streams (`metricsStream`, `cpuStream`, `memoryStream`, `gpuStream`) and one-shot async snapshots via a background `Isolate`.
* Zero-Rust consumer setup via precompiled binaries (`prebuilt/` + GitHub Releases fallback).
