import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for managing Dolch sight words and determining when to suppress pictograms
class SightWordService {
  static final SightWordService _instance = SightWordService._internal();
  factory SightWordService() => _instance;
  SightWordService._internal();

  Map<String, dynamic>? _sightWordsData;
  Set<String>? _currentSightWords;
  String _currentGradeLevel = 'pre_k';

  /// Initialize the service by loading sight words data
  Future<void> initialize() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/dolch_sight_words.json');
      _sightWordsData = jsonDecode(jsonString);
      await _updateSightWordsForGradeLevel(_currentGradeLevel);
      debugPrint('🔤 SightWordService: Initialized with ${_currentSightWords?.length ?? 0} sight words for grade level: $_currentGradeLevel');
    } catch (e) {
      debugPrint('🔤 SightWordService: Error loading sight words data: $e');
      _sightWordsData = null;
      _currentSightWords = null;
    }
  }

  /// Update the grade level and rebuild the sight words set
  Future<void> setGradeLevel(String gradeLevel) async {
    if (gradeLevel != _currentGradeLevel) {
      _currentGradeLevel = gradeLevel;
      await _updateSightWordsForGradeLevel(gradeLevel);
      debugPrint('🔤 SightWordService: Updated to grade level: $gradeLevel (${_currentSightWords?.length ?? 0} words)');
    }
  }

  /// Get the current grade level
  String get currentGradeLevel => _currentGradeLevel;

  /// Check if a given text should be displayed as text-only (without pictogram)
  /// Returns true if ALL words in the text are sight words
  bool isSightWordText(String text) {
    if (_currentSightWords == null || _currentSightWords!.isEmpty) {
      return false;
    }

    final cleanText = text.trim().toLowerCase();
    if (cleanText.isEmpty) {
      return false;
    }

    // Split into words and remove punctuation
    final words = cleanText
        .split(RegExp(r'\s+'))
        .map((word) => word.replaceAll(RegExp(r'[^\w]'), ''))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return false;
    }

    // ALL words must be sight words for the text to be considered a sight word phrase
    final allAreSightWords = words.every((word) => _currentSightWords!.contains(word));
    
    if (allAreSightWords) {
      debugPrint('🔤 SightWordService: "$text" identified as sight word text (all ${words.length} words are sight words)');
    }

    return allAreSightWords;
  }

  /// Get all sight words for the current grade level
  Set<String> getAllSightWords() {
    return Set.from(_currentSightWords ?? {});
  }

  /// Get statistics about current sight words
  Map<String, dynamic> getStats() {
    return {
      'gradeLevel': _currentGradeLevel,
      'totalWords': _currentSightWords?.length ?? 0,
      'dataLoaded': _sightWordsData != null,
    };
  }

  /// Update the sight words set based on the grade level (cumulative)
  Future<void> _updateSightWordsForGradeLevel(String gradeLevel) async {
    if (_sightWordsData == null) {
      _currentSightWords = null;
      return;
    }

    try {
      final gradeLevels = _sightWordsData!['grade_levels'] as Map<String, dynamic>?;
      final sightWords = _sightWordsData!['dolch_sight_words'] as Map<String, dynamic>?;

      if (gradeLevels == null || sightWords == null) {
        debugPrint('🔤 SightWordService: Invalid sight words data structure');
        _currentSightWords = null;
        return;
      }

      final gradeConfig = gradeLevels[gradeLevel] as Map<String, dynamic>?;
      if (gradeConfig == null) {
        debugPrint('🔤 SightWordService: Unknown grade level: $gradeLevel, defaulting to pre_k');
        _currentGradeLevel = 'pre_k';
        await _updateSightWordsForGradeLevel('pre_k');
        return;
      }

      final includes = List<String>.from(gradeConfig['includes'] as List);
      final allWords = <String>{};

      for (final level in includes) {
        final levelWords = List<String>.from(sightWords[level] as List? ?? []);
        allWords.addAll(levelWords.map((word) => word.toLowerCase()));
      }

      _currentSightWords = allWords;
      debugPrint('🔤 SightWordService: Loaded ${allWords.length} sight words for $gradeLevel (includes: ${includes.join(', ')})');

    } catch (e) {
      debugPrint('🔤 SightWordService: Error updating sight words for grade level $gradeLevel: $e');
      _currentSightWords = null;
    }
  }

  /// Check if the service is properly initialized
  bool get isInitialized => _sightWordsData != null;

  /// Get available grade levels
  List<String> getAvailableGradeLevels() {
    if (_sightWordsData == null) return [];
    
    final gradeLevels = _sightWordsData!['grade_levels'] as Map<String, dynamic>?;
    return gradeLevels?.keys.toList() ?? [];
  }

  /// Get human-readable name for a grade level
  String getGradeLevelName(String gradeLevel) {
    if (_sightWordsData == null) return gradeLevel;
    
    final gradeLevels = _sightWordsData!['grade_levels'] as Map<String, dynamic>?;
    final gradeConfig = gradeLevels?[gradeLevel] as Map<String, dynamic>?;
    return gradeConfig?['name'] as String? ?? gradeLevel;
  }
}