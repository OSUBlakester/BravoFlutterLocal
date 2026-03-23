import 'package:flutter/material.dart';
import 'lib/services/pictogram_service.dart';
import 'lib/config/environment_config.dart';

/// Test the complete PictogramService flow for the "I" button
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔍 Testing complete PictogramService flow for "I" button...');
  print('Environment: ${EnvironmentConfig.currentEnvironment}');
  print('API URL: ${EnvironmentConfig.apiBaseUrl}');
  
  final pictogramService = PictogramService();
  
  // Test the exact flow that happens when "I" button is pressed
  print('\n📱 Simulating "I" button press...');
  
  try {
    final result = await pictogramService.getPictogramForText('I');
    
    if (result != null) {
      print('✅ SUCCESS! Found image for "I" button');
      print('Image URL: $result');
      print('🎉 The "I" button should now work correctly!');
    } else {
      print('❌ FAILED! No image found for "I" button');
      print('This indicates there may still be an issue.');
    }
  } catch (e) {
    print('❌ ERROR during "I" button test: $e');
  }
  
  // Also test some other common single characters to verify the fix works broadly
  final testCases = ['a', 'A', 'o', 'O', 'the', 'and'];
  
  print('\n🧪 Testing other common words to verify fix works broadly...');
  for (final testCase in testCases) {
    try {
      final result = await pictogramService.getPictogramForText(testCase);
      if (result != null) {
        print('✅ "$testCase" - Found image');
      } else {
        print('⚠️  "$testCase" - No image found (may be normal)');
      }
    } catch (e) {
      print('❌ "$testCase" - Error: $e');
    }
  }
  
  print('\n🔧 Test complete! Check the console output above to see if "I" button works.');
}