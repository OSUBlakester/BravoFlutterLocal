import 'dart:convert';
import 'package:http/http.dart' as http;

/// Debug script to test the "I" button image matching issue
void main() async {
  final baseUrl = 'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app';
  
  print('🔍 Testing "I" button image matching...');
  
  // Test different search strategies
  final strategies = [
    {'name': 'Comprehensive', 'url': '$baseUrl/api/imagecreator/search?tag=I&concept=I&subconcept=I&limit=5'},
    {'name': 'Tag only (uppercase)', 'url': '$baseUrl/api/imagecreator/search?tag=I&limit=5'},
    {'name': 'Tag only (lowercase)', 'url': '$baseUrl/api/imagecreator/search?tag=i&limit=5'},
    {'name': 'Subconcept only (uppercase)', 'url': '$baseUrl/api/imagecreator/search?subconcept=I&limit=5'},
    {'name': 'Subconcept only (lowercase)', 'url': '$baseUrl/api/imagecreator/search?subconcept=i&limit=5'},
  ];
  
  for (final strategy in strategies) {
    print('\n📋 Testing ${strategy['name']}:');
    print('URL: ${strategy['url']}');
    
    try {
      final response = await http.get(
        Uri.parse(strategy['url']!),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      print('Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          print('Found: ${images.length} images');
          
          if (images.isNotEmpty) {
            for (int i = 0; i < images.length && i < 3; i++) {
              final image = images[i];
              print('  Image ${i + 1}:');
              print('    - Subconcept: ${image['subconcept']}');
              print('    - Tags: ${image['tags']}');
              print('    - Image URL: ${image['image_url']}');
            }
          } else {
            print('  ❌ No images found');
          }
        } else {
          print('  ❌ Unexpected response format');
        }
      } else {
        print('  ❌ API error: ${response.statusCode}');
        print('  Response: ${response.body}');
      }
    } catch (e) {
      print('  ❌ Request failed: $e');
    }
  }
  
  print('\n🔍 Debug complete');
}