import 'dart:convert';
import 'package:http/http.dart' as http;

/// Test the correct dev API endpoint that the Flutter app actually uses
void main() async {
  final baseUrl = 'https://dev.talkwithbravo.com'; // Correct dev environment
  
  print('🔍 Testing CORRECT dev API endpoint for "I" button...');
  print('Base URL: $baseUrl');
  
  // Test different search strategies with the correct API
  final strategies = [
    {'name': 'Comprehensive', 'url': '$baseUrl/api/imagecreator/search?tag=I&concept=I&subconcept=I&limit=5'},
    {'name': 'Tag only (uppercase)', 'url': '$baseUrl/api/imagecreator/search?tag=I&limit=5'},
    {'name': 'Subconcept only (uppercase)', 'url': '$baseUrl/api/imagecreator/search?subconcept=I&limit=5'},
    {'name': 'General search test', 'url': '$baseUrl/api/imagecreator/search?limit=5'},
  ];
  
  for (final strategy in strategies) {
    print('\n📋 Testing ${strategy['name']}:');
    
    try {
      final response = await http.get(
        Uri.parse(strategy['url']!),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));
      
      print('Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          print('Found: ${images.length} images');
          
          if (images.isNotEmpty) {
            for (int i = 0; i < images.length && i < 2; i++) {
              final image = images[i];
              print('  Image ${i + 1}:');
              print('    - Subconcept: ${image['subconcept']}');
              print('    - Tags: ${image['tags']}');
              print('    - Concept: ${image['concept'] ?? 'N/A'}');
              print('    - ID: ${image['id'] ?? 'N/A'}');
            }
          } else {
            print('  ❌ No images found');
          }
        } else {
          print('  ❌ Unexpected response format');
          print('  Response: ${response.body}');
        }
      } else {
        print('  ❌ API error: ${response.statusCode}');
        print('  Response: ${response.body}');
      }
    } catch (e) {
      print('  ❌ Request failed: $e');
    }
  }
  
  print('\n🔍 Dev API test complete');
}