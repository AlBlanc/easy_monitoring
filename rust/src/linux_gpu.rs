#[cfg(any(target_os = "linux", target_os = "android"))]
use std::fs;
use std::path::Path;
use std::time::Instant;

#[derive(Debug, Default, Clone)]
pub struct GpuSample {
    pub total_usage_percent: f64,
    pub process_usage_percent: f64,
    pub used_vram_bytes: u64,
}

#[cfg(any(target_os = "linux", target_os = "android"))]
pub struct LinuxGpuMonitor {
    last_poll: Instant,
    last_proc_gpu_ns: u64,
}

#[cfg(any(target_os = "linux", target_os = "android"))]
impl LinuxGpuMonitor {
    pub fn new() -> Self {
        Self {
            last_poll: Instant::now(),
            last_proc_gpu_ns: 0,
        }
    }

    pub fn poll(&mut self, target_pid: u32) -> GpuSample {
        let now = Instant::now();
        let elapsed_secs = now.duration_since(self.last_poll).as_secs_f64().max(0.001);
        self.last_poll = now;

        let total_usage = Self::read_system_gpu_usage();
        let (proc_usage, proc_vram) = self.sample_process_gpu(target_pid, elapsed_secs);
        let used_vram = Self::read_system_vram_usage().max(proc_vram);

        GpuSample {
            total_usage_percent: total_usage,
            process_usage_percent: proc_usage,
            used_vram_bytes: used_vram,
        }
    }

    fn read_system_gpu_usage() -> f64 {
        // 1. Android Qualcomm Adreno
        if let Ok(content) = fs::read_to_string("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage") {
            if let Some(val) = Self::parse_percentage(&content) {
                return val;
            }
        }

        // 2. Android / Linux ARM Mali device utilization
        if let Ok(content) = fs::read_to_string("/sys/class/misc/mali0/device/utilization") {
            if let Some(val) = Self::parse_percentage(&content) {
                return val;
            }
        }

        // 3. Android / Linux common devfreq GPU paths (Mali, PowerVR, etc.)
        let devfreq_paths = [
            "/sys/class/devfreq/gpufreq/load",
            "/sys/class/devfreq/1c00000.mali/load",
            "/sys/class/devfreq/gpu/load",
            "/sys/kernel/gpu/gpu_busy",
        ];
        for path in &devfreq_paths {
            if let Ok(content) = fs::read_to_string(path) {
                if let Some(val) = Self::parse_percentage(&content) {
                    return val;
                }
            }
        }

        // 4. Linux DRM AMD / Intel gpu_busy_percent
        for card_idx in 0..8 {
            let busy_path = format!("/sys/class/drm/card{}/device/gpu_busy_percent", card_idx);
            if let Ok(content) = fs::read_to_string(&busy_path) {
                if let Some(val) = Self::parse_percentage(&content) {
                    return val;
                }
            }

            // 5. Linux DRM Intel GT frequency scaling ratio
            let act_path = format!("/sys/class/drm/card{}/gt/gt0/rps_act_freq_mhz", card_idx);
            let max_path = format!("/sys/class/drm/card{}/gt/gt0/rps_max_freq_mhz", card_idx);
            if let (Ok(act_str), Ok(max_str)) = (fs::read_to_string(&act_path), fs::read_to_string(&max_path)) {
                if let (Ok(act), Ok(max)) = (act_str.trim().parse::<f64>(), max_str.trim().parse::<f64>()) {
                    if max > 0.0 {
                        return ((act / max) * 100.0).clamp(0.0, 100.0);
                    }
                }
            }

            // Older Intel path
            let old_act = format!("/sys/class/drm/card{}/gt_act_freq_mhz", card_idx);
            let old_max = format!("/sys/class/drm/card{}/gt_max_freq_mhz", card_idx);
            if let (Ok(act_str), Ok(max_str)) = (fs::read_to_string(&old_act), fs::read_to_string(&old_max)) {
                if let (Ok(act), Ok(max)) = (act_str.trim().parse::<f64>(), max_str.trim().parse::<f64>()) {
                    if max > 0.0 {
                        return ((act / max) * 100.0).clamp(0.0, 100.0);
                    }
                }
            }
        }

        0.0
    }

