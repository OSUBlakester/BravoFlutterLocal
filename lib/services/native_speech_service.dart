import 'package:flutter/services.dart';
import 'dart:async';

class NativeSpeechService {
  static const _platform = MethodChannel('audio_routing');
  static const _resultsChannel = MethodChannel('native_speech_results');
  
  static StreamController<Map<String, dynamic>>? _speechResultController;
  static StreamController<String>? _speechErrorController;
  
  static Stream<Map<String, dynamic>>? get speechResults => _speechResultController?.stream;
  static Stream<String>? get speechErrors => _speechErrorController?.stream;
  
  static Future<void> initialize() async {
    _speechResultController = StreamController<Map<String, dynamic>>.broadcast();
    _speechErrorController = StreamController<String>.broadcast();
    
    _resultsChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSpeechResult':
          final Map<String, dynamic> result = Map<String, dynamic>.from(call.arguments);
          _speechResultController?.add(result);
          break;
        case 'onSpeechError':
          final String error = call.arguments['error'] ?? 'Unknown error';
          _speechErrorController?.add(error);
          break;
      }
    });
  }
  
  static Future<String?> checkSpeechPermission() async {
    try {
      final String result = await _platform.invokeMethod('checkSpeechPermission');
      return result;
    } catch (e) {
      print('Error checking speech permission: $e');
      return null;
    }
  }
  
  static Future<String?> requestSpeechPermission() async {
    try {
      final String result = await _platform.invokeMethod('requestSpeechPermission');
      return result;
    } catch (e) {
      print('Error requesting speech permission: $e');
      return null;
    }
  }
  
  static Future<bool> startRecognition() async {
    try {
      await _platform.invokeMethod('startNativeSpeechRecognition');
      return true;
    } catch (e) {
      print('Error starting native speech recognition: $e');
      return false;
    }
  }
  
  static Future<bool> stopRecognition() async {
    try {
      await _platform.invokeMethod('stopNativeSpeechRecognition');
      return true;
    } catch (e) {
      print('Error stopping native speech recognition: $e');
      return false;
    }
  }
  
  static void dispose() {
    _speechResultController?.close();
    _speechErrorController?.close();
    _speechResultController = null;
    _speechErrorController = null;
  }
}
