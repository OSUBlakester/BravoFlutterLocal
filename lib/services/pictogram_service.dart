import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/environment_config.dart';
import 'sight_word_service.dart';
import 'custom_image_service.dart';

/// Result object for pictogram lookup that includes sight word information
class PictogramResult {
  final String? imageUrl;
  final bool isSightWord;
  final String originalText;

  PictogramResult({
    required this.imageUrl,
    required this.isSightWord,
    required this.originalText,
  });
}

/// Service for handling pictogram/image loading, caching, and dynamic assignment
class PictogramService {
  static final PictogramService _instance = PictogramService._internal();
  factory PictogramService() => _instance;
  PictogramService._internal();

  // Cache for storing image URLs to avoid repeated API calls (global shared library)
  final Map<String, String?> _imageCache = {};
  
  // Current user context for future custom images feature
  String? _currentUserId;
  String? _currentIdToken;
  
  // Custom image batch preloading
  Map<String, String> _customImageMatches = {};
  bool _customImagesPreloaded = false;
  
  // Service settings
  bool enablePictograms = true;
  
  /// Set user context for custom images and clear caches if user changed
  void setUserContext({required String userId, required String idToken}) {
    final userChanged = _currentUserId != userId;
    
    _currentUserId = userId;
    _currentIdToken = idToken;
    
    debugPrint('🔧 PictogramService: Set user context - userId: $userId (global cache mode)');
    
    // Clear custom image cache when user changes to force fresh data
    if (userChanged) {
      debugPrint('🔄 PictogramService: User changed, clearing custom image cache for fresh data');
      CustomImageService.clearCache();
      _customImageMatches.clear();
      _customImagesPreloaded = false;
    }
  }

  /// Get pictogram/image URL for a given text with sight word information
  /// Returns PictogramResult with image URL and sight word status
  Future<PictogramResult?> getPictogramResult(String text, {int? sightWordGradeLevel, bool enableSightWords = true, List<String>? keywords, bool shouldLogMissing = true}) async {
    debugPrint('🚨 PICTOGRAM SERVICE CALLED: text="$text", enablePictograms=$enablePictograms, shouldLogMissing=$shouldLogMissing, keywords=$keywords');
    
    // Keep original text with capitalization for optimization, but create lowercase version for other processing
    final originalText = text.trim().replaceAll(RegExp(r'[^\w\s]'), '');
    final searchText = originalText.toLowerCase();
    debugPrint('🚨 PICTOGRAM SERVICE: Original text="$text" → Original preserved="$originalText" → Search text="$searchText"');
    
    // Initialize sight word flag
    bool isSightWord = false;
    
    // Return null early if pictograms are disabled or if the text is empty
    if (!enablePictograms || searchText.isEmpty) {
      debugPrint('🚨 PICTOGRAM SERVICE: Pictograms DISABLED (enablePictograms=$enablePictograms) or empty text (searchText="$searchText") - returning null');
      return null;
    }

    // Check if this text should be displayed as text-only due to sight words
    // Only apply sight word logic if both enableSightWords and sightWordGradeLevel are provided
    if (enableSightWords && sightWordGradeLevel != null) {
      final sightWordService = SightWordService();
      if (sightWordService.isInitialized) {
        // Update grade level if needed
        await sightWordService.setGradeLevel(sightWordGradeLevel.toString());
        
        // Check if this text is a sight word (MUST use original full text, not optimized search text)
        if (sightWordService.isSightWordText(text)) {
          // debugPrint('🔤 PictogramService: "$text" is a sight word - suppressing pictogram');
          isSightWord = true;
          return PictogramResult(imageUrl: null, isSightWord: true, originalText: text);
        }
      } else {
        // debugPrint('🔤 PictogramService: SightWordService not initialized - proceeding with normal pictogram logic');
      }
    }

    final imageUrl = await _getImageUrl(originalText, keywords: keywords, shouldLogMissing: shouldLogMissing);
    return PictogramResult(imageUrl: imageUrl, isSightWord: isSightWord, originalText: text);
  }

  /// Legacy method - kept for backward compatibility
  /// Get pictogram/image URL for a given text
  /// Returns null if pictograms are disabled, text is a sight word, or no image found
  Future<String?> getPictogramForText(String text, {bool enablePictograms = true, String? sightWordGradeLevel, bool enableSightWords = true}) async {
    // Set the instance enable flag
    this.enablePictograms = enablePictograms;
    
    // Convert string grade level to int
    int? gradeLevel;
    if (sightWordGradeLevel != null) {
      gradeLevel = int.tryParse(sightWordGradeLevel);
    }
    
    final result = await getPictogramResult(text, sightWordGradeLevel: gradeLevel, enableSightWords: enableSightWords);
    return result?.imageUrl;
  }

  /// Internal method to get image URL with custom images priority
  Future<String?> _getImageUrl(String text, {List<String>? keywords, bool shouldLogMissing = true}) async {
    final normalizedText = text.toLowerCase().trim();
    debugPrint('🚨 _getImageUrl called with original: "$text" → normalized for cache: "$normalizedText"');
    
    // Check cache first
    if (_imageCache.containsKey(normalizedText)) {
      final cachedResult = _imageCache[normalizedText];
      return cachedResult;
    }

    try {
      // PRIORITY 1: Check preloaded custom images cache first
      if (_customImagesPreloaded && _customImageMatches.containsKey(text)) {
        final customImageUrl = _customImageMatches[text]!;
        debugPrint('⚡ PictogramService: Using preloaded custom image for "$text"');
        _imageCache[normalizedText] = customImageUrl;
        await _saveCacheToPrefs();
        return customImageUrl;
      }
      
      // PRIORITY 2: Fallback to individual custom image lookup (if user context available)
      if (_currentUserId != null && _currentIdToken != null) {
        try {
          // Special debug for single character queries that might match Lily
          if (text.length == 1) {
            debugPrint('🚨 PictogramService: SINGLE CHARACTER QUERY - "$text" (fallback lookup)');
          }
          
          final customImage = await CustomImageService.findBestMatch(
            concept: text,
            idToken: _currentIdToken!,
            aacUserId: _currentUserId!,
            shouldLogMissing: shouldLogMissing,
          );
          
          if (customImage != null) {
            // Special warning for single character matches that might be false positives
            if (text.length == 1 && !customImage.tags.any((tag) => tag.toLowerCase() == text.toLowerCase())) {
              debugPrint('⚠️ PictogramService: FALSE POSITIVE - "$text" matched custom image with tags ${customImage.tags}');
            }
            
            // Cache the custom image result and add to preloaded cache
            _imageCache[normalizedText] = customImage.imageUrl;
            _customImageMatches[text] = customImage.imageUrl;
            await _saveCacheToPrefs();
            return customImage.imageUrl;
          }
        } catch (customImageError) {
          // Continue to global library on error
        }
      }

      // PRIORITY 3: Check global Firestore library (existing logic)
      // debugPrint('🚨 CALLING _fetchImageFromFirestore with original text: "$text" (cache key: "$normalizedText")');
      final imageUrl = await _fetchImageFromFirestore(text, keywords: keywords, shouldLogMissing: shouldLogMissing);
      
      if (imageUrl != null && imageUrl.isNotEmpty) {
        debugPrint('🔍 PictogramService: ✅ Found global image URL: $imageUrl');
        // Cache the result
        _imageCache[normalizedText] = imageUrl;
        await _saveCacheToPrefs();
        return imageUrl;
      }

      debugPrint('🔍 PictogramService: ❌ No image found for "$normalizedText" in global library');
      // No image found - cache null to avoid repeated API calls
      _imageCache[normalizedText] = null;
      await _saveCacheToPrefs();
      return null;
      
    } catch (e) {
      return null;
    }
  }

  /// Fetch image URL from Firestore via backend API
  Future<String?> _fetchImageFromFirestore(String text, {List<String>? keywords, bool shouldLogMissing = true}) async {
    final baseUrl = EnvironmentConfig.apiBaseUrl;
    // debugPrint('🔍 PictogramService: Server Base URL: $baseUrl');
    
    // Apply intelligent search term optimization to prioritize subjects/objects
    final optimizedSearchTerm = getOptimizedSearchTerm(text, keywords: keywords);
    debugPrint('🔍 Image search optimization: "$text" → "$optimizedSearchTerm" (keywords: $keywords)');
    
    // Use optimized search term for all strategies
    final searchText = optimizedSearchTerm.isNotEmpty ? optimizedSearchTerm : text;
    
    debugPrint('🚨 CRITICAL DEBUG: Original text="$text", Optimized="$optimizedSearchTerm", Final searchText="$searchText"');
    
    // 🚨 CRITICAL FIX: When shouldLogMissing=false, the deployed server ignores
    // log_missing=false and ALWAYS logs when 0 results are found. So we must
    // MINIMIZE calls that return 0 results. When the original text is multi-word
    // but optimized is single-word, try the ORIGINAL first — the server's internal
    // partial word matching can find matches (e.g., "joke" from "Scarecrow award joke")
    // that the optimized single word ("scarecrow") would miss.
    final bool originalIsMultiWord = text.contains(' ');
    final bool optimizedIsDifferent = searchText.toLowerCase().trim() != text.toLowerCase().trim();
    
    if (!shouldLogMissing && originalIsMultiWord && optimizedIsDifferent) {
      // Try original multi-word text FIRST — server does partial word matching internally
      debugPrint('🚨 SMART ORDER: shouldLogMissing=false, trying original multi-word text FIRST: "$text"');
      
      final images = await _trySearchWithTermRaw(text, baseUrl);
      if (images.isNotEmpty) {
        debugPrint('🚨 ✅ FOUND ${images.length} candidates for original text: "$text"');
        final bestImage = _selectBestImageMatch(images, text);
        final imageUrl = bestImage['image_url'] as String?;
        
        if (imageUrl != null) {
          debugPrint('🚨 ✅ BEST MATCH from original text: "${bestImage['name']}"');
          _imageCache[text.toLowerCase().trim()] = imageUrl;
          await _saveCacheToPrefs();
          return imageUrl;
        }
      }
      
      // Original text also failed — try optimized term as backup
      debugPrint('🚨 Original text failed, trying optimized: "$searchText"');
      if (searchText.contains(' ')) {
        final optImages = await _trySearchWithTermRaw(searchText, baseUrl);
        if (optImages.isNotEmpty) {
          final bestImage = _selectBestImageMatch(optImages, searchText);
          final imageUrl = bestImage['image_url'] as String?;
          if (imageUrl != null) {
            _imageCache[text.toLowerCase().trim()] = imageUrl;
            await _saveCacheToPrefs();
            return imageUrl;
          }
        }
      } else {
        final result = await _trySearchWithTermSilent(searchText, baseUrl);
        if (result != null) {
          _imageCache[text.toLowerCase().trim()] = result;
          await _saveCacheToPrefs();
          return result;
        }
      }
      
      // Both failed, return null (no more calls to prevent server logging)
      debugPrint('🚨 Both original and optimized failed for "$text" - returning null (shouldLogMissing=false)');
      return null;
    }
    
    // Standard flow (shouldLogMissing=true or optimized matches original)
    debugPrint('🚨 STEP 1: Trying optimized term: "$searchText" (single server call - server handles variations)');
    
    if (searchText.contains(' ')) {
      // Multi-word phrase - make ONE comprehensive search call
      // The server internally tries: exact tag, lowercase, underscore, partial word matches
      // So we don't need to try each variation as a separate API call
      debugPrint('🚨 MULTI-WORD SEARCH: "$searchText" (single API call, server handles variations internally)');
      
      final images = await _trySearchWithTermRaw(searchText, baseUrl);
      if (images.isNotEmpty) {
        debugPrint('🚨 ✅ FOUND ${images.length} candidates for: "$searchText"');
        final bestImage = _selectBestImageMatch(images, searchText);
        final imageUrl = bestImage['image_url'] as String?;
        
        if (imageUrl != null) {
          debugPrint('🚨 ✅ BEST MATCH SELECTED: "${bestImage['name']}" (Score: ${bestImage['priorityScore']})');
          _imageCache[text.toLowerCase().trim()] = imageUrl;
          await _saveCacheToPrefs();
          return imageUrl;
        }
      }
      
      debugPrint('🚨 ❌ Primary search failed for "$searchText"');
    } else {
      // Single word - try it directly
      // debugPrint('🚨 SINGLE WORD: Trying "$searchText"');
      var result = await _trySearchWithTermSilent(searchText, baseUrl);
      
      // If capitalized search failed, try lowercase (e.g. "Superman" -> "superman")
      if (result == null && searchText != searchText.toLowerCase()) {
        debugPrint('🚨 SINGLE WORD: Capitalized search failed, trying lowercase: "${searchText.toLowerCase()}"');
        result = await _trySearchWithTermSilent(searchText.toLowerCase(), baseUrl);
      }

      if (result != null) {
        // debugPrint('🚨 ✅ SUCCESS with single word: "$searchText"');
        _imageCache[text.toLowerCase().trim()] = result;
        await _saveCacheToPrefs();
        return result;
      }
    }
    
    // STRATEGY 2: Try processed keywords and variations
    // debugPrint('🔍 PictogramService: Strategy 2 - Keyword extraction and variations...');
    
    debugPrint('🚨 STEP 2: Optimized term failed, trying ONLY original text if different');
    
    // If optimized term failed and is different from original, try original text
    if (searchText != text.toLowerCase().trim()) {
      final originalResult = await _trySearchWithTermSilent(text, baseUrl);
      if (originalResult != null) {
        debugPrint('🚨 ✅ SUCCESS with original text: "$text"');
        _imageCache[text.toLowerCase().trim()] = originalResult;
        await _saveCacheToPrefs();
        return originalResult;
      }
    }
    
    debugPrint('🚨 STEP 3: Both optimized and original failed - SKIPPING dynamic search for multi-word phrases');
    
    // For multi-word phrases, DO NOT fall back to individual words - this causes "world" matches
    if (searchText.contains(' ') || text.contains(' ')) {
      debugPrint('🚨 REFUSING individual word fallback for multi-word phrase: "$text"');
      debugPrint('🚨 This prevents matching generic words like "world" instead of "Disney World"');
      
      // When shouldLogMissing=false, DON'T make more API calls. The server already
      // searched comprehensively in STEP 1 (exact, lowercase, underscore, partial words).
      // Extra calls with different params (subconcept, concept, limit=1) create different
      // cache keys and each one that returns 0 results causes the server to log missing_images.
      if (!shouldLogMissing) {
        debugPrint('🚨 shouldLogMissing=false - skipping final search to prevent server-side logging');
        return null;
      }
      
      // Log as missing using ONLY the original text
      final finalResult = await _trySearchWithTermOriginalOnly(text, baseUrl, shouldLogMissing);
      return finalResult; // Will be null but logs the missing image
    }
    
    debugPrint('🚨 STEP 4: Single word - proceeding to dynamic search');
    
    // When shouldLogMissing=false, skip dynamic keyword search entirely.
    // STEP 1 already made a comprehensive server search. The dynamic search tries
    // multiple extracted keywords, each a separate API call that could trigger
    // server-side missing_images logging on failure.
    if (!shouldLogMissing) {
      debugPrint('🚨 shouldLogMissing=false - skipping dynamic search to prevent server-side logging for "$text"');
      return null;
    }
    
    // DYNAMIC APPROACH: Only for single words
    final extractedKeywords = _extractKeywords(text);
    debugPrint('🔧 DEBUG: DYNAMIC SEARCH - Processing "$text" with keywords: $extractedKeywords');
    
    // Try comprehensive search with the original phrase first (best chance for exact match)
    debugPrint('🔧 DEBUG: Trying comprehensive search with full phrase: "$text"');
    final fullPhraseResult = await _trySearchWithTermSilent(text, baseUrl);
    if (fullPhraseResult != null) {
      debugPrint('🔍 PictogramService: ✅ Found image with full phrase "$text"');
      return fullPhraseResult;
    }
    
    // If full phrase fails, try each individual keyword and collect results
    debugPrint('🔧 DEBUG: Full phrase failed, trying individual keywords dynamically...');
    final searchCandidates = <Map<String, dynamic>>[];
    
    // Add original text as a candidate
    searchCandidates.add({
      'term': text.toLowerCase().trim(),
      'source': 'original',
      'priority': 100,
    });
    
    // Add each keyword as a candidate
    for (final keyword in extractedKeywords) {
      searchCandidates.add({
        'term': keyword,
        'source': 'keyword',  
        'priority': 50,
      });
    }
    
    // Try each candidate and collect successful results
    final successfulResults = <Map<String, dynamic>>[];
    for (final candidate in searchCandidates) {
      final term = candidate['term'] as String;
      debugPrint('🔧 DEBUG: Trying dynamic search candidate: "$term"');
      
      final result = await _trySearchWithTermSilent(term, baseUrl);
      if (result != null) {
        successfulResults.add({
          'url': result,
          'term': term,
          'source': candidate['source'],
          'priority': candidate['priority'],
        });
        debugPrint('🔍 SUCCESS: Found image for "$term" (${candidate['source']})');
      }
    }
    
    // If we found multiple results, return the highest priority one
    if (successfulResults.isNotEmpty) {
      // Sort by priority (highest first)
      successfulResults.sort((a, b) => (b['priority'] as int).compareTo(a['priority'] as int));
      final bestResult = successfulResults.first;
      debugPrint('🔍 PictogramService: ✅ DYNAMIC SELECTION - Best result: "${bestResult['term']}" (${bestResult['source']})');
      return bestResult['url'] as String;
    }
    
    debugPrint('🔧 DEBUG: All dynamic search attempts failed, falling back to static keyword selection');
    
    // Fallback to static approach if dynamic search fails
    final searchKeyword = _selectMeaningfulKeyword(extractedKeywords, text);
    debugPrint('🔧 DEBUG: Fallback - Using static keyword: "$searchKeyword"');
    
    final searchTerms = _generateSearchVariations(searchKeyword);
    // debugPrint('🔧 DEBUG: Trying word variants for "$searchKeyword": $searchTerms');
    
    // CRITICAL: Remove the original text from searchTerms to avoid duplicate logging
    // We already tried the original text in Strategy 1, so only try actual variations here
    final actualVariations = searchTerms.where((term) => term != text.toLowerCase()).toList();
    // debugPrint('🔧 DEBUG: Filtered variations (excluding original): $actualVariations');
    
    // NOTE: Since _generateSearchVariations now only returns original text, actualVariations will be empty
    if (actualVariations.isEmpty) {
      // debugPrint('🔍 PictogramService: Strategy 2 - No variations available (variations disabled), skipping to Strategy 3');
    } else {
      // Try variations with processed keywords (no missing image logging yet)
      for (final searchTerm in actualVariations) {
        // debugPrint('🔍 PictogramService: Strategy 2 - Trying variation: "$searchTerm" (silent search, no logging)');
        final searchResult = await _trySearchWithTermSilent(searchTerm, baseUrl);
        if (searchResult != null) {
          // debugPrint('🔍 PictogramService: ✅ Found image with keyword variation: "$searchTerm"');
          return searchResult;
        }
        // debugPrint('🔍 PictogramService: ❌ No image found for variation: "$searchTerm"');
      }
    }
    
    // STRATEGY 3: If ALL strategies failed, make ONE final call with ONLY the exact original text
    // This ensures only the actual button text is logged as missing, not variations like "slang" + "slangs" 
    // debugPrint('🔍 PictogramService: ❌ All silent searches failed for "$text" - making final call to log ONLY ORIGINAL TEXT as missing');
    // debugPrint('🔍 PictogramService: CRITICAL - Only logging exact text "$text", NOT any variations');
    // debugPrint('🔍 PictogramService: 🚨 ABOUT TO LOG MISSING IMAGE FOR: "$text"');
    
    // When shouldLogMissing=false, skip the final fallback call entirely.
    // The server already searched comprehensively in STEP 1. The fallback strategies
    // (subconcept-only, tag-only, concept-only with limit=1) create different cache keys
    // and each failed one triggers server-side missing_images logging.
    if (!shouldLogMissing) {
      debugPrint('🚨 shouldLogMissing=false - skipping final search to prevent server-side logging for "$text"');
      return null;
    }
    
    // Use ONLY the original text for the final missing image logging call (no variations)
    final finalResult = await _trySearchWithTermOriginalOnly(text, baseUrl, shouldLogMissing);
    
    // debugPrint('🔧 DEBUG: ❌ No images found for any variation of "$text" using all strategies');
    // debugPrint('🔧 DEBUG: Missing image logged for ORIGINAL TEXT ONLY: "$text"');
    // debugPrint('🔍 PictogramService: 🚨 MISSING IMAGE LOGGING COMPLETED FOR: "$text"');
    return finalResult; // This will be null, but the server will have logged only the original text
  }

