Pod::Spec.new do |s|
  s.name = 'ffmpeg_kit_min_gpl'
  s.version = '6.0.3-LTS'
  s.summary          = 'FFmpeg Kit for Flutter'
  s.description      = 'A Flutter plugin for running FFmpeg and FFprobe commands.'
  s.homepage         = 'https://github.com/arthenica/ffmpeg-kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ARTHENICA' => 'open-source@arthenica.com' }

  s.platform            = :osx
  s.requires_arc        = true
  s.static_framework    = true

  s.source              = { :path => '.' }
  s.source_files        = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  s.default_subspec = 'min-gpl-lts'

  s.dependency          'FlutterMacOS'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.prepare_command = <<-CMD
    download_url="https://github.com/meetleev/flutter-ffmpeg-kit/releases/download/6.0.3/ffmpeg-kit-macos-min-gpl-lts.zip" 
    if [ ! -d "./Frameworks" ]; then
        echo "Downloading from ${download_url}..."
        curl -L $download_url -o /tmp/ffmped_kit.zip
        unzip -o /tmp/ffmped_kit.zip -d Frameworks
    fi
  CMD

  s.subspec 'min' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-min', "6.0"
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'min-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-min', "6.0.LTS"
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'min-gpl' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    # ss.dependency 'ffmpeg-kit-macos-min-gpl', "6.0"
    ss.vendored_frameworks = 'Frameworks/*.framework'
    ss.macos.frameworks = 'VideoToolbox', 'AudioToolbox', 'AVKit', 'CoreAudio', 'CoreImage', 'OpenCL'
    ss.libraries = 'z', 'bz2', 'c++', 'iconv'
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'min-gpl-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    # ss.dependency 'ffmpeg-kit-macos-min-gpl', "6.0.LTS"
    ss.vendored_frameworks = 'Frameworks/*.framework'
    ss.macos.frameworks = 'VideoToolbox', 'AudioToolbox', 'AVKit', 'CoreAudio', 'CoreImage', 'OpenCL'
    ss.libraries = 'z', 'bz2', 'c++', 'iconv'
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'https' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    # ss.dependency 'ffmpeg-kit-macos-https', "6.0"
    ss.vendored_frameworks = 'Frameworks/*.framework'
    ss.macos.frameworks = 'VideoToolbox', 'AudioToolbox', 'AVKit', 'CoreAudio', 'CoreImage', 'OpenCL'
    ss.libraries = 'z', 'bz2', 'c++', 'iconv'
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'https-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    # ss.dependency 'ffmpeg-kit-macos-https', "6.0.LTS"
    ss.vendored_frameworks = 'Frameworks/*.framework'
    ss.macos.frameworks = 'VideoToolbox', 'AudioToolbox', 'AVKit', 'CoreAudio', 'CoreImage', 'OpenCL'
    ss.libraries = 'z', 'bz2', 'c++', 'iconv'
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'https-gpl' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-https-gpl', "6.0"
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'https-gpl-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-https-gpl', "6.0.LTS"
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'audio' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-audio', "6.0"
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'audio-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-audio', "6.0.LTS"
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'video' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-video', "6.0"
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'video-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-video', "6.0.LTS"
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'full' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-full', "6.0"
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'full-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-full', "6.0.LTS"
    ss.osx.deployment_target = '10.12'
  end

  s.subspec 'full-gpl' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-full-gpl', "6.0"
    ss.osx.deployment_target = '10.15'
  end

  s.subspec 'full-gpl-lts' do |ss|
    ss.source_files         = 'Classes/**/*'
    ss.public_header_files  = 'Classes/**/*.h'
    ss.dependency 'ffmpeg-kit-macos-full-gpl', "6.0.LTS"
    ss.osx.deployment_target = '10.12'
  end

end
