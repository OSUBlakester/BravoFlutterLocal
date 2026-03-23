import 'package:flutter/material.dart';
import 'lib/services/pictogram_service.dart';
import 'lib/config/environment_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test script to verify environment-aware cache clearing
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔍 Testing Environment-Aware Cache System...');
  print('Current Environment: ${EnvironmentConfig.environmentName}');
  print('API URL: ${EnvironmentConfig.apiBaseUrl}');
  
  // Check cached environment
  final prefs = await SharedPreferences.getInstance();
  final cachedEnv = prefs.getString('pictogram_cache_environment');
  final cacheJson = prefs.getString('pictogram_cache');
  
  print('\n📦 Cache Status:');
  print('  Cached Environment: ${cachedEnv ?? "None"}');
  print('  Has Cache Data: ${cacheJson != null}');
  if (cacheJson != null) {
    print('  Cache Size: ${cacheJson.length} bytes');
  }
  
  // Load cache (will auto-clear if environment changed)
  final pictogramService = PictogramService();
  await pictogramService.loadCacheFromPrefs();
  
  print('\n✅ Cache load complete!');
  print('If environment changed, cache was automatically cleared.');
  print('\n🧪 Testing image lookup for common word...');
  
  // Test a simple word
  final result = await pictogramService.getPictogramForText('cat');
  
  if (result != null) {
    print('✅ Found image for "cat": $result');
    
    // Verify it's using the correct environment URL
    if (result.contains(EnvironmentConfig.apiBaseUrl)) {
      print('✅ Image URL matches current environment!');
    } else {
      print('⚠️ WARNING: Image URL does NOT match current environment');
      print('   Expected: ${EnvironmentConfig.apiBaseUrl}');
      print('   Got: $result');
    }
  } else {
    print('❌ No image found for "cat"');
  }
  
  print('\n🎉 Test complete!');
}
