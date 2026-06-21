import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';
import 'pictogram_service.dart';

/// Service for fetching mood mascot images from Firestore
class MoodImageService {
  static final MoodImageService _instance = MoodImageService._internal();
  factory MoodImageService() => _instance;
  MoodImageService._internal();

  // Cache for storing mood image URLs to avoid repeated API calls
  final Map<String, String?> _moodImageCache = {};

  static const Set<String> _nonImageMoods = {
    'skip',
    'no mood selected',
  };
  
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

    if (_nonImageMoods.contains(cacheKey)) {
      debugPrint('🎭 MoodImageService: Skipping image lookup for non-image mood: $moodName');
      _moodImageCache[cacheKey] = null;
      return null;
    }
    
    // Primary path: dedicated mood endpoint.
    final endpointUrl = await _fetchFromMoodEndpoint(cacheKey, moodName);
    if (endpointUrl != null && endpointUrl.isNotEmpty) {
      _moodImageCache[cacheKey] = endpointUrl;
      debugPrint('🎭 MoodImageService: Assigned mood endpoint image for $moodName: $endpointUrl');
      return endpointUrl;
    }

    // Fallback path: same general symbol lookup path the web app uses.
    final fallbackUrl = await _fetchFromGenericSymbolLookup(moodName);
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      _moodImageCache[cacheKey] = fallbackUrl;
      debugPrint('🎭 MoodImageService: Assigned fallback symbol image for $moodName: $fallbackUrl');
      return fallbackUrl;
    }

    debugPrint('🎭 MoodImageService: No image found for $moodName after endpoint + fallback lookup');
    _moodImageCache[cacheKey] = null;
    return null;
  }

  Future<String?> _fetchFromMoodEndpoint(String cacheKey, String moodName) async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/mood/image/$cacheKey'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      debugPrint('🎭 MoodImageService: API response status for $moodName: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('🎭 MoodImageService: Mood endpoint miss for $moodName (status: ${response.statusCode})');
        return null;
      }

      final data = json.decode(response.body);
      return data['image_url'] as String?;
    } catch (error) {
      debugPrint('🎭 MoodImageService: Mood endpoint error for $moodName: $error');
      return null;
    }
  }

  Future<String?> _fetchFromGenericSymbolLookup(String moodName) async {
    try {
      final result = await PictogramService().getPictogramResult(
        moodName,
        enableSightWords: false,
        shouldLogMissing: false,
        // Intentionally omit keywords/locale so this path uses the public
        // /api/imagecreator/search lookup and avoids auth-only button-search.
        keywords: null,
        locale: null,
      );
      return result?.imageUrl;
    } catch (error) {
      debugPrint('🎭 MoodImageService: Fallback symbol lookup error for $moodName: $error');
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