// Stub implementation for non-web platforms (iOS, Android)
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audio_device.dart';

class AudioDeviceService {
  static const platform = MethodChannel('audio_routing');

  // Device storage keys
  static const String _personalSpeakerKey = 'personal_speaker_device';
  static const String _systemSpeakerKey = 'system_speaker_device';

  // Current device selections
  String _personalSpeakerId = 'default';
  String _systemSpeakerId = 'default';

  // Available devices
  final List<AudioDevice> _availableDevices = [];

  // Audio player for testing
  AudioPlayer? _audioPlayer;

  // Getters
  String get personalSpeakerId => _personalSpeakerId;
  String get systemSpeakerId => _systemSpeakerId;
  List<AudioDevice> get availableDevices => List.unmodifiable(_availableDevices);

  // Initialize the service
  Future<void> initialize() async {
    print('AudioDeviceService: Initializing on ${Platform.operatingSystem}');
    
    await _loadSavedPreferences();
    await _loadAvailableDevices();
  }

  // Load saved preferences from local storage
  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _personalSpeakerId = prefs.getString(_personalSpeakerKey) ?? 'default';
      _systemSpeakerId = prefs.getString(_systemSpeakerKey) ?? 'default';
      print(
        'Loaded saved preferences: personal=$_personalSpeakerId, system=$_systemSpeakerId',
      );
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
      print(
        'Saved preferences: personal=$_personalSpeakerId, system=$_systemSpeakerId',
      );
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

  // Load available devices based on platform
  Future<void> _loadAvailableDevices() async {
    print('Loading available devices for ${Platform.operatingSystem}');
    
    // Add default device for all platforms
    _availableDevices.clear();
    _availableDevices.add(
      AudioDevice(
        id: 'default',
        name: 'Default',
        kind: 'default',
      ),
    );

    if (Platform.isWindows) {
      await _loadWindowsDevices();
    } else if (Platform.isIOS || Platform.isAndroid) {
      // For mobile, we'll use the existing platform channel approach
      // Just return default for now, since routing is handled differently
      print('Mobile platform: Using default audio routing');
    }
  }

  // Load devices for Windows platform
  Future<void> _loadWindowsDevices() async {
    // Stub implementation for non-web platforms
    // This would normally load Windows audio devices
    print('Windows audio device loading not available on this platform');
  }

  // Stub methods for all other functionality
  Future<void> playAudioToDevice(String deviceId, {bool isPersonal = true}) async {
    print('Audio playback not available on this platform');
  }

  Future<void> playTTSAudio(String base64Audio, {bool isPersonal = false}) async {
    print('TTS audio playback not available on this platform');
  }

  Future<void> testPersonalSpeaker() async {
    print('Testing personal speaker not available on this platform');
  }

  Future<void> testSystemSpeaker() async {
    print('Testing system speaker not available on this platform');
  }

  Future<void> refreshDevices() async {
    print('Refreshing devices not available on this platform');
    await _loadAvailableDevices();
  }

  Future<void> testAudioDevice(String deviceId) async {
    print('Audio device testing not available on this platform');
  }

  Future<void> stopAllAudio() async {
    print('Stop audio not available on this platform');
  }

  void dispose() {
    _audioPlayer?.dispose();
  }
}
