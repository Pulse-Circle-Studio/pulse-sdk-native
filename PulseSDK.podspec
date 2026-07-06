Pod::Spec.new do |s|
  s.name             = 'PulseSDK'
  s.version          = '0.1.0'
  s.summary          = 'Pulse analytics SDK for iOS — a reliable, ordered, persistent event queue with idempotent delivery.'
  s.description      = <<-DESC
    Pulse is a privacy-first analytics SDK. It does exactly two things: a
    reliable, ordered, persistent event queue with idempotent delivery, and
    identity (anonymous id, identify, reset). No auto-capture, no session
    replay, no fingerprinting — nothing is collected automatically.
  DESC
  s.homepage         = 'https://github.com/Pulse-Circle-Studio/pulse-sdk-native'
  s.license          = { :type => 'MIT', :text => 'Copyright (c) 2026 Pulse Circle Studio. Licensed under the MIT License.' }
  s.author           = { 'Pulse Circle Studio' => 'rost@pulsecircle.studio' }
  s.source           = { :git => 'https://github.com/Pulse-Circle-Studio/pulse-sdk-native.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions   = ['5.9']

  s.source_files     = 'ios/Sources/PulseSDK/**/*.swift'
  s.frameworks       = 'Foundation'
end
