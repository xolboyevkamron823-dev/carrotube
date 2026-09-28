#
# CocoaPods spec (used when Swift Package Manager is disabled for the app).
# Same sources as carro_native/Package.swift: Swift player + ObjC++ tap bridge + C++ DSP core.
#
Pod::Spec.new do |s|
  s.name             = 'carro_native'
  s.version          = '1.0.0'
  s.summary          = 'CarroTube native layer: Carrozzeria DSP engine, AVPlayer with DSP tap, IR capture.'
  s.description      = <<-DESC
Pioneer Carrozzeria style DSP (GEQ, crossover, time alignment, Sound Field reverb and
convolution, limiter) applied to every sample of AVPlayer playback via MTAudioProcessingTap.
                       DESC
  s.homepage         = 'https://github.com/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CarroTube' => 'dev@carrotube.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'carro_native/Sources/**/*.{h,m,mm,c,cpp,swift}'
  s.public_header_files = 'carro_native/Sources/CarroDSP/include/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.frameworks = 'AVFoundation', 'AVKit', 'MediaPlayer', 'MediaToolbox', 'CoreMedia'
  s.library = 'c++'
  s.resource_bundles = { 'carro_native_privacy' => ['carro_native/Sources/carro_native/PrivacyInfo.xcprivacy'] }

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/carro_native/Sources/CarroDSP/core"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) NDEBUG=1',
  }
  s.swift_version = '5.0'
end
