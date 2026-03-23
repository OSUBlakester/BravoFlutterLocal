import 'dart:convert';
import 'package:http/http.dart' as http;

/// Simple test to verify the "I" button image matching works with current PictogramService logic
void main() async {
  final baseUrl = 'https://dev.talkwithbravo.com';
  
  print('🔍 Testing PictogramService fallback logic for "I" button...');
  print('This simulates the actual search strategies used by PictogramService');
  
  final searchTerm = 'I';
  
  // Test Strategy 1: Comprehensive search (currently broken)
  print('\n📋 Strategy 1: Comprehensive search (comprehensive fails)');
  final comprehensiveUrl = '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(searchTerm)}&concept=${Uri.encodeComponent(searchTerm)}&subconcept=${Uri.encodeComponent(searchTerm)}&limit=5&log_missing=false';
  
  String? result = await testStrategy('Comprehensive', comprehensiveUrl);
  if (result != null) {
    print('✅ "I" button would work with comprehensive search: $result');
    return;
  }
  
  // Test Strategy 2: Subconcept-only search (this should work!)
  print('\n📋 Strategy 2: Subconcept-only fallback (should work)');
  final subconceptUrl = '$baseUrl/api/imagecreator/search?subconcept=${Uri.encodeComponent(searchTerm)}&limit=1&log_missing=false';
  
  result = await testStrategy('Subconcept-only', subconceptUrl);
  if (result != null) {
    print('✅ "I" button would work with subconcept fallback: $result');
    return;
  }
  
  // Test Strategy 3: Tag-only search (this should also work!)
  print('\n📋 Strategy 3: Tag-only fallback (should work)');
  final tagUrl = '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(searchTerm)}&limit=1&log_missing=false';
  
  result = await testStrategy('Tag-only', tagUrl);
  if (result != null) {
    print('✅ "I" button would work with tag fallback: $result');
    return;
  }
  
  // Test Strategy 4: Concept-only search
  print('\n📋 Strategy 4: Concept-only fallback');
  final conceptUrl = '$baseUrl/api/imagecreator/search?concept=${Uri.encodeComponent(searchTerm)}&limit=1&log_missing=false';
  
  result = await testStrategy('Concept-only', conceptUrl);
  if (result != null) {
    print('✅ "I" button would work with concept fallback: $result');
    return;
  }
  
  print('\n❌ All strategies failed - "I" button would not work');
}

Future<String?> testStrategy(String strategyName, String url) async {
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 8));
    
    print('  Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data is Map<String, dynamic> && data['images'] is List) {
        final images = data['images'] as List;
        print('  Found: ${images.length} images');
        
        if (images.isNotEmpty) {
          final firstImage = images[0];
          final imageUrl = firstImage['image_url'] as String?;
          final imageName = firstImage['name'] as String? ?? 'unknown';
          final subconcept = firstImage['subconcept'] as String? ?? '';
          final documentId = firstImage['id'] as String? ?? '';
          
          print('  ✅ SUCCESS: $imageName');
          print('    - Subconcept: $subconcept');
          print('    - Document ID: $documentId');
          print('    - Image URL: $imageUrl');
          
          return imageUrl;
        } else {
          print('  ❌ No images found');
        }
      } else {
        print('  ❌ Unexpected response format');
      }
    } else {
      print('  ❌ API error: ${response.statusCode}');
    }
  } catch (e) {
    print('  ❌ Request failed: $e');
  }
  
  return null;
}