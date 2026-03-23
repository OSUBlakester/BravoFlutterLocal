import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io';

void main() {
  runApp(const AudioTestApp());
}

class AudioTestApp extends StatelessWidget {
  const AudioTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bravo AAC Audio Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AudioTestPage(),
    );
  }
}

class AudioTestPage extends StatefulWidget {
  const AudioTestPage({super.key});

  @override
  State<AudioTestPage> createState() => _AudioTestPageState();
}

class _AudioTestPageState extends State<AudioTestPage> {
  static const platform = MethodChannel('audio_routing');
  late FlutterTts flutterTts;
  String statusMessage = 'Ready to test audio routing';

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bravo AAC Audio Test'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusMessage,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 40),
            
            const Text(
              'Test Audio Routing for AAC App:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 30),
            
            ElevatedButton(
              onPressed: _testPersonalAudio,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.all(20),
              ),
              child: const Column(
                children: [
                  Text('Test Personal Audio', style: TextStyle(fontSize: 18, color: Colors.white)),
                  Text('(Auditory Scanning)', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  Text('Should go to default device', style: TextStyle(fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _testSystemAudio,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.all(20),
              ),
              child: const Column(
                children: [
                  Text('Test System Audio', style: TextStyle(fontSize: 18, color: Colors.white)),
                  Text('(Announcement)', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  Text('Should force to speaker', style: TextStyle(fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _simulateAAC,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.all(20),
              ),
              child: const Column(
                children: [
                  Text('Simulate AAC Flow', style: TextStyle(fontSize: 18, color: Colors.white)),
                  Text('Scanning → Selection → Announcement', style: TextStyle(fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expected Behavior:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('• Personal: Default device (earpiece/headphones)'),
                  Text('• System: Built-in speaker (forced)'),
                  Text('• AAC Flow: Combines both routing types'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testPersonalAudio() async {
    setState(() {
      statusMessage = 'Testing personal audio (scanning)...';
    });

    try {
      if (!kIsWeb && Platform.isIOS) {
        await platform.invokeMethod('resetToDefault');
        print('iOS: Audio reset to default for personal use');
      }
      
      await flutterTts.speak('This is personal audio for scanning. You should hear this privately.');
      
      setState(() {
        statusMessage = 'Personal audio test completed';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error in personal audio: $e';
      });
      print('Personal audio error: $e');
    }
  }

  Future<void> _testSystemAudio() async {
    setState(() {
      statusMessage = 'Testing system audio (announcement)...';
    });

    try {
      if (!kIsWeb && Platform.isIOS) {
        await platform.invokeMethod('forceSpeaker');
        print('iOS: Audio forced to speaker for system announcement');
      }
      
      await flutterTts.speak('This is system audio for announcements. You should hear this from the speaker.');
      
      setState(() {
        statusMessage = 'System audio test completed';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error in system audio: $e';
      });
      print('System audio error: $e');
    }
  }

  Future<void> _simulateAAC() async {
    setState(() {
      statusMessage = 'Simulating AAC flow...';
    });

    try {
      // Step 1: Scanning (personal audio)
      if (!kIsWeb && Platform.isIOS) {
        await platform.invokeMethod('resetToDefault');
      }
      
      setState(() {
        statusMessage = 'Scanning options (personal audio)...';
      });
      
      await flutterTts.speak('Scanning: Hello');
      await Future.delayed(const Duration(seconds: 2));
      
      await flutterTts.speak('Scanning: Goodbye');
      await Future.delayed(const Duration(seconds: 2));
      
      // Step 2: Selection and announcement (system audio)
      setState(() {
        statusMessage = 'User selected - announcing (system audio)...';
      });
      
      if (!kIsWeb && Platform.isIOS) {
        await platform.invokeMethod('forceSpeaker');
      }
      
      await flutterTts.speak('Hello! How are you today?');
      
      setState(() {
        statusMessage = 'AAC flow simulation completed';
      });
      
    } catch (e) {
      setState(() {
        statusMessage = 'Error in AAC simulation: $e';
      });
      print('AAC simulation error: $e');
    }
  }
}
