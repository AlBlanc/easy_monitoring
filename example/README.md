# easy_monitoring_example

Example Flutter application showcasing the [`easy_monitoring`](../README.md) plugin.

It renders a live hardware monitoring dashboard powered by **Dart Streams** (`EasyMonitoring.instance.metricsStream`) and native **Rust** probes (`sysinfo` & `gfxinfo`).

---

## Features Overview

- **Current Process (`currentProcess`)**:
  - Process ID (`PID`), executable name, OS status, and uptime.
  - **Process CPU**: Normalized CPU usage (`0–100%`) and raw per-core usage (`100% = 1 logical core`) with a live sparkline chart.
  - **Process RAM**: Physical RAM (RSS) over total system RAM (`MB` / `GB` and `%`) and allocated virtual memory.
  - **Process GPU**: Process GPU core load (`%`) and VRAM used by the application (`MB` / `GB` and `%`).
- **System Processor (`cpu`)**:
  - Global utilization (`%`), CPU brand/vendor, physical and logical core counts, average and peak clock frequencies (`MHz` / `GHz`).
  - Expandable live grid showing utilization (`%`) for every logical CPU core.
- **System Memory (`memory`)**:
  - RAM & Swap utilization in percentage (`%`) and absolute values (`GB` and `MB` used, total, available, and free).
- **System Graphics Card (`gpu`)**:
  - GPU core load (`%`), VRAM consumption (`%`, `GB`, and `MB` used over total), vendor/model, and temperature (`°C` when reported).
- **Interactive Controls**:
  - Refresh interval selector (`250 ms`, `500 ms`, `1 s`, `2 s`).
  - **Play / Pause** stream toggle (`StreamSubscription`).
  - Manual one-shot snapshot button (`getSystemMetrics()`).

---

## Running the Example

From the `example` directory:

```bash
cd example
flutter pub get

# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux

# Android / iOS
flutter run -d android
flutter run -d ios
```
