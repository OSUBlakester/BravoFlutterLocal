import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';
import '../services/user_settings_provider.dart';
import '../services/authenticated_http_client.dart';

class TapInterfaceCategory {
  final String id;
  final String label;
  final String? speechText;
  final String? imageUrl;
  final String? customAudioFile;
  final String? backgroundColor;
  final String? textColor;
  final String? llmPrompt;
  final String? wordsPrompt;
  final String? staticOptions;
  final String? specialPage;
  final bool hidden;
  final String optionType; // 'phrase' or 'word'
  final List<TapInterfaceCategory> children;

  TapInterfaceCategory({
    required this.id,
    required this.label,
    this.speechText,
    this.imageUrl,
    this.customAudioFile,
    this.backgroundColor,
    this.textColor,
    this.llmPrompt,
    this.wordsPrompt,
    this.staticOptions,
    this.specialPage,
    this.hidden = false,
    this.optionType = 'phrase', // default to phrase
    this.children = const [],
  });

  static String? _normalizeSpecialPage(dynamic raw) {
    if (raw == null) return null;
    var value = raw.toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('!')) {
      value = value.substring(1);
    }
    final normalized = value
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(' ', '-');

    switch (normalized) {
      case 'email':
      case 'email-page':
      case 'emailpage':
      case 'mail':
        return 'email';
      case 'guesswho':
      case 'guess-who':
        return 'guess-who';
      case 'free-style':
      case 'freestyle':
        return 'freestyle';
      default:
        return normalized;
    }
  }

  static bool _parseHidden(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = (raw ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  factory TapInterfaceCategory.fromJson(Map<String, dynamic> json) {
    final normalizedSpecialPage = _normalizeSpecialPage(
      json['special_function'] ?? json['special_page'] ?? json['specialPage'],
    );
    final parsedLabel = (json['label'] ?? '').toString();
    final effectiveLabel =
        parsedLabel.trim().isNotEmpty
            ? parsedLabel
            : (normalizedSpecialPage == 'email' ? 'Email' : parsedLabel);

    return TapInterfaceCategory(
      id: (json['id'] ?? effectiveLabel).toString(),
      label: effectiveLabel,
      speechText: json['speech_text'],
      imageUrl: json['image_url'],
      customAudioFile: json['custom_audio_file'],
      backgroundColor: json['background_color'],
      textColor: json['text_color'],
      llmPrompt: json['llm_prompt'],
      wordsPrompt: json['words_prompt'],
      staticOptions: json['static_options'],
      specialPage: normalizedSpecialPage,
      hidden: _parseHidden(json['hidden']),
      optionType: json['option_type'] ?? 'phrase',
      children: (json['children'] as List<dynamic>? ?? [])
          .map((child) => TapInterfaceCategory.fromJson(child))
          .toList(),
    );
  }

  bool get hasLLMQuery => llmPrompt != null && llmPrompt!.isNotEmpty;
  bool get hasWordsPrompt => wordsPrompt != null && wordsPrompt!.isNotEmpty;
  bool get hasStaticOptions => staticOptions != null && staticOptions!.isNotEmpty;
  bool get hasSpecialPage => specialPage != null && specialPage!.isNotEmpty;
  bool get hasChildren => children.isNotEmpty;
  bool get hasCustomAudioFile => customAudioFile != null && customAudioFile!.isNotEmpty;
  
  List<String> get staticOptionsList {
    if (!hasStaticOptions) return [];
    return staticOptions!.split(',').map((e) => e.trim()).toList();
  }
}

class TapInterfaceConfig {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final String createdAt;
  final String updatedAt;
  final List<TapInterfaceCategory> buttons;

  TapInterfaceConfig({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.buttons,
  });

  factory TapInterfaceConfig.fromJson(Map<String, dynamic> json) {
    return TapInterfaceConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      buttons: (json['buttons'] as List<dynamic>? ?? [])
          .map((button) => TapInterfaceCategory.fromJson(button))
          .toList(),
    );
  }
}

class TapInterfaceService {
  final UserSettingsProvider userSettingsProvider;

  TapInterfaceService({required this.userSettingsProvider});

