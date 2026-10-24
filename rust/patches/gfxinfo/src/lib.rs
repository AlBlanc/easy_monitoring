#![doc = include_str!("../README.md")]

use std::{error::Error, fmt::Debug};

// The library we use for Nvidia is cross-platform
#[cfg(all(feature = "nvidia", not(target_os = "macos")))]
mod nvidia;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
mod platform {
  pub use crate::linux::*;
}

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
mod platform {
  pub use crate::windows::*;
}

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
mod platform {
  pub use crate::macos::*;
}

mod util;

pub trait Gpu: Debug {
  /// Get the GPU vendor (ie. AMD, Nvidia).
  fn vendor(&self) -> &str;
  // Get the GPU model (ie. Radeon RX 6800, GeForce RTX 3070).
  fn model(&self) -> &str;
  /// Get the GPU family (ie. Vega, Navi).
  fn family(&self) -> &str;
  /// Get the GPU device ID.
  fn device_id(&self) -> &u32;

  #[cfg(feature = "gpu_info")]
  fn info(&self) -> Box<dyn GpuInfo>;
}

/// Trait for providing GPU information. If any numbers return 0, they are likely unsupported or otherwise not available.
#[cfg(feature = "gpu_info")]
pub trait GpuInfo {
  /// Get the total amount of VRAM in bytes.
  fn total_vram(&self) -> u64;
  /// Get the amount of used VRAM in bytes.
  fn used_vram(&self) -> u64;
  /// Get the load percentage.
  fn load_pct(&self) -> u32;
  /// Get the GPU temperature in degrees mcelsius.
  fn temperature(&self) -> u32;
  /// Get the amount of VRAM in bytes used by a specific process (`pid`).
  fn process_used_vram(&self, _pid: u32) -> u64 {
    0
  }
  /// Get the GPU load percentage (`0..=100`) for a specific process (`pid`).
  fn process_load_pct(&self, _pid: u32) -> u32 {
    0
  }
}

/// Attempts to get the currently active GPU, using vendor-specific methods.
pub fn active_gpu() -> Result<Box<dyn Gpu>, Box<dyn Error>> {
  platform::active_gpu()
}
