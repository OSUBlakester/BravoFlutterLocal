// Simple test to verify Windows audio device enumeration
// Run this with: flutter run -d windows

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(WindowsAudioTest());
}

class WindowsAudioTest extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Windows Audio Test',
      home: WindowsAudioTestHome(),
    );
  }
}

class WindowsAudioTestHome extends StatefulWidget {
  @override
  _WindowsAudioTestHomeState createState() => _WindowsAudioTestHomeState();
}

class _WindowsAudioTestHomeState extends State<WindowsAudioTestHome> {
  static const platform = MethodChannel('audio_routing');
  List<Map<String, dynamic>> devices = [];
  String status = 'Ready to test';

  Future<void> testWindowsAudio() async {
    setState(() {
      status = 'Testing Windows audio...';
    });

    try {
      final result = await platform.invokeMethod('getAudioDevices');
      setState(() {
        devices = List<Map<String, dynamic>>.from(result ?? []);
        status = 'Found ${devices.length} audio devices';
      });
    } catch (e) {
      setState(() {
        status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Windows Audio Test')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Status: $status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: testWindowsAudio,
              child: Text('Test Windows Audio Devices'),
            ),
            SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return Card(
                    child: ListTile(
                      title: Text(device['name'] ?? 'Unknown'),
                      subtitle: Text('ID: ${device['id'] ?? 'Unknown'}'),
                      trailing: Text(device['kind'] ?? 'Unknown'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
