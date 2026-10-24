Pod::Spec.new do |s|
  s.name             = 'easy_monitoring'
  s.version          = '0.1.1'
  s.summary          = 'Real-time CPU, RAM, and GPU hardware monitoring library powered by Rust.'
  s.description      = <<-DESC
Cross-platform CPU, RAM, and GPU hardware monitoring library for Flutter using Rust sysinfo and gfxinfo.
                       DESC
  s.homepage         = 'https://github.com/AlBlanc/easy_monitoring'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alban' => 'alban@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '12.0'

  s.prepare_command  = 'bash Classes/resolve_native_ios.sh'
  s.vendored_libraries = 'Frameworks/libeasy_monitoring.a'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
