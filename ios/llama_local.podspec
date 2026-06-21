Pod::Spec.new do |s|
  s.name             = 'llama_local'
  s.version          = '0.9.0'
  s.summary          = 'Local llama.cpp xcframework for on-device LLM POC'
  s.description      = 'Links llama.xcframework from ios/Frameworks for llama_cpp_dart on-device inference.'
  s.homepage         = 'https://github.com/netdur/llama_cpp_dart'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Bravo AAC' => 'dev@local' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.vendored_frameworks = 'Frameworks/llama.xcframework'
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_llama_backend_init'
  }
  s.requires_arc     = true
end
