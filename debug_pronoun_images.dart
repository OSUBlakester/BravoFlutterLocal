import 'dart:convert';
import 'package:http/http.dart' as http;

/// Debug script to find images that might work for "I" pronoun
void main() async {
  final baseUrl = 'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app';
  
  print('🔍 Searching for pronoun and self-reference images...');
  
  // Test related terms that might have images
  final searchTerms = [
    'me', 'myself', 'self', 'person', 'user', 'individual', 
    'pronoun', 'first person', 'identity', 'human', 'people'
  ];
  
  for (final term in searchTerms) {
    print('\n📋 Searching for "$term":');
    
    try {
      final url = '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(term)}&concept=${Uri.encodeComponent(term)}&subconcept=${Uri.encodeComponent(term)}&limit=3';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          print('Found: ${images.length} images');
          
          if (images.isNotEmpty) {
            final image = images[0]; // Show first result
            print('  Best match:');
            print('    - Subconcept: ${image['subconcept']}');
            print('    - Tags: ${image['tags']}');
            print('    - Concept: ${image['concept']}');
            print('    - Image URL: ${image['image_url']}');
          }
        }
      }
    } catch (e) {
      print('  ❌ Request failed: $e');
    }
  }
  
  print('\n🔍 Search complete');
}