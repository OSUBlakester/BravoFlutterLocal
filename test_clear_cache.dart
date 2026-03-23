import 'package:flutter/material.dart';
import 'lib/services/pictogram_service.dart';

/// Debug script to clear cache and test "I" button
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔍 Testing "I" button with cache clearing...');
  
  final pictogramService = PictogramService();
  
  print('\n🗑️ Step 1: Clearing pictogram cache...');
  await pictogramService.clearCache();
  print('✅ Cache cleared');
  
  print('\n🧪 Step 2: Testing "I" button after cache clear...');
  try {
    final result = await pictogramService.getPictogramForText('I');
    
    if (result != null) {
      print('✅ SUCCESS! "I" button found image after cache clear:');
      print('   Image URL: $result');
      print('🎉 The issue was cached null results!');
    } else {
      print('❌ STILL FAILING: "I" button returned null even after cache clear');
      print('   This indicates the API issue is still present');
    }
  } catch (e) {
    print('❌ ERROR during "I" button test: $e');
  }
  
  print('\n💡 If this fixed it, the user needs to:');
  print('   - Delete and reinstall the app (clears all cache)');
  print('   - OR add cache versioning/invalidation logic');
}