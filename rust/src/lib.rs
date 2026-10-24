use std::ffi::CString;
use std::os::raw::c_char;
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
use gfxinfo::active_gpu;
use serde::{Deserialize, Serialize};
use sysinfo::{
    CpuRefreshKind, MemoryRefreshKind, Pid, ProcessRefreshKind, ProcessesToUpdate, RefreshKind,
    System, get_current_pid,
};

/// Per-core CPU metrics collected via `sysinfo`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuCoreMetrics {
    pub index: usize,
    pub name: String,
    pub usage_percent: f32,
    pub frequency_mhz: u64,
}

/// Aggregate and per-core CPU metrics collected via `sysinfo`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuMetrics {
    pub usage_percent: f32,
    pub brand: String,
    pub vendor_id: String,
    pub physical_cores: usize,
    pub logical_cores: usize,
    pub average_frequency_mhz: u64,
    pub max_frequency_mhz: u64,
    pub cores: Vec<CpuCoreMetrics>,
}

/// Physical RAM and Swap metrics collected via `sysinfo`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryMetrics {
    pub total_memory_bytes: u64,
    pub used_memory_bytes: u64,
    pub free_memory_bytes: u64,
    pub available_memory_bytes: u64,
    pub usage_percent: f64,
    pub total_swap_bytes: u64,
    pub used_swap_bytes: u64,
    pub free_swap_bytes: u64,
    pub swap_usage_percent: f64,
}

/// GPU metrics collected via `gfxinfo` (desktop) or platform APIs (iOS/Android).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GpuMetrics {
    pub available: bool,
    pub vendor: String,
    pub model: String,
    pub family: String,
    pub device_id: u32,
    pub usage_percent: f64,
    pub used_vram_bytes: u64,
    pub total_vram_bytes: u64,
    pub vram_usage_percent: f64,
    pub temperature_celsius: Option<f64>,
}

/// CPU, RAM, and GPU consumption metrics for a specific process
/// (by default the current running process).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessMetrics {
    pub pid: u32,
    pub name: String,
    pub status: String,
    pub run_time_seconds: u64,
    /// Normalized CPU usage across all logical cores (`0.0` to `100.0`%).
    pub cpu_usage_percent: f32,
    /// Raw `sysinfo` CPU usage where `100.0%` equals 1 full logical core
    /// (`0.0` to `100.0 * logical_cores`%).
    pub raw_cpu_usage_percent: f32,
    /// Physical RAM (Resident Set Size) used by the process in bytes.
    pub memory_bytes: u64,
    /// Virtual memory allocated by the process in bytes.
    pub virtual_memory_bytes: u64,
    /// Total system physical RAM in bytes (for reference).
    pub total_system_memory_bytes: u64,
    /// Percentage of total system RAM used by the process (`0.0` to `100.0`%).
    pub memory_usage_percent: f64,
    /// GPU core utilization percentage for this process (`0.0` to `100.0`%).
    pub gpu_usage_percent: f64,
    /// GPU VRAM used by this process in bytes.
    pub gpu_used_vram_bytes: u64,
    /// Total GPU VRAM in bytes.
    pub gpu_total_vram_bytes: u64,
    /// Percentage of total GPU VRAM used by this process (`0.0` to `100.0`%).
    pub gpu_vram_usage_percent: f64,
}

/// Complete system snapshot combining global CPU, Memory (RAM/Swap), GPU,
/// and current process consumption metrics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub cpu: CpuMetrics,
    pub memory: MemoryMetrics,
    pub gpu: GpuMetrics,
    pub current_process: ProcessMetrics,
    pub timestamp_ms: u64,
}

/// Stateful monitoring engine keeping `sysinfo::System` alive across polls
/// so CPU usage deltas (both global and per-process) are accurate without blocking on every tick.
pub struct EasyMonitoringEngine {
    system: System,
    physical_cores: usize,
    current_pid: Pid,
    start_instant: std::time::Instant,
}

impl EasyMonitoringEngine {
    pub fn new() -> Self {
        let refresh_kind = RefreshKind::nothing()
            .with_cpu(CpuRefreshKind::everything())
            .with_memory(MemoryRefreshKind::everything());
        let mut system = System::new_with_specifics(refresh_kind);
        system.refresh_specifics(refresh_kind);

        let current_pid =
            get_current_pid().unwrap_or_else(|_| Pid::from_u32(std::process::id()));
        let proc_refresh = ProcessRefreshKind::nothing().with_cpu().with_memory();
        system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[current_pid]),
            true,
            proc_refresh,
        );

        // Perform an initial short sleep once on creation so the very first poll
        // already has a valid CPU usage baseline for both global CPU and current process.
        std::thread::sleep(sysinfo::MINIMUM_CPU_UPDATE_INTERVAL);
        system.refresh_cpu_all();
        system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[current_pid]),
            true,
            proc_refresh,
        );

        let physical_cores = system
            .physical_core_count()
            .unwrap_or_else(|| system.cpus().len());

        Self {
            system,
            physical_cores,
            current_pid,
            start_instant: std::time::Instant::now(),
        }
    }

    pub fn poll(&mut self) -> SystemMetrics {
        self.system.refresh_cpu_all();
        self.system.refresh_memory();
        let proc_refresh = ProcessRefreshKind::nothing().with_cpu().with_memory();
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[self.current_pid]),
            true,
            proc_refresh,
        );

        let cpu = self.collect_cpu_metrics();
        let memory = self.collect_memory_metrics();
        let (gpu, proc_gpu_load, proc_gpu_vram) =
            Self::collect_gpu_and_process_metrics(
                memory.total_memory_bytes,
                self.current_pid.as_u32(),
            );
        let current_process = self.build_process_metrics(
            self.current_pid,
            cpu.logical_cores,
            memory.total_memory_bytes,
            gpu.total_vram_bytes,
            proc_gpu_load,
            proc_gpu_vram,
        );

        let timestamp_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        SystemMetrics {
            cpu,
            memory,
            gpu,
            current_process,
            timestamp_ms,
        }
    }

    pub fn poll_process(&mut self, pid_override: Option<u32>) -> ProcessMetrics {
        let target_pid = pid_override
            .filter(|&p| p > 0)
            .map(Pid::from_u32)
            .unwrap_or(self.current_pid);

        self.system.refresh_memory();
        let proc_refresh = ProcessRefreshKind::nothing().with_cpu().with_memory();
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[target_pid]),
            true,
            proc_refresh,
        );

        let logical_cores = self.system.cpus().len().max(1);
        let total_mem = self.system.total_memory();
        let (gpu, proc_gpu_load, proc_gpu_vram) =
            Self::collect_gpu_and_process_metrics(total_mem, target_pid.as_u32());

        self.build_process_metrics(
            target_pid,
            logical_cores,
            total_mem,
            gpu.total_vram_bytes,
            proc_gpu_load,
            proc_gpu_vram,
        )
    }

    fn collect_cpu_metrics(&self) -> CpuMetrics {
        let cpus = self.system.cpus();
        let logical_cores = cpus.len();
        let physical_cores = if self.physical_cores > 0 {
            self.physical_cores
        } else {
            logical_cores
        };

        let brand = cpus
            .first()
            .map(|c| c.brand().trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "Unknown CPU".to_string());

        let vendor_id = cpus
            .first()
            .map(|c| c.vendor_id().trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "Unknown".to_string());

        let mut total_freq: u64 = 0;
        let mut max_freq: u64 = 0;
        let mut cores = Vec::with_capacity(logical_cores);

        for (idx, cpu) in cpus.iter().enumerate() {
            let freq = cpu.frequency();
            total_freq += freq;
            if freq > max_freq {
                max_freq = freq;
            }
            let usage = cpu.cpu_usage();
            let clamped_usage = if usage.is_finite() {
                usage.clamp(0.0, 100.0)
            } else {
                0.0
            };
            cores.push(CpuCoreMetrics {
                index: idx,
                name: cpu.name().to_string(),
                usage_percent: clamped_usage,
                frequency_mhz: freq,
            });
        }

        let average_frequency_mhz = if logical_cores > 0 {
            total_freq / (logical_cores as u64)
        } else {
            0
        };

        let global_usage = self.system.global_cpu_usage();
        let usage_percent = if global_usage.is_finite() {
            global_usage.clamp(0.0, 100.0)
        } else {
            0.0
        };

        CpuMetrics {
            usage_percent,
            brand,
            vendor_id,
            physical_cores,
            logical_cores,
            average_frequency_mhz,
            max_frequency_mhz: max_freq,
            cores,
        }
    }

    fn collect_memory_metrics(&self) -> MemoryMetrics {
        let total_memory_bytes = self.system.total_memory();
        let used_memory_bytes = self.system.used_memory();
        let free_memory_bytes = self.system.free_memory();
        let available_memory_bytes = self.system.available_memory();

        let usage_percent = if total_memory_bytes > 0 {
            ((used_memory_bytes as f64 / total_memory_bytes as f64) * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };

        let total_swap_bytes = self.system.total_swap();
        let used_swap_bytes = self.system.used_swap();
        let free_swap_bytes = self.system.free_swap();

        let swap_usage_percent = if total_swap_bytes > 0 {
            ((used_swap_bytes as f64 / total_swap_bytes as f64) * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };

        MemoryMetrics {
            total_memory_bytes,
            used_memory_bytes,
            free_memory_bytes,
            available_memory_bytes,
            usage_percent,
            total_swap_bytes,
            used_swap_bytes,
            free_swap_bytes,
            swap_usage_percent,
        }
    }

    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    fn collect_gpu_and_process_metrics(
        fallback_unified_memory_bytes: u64,
        pid: u32,
    ) -> (GpuMetrics, f64, u64) {
        match active_gpu() {
            Ok(gpu) => {
                let vendor = gpu.vendor().to_string();
                let model = gpu.model().to_string();
                let family = gpu.family().to_string();
                let device_id = *gpu.device_id();

                let info = gpu.info();
                let usage_percent = (info.load_pct() as f64).clamp(0.0, 100.0);
                let used_vram_bytes = info.used_vram();
                let mut total_vram_bytes = info.total_vram();

                // On unified memory architectures (e.g. Apple Silicon), if total_vram is 0
                // or smaller than used_vram, fallback to unified system memory total.
                if (total_vram_bytes == 0 || total_vram_bytes < used_vram_bytes)
                    && fallback_unified_memory_bytes > 0
                {
                    total_vram_bytes = fallback_unified_memory_bytes;
                }

                let vram_usage_percent = if total_vram_bytes > 0 {
                    ((used_vram_bytes as f64 / total_vram_bytes as f64) * 100.0).clamp(0.0, 100.0)
                } else {
                    0.0
                };

                let raw_temp_mc = info.temperature();
                let temperature_celsius = if raw_temp_mc > 0 {
                    Some(raw_temp_mc as f64 / 1000.0)
                } else {
                    None
                };

                let proc_gpu_load = (info.process_load_pct(pid) as f64).clamp(0.0, 100.0);
                let proc_gpu_vram = info.process_used_vram(pid);

                (
                    GpuMetrics {
                        available: true,
                        vendor,
                        model,
                        family,
                        device_id,
                        usage_percent,
                        used_vram_bytes,
                        total_vram_bytes,
                        vram_usage_percent,
                        temperature_celsius,
                    },
                    proc_gpu_load,
                    proc_gpu_vram,
                )
            }
            Err(_) => (
                GpuMetrics {
                    available: false,
                    vendor: "Unavailable".to_string(),
                    model: "No supported GPU detected".to_string(),
                    family: "N/A".to_string(),
                    device_id: 0,
                    usage_percent: 0.0,
                    used_vram_bytes: 0,
                    total_vram_bytes: 0,
                    vram_usage_percent: 0.0,
                    temperature_celsius: None,
                },
                0.0,
                0,
            ),
        }
    }

    #[cfg(target_os = "ios")]
    fn collect_gpu_and_process_metrics(
        fallback_unified_memory_bytes: u64,
        _pid: u32,
    ) -> (GpuMetrics, f64, u64) {
        let total_vram_bytes = fallback_unified_memory_bytes;
        (
            GpuMetrics {
                available: true,
                vendor: "Apple".to_string(),
                model: "Apple Mobile GPU (Metal)".to_string(),
                family: "Apple Silicon".to_string(),
                device_id: 0,
                usage_percent: 0.0,
                used_vram_bytes: 0,
                total_vram_bytes,
                vram_usage_percent: 0.0,
                temperature_celsius: None,
            },
            0.0,
            0,
        )
    }

    #[cfg(target_os = "android")]
    fn collect_gpu_and_process_metrics(
        fallback_unified_memory_bytes: u64,
        _pid: u32,
    ) -> (GpuMetrics, f64, u64) {
        let model = std::fs::read_to_string("/sys/class/kgsl/kgsl-3d0/gpu_model")
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "Mobile SoC GPU".to_string());
        let vendor = if model.to_lowercase().contains("adreno") {
            "Qualcomm".to_string()
        } else if model.to_lowercase().contains("mali") {
            "ARM".to_string()
        } else {
            "Android GPU".to_string()
        };

        let load_pct = std::fs::read_to_string("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage")
            .or_else(|_| std::fs::read_to_string("/sys/class/misc/mali0/device/utilization"))
            .ok()
            .and_then(|s| {
                s.trim()
                    .trim_end_matches('%')
                    .trim()
                    .parse::<f64>()
                    .ok()
            })
            .unwrap_or(0.0)
            .clamp(0.0, 100.0);

        let used_vram_bytes = std::fs::read_to_string("/sys/class/kgsl/kgsl-3d0/page_alloc")
            .ok()
            .and_then(|s| s.trim().parse::<u64>().ok())
            .unwrap_or(0);

        let total_vram_bytes = fallback_unified_memory_bytes;
        let vram_usage_percent = if total_vram_bytes > 0 {
            ((used_vram_bytes as f64 / total_vram_bytes as f64) * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };

        (
            GpuMetrics {
                available: true,
                vendor,
                model,
                family: "Mobile".to_string(),
                device_id: 0,
                usage_percent: load_pct,
                used_vram_bytes,
                total_vram_bytes,
                vram_usage_percent,
                temperature_celsius: None,
            },
            0.0,
            0,
        )
    }

    fn build_process_metrics(
        &self,
        pid: Pid,
        logical_cores: usize,
        total_system_memory_bytes: u64,
        gpu_total_vram_bytes: u64,
        gpu_usage_percent: f64,
        gpu_used_vram_bytes: u64,
    ) -> ProcessMetrics {
        let cores_count = logical_cores.max(1) as f32;

        #[cfg(target_os = "ios")]
        {
            if pid == self.current_pid {
                let (raw_cpu, rss_bytes, virt_bytes) = query_ios_current_task_metrics();
                let cpu_usage_percent = (raw_cpu / cores_count).clamp(0.0, 100.0);
                let memory_usage_percent = if total_system_memory_bytes > 0 {
                    ((rss_bytes as f64 / total_system_memory_bytes as f64) * 100.0)
                        .clamp(0.0, 100.0)
                } else {
                    0.0
                };
                let gpu_vram_usage_percent = if gpu_total_vram_bytes > 0 {
                    ((gpu_used_vram_bytes as f64 / gpu_total_vram_bytes as f64) * 100.0)
                        .clamp(0.0, 100.0)
                } else {
                    0.0
                };
                return ProcessMetrics {
                    pid: pid.as_u32(),
                    name: "iOS App Process".to_string(),
                    status: "Run".to_string(),
                    run_time_seconds: self.start_instant.elapsed().as_secs(),
                    cpu_usage_percent,
                    raw_cpu_usage_percent: raw_cpu,
                    memory_bytes: rss_bytes,
                    virtual_memory_bytes: virt_bytes,
                    total_system_memory_bytes,
                    memory_usage_percent,
                    gpu_usage_percent,
                    gpu_used_vram_bytes,
                    gpu_total_vram_bytes,
                    gpu_vram_usage_percent,
                };
            }
        }

        if let Some(proc_info) = self.system.process(pid) {
            let raw_cpu = proc_info.cpu_usage();
            let raw_cpu_usage_percent = if raw_cpu.is_finite() && raw_cpu >= 0.0 {
                raw_cpu
            } else {
                0.0
            };
            let cpu_usage_percent = (raw_cpu_usage_percent / cores_count).clamp(0.0, 100.0);

            let memory_bytes = proc_info.memory();
            let virtual_memory_bytes = proc_info.virtual_memory();
            let memory_usage_percent = if total_system_memory_bytes > 0 {
                ((memory_bytes as f64 / total_system_memory_bytes as f64) * 100.0)
                    .clamp(0.0, 100.0)
            } else {
                0.0
            };

            let gpu_vram_usage_percent = if gpu_total_vram_bytes > 0 {
                ((gpu_used_vram_bytes as f64 / gpu_total_vram_bytes as f64) * 100.0)
                    .clamp(0.0, 100.0)
            } else {
                0.0
            };

            let run_time = proc_info.run_time();
            let effective_run_time = if run_time > 0 {
                run_time
            } else {
                self.start_instant.elapsed().as_secs()
            };

            ProcessMetrics {
                pid: pid.as_u32(),
                name: proc_info.name().to_string_lossy().into_owned(),
                status: proc_info.status().to_string(),
                run_time_seconds: effective_run_time,
                cpu_usage_percent,
                raw_cpu_usage_percent,
                memory_bytes,
                virtual_memory_bytes,
                total_system_memory_bytes,
                memory_usage_percent,
                gpu_usage_percent,
                gpu_used_vram_bytes,
                gpu_total_vram_bytes,
                gpu_vram_usage_percent,
            }
        } else {
            ProcessMetrics {
                pid: pid.as_u32(),
                name: "Unknown Process".to_string(),
                status: "Unknown".to_string(),
                run_time_seconds: self.start_instant.elapsed().as_secs(),
                cpu_usage_percent: 0.0,
                raw_cpu_usage_percent: 0.0,
                memory_bytes: 0,
                virtual_memory_bytes: 0,
                total_system_memory_bytes,
                memory_usage_percent: 0.0,
                gpu_usage_percent: 0.0,
                gpu_used_vram_bytes: 0,
                gpu_total_vram_bytes,
                gpu_vram_usage_percent: 0.0,
            }
        }
    }
}

/// On iOS, `sysinfo` disables process enumeration due to App Store sandbox rules,
/// but querying the current process's own Mach task (`mach_task_self`) is 100% allowed.
#[cfg(target_os = "ios")]
fn query_ios_current_task_metrics() -> (f32, u64, u64) {
    unsafe {
        let task = libc::mach_task_self();
        let mut info: libc::mach_task_basic_info_data_t = std::mem::zeroed();
        let mut count = (std::mem::size_of::<libc::mach_task_basic_info_data_t>()
            / std::mem::size_of::<libc::natural_t>())
            as libc::mach_msg_type_number_t;

        let kr = libc::task_info(
            task,
            libc::MACH_TASK_BASIC_INFO,
            &mut info as *mut _ as libc::task_info_t,
            &mut count,
        );

        let (rss_bytes, virt_bytes) = if kr == libc::KERN_SUCCESS {
            (info.resident_size as u64, info.virtual_size as u64)
        } else {
            (0, 0)
        };

        let mut thread_list: libc::thread_act_array_t = std::ptr::null_mut();
        let mut thread_count: libc::mach_msg_type_number_t = 0;
        let mut total_cpu_pct: f32 = 0.0;

        if libc::task_threads(task, &mut thread_list, &mut thread_count) == libc::KERN_SUCCESS
            && !thread_list.is_null()
        {
            for i in 0..(thread_count as usize) {
                let thread = *thread_list.add(i);
                let mut tinfo: libc::thread_basic_info_data_t = std::mem::zeroed();
                let mut tcount = (std::mem::size_of::<libc::thread_basic_info_data_t>()
                    / std::mem::size_of::<libc::natural_t>())
                    as libc::mach_msg_type_number_t;
                if libc::thread_info(
                    thread,
                    libc::THREAD_BASIC_INFO as u32,
                    &mut tinfo as *mut _ as libc::thread_info_t,
                    &mut tcount,
                ) == libc::KERN_SUCCESS
                {
                    if (tinfo.flags & libc::TH_FLAGS_IDLE) == 0 {
                        total_cpu_pct +=
                            (tinfo.cpu_usage as f32 / libc::TH_USAGE_SCALE as f32) * 100.0;
                    }
                }
                libc::mach_port_deallocate(task, thread);
            }
            let alloc_size =
                (thread_count as usize) * std::mem::size_of::<libc::thread_t>();
            libc::vm_deallocate(
                task,
                thread_list as libc::vm_address_t,
                alloc_size as libc::vm_size_t,
            );
        }

        (total_cpu_pct, rss_bytes, virt_bytes)
    }
}

impl Default for EasyMonitoringEngine {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// C-ABI FFI Exports for Dart (`dart:ffi`)
// ============================================================================

/// Creates a new `EasyMonitoringEngine` instance on the heap and returns its opaque pointer.
/// Must be freed via `easy_monitoring_destroy`.
#[unsafe(no_mangle)]
pub extern "C" fn easy_monitoring_create() -> *mut EasyMonitoringEngine {
    let engine = Box::new(EasyMonitoringEngine::new());
    Box::into_raw(engine)
}

/// Destroys an `EasyMonitoringEngine` instance created by `easy_monitoring_create`.
///
/// # Safety
/// `handle` must be a valid pointer returned by `easy_monitoring_create` or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn easy_monitoring_destroy(handle: *mut EasyMonitoringEngine) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Polls CPU, Memory, GPU, and current process metrics using the provided
/// `EasyMonitoringEngine` handle and returns a newly allocated UTF-8 JSON C-string.
///
/// The caller must free the returned string using `easy_monitoring_free_string`.
///
/// # Safety
/// `handle` must be a valid pointer returned by `easy_monitoring_create`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn easy_monitoring_poll_json(
    handle: *mut EasyMonitoringEngine,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }

    let engine = unsafe { &mut *handle };
    let metrics = engine.poll();

    match serde_json::to_string(&metrics) {
        Ok(json) => match CString::new(json) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Polls CPU, Memory, and GPU metrics for a specific process (`pid`, or `0` for the current process)
/// and returns a newly allocated UTF-8 JSON C-string representing `ProcessMetrics`.
///
/// The caller must free the returned string using `easy_monitoring_free_string`.
///
/// # Safety
/// `handle` must be a valid pointer returned by `easy_monitoring_create`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn easy_monitoring_poll_process_json(
    handle: *mut EasyMonitoringEngine,
    pid: u32,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }

    let engine = unsafe { &mut *handle };
    let proc_metrics = engine.poll_process(if pid == 0 { None } else { Some(pid) });

    match serde_json::to_string(&proc_metrics) {
        Ok(json) => match CString::new(json) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Frees a C-string returned by `easy_monitoring_poll_json`,
/// `easy_monitoring_poll_process_json`, or `easy_monitoring_version`.
///
/// # Safety
/// `ptr` must be a valid pointer returned by this library or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn easy_monitoring_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

/// Returns the version of the native `easy_monitoring` Rust library.
/// Must be freed using `easy_monitoring_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn easy_monitoring_version() -> *mut c_char {
    CString::new(env!("CARGO_PKG_VERSION"))
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[test]
    fn test_engine_poll_and_ffi_lifecycle() {
        unsafe {
            let handle = easy_monitoring_create();
            assert!(!handle.is_null());

            let json_ptr = easy_monitoring_poll_json(handle);
            assert!(!json_ptr.is_null());

            let c_str = CStr::from_ptr(json_ptr);
            let json_str = c_str.to_str().expect("Valid UTF-8 JSON");
            println!("Polled JSON:\n{}", json_str);

            let parsed: SystemMetrics =
                serde_json::from_str(json_str).expect("Deserialize SystemMetrics");

            assert!(parsed.cpu.logical_cores > 0);
            assert!(parsed.cpu.usage_percent >= 0.0 && parsed.cpu.usage_percent <= 100.0);
            assert!(parsed.memory.total_memory_bytes > 0);
            assert!(parsed.memory.used_memory_bytes > 0);
            assert!(parsed.memory.usage_percent > 0.0 && parsed.memory.usage_percent <= 100.0);
            assert!(parsed.current_process.pid > 0);
            assert!(!parsed.current_process.name.is_empty());
            assert!(parsed.current_process.memory_bytes > 0);
            assert!(parsed.timestamp_ms > 0);

            easy_monitoring_free_string(json_ptr);

            let proc_json_ptr = easy_monitoring_poll_process_json(handle, 0);
            assert!(!proc_json_ptr.is_null());
            let proc_c_str = CStr::from_ptr(proc_json_ptr);
            let proc_parsed: ProcessMetrics = serde_json::from_str(
                proc_c_str.to_str().expect("Valid UTF-8 process JSON"),
            )
            .expect("Deserialize ProcessMetrics");
            assert_eq!(proc_parsed.pid, std::process::id());
            assert!(proc_parsed.memory_bytes > 0);
            easy_monitoring_free_string(proc_json_ptr);

            easy_monitoring_destroy(handle);
        }
    }
}