  Future<TapInterfaceConfig?> fetchTapInterfaceConfig() async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/tap-interface/config'),
        headers: {
          'Authorization': 'Bearer ${userSettingsProvider.idToken}',
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return TapInterfaceConfig.fromJson(data);
      } else {
        print('Failed to load tap interface config: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching tap interface config: $e');
      return null;
    }
  }

  Future<List<Map<String, String>>> generateLLMPhraseOptions({
    required String context,
    int maxOptions = 6,
    bool requestDifferentOptions = false,
    List<String> excludeOptions = const [],
    String? currentMood,
  }) async {
    try {
      // Use the same prompt format and endpoint as main.dart
      final summaryInstruction = 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      
      String excludeText = '';
      if (requestDifferentOptions && excludeOptions.isNotEmpty) {
        excludeText = '\nDo NOT include these options I already have: ${excludeOptions.join(', ')}\n';
      }

      String moodContext = '';
      if (currentMood != null && currentMood.isNotEmpty && currentMood != 'No Mood Selected') {
        moodContext = '\nThe user is currently feeling: $currentMood. Ensure the options reflect this mood.\n';
      }
      
      final promptForLLM =
          'Generate exactly $maxOptions short, single-phrase options that directly answer or respond to: "$context".\n'
          'IMPORTANT: Provide exactly $maxOptions options, no more, no less. Each option must be relevant to the context provided.\n'
          'ONLY provide options that directly relate to the context: "$context"\n'
          '${requestDifferentOptions ? 'Generate DIFFERENT options than what I already have.\n' : ''}'
          '$excludeText'
          '$moodContext'
          'Do not include any introductory or concluding text.\n'
          'Do NOT number your responses (no 1., 2., 3., etc.).\n'
          'Do NOT use bullet points or dashes.\n'
          'Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option contain the question and the answer.\n'
          '$summaryInstruction\n'
          'The "keywords" key should be a list of 1-3 simple, concrete nouns or verbs from the phrase that could be used to find relevant images. Focus on visual, concrete concepts (like "food", "happy", "play", "home") rather than abstract words.\n'
          'Example: [{"option": "I want to go outside", "summary": "Go outside", "keywords": ["outside", "play"]}, {"option": "Can I have some water please?", "summary": "Water please", "keywords": ["water", "drink"]}]';
      
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'prompt': promptForLLM,
        }),
        timeoutSeconds: 30,
      );

      print('LLM Phrase API Response: ${response.statusCode}');
      print('LLM Phrase API Response Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
      
      if (response.statusCode == 200) {
        var responseBody = response.body;
        
        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          print('LLM Phrase API: Detected markdown code fence, stripping...');
          responseBody = responseBody.replaceAll('```json', '').replaceAll('```', '').trim();
        }
        
        final dynamic decodedData = json.decode(responseBody);
        
        // Handle both direct list and wrapped in options key
        final List<dynamic> data = decodedData is List ? decodedData : 
                                   (decodedData is Map && decodedData['options'] != null) ? decodedData['options'] : [];
        
        print('LLM Phrase API Decoded ${data.length} items');
        
        final options = <Map<String, String>>[];
        
        for (var i = 0; i < data.length; i++) {
          var item = data[i];
          
          // If item is a string, try to parse it as JSON
          if (item is String) {
            final trimmed = item.trim();
            
            // Skip markdown artifacts
            if (trimmed.startsWith('```') || trimmed == 'json' || trimmed.isEmpty) {
              continue;
            }
            
            if (trimmed.startsWith('{')) {
              try {
                String cleaned = trimmed.endsWith(',') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
                item = json.decode(cleaned);
              } catch (e) {
                print('LLM Phrase API: Failed to parse string as JSON: $e');
                continue;
              }
            } else {
              continue; // Skip non-JSON strings
            }
          }
          
          if (item is Map) {
            // Extract keywords from LLM response
            final keywords = item['keywords'];
            final keywordsString = keywords is List ? keywords.join('|') : (keywords?.toString() ?? '');
            
            final optionText = item['option']?.toString() ?? item['text']?.toString() ?? '';
            final summaryText = item['summary']?.toString() ?? optionText;
            
            // Skip invalid entries
            if (optionText.isEmpty || optionText.startsWith('{') || optionText.startsWith('```')) {
              continue;
            }
            
            options.add({
              'summary': summaryText,
              'fullText': optionText,
              'keywords': keywordsString,
            });
          }
        }
        
        print('LLM Phrase API Extracted Options with Keywords (${options.length}): ${options.take(5).map((o) => o['fullText']).toList()}');
        return options;
      }
      
      print('Failed to generate LLM phrase options: ${response.statusCode}');
      return [
        {'summary': 'Try again', 'fullText': 'Try again'},
        {'summary': 'Something else', 'fullText': 'Something else'},
        {'summary': 'Go back', 'fullText': 'Go back'},
      ];
    } catch (e) {
      print('Error in generateLLMPhraseOptions: $e');
      return [
        {'summary': 'Try again', 'fullText': 'Try again'},
        {'summary': 'Something else', 'fullText': 'Something else'},
        {'summary': 'Go back', 'fullText': 'Go back'},
      ];
    }
  }

  // Keep the old method for backward compatibility
  Future<List<String>> generateLLMOptions({
    required String llmPrompt,
    required String categoryLabel,
    int maxOptions = 20,
  }) async {
    try {
      final phraseOptions = await generateLLMPhraseOptions(
        context: categoryLabel,
        maxOptions: maxOptions,
      );
      return phraseOptions.map((option) => option['fullText'] ?? '').toList();
    } catch (e) {
      print('Error in generateLLMOptions wrapper: $e');
      return [];
    }
  }

  Future<List<String>> generateCategoryWords({
    required String category,
    String buildSpaceContent = '',
    List<String> excludeWords = const [],
    int maxOptions = 27,
    bool requestDifferentOptions = false,
    String? currentMood,
  }) async {
    try {
      print('🎯 TapInterfaceService - generateCategoryWords called with:');
      print('   category: "$category"');
      print('   MOOD CHECK: category contains "feeling"? ${category.contains('feeling')}');
      print('   buildSpaceContent: "$buildSpaceContent"');
      print('   excludeWords: $excludeWords');
      print('   maxOptions: $maxOptions');
      print('   currentMood: $currentMood');
      
      // Extract mood from category if present, or use passed mood
      String? extractedMood = currentMood;
      if (extractedMood == null && category.contains('feeling')) {
        // Extract mood from "feeling X" pattern
        final moodMatch = RegExp(r'feeling (\w+)').firstMatch(category);
        extractedMood = moodMatch?.group(1);
      }
      
      print('   Final mood for category: $extractedMood');
      
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/freestyle/category-words'),
        headers: {
          'Authorization': 'Bearer ${userSettingsProvider.idToken}',
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'category': category,
          'build_space_content': buildSpaceContent,
          'exclude_words': excludeWords,
          'request_different_options': requestDifferentOptions,
          'current_mood': extractedMood,  // Send the extracted mood to backend
        }),
      );

      print('Category Words API Response: ${response.statusCode}');
      print('Category Words API Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Category Words API Parsed Data: $data');
        
        final rawWords = data['words'] ?? [];
        print('Category Words API Raw Words: $rawWords');
        
        final words = rawWords.map<String>((word) {
          String raw;
          if (word is String) {
            raw = word;
          } else if (word is Map<String, dynamic>) {
            raw = word['text']?.toString() ?? word['word']?.toString() ?? word.toString();
          } else {
            raw = word.toString();
          }
          return _normalizeOptionText(raw);
        }).where((text) {
          final trimmedText = text.trim();
          return trimmedText.isNotEmpty && 
                 trimmedText.length > 0 &&
                 !trimmedText.contains('here are') &&
                 trimmedText.length <= 50;
        }).toList();
        
        print('Category Words API Final Words: $words');
        
        // CRITICAL FIX: Apply client-side exclusion filtering since API exclusions aren't working properly
        if (requestDifferentOptions && excludeWords.isNotEmpty) {
          print('🔧 Applying CLIENT-SIDE exclusion filtering for category words...');
          print('   Original API words count: ${words.length}');
          print('   Excluding words: ${excludeWords.take(5).toList()}${excludeWords.length > 5 ? '...' : ''}');
          
          // Create case-insensitive exclusion set for better matching
          final excludeSet = excludeWords.map((e) => e.toLowerCase().trim()).toSet();
          
          // Filter out excluded words
          final filteredWords = words.where((word) {
            final wordLower = word.toLowerCase().trim();
            final shouldExclude = excludeSet.contains(wordLower);
            if (shouldExclude) {
              print('   🚫 Excluding: "$word" (matches excluded "${excludeWords.firstWhere((e) => e.toLowerCase().trim() == wordLower, orElse: () => wordLower)}")');
            }
            return !shouldExclude;
          }).toList();
          
          print('   After client-side exclusion: ${filteredWords.length} words');
          print('   First 10 after exclusion: ${filteredWords.take(10).toList()}');
          
          // If we have too few words after exclusion, supplement with category-appropriate alternatives
          if (filteredWords.length < maxOptions ~/ 2) {
            print('   ⚡ Too few words after exclusion (${filteredWords.length}), adding category alternatives...');
            
            // Generate category-specific alternatives based on the category
            List<String> categoryAlternatives = [];
            final categoryLower = category.toLowerCase();
            
            // Check for vacation/travel related
            if (categoryLower.contains('vacation') || categoryLower.contains('travel') || 
                categoryLower.contains('destination') || categoryLower.contains('holiday')) {
              categoryAlternatives = ['Hawaii', 'Florida', 'California', 'Colorado', 'Texas', 'New York', 
                'Alaska', 'Arizona', 'beach', 'mountains', 'forest', 'lake', 'ocean', 'island', 
                'resort', 'hotel', 'cabin', 'campground', 'cruise', 'Disney', 'theme park', 'zoo', 
                'aquarium', 'museum', 'city', 'country', 'Europe', 'Mexico', 'Canada'];
            }
            // Check for places/locations
            else if (categoryLower.contains('place') || categoryLower.contains('location') || 
                     categoryLower.contains('where') || categoryLower.contains('go')) {
              categoryAlternatives = ['home', 'park', 'school', 'store', 'restaurant', 'library', 
                'playground', 'pool', 'gym', 'mall', 'theater', 'hospital', 'church', 'downtown', 
                'neighborhood', 'garden', 'beach', 'mountains', 'lake', 'river', 'forest'];
            }
            // Food related
            else if (categoryLower.contains('food') || categoryLower.contains('meal') || 
                     categoryLower.contains('eat') || categoryLower.contains('snack')) {
              categoryAlternatives = ['pizza', 'burger', 'sandwich', 'salad', 'pasta', 'chicken', 
                'fish', 'steak', 'soup', 'fruit', 'vegetables', 'dessert', 'ice cream', 'cake', 
                'cookies', 'chips', 'popcorn', 'yogurt', 'cheese', 'bread'];
            }
            else if (categoryLower.contains('feeling') || categoryLower.contains('emotion')) {
              categoryAlternatives = ['excited', 'thrilled', 'peaceful', 'curious', 'hopeful', 'determined', 'inspired', 'grateful'];
            }
            else if (categoryLower.contains('action') || categoryLower.contains('activity') || categoryLower.contains('game')) {
              categoryAlternatives = ['explore', 'create', 'discover', 'adventure', 'journey', 'wander', 'climb', 'swim'];
            }
            else if (categoryLower.contains('people') || categoryLower.contains('family') || categoryLower.contains('who')) {
              categoryAlternatives = ['neighbor', 'teammate', 'companion', 'mentor', 'helper', 'visitor', 'guest', 'host'];
            }
            else if (categoryLower.contains('places')) {
              categoryAlternatives = ['adventure', 'journey', 'destination', 'hideaway', 'sanctuary', 'playground', 'workshop', 'studio'];
            }
            else {
              categoryAlternatives = ['awesome', 'amazing', 'wonderful', 'fantastic', 'brilliant', 'creative', 'special', 'unique'];
            }
            
            // Add category alternatives that aren't already excluded
            for (String alternative in categoryAlternatives) {
              if (!excludeSet.contains(alternative.toLowerCase()) && 
                  !filteredWords.map((e) => e.toLowerCase()).contains(alternative.toLowerCase()) &&
                  filteredWords.length < maxOptions) {
                filteredWords.add(alternative);
                print('   ✨ Added category alternative: "$alternative"');
              }
            }
            
            print('   Final count with category alternatives: ${filteredWords.length}');
          }
          
          return filteredWords;
        }
        
        return words;
      }
      
      print('Failed to generate category words: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error generating category words: $e');
      return [];
    }
  }

  Future<List<String>> generateFreestyleOptions({
    required String context,
    String buildSpaceText = '',
    bool singleWordsOnly = true,
    int maxOptions = 15,
    bool requestDifferentOptions = false,
    List<String> excludeOptions = const [],
    String? currentMood,
  }) async {
    debugPrint('🔧🔧🔧 FREESTYLE OPTIONS SERVICE CALLED 🔧🔧🔧');
    try {
      debugPrint('🔧 TapInterfaceService - generateFreestyleOptions called with:');
      debugPrint('   buildSpaceText: "$buildSpaceText"');
      debugPrint('   context: "$context"');
      debugPrint('   singleWordsOnly: $singleWordsOnly');
      print('   requestDifferentOptions: $requestDifferentOptions');
      print('   excludeOptions: $excludeOptions');
      print('   excludeOptions length: ${excludeOptions.length}');
      print('   currentMood: $currentMood');
      
      // Extract mood from context if present, or use passed mood
      String? extractedMood = currentMood;
      if (extractedMood == null && context.contains('feeling')) {
        // Extract mood from "feeling X" pattern
        final moodMatch = RegExp(r'feeling (\w+)').firstMatch(context);
        extractedMood = moodMatch?.group(1);
      }
      
      // If we have a mood but no specific context, add it to context for general requests
      String effectiveContext = context;
      if (extractedMood != null && extractedMood.isNotEmpty && !context.contains('feeling')) {
        effectiveContext = '$context when feeling $extractedMood';
      }
      
      print('   Final mood: $extractedMood');
      print('   Sending to API - source_page: "${effectiveContext.contains('feeling') ? 'Mood-Aware Words' : effectiveContext}", context: "$effectiveContext"');
      print('   Full request body will include exclude_words: $excludeOptions');
      
      // Use the same endpoint and format as the working freestyle.js
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'build_space_text': buildSpaceText,
          'context': effectiveContext,  // Use the mood-enhanced context directly
          'source_page': effectiveContext.contains('feeling') ? 'Mood-Aware Words' : effectiveContext,  // Use descriptive source page
          'is_llm_generated': false,
          'single_words_only': singleWordsOnly,
          'originating_button_text': null,
          'request_different_options': requestDifferentOptions,
          'exclude_words': excludeOptions,  // Fixed: use 'exclude_words' not 'exclude_options'
          'current_mood': extractedMood,  // Send the extracted mood to backend
          'max_options': maxOptions,  // Override FreestyleOptions setting
          'timestamp': DateTime.now().millisecondsSinceEpoch, // Prevent caching
        }),
      );

      debugPrint('Freestyle API Response: ${response.statusCode}');
      
      // Log full response for debugging
      if (response.statusCode != 200) {
        debugPrint('❌ Freestyle API Error: Status ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }
      
      if (response.body.isEmpty) {
        debugPrint('❌ Freestyle API: Empty response body');
        return [];
      }
      
      debugPrint('Freestyle API Response Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
      
      if (response.statusCode == 200) {
        var responseBody = response.body;
        
        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          print('Freestyle API: Detected markdown code fence, stripping...');
          responseBody = responseBody.replaceAll('```json', '').replaceAll('```', '').trim();
        }
        
        final data = json.decode(responseBody);
        print('✅ Freestyle API Parsed Data Type: ${data.runtimeType}');
        print('✅ Full parsed data structure: $data');
        
        // Use the exact same response parsing as freestyle_page.dart
        final rawOptions = data['word_options'] ?? [];
        print('✅ Freestyle API word_options field exists: ${data.containsKey('word_options')}');
        print('✅ Freestyle API Raw Options: $rawOptions');
        print('✅ Freestyle API Raw Options Type: ${rawOptions.runtimeType}');
        print('✅ Freestyle API Raw Options Length: ${rawOptions is List ? rawOptions.length : 'N/A'}');
        
        final options = <String>[];
        
        if (rawOptions is List) {
          for (var i = 0; i < rawOptions.length; i++) {
            final option = rawOptions[i];
            String raw = '';
            
            if (option is String) {
              final trimmed = option.trim();
              
              // Skip markdown artifacts
              if (trimmed.startsWith('```') || trimmed == 'json' || trimmed.isEmpty) {
                continue;
              }
              
              // Check if it's JSON-encoded string
              if (trimmed.startsWith('{')) {
                try {
                  String cleaned = trimmed.endsWith(',') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
                  final parsed = json.decode(cleaned);
                  if (parsed is Map) {
                    raw = parsed['option']?.toString() ?? 
                          parsed['text']?.toString() ?? 
                          parsed['word']?.toString() ?? 
                          trimmed;
                  } else {
                    raw = trimmed;
                  }
                } catch (e) {
                  raw = trimmed;
                }
              } else {
                raw = trimmed;
              }
            } else if (option is Map<String, dynamic>) {
              raw = option['option']?.toString() ?? 
                    option['text']?.toString() ?? 
                    option['word']?.toString() ?? 
                    option.toString();
            } else {
              raw = option.toString();
            }
            
            final normalized = _normalizeOptionText(raw);
            final trimmedText = normalized.trim();
            
            // Filter out invalid options
            if (trimmedText.isNotEmpty && 
                trimmedText.length > 0 &&
                trimmedText.length <= 50 &&
                !trimmedText.contains('here are') &&
                !trimmedText.startsWith('{') &&
                !trimmedText.contains('option":') &&
                !trimmedText.startsWith('```') &&
                trimmedText != 'json') {
              options.add(normalized);
            }
          }
        }
        
        print('Freestyle API Final Options (${options.length}): ${options.take(10).toList()}');
        
        if (options.isEmpty) {
          print('⚠️  WARNING: Freestyle API returned empty options list!');
          print('   Context: "$context"');
          print('   BuildSpace: "$buildSpaceText"');
          return [];
        }
        
        // CRITICAL FIX: Apply client-side exclusion filtering since API exclusions aren't working properly
        if (requestDifferentOptions && excludeOptions.isNotEmpty) {
          print('🔧 Applying CLIENT-SIDE exclusion filtering...');
          print('   Original API options count: ${options.length}');
          print('   Excluding options: ${excludeOptions.take(5).toList()}${excludeOptions.length > 5 ? '...' : ''}');
          
          // Create case-insensitive exclusion set for better matching
          final excludeSet = excludeOptions.map((e) => e.toLowerCase().trim()).toSet();
          
          // Filter out excluded options
          final filteredOptions = options.where((option) {
            final optionLower = option.toLowerCase().trim();
            final shouldExclude = excludeSet.contains(optionLower);
            if (shouldExclude) {
              print('   🚫 Excluding: "$option" (matches excluded "${excludeOptions.firstWhere((e) => e.toLowerCase().trim() == optionLower, orElse: () => optionLower)}")');
            }
            return !shouldExclude;
          }).toList();
          
          print('   After client-side exclusion: ${filteredOptions.length} options');
          print('   First 10 after exclusion: ${filteredOptions.take(10).toList()}');
          
          // If we have too few options after exclusion, supplement with context-appropriate alternatives
          if (filteredOptions.length < maxOptions ~/ 2) {
            print('   ⚡ Too few options after exclusion (${filteredOptions.length}), adding context alternatives...');
            
            List<String> contextAlternatives = [];
            final contextLower = context.toLowerCase();
            
            // Check for vacation/travel related
            if (contextLower.contains('vacation') || contextLower.contains('travel') || 
                contextLower.contains('destination') || contextLower.contains('holiday')) {
              contextAlternatives = ['Hawaii', 'Florida', 'California', 'Colorado', 'Texas', 
                'beach', 'mountains', 'forest', 'lake', 'ocean', 'island', 'resort', 'Disney', 
                'cruise', 'camping', 'hiking', 'swimming', 'sightseeing'];
            }
            // Check for places/locations
            else if (contextLower.contains('place') || contextLower.contains('location') || contextLower.contains('where')) {
              contextAlternatives = ['home', 'park', 'school', 'store', 'restaurant', 'library', 
                'playground', 'pool', 'gym', 'mall', 'theater', 'downtown', 'beach', 'mountains'];
            }
            // Food related
            else if (contextLower.contains('food') || contextLower.contains('meal') || contextLower.contains('eat')) {
              contextAlternatives = ['pizza', 'burger', 'sandwich', 'salad', 'pasta', 'chicken', 
                'fish', 'fruit', 'vegetables', 'dessert', 'ice cream', 'cookies'];
            }
            // Default creative alternatives
            else {
              contextAlternatives = [
                'awesome', 'amazing', 'wonderful', 'fantastic', 'brilliant', 'excellent', 'perfect', 'great',
                'create', 'build', 'make', 'design', 'craft', 'construct', 'form', 'shape',
                'adventure', 'journey', 'explore', 'discover', 'travel', 'wander', 'roam', 'quest',
                'music', 'art', 'color', 'paint', 'draw', 'sing', 'dance', 'rhythm',
                'family', 'friend', 'together', 'share', 'care', 'love', 'support', 'connect',
                'outside', 'nature', 'sky', 'sun', 'moon', 'stars', 'tree', 'flower',
                'learn', 'teach', 'understand', 'explain', 'question', 'answer', 'wonder', 'imagine',
                'kind', 'gentle', 'brave', 'strong', 'smart', 'clever', 'wise', 'thoughtful'
              ];
            }
            
            // Add context alternatives that aren't already excluded
            for (String creative in contextAlternatives) {
              if (!excludeSet.contains(creative.toLowerCase()) && 
                  !filteredOptions.map((e) => e.toLowerCase()).contains(creative.toLowerCase()) &&
                  filteredOptions.length < maxOptions) {
                filteredOptions.add(creative);
                print('   ✨ Added creative alternative: "$creative"');
              }
            }
            
            print('   Final count with creative alternatives: ${filteredOptions.length}');
          }
          
          return filteredOptions;
        }
        
        return options;
      }
      
      debugPrint('❌ Failed to generate freestyle options: ${response.statusCode}');
      debugPrint('   Response body: ${response.body}');
      return [];
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ ERROR in generateFreestyleOptions: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Generate options using the simple /api/generate-options endpoint (like the web app)
  /// This is better for answering specific questions than the freestyle endpoint
  Future<List<String>> generateDirectOptions({
    required String prompt,
    int maxOptions = 18,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/generate-options'),
        headers: {
          'Authorization': 'Bearer ${userSettingsProvider.idToken}',
          'X-User-ID': userSettingsProvider.userId ?? '',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'prompt': prompt,
          'count': maxOptions,
        }),
      );

      print('Direct Options API Response: ${response.statusCode}');
      print('Direct Options API Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        var responseBody = response.body;
        
        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          print('Direct Options API: Detected markdown code fence, stripping...');
          responseBody = responseBody.replaceAll('```json', '').replaceAll('```', '').trim();
          print('Direct Options API: After stripping fences: ${responseBody.substring(0, responseBody.length > 200 ? 200 : responseBody.length)}');
        }
        
        final data = json.decode(responseBody);
        print('Direct Options API Decoded Data Type: ${data.runtimeType}');
        
        List<dynamic> rawOptions = [];
        
        // Handle different response formats
        if (data is Map && data['options'] != null) {
          rawOptions = data['options'] as List<dynamic>;
        } else if (data is List) {
          rawOptions = data;
        }
        
        print('Direct Options API Raw Options Count: ${rawOptions.length}');
        
        final List<String> options = [];
        for (var i = 0; i < rawOptions.length; i++) {
          final option = rawOptions[i];
          
          if (option is String) {
            final trimmed = option.trim();
            
            // Skip empty strings, commas, brackets, markdown artifacts
            if (trimmed.isEmpty || trimmed == ',' || trimmed == '[' || trimmed == ']' || 
                trimmed.startsWith('```') || trimmed == 'json') {
              continue;
            }
            
            // Check if it's a JSON-encoded string like "{\"option\": \"text\"}"
            if (trimmed.startsWith('{')) {
              try {
                // Remove trailing comma if present
                String cleaned = trimmed;
                if (cleaned.endsWith(',')) {
                  cleaned = cleaned.substring(0, cleaned.length - 1);
                }
                
                final parsed = json.decode(cleaned);
                
                // Extract the actual text from the parsed object
                if (parsed is Map) {
                  final text = parsed['option']?.toString().trim() ?? 
                               parsed['text']?.toString().trim() ?? 
                               parsed['word']?.toString().trim() ?? 
                               trimmed;
                  if (text.isNotEmpty && !text.startsWith('{') && !text.startsWith('```')) {
                    options.add(text);
                  }
                } else {
                  if (!trimmed.startsWith('```')) {
                    options.add(trimmed);
                  }
                }
              } catch (e) {
                print('Direct Options API Failed to parse as JSON: $e');
                // If parsing fails and it's not markdown, use the string as-is
                if (!trimmed.startsWith('```')) {
                  options.add(trimmed);
                }
              }
            } else {
              // Not JSON, use as-is (but skip markdown)
              if (!trimmed.startsWith('```')) {
                options.add(trimmed);
              }
            }
          } else if (option is Map) {
            // Already a parsed object, extract the text field
            final text = option['option']?.toString().trim() ?? 
                         option['text']?.toString().trim() ?? 
                         option['word']?.toString().trim() ?? 
                         option.toString().trim();
            if (text.isNotEmpty && !text.startsWith('{') && !text.startsWith('```')) {
              options.add(text);
            }
          } else {
            // Other type, convert to string
            final text = option.toString().trim();
            if (text.isNotEmpty && !text.startsWith('```')) {
              options.add(text);
            }
          }
        }
        
        final filteredOptions = options.where((option) => 
          option.isNotEmpty && 
          !option.startsWith('{') && 
          !option.contains('option":') &&
          !option.startsWith('```') &&
          option != 'json'
        ).toList();

        // Normalize to single-word options only (Words section expects single tokens)
        final cleanedOptions = filteredOptions
            .map(_normalizeSingleWordOption)
            .where((option) => option.isNotEmpty)
            .toList();
        
        print('Direct Options API Final Extracted Options (${cleanedOptions.length}): ${cleanedOptions.take(10).toList()}');
        return cleanedOptions;
      }
      
      print('Failed to generate direct options: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error generating direct options: $e');
      return [];
    }
  }

  /// Generate word options for text completion using a custom prompt
  /// This method is used when a category has a wordsPrompt defined
  Future<List<Map<String, dynamic>>> generateCustomWordOptions({
    required String prompt,
    int maxOptions = 30,
  }) async {
    try {
      print('🎯 TapInterfaceService - generateCustomWordOptions called with:');
      print('   prompt: "$prompt"');
      print('   maxOptions: $maxOptions');
      
      // Note: Mood context support can be added later if needed
      String moodContext = '';
      
      print('Using custom words prompt for text completion');
      
      // Create intelligent prompt based on the type of starter word
      String intelligentPrompt = _createIntelligentPrompt(prompt, maxOptions, moodContext);
      
      // Use the /llm endpoint like the web app does
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userSettingsProvider.userId ?? '',
        },
        body: json.encode({
          'prompt': intelligentPrompt
        }),
        timeoutSeconds: 30,
      );

      print('Custom Words LLM Response: ${response.statusCode}');
      print('Custom Words LLM Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Custom Words LLM Parsed Data: $data');
        
        // Convert LLM response format to words format with keywords preserved
        final words = <Map<String, dynamic>>[];
        if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic> && item['option'] != null) {
              final optionText = item['option'].toString().trim();
              if (optionText.isNotEmpty && 
                  !optionText.toLowerCase().contains('here are') &&
                  optionText != prompt &&
                  optionText.length <= 50) {
                
                // Remove the original prompt from the beginning if it exists
                String cleanedOption = _removePromptFromOption(optionText, prompt);
                final normalizedText = _normalizeOptionText(cleanedOption);
                
                // Extract keywords from the LLM response, prioritizing nouns for image matching
                List<String> keywords = [];
                if (item['keywords'] != null) {
                  if (item['keywords'] is List) {
                    keywords = (item['keywords'] as List).map((k) => k.toString()).toList();
                  } else if (item['keywords'] is String) {
                    keywords = [item['keywords'].toString()];
                  }
                }
                
                // If no keywords provided, extract potential nouns from the text as fallback
                if (keywords.isEmpty) {
                  keywords = _extractImageKeywords(normalizedText);
                  print('Generated fallback keywords for "$normalizedText": $keywords');
                }
                
                words.add({
                  'text': normalizedText,
                  'summary': item['summary']?.toString() ?? normalizedText,
                  'keywords': keywords,
                });
              }
            }
          }
        }
        
        print('Custom Words LLM Final Words: ${words.length} items with keywords');
        return words;
      }
      
      print('Failed to generate custom word options: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error generating custom word options: $e');
      return [];
    }
  }

  /// Create an intelligent prompt based on the starter word type
  String _createIntelligentPrompt(String prompt, int maxOptions, String moodContext) {
    final promptLower = prompt.toLowerCase().trim();
    
    // Question words that should generate meaningful question continuations
    if (promptLower == 'who') {
      return 'Generate $maxOptions different ways to complete the question "Who..." with logical, meaningful continuations$moodContext. Examples: "is at the door", "called me", "wants to play", "is my teacher", "lives here". Each option should complete the question "Who..." to make a sensible question someone might ask. For keywords, focus on NOUNS and PEOPLE (like "teacher", "friend", "mom", "doctor") that would be good for image matching, not action words. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'what') {
      return 'Generate $maxOptions different ways to complete the question "What..." with logical, meaningful continuations$moodContext. Examples: "time is it", "are we eating", "is that sound", "happened today", "should I do". Each option should complete the question "What..." to make a sensible question someone might ask. For keywords, focus on NOUNS and OBJECTS (like "food", "sound", "time", "activity") that would be good for image matching, not action words. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'where') {
      return 'Generate $maxOptions different ways to complete the question "Where..." with logical, meaningful continuations$moodContext. Examples: "is Mom", "are we going", "did I put my keys", "is the bathroom", "should we meet". Each option should complete the question "Where..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'when') {
      return 'Generate $maxOptions different ways to complete the question "When..." with logical, meaningful continuations$moodContext. Examples: "are we leaving", "is dinner ready", "do I need to be there", "will you be back", "did this happen". Each option should complete the question "When..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'why') {
      return 'Generate $maxOptions different ways to complete the question "Why..." with logical, meaningful continuations$moodContext. Examples: "are you sad", "is this happening", "can\'t I go", "did you do that", "is it so loud". Each option should complete the question "Why..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'how') {
      return 'Generate $maxOptions different ways to complete the question "How..." with logical, meaningful continuations$moodContext. Examples: "are you feeling", "do I do this", "long will it take", "did you know", "much does it cost". Each option should complete the question "How..." to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'can' || promptLower == 'could') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "I help you", "we go outside", "you show me", "I have a snack", "we play together". Each option should complete the question to make a sensible request or question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'should' || promptLower == 'would') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "I call Mom", "we go home", "you like this", "I wear a jacket", "we have lunch". Each option should complete the question to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'do' || promptLower == 'does' || promptLower == 'did') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "you want to play", "this work", "I miss anything", "you need help", "we have time". Each option should complete the question to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else if (promptLower == 'is' || promptLower == 'are' || promptLower == 'was' || promptLower == 'were') {
      return 'Generate $maxOptions different ways to complete the question starting with "$prompt..." with logical, meaningful continuations$moodContext. Examples: "Mom coming home", "you feeling better", "that the doorbell", "we going soon", "dinner ready". Each option should complete the question to make a sensible question someone might ask. Return as a JSON array with "option", "summary", and "keywords" keys.';
    } else {
      // For non-question starters, use the original approach
      return 'Complete this sentence starter: "$prompt" with $maxOptions different continuations$moodContext. Each option should be the continuation part that comes AFTER "$prompt". Allow proper nouns, place names, and multi-word phrases (1-4 words each). Examples: if prompt is "I want to go to", generate options like "the park", "Broncos stadium", "my room". For keywords, focus on MAIN NOUNS and SUBJECTS (like "park", "stadium", "room", "burger", "salad") that represent the primary object or place, not adjectives like "big" or "light". Return as a JSON array with "option", "summary", and "keywords" keys.';
    }
  }

  /// Extract meaningful keywords for image matching, prioritizing nouns over adjectives
  List<String> _extractImageKeywords(String text) {
    // Common adjectives that should not be primary image keywords
    final adjectives = {
      'big', 'small', 'large', 'little', 'tiny', 'huge', 'giant', 'mini',
      'light', 'dark', 'bright', 'dim', 'heavy', 'soft', 'hard', 'rough', 'smooth',
      'hot', 'cold', 'warm', 'cool', 'freezing', 'burning', 'icy',
      'fast', 'slow', 'quick', 'rapid', 'speedy', 'sluggish',
      'old', 'new', 'young', 'ancient', 'modern', 'fresh', 'stale',
      'good', 'bad', 'great', 'terrible', 'awful', 'amazing', 'wonderful',
      'beautiful', 'ugly', 'pretty', 'handsome', 'cute', 'adorable',
      'loud', 'quiet', 'noisy', 'silent', 'peaceful',
      'clean', 'dirty', 'messy', 'tidy', 'neat',
      'happy', 'sad', 'angry', 'excited', 'calm', 'nervous',
      'red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'brown', 'black', 'white', 'gray', 'grey',
      'round', 'square', 'long', 'short', 'wide', 'narrow', 'thick', 'thin',
      'wet', 'dry', 'damp', 'moist', 'soggy',
      'empty', 'full', 'half', 'complete', 'incomplete',
      'open', 'closed', 'broken', 'fixed', 'damaged',
      'cheap', 'expensive', 'free', 'costly',
      'easy', 'difficult', 'simple', 'complex',
      'safe', 'dangerous', 'risky', 'secure',
      'funny', 'serious', 'silly', 'smart', 'clever', 'stupid',
      'rich', 'poor', 'wealthy', 'broke',
      'healthy', 'sick', 'ill', 'well',
      'busy', 'lazy', 'active', 'tired', 'energetic'
    };
    
    // Common nouns that make good image keywords
    final goodNouns = {
      'burger', 'salad', 'pizza', 'sandwich', 'soup', 'pasta', 'chicken', 'fish', 'beef', 'vegetables',
      'park', 'beach', 'stadium', 'school', 'hospital', 'store', 'restaurant', 'library', 'theater',
      'car', 'bus', 'train', 'plane', 'bike', 'boat', 'truck', 'motorcycle',
      'dog', 'cat', 'bird', 'horse', 'elephant', 'lion', 'bear', 'rabbit', 'animal',
      'book', 'phone', 'computer', 'table', 'chair', 'bed', 'house', 'door', 'window',
      'ball', 'game', 'toy', 'music', 'movie', 'picture', 'photo',
      'water', 'milk', 'juice', 'coffee', 'tea', 'soda',
      'shirt', 'pants', 'shoes', 'hat', 'jacket', 'dress', 'socks',
      'apple', 'banana', 'orange', 'grape', 'strawberry', 'cookie', 'cake', 'bread',
      'friend', 'family', 'mom', 'dad', 'child', 'baby', 'person', 'people',
      'money', 'job', 'work', 'office', 'meeting', 'party', 'celebration'
    };
    
    // Split text into words and clean them
    final words = text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Remove punctuation
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    
    List<String> keywords = [];
    
    // First pass: Find known good nouns
    for (final word in words) {
      if (goodNouns.contains(word)) {
        keywords.add(word);
      }
    }
    
    // Second pass: Add other words that aren't adjectives (potential nouns)
    for (final word in words) {
      if (!adjectives.contains(word) && 
          !goodNouns.contains(word) && 
          word.length > 2 && // Skip very short words
          !keywords.contains(word)) {
        keywords.add(word);
      }
    }
    
    // If we still don't have keywords, take the longest non-adjective words
    if (keywords.isEmpty) {
      final nonAdjectives = words
          .where((word) => !adjectives.contains(word) && word.length > 2)
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length)); // Sort by length descending
      
      keywords.addAll(nonAdjectives.take(3)); // Take up to 3 longest words
    }
    
    // Limit to reasonable number of keywords
    return keywords.take(5).toList();
  }

  /// Remove the original prompt from the option text to get just the completion part
  String _removePromptFromOption(String optionText, String originalPrompt) {
    final optionLower = optionText.toLowerCase().trim();
    final promptLower = originalPrompt.toLowerCase().trim();
    
    // If the option starts with the prompt, remove it
    if (optionLower.startsWith(promptLower)) {
      String remainder = optionText.substring(originalPrompt.length).trim();
      // If there's remaining text after removing the prompt, return it
      if (remainder.isNotEmpty) {
        return remainder;
      }
    }
    
    // If the option doesn't start with prompt or has no remainder, return as-is
    return optionText;
  }

  /// Normalize option text by removing numbered prefixes and cleaning up formatting
  String _normalizeOptionText(String raw) {
    var text = raw.trim();
    // Remove surrounding quotes if accidentally included
    if (text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1).trim();
    }
    // Strip common numbered prefixes: "1.", "1)", "1 -", "1:"
    text = text.replaceFirst(RegExp(r'^\s*\d+\s*[\.\)\-:]\s*'), '');
    // Also strip leading bullets like "- " or "• "
    text = text.replaceFirst(RegExp(r'^[\-•]\s*'), '');
    return text.trim();
  }

  /// Normalize direct word options to a single token and drop phrase-like outputs
  String _normalizeSingleWordOption(String raw) {
    var text = _normalizeOptionText(raw);

    // Remove common LLM artifacts like "summary" or "option" prefixes
    text = text.replaceFirst(RegExp(r'^(summary|option|options)\b[:\-]?\s*', caseSensitive: false), '');

    // Collapse punctuation into spaces
    text = text.replaceAll(RegExp(r"[^\p{L}\p{N}\-']+", unicode: true), ' ').trim();

    if (text.isEmpty) return '';

    // Keep only single-word options for the Words section
    if (text.contains(RegExp(r'\s+'))) {
      return '';
    }

    // Guard against stray artifacts
    if (text.toLowerCase() == 'summary' || text.toLowerCase() == 'option') {
      return '';
    }

    return text;
  }
}