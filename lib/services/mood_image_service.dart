import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';

/// Service for fetching mood mascot images from Firestore
class MoodImageService {
  static final MoodImageService _instance = MoodImageService._internal();
  factory MoodImageService() => _instance;
  MoodImageService._internal();

  // Cache for storing mood image URLs to avoid repeated API calls
  final Map<String, String?> _moodImageCache = {};
  
  /// Get mood mascot image URL for a given mood name
  /// Returns the image URL or null if not found (fallback to emoji)
  Future<String?> getMoodImageUrl(String moodName) async {
    debugPrint('🎭 MoodImageService: Getting image for mood: $moodName');
    
    // Check cache first
    final cacheKey = moodName.toLowerCase();
    if (_moodImageCache.containsKey(cacheKey)) {
      final cachedUrl = _moodImageCache[cacheKey];
      debugPrint('🎭 MoodImageService: Cache hit for $moodName: $cachedUrl');
      return cachedUrl;
    }
    
    try {
      // Query the mood_images collection for this mood
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/mood/image/$cacheKey'),
        headers: {
          'Content-Type': 'application/json',
        },
      );
      
      debugPrint('🎭 MoodImageService: API response status for $moodName: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final imageUrl = data['image_url'] as String?;
        
        // Cache the result (including null results to avoid repeated failed requests)
        _moodImageCache[cacheKey] = imageUrl;
        
        debugPrint('🎭 MoodImageService: Found image for $moodName: $imageUrl');
        return imageUrl;
      } else {
        debugPrint('🎭 MoodImageService: No image found for $moodName (status: ${response.statusCode})');
        // Cache null result
        _moodImageCache[cacheKey] = null;
        return null;
      }
    } catch (error) {
      debugPrint('🎭 MoodImageService: Error fetching mood image for $moodName: $error');
      // Cache null result on error to avoid repeated failed requests
      _moodImageCache[cacheKey] = null;
      return null;
    }
  }
  
  /// Preload mood images for all mood options to improve performance
  Future<void> preloadMoodImages(List<String> moodNames) async {
    debugPrint('🎭 MoodImageService: Preloading ${moodNames.length} mood images...');
    
    final futures = moodNames.map((mood) => getMoodImageUrl(mood));
    await Future.wait(futures);
    
    final cachedCount = _moodImageCache.values.where((url) => url != null).length;
    debugPrint('🎭 MoodImageService: Preloaded complete. $cachedCount/${moodNames.length} mood images cached.');
  }
  
  /// Clear the image cache (useful for testing or when mood images are updated)
  void clearCache() {
    debugPrint('🎭 MoodImageService: Clearing mood image cache');
    _moodImageCache.clear();
  }
  
  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    final totalCached = _moodImageCache.length;
    final withImages = _moodImageCache.values.where((url) => url != null).length;
    final withoutImages = totalCached - withImages;
    
    return {
      'total_cached': totalCached,
      'with_images': withImages, 
      'without_images': withoutImages,
      'cache_entries': Map.from(_moodImageCache),
    };
  }
}