  /// Final search method that uses comprehensive search with missing image logging
  Future<String?> _trySearchWithTermOriginalOnly(String originalText, String baseUrl, bool shouldLogMissing) async {
    // debugPrint('🔍 PictogramService: Final comprehensive search for "$originalText" (will trigger missing image logging if no results)');
    
    // Use tag-only search as the primary search strategy
    // Increased limit to 20 to ensure we get the best candidates
    final logMissingParam = shouldLogMissing ? 'true' : 'false';
    final comprehensiveUrl = '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(originalText)}&limit=20&log_missing=$logMissingParam';
    
    try {
      debugPrint('🔍 PictogramService: Final comprehensive search attempt for "$originalText"');
      
      final response = await http.get(
        Uri.parse(comprehensiveUrl),
        headers: {
          'Content-Type': 'application/json',
          // Note: Global image library doesn't need user authentication
          // Custom user images feature will add auth headers when implemented
        },
      ).timeout(const Duration(seconds: 5)); // Increased timeout to allow all fallback strategies to complete

      debugPrint('PictogramService: Final comprehensive API response ${response.statusCode} for "$originalText"');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('🔧 DEBUG: Final comprehensive API response for "$originalText": $data');
        
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          if (images.isNotEmpty) {
            final firstImage = images[0];
            if (firstImage is Map<String, dynamic> && firstImage['image_url'] != null) {
              final imageUrl = firstImage['image_url'].toString();
              debugPrint('🔍 PictogramService: ✅ Final comprehensive search found image for "$originalText": $imageUrl');
              return imageUrl;
            }
          }
        }
      } else {
        debugPrint('PictogramService: Final comprehensive API error ${response.statusCode} for "$originalText": ${response.body}');
      }
    } catch (e) {
      debugPrint('PictogramService: Final comprehensive search exception for "$originalText": $e');
    }
    
    // If comprehensive search fails, try individual strategies as fallback
    debugPrint('🔍 PictogramService: Final comprehensive search failed, trying individual fallback strategies...');
    
    final fallbackStrategies = [
      {'name': 'subconcept-only', 'url': '$baseUrl/api/imagecreator/search?subconcept=${Uri.encodeComponent(originalText)}&limit=1&log_missing=false'},
      {'name': 'tag-only', 'url': '$baseUrl/api/imagecreator/search?tag=${Uri.encodeComponent(originalText)}&limit=1&log_missing=false'},
      {'name': 'concept-only', 'url': '$baseUrl/api/imagecreator/search?concept=${Uri.encodeComponent(originalText)}&limit=1&log_missing=false'},
    ];

    for (final strategy in fallbackStrategies) {
      try {
        final url = strategy['url']!;
        // final strategyName = strategy['name']!;
        
        // debugPrint('🔍 PictogramService: Final search attempt for ORIGINAL TEXT "$originalText" using $strategyName strategy (log_missing=true)');
        
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 5)); // Increased timeout to allow all fallback strategies to complete

        // debugPrint('PictogramService: Final API response ${response.statusCode} for ORIGINAL TEXT "$originalText" ($strategyName)');
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // debugPrint('🔧 DEBUG: Final API response for ORIGINAL TEXT "$originalText" ($strategyName): $data');
          
          // Handle the response structure: {images: [...], total_found: n, ...}
          if (data is Map<String, dynamic> && data['images'] is List) {
            final images = data['images'] as List;
            if (images.isNotEmpty) {
              final firstImage = images[0];
              if (firstImage is Map<String, dynamic> && firstImage['url'] != null) {
                final imageUrl = firstImage['url'].toString();
                // debugPrint('🔍 PictogramService: ✅ Final search found image for ORIGINAL TEXT "$originalText": $imageUrl');
                return imageUrl;
              }
            }
          }
        } else {
          // debugPrint('PictogramService: Final API error ${response.statusCode} for ORIGINAL TEXT "$originalText" ($strategyName): ${response.body}');
        }
      } catch (e) {
        // debugPrint('PictogramService: Final search exception for ORIGINAL TEXT "$originalText": $e');
      }
    }
    
    // debugPrint('🔍 PictogramService: ❌ Final search completed - no image found for ORIGINAL TEXT "$originalText"');
    debugPrint('🔍 PictogramService: ✅ Missing image logging completed for ORIGINAL TEXT ONLY: "$originalText"');
    return null;
  }

  /// Select the best image match using frontend prioritization
  /// Prioritizes: 1) Subconcept exact match, 2) Tag 0 match, 3) Tag 1 match, 4) Other tag matches
  Map<String, dynamic> _selectBestImageMatch(List<dynamic> images, String searchTerm) {
    final searchTermLower = searchTerm.toLowerCase().trim();
    debugPrint('🔍 Frontend prioritization: Evaluating ${images.length} images for "$searchTerm"');
    
    // Identify head noun (last word) for compound terms
    String? headNoun;
    final genericEndings = {
      'world', 'land', 'city', 'park', 'center', 'station', 'street', 'road', 'avenue', 'place', 'building', 'system', 'group',
      // Add pronouns and demonstratives
      'this', 'that', 'these', 'those', 'it',
      'me', 'you', 'him', 'her', 'us', 'them',
      'something', 'someone', 'somebody', 'anything', 'anyone', 'anybody', 'everything', 'everyone', 'everybody', 'nothing', 'nobody'
    };
    final words = searchTermLower.split(' ');
    if (words.length > 1) {
      final candidateHead = words.last.trim();
      // Only consider it a head noun if it's NOT a generic ending
      if (!genericEndings.contains(candidateHead)) {
        headNoun = candidateHead;
        debugPrint('🔍 Compound term detected. Head noun: "$headNoun"');
      } else {
        debugPrint('🔍 Compound term detected but head noun "$candidateHead" is generic. Ignoring head noun logic.');
      }
    }
    
    // Score each image based on match quality
    final scoredImages = <Map<String, dynamic>>[];
    
    for (final image in images) {
      final subconcept = (image['subconcept'] as String? ?? '').toLowerCase().trim();
      final subconceptNormalized = subconcept.replaceAll('_', ' ');
      final tags = image['tags'] as List? ?? [];
      final imageName = image['name'] as String? ?? 'unknown';
      
      // Check if all words from search term are present in tags or subconcept
      // This helps with "living room" matching tags ["living", "room"]
      final searchWords = searchTermLower.split(' ');
      final allWordsPresent = searchWords.length > 1 && searchWords.every((w) => 
          subconceptNormalized.contains(w) || 
          tags.any((t) => t.toString().toLowerCase().trim() == w)
      );
      
      int score = 0;
      String matchReason = '';
      
      // HIGHEST PRIORITY: Subconcept exact match (score: 1000)
      // Allow matching "living_room" with "living room"
      if (subconcept.isNotEmpty && (subconcept == searchTermLower || subconceptNormalized == searchTermLower)) {
        score = 1000;
        matchReason = 'Subconcept exact match';
      }
      // HIGH PRIORITY: Tag 0 exact match (score: 800)
      else if (tags.isNotEmpty && tags[0].toString().toLowerCase().trim() == searchTermLower) {
        score = 800;
        matchReason = 'Tag 0 exact match';
      }
      // MEDIUM PRIORITY: Tag 1 exact match (score: 600)
      else if (tags.length > 1 && tags[1].toString().toLowerCase().trim() == searchTermLower) {
        score = 600;
        matchReason = 'Tag 1 exact match';
      }
      // ALL WORDS PRESENT (score: 750) - New logic for "living room" -> ["living", "room"]
      else if (allWordsPresent) {
        score = 750;
        matchReason = 'All words present in tags/subconcept';
      }
      // HEAD NOUN EXACT MATCH (score: 500) - New logic for "Denver Broncos" -> "Broncos"
      else if (headNoun != null && (subconcept == headNoun || tags.any((t) => t.toString().toLowerCase().trim() == headNoun))) {
        score = 500;
        matchReason = 'Head noun exact match ($headNoun)';
      }
      // HEAD NOUN PARTIAL MATCH (score: 450) - New logic for "Denver Broncos" -> "Broncos" (partial)
      else if (headNoun != null && (subconcept.contains(headNoun) || tags.any((t) => t.toString().toLowerCase().trim().contains(headNoun!)))) {
        score = 450;
        matchReason = 'Head noun partial match ($headNoun)';
      }
      // LOWER PRIORITY: Other tag matches (score: 400 - position penalty)
      else {
        for (int i = 2; i < tags.length && i < 5; i++) {
          if (tags[i].toString().toLowerCase().trim() == searchTermLower) {
            score = 400 - (i * 50); // Penalty for higher tag positions
            matchReason = 'Tag $i exact match';
            break;
          }
        }
      }
      
      // FALLBACK: Partial matches (score: 100-300)
      if (score == 0) {
        int subconceptScore = 0;
        String subconceptReason = '';
        // genericEndings is already defined at the top of the function now
        
        // Split subconcept matching:
        // 1. Subconcept contains search term (e.g. "Denver Broncos" contains "Broncos") -> Stronger match (300)
        // 2. Search term contains subconcept (e.g. "Denver Broncos" contains "Denver") -> Weaker match (100)
        if (subconcept.contains(searchTermLower)) {
          subconceptScore = 300;
          subconceptReason = 'Subconcept contains search term';
        } else if (searchTermLower.contains(subconcept)) {
          subconceptScore = 100;
          // Bonus for matching end of search term (head of compound)
          if (searchTermLower.endsWith(subconcept) && !genericEndings.contains(subconcept)) {
            subconceptScore += 200; // Boost to 300 to compete with tags
          } else if (searchTermLower.startsWith(subconcept)) {
            subconceptScore += 20; // Slight boost for start match
          }
          subconceptReason = 'Search term contains subconcept';
        }
        
        int tagScore = 0;
        String tagReason = '';
        
        // Check tags for partial matches
        for (int i = 0; i < tags.length && i < 5; i++) {
          final tag = tags[i].toString().toLowerCase().trim();
          if (tag.isNotEmpty) {
            if (tag.contains(searchTermLower) || searchTermLower.contains(tag)) {
              int currentTagScore = 150 - (i * 10);
              
              // Bonus for matching end of search term (head of compound)
              if (searchTermLower.endsWith(tag) && !genericEndings.contains(tag)) {
                currentTagScore += 200; // Boost to 350 - MASSIVE preference for head noun
              } else if (searchTermLower.startsWith(tag)) {
                currentTagScore += 20; // Slight boost for start match
              }
              
              // Keep the best tag score found for this image
              if (currentTagScore > tagScore) {
                tagScore = currentTagScore;
                tagReason = 'Tag $i partial match';
              }
              // Don't break, check all tags to find the best match
            }
          }
        }
        
        // Take the best of subconcept vs tag match
        if (subconceptScore >= tagScore && subconceptScore > 0) {
          score = subconceptScore;
          matchReason = subconceptReason;
        } else if (tagScore > 0) {
          score = tagScore;
          matchReason = tagReason;
        }
      }
      
      scoredImages.add({
        ...image,
        'priorityScore': score,
        'matchReason': matchReason,
      });
      
      debugPrint('🔍 Image "$imageName": score=$score, reason="$matchReason", subconcept="$subconcept", tags=${tags.take(3).toList()}');
    }
    
    // Sort by score (highest first)
    scoredImages.sort((a, b) => (b['priorityScore'] as int).compareTo(a['priorityScore'] as int));
    
    final bestMatch = scoredImages.first;
    debugPrint('🔍 ✅ SELECTED: "${bestMatch['name']}" with score ${bestMatch['priorityScore']} (${bestMatch['matchReason']})');
    
    return bestMatch;
  }

  /// DYNAMIC silent search that uses comprehensive server search for best results
  /// This allows the server's enhanced scoring system to find the best match
  Future<String?> _trySearchWithTermSilent(String searchTerm, String baseUrl) async {
    debugPrint('🔍 PictogramService: 🤫 DYNAMIC SILENT SEARCH for "$searchTerm" (log_missing=false)');
    debugPrint('🔍 BASE URL: $baseUrl');
    
    // CRITICAL: Do NOT force lowercase. Respect the casing of the search term.
    // This allows searching for "Something" (Capitalized) if needed.
    final encodedTerm = Uri.encodeComponent(searchTerm);
    debugPrint('🔧 DEBUG API: term="$searchTerm", encoded="$encodedTerm"');
    
    // Use tag-only search as the primary search strategy
    // PREVIOUSLY: We sent tag, concept, AND subconcept, but the backend ANDs them together,
    // causing matches to fail unless the image had the term in ALL fields.
    // Now we prioritize the tag search which is the most comprehensive.
    final comprehensiveUrl = '$baseUrl/api/imagecreator/search?tag=$encodedTerm&limit=20&log_missing=false';
    
    try {
      // debugPrint('PictogramService: Comprehensive search for "$searchTerm"');
      debugPrint('🔍 MAKING HTTP GET REQUEST TO: $comprehensiveUrl');
      
      final response = await http.get(
        Uri.parse(comprehensiveUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('🔍 ⏰ TIMEOUT: Comprehensive search request timed out after 8 seconds for "$searchTerm"');
          throw Exception('Comprehensive search timeout for "$searchTerm"');
        },
      );
      
      // debugPrint('🔍 HTTP REQUEST COMPLETED for "$searchTerm" - about to process response');
      // debugPrint('✅ HTTP RESPONSE RECEIVED - Status: ${response.statusCode} for "$searchTerm" (comprehensive)');
      // debugPrint('🔍 RESPONSE BODY PREVIEW: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // debugPrint('🔍 PARSED DATA TYPE: ${data.runtimeType}');
        
        if (data is Map<String, dynamic> && data['images'] is List) {
          final images = data['images'] as List;
          // debugPrint('PictogramService: Comprehensive search found ${images.length} images for "$searchTerm"');
          // debugPrint('🔍 FULL RESPONSE: ${response.body}');
          
          if (images.isNotEmpty) {
            // Apply frontend prioritization instead of trusting backend scoring
            debugPrint('🔍 *** APPLYING FRONTEND PRIORITIZATION for "$searchTerm" with ${images.length} images ***');
            
            // DEBUG: Print all candidates to understand why the correct one might be missed
            for (int i = 0; i < images.length; i++) {
              final img = images[i];
              debugPrint('🔍 CANDIDATE $i: name="${img['name']}", subconcept="${img['subconcept']}", tags=${img['tags']}');
            }
            
            final bestImage = _selectBestImageMatch(images, searchTerm);
            final imageUrl = bestImage['image_url'] as String?;
            final imageName = bestImage['name'] as String? ?? 'unknown';
            final subconcept = bestImage['subconcept'] as String? ?? '';
            final tags = bestImage['tags'] as List? ?? [];
            
            debugPrint('🔍 ✅ Best match selected by frontend prioritization for "$searchTerm": $imageName');
            debugPrint('🔍 Image details: subconcept="$subconcept", tags=$tags');
            debugPrint('🔍 *** FRONTEND PRIORITIZATION COMPLETE - SELECTED IMAGE URL: $imageUrl ***');
            debugPrint('PictogramService: ✅ Comprehensive search found image URL for "$searchTerm": $imageUrl');
            debugPrint('🔍 RETURNING URL: $imageUrl');
            return imageUrl;
          } else {
            debugPrint('PictogramService: Comprehensive search - no images found for "$searchTerm"');
          }
        } else {
          debugPrint('PictogramService: Comprehensive search - unexpected response format for "$searchTerm"');
          debugPrint('🔍 UNEXPECTED DATA: ${data}');
        }
      } else {
        debugPrint('PictogramService: Comprehensive search - API returned ${response.statusCode} for "$searchTerm"');
        debugPrint('🔍 ERROR RESPONSE BODY: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('🔍 ❌ EXCEPTION: Comprehensive search error for "$searchTerm": $e');
      debugPrint('🔍 STACK TRACE: $stackTrace');
    }
    
    // If comprehensive search fails, fall back to individual strategies
    debugPrint('🔍 PictogramService: Comprehensive search failed, trying individual strategies...');
    
    // Try individual search strategies in priority order (subconcept first!)
    // Use higher limit to get more candidates for prioritization
    // CRITICAL: Use ORIGINAL CASE for fallbacks to support case-sensitive backends
    final fallbackStrategies = [
      {'name': 'subconcept-only', 'url': '$baseUrl/api/imagecreator/search?subconcept=$encodedTerm&limit=5&log_missing=false'},
      {'name': 'concept-only', 'url': '$baseUrl/api/imagecreator/search?concept=$encodedTerm&limit=5&log_missing=false'},
    ];

    for (final strategy in fallbackStrategies) {
      try {
        final url = strategy['url']!;
        final strategyName = strategy['name']!;
        
        debugPrint('PictogramService: Silent search for "$searchTerm" using $strategyName strategy');
        debugPrint('🔍 MAKING HTTP GET REQUEST TO: $url');
        
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
          },
        ).timeout(
          const Duration(seconds: 8), // Shorter timeout for silent searches
          onTimeout: () {
            debugPrint('🔍 ⏰ TIMEOUT: Silent search request timed out after 8 seconds for "$searchTerm" ($strategyName)');
            throw Exception('Silent search timeout for "$searchTerm" using $strategyName');
          },
        );
        
        debugPrint('🔍 HTTP REQUEST COMPLETED for "$searchTerm" - about to process response');
        debugPrint('✅ HTTP RESPONSE RECEIVED - Status: ${response.statusCode} for "$searchTerm" ($strategyName)');
        debugPrint('🔍 RESPONSE BODY LENGTH: ${response.body.length} characters');
        debugPrint('🔍 RESPONSE BODY PREVIEW: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('🔍 PARSED DATA TYPE: ${data.runtimeType}');
          
          // Handle the response structure: {images: [...], total_found: n, ...}
          if (data is Map<String, dynamic> && data['images'] is List) {
            final images = data['images'] as List;
            debugPrint('PictogramService: Silent search found ${images.length} images for "$searchTerm" using $strategyName');
            debugPrint('🔍 FULL RESPONSE: ${response.body}');
            
            if (images.isNotEmpty) {
              // Apply frontend prioritization for fallback strategies too
              debugPrint('🔍 *** APPLYING FRONTEND PRIORITIZATION in fallback strategy "$strategyName" for "$searchTerm" with ${images.length} images ***');
              final bestImage = _selectBestImageMatch(images, searchTerm);
              final imageUrl = bestImage['image_url'] as String?;
              final imageName = bestImage['name'] as String? ?? 'unknown';
              debugPrint('🔍 ✅ Silent search found image for "$searchTerm": $imageName');
              debugPrint('PictogramService: ✅ Silent search found image URL for "$searchTerm" using $strategyName: $imageUrl');
              debugPrint('🔍 *** FALLBACK PRIORITIZATION COMPLETE - SELECTED IMAGE URL: $imageUrl ***');
              debugPrint('🔍 RETURNING URL: $imageUrl');
              return imageUrl; // Return immediately on first success
            } else {
              debugPrint('PictogramService: Silent search - no images found for "$searchTerm" using $strategyName');
            }
          } else {
            debugPrint('PictogramService: Silent search - unexpected response format for "$searchTerm" ($strategyName)');
            debugPrint('🔍 UNEXPECTED DATA: ${data}');
          }
        } else {
          debugPrint('PictogramService: Silent search - API returned ${response.statusCode} for "$searchTerm" ($strategyName)');
          debugPrint('🔍 ERROR RESPONSE BODY: ${response.body}');
        }
      } catch (e, stackTrace) {
        debugPrint('🔍 ❌ EXCEPTION: Silent search error for "$searchTerm" (${strategy["name"]}): $e');
        debugPrint('🔍 STACK TRACE: $stackTrace');
        // Continue to next strategy
      }
    }
    
    // No image found with any silent strategy for this search term
    debugPrint('🔍 PictogramService: 🤫 SILENT SEARCH COMPLETED - NO MATCHES for "$searchTerm"');
    return null;
  }

  /// Helper method to get raw image data from search (for multi-variation aggregation)
  Future<List<Map<String, dynamic>>> _trySearchWithTermRaw(String searchTerm, String baseUrl) async {
    // CRITICAL: Do NOT force lowercase here. The caller (_fetchImageFromFirestore) constructs variations
    // with specific casing (e.g. "Something" vs "something") and we must respect that.
    // If the backend is case-sensitive, forcing lowercase will cause matches to fail.
    final encodedTerm = Uri.encodeComponent(searchTerm);
    final comprehensiveUrl = '$baseUrl/api/imagecreator/search?tag=$encodedTerm&limit=20&log_missing=false';
    
    debugPrint('🔍 RAW SEARCH: "$searchTerm" -> $comprehensiveUrl');
    
    try {
      final response = await http.get(
        Uri.parse(comprehensiveUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['images'] is List) {
          return List<Map<String, dynamic>>.from(data['images']);
        }
      }
    } catch (e) {
      debugPrint('Error in _trySearchWithTermRaw for "$searchTerm": $e');
    }
    return [];
  }

  /// Generate search variations (singular, plural, etc.)
  List<String> _generateSearchVariations(String text) {
    // DISABLED: Only return the original text to prevent plural/singular variations
    // This ensures only the exact button text is ever used for searching
    debugPrint('🔧 DEBUG: Variations disabled - returning only original text: "$text"');
    return [text.toLowerCase()];
  }

  /// Intelligently extracts search terms for image matching by prioritizing subjects/objects over action verbs
  String getOptimizedSearchTerm(String summary, {List<String>? keywords}) {
    if (summary.isEmpty) return '';
    
    // SPECIAL CASE: "Something Else" - preserve this specific phrase (check first!)
    if (summary.toLowerCase().contains('something else')) {
      debugPrint('🚨 ✅ PRESERVING SPECIAL PHRASE: "Something Else"');
      return "Something Else";
    }
    
    // debugPrint('🚨 OPTIMIZATION DEBUG: Processing "$summary" with keywords: $keywords');
    
    // PRIORITY 1: Use LLM keywords if available - they're often more specific than our heuristics
    if (keywords != null && keywords.isNotEmpty) {
      debugPrint('🚨 🎯 KEYWORDS AVAILABLE: Checking for multi-word compound terms in keywords');
      
      // Look for compound terms in keywords (multi-word phrases that should be kept together)
      for (final keyword in keywords) {
        final keywordWords = keyword.trim().split(RegExp(r'\s+'));
        if (keywordWords.length >= 2) {
          // Multi-word keyword - check if it's a compound term we should preserve
          final keywordCompound = _extractCompoundTerm(keyword);
          if (keywordCompound != null && keywordCompound.isNotEmpty) {
            // Use original keyword capitalization instead of the compound result
            final originalKeyword = keyword.trim();
            debugPrint('🚨 🎯 ✅ USING KEYWORD WITH ORIGINAL CASE: "$originalKeyword" from keyword "$keyword"');
            return originalKeyword;
          }
        }
      }
      
      // If no compound keywords found, use the first meaningful multi-word keyword with original case
      for (final keyword in keywords) {
        final keywordWords = keyword.trim().split(RegExp(r'\s+'));
        if (keywordWords.length >= 2) {
          final originalKeyword = keyword.trim();
          debugPrint('🚨 🎯 ✅ USING MULTI-WORD KEYWORD WITH ORIGINAL CASE: "$originalKeyword" from "$keyword"');
          return originalKeyword;
        }
      }
      
      debugPrint('🚨 🎯 No multi-word keywords found, falling back to heuristic analysis');
    }
    
    // PRIORITY 2: Check for compound terms that should be preserved as complete phrases
    final compoundTerm = _extractCompoundTerm(summary);
    debugPrint('🚨 COMPOUND TERM RESULT: "$compoundTerm" from "$summary"');
    if (compoundTerm != null && compoundTerm.isNotEmpty) {
      // Try to preserve original casing from the summary
      final originalLower = summary.toLowerCase();
      final startIndex = originalLower.indexOf(compoundTerm.toLowerCase());
      if (startIndex != -1) {
         final originalCase = summary.substring(startIndex, startIndex + compoundTerm.length);
         debugPrint('🚨 ✅ USING COMPOUND TERM WITH ORIGINAL CASE: "$originalCase"');
         return originalCase;
      }
      
      debugPrint('🚨 ✅ USING COMPOUND TERM: "$compoundTerm"');
      return compoundTerm;
    } else {
      debugPrint('🚨 ❌ NO COMPOUND TERM FOUND for "$summary"');
    }
    
    final questionWords = ['what', 'who', 'where', 'when', 'why', 'how'];
    final words = summary.toLowerCase().trim().split(RegExp(r'\s+'));
    
    // Common action verbs that should be deprioritized in favor of objects/subjects
    final commonActionVerbs = [
      'watch', 'see', 'look', 'view', 'observe', 'listen', 'hear', 'play', 'do', 'make', 'get', 'go', 'come',
      'eat', 'drink', 'read', 'write', 'talk', 'speak', 'say', 'tell', 'ask', 'answer', 'call', 'walk',
      'run', 'sit', 'stand', 'work', 'study', 'learn', 'teach', 'help', 'use', 'try', 'want', 'need',
      'like', 'love', 'hate', 'think', 'know', 'understand', 'feel', 'take', 'give', 'put', 'find',
      'buy', 'sell', 'pay', 'spend', 'save', 'open', 'close', 'start', 'stop', 'finish', 'continue'
    ];
    
    // Remove question words from the beginning
    List<String> meaningfulWords = List.from(words);
    while (meaningfulWords.isNotEmpty && questionWords.contains(meaningfulWords.first)) {
      meaningfulWords.removeAt(0);
    }
    
    // Remove common filler words and clean punctuation
    final fillerWords = [
      'is', 'are', 'the', 'a', 'an', 'that', 'this', 'it', 'do', 'does', 'did', 'can', 'will', 'would', 'should',
      // Pronouns to ignore for image matching
      'i', 'me', 'my', 'mine', 'myself',
      'you', 'your', 'yours', 'yourself',
      'he', 'him', 'his', 'himself',
      'she', 'her', 'hers', 'herself',
      'we', 'us', 'our', 'ours', 'ourselves',
      'they', 'them', 'their', 'theirs', 'themselves'
    ];
    meaningfulWords = meaningfulWords
        .where((word) => !fillerWords.contains(word))
        .map((word) => word.replaceAll(RegExp(r'[?!.,;:]'), ''))  // Remove punctuation
        .where((word) => word.isNotEmpty)  // Remove empty strings
        .toList();
    
    // Enhanced keyword processing - prioritize specific nouns over action verbs
    if (keywords != null && keywords.isNotEmpty) {
      final questionAndFillerWords = [...questionWords, ...fillerWords, 'question', 'curiosity', 'that', 'this'];
      final genericTerms = ['color', 'thing', 'object', 'item', 'stuff', 'shape', 'size'];
      
      // First, look for specific nouns that aren't action verbs
      final specificNounKeyword = keywords.firstWhere(
        (keyword) {
          final cleanKeyword = keyword.toLowerCase().trim().replaceAll(RegExp(r'[?!.,;:]'), '');
          return cleanKeyword.length > 2 && 
                 !questionAndFillerWords.contains(cleanKeyword) &&
                 !genericTerms.contains(cleanKeyword) &&
                 !commonActionVerbs.contains(cleanKeyword);
        },
        orElse: () => '',
      );
      
      if (specificNounKeyword.isNotEmpty) {
        final cleanKeyword = specificNounKeyword.toLowerCase().trim().replaceAll(RegExp(r'[?!.,;:]'), '');
        debugPrint('🔧 DEBUG: Using specific noun keyword: "$cleanKeyword"');
        return cleanKeyword;
      }
      
      // If no specific nouns found, fall back to any meaningful keyword
      final meaningfulKeyword = keywords.firstWhere(
        (keyword) {
          final cleanKeyword = keyword.toLowerCase().trim().replaceAll(RegExp(r'[?!.,;:]'), '');
          return cleanKeyword.length > 2 && 
                 !questionAndFillerWords.contains(cleanKeyword) &&
                 !genericTerms.contains(cleanKeyword);
        },
        orElse: () => '',
      );
      
      if (meaningfulKeyword.isNotEmpty) {
        final cleanKeyword = meaningfulKeyword.toLowerCase().trim().replaceAll(RegExp(r'[?!.,;:]'), '');
        debugPrint('🔧 DEBUG: Using meaningful keyword: "$cleanKeyword"');
        return cleanKeyword;
      }
    }
    
    // Enhanced word analysis - prioritize subjects/objects over action verbs
    if (meaningfulWords.isNotEmpty) {
      // For single word inputs that are specific, prefer the original case
      final originalWordLower = summary.toLowerCase().trim();
      final originalWord = summary.trim(); // Preserve original case
      if (meaningfulWords.length == 1 && originalWordLower.length > 2) {
        debugPrint('🔧 DEBUG: Using original single word with preserved case: "$originalWord"');
        return originalWord;
      }
      
      // Separate words into action verbs vs potential subjects/objects
      final originalWords = summary.trim().split(RegExp(r'\s+'));
      final nonActionWords = <String>[];
      final actionWords = <String>[];
      
      for (final word in meaningfulWords) {
        if (commonActionVerbs.contains(word)) {
          actionWords.add(word);
        } else {
          nonActionWords.add(word);
        }
      }
      
      // STRATEGY: Try multi-word combinations first before falling back to single words
      if (nonActionWords.length >= 2) {
        // Try to form meaningful multi-word combinations
        final multiWordCandidates = <String>[];
        
        // Try consecutive pairs and triplets of non-action words
        for (int i = 0; i < nonActionWords.length - 1; i++) {
          final twoWordCombo = '${nonActionWords[i]} ${nonActionWords[i + 1]}';
          multiWordCandidates.add(twoWordCombo);
          
          // Try three-word combinations if available
          if (i < nonActionWords.length - 2) {
            final threeWordCombo = '${nonActionWords[i]} ${nonActionWords[i + 1]} ${nonActionWords[i + 2]}';
            multiWordCandidates.add(threeWordCombo);
          }
        }
        
        // Try to reconstruct original case for multi-word combinations
        for (final candidate in multiWordCandidates) {
          final candidateWords = candidate.split(' ');
          final originalCaseCandidate = candidateWords.map((word) {
            return originalWords.firstWhere(
              (origWord) => origWord.toLowerCase().replaceAll(RegExp(r'[?!.,;:]'), '') == word,
              orElse: () => word,
            );
          }).join(' ');
          
          // Prefer longer, more specific combinations
          if (candidateWords.length >= 2) {
            debugPrint('🔧 DEBUG: Using multi-word subject/object combination: "$originalCaseCandidate" (avoided action verbs: $actionWords)');
            return originalCaseCandidate;
          }
        }
      }
      
      // Fallback: Use the longest single non-action word
      if (nonActionWords.isNotEmpty) {
        nonActionWords.sort((a, b) => b.length.compareTo(a.length));
        final selectedWord = nonActionWords.first;
        
        // Find the original case version
        final originalCaseWord = originalWords.firstWhere(
          (word) => word.toLowerCase().replaceAll(RegExp(r'[?!.,;:]'), '') == selectedWord,
          orElse: () => selectedWord,
        );
        
        debugPrint('🔧 DEBUG: Using single prioritized subject/object: "$originalCaseWord" (avoided action verbs: $actionWords)');
        return originalCaseWord;
      }
      
      // If only action words remain, use the longest one (but log this for debugging)
      meaningfulWords.sort((a, b) => b.length.compareTo(a.length));
      final selectedLowerWord = meaningfulWords.first;
      
      final originalCaseWord = originalWords.firstWhere(
        (word) => word.toLowerCase().replaceAll(RegExp(r'[?!.,;:]'), '') == selectedLowerWord,
        orElse: () => selectedLowerWord,
      );
      
      debugPrint('🔧 DEBUG: Only action verbs available, using: "$originalCaseWord" from $meaningfulWords');
      return originalCaseWord;
    }
    
    // Fallback to original summary if no meaningful words found (preserve case)
    debugPrint('🔧 DEBUG: No meaningful words found, using original: "${summary.trim()}"');
    return summary.trim();
  }

  /// Dynamically extract compound terms using linguistic patterns rather than hardcoded lists
  String? _extractCompoundTerm(String text) {
    final lowerText = text.toLowerCase();
    final words = lowerText.split(RegExp(r'\s+'));
    
    // Skip single words or very short phrases
    if (words.length < 2) return null;
    
    // PRIORITY 0: Check for "X and Y" patterns (category names like "Food and Drink")
    // This should be checked FIRST before other compound term detection
    for (int i = 0; i < words.length - 2; i++) {
      if (words[i + 1] == 'and') {
        final word1 = words[i];
        final word3 = words[i + 2];
        
        // Both words should be substantive (not articles, pronouns, etc.)
        final skipWords = {'a', 'an', 'the', 'i', 'me', 'you', 'he', 'she', 'it', 'we', 'they', 'this', 'that'};
        
        if (!skipWords.contains(word1) && !skipWords.contains(word3) && 
            word1.length > 2 && word3.length > 2) {
          // Found "X and Y" pattern - preserve original case from input text
          final originalWords = text.split(RegExp(r'\s+'));
          if (i + 2 < originalWords.length) {
            final compound = '${originalWords[i]} and ${originalWords[i + 2]}';
            debugPrint('🚨 ✅ FOUND "X and Y" PATTERN: "$compound" from "$text"');
            return compound;
          }
        }
      }
    }
    
    // Define word categories for dynamic compound detection
    final properNouns = _identifyProperNouns(text); // Capitalized words
    final nounIndicators = {'world', 'land', 'park', 'center', 'mall', 'house', 'tower', 'bridge', 'stadium', 'field', 'arena', 'hall'};
    final descriptiveWords = {'national', 'international', 'royal', 'grand', 'great', 'new', 'old', 'north', 'south', 'east', 'west', 'central', 'downtown'};
    final brandIndicators = {'inc', 'corp', 'co', 'company', 'studios', 'productions', 'entertainment', 'games', 'systems'};
    final sportsTeamWords = {'broncos', 'cowboys', 'packers', 'patriots', 'lakers', 'celtics', 'bulls', 'heat', 'yankees', 'giants', 'eagles', 'steelers'};
    
    debugPrint('🚨 COMPOUND DEBUG: Analyzing "$text"');
    debugPrint('🚨 WORDS: $words');
    debugPrint('🚨 PROPER NOUNS: $properNouns');
    debugPrint('🚨 NOUN INDICATORS: $nounIndicators');
    
    // STRATEGY 1: Look for proper noun + noun indicator patterns (Disney + World, Universal + Studios)
    for (int i = 0; i < words.length - 1; i++) {
      final currentWord = words[i];
      final nextWord = words[i + 1];
      
      debugPrint('🚨 CHECKING: "$currentWord" + "$nextWord"');
      debugPrint('🚨 - Is "$currentWord" a proper noun? ${properNouns.contains(currentWord)}');
      debugPrint('🚨 - Is "$nextWord" a noun indicator? ${nounIndicators.contains(nextWord)}');
      
      // Check if we have a proper noun followed by a common noun indicator
      if (properNouns.contains(currentWord) && nounIndicators.contains(nextWord)) {
        final compound = '$currentWord $nextWord';
        debugPrint('🚨 ✅ FOUND COMPOUND (proper + noun): "$compound"');
        return compound;
      }
      
      // Check for descriptive word + proper noun patterns (New York, Los Angeles)
      if (descriptiveWords.contains(currentWord) && properNouns.contains(nextWord)) {
        final compound = '$currentWord $nextWord';
        debugPrint('🔧 DEBUG: Found dynamic compound (descriptive + proper): "$compound"');
        return compound;
      }
      
      // Check for proper noun + sports team name (Denver Broncos, Los Angeles Lakers)
      if (properNouns.contains(currentWord) && sportsTeamWords.contains(nextWord)) {
        final compound = '$currentWord $nextWord';
        debugPrint('🔧 DEBUG: Found dynamic compound (proper + sports team): "$compound"');
        return compound;
      }
      
      // Check for proper noun + brand indicator (Universal Studios, Disney Productions)
      if (properNouns.contains(currentWord) && brandIndicators.contains(nextWord)) {
        final compound = '$currentWord $nextWord';
        debugPrint('🔧 DEBUG: Found dynamic compound (brand): "$compound"');
        return compound;
      }
    }
    
    // STRATEGY 2: Look for three-word combinations (New York City, Los Angeles Lakers)
    for (int i = 0; i < words.length - 2; i++) {
      final word1 = words[i];
      final word2 = words[i + 1];
      final word3 = words[i + 2];
      
      // Descriptive + Proper + Noun pattern (New York City)
      if (descriptiveWords.contains(word1) && properNouns.contains(word2) && 
          (nounIndicators.contains(word3) || properNouns.contains(word3))) {
        final compound = '$word1 $word2 $word3';
        debugPrint('🔧 DEBUG: Found dynamic compound (three-word): "$compound"');
        return compound;
      }
      
      // Proper + Proper + Noun pattern (Harry Potter Movies, Star Wars Games)
      if (properNouns.contains(word1) && properNouns.contains(word2) && 
          (nounIndicators.contains(word3) || brandIndicators.contains(word3))) {
        final compound = '$word1 $word2 $word3';
        debugPrint('🔧 DEBUG: Found dynamic compound (proper-proper-noun): "$compound"');
        return compound;
      }
    }
    
    // STRATEGY 3: Look for any consecutive proper nouns (fallback for names like "Disney World")
    final consecutiveProperNouns = <String>[];
    for (int i = 0; i < words.length; i++) {
      if (properNouns.contains(words[i])) {
        if (consecutiveProperNouns.isEmpty) {
          consecutiveProperNouns.add(words[i]);
        } else {
          // Check if this continues a sequence
          if (i > 0 && properNouns.contains(words[i - 1])) {
            consecutiveProperNouns.add(words[i]);
          } else {
            // Break in sequence, check if we have a valid compound
            if (consecutiveProperNouns.length >= 2) {
              final compound = consecutiveProperNouns.join(' ');
              debugPrint('🔧 DEBUG: Found dynamic compound (consecutive proper nouns): "$compound"');
              return compound;
            }
            consecutiveProperNouns.clear();
            consecutiveProperNouns.add(words[i]);
          }
        }
      } else {
        // Non-proper noun, check if we have accumulated proper nouns
        if (consecutiveProperNouns.length >= 2) {
          final compound = consecutiveProperNouns.join(' ');
          debugPrint('🔧 DEBUG: Found dynamic compound (final consecutive proper nouns): "$compound"');
          return compound;
        }
        consecutiveProperNouns.clear();
      }
    }
    
    // Final check for accumulated proper nouns at end of text
    if (consecutiveProperNouns.length >= 2) {
      final compound = consecutiveProperNouns.join(' ');
      debugPrint('🔧 DEBUG: Found dynamic compound (end consecutive proper nouns): "$compound"');
      return compound;
    }
    
    return null;
  }
  
  /// Identify proper nouns by looking at capitalization in the original text
  Set<String> _identifyProperNouns(String originalText) {
    final properNouns = <String>{};
    final words = originalText.split(RegExp(r'\s+'));
    
    // Words to never consider proper nouns even if capitalized (pronouns, prepositions, common verbs)
    final commonWords = {
      'this', 'that', 'these', 'those', 
      'me', 'you', 'him', 'her', 'it', 'us', 'them',
      'my', 'your', 'his', 'its', 'our', 'their',
      'what', 'where', 'when', 'why', 'how', 'who',
      'is', 'are', 'was', 'were', 'be', 'been',
      'do', 'does', 'did', 'done',
      'have', 'has', 'had',
      'can', 'could', 'will', 'would', 'shall', 'should',
      'a', 'an', 'the',
      'and', 'but', 'or', 'nor', 'for', 'yet', 'so',
      'in', 'on', 'at', 'to', 'from', 'by', 'with', 'about',
      'please', 'thank', 'thanks', 'hello', 'hi', 'bye', 'goodbye'
    };
    
    debugPrint('🚨 PROPER NOUN ANALYSIS START for: "$originalText"');
    debugPrint('🚨 Words to analyze: $words');
    
    for (int i = 0; i < words.length; i++) {
      final word = words[i].replaceAll(RegExp(r'[^\w]'), ''); // Remove punctuation
      final lowerWord = word.toLowerCase();
      
      // Skip if empty, too short, or is a common word
      if (word.length < 2 || commonWords.contains(lowerWord)) {
        debugPrint('🚨 SKIPPING (too short or common): word="$word"');
        continue;
      }
      
      // Check if word is capitalized (but not if it's the first word of the sentence)
      final isCapitalized = word[0] == word[0].toUpperCase() && word.substring(1) == word.substring(1).toLowerCase();
      final isFirstWord = i == 0;
      final nextWordCapitalized = i < words.length - 1 && words[i + 1].isNotEmpty && words[i + 1][0] == words[i + 1][0].toUpperCase();
      
      debugPrint('🚨 WORD CHECK: "$word" - isCapitalized=$isCapitalized, isFirstWord=$isFirstWord, nextCapitalized=$nextWordCapitalized');
      
      // Consider it a proper noun if:
      // 1. It's capitalized and not the first word, OR
      // 2. It's capitalized, is the first word, but the next word is also capitalized (indicating a name)
      if (isCapitalized && (!isFirstWord || (i < words.length - 1 && words[i + 1].isNotEmpty && words[i + 1][0] == words[i + 1][0].toUpperCase()))) {
        properNouns.add(word.toLowerCase());
        debugPrint('🚨 ✅ ADDED PROPER NOUN: "$word" -> "${word.toLowerCase()}"');
      } else {
        debugPrint('🚨 ❌ NOT PROPER NOUN: "$word" (capitalized=$isCapitalized, firstWord=$isFirstWord, nextCap=$nextWordCapitalized)');
      }
    }
    
    debugPrint('🚨 FINAL PROPER NOUNS DETECTED: $properNouns');
    return properNouns;
  }

  /// Save cache to SharedPreferences for persistence
  Future<void> _saveCacheToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = jsonEncode(_imageCache);
      await prefs.setString('pictogram_cache', cacheJson);
    } catch (e) {
      debugPrint('Error saving pictogram cache: $e');
    }
  }

  /// Load cache from SharedPreferences (global shared library)
  Future<void> loadCacheFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString('pictogram_cache');
      final cachedEnvironment = prefs.getString('pictogram_cache_environment');
      final currentEnvironment = EnvironmentConfig.environmentName;
      
      debugPrint('🔧 PictogramService: Loading global image cache (user: $_currentUserId)');
      debugPrint('🔧 PictogramService: Current environment: $currentEnvironment, Cached environment: $cachedEnvironment');
      
      // Clear cache if environment changed
      if (cachedEnvironment != null && cachedEnvironment != currentEnvironment) {
        debugPrint('⚠️ PictogramService: Environment changed from $cachedEnvironment to $currentEnvironment - clearing cache');
        _imageCache.clear();
        await prefs.remove('pictogram_cache');
        await prefs.setString('pictogram_cache_environment', currentEnvironment);
        return;
      }
      
      if (cacheJson != null) {
        final Map<String, dynamic> decodedCache = jsonDecode(cacheJson);
        _imageCache.clear();
        decodedCache.forEach((key, value) {
          _imageCache[key] = value as String?;
        });
        debugPrint('🔧 PictogramService: Loaded ${_imageCache.length} cached items from global library');
      } else {
        debugPrint('🔧 PictogramService: No cached items found in global library');
      }
      
      // Store current environment
      await prefs.setString('pictogram_cache_environment', currentEnvironment);
    } catch (e) {
      debugPrint('Error loading pictogram cache: $e');
    }
  }

  /// Clear the image cache
  Future<void> clearCache() async {
    _imageCache.clear();
    _customImageMatches.clear();
    _customImagesPreloaded = false;
    CustomImageService.clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pictogram_cache');
      debugPrint('🔄 PictogramService: Cache cleared - all cached images removed');
    } catch (e) {
      debugPrint('Error clearing pictogram cache: $e');
    }
  }
  
  /// Batch preload custom images and build match cache
  Future<void> preloadCustomImages(List<String> buttonTexts) async {
    if (_currentUserId == null || _currentIdToken == null) {
      debugPrint('📭 PictogramService: No user context for custom image preloading');
      return;
    }
    
    if (_customImagesPreloaded) {
      debugPrint('📚 PictogramService: Custom images already preloaded (${_customImageMatches.length} matches cached)');
      return;
    }
    
    try {
      debugPrint('🚀 PictogramService: Batch preloading custom images for ${buttonTexts.length} buttons');
      
      // Fetch all custom images once
      final customImages = await CustomImageService.getCustomImages(
        idToken: _currentIdToken!,
        aacUserId: _currentUserId!,
        shouldLogMissing: false,
      );
      
      if (customImages.isEmpty) {
        debugPrint('📭 PictogramService: No custom images to preload');
        _customImagesPreloaded = true;
        return;
      }
      
      debugPrint('🔍 PictogramService: Building match cache for ${customImages.length} custom images');
      
      // Build match cache for all button texts
      for (final buttonText in buttonTexts) {
        for (final image in customImages) {
          if (image.matchesQuery(buttonText)) {
            _customImageMatches[buttonText] = image.imageUrl;
            debugPrint('✅ Preloaded match: "$buttonText" → "${image.concept}" (${image.imageUrl})');
            break; // Use first match
          }
        }
      }
      
      _customImagesPreloaded = true;
      debugPrint('🎯 PictogramService: Batch preload complete - ${_customImageMatches.length} matches cached');
      
    } catch (e) {
      debugPrint('❌ PictogramService: Batch preload error: $e');
    }
  }

  /// Static method to clear cache from anywhere in the app
  static Future<void> clearGlobalCache() async {
    final instance = PictogramService._instance;
    await instance.clearCache();
  }

  /// Clear cache for specific problematic words that might be cached as null
  Future<void> clearCacheForWord(String word) async {
    final normalizedWord = word.toLowerCase().trim();
    
    if (_imageCache.containsKey(normalizedWord)) {
      final oldValue = _imageCache[normalizedWord];
      _imageCache.remove(normalizedWord);
      debugPrint('PictogramService: Cleared cache for word "$normalizedWord" (was: $oldValue)');
      
      // Save updated cache
      await _saveCacheToPrefs();
    } else {
      debugPrint('PictogramService: Word "$normalizedWord" not found in cache');
    }
  }

  /// Clear cache for common problematic single-character words
  Future<void> clearProblematicCache() async {
    final problematicWords = ['i', 'a', 'o', 'u', 'we', 'me', 'he', 'she', 'it', 'is', 'to', 'go', 'no', 'on', 'up', 'my'];
    
    int clearedCount = 0;
    for (final word in problematicWords) {
      if (_imageCache.containsKey(word)) {
        final oldValue = _imageCache[word];
        _imageCache.remove(word);
        clearedCount++;
        debugPrint('PictogramService: Cleared "$word" from cache (was: $oldValue)');
      }
    }
    
    if (clearedCount > 0) {
      await _saveCacheToPrefs();
    }
    
    debugPrint('PictogramService: Cleared $clearedCount out of ${problematicWords.length} problematic words from cache');
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    final totalEntries = _imageCache.length;
    final nullEntries = _imageCache.values.where((v) => v == null).length;
    final imageEntries = _imageCache.values.where((v) => v != null && v.startsWith('http')).length;
    final emojiEntries = _imageCache.values.where((v) => v != null && !v.startsWith('http')).length;

    return {
      'totalEntries': totalEntries,
      'nullEntries': nullEntries,
      'imageEntries': imageEntries,
      'emojiEntries': emojiEntries,
      'cacheKeys': _imageCache.keys.toList(),
    };
  }

  /// Manually assign an image URL to a specific text (for admin/manual assignment)
  Future<void> assignImageToText(String text, String? imageUrl) async {
    final normalizedText = text.toLowerCase().trim();
    _imageCache[normalizedText] = imageUrl;
    await _saveCacheToPrefs();
  }

  /// Preload images for common words to improve performance
  /// This uses cache-only lookups to avoid triggering missing image logging
  Future<void> preloadCommonWords() async {
    final commonWords = [
      'hello', 'hi', 'goodbye', 'yes', 'no', 'please', 'thank you',
      'help', 'stop', 'go', 'more', 'water', 'food', 'happy', 'sad'
    ];

    debugPrint('🔄 PictogramService: Preloading common words (cache-only, no missing image logging)');
    
    for (final word in commonWords) {
      if (!_imageCache.containsKey(word)) {
        // Use cache-only preload to avoid missing image logging
        _preloadWordCacheOnly(word).catchError((e) {
          debugPrint('Error preloading pictogram for "$word": $e');
          return null;
        });
      }
    }
  }

  /// Preload a single word using cache-only lookup (no missing image logging)
  Future<void> _preloadWordCacheOnly(String word) async {
    final normalizedText = word.toLowerCase().trim();
    
    // Check if already in cache
    if (_imageCache.containsKey(normalizedText)) {
      return;
    }
    
    // Since we've removed emoji fallbacks, there's nothing to preload
    debugPrint('🔄 PictogramService: Skipping preload for "$word" - no fallback system');
  }

  /// Extract meaningful keywords from text (matching web app logic)
  List<String> _extractKeywords(String text) {
    final keywords = <String>[];
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    
    // Common stop words to filter out
    const stopWords = {
      'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from',
      'has', 'he', 'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the',
      'to', 'was', 'will', 'with', 'i', 'me', 'my', 'we', 'us', 'our',
      'you', 'your', 'they', 'them', 'their', 'this', 'these',
      'those', 'am', 'been', 'being', 'have', 'had', 'do', 'does', 'did',
      'can', 'could', 'should', 'would', 'may', 'might', 'must', 'shall',
      'feeling', 'today', 'now', 'bit', 'little', 'very', 'really', 'so',
      'just', 'quite', 'too', 'much', 'many', 'some', 'any', 'all'
    };
    
    // Emotion/feeling words that are meaningful
    const emotionWords = {
      'happy', 'sad', 'angry', 'excited', 'tired', 'hungry', 'thirsty',
      'fantastic', 'great', 'good', 'bad', 'awful', 'amazing', 'wonderful',
      'terrible', 'lonely', 'scared', 'worried', 'calm', 'relaxed',
      'stressed', 'anxious', 'proud', 'embarrassed', 'confused',
      'energetic', 'positive', 'negative', 'unhappy'
    };
    
    // Action words that are meaningful
    const actionWords = {
      'eat', 'drink', 'play', 'sleep', 'work', 'study', 'read', 'write',
      'run', 'walk', 'jump', 'dance', 'sing', 'talk', 'listen', 'watch',
      'help', 'share', 'give', 'take', 'buy', 'sell', 'make', 'build',
      'cook', 'clean', 'wash', 'drive', 'fly', 'swim', 'climb', 'get', 'go',
      'come', 'see', 'want', 'need', 'like', 'love', 'hate', 'find', 'look',
      'call', 'meet', 'visit', 'stay', 'leave', 'start', 'stop', 'finish'
    };
    
    for (final word in words) {
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
      if (cleanWord.length > 2 && !stopWords.contains(cleanWord)) {
        // Prioritize emotion and action words
        if (emotionWords.contains(cleanWord) || actionWords.contains(cleanWord)) {
          keywords.insert(0, cleanWord); // Add to front for priority
        } else {
          keywords.add(cleanWord);
        }
      }
    }
    
    return keywords;
  }

  /// Select the most meaningful keyword from extracted keywords with improved contextual logic
  String _selectMeaningfulKeyword(List<String> keywords, String originalText) {
    if (keywords.isEmpty) {
      // If no keywords found, use the original text
      return originalText.toLowerCase().trim();
    }
    
    debugPrint('🔧 DEBUG: Selecting meaningful keyword from: $keywords for text: "$originalText"');
    
    // Define word categories for contextual prioritization
    const actionWords = {'want', 'need', 'like', 'love', 'hate', 'get', 'have', 'make', 'do', 'go', 'come'};
    const specificNouns = {
      // Food & drinks
      'pizza', 'burger', 'sandwich', 'salad', 'soup', 'pasta', 'chicken', 'beef',
      'fish', 'rice', 'bread', 'cheese', 'fruit', 'apple', 'orange', 'banana',
      'cake', 'cookie', 'ice', 'cream', 'coffee', 'tea', 'juice', 'water',
      'breakfast', 'lunch', 'dinner', 'snack', 'dessert', 'meal',
      // Places
      'restroom', 'bathroom', 'toilet', 'home', 'school', 'hospital', 'store', 'park',
      // Objects
      'music', 'book', 'phone', 'computer', 'car', 'information', 'help',
      // Activities  
      'draw', 'drawing', 'paint', 'painting', 'read', 'reading', 'play', 'playing'
    };
    const descriptiveWords = {'tired', 'happy', 'sad', 'angry', 'excited', 'hungry', 'thirsty', 'hot', 'cold', 'big', 'small'};
    
    // IMPROVED CONTEXTUAL LOGIC:
    // 1. For "feeling" contexts (feel tired, am happy), prioritize the descriptive word
    final lowerOriginal = originalText.toLowerCase();
    if (lowerOriginal.startsWith('feel ') || lowerOriginal.startsWith('am ') || lowerOriginal.startsWith('being ')) {
      final descriptiveKeywords = keywords.where((word) => descriptiveWords.contains(word)).toList();
      if (descriptiveKeywords.isNotEmpty) {
        debugPrint('🔧 DEBUG: Feeling context detected - prioritizing descriptive word: ${descriptiveKeywords.first}');
        return descriptiveKeywords.first;
      }
    }
    
    // 2. For action contexts, look at what follows the action word
    final actionKeywords = keywords.where((word) => actionWords.contains(word)).toList();
    if (actionKeywords.isNotEmpty) {
      final actionWord = actionKeywords.first;
      
      // Find specific nouns that could be the object of the action
      final nounKeywords = keywords.where((word) => specificNouns.contains(word)).toList();
      
      if (nounKeywords.isNotEmpty) {
        // Check if this is a case where the noun is more visually descriptive
        final nounWord = nounKeywords.first;
        
        // For these action + noun combinations, prioritize the noun for better images
        if ((actionWord == 'want' && ['snack', 'food', 'water', 'juice'].contains(nounWord)) ||
            (actionWord == 'need' && ['restroom', 'bathroom', 'toilet', 'help', 'information'].contains(nounWord)) ||
            (actionWord == 'like' && ['music', 'draw', 'drawing', 'read', 'reading'].contains(nounWord))) {
          debugPrint('🔧 DEBUG: Action + specific noun context - prioritizing noun "$nounWord" over action "$actionWord"');
          return nounWord;
        }
      }
      
      // For generic action contexts, use the action word
      debugPrint('🔧 DEBUG: Generic action context - using action word: $actionWord');
      return actionWord;
    }
    
    // 3. If no action words, prioritize specific nouns over generic words
    final nounKeywords = keywords.where((word) => specificNouns.contains(word)).toList();
    if (nounKeywords.isNotEmpty) {
      debugPrint('🔧 DEBUG: No action context - prioritizing specific noun: ${nounKeywords.first}');
      return nounKeywords.first;
    }
    
    // 4. Fall back to first keyword (emotion/action words are already prioritized in extraction)
    final selected = keywords.first;
    debugPrint('🔧 DEBUG: Using first available keyword: "$selected"');
    return selected;
  }

  /// Intelligently select the best text for image searching based on button data
  /// This is the key method that makes the system robust for all button types
  /*
  String _selectBestSearchText(String originalText, Map<String, dynamic>? buttonData) {
    debugPrint('🔍 PictogramService: _selectBestSearchText called with originalText="$originalText"');
    debugPrint('🔍 PictogramService: buttonData=$buttonData');
    
    if (buttonData == null) {
      debugPrint('🔍 PictogramService: No button data - using original text');
      return originalText;
    }

    // STRATEGY 1: Use LLM-provided keywords if available (most intelligent)
    if (buttonData['keywords'] != null) {
      final keywords = buttonData['keywords'];
      debugPrint('🔍 PictogramService: Found LLM keywords: $keywords');
      
      if (keywords is List && keywords.isNotEmpty) {
        // Use the first meaningful keyword from LLM  
        final llmKeyword = keywords.first.toString();
        debugPrint('🔍 PictogramService: Using LLM keyword: "$llmKeyword"');
        return llmKeyword;
      }
    }

    // STRATEGY 2: Use summary field if this is an LLM-generated button
    if (buttonData['isLLMGenerated'] == true && buttonData['summary'] != null) {
      final summary = buttonData['summary'].toString();
      if (summary.isNotEmpty && summary.toLowerCase() != originalText.toLowerCase()) {
        debugPrint('🔍 PictogramService: Using LLM summary: "$summary"');
        return summary;
      }
    }

    // STRATEGY 3: Try to extract meaningful keywords from original text
    debugPrint('🔍 PictogramService: Falling back to keyword extraction for: "$originalText"');
    final extractedKeywords = _extractKeywords(originalText);
    if (extractedKeywords.isNotEmpty) {
      final meaningfulKeyword = _selectMeaningfulKeyword(extractedKeywords, originalText);
      debugPrint('🔍 PictogramService: Extracted meaningful keyword: "$meaningfulKeyword"');
      return meaningfulKeyword;
    }

    // STRATEGY 4: Fallback to original text
    debugPrint('🔍 PictogramService: No optimization possible - using original text');
    return originalText;
  }
  */
}