    fn read_system_vram_usage() -> u64 {
        // Qualcomm Adreno page_alloc
        if let Ok(content) = fs::read_to_string("/sys/class/kgsl/kgsl-3d0/page_alloc") {
            if let Ok(bytes) = content.trim().parse::<u64>() {
                return bytes;
            }
        }

        // Linux AMD VRAM usage
        for card_idx in 0..8 {
            let vram_path = format!("/sys/class/drm/card{}/device/mem_info_vram_used", card_idx);
            if let Ok(content) = fs::read_to_string(&vram_path) {
                if let Ok(bytes) = content.trim().parse::<u64>() {
                    return bytes;
                }
            }
        }

        0
    }

    fn sample_process_gpu(&mut self, target_pid: u32, elapsed_secs: f64) -> (f64, u64) {
        if target_pid == 0 {
            return (0.0, 0);
        }

        let fdinfo_dir = format!("/proc/{}/fdinfo", target_pid);
        let path = Path::new(&fdinfo_dir);
        if !path.is_dir() {
            return (0.0, 0);
        }

        let mut total_drm_ns = 0u64;
        let mut proc_vram_bytes = 0u64;

        if let Ok(entries) = fs::read_dir(path) {
            for entry in entries.flatten() {
                if let Ok(content) = fs::read_to_string(entry.path()) {
                    for line in content.lines() {
                        // Linux 5.4+ DRM engine time: drm-engine-render, drm-engine-compute, drm-engine-copy
                        if line.starts_with("drm-engine-") {
                            if let Some(pos) = line.find(':') {
                                if let Ok(ns) = line[pos + 1..].trim().trim_end_matches("ns").trim().parse::<u64>() {
                                    total_drm_ns += ns;
                                }
                            }
                        }
                        // Linux DRM client memory usage
                        if line.starts_with("drm-resident-memory:") || line.starts_with("drm-total-memory:") {
                            if let Some(pos) = line.find(':') {
                                let parts: Vec<&str> = line[pos + 1..].trim().split_whitespace().collect();
                                if let Some(&num_str) = parts.first() {
                                    if let Ok(val) = num_str.parse::<u64>() {
                                        let unit = parts.get(1).map(|&u| u.to_lowercase()).unwrap_or_default();
                                        let bytes = match unit.as_str() {
                                            "kib" | "kb" => val * 1024,
                                            "mib" | "mb" => val * 1024 * 1024,
                                            "gib" | "gb" => val * 1024 * 1024 * 1024,
                                            _ => val,
                                        };
                                        proc_vram_bytes = proc_vram_bytes.max(bytes);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let mut proc_usage = 0.0;
        if self.last_proc_gpu_ns > 0 && total_drm_ns >= self.last_proc_gpu_ns {
            let delta_ns = (total_drm_ns - self.last_proc_gpu_ns) as f64;
            let elapsed_ns = elapsed_secs * 1_000_000_000.0;
            if elapsed_ns > 0.0 {
                proc_usage = ((delta_ns / elapsed_ns) * 100.0).clamp(0.0, 100.0);
            }
        }
        self.last_proc_gpu_ns = total_drm_ns;

        (proc_usage, proc_vram_bytes)
    }

    fn parse_percentage(s: &str) -> Option<f64> {
        let trimmed = s.trim().trim_end_matches('%').trim();
        // Handle formats like "load: 45%" or just "45"
        let val_str = trimmed.split_whitespace().last()?;
        val_str.parse::<f64>().ok().map(|v| v.clamp(0.0, 100.0))
    }
}
