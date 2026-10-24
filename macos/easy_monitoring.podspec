Pod::Spec.new do |s|
  s.name             = 'easy_monitoring'
  s.version          = '0.1.0'
  s.summary          = 'Real-time CPU, RAM, and GPU hardware monitoring library powered by Rust.'
  s.description      = <<-DESC
Cross-platform CPU, RAM, and GPU hardware monitoring library for Flutter using Rust sysinfo and gfxinfo.
                       DESC
  s.homepage         = 'https://github.com/AlBlanc/easy_monitoring'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alban' => 'alban@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :osx, '10.15'

  s.prepare_command  = 'bash Classes/resolve_native_macos.sh'
  s.vendored_libraries = 'Frameworks/libeasy_monitoring.dylib'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks @loader_path/Frameworks'
  }
  s.swift_version = '5.0'
end
