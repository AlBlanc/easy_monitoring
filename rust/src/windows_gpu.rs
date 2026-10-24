#[cfg(target_os = "windows")]
use std::slice;
use windows::{
    core::PCWSTR,
    Win32::System::Performance::{
        PdhAddCounterW, PdhAddEnglishCounterW, PdhCloseQuery, PdhCollectQueryData,
        PdhGetFormattedCounterArrayW, PdhOpenQueryW, PDH_FMT_COUNTERVALUE_ITEM_W, PDH_FMT_DOUBLE,
        PDH_FMT_LARGE, PDH_HCOUNTER, PDH_HQUERY,
    },
};

#[derive(Debug, Default, Clone)]
pub struct GpuSample {
    pub total_usage_percent: f64,
    pub process_usage_percent: f64,
    pub used_vram_bytes: u64,
}

pub struct WindowsGpuMonitor {
    query: PDH_HQUERY,
    engine_counter: Option<PDH_HCOUNTER>,
    dedicated_vram_counter: Option<PDH_HCOUNTER>,
    shared_vram_counter: Option<PDH_HCOUNTER>,
    // 8-byte aligned buffer to hold counter value items and their strings
    buffer: Vec<u64>,
}

unsafe impl Send for WindowsGpuMonitor {}
unsafe impl Sync for WindowsGpuMonitor {}

impl WindowsGpuMonitor {
    pub fn new() -> Option<Self> {
        unsafe {
            let mut query = PDH_HQUERY::default();
            let status = PdhOpenQueryW(None, 0, &mut query);
            if status != 0 {
                return None;
            }

            let engine_counter = Self::add_counter(query, "\\GPU Engine(*)\\Utilization Percentage");
            let dedicated_vram_counter =
                Self::add_counter(query, "\\GPU Adapter Memory(*)\\Dedicated Usage");
            let shared_vram_counter =
                Self::add_counter(query, "\\GPU Adapter Memory(*)\\Shared Usage");

            // Baseline sample so the next poll calculates the time delta
            let _ = PdhCollectQueryData(query);

            Some(Self {
                query,
                engine_counter,
                dedicated_vram_counter,
                shared_vram_counter,
                buffer: vec![0u64; 4096],
            })
        }
    }

    unsafe fn add_counter(query: PDH_HQUERY, path_str: &str) -> Option<PDH_HCOUNTER> {
        let utf16: Vec<u16> = path_str.encode_utf16().chain(std::iter::once(0)).collect();
        let pcwstr = PCWSTR(utf16.as_ptr());
        let mut counter = PDH_HCOUNTER::default();

        let mut status = unsafe { PdhAddEnglishCounterW(query, pcwstr, 0, &mut counter) };
        if status != 0 {
            status = unsafe { PdhAddCounterW(query, pcwstr, 0, &mut counter) };
        }

        if status == 0 {
            Some(counter)
        } else {
            None
        }
    }

    pub fn poll(&mut self, target_pid: u32) -> GpuSample {
        unsafe {
            let status = PdhCollectQueryData(self.query);
            if status != 0 {
                return GpuSample::default();
            }

            let (total_usage_percent, process_usage_percent) = if let Some(counter) = self.engine_counter {
                self.sample_engine_usage(counter, target_pid)
            } else {
                (0.0, 0.0)
            };

            let dedicated_vram = self
                .dedicated_vram_counter
                .map(|c| self.sample_memory_counter(c))
                .unwrap_or(0);

            let shared_vram = self
                .shared_vram_counter
                .map(|c| self.sample_memory_counter(c))
                .unwrap_or(0);

            let used_vram_bytes = if dedicated_vram > 0 {
                dedicated_vram
            } else {
                shared_vram
            };

            GpuSample {
                total_usage_percent,
                process_usage_percent,
                used_vram_bytes,
            }
        }
    }

    unsafe fn sample_engine_usage(
        &mut self,
        counter: PDH_HCOUNTER,
        target_pid: u32,
    ) -> (f64, f64) {
        let mut buffer_size = (self.buffer.len() * std::mem::size_of::<u64>()) as u32;
        let mut item_count = 0u32;

        let mut status = unsafe {
            PdhGetFormattedCounterArrayW(
                counter,
                PDH_FMT_DOUBLE,
                &mut buffer_size,
                &mut item_count,
                Some(self.buffer.as_mut_ptr() as *mut _),
            )
        };

        if status != 0 && buffer_size > 0 {
            let required_u64s = (buffer_size as usize + 7) / 8;
            self.buffer.resize(required_u64s, 0);
            status = unsafe {
                PdhGetFormattedCounterArrayW(
                    counter,
                    PDH_FMT_DOUBLE,
                    &mut buffer_size,
                    &mut item_count,
                    Some(self.buffer.as_mut_ptr() as *mut _),
                )
            };
        }

        if status != 0 || item_count == 0 {
            return (0.0, 0.0);
        }

        let items = unsafe {
            slice::from_raw_parts(
                self.buffer.as_ptr() as *const PDH_FMT_COUNTERVALUE_ITEM_W,
                item_count as usize,
            )
        };

        let pid_prefix = format!("pid_{}_", target_pid);
        let pid_prefix_u16: Vec<u16> = pid_prefix.encode_utf16().collect();

        let mut total_load = 0.0;
        let mut proc_load = 0.0;

        for item in items {
            let val = unsafe { item.FmtValue.Anonymous.doubleValue };
            if !val.is_finite() || val <= 0.0 {
                continue;
            }

            total_load += val;

            if !item.szName.is_null() && !pid_prefix_u16.is_empty() {
                let name_ptr = item.szName.0;
                let mut matches = true;
                for (i, &expected) in pid_prefix_u16.iter().enumerate() {
                    let c = unsafe { *name_ptr.add(i) };
                    if c == 0 || c != expected {
                        matches = false;
                        break;
                    }
                }
                if matches {
                    proc_load += val;
                }
            }
        }

        (
            total_load.clamp(0.0, 100.0),
            proc_load.clamp(0.0, 100.0),
        )
    }

    unsafe fn sample_memory_counter(&mut self, counter: PDH_HCOUNTER) -> u64 {
        let mut buffer_size = (self.buffer.len() * std::mem::size_of::<u64>()) as u32;
        let mut item_count = 0u32;

        let mut status = unsafe {
            PdhGetFormattedCounterArrayW(
                counter,
                PDH_FMT_LARGE,
                &mut buffer_size,
                &mut item_count,
                Some(self.buffer.as_mut_ptr() as *mut _),
            )
        };

        if status != 0 && buffer_size > 0 {
            let required_u64s = (buffer_size as usize + 7) / 8;
            self.buffer.resize(required_u64s, 0);
            status = unsafe {
                PdhGetFormattedCounterArrayW(
                    counter,
                    PDH_FMT_LARGE,
                    &mut buffer_size,
                    &mut item_count,
                    Some(self.buffer.as_mut_ptr() as *mut _),
                )
            };
        }

        if status != 0 || item_count == 0 {
            return 0;
        }

        let items = unsafe {
            slice::from_raw_parts(
                self.buffer.as_ptr() as *const PDH_FMT_COUNTERVALUE_ITEM_W,
                item_count as usize,
            )
        };

        let mut total_bytes = 0u64;
        for item in items {
            let val = unsafe { item.FmtValue.Anonymous.largeValue };
            if val > 0 {
                total_bytes += val as u64;
            }
        }

        total_bytes
    }
}

impl Drop for WindowsGpuMonitor {
    fn drop(&mut self) {
        unsafe {
            let _ = PdhCloseQuery(self.query);
        }
    }
}
