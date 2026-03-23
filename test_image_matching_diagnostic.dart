import 'package:flutter/material.dart';
import 'lib/services/pictogram_service.dart';
import 'lib/config/environment_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Diagnostic tool to test image matching in production
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔍 DIAGNOSTIC: Testing Image Matching in ${EnvironmentConfig.environmentName}');
  print('API Base URL: ${EnvironmentConfig.apiBaseUrl}');
  print('');
  
  // Test words that should have images
  final testWords = ['cat', 'dog', 'happy', 'home', 'eat', 'drink', 'I', 'you'];
  
  print('Testing direct API calls...\n');
  
  for (final word in testWords) {
    await testDirectAPICall(word);
    print('');
  }
  
  print('\nNow testing through PictogramService...\n');
  
  final pictogramService = PictogramService();
  pictogramService.enablePictograms = true;
  
  for (final word in testWords) {
    try {
      final result = await pictogramService.getPictogramForText(word);
      if (result != null) {
        print('✅ "$word": Found image');
        print('   URL: $result');
      } else {
        print('❌ "$word": No image found');
      }
    } catch (e) {
      print('❌ "$word": Error - $e');
    }
  }
  
  print('\n🎉 Diagnostic complete!');
}

Future<void> testDirectAPICall(String word) async {
  final baseUrl = EnvironmentConfig.apiBaseUrl;
  final url = '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(word)}&limit=5';
  
  print('Testing "$word"...');
  print('  URL: $url');
  
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 5));
    
    print('  Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data.containsKey('images')) {
        final images = data['images'] as List;
        print('  Results: ${images.length} images found');
        if (images.isNotEmpty) {
          final first = images.first;
          print('  First image: ${first['name'] ?? 'unknown'}');
          print('  Image URL: ${first['image_url'] ?? 'no url'}');
        }
      } else {
        print('  Unexpected response format: $data');
      }
    } else {
      print('  Error response: ${response.body}');
    }
  } catch (e) {
    print('  Exception: $e');
  }
}
