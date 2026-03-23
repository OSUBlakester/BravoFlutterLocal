import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'services/audio_device_service.dart';

void main() {
  runApp(AudioRoutingPOC());
}

class AudioRoutingPOC extends StatelessWidget {
  const AudioRoutingPOC({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Audio Routing POC', home: AudioRoutingHome());
  }
}

class AudioRoutingHome extends StatefulWidget {
  const AudioRoutingHome({super.key});

  @override
  _AudioRoutingHomeState createState() => _AudioRoutingHomeState();
}

class _AudioRoutingHomeState extends State<AudioRoutingHome> {
  final player = AudioPlayer();
  final audioDeviceService = AudioDeviceService();
  static const platform = MethodChannel('audio_routing');
  
  bool _isLoading = true;
  String? _selectedPersonalDevice;
  String? _selectedSystemDevice;

  @override
  void initState() {
    super.initState();
    _initializeAudioService();
  }

  Future<void> _initializeAudioService() async {
    try {
      await audioDeviceService.initialize();
      setState(() {
        _selectedPersonalDevice = audioDeviceService.personalSpeakerId;
        _selectedSystemDevice = audioDeviceService.systemSpeakerId;
        _isLoading = false;
      });
    } catch (e) {
      print('Error initializing audio service: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> playOnDefault() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        try {
          await platform.invokeMethod('resetToDefault');
        } catch (e) {
          print('Failed to reset audio route: $e');
        }
      }
      
      // Use audio device service for routing
      await audioDeviceService.playAudioToDevice(
        audioDeviceService.personalSpeakerId,
        isPersonal: true
      );
      
      await player.setAsset('assets/test.mp3');
      await player.play();
    } catch (e) {
      print('Failed to play audio: $e');
    }
  }

  Future<void> playThroughSpeaker() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        try {
          await platform.invokeMethod('forceSpeaker');
        } catch (e) {
          print('Failed to force speaker: $e');
        }
      }
      
      // Use audio device service for routing
      await audioDeviceService.playAudioToDevice(
        audioDeviceService.systemSpeakerId,
        isPersonal: false
      );
      
      await player.setAsset('assets/test.mp3');
      await player.play();
    } catch (e) {
      print('Failed to play audio: $e');
    }
  }

  Future<void> _testPersonalSpeaker() async {
    try {
      await audioDeviceService.testPersonalSpeaker();
    } catch (e) {
      _showErrorDialog('Personal speaker test failed: $e');
    }
  }

  Future<void> _testSystemSpeaker() async {
    try {
      await audioDeviceService.testSystemSpeaker();
    } catch (e) {
      _showErrorDialog('System speaker test failed: $e');
    }
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await audioDeviceService.refreshDevices();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error refreshing devices: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Failed to refresh devices: $e');
    }
  }

  Future<void> _saveAudioSettings() async {
    try {
      await audioDeviceService.savePreferences();
      _showSuccessDialog('Audio settings saved successfully!');
    } catch (e) {
      _showErrorDialog('Failed to save settings: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Success'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // For Windows: setSinkId is supported via just_audio
  // For Android/iOS: you’ll need to use platform channels for advanced routing

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Audio Routing POC')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Audio Device Selection Section
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Audio Device Settings',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              IconButton(
                                onPressed: _refreshDevices,
                                icon: Icon(Icons.refresh),
                                tooltip: 'Refresh Devices',
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          
                          // Personal Speaker Selection
                          Text(
                            'Personal Speaker:',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 8),
                          DropdownButton<String>(
                            value: _selectedPersonalDevice,
                            isExpanded: true,
                            items: audioDeviceService.availableDevices.map((device) {
                              return DropdownMenuItem<String>(
                                value: device.id,
                                child: Text(device.name),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedPersonalDevice = newValue;
                                });
                                audioDeviceService.setPersonalSpeaker(newValue);
                              }
                            },
                          ),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _testPersonalSpeaker,
                            child: Text('Test Personal Speaker'),
                          ),
                          
                          SizedBox(height: 16),
                          
                          // System Speaker Selection
                          Text(
                            'System Speaker:',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 8),
                          DropdownButton<String>(
                            value: _selectedSystemDevice,
                            isExpanded: true,
                            items: audioDeviceService.availableDevices.map((device) {
                              return DropdownMenuItem<String>(
                                value: device.id,
                                child: Text(device.name),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedSystemDevice = newValue;
                                });
                                audioDeviceService.setSystemSpeaker(newValue);
                              }
                            },
                          ),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _testSystemSpeaker,
                            child: Text('Test System Speaker'),
                          ),
                          
                          SizedBox(height: 16),
                          
                          // Save Settings Button
                          ElevatedButton(
                            onPressed: _saveAudioSettings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('Save Audio Settings'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Audio Playback Test Section
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Audio Playback Test',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: playOnDefault,
                            child: Text('Play on Personal Device'),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: playThroughSpeaker,
                            child: Text('Play on System Device'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Platform Info
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Platform Information',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          SizedBox(height: 8),
                          Text(
                            kIsWeb
                                ? 'Web: Using browser MediaDevices API and setSinkId for device selection.'
                                : Platform.isWindows
                                    ? 'Windows: Using platform channels for Core Audio API device selection.'
                                    : Platform.isIOS
                                        ? 'iOS: Using platform channels for AVAudioSession speaker routing.'
                                        : Platform.isAndroid
                                            ? 'Android: Using AudioManager for basic audio routing.'
                                            : 'Platform: Unknown - using default audio routing.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
