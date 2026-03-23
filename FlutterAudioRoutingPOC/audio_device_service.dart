import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_device.dart';

// For web platform
import 'dart:html' as html show window;
import 'dart:js_util' as js_util;

class AudioDeviceService {
  static const platform = MethodChannel('audio_routing');
  
  // Storage keys
  static const String _personalSpeakerKey = 'bravoPersonalSpeakerId';
  static const String _systemSpeakerKey = 'bravoSystemSpeakerId';

  List<AudioDevice> _availableDevices = [];
  String _personalSpeakerId = 'default';
  String _systemSpeakerId = 'default';

  // Getters
  List<AudioDevice> get availableDevices => _availableDevices;
  String get personalSpeakerId => _personalSpeakerId;
  String get systemSpeakerId => _systemSpeakerId;

  // Initialize the service
  Future<void> initialize() async {
    await _loadSavedPreferences();
    await _loadAvailableDevices();
  }

  // Load saved preferences from local storage
  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _personalSpeakerId = prefs.getString(_personalSpeakerKey) ?? 'default';
      _systemSpeakerId = prefs.getString(_systemSpeakerKey) ?? 'default';
      print('Loaded saved preferences: personal=$_personalSpeakerId, system=$_systemSpeakerId');
    } catch (e) {
      print('Error loading preferences: $e');
    }
  }

  // Save preferences to local storage
  Future<void> savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_personalSpeakerKey, _personalSpeakerId);
      await prefs.setString(_systemSpeakerKey, _systemSpeakerId);
      print('Saved preferences: personal=$_personalSpeakerId, system=$_systemSpeakerId');
    } catch (e) {
      print('Error saving preferences: $e');
    }
  }

  // Set personal speaker device
  void setPersonalSpeaker(String deviceId) {
    print('Setting personal speaker to: $deviceId');
    _personalSpeakerId = deviceId;
  }

  // Set system speaker device
  void setSystemSpeaker(String deviceId) {
    print('Setting system speaker to: $deviceId');
    _systemSpeakerId = deviceId;
  }

  // Load available audio devices based on platform
  Future<void> _loadAvailableDevices() async {
    _availableDevices = [
      AudioDevice(id: 'default', name: 'Default Speaker', kind: 'audiooutput')
    ];

    if (kIsWeb) {
      await _loadWebDevices();
    } else if (Platform.isWindows) {
      await _loadWindowsDevices();
    } else if (Platform.isIOS || Platform.isAndroid) {
      // For mobile, we'll use the existing platform channel approach
      // Just return default for now, since routing is handled differently
      print('Mobile platform: Using default audio routing');
    }
  }

  // Load devices for web platform using Web Audio API
  Future<void> _loadWebDevices() async {
    try {
      // Call our JavaScript bridge to get devices
      final jsGetDevices = js_util.getProperty(html.window, 'getAudioDevices');
      if (jsGetDevices != null) {
        final result = await js_util.promiseToFuture(js_util.callMethod(jsGetDevices, 'call', []));
        
        print('Web: Raw result from JavaScript: $result');
        print('Web: Result type: ${result.runtimeType}');
        
        if (result != null) {
          _availableDevices.clear();
          
          // Convert the JavaScript result to Dart using js_util.dartify
          final dartResult = js_util.dartify(result);
          print('Web: Dartified result: $dartResult');
          print('Web: Dartified type: ${dartResult.runtimeType}');
          
          if (dartResult is List) {
            print('Web: Processing ${dartResult.length} devices');
            
            for (int i = 0; i < dartResult.length; i++) {
              try {
                final deviceData = dartResult[i];
                print('Web: Processing device $i: $deviceData');
                
                if (deviceData is Map) {
                  final id = deviceData['id']?.toString() ?? 'unknown-$i';
                  final name = deviceData['name']?.toString() ?? 'Unknown Device $i';
                  final kind = deviceData['kind']?.toString() ?? 'audiooutput';
                  
                  _availableDevices.add(AudioDevice(
                    id: id,
                    name: name,
                    kind: kind,
                  ));
                  print('Web: Added device: $name ($id)');
                } else {
                  print('Web: Device $i is not a Map: ${deviceData.runtimeType}');
                }
              } catch (e) {
                print('Web: Error processing device $i: $e');
              }
            }
          } else {
            print('Web: Dartified result is not a List: ${dartResult.runtimeType}');
            // Fallback to default only
            _availableDevices.add(AudioDevice(id: 'default', name: 'Default Speaker', kind: 'audiooutput'));
          }
        } else {
          print('Web: JavaScript returned null result');
          _availableDevices.add(AudioDevice(id: 'default', name: 'Default Speaker', kind: 'audiooutput'));
        }
      } else {
        print('Web: JavaScript getAudioDevices function not found');
        _availableDevices.add(AudioDevice(id: 'default', name: 'Default Speaker', kind: 'audiooutput'));
      }
      
      print('Web: Final device count: ${_availableDevices.length}');
      for (final device in _availableDevices) {
        print('Web: Device: ${device.name} (${device.id})');
      }
    } catch (e) {
      print('Error loading web audio devices: $e');
      print('Error stack trace: ${StackTrace.current}');
      // Fallback to default device only
      _availableDevices = [
        AudioDevice(id: 'default', name: 'Default Speaker', kind: 'audiooutput')
      ];
    }
  }

  // Load devices for Windows platform using platform channels
  Future<void> _loadWindowsDevices() async {
    try {
      final result = await platform.invokeMethod('getAudioDevices');
      if (result is List) {
        for (final deviceMap in result) {
          if (deviceMap is Map) {
            _availableDevices.add(AudioDevice.fromMap(Map<String, dynamic>.from(deviceMap)));
          }
        }
      }
      print('Windows: Found ${_availableDevices.length} audio devices');
    } catch (e) {
      print('Error loading Windows audio devices: $e');
      // Fallback: create some dummy devices for testing
      _availableDevices.addAll([
        AudioDevice(id: 'speakers', name: 'Speakers', kind: 'audiooutput'),
        AudioDevice(id: 'headphones', name: 'Headphones', kind: 'audiooutput'),
      ]);
    }
  }

  // Play audio to specific device
  Future<void> playAudioToDevice(String deviceId, {bool isPersonal = true}) async {
    try {
      if (kIsWeb) {
        await _playWebAudio(deviceId);
      } else if (Platform.isWindows) {
        await _playWindowsAudio(deviceId);
      } else if (Platform.isIOS || Platform.isAndroid) {
        // Use existing mobile audio routing
        await _playMobileAudio(isPersonal);
      }
    } catch (e) {
      print('Error playing audio to device $deviceId: $e');
      rethrow;
    }
  }

  // Web audio playback with setSinkId
  Future<void> _playWebAudio(String deviceId) async {
    try {
      print('Web: _playWebAudio called with deviceId: $deviceId');
      // Call our JavaScript bridge to play audio using direct invocation
      final jsPlayAudio = js_util.getProperty(html.window, 'playAudioToDevice');
      if (jsPlayAudio != null) {
        print('Web: Calling JavaScript playAudioToDevice with deviceId: $deviceId');
        // Fix: Call the function directly with the deviceId parameter
        final result = js_util.callMethod(jsPlayAudio, 'call', [html.window, deviceId]);
        await js_util.promiseToFuture(result);
        print('Web: Successfully played audio to device $deviceId using setSinkId');
      } else {
        throw Exception('JavaScript audio bridge not available');
      }
    } catch (e) {
      print('Web audio playback error: $e');
      rethrow;
    }
  }

  // Windows audio playback via platform channels
  Future<void> _playWindowsAudio(String deviceId) async {
    try {
      await platform.invokeMethod('playAudioToDevice', {
        'deviceId': deviceId,
        'audioFile': 'assets/test.mp3'
      });
    } catch (e) {
      print('Windows audio playback error: $e');
      rethrow;
    }
  }

  // Mobile audio playback using existing approach
  Future<void> _playMobileAudio(bool isPersonal) async {
    try {
      if (Platform.isIOS) {
        if (isPersonal) {
          await platform.invokeMethod('resetToDefault');
        } else {
          await platform.invokeMethod('forceSpeaker');
        }
      }
      // For Android, implement similar logic if needed
    } catch (e) {
      print('Mobile audio routing error: $e');
      rethrow;
    }
  }

  // Test audio playback
  Future<void> testPersonalSpeaker() async {
    print('Testing personal speaker: $_personalSpeakerId');
    print('Available devices: ${_availableDevices.map((d) => '${d.name} (${d.id})').join(', ')}');
    await playAudioToDevice(_personalSpeakerId, isPersonal: true);
  }

  Future<void> testSystemSpeaker() async {
    print('Testing system speaker: $_systemSpeakerId');
    print('Available devices: ${_availableDevices.map((d) => '${d.name} (${d.id})').join(', ')}');
    await playAudioToDevice(_systemSpeakerId, isPersonal: false);
  }

  // Refresh device list
  Future<void> refreshDevices() async {
    await _loadAvailableDevices();
  }
}
