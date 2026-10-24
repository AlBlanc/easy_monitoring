use serde::Deserialize;
use std::error::Error;
use windows::{
  Win32::System::Performance::{
    PDH_FMT_DOUBLE, PDH_HCOUNTER, PDH_HQUERY, PdhAddCounterW, PdhCloseQuery, PdhCollectQueryData,
    PdhGetFormattedCounterValue, PdhOpenQueryW,
  },
  core::PCWSTR,
};
use wmi::{COMLibrary, WMIConnection};

use crate::{Gpu, GpuInfo};

#[cfg(feature = "nvidia")]
use crate::nvidia;

#[derive(Debug)]
pub struct WindowsGpu {
  total_vram: u64,

  vendor: String,
  model: String,
  family: String,
  device_id: u32,
}

impl Gpu for WindowsGpu {
  fn vendor(&self) -> &str {
    &self.vendor
  }

  fn model(&self) -> &str {
    &self.model
  }

  fn family(&self) -> &str {
    &self.family
  }

  fn device_id(&self) -> &u32 {
    &self.device_id
  }

  #[cfg(feature = "gpu_info")]
  fn info(&self) -> Box<dyn GpuInfo> {
    Box::new(WindowsGpuInfo {
      total_vram: self.total_vram,
    })
  }
}

#[cfg(feature = "gpu_info")]
pub struct WindowsGpuInfo {
  // This is grabbed in the WindowsGpu struct
  total_vram: u64,
}

#[cfg(feature = "gpu_info")]
impl GpuInfo for WindowsGpuInfo {
  fn total_vram(&self) -> u64 {
    self.total_vram
  }

  fn used_vram(&self) -> u64 {
    unsafe { counter_value("\\GPU Adapter Memory(*)\\Dedicated Usage".to_string()).unwrap_or(0) }
  }

  fn load_pct(&self) -> u32 {
    unsafe {
      counter_value("\\GPU Engine(*)\\Utilization Percentage".to_string()).unwrap_or(0) as u32
    }
  }

  fn temperature(&self) -> u32 {
    // TODO: fix
    0
  }

  fn process_used_vram(&self, pid: u32) -> u64 {
    unsafe {
      counter_value(format!(
        "\\GPU Process Memory(pid_{}_*)\\Dedicated Usage",
        pid
      ))
      .or_else(|_| {
        counter_value(format!("\\GPU Process Memory(pid_{}_*)\\Local Usage", pid))
      })
      .unwrap_or(0)
    }
  }

  fn process_load_pct(&self, pid: u32) -> u32 {
    unsafe {
      counter_value(format!(
        "\\GPU Engine(pid_{}_*)\\Utilization Percentage",
        pid
      ))
      .unwrap_or(0) as u32
    }
  }
}

#[derive(Deserialize)]
#[serde(rename = "Win32_VideoController")]
#[serde(rename_all = "PascalCase")]
struct WMIGpu {
  name: String,
  video_processor: String,
  adapter_compatibility: String,
  device_id: String,
  adapter_ram: u32,
}

pub fn active_gpu() -> Result<Box<dyn Gpu>, Box<dyn Error>> {
  // Prefer using the easy Nvidia library
  #[cfg(feature = "nvidia")]
  {
    let gpu = nvidia::active_gpu();
    if let Ok(gpu) = gpu {
      return Ok(Box::new(gpu));
    }
  }

  let com = COMLibrary::new()?;
  let wmi = WMIConnection::new(com)?;
  let gpu: Vec<WMIGpu> = wmi.raw_query("SELECT * FROM Win32_VideoController")?;

  let gpu = match gpu.first() {
    Some(gpu) => gpu,
    None => return Err("No GPU found".into()),
  };

  Ok(Box::new(WindowsGpu {
    total_vram: gpu.adapter_ram as u64,

    vendor: gpu.video_processor.clone(),
    model: gpu.name.clone(),
    family: gpu.adapter_compatibility.clone(),
    // TODO: fix
    device_id: 0x0,
  }))
}

pub unsafe fn counter_value(counter_path: String) -> Result<u64, Box<dyn Error>> {
  let mut query = PDH_HQUERY::default();
  let status = unsafe { PdhOpenQueryW(None, 0, &mut query) };

  if status != 0 {
    return Err(format!("Could not open query: {}", status).into());
  }

  let counter_path_utf16: Vec<u16> = counter_path
    .encode_utf16()
    .chain(std::iter::once(0))
    .collect();
  let counter_path_pcwstr = PCWSTR(counter_path_utf16.as_ptr());

  let mut counter = PDH_HCOUNTER::default();

  let status = unsafe { PdhAddCounterW(query, counter_path_pcwstr, 0, &mut counter) };

  if status != 0 {
    let _ = unsafe { PdhCloseQuery(query) };
    return Err(format!("Could not add counter: {}", status).into());
  }

  let status = unsafe { PdhCollectQueryData(query) };

  if status != 0 {
    let _ = unsafe { PdhCloseQuery(query) };
    return Err(format!("Could not collect query data: {}", status).into());
  }

  let mut value = std::mem::zeroed();
  let status = unsafe { PdhGetFormattedCounterValue(counter, PDH_FMT_DOUBLE, None, &mut value) };

  if status != 0 {
    let _ = unsafe { PdhCloseQuery(query) };
    return Err(format!("Could not get raw counter value: {}", status).into());
  }

  let raw_value = unsafe { value.Anonymous.doubleValue.round() as u64 };

  // Close query
  let status = unsafe { PdhCloseQuery(query) };

  if status != 0 {
    return Err(format!("Could not close query: {}", status).into());
  }

  Ok(raw_value)
}
