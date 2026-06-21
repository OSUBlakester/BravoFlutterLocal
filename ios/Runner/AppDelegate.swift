import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let audioRoutingChannel = "audio_routing"
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("✅ AppDelegate: Application launched")
    GeneratedPluginRegistrant.register(with: self)
    print("✅ AppDelegate: Plugins registered")
    
    // Set up audio routing method channel
    guard let controller = window?.rootViewController as? FlutterViewController else {
      fatalError("rootViewController is not type FlutterViewController")
    }
    
    let audioChannel = FlutterMethodChannel(
      name: audioRoutingChannel,
      binaryMessenger: controller.binaryMessenger
    )
    
    audioChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "forceSpeaker":
        self?.forceSpeaker(result: result)
      case "resetToDefault":
        self?.resetToDefault(result: result)
      case "setupOptimalAudioSession":
        self?.setupOptimalAudioSession(result: result)
      case "routeToPersonal":
        self?.routeToPersonal(result: result)
      case "captureCurrentVolume":
        self?.captureCurrentVolume(call: call, result: result)
      case "checkMicrophonePermission":
        self?.checkMicrophonePermission(result: result)
      case "requestMicrophonePermission":
        self?.requestMicrophonePermission(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    print("✅ AppDelegate: Audio routing channel registered")
    
    // Register for audio route change notifications (BT disconnect/reconnect)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    print("✅ AppDelegate: Audio route change observer registered")
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    return [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
  }
  
  // MARK: - Audio Route Change Observer
  
  private var isReestablishingSession = false
  
  /// Handles audio route changes (Bluetooth connect/disconnect/reconnect).
  /// Re-establishes the audio session with BT A2DP support so volume settings
  /// applied via software (player.setVolume / flutterTts.setVolume) persist
  /// regardless of hardware route changes.
  @objc private func handleRouteChange(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
      return
    }
    
    // Only handle actual device connect/disconnect — NOT category changes.
    // Responding to .categoryChange would create an infinite loop because
    // reestablishAudioSession() itself changes the category.
    guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else {
      return
    }
    
    // Prevent re-entrant calls
    guard !isReestablishingSession else { return }
    
    let audioSession = AVAudioSession.sharedInstance()
    let currentRoute = audioSession.currentRoute
    let outputPortNames = currentRoute.outputs.map { $0.portName }
    let outputPortTypes = currentRoute.outputs.map { $0.portType.rawValue }
    
    switch reason {
    case .newDeviceAvailable:
      print("✅ iOS Audio Route Change: New device available (e.g., BT reconnected)")
      print("   Current outputs: \(outputPortNames) (types: \(outputPortTypes))")
    case .oldDeviceUnavailable:
      print("✅ iOS Audio Route Change: Device disconnected")
      print("   Current outputs: \(outputPortNames) (types: \(outputPortTypes))")
    default:
      break
    }
    
    reestablishAudioSession()
  }
  
  /// Re-establish the audio session with Bluetooth A2DP support after a route change.
  /// This ensures the session is properly configured for the new audio route
  /// so that software volume (from admin settings) continues to be applied correctly.
  private func reestablishAudioSession() {
    isReestablishingSession = true
    defer { isReestablishingSession = false }
    
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try audioSession.setActive(true)
      // Remove any speaker override so audio goes to the connected BT device
      try audioSession.overrideOutputAudioPort(.none)
      
      let currentRoute = audioSession.currentRoute
      let outputPortNames = currentRoute.outputs.map { $0.portName }
      print("✅ iOS Audio: Re-established audio session after route change (outputs: \(outputPortNames))")
    } catch {
      print("❌ iOS Audio: Failed to re-establish session after route change: \(error.localizedDescription)")
    }
  }
  
  // MARK: - Audio Routing Methods
  
  /// Set up an optimal audio session that supports both built-in speaker and Bluetooth A2DP output.
  /// This should be called once during initialization instead of forceSpeaker.
  private func setupOptimalAudioSession(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      
      // Configure audio session for playback+recording with Bluetooth A2DP support
      // .defaultToSpeaker: routes to speaker (not earpiece) when no external device
      // .allowBluetooth: allows HFP Bluetooth (low-quality, for calls)
      // .allowBluetoothA2DP: allows A2DP Bluetooth (high-quality, for speakers/headphones)
      try audioSession.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try audioSession.setActive(true)
      
      // Do NOT override output port — let the system use the best available route
      // (Bluetooth A2DP if connected, otherwise built-in speaker)
      
      let currentRoute = audioSession.currentRoute
      let outputPortNames = currentRoute.outputs.map { $0.portName }
      let outputPortTypes = currentRoute.outputs.map { $0.portType.rawValue }
      print("✅ iOS Audio: Optimal audio session configured")
      print("   Current outputs: \(outputPortNames) (types: \(outputPortTypes))")
      result(true)
    } catch {
      print("❌ iOS Audio: Failed to setup optimal audio session - \(error.localizedDescription)")
      result(FlutterError(code: "AUDIO_ERROR", message: "Failed to setup optimal audio session: \(error.localizedDescription)", details: nil))
    }
  }
  
  /// Force audio output to the built-in speaker (for system announcements).
  /// This overrides Bluetooth and routes directly to the device speaker.
  private func forceSpeaker(result: @escaping FlutterResult) {
    let audioSession = AVAudioSession.sharedInstance()

    // First attempt: ensure category/active state supports output override.
    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try audioSession.setActive(true)
      try audioSession.overrideOutputAudioPort(.speaker)

      let currentRoute = audioSession.currentRoute
      let outputPortNames = currentRoute.outputs.map { $0.portName }
      print("✅ iOS Audio: Forced speaker output (outputs: \(outputPortNames))")
      result(true)
      return
    } catch {
      print("⚠️ iOS Audio: forceSpeaker primary attempt failed - \(error.localizedDescription)")
    }

    // Second attempt: clear override, reactivate, then re-apply speaker override.
    do {
      try audioSession.overrideOutputAudioPort(.none)
      try audioSession.setActive(true)
      try audioSession.overrideOutputAudioPort(.speaker)

      let currentRoute = audioSession.currentRoute
      let outputPortNames = currentRoute.outputs.map { $0.portName }
      print("✅ iOS Audio: Forced speaker output on retry (outputs: \(outputPortNames))")
      result(true)
    } catch {
      // Do not throw FlutterError here. Dart side treats this as a hard failure and
      // falls back to local TTS, which causes the wrong first-announcement voice path.
      // Returning false keeps the backend path alive while still logging diagnostics.
      print("❌ iOS Audio: Failed to force speaker after retry - \(error.localizedDescription)")
      result(false)
    }
  }
  
  /// Route audio to the personal device (Bluetooth/headphones) by removing speaker override.
  /// Keeps the audio session active to maintain Bluetooth connection.
  private func routeToPersonal(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      // Directly override port without changing category/active state to prevent background audio session interruptions
      try audioSession.overrideOutputAudioPort(.none)
      let currentRoute = audioSession.currentRoute
      let outputPortNames = currentRoute.outputs.map { $0.portName }
      print("✅ iOS Audio: Routed to personal device (outputs: \(outputPortNames)) (direct override)")
      result(true)
    } catch {
      print("❌ iOS Audio: Failed to route to personal - \(error.localizedDescription)")
      result(FlutterError(code: "AUDIO_ERROR", message: "Failed to route to personal: \(error.localizedDescription)", details: nil))
    }
  }
  
  /// Reset audio routing to default (removes speaker override, keeps session active).
  /// Does NOT deactivate the session to preserve Bluetooth connections.
  private func resetToDefault(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      
      // Reset to default output (allows Bluetooth/headphones)
      try audioSession.overrideOutputAudioPort(.none)
      
      // Keep session active to maintain Bluetooth connection state.
      // Previously we called setActive(false) here which was too aggressive
      // and would disrupt Bluetooth reconnection and volume state.
      
      let currentRoute = audioSession.currentRoute
      let outputPortNames = currentRoute.outputs.map { $0.portName }
      print("✅ iOS Audio: Reset to default routing (outputs: \(outputPortNames))")
      result(true)
    } catch {
      print("❌ iOS Audio: Failed to reset audio - \(error.localizedDescription)")
      result(FlutterError(code: "AUDIO_ERROR", message: "Failed to reset audio: \(error.localizedDescription)", details: nil))
    }
  }

  /// Check microphone permission status for iOS speech recognition flows.
  /// Returns one of: granted, denied, undetermined.
  private func checkMicrophonePermission(result: @escaping FlutterResult) {
    let recordPermission = AVAudioSession.sharedInstance().recordPermission
    switch recordPermission {
    case .granted:
      result("granted")
    case .denied:
      result("denied")
    case .undetermined:
      result("undetermined")
    @unknown default:
      result("undetermined")
    }
  }

  /// Request microphone permission and return granted/denied.
  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async {
        result(granted ? "granted" : "denied")
      }
    }
  }
  
  /// Capture the current device output volume (0-10 scale).
  /// Uses AVAudioSession.outputVolume (0.0-1.0) and scales to 0-10 for the app.
  private func captureCurrentVolume(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let audioSession = AVAudioSession.sharedInstance()
    let outputVolume = audioSession.outputVolume // 0.0 to 1.0
    let scaledVolume = Int(round(Double(outputVolume) * 10.0)) // 0-10 scale
    
    let args = call.arguments as? [String: Any]
    let isPersonal = args?["isPersonal"] as? Bool ?? true
    
    print("✅ iOS Audio: Captured \(isPersonal ? "personal" : "system") volume: \(scaledVolume)/10 (raw: \(outputVolume))")
    result(scaledVolume)
  }
}


