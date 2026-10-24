use std::{error::Error, ptr::null_mut};

use core_foundation::dictionary::{CFDictionary, CFMutableDictionaryRef};
use core_foundation::number::CFNumber;
use core_foundation::string::CFString;
use core_foundation::{
  base::{CFTypeRef, TCFType, TCFTypeRef, kCFAllocatorDefault},
  data::{__CFData, CFData},
  dictionary::__CFDictionary,
  number::__CFNumber,
  string::__CFString,
};
use io_kit_sys::{
  IOIteratorNext, IOObjectRelease, IORegistryEntryCreateCFProperties,
  IORegistryEntryGetChildIterator, IOServiceGetMatchingServices, IOServiceMatching,
  kIOMasterPortDefault,
  types::{io_iterator_t, io_registry_entry_t},
};

use crate::util::pci::vendor_id_to_name;
use crate::{Gpu, GpuInfo};

pub enum DataType {
  Number,
  _String,
}

#[derive(Debug)]
pub struct MacGpu {
  vendor: String,
  model: String,
  family: String,
  device_id: u32,
}

impl Gpu for MacGpu {
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
    Box::new(MacGpuInfo {})
  }
}

#[cfg(feature = "gpu_info")]
pub struct MacGpuInfo {}

#[cfg(feature = "gpu_info")]
impl GpuInfo for MacGpuInfo {
  fn total_vram(&self) -> u64 {
    // Check if dedicated VRAM is reported in PerformanceStatistics ("VRAM,totalMB"),
    // otherwise return "Alloc system memory" (allocated unified GPU memory pool).
    if let Ok(vram_mb) = performance_stat("VRAM,totalMB", DataType::Number) {
      if vram_mb > 0 {
        return vram_mb * 1024 * 1024;
      }
    }
    performance_stat("Alloc system memory", DataType::Number).unwrap_or(0)
  }

  fn used_vram(&self) -> u64 {
    performance_stat("In use system memory", DataType::Number)
      .or_else(|_| performance_stat("vramUsedBytes", DataType::Number))
      .or_else(|_| performance_stat("Alloc system memory", DataType::Number))
      .unwrap_or(0)
  }

  fn load_pct(&self) -> u32 {
    performance_stat("Device Utilization %", DataType::Number)
      .or_else(|_| performance_stat("Renderer Utilization %", DataType::Number))
      .unwrap_or(0) as u32
  }

  fn temperature(&self) -> u32 {
    performance_stat("Temperature(C)", DataType::Number)
      .map(|t| (t as u32) * 1000)
      .unwrap_or(0)
  }

  fn process_used_vram(&self, pid: u32) -> u64 {
    query_macos_process_gpu_stats(pid, self.used_vram(), self.load_pct()).0
  }

  fn process_load_pct(&self, pid: u32) -> u32 {
    query_macos_process_gpu_stats(pid, self.used_vram(), self.load_pct()).1
  }
}

fn query_macos_process_gpu_stats(
  target_pid: u32,
  global_used_vram: u64,
  global_load_pct: u32,
) -> (u64, u32) {
  unsafe {
    let match_dict = IOServiceMatching(c"IOAccelerator".as_ptr());
    let mut itr: io_iterator_t = 0;
    if IOServiceGetMatchingServices(kIOMasterPortDefault, match_dict, &mut itr) != 0 {
      return (0, 0);
    }

    let pid_prefix_comma = format!("pid {},", target_pid);
    let pid_prefix_space = format!("pid {} ", target_pid);
    let mut total_clients: u64 = 0;
    let mut target_clients: u64 = 0;
    let mut explicit_pid_vram: u64 = 0;

    let mut entry: io_registry_entry_t;
    while {
      entry = IOIteratorNext(itr);
      entry != 0
    } {
      let mut child_itr: io_iterator_t = 0;
      let plane = b"IOService\0";
      if IORegistryEntryGetChildIterator(
        entry,
        plane.as_ptr() as *mut std::os::raw::c_char,
        &mut child_itr,
      ) == 0
      {
        let mut child: io_registry_entry_t;
        while {
          child = IOIteratorNext(child_itr);
          child != 0
        } {
          let mut child_dict_ref: CFMutableDictionaryRef = null_mut();
          if IORegistryEntryCreateCFProperties(
            child,
            &mut child_dict_ref,
            kCFAllocatorDefault,
            0,
          ) == 0
            && !child_dict_ref.is_null()
          {
            let child_dict: CFDictionary<CFString, CFTypeRef> =
              CFDictionary::wrap_under_create_rule(child_dict_ref);
            if let Some(creator_ptr) =
              child_dict.find(CFString::from_static_string("IOUserClientCreator"))
            {
              total_clients += 1;
              let creator_cf: CFString = CFString::wrap_under_get_rule(
                creator_ptr.as_void_ptr() as *const __CFString,
              );
              let creator_str = creator_cf.to_string();
              if creator_str.starts_with(&pid_prefix_comma)
                || creator_str.starts_with(&pid_prefix_space)
              {
                target_clients += 1;
                if let Some(mem_ptr) =
                  child_dict.find(CFString::from_static_string("In use system memory"))
                {
                  let num: CFNumber = CFNumber::wrap_under_get_rule(
                    mem_ptr.as_void_ptr() as *const __CFNumber,
                  );
                  if let Some(val) = num.to_i64() {
                    if val > 0 {
                      explicit_pid_vram = explicit_pid_vram.saturating_add(val as u64);
                    }
                  }
                }
              }
            }
          }
          IOObjectRelease(child);
        }
        IOObjectRelease(child_itr);
      }
      IOObjectRelease(entry);
    }
    IOObjectRelease(itr);

    if target_clients == 0 {
      return (0, 0);
    }

    let vram = if explicit_pid_vram > 0 {
      explicit_pid_vram
    } else if total_clients > 0 {
      (global_used_vram.saturating_mul(target_clients)) / total_clients
    } else {
      0
    };

    let load = if total_clients > 0 && global_load_pct > 0 {
      ((global_load_pct as u64).saturating_mul(target_clients) / total_clients) as u32
    } else {
      0
    };

    (vram, load.min(100))
  }
}

pub fn active_gpu() -> Result<Box<dyn Gpu>, Box<dyn Error>> {
  unsafe {
    let match_dict = IOServiceMatching(c"IOAccelerator".as_ptr());
    let mut itr: io_iterator_t = 0;
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, match_dict, &mut itr);

    if result != 0 {
      return Err("Failed to get IOAccelerator services".into());
    }

    let mut entry: io_registry_entry_t;

    while {
      entry = IOIteratorNext(itr);
      entry != 0
    } {
      let mut service_dict: CFMutableDictionaryRef = null_mut();

      if IORegistryEntryCreateCFProperties(entry, &mut service_dict, kCFAllocatorDefault, 0) != 0
        || service_dict.is_null()
      {
        IOObjectRelease(entry);
        continue;
      }

      let dict: CFDictionary<CFString, CFTypeRef> =
        CFDictionary::wrap_under_create_rule(service_dict);
      let vendor = dict.find(CFString::from_static_string("vendor-id"));
      let model = dict.find(CFString::from_static_string("model"));
      let family = "N/A";

      if vendor.is_none() || model.is_none() {
        IOObjectRelease(entry);
        continue;
      }

      let vendor_ptr = vendor.unwrap();
      let model_ptr = model.unwrap();
      let model: CFString =
        CFString::wrap_under_get_rule(model_ptr.as_void_ptr() as *const __CFString);
      let vendor: CFData = CFData::wrap_under_get_rule(vendor_ptr.as_void_ptr() as *const __CFData);
      let mut vendor = vendor.bytes().to_vec();
      vendor.reverse();

      let vendor = vendor
        .iter()
        .map(|b| {
          if *b != 0 {
            return format!("{:02x}", b);
          }

          "".to_string()
        })
        .collect::<Vec<String>>()
        .join("");

      IOObjectRelease(entry);
      IOObjectRelease(itr);

      return Ok(Box::new(MacGpu {
        vendor: vendor_id_to_name(u16::from_str_radix(&vendor, 16).unwrap_or(0)).to_string(),
        model: model.to_string(),
        family: family.to_string(),
        device_id: 0x0,
      }));
    }

    IOObjectRelease(itr);
  }

  Err("No GPU found".into())
}

pub fn performance_stat(stat: &'static str, data_type: DataType) -> Result<u64, Box<dyn Error>> {
  unsafe {
    let match_dict = IOServiceMatching(c"IOAccelerator".as_ptr());
    let mut itr: io_iterator_t = 0;
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, match_dict, &mut itr);

    if result != 0 {
      return Err("Failed to get IOAccelerator services".into());
    }

    let mut entry: io_registry_entry_t;

    while {
      entry = IOIteratorNext(itr);
      entry != 0
    } {
      let mut service_dict: CFMutableDictionaryRef = null_mut();

      if IORegistryEntryCreateCFProperties(entry, &mut service_dict, kCFAllocatorDefault, 0) != 0
        || service_dict.is_null()
      {
        IOObjectRelease(entry);
        continue;
      }

      let dict: CFDictionary<CFString, CFTypeRef> =
        CFDictionary::wrap_under_create_rule(service_dict);
      let perf_properties = dict.find(CFString::from_static_string("PerformanceStatistics"));

      if perf_properties.is_none() {
        IOObjectRelease(entry);
        continue;
      }

      // IMPORTANT: dict.find() follows CoreFoundation's Get Rule (unretained pointer).
      // Using wrap_under_create_rule here previously caused a double-free crash on macOS.
      let perf_properties: CFDictionary<CFString, CFTypeRef> = CFDictionary::wrap_under_get_rule(
        perf_properties.unwrap().as_void_ptr() as *const __CFDictionary,
      );
      let stat_val = perf_properties.find(CFString::from_static_string(stat));

      if stat_val.is_none() {
        IOObjectRelease(entry);
        continue;
      }

      let stat_val = stat_val.unwrap();

      let result_val = match data_type {
        DataType::Number => {
          let num: CFNumber =
            CFNumber::wrap_under_get_rule(stat_val.as_void_ptr() as *const __CFNumber);
          let stat_i64 = num.to_i64().unwrap_or(0);
          Ok(stat_i64.try_into().unwrap_or(0))
        }
        _ => Err("Unsupported data type".into()),
      };

      IOObjectRelease(entry);
      IOObjectRelease(itr);
      return result_val;
    }

    IOObjectRelease(itr);
  }

  Err("Failed to get performance stat".into())
}
