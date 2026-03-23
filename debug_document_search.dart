import 'dart:convert';
import 'package:http/http.dart' as http;

/// Debug script to check the specific document and related search issues
void main() async {
  final baseUrl = 'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app';
  final documentId = '64QuIPGuPrR3t6dfpa18';
  
  print('🔍 Investigating specific document and search issues...');
  
  // 1. Try to get the specific document if there's an API for it
  print('\n📋 Testing document-specific endpoints...');
  
  // 2. Search for any images to verify the API is working
  print('\n📋 Testing general image search to verify API functionality...');
  try {
    final testUrl = '$baseUrl/api/imagecreator/search?limit=5';
    final response = await http.get(
      Uri.parse(testUrl),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    
    print('General search status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['images'] is List) {
        final images = data['images'] as List;
        print('Total images available: ${images.length}');
        
        if (images.isNotEmpty) {
          print('Sample image structure:');
          final sample = images[0];
          print('  - ID: ${sample['id'] ?? 'N/A'}');
          print('  - Subconcept: ${sample['subconcept'] ?? 'N/A'}');
          print('  - Tags: ${sample['tags'] ?? 'N/A'}');
          print('  - Concept: ${sample['concept'] ?? 'N/A'}');
        }
      }
    }
  } catch (e) {
    print('General search failed: $e');
  }
  
  // 3. Search for single-character terms to see if there's filtering
  print('\n📋 Testing single-character search behavior...');
  final singleChars = ['a', 'A', 'i', 'I', 'o', 'O'];
  
  for (final char in singleChars) {
    try {
      final url = '$baseUrl/api/imagecreator/search?tag=$char&limit=1';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          print('  "$char": ${images.length} results');
        }
      }
    } catch (e) {
      print('  "$char": Error - $e');
    }
  }
  
  // 4. Check if there are any pronoun-related images
  print('\n📋 Searching for pronoun-related images...');
  final pronouns = ['me', 'you', 'he', 'she', 'we', 'they'];
  
  for (final pronoun in pronouns) {
    try {
      final url = '$baseUrl/api/imagecreator/search?tag=$pronoun&limit=1';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          if (images.isNotEmpty) {
            print('  "$pronoun": Found image - subconcept: ${images[0]['subconcept']}');
          }
        }
      }
    } catch (e) {
      print('  "$pronoun": Error - $e');
    }
  }
  
  print('\n✅ Investigation complete');
  print('\nRecommendations:');
  print('1. Verify the document $documentId exists in the correct Firestore collection');
  print('2. Check if the document has the expected tags and subconcept fields');
  print('3. Ensure the search API is querying the correct collection/database');
  print('4. Consider if there are environment-specific databases (dev/prod)');
}