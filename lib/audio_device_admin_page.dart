import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'services/audio_device_service.dart';
import 'models/audio_device.dart';

class AudioDeviceAdminPage extends StatefulWidget {
  const AudioDeviceAdminPage({Key? key}) : super(key: key);

  @override
  State<AudioDeviceAdminPage> createState() => _AudioDeviceAdminPageState();
}

class _AudioDeviceAdminPageState extends State<AudioDeviceAdminPage> {
  final AudioDeviceService audioDeviceService = AudioDeviceService();
  bool isLoading = true;
  String? selectedPersonalDevice;
  String? selectedSystemDevice;
  String status = '';

  @override
  void initState() {
    super.initState();
    // Stop wake word listening when this page is shown
    final dynamic gridState = context.findAncestorStateOfType<State<StatefulWidget>>();
    if (gridState != null && gridState.runtimeType.toString() == '_GridPageState') {
      try {
        gridState._wakeWordService?.stopWakeWordListening();
      } catch (_) {}
    }
    _initAudioDevices();
  }

  Future<void> _initAudioDevices() async {
    setState(() {
      isLoading = true;
    });
    await audioDeviceService.initialize();
    setState(() {
      selectedPersonalDevice = audioDeviceService.personalSpeakerId;
      selectedSystemDevice = audioDeviceService.systemSpeakerId;
      isLoading = false;
    });
  }

  Future<void> _refreshDevices() async {
    setState(() {
      isLoading = true;
    });
    await audioDeviceService.refreshDevices();
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveAudioSettings() async {
    await audioDeviceService.savePreferences();
    setState(() {
      status = 'Audio settings saved!';
    });
  }

  Future<void> _testPersonalSpeaker() async {
    setState(() {
      status = 'Testing personal speaker...';
    });
    await audioDeviceService.testPersonalSpeaker();
    setState(() {
      status = 'Tested personal speaker.';
    });
  }

  Future<void> _testSystemSpeaker() async {
    setState(() {
      status = 'Testing system speaker...';
    });
    await audioDeviceService.testSystemSpeaker();
    setState(() {
      status = 'Tested system speaker.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = !kIsWeb && Platform.isWindows;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Device Admin')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: (isWindows || kIsWeb)
                  ? _buildDeviceUI()
                  : _buildNonWindowsUI(),
            ),
    );
  }

  Widget _buildDeviceUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Select output devices for Personal and System audio.'),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Devices',
              onPressed: _refreshDevices,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Personal Speaker:'),
        DropdownButton<String>(
          value: selectedPersonalDevice,
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
                selectedPersonalDevice = newValue;
              });
              audioDeviceService.setPersonalSpeaker(newValue);
            }
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _testPersonalSpeaker,
          child: const Text('Test Personal Speaker'),
        ),
        const SizedBox(height: 24),
        Text('System Speaker:'),
        DropdownButton<String>(
          value: selectedSystemDevice,
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
                selectedSystemDevice = newValue;
              });
              audioDeviceService.setSystemSpeaker(newValue);
            }
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _testSystemSpeaker,
          child: const Text('Test System Speaker'),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _saveAudioSettings,
          child: const Text('Save Audio Settings'),
        ),
        const SizedBox(height: 16),
        if (status.isNotEmpty)
          Text(status, style: const TextStyle(color: Colors.blue)),
        const SizedBox(height: 16),
        const Text(
          'Note: This setting is only needed for Windows devices. On other platforms, Personal audio will use headphones and System audio will use built-in speakers.',
        ),
      ],
    );
  }

  Widget _buildNonWindowsUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Audio device selection is only needed for Windows devices.'),
        SizedBox(height: 16),
        Text(
          'On this platform, Personal audio will use headphones and System audio will use built-in speakers.',
        ),
      ],
    );
  }
}
