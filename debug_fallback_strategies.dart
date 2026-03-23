import 'dart:convert';
import 'package:http/http.dart' as http;

/// Test different search strategies to fix the "I" button issue
void main() async {
  final baseUrl = 'https://dev.talkwithbravo.com';
  
  print('🔍 Testing search strategies to fix "I" button matching...');
  
  final searchTerm = 'I';
  
  // Test different strategies in order of preference
  final strategies = [
    {
      'name': 'Current comprehensive (broken)',
      'url': '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(searchTerm)}&concept=${Uri.encodeComponent(searchTerm)}&subconcept=${Uri.encodeComponent(searchTerm)}&limit=5&log_missing=false',
    },
    {
      'name': 'Tag-only (works)',
      'url': '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(searchTerm)}&limit=5',
    },
    {
      'name': 'Subconcept-only (works)',
      'url': '$baseUrl/api/imagecreator/search?subconcept=${Uri.encodeComponent(searchTerm)}&limit=5',
    },
    {
      'name': 'Concept-only',
      'url': '$baseUrl/api/imagecreator/search?concept=${Uri.encodeComponent(searchTerm)}&limit=5',
    },
  ];
  
  for (final strategy in strategies) {
    print('\n📋 Testing: ${strategy['name']}');
    print('URL: ${strategy['url']}');
    
    try {
      final response = await http.get(
        Uri.parse(strategy['url']!),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = data['images'] as List;
        
        print('✅ Found: ${images.length} images');
        
        if (images.isNotEmpty) {
          final firstImage = images[0];
          print('  Best match:');
          print('    - Image URL: ${firstImage['image_url']}');
          print('    - Subconcept: ${firstImage['subconcept']}');
          print('    - Tags: ${firstImage['tags']}');
          print('    - Document ID: ${firstImage['id']}');
          
          if (strategy['name']!.contains('works')) {
            print('  🎉 This strategy works! Use this as fallback.');
          }
        }
      } else {
        print('❌ Status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error: $e');
    }
  }
  
  print('\n🔧 Recommendation: Update PictogramService to use tag-only or subconcept-only as fallback when comprehensive fails.');
}