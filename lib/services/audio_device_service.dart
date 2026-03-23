// Conditional export for AudioDeviceService
// Uses stub implementation by default, switches to web implementation on web
export 'audio_device_service_stub.dart'
    if (dart.library.html) 'audio_device_service_web.dart';