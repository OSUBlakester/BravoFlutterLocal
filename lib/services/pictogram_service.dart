import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/custom_image.dart';
import '../config/environment_config.dart';
import 'sight_word_service.dart';
import 'custom_image_service.dart';
import 'package:path_provider/path_provider.dart';
import 'authenticated_http_client.dart';
import 'storage_image_url_service.dart';

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

  static const Map<String, List<String>> _spanishToEnglishFallbacks = {
    'por favor': ['please'],
    'gracias': ['thank you', 'thanks'],
    'de nada': ['you are welcome'],
    'lo siento': ['sorry'],
    'perdon': ['sorry'],
    'perdón': ['sorry'],
    'hola': ['hello'],
    'adios': ['goodbye', 'bye'],
    'adiós': ['goodbye', 'bye'],
    'buenos dias': ['good morning'],
    'buenos días': ['good morning'],
    'buenas noches': ['good night'],
    'casa': ['home'],
    'bano': ['bathroom', 'toilet'],
    'baño': ['bathroom', 'toilet'],
    'yo': ['i', 'me'],
    'tu': ['you'],
    'tú': ['you'],
    'usted': ['you'],
    'ustedes': ['you'],
    'nosotros': ['we'],
    'nosotras': ['we'],
    'ellos': ['they'],
    'ellas': ['they'],
    'triste': ['sad'],
    'feliz': ['happy'],
    'alla': ['there'],
    'allá': ['there'],
    'aqui': ['here'],
    'aquí': ['here'],
    'mirar': ['look'],
    'quiero': ['want'],
    'querer': ['want'],
    'necesito': ['need'],
    'necesitar': ['need'],
    'me gusta': ['like'],
    'gusta': ['like'],
    'gustar': ['like'],
    'bebe': ['baby'],
    'bebe?': ['baby'],
    'bebé': ['baby'],
    'agua': ['water'],
    'leche': ['milk'],
    'comer': ['eat', 'food'],
    'como': ['eat', 'food'],
    'beber': ['drink'],
    'tengo': ['have'],
    'tener': ['have'],
    'quieres': ['want'],
    'quiere': ['want'],
    'vamos': ['go'],
    'ir': ['go'],
    'ven': ['come'],
    'venir': ['come'],
    'dame': ['give'],
    'dar': ['give'],
    'ayuda': ['help'],
    'ayudar': ['help'],
    'si': ['yes'],
    'sí': ['yes'],
    'no': ['no'],
  };

  // Generic reverse mappings from localized starter vocabulary to canonical
  // English image terms. This is language-level logic (not per-button hacks)
  // and is used when server localized search is incomplete.
  static const Map<String, Map<String, List<String>>> _localizedToEnglishLexicon = {
    'es': {
      'yo': ['i', 'me'],
      'tu': ['you'],
      'tú': ['you'],
      'nosotros': ['we'],
      'quiero': ['want'],
      'necesito': ['need'],
      'gusta': ['like'],
      'ir': ['go'],
      'ver': ['see', 'look'],
      'ayuda': ['help'],
      'mas': ['more'],
      'más': ['more'],
      'muy': ['very', 'really'],
      'tan': ['so'],
      'mucho': ['a lot', 'more'],
      'mucha': ['a lot', 'more'],
      'muchos': ['a lot', 'more'],
      'muchas': ['a lot', 'more'],
      'poco': ['little'],
      'poca': ['little'],
      'pocos': ['few'],
      'pocas': ['few'],
      'ya': ['already', 'now'],
      'todavia': ['still', 'yet'],
      'todavía': ['still', 'yet'],
      'tambien': ['also'],
      'también': ['also'],
      'por favor': ['please'],
      'tienda': ['store', 'shop', 'market'],
      'comprar': ['buy', 'shop'],
      'mercado': ['market', 'store'],
      'algo mas': ['something else', 'more'],
      'algo más': ['something else', 'more'],
      'si': ['yes'],
      'sí': ['yes'],
      'ok': ['okay'],
      'detener': ['stop'],
      'otra vez': ['again'],
      'bueno': ['good'],
      'bien': ['good'],
      'malo': ['bad'],
      'mal': ['bad'],
      'feliz': ['happy'],
      'triste': ['sad'],
      'cansado': ['tired'],
      'esto': ['this'],
      'eso': ['that'],
      'aqui': ['here'],
      'aquí': ['here'],
      'alli': ['there'],
      'allí': ['there'],
      'alla': ['there'],
      'allá': ['there'],
      'ahora': ['now'],
      'luego': ['later'],
      'hoy': ['today'],
      'hablar': ['talk'],
      'jugar': ['play'],
      'comer': ['eat', 'food'],
      'beber': ['drink'],
      'mirar': ['look', 'see'],
      'mi': ['my', 'me'],
    },
  };

  // Cache for storing image URLs to avoid repeated API calls (global shared library)
  final Map<String, String?> _imageCache = {};
  final Map<String, String> _fallbackTermUrlCache = {};
  final Map<String, Future<String?>> _inFlightImageLookups = {};
  final Map<String, String> _canonicalSearchCache = {};
  Timer? _cachePersistDebounceTimer;
  bool _cachePersistQueued = false;
  bool _cachePersistInFlight = false;
  static const Duration _cachePersistDebounceDelay = Duration(milliseconds: 450);

  static const String _pictogramCachePrefsKey = 'pictogram_cache';
  static const String _pictogramEnvPrefsKey = 'pictogram_cache_environment';
  static const String _pictogramCacheVersionPrefsKey =
      'pictogram_cache_matching_version';
  static const String _currentPictogramCacheVersion = '6';
  static const String _fallbackUrlCachePrefsKey = 'pictogram_fallback_url_cache_v2';
  static const String _canonicalSearchCachePrefsKey = 'pictogram_canonical_search_cache_v2';
  static const String _remoteFilePathCachePrefsKey =
      'pictogram_remote_file_path_cache_v1';

  final Map<String, String> _remoteFilePathCache = {};
  
  // Current user context for future custom images feature
  String? _currentUserId;
  String? _currentIdToken;
  String? _currentMascot;
  
  // Custom image batch preloading
  final List<CustomImage> _customImages = [];
  Map<String, String> _customImageMatches = {};
  bool _customImagesPreloaded = false;
  Future<void>? _customImagesPreloadFuture;

  // Local Symbol Library Cache
  final Map<String, String> _localLibraryTagIndex = {};
  // Reverse index: imageUrl -> list of tags, used to validate library matches.
  final Map<String, List<String>> _localLibraryUrlTags = {};
  // Canonical field index: imageUrl -> normalized subconcept/subcategory.
  final Map<String, String> _localLibraryUrlSubconcept = {};
  bool _libraryLoaded = false;
  Future<void>? _libraryLoadFuture;
  static const String _libraryFilename = 'bravo_symbol_library.json';
  static const String _libraryTimestampPrefsKey = 'symbol_library_download_time';
  
  // Service settings
  bool enablePictograms = true;

  // Profile image cache for personal pronouns (I/me/myself).
  String? _profileImageUrl;
  DateTime? _profileImageFetchedAt;
  String? _profileImageForUserId;
  static const Duration _profileImageCacheTtl = Duration(minutes: 5);
  static const String _localProfileImagePathPrefix = 'local_profile_image_path_';

  // Prevent repeated slow button-search attempts when the endpoint is timing out.
  // Cooldown is tracked per (locale, term) so one timeout does not block all words.
  final Map<String, DateTime> _skipButtonSearchUntilByKey = {};
  static const Duration _buttonSearchTimeoutCooldown = Duration(seconds: 25);
  bool _skipDirectFirestoreReads = false;

  bool _isFirestorePermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  void _handleFirestoreReadError(Object error, String context) {
    if (_isFirestorePermissionDenied(error)) {
      if (!_skipDirectFirestoreReads) {
        debugPrint(
          '🚫 PictogramService: Firestore read blocked by rules in $context; disabling direct Firestore lookups for this session',
        );
      }
      _skipDirectFirestoreReads = true;
    }
  }

  String _normalizeLookupKey(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeAsciiLookupKey(String value) {
    return _normalizeLookupKey(_stripDiacritics(value));
  }

  String _buildPrimaryCacheKey(String text, {String? locale}) {
    final normalized = _normalizeAsciiLookupKey(text);
    final isNonEnglish = locale != null && !locale.startsWith('en');
    final baseKey = isNonEnglish ? '${locale.toLowerCase()}:$normalized' : normalized;
    return _currentMascot != null ? '$_currentMascot::$baseKey' : baseKey;
  }

  String _buildButtonSearchCooldownKey(String text, {String? locale}) {
    final normalized = _normalizeAsciiLookupKey(text);
    if (locale == null || locale.isEmpty) {
      return normalized;
    }
    return '${locale.toLowerCase()}:$normalized';
  }

  DateTime? _getButtonSearchCooldownExpiry(String text, {String? locale}) {
    final key = _buildButtonSearchCooldownKey(text, locale: locale);
    final expiry = _skipButtonSearchUntilByKey[key];
    if (expiry == null) return null;
    if (!DateTime.now().isBefore(expiry)) {
      _skipButtonSearchUntilByKey.remove(key);
      return null;
    }
    return expiry;
  }

  void _markButtonSearchTimeout(String text, {String? locale}) {
    final key = _buildButtonSearchCooldownKey(text, locale: locale);
    final expiry = DateTime.now().add(_buttonSearchTimeoutCooldown);
    _skipButtonSearchUntilByKey[key] = expiry;
    debugPrint(
      'PictogramService: button-search timed out for "$text" (locale=$locale); cooling down this term until $expiry',
    );
  }

  List<String> _buildCacheKeyVariants(String text, {String? locale}) {
    final isNonEnglish = locale != null && !locale.startsWith('en');
    final rawNormalized = _normalizeLookupKey(text);
    final asciiNormalized = _normalizeAsciiLookupKey(text);
    final mascotPrefix = _currentMascot != null ? '$_currentMascot::' : '';

    if (!isNonEnglish) {
      return ['$mascotPrefix$rawNormalized'];
    }

    final variants = <String>[];
    final seen = <String>{};

    void addKey(String key) {
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      variants.add(key);
    }

    addKey('$mascotPrefix${locale.toLowerCase()}:$asciiNormalized');
    addKey('$mascotPrefix${locale.toLowerCase()}:$rawNormalized');
    return variants;
  }

  bool _isStaleLocalFileUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    if (!url.startsWith('file://')) return false;

    try {
      final path = Uri.parse(url).toFilePath();
      return !File(path).existsSync();
    } catch (_) {
      return true;
    }
  }

  String? _getLocalFileUrlForRemote(String remoteUrl) {
    final mappedPath = _remoteFilePathCache[remoteUrl];
    if (mappedPath == null || mappedPath.isEmpty) {
      return null;
    }

    final localFile = File(mappedPath);
    if (!localFile.existsSync()) {
      _remoteFilePathCache.remove(remoteUrl);
      return null;
    }

    return 'file://$mappedPath';
  }

  void _rememberLocalFileForRemote(String remoteUrl, String localPath) {
    final normalizedRemote = remoteUrl.trim();
    if (normalizedRemote.isEmpty || localPath.trim().isEmpty) {
      return;
    }
    _remoteFilePathCache[normalizedRemote] = localPath;
    unawaited(_saveCacheToPrefs());
  }

  Future<String?> _resolveDisplayImageUrl(
    String? sourceUrl, {
    bool cacheOnly = false,
  }) async {
    if (sourceUrl == null || sourceUrl.isEmpty) {
      return sourceUrl;
    }

    final trimmed = sourceUrl.trim();
    if (!trimmed.startsWith('http')) {
      return trimmed;
    }

    final mappedLocalUrl = _getLocalFileUrlForRemote(trimmed);
    if (mappedLocalUrl != null) {
      return mappedLocalUrl;
    }

    try {
      final cachedInfo = await DefaultCacheManager().getFileFromCache(trimmed);
      if (cachedInfo != null && cachedInfo.file.existsSync()) {
        final localPath = cachedInfo.file.path;
        _rememberLocalFileForRemote(trimmed, localPath);
        return 'file://$localPath';
      }
    } catch (e) {
      debugPrint('PictogramService: local file cache lookup failed for "$trimmed": $e');
    }

    if (!cacheOnly) {
      unawaited(_cacheRemoteImageFileInBackground(trimmed));
    }

    return trimmed;
  }

  Future<void> _cacheRemoteImageFileInBackground(String remoteUrl) async {
    if (remoteUrl.isEmpty || !remoteUrl.startsWith('http')) {
      return;
    }

    try {
      final cachedFile = await DefaultCacheManager().getSingleFile(remoteUrl);
      if (cachedFile.existsSync()) {
        _rememberLocalFileForRemote(remoteUrl, cachedFile.path);
      }
    } catch (e) {
      debugPrint('PictogramService: background remote image cache failed for "$remoteUrl": $e');
    }
  }

  List<String> _buildSearchVariants(String text) {
    final original = text.trim();
    final normalized = _normalizeLookupKey(text);
    if (normalized.isEmpty) return const [];

    final ascii = _normalizeAsciiLookupKey(text);
    final compact = ascii
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final variants = <String>[];
    final seen = <String>{};
    void addVariant(String value) {
      final key = _normalizeLookupKey(value);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      variants.add(key);
    }

    addVariant(original);
    addVariant(normalized);
    addVariant(original.toLowerCase());
    addVariant(_stripDiacritics(original));
    addVariant(ascii);
    addVariant(compact);
    return variants;
  }

  List<String> _buildLocalizedTagQueryVariants(String text) {
    final original = text.trim();
    if (original.isEmpty) return const [];

    final variants = <String>[];
    final seen = <String>{};

    void addVariant(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      variants.add(trimmed);
    }

    // Firestore arrayContains is exact and case-sensitive; try preserved forms first.
    addVariant(original);
    addVariant(original.toLowerCase());
    addVariant(_stripDiacritics(original));
    addVariant(_stripDiacritics(original).toLowerCase());

    // Include normalized forms as fallback.
    addVariant(_normalizeLookupKey(original));
    addVariant(_normalizeAsciiLookupKey(original));

    return variants;
  }

  List<String> _buildFirestoreExactMatchVariants(String text) {
    final baseVariants = _buildLocalizedTagQueryVariants(text);
    final variants = <String>[];
    final seen = <String>{};

    void addVariant(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      variants.add(trimmed);
    }

    for (final base in baseVariants) {
      addVariant(base);
      addVariant(base.toUpperCase());
      if (base.isNotEmpty) {
        addVariant(base[0].toUpperCase() + base.substring(1).toLowerCase());
      }
    }

    return variants;
  }

  List<String> _getLocalizedLexiconTerms(String raw, String? locale) {
    if (locale == null || locale.isEmpty) return const [];
    final langCode = locale.split('-').first.toLowerCase();
    final lexicon = _localizedToEnglishLexicon[langCode];
    if (lexicon == null) return const [];

    final normalized = _normalizeLookupKey(raw);
    final normalizedAscii = _normalizeAsciiLookupKey(raw);

    final terms = <String>[];
    final seen = <String>{};

    void addTerm(String value) {
      final key = _normalizeLookupKey(value);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      terms.add(key);
    }

    final direct = lexicon[normalized];
    if (direct != null) {
      for (final term in direct) {
        addTerm(term);
      }
    }

    if (normalizedAscii != normalized) {
      final asciiDirect = lexicon[normalizedAscii];
      if (asciiDirect != null) {
        for (final term in asciiDirect) {
          addTerm(term);
        }
      }
    }

    return terms;
  }

  List<String> _getLocaleFieldCandidates(String locale) {
    final trimmed = locale.trim();
    if (trimmed.isEmpty) return const [];
    final langCode = trimmed.split('-').first.toLowerCase();
    final candidates = <String>[];
    // Always prefer base language first (e.g., es) because localized_tags are
    // typically stored by language code, not full locale (es-US).
    if (langCode.isNotEmpty) {
      candidates.add(langCode);
    }
    if (trimmed.isNotEmpty && trimmed.toLowerCase() != langCode) {
      candidates.add(trimmed);
    }
    return candidates;
  }

  String? _extractAacImageUrl(Map<String, dynamic> data) {
    final candidates = [
      data['url'],
      data['imageUrl'],
      data['image_url'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  Future<String?> _fetchViaLocalizedTags(String text, String locale) async {
    if (_skipDirectFirestoreReads) {
      return null;
    }

    final localeCandidates = _getLocaleFieldCandidates(locale);
    if (localeCandidates.isEmpty) return null;

    final variants = _buildLocalizedTagQueryVariants(text);
    if (variants.isEmpty) return null;

    for (final variant in variants.take(4)) {
      for (final langCode in localeCandidates) {
        try {
          debugPrint(
            '🔍 Localized tags lookup: text="$text" variant="$variant" lang="$langCode"',
          );
          final snapshot = await FirebaseFirestore.instance
              .collection('aac_images')
              .where('localized_tags.$langCode', arrayContains: variant)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 2));

          debugPrint(
            '🔍 Localized tags result: variant="$variant" lang="$langCode" docs=${snapshot.docs.length}',
          );

          if (snapshot.docs.isNotEmpty) {
            final data = snapshot.docs.first.data();
            final imageUrl = _extractAacImageUrl(data);
            if (imageUrl != null && imageUrl.isNotEmpty) {
              debugPrint(
                '✅ Localized tags match: variant="$variant" lang="$langCode" url=$imageUrl',
              );
              return imageUrl;
            }
          }
        } catch (e) {
          _handleFirestoreReadError(e, 'localized_tags query');
          debugPrint(
            '⚠️ Localized tags lookup error: text="$text" variant="$variant" lang="$langCode" error=$e',
          );
          if (_skipDirectFirestoreReads) {
            return null;
          }
          // Continue to next locale candidate (e.g., es after es-US).
        }
      }
    }

    return null;
  }

  Future<String?> _fetchViaDirectAacTagsAndSubconcept(List<String> terms) async {
    if (_skipDirectFirestoreReads) {
      return null;
    }

    if (terms.isEmpty) return null;

    final variants = <String>[];
    final seen = <String>{};

    void addVariant(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      variants.add(trimmed);
    }

    for (final term in terms) {
      for (final variant in _buildFirestoreExactMatchVariants(term)) {
        addVariant(variant);
      }
      if (variants.length >= 12) {
        break;
      }
    }

    if (variants.isEmpty) return null;

    for (final variant in variants.take(12)) {
      // Prioritize canonical category fields over generic tags.
      try {
        final subconceptSnapshot = await FirebaseFirestore.instance
            .collection('aac_images')
            .where('subconcept', isEqualTo: variant)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 2));

        if (subconceptSnapshot.docs.isNotEmpty) {
          final data = subconceptSnapshot.docs.first.data();
          final imageUrl = _extractAacImageUrl(data);
          if (imageUrl != null && imageUrl.isNotEmpty) {
            debugPrint('✅ Direct subconcept match: variant="$variant" url=$imageUrl');
            return imageUrl;
          }
        }
      } catch (e) {
        _handleFirestoreReadError(e, 'aac_images.subconcept query');
        if (_skipDirectFirestoreReads) {
          return null;
        }
        // Continue to next fallback query.
      }

      try {
        final tagSnapshot = await FirebaseFirestore.instance
            .collection('aac_images')
            .where('tags', arrayContains: variant)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 2));

        if (tagSnapshot.docs.isNotEmpty) {
          final data = tagSnapshot.docs.first.data();
          final imageUrl = _extractAacImageUrl(data);
          if (imageUrl != null && imageUrl.isNotEmpty) {
            debugPrint('✅ Direct tags match: variant="$variant" url=$imageUrl');
            return imageUrl;
          }
        }
      } catch (e) {
        _handleFirestoreReadError(e, 'aac_images.tags query');
        if (_skipDirectFirestoreReads) {
          return null;
        }
        // Continue to next fallback query.
      }

      try {
        final searchTagsSnapshot = await FirebaseFirestore.instance
            .collection('aac_images')
            .where('search_tags', arrayContains: variant)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 2));

        if (searchTagsSnapshot.docs.isNotEmpty) {
          final data = searchTagsSnapshot.docs.first.data();
          final imageUrl = _extractAacImageUrl(data);
          if (imageUrl != null && imageUrl.isNotEmpty) {
            debugPrint('✅ Direct search_tags match: variant="$variant" url=$imageUrl');
            return imageUrl;
          }
        }
      } catch (e) {
        _handleFirestoreReadError(e, 'aac_images.search_tags query');
        if (_skipDirectFirestoreReads) {
          return null;
        }
        // Continue to next fallback query.
      }
    }

    return null;
  }

  String _stripDiacritics(String input) {
    const replacements = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n', 'ç': 'c',
      'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A', 'Ã': 'A', 'Å': 'A',
      'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
      'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
      'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O', 'Õ': 'O',
      'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
      'Ñ': 'N', 'Ç': 'C',
    };

    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(replacements[ch] ?? ch);
    }
    return buffer.toString();
  }

  List<String> _buildCustomLookupTerms(String text, List<String>? keywords) {
    final terms = <String>[];
    final seen = <String>{};

    void addTerm(String raw) {
      final normalized = _normalizeLookupKey(raw);
      if (normalized.isEmpty || seen.contains(normalized)) return;
      seen.add(normalized);
      terms.add(normalized);
    }

    addTerm(text);
    if (keywords != null) {
      for (final keyword in keywords) {
        addTerm(keyword);
      }
    }

    return terms;
  }

  List<String> _expandLocaleFallbackTerms(String raw, String? locale) {
    final normalized = _normalizeLookupKey(raw);
    if (normalized.isEmpty) return const [];

    final terms = <String>[];
    final seen = <String>{};

    void addTerm(String value) {
      final key = _normalizeLookupKey(value);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      terms.add(key);
    }

    var hasMappedFallback = false;

    if (locale != null && locale.toLowerCase().startsWith('es')) {
      final normalizedAscii = _stripDiacritics(normalized)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (normalizedAscii.isNotEmpty) {
        final directFallbacks = _spanishToEnglishFallbacks[normalizedAscii];
        if (directFallbacks != null) {
          hasMappedFallback = true;
          for (final fallback in directFallbacks) {
            addTerm(fallback);
          }
        }

        for (final token in normalizedAscii.split(' ')) {
          final tokenFallbacks = _spanishToEnglishFallbacks[token];
          if (tokenFallbacks != null) {
            hasMappedFallback = true;
            for (final fallback in tokenFallbacks) {
              addTerm(fallback);
            }
          }
        }
      }
    }

    // If we found a locale mapping (e.g. quiero -> want), avoid searching
    // source-language variants in the same request to keep lookups fast and
    // deterministic.
    if (!hasMappedFallback) {
      addTerm(normalized);
      addTerm(_stripDiacritics(normalized));
    }

    return terms;
  }

  List<String> _getLocaleMappedFallbackTerms(String raw, String? locale) {
    final normalized = _normalizeLookupKey(raw);
    if (normalized.isEmpty) return const [];
    if (locale == null || !locale.toLowerCase().startsWith('es')) return const [];

    final mapped = <String>[];
    final seen = <String>{};

    void addMapped(String value) {
      final key = _normalizeLookupKey(value);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      mapped.add(key);
    }

    final normalizedAscii = _stripDiacritics(normalized)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalizedAscii.isEmpty) return const [];

    final directFallbacks = _spanishToEnglishFallbacks[normalizedAscii];
    if (directFallbacks != null) {
      for (final fallback in directFallbacks) {
        addMapped(fallback);
      }
    }

    for (final token in normalizedAscii.split(' ')) {
      final tokenFallbacks = _spanishToEnglishFallbacks[token];
      if (tokenFallbacks != null) {
        for (final fallback in tokenFallbacks) {
          addMapped(fallback);
        }
      }
    }

    return mapped;
  }

  List<String> _collectLocaleMappedTerms(
    String text,
    List<String>? keywords,
    String? locale,
  ) {
    final mapped = <String>[];
    final seen = <String>{};

    void addMappedFrom(String raw) {
      final terms = _getLocaleMappedFallbackTerms(raw, locale);
      for (final term in terms) {
        final key = _normalizeLookupKey(term);
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        mapped.add(key);
      }
    }

    addMappedFrom(text);
    if (keywords != null) {
      for (final keyword in keywords) {
        addMappedFrom(keyword);
      }
    }

    void addLexiconFrom(String raw) {
      final terms = _getLocalizedLexiconTerms(raw, locale);
      for (final term in terms) {
        final key = _normalizeLookupKey(term);
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        mapped.add(key);
      }
    }

    addLexiconFrom(text);
    if (keywords != null) {
      for (final keyword in keywords) {
        addLexiconFrom(keyword);
      }
    }

    return mapped;
  }

  bool _looksEnglishLike(String value) {
    final normalized = _normalizeAsciiLookupKey(value);
    if (normalized.isEmpty) return false;
    return RegExp(r'^[a-z0-9\s]+$').hasMatch(normalized);
  }

  List<String> _collectNonEnglishCandidateTerms(
    String text,
    List<String>? keywords,
    String? locale,
  ) {
    final terms = <String>[];
    final seen = <String>{};

    void addTerm(String raw) {
      final normalized = _normalizeAsciiLookupKey(raw);
      if (normalized.isEmpty || seen.contains(normalized)) return;
      seen.add(normalized);
      terms.add(normalized);
    }

    for (final mapped in _collectLocaleMappedTerms(text, keywords, locale)) {
      addTerm(mapped);
    }

    if (keywords != null) {
      for (final keyword in keywords) {
        if (_looksEnglishLike(keyword)) {
          addTerm(keyword);
        }
      }
    }

    for (final variant in _buildSearchVariants(text)) {
      addTerm(variant);
    }

    return terms;
  }

  Future<void> _clearPersistedLookupCachesForProfileChange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pictogramCachePrefsKey);
      await prefs.remove(_fallbackUrlCachePrefsKey);
      await prefs.remove(_canonicalSearchCachePrefsKey);
      debugPrint('🔄 PictogramService: Cleared persisted lookup caches after profile switch');
    } catch (e) {
      debugPrint('⚠️ PictogramService: Failed to clear persisted caches on profile switch: $e');
    }
  }
  
  /// Set user context for custom images and clear caches if user changed
  void setUserContext({required String userId, required String idToken, String? mascot}) {
    final userChanged = _currentUserId != userId;
    final newMascot = (mascot != null && mascot.isNotEmpty) ? mascot : null;

    // When no mascot is explicitly provided and the user hasn't changed, preserve
    // the existing mascot. Button-level calls pass null/empty when settings haven't
    // loaded yet — without this guard they would overwrite the correct mascot that
    // was already set by the app-level call in app_loading_page.
    final effectiveMascot = (newMascot != null || userChanged) ? newMascot : _currentMascot;
    final mascotChanged = effectiveMascot != _currentMascot;

    _currentUserId = userId;
    _currentIdToken = idToken;
    _currentMascot = effectiveMascot;

    debugPrint('🔧 PictogramService: Set user context - userId: $userId mascot: $effectiveMascot');

    // Clear image cache when mascot changes so mascot-preferred images are fetched fresh.
    // Cache keys already include the mascot prefix, so this just evicts stale in-memory entries.
    if (mascotChanged && !userChanged) {
      debugPrint('🎭 PictogramService: Mascot changed to "$effectiveMascot", clearing image cache');
      _imageCache.clear();
      _customImageMatches.clear();
      _inFlightImageLookups.clear();
    }

    // Clear custom image cache when user changes to force fresh data
    if (userChanged) {
      debugPrint('🔄 PictogramService: User changed, clearing custom image cache for fresh data');
      CustomImageService.clearCache();
      _imageCache.clear();
      _fallbackTermUrlCache.clear();
      _canonicalSearchCache.clear();
      _inFlightImageLookups.clear();
      _skipButtonSearchUntilByKey.clear();
      _customImageMatches.clear();
      _customImages.clear();
      _customImagesPreloaded = false;
      _customImagesPreloadFuture = null;
      _profileImageUrl = null;
      _profileImageFetchedAt = null;
      _profileImageForUserId = null;
      _localLibraryTagIndex.clear();
      _localLibraryUrlTags.clear();
      _localLibraryUrlSubconcept.clear();
      _libraryLoaded = false;
      _libraryLoadFuture = null;
      unawaited(_initLocalLibrary());
      unawaited(_clearPersistedLookupCachesForProfileChange());
      // Warm custom image cache in the background for the new profile without
      // blocking button image lookup on first render.
      unawaited(preloadCustomImages(const <String>[]));
    }
  }

  /// True when a mascot is active, meaning mascot-specific images should be
  /// preferred over pre-assigned generic image URLs.
  bool get hasMascot => _currentMascot != null && _currentMascot!.isNotEmpty;

  bool _isPersonalPronounLookup(String text, List<String>? keywords) {
    const pronouns = {
      'i',
      'me',
      'my',
      'mine',
      'myself',
      // Common Spanish first-person forms for bilingual boards.
      'yo',
      'mi',
      'mio',
      'mia',
      'conmigo',
    };

    bool matches(String raw) => pronouns.contains(_normalizeLookupKey(raw));

    if (matches(text)) return true;
    if (keywords != null) {
      for (final keyword in keywords) {
        if (matches(keyword)) return true;
      }
    }
    return false;
  }

  bool _isProfileImageCacheValid() {
    if (_profileImageUrl == null || _profileImageUrl!.isEmpty) return false;
    if (_profileImageFetchedAt == null) return false;
    if (_profileImageForUserId == null || _profileImageForUserId != _currentUserId) {
      return false;
    }
    return DateTime.now().difference(_profileImageFetchedAt!) < _profileImageCacheTtl;
  }

  Future<String?> _fetchProfileImageUrl() async {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      return null;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final localPath = prefs.getString(
        '$_localProfileImagePathPrefix$_currentUserId',
      );
      if (localPath != null && localPath.isNotEmpty) {
        final localFile = File(localPath);
        if (await localFile.exists()) {
          return 'file://$localPath';
        }
      }
    } catch (_) {
      // Fall through to remote endpoint lookup.
    }

    if (_isProfileImageCacheValid()) {
      // If the cached URL points to a local file, verify it still exists.
      // If it was deleted (e.g. admin page switched to canonical server URL),
      // invalidate and fall through to re-fetch from the remote endpoint.
      if (_profileImageUrl!.startsWith('file://')) {
        try {
          final path = Uri.parse(_profileImageUrl!).toFilePath();
          if (!File(path).existsSync()) {
            _profileImageUrl = null;
            _profileImageFetchedAt = null;
            // fall through to remote endpoint lookup
          } else {
            return _profileImageUrl;
          }
        } catch (_) {
          _profileImageUrl = null;
          _profileImageFetchedAt = null;
        }
      } else {
        return _profileImageUrl;
      }
    }

    final refreshedToken = await AuthenticatedHttpClient.getRefreshedIdToken();
    final tokenToUse = (refreshedToken != null && refreshedToken.isNotEmpty)
      ? refreshedToken
        : _currentIdToken;

    if (tokenToUse == null || tokenToUse.isEmpty) {
      return null;
    }

    final response = await http.get(
      Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/get_profile_image'),
      headers: {
        'Authorization': 'Bearer $tokenToUse',
        'X-User-ID': _currentUserId!,
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 3));

    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final profileImage = data['profile_image'];
    if (profileImage is! Map<String, dynamic>) {
      return null;
    }

    final fallbackUrl = (profileImage['signed_image_url'] ??
        data['profileImageSignedUrl'] ??
        profileImage['image_url'])
      ?.toString()
      .trim();

    final resolvedUrl = await StorageImageUrlService.resolveImageUrl(
      storagePath: profileImage['storage_path']?.toString(),
      fallbackUrl: fallbackUrl,
      bucketName: '${EnvironmentConfig.projectId}-aac-images',
    );
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }

    _profileImageUrl = resolvedUrl;
    _profileImageFetchedAt = DateTime.now();
    _profileImageForUserId = _currentUserId;
    return resolvedUrl;
  }

  /// Get pictogram/image URL for a given text with sight word information
  /// Returns PictogramResult with image URL and sight word status
  /// [locale] is the user's BCP-47 locale (e.g. 'es-US'). When non-English,
  /// the search uses /api/symbols/button-search with the locale so the server
  /// can match against localized_tags in Firestore.
  Future<PictogramResult?> getPictogramResult(String text, {int? sightWordGradeLevel, bool enableSightWords = true, List<String>? keywords, bool shouldLogMissing = true, String? locale, bool webFastPath = false, bool cacheOnly = false}) async {
    debugPrint('🚨 PICTOGRAM SERVICE CALLED: text="$text", enablePictograms=$enablePictograms, shouldLogMissing=$shouldLogMissing, keywords=$keywords');
    
    // Preserve locale characters (e.g. bebé, aquí, niño).
    // Prior sanitization used ASCII-style \w and stripped accents, causing
    // terms like "bebé" -> "beb" and guaranteed misses.
    final originalText = text.trim();
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

    final imageUrl = await _getImageUrl(
      originalText,
      keywords: keywords,
      shouldLogMissing: shouldLogMissing,
      locale: locale,
      webFastPath: webFastPath,
      cacheOnly: cacheOnly,
    );
    final displayUrl = await _resolveDisplayImageUrl(
      imageUrl,
      cacheOnly: cacheOnly,
    );
    return PictogramResult(
      imageUrl: displayUrl,
      isSightWord: isSightWord,
      originalText: text,
    );
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

  /// Fetch image via /api/symbols/button-search (locale-aware, mirrors web app).
  /// Passes the display word + locale so the server can query localized_tags in
  /// Firestore (e.g. searching "agua" with locale "es-US" finds the water image).
  Future<String?> _fetchViaButtonSearch(String text, List<String>? keywords, String? locale) async {
    final baseUrl = EnvironmentConfig.apiBaseUrl;
    final encodedText = Uri.encodeComponent(text.trim());
    String url = '$baseUrl/api/symbols/button-search?q=$encodedText&limit=25';
    if (locale != null && locale.isNotEmpty) {
      url += '&locale=${Uri.encodeComponent(locale)}';
    }
    if (keywords != null && keywords.isNotEmpty) {
      url += '&keywords=${Uri.encodeComponent(jsonEncode(keywords))}';
    }
    if (_currentMascot != null) {
      url += '&mascot=${Uri.encodeComponent(_currentMascot!)}';
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_currentIdToken != null) {
      headers['Authorization'] = 'Bearer $_currentIdToken';
    }
    if (_currentUserId != null) {
      headers['X-User-ID'] = _currentUserId!;
    }

    try {
      debugPrint('🌐 PictogramService: button-search "$text" locale=$locale keywords=$keywords mascot=$_currentMascot url=$url');
      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        debugPrint(
          '🌐 PictogramService: button-search non-200 for "$text": ${response.statusCode}',
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['symbols'] is List) {
          final symbols = data['symbols'] as List;
          final queryNorm = _normalizeLookupKey(text);
          String? bestSubconceptUrl;
          String? bestTagUrl;

          // Three buckets for mascot-aware selection:
          //   mascotMatch  — symbol.mascot == _currentMascot (best)
          //   noMascot     — symbol.mascot is null/empty     (neutral fallback)
          //   (wrong mascot symbols are skipped entirely)
          // Without a mascot, use the original subconcept-preference logic.
          String? mascotMatchUrl;
          String? noMascotUrl;

          for (final raw in symbols) {
            if (raw is! Map) continue;
            final symbol = raw;
            final symbolUrl =
                symbol['url']?.toString() ??
                symbol['image_url']?.toString() ??
                symbol['imageUrl']?.toString();
            if (symbolUrl == null || symbolUrl.isEmpty) continue;

            // Validate the symbol's tags/subconcept safely match the query
            // to prevent suffix-wildcard false positives (e.g. ears -> bears).
            final symbolTags = (symbol['tags'] as List? ?? [])
                .map((t) => t.toString().toLowerCase().trim())
                .toList();
            final symbolSubconcept =
                (symbol['subconcept'] as String? ??
                        symbol['subcategory'] as String? ??
                        '')
                .toLowerCase()
                .trim()
                .replaceAll('_', ' ');
            final allTerms = [...symbolTags, if (symbolSubconcept.isNotEmpty) symbolSubconcept];

            final isMatch = allTerms.isEmpty ||
                allTerms.any((t) => _areSingularPluralEquivalent(queryNorm, t));

            if (!isMatch) {
              debugPrint(
                '🌐 PictogramService: ⚠️ button-search rejected "${symbol['name']}" for "$text" — tags $symbolTags do not safely match',
              );
              continue;
            }

            if (_currentMascot != null) {
              // Mascot-aware selection: bucket by mascot field, skip wrong mascots.
              final symbolMascot = (symbol['mascot'] as String? ?? '').toLowerCase().trim();
              if (symbolMascot == _currentMascot) {
                mascotMatchUrl ??= symbolUrl;
                debugPrint('🌐 PictogramService: ✅ mascot match "$_currentMascot" for "$text": $symbolUrl');
              } else if (symbolMascot.isEmpty) {
                noMascotUrl ??= symbolUrl;
                debugPrint('🌐 PictogramService: 📎 no-mascot fallback for "$text": $symbolUrl');
              } else {
                debugPrint('🌐 PictogramService: ⛔ wrong mascot "$symbolMascot" skipped for "$text"');
              }
              // Stop as soon as we have an exact mascot match.
              if (mascotMatchUrl != null) break;
            } else {
              final subconceptIsBest =
                  symbolSubconcept.isNotEmpty &&
                  _areSingularPluralEquivalent(queryNorm, symbolSubconcept);
              final tagsContainMatch = symbolTags.any(
                (tag) => _areSingularPluralEquivalent(queryNorm, tag),
              );

              if (subconceptIsBest && bestSubconceptUrl == null) {
                bestSubconceptUrl = symbolUrl;
                debugPrint(
                  '🌐 PictogramService: ✅ button-search prioritized subconcept match for "$text": $symbolUrl (subconcept="$symbolSubconcept")',
                );
              } else if (tagsContainMatch && bestTagUrl == null) {
                bestTagUrl = symbolUrl;
                debugPrint(
                  '🌐 PictogramService: ✅ button-search fallback tag match for "$text": $symbolUrl',
                );
              }
            }
          }

          // For mascot mode, prefer exact mascot match, then no-mascot generic.
          if (_currentMascot != null) {
            bestSubconceptUrl = mascotMatchUrl ?? noMascotUrl;
          }

          if (bestSubconceptUrl != null && bestSubconceptUrl.isNotEmpty) {
            return bestSubconceptUrl;
          }
          if (bestTagUrl != null && bestTagUrl.isNotEmpty) {
            return bestTagUrl;
          }
        }
      }
    } catch (e) {
      if (e is TimeoutException) {
        _markButtonSearchTimeout(text, locale: locale);
      }
      debugPrint('PictogramService: button-search error for "$text": $e');
    }
    return null;
  }

  /// Internal method to get image URL with custom images priority
  Future<String?> _getImageUrl(String text, {List<String>? keywords, bool shouldLogMissing = true, String? locale, bool webFastPath = false, bool cacheOnly = false}) async {
    final isNonEnglish = locale != null && !locale.startsWith('en');
    final cacheKey = _buildPrimaryCacheKey(text, locale: locale);
    final cacheKeyVariants = _buildCacheKeyVariants(text, locale: locale);
    debugPrint('🚨 _getImageUrl called with original: "$text" locale=$locale cacheKey="$cacheKey"');

    // Check cache first
    var removedStaleNull = false;
    for (final key in cacheKeyVariants) {
      if (_imageCache.containsKey(key)) {
        final cached = _imageCache[key];
        if (_isStaleLocalFileUrl(cached)) {
          _imageCache.remove(key);
          removedStaleNull = true;
          continue;
        }
        if (cached != null && cached.isNotEmpty) {
          // Evict URLs whose local library source tags do NOT safely match
          // the query — this catches stale wrong matches (e.g. ears->bears)
          // that were stored before matching rules were tightened.
          if (_libraryLoaded && !_libraryUrlMatchesQuery(cached, text)) {
            debugPrint(
              '🗑️ PictogramService: Evicting stale wrong cache entry for "$text": $cached',
            );
            _imageCache.remove(key);
            removedStaleNull = true;
            continue;
          }
          return cached;
        }

        // Null cache entries are often stale after backend/tag updates.
        // For non-English lookups, force a fresh lookup instead of returning null.
        if (isNonEnglish) {
          _imageCache.remove(key);
          removedStaleNull = true;
        } else {
          return null;
        }
      }
    }

    if (removedStaleNull) {
      await _saveCacheToPrefs();
    }

    final inFlightLookup = _inFlightImageLookups[cacheKey];
    if (inFlightLookup != null) {
      debugPrint('🔁 Reusing in-flight pictogram lookup for cacheKey="$cacheKey"');
      return await inFlightLookup;
    }

    final lookupFuture = () async {

    try {
      // PRIORITY 0: Personal pronouns should use the dedicated profile image.
      if (_isPersonalPronounLookup(text, keywords)) {
        try {
          final profileUrl = await _fetchProfileImageUrl();
          if (profileUrl != null && profileUrl.isNotEmpty) {
            for (final key in cacheKeyVariants) {
              _imageCache[key] = profileUrl;
            }
            await _saveCacheToPrefs();
            debugPrint(
              '👤 PictogramService: Using profile image for personal pronoun "$text"',
            );
            return profileUrl;
          }
        } catch (e) {
          debugPrint('PictogramService: profile image lookup error for "$text": $e');
        }
      }

      final localeCandidateTerms = isNonEnglish
          ? _collectNonEnglishCandidateTerms(text, keywords, locale)
          : const <String>[];

      // PRIORITY 1: Check preloaded custom images cache first
      final customLookupTerms = _buildCustomLookupTerms(text, keywords);
      if (_customImagesPreloaded) {
        for (final term in customLookupTerms) {
          if (_customImageMatches.containsKey(term)) {
            final customImageUrl = _customImageMatches[term]!;
            debugPrint('⚡ PictogramService: Using preloaded custom image for "$text" via "$term"');
            for (final key in cacheKeyVariants) {
              _imageCache[key] = customImageUrl;
            }
            await _saveCacheToPrefs();
            return customImageUrl;
          }
        }
      } else if (_currentUserId != null && _currentIdToken != null) {
        // Keep preload non-blocking for render latency: start once and continue.
        unawaited(preloadCustomImages(const <String>[]));
      }

      // PRIORITY 1.5: Check local library index cache (instant lookup).
      // Skip when mascot is active — the local library index has no mascot field,
      // so it returns whichever image was indexed first (which may be the wrong
      // mascot). Defer to button-search which does proper mascot-aware selection.
      if (_currentMascot == null) {
        if (!_libraryLoaded) {
          await _initLocalLibrary();
        }
        final localLibraryUrl = _searchLocalLibraryIndex(text, keywords: keywords);
        if (localLibraryUrl != null && localLibraryUrl.isNotEmpty) {
          debugPrint('📚 PictogramService: Found local library match for "$text": $localLibraryUrl');
          for (final key in cacheKeyVariants) {
            _imageCache[key] = localLibraryUrl;
          }
          await _saveCacheToPrefs();
          return localLibraryUrl;
        }
      }

      // Cache-only mode for first paint: avoid network-driven phased rendering.
      if (cacheOnly) {
        return null;
      }

      // PRIORITY 2: Web parity fast path.
      // The web app calls unified button-search first for tap words. Do the same
      // here so first-load matching is fast and consistent.
      var didTryButtonSearch = false;
      final buttonSearchCooldownExpiry = _getButtonSearchCooldownExpiry(
        text,
        locale: locale,
      );
      final shouldSkipButtonSearch = buttonSearchCooldownExpiry != null;
      if (shouldSkipButtonSearch) {
        debugPrint(
          '🌐 PictogramService: Skipping early button-search for "$text" due to timeout cooldown until $buttonSearchCooldownExpiry',
        );
      } else {
        didTryButtonSearch = true;
        final buttonSearchUrl = await _fetchViaButtonSearch(text, keywords, locale);
        if (buttonSearchUrl != null && buttonSearchUrl.isNotEmpty) {
          for (final key in cacheKeyVariants) {
            _imageCache[key] = buttonSearchUrl;
          }
          _fallbackTermUrlCache[_normalizeAsciiLookupKey(text)] = buttonSearchUrl;
          await _saveCacheToPrefs();
          return buttonSearchUrl;
        }
      }

      // Web app behavior for Tap grids is effectively cache/custom + button-search.
      // Skip deeper fallback chains to avoid phased, long-tail matching rounds.
      if (webFastPath) {
        return null;
      }

      // PRIORITY 3: Direct localized tag lookup in Firestore for non-English
      // terms before endpoint fallbacks. This avoids translation/conversion misses.
      if (isNonEnglish) {
        final localizedUrl = await _fetchViaLocalizedTags(text, locale);
        if (localizedUrl != null && localizedUrl.isNotEmpty) {
          for (final key in cacheKeyVariants) {
            _imageCache[key] = localizedUrl;
          }
          await _saveCacheToPrefs();
          return localizedUrl;
        }

        final directTerms = <String>[];
        final seenDirectTerms = <String>{};

        void addDirectTerm(String raw) {
          final normalized = _normalizeLookupKey(raw);
          if (normalized.isEmpty || seenDirectTerms.contains(normalized)) return;
          seenDirectTerms.add(normalized);
          directTerms.add(raw);
        }

        addDirectTerm(text);
        if (keywords != null) {
          for (final keyword in keywords) {
            addDirectTerm(keyword);
          }
        }
        for (final mapped in localeCandidateTerms) {
          addDirectTerm(mapped);
          if (directTerms.length >= 8) {
            break;
          }
        }

        final directAacUrl = await _fetchViaDirectAacTagsAndSubconcept(directTerms);
        if (directAacUrl != null && directAacUrl.isNotEmpty) {
          for (final key in cacheKeyVariants) {
            _imageCache[key] = directAacUrl;
          }
          await _saveCacheToPrefs();
          return directAacUrl;
        }
      }

      // PRIORITY 3.5: Fallback to individual custom image lookup (if user context available)
      // Keep this after non-English Firestore lookups so localized matches are not
      // blocked by slow custom-image network calls.
      if (_currentUserId != null && _currentIdToken != null) {
        try {
          if (text.length == 1) {
            debugPrint('🚨 PictogramService: SINGLE CHARACTER QUERY - "$text" (fallback lookup)');
          }

          final customTermsToTry = _customImagesPreloaded
              ? customLookupTerms
              : customLookupTerms.take(1);

          for (final term in customTermsToTry) {
            final customImage = await CustomImageService.findBestMatch(
              concept: term,
              idToken: _currentIdToken!,
              aacUserId: _currentUserId!,
              shouldLogMissing: shouldLogMissing,
            ).timeout(
              _customImagesPreloaded
                  ? const Duration(seconds: 2)
                  : const Duration(milliseconds: 700),
              onTimeout: () {
                debugPrint(
                  '⏱️ PictogramService: custom image lookup timeout for "$term"; continuing fallback chain',
                );
                return null;
              },
            );

            if (customImage != null) {
              if (term.length == 1 &&
                  !customImage.tags.any((tag) => tag.toLowerCase() == term)) {
                debugPrint(
                  '⚠️ PictogramService: FALSE POSITIVE - "$term" matched custom image with tags ${customImage.tags}',
                );
              }
              for (final key in cacheKeyVariants) {
                _imageCache[key] = customImage.imageUrl;
              }
              _customImageMatches[term] = customImage.imageUrl;
              await _saveCacheToPrefs();
              return customImage.imageUrl;
            }
          }
        } catch (customImageError) {
          // Continue to global library on error.
          debugPrint('PictogramService: custom image lookup error for "$text": $customImageError');
        }
      }

      // PRIORITY 4: locale-aware canonical term fallback after fast path.
      // When the user language is non-English, send the display word + locale
      // so the server can match against localized_tags in Firestore.
      // Also used for English with keywords for better keyword-based matching.
      final canonicalTerm = _canonicalSearchCache[cacheKey];
      if (isNonEnglish && canonicalTerm != null && canonicalTerm.isNotEmpty) {
        final canonicalUrl = await _fetchImageFromFirestoreFastTagOnly(canonicalTerm);
        if (canonicalUrl != null && canonicalUrl.isNotEmpty) {
          for (final key in cacheKeyVariants) {
            _imageCache[key] = canonicalUrl;
          }
          await _saveCacheToPrefs();
          return canonicalUrl;
        }
      }

      // PRIORITY 3A: For non-English locales, try mapped canonical terms first
      // (e.g. "por favor" -> "please") before any slower locale endpoint call.
      if (isNonEnglish && localeCandidateTerms.isNotEmpty) {
        debugPrint(
          '🔍 PictogramService: Trying non-English candidate terms first for "$text": $localeCandidateTerms',
        );
        for (final mappedTerm in localeCandidateTerms.take(3)) {
          final mappedUrl = await _fetchImageFromFirestoreFastTagOnly(mappedTerm);
          if (mappedUrl != null && mappedUrl.isNotEmpty) {
            debugPrint(
              '🔍 PictogramService: ✅ Locale mapped fast lookup found for "$text" via "$mappedTerm": $mappedUrl',
            );
            for (final key in cacheKeyVariants) {
              _imageCache[key] = mappedUrl;
            }
            _canonicalSearchCache[cacheKey] = mappedTerm;
            await _saveCacheToPrefs();
            return mappedUrl;
          }
        }
      }

      if (!didTryButtonSearch && ((keywords != null && keywords.isNotEmpty) || isNonEnglish)) {
        // Keep button-search enabled for Web parity (especially category/symbol
        // assignments that may exist only in symbols/button-search), but still
        // rely on timeout cooldown to prevent repeated stalls.
        if (shouldSkipButtonSearch) {
          debugPrint(
            '🌐 PictogramService: Skipping button-search for "$text" due to timeout cooldown for this term (until $buttonSearchCooldownExpiry)',
          );
        } else {
          final buttonSearchUrl = await _fetchViaButtonSearch(text, keywords, locale);
          if (buttonSearchUrl != null && buttonSearchUrl.isNotEmpty) {
            for (final key in cacheKeyVariants) {
              _imageCache[key] = buttonSearchUrl;
            }
            _fallbackTermUrlCache[_normalizeAsciiLookupKey(text)] = buttonSearchUrl;
            await _saveCacheToPrefs();
            return buttonSearchUrl;
          }
        }
      }

      // PRIORITY 4: Global Firestore library via imagecreator/search (English fallback).
      // For non-English locales, prefer localized lookup first, then fall back to
      // source/keyword terms when localized search misses (or auth is unavailable).
      if (isNonEnglish) {
        final fallbackTerms = <String>[];
        final seenFallbackTerms = <String>{};
        const maxFallbackTerms = 3;

        void addFallbackTerm(String raw) {
          if (fallbackTerms.length >= maxFallbackTerms) {
            return;
          }

          final expandedTerms = _expandLocaleFallbackTerms(raw, locale);
          for (final expanded in expandedTerms) {
            if (fallbackTerms.length >= maxFallbackTerms) {
              return;
            }
            if (expanded.isEmpty || seenFallbackTerms.contains(expanded)) {
              continue;
            }
            seenFallbackTerms.add(expanded);
            fallbackTerms.add(expanded);
          }
        }

        if (localeCandidateTerms.isNotEmpty) {
          for (final mapped in localeCandidateTerms) {
            if (fallbackTerms.length >= maxFallbackTerms) {
              break;
            }
            if (!seenFallbackTerms.contains(mapped)) {
              seenFallbackTerms.add(mapped);
              fallbackTerms.add(mapped);
            }
          }
        } else {
          // No direct locale mapping from source text: try source + limited keywords.
          addFallbackTerm(text);

          if (keywords != null && fallbackTerms.length < maxFallbackTerms) {
            for (final keyword in keywords) {
              if (fallbackTerms.length >= maxFallbackTerms) {
                break;
              }
              addFallbackTerm(keyword);
            }
          }
        }

        debugPrint('🔍 PictogramService: Non-English fallback terms for "$text": $fallbackTerms');

        for (final fallbackTerm in fallbackTerms) {
          final fallbackUrl = await _fetchImageFromFirestoreFastTagOnly(
            fallbackTerm,
          );
          if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
            debugPrint(
              '🔍 PictogramService: ✅ Non-English fallback found for "$text" via "$fallbackTerm": $fallbackUrl',
            );
            for (final key in cacheKeyVariants) {
              _imageCache[key] = fallbackUrl;
            }
            _canonicalSearchCache[cacheKey] = fallbackTerm;
            await _saveCacheToPrefs();
            return fallbackUrl;
          }
        }

        debugPrint(
          '🔍 PictogramService: Non-English lookup miss for "$text" locale="$locale" after localized + fallback search',
        );

        // Do not cache non-English misses; localized tags can be updated rapidly
        // and stale negative caches hide newly-added images.
        return null;
      }

      final imageUrl = await _fetchImageFromFirestore(text, keywords: keywords, shouldLogMissing: shouldLogMissing);

      if (imageUrl != null && imageUrl.isNotEmpty) {
        debugPrint('🔍 PictogramService: ✅ Found global image URL: $imageUrl');
        for (final key in cacheKeyVariants) {
          _imageCache[key] = imageUrl;
        }
        await _saveCacheToPrefs();
        return imageUrl;
      }

      debugPrint('🔍 PictogramService: ❌ No image found for "$cacheKey"');
      // Cache null in memory only — NOT persisted to SharedPreferences so it is
      // retried on the next app launch (avoids stale nulls blocking fresh lookups).
      // IMPORTANT: During preload (shouldLogMissing=false), don't cache misses.
      // Otherwise warmup can poison cache and block later visible lookups.
      if (!isNonEnglish && shouldLogMissing) {
        for (final key in cacheKeyVariants) {
          _imageCache[key] = null;
        }
      }
      return null;
      
    } catch (e) {
      return null;
    }
    }();

    _inFlightImageLookups[cacheKey] = lookupFuture;
    try {
      return await lookupFuture;
    } finally {
      if (identical(_inFlightImageLookups[cacheKey], lookupFuture)) {
        _inFlightImageLookups.remove(cacheKey);
      }
    }
  }

  /// Warm cache for currently visible buttons using bounded concurrency.
  /// This reduces per-button render latency and avoids duplicate network fan-out.
  Future<void> prefetchButtonPictograms({
    required List<String> words,
    Map<String, List<String>> keywordMap = const {},
    String? locale,
    int maxItems = 24,
    bool shouldLogMissing = false,
    bool webFastPath = false,
    bool warmDiskCache = false,
  }) async {
    if (words.isEmpty) return;

    // Ensure local library index is initialized
    if (!_libraryLoaded) {
      await _initLocalLibrary();
    }

    // Ensure custom images are preloaded before prefetching buttons, to prioritize custom images
    if (!_customImagesPreloaded && _currentUserId != null && _currentIdToken != null) {
      try {
        await preloadCustomImages(words);
      } catch (e) {
        debugPrint('❌ PictogramService: Error preloading custom images in prefetch: $e');
      }
    }

    final isNonEnglish = locale != null && !locale.startsWith('en');
    final uniqueWords = <String>[];
    final seen = <String>{};

    for (final raw in words) {
      final normalized = _normalizeLookupKey(raw);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      uniqueWords.add(raw);
      if (uniqueWords.length >= maxItems) break;
    }

    if (uniqueWords.isEmpty) return;

    final unresolvedWords = <String>[];

    for (final word in uniqueWords) {
      final cacheKeyVariants = _buildCacheKeyVariants(word, locale: locale);

      // Check in-memory cache first (use mascot-prefixed primary key when mascot is active)
      final prefetchCheckKey = _buildPrimaryCacheKey(word, locale: locale);
      if (_imageCache.containsKey(prefetchCheckKey) && _imageCache[prefetchCheckKey] != null) {
        continue;
      }

      // PRIORITY 0: Personal pronouns
      if (_isPersonalPronounLookup(word, keywordMap[word])) {
        final profileUrl = await _fetchProfileImageUrl();
        if (profileUrl != null && profileUrl.isNotEmpty) {
          for (final key in cacheKeyVariants) {
            _imageCache[key] = profileUrl;
          }
          continue;
        }
      }

      // PRIORITY 1: Check preloaded custom images
      var foundCustom = false;
      final customLookupTerms = _buildCustomLookupTerms(word, keywordMap[word]);
      if (_customImagesPreloaded) {
        for (final term in customLookupTerms) {
          if (_customImageMatches.containsKey(term)) {
            final customImageUrl = _customImageMatches[term]!;
            for (final key in cacheKeyVariants) {
              _imageCache[key] = customImageUrl;
            }
            foundCustom = true;
            break;
          }
        }
      }
      if (foundCustom) continue;

      // PRIORITY 2: Check local library index lookup.
      // Skip when mascot is active — local library has no mascot metadata, so it
      // may return a wrong-mascot image. Button-search handles mascot selection.
      if (_currentMascot == null) {
        final localUrl = _searchLocalLibraryIndex(word, keywords: keywordMap[word]);
        if (localUrl != null && localUrl.isNotEmpty) {
          for (final key in cacheKeyVariants) {
            _imageCache[key] = localUrl;
          }
          continue;
        }
      }

      // If we couldn't resolve locally, add to list for remote batch search
      unresolvedWords.add(word);
    }

    // Now batch-search any remaining unresolved words remotely
    if (unresolvedWords.isNotEmpty) {
      try {
        final batchResults = await batchSearchRemoteSymbols(unresolvedWords);
        for (final word in unresolvedWords) {
          final imageUrl = batchResults[word];
          final cacheKeyVariants = _buildCacheKeyVariants(word, locale: locale);
          
          for (final key in cacheKeyVariants) {
            _imageCache[key] = imageUrl; // Can be null if not found, to cache misses
          }
        }
        await _saveCacheToPrefs();
      } catch (e) {
        debugPrint('❌ PictogramService: Error in batch prefetching: $e');
      }
    }

    // Optionally warm disk cache for resolved URLs in the background
    if (warmDiskCache) {
      final urlsToWarm = <String>[];
      for (final word in uniqueWords) {
        final normalized = _normalizeLookupKey(word);
        final cacheKey = isNonEnglish ? '${locale.toLowerCase()}:$normalized' : normalized;
        final url = _imageCache[cacheKey];
        if (url != null && url.startsWith('http')) {
          urlsToWarm.add(url);
        }
      }
      if (urlsToWarm.isNotEmpty) {
        unawaited(warmDiskCacheForImageUrls(imageUrls: urlsToWarm));
      }
    }
  }

  /// Warm local disk cache for a set of remote image URLs.
  /// Returns the number of URLs that were confirmed on disk during this pass.
  Future<int> warmDiskCacheForImageUrls({
    required List<String> imageUrls,
    int maxItems = 200,
    int maxConcurrent = 8,
  }) async {
    if (imageUrls.isEmpty) return 0;

    final uniqueUrls = <String>[];
    final seen = <String>{};
    for (final raw in imageUrls) {
      final normalized = raw.trim();
      if (!normalized.startsWith('http')) continue;
      if (seen.contains(normalized)) continue;
      seen.add(normalized);
      uniqueUrls.add(normalized);
      if (uniqueUrls.length >= maxItems) break;
    }

    if (uniqueUrls.isEmpty) return 0;

    int cursor = 0;
    int warmed = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor;
        if (index >= uniqueUrls.length) return;
        cursor += 1;

        final remoteUrl = uniqueUrls[index];
        final mappedLocal = _getLocalFileUrlForRemote(remoteUrl);
        if (mappedLocal != null) {
          warmed += 1;
          continue;
        }

        try {
          final cachedInfo = await DefaultCacheManager().getFileFromCache(
            remoteUrl,
          );
          if (cachedInfo != null && cachedInfo.file.existsSync()) {
            _rememberLocalFileForRemote(remoteUrl, cachedInfo.file.path);
            warmed += 1;
            continue;
          }
        } catch (_) {
          // Continue to active download attempt.
        }

        try {
          final cachedFile = await DefaultCacheManager().getSingleFile(
            remoteUrl,
          );
          if (cachedFile.existsSync()) {
            _rememberLocalFileForRemote(remoteUrl, cachedFile.path);
            warmed += 1;
          }
        } catch (e) {
          debugPrint(
            'PictogramService: warmDiskCacheForImageUrls failed for "$remoteUrl": $e',
          );
        }
      }
    }

    final workers = <Future<void>>[];
    final workerCount = maxConcurrent < 1 ? 1 : maxConcurrent;
    for (int i = 0; i < workerCount; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);

    return warmed;
  }

  /// Warm disk cache for image URLs already present in in-memory lookup cache.
  /// This avoids additional matching/network lookup logic while still caching files.
  Future<int> warmDiskCacheForExistingCachedUrls({
    int maxItems = 400,
    int maxConcurrent = 8,
  }) async {
    final urls = <String>[];
    final seen = <String>{};

    for (final url in _imageCache.values) {
      final normalized = (url ?? '').trim();
      if (!normalized.startsWith('http')) continue;
      if (seen.contains(normalized)) continue;
      seen.add(normalized);
      urls.add(normalized);
      if (urls.length >= maxItems) break;
    }

    if (urls.isEmpty) return 0;

    return warmDiskCacheForImageUrls(
      imageUrls: urls,
      maxItems: maxItems,
      maxConcurrent: maxConcurrent,
    );
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
    final bool originalIsSingleWord = !originalIsMultiWord;
    final bool optimizedIsMultiWord = searchText.contains(' ');

    // For single-word buttons (e.g. "bad") where optimization expands to a
    // slower multi-word phrase (e.g. "thumbs down"), always try the original
    // single word first. This mirrors expected Tap Words behavior and avoids
    // timing out on the expanded phrase before the literal term is attempted.
    if (originalIsSingleWord && optimizedIsDifferent && optimizedIsMultiWord) {
      final originalFirstResult = await _trySearchWithTermSilent(text, baseUrl);
      if (originalFirstResult != null && originalFirstResult.isNotEmpty) {
        _imageCache[text.toLowerCase().trim()] = originalFirstResult;
        await _saveCacheToPrefs();
        return originalFirstResult;
      }
    }
    
    if (!shouldLogMissing && originalIsMultiWord && optimizedIsDifferent) {
      // Try original multi-word text FIRST — server does partial word matching internally
      debugPrint('🚨 SMART ORDER: shouldLogMissing=false, trying original multi-word text FIRST: "$text"');
      
      final images = await _trySearchWithTermRaw(text, baseUrl);
      if (images.isNotEmpty) {
        debugPrint('🚨 ✅ FOUND ${images.length} candidates for original text: "$text"');
        final bestImage = _selectBestImageMatch(images, text);
        final bestScore = bestImage['priorityScore'] as int? ?? 0;
        final imageUrl = bestImage['image_url'] as String?;
        
        if (imageUrl != null && bestScore > 0) {
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
          final bestScore = bestImage['priorityScore'] as int? ?? 0;
          final imageUrl = bestImage['image_url'] as String?;
          if (imageUrl != null && bestScore > 0) {
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

  /// Fast path for locale fallback terms: one tag-based API call, no extra strategy rounds.
  Future<String?> _fetchImageFromFirestoreFastTagOnly(String text) async {
    final baseUrl = EnvironmentConfig.apiBaseUrl;
    final normalizedTerm = _normalizeAsciiLookupKey(text);
    if (normalizedTerm.isEmpty) {
      return null;
    }

    if (_fallbackTermUrlCache.containsKey(normalizedTerm)) {
      return _fallbackTermUrlCache[normalizedTerm];
    }

    final termVariants = _buildSearchVariants(text);
    final fields = ['tag', 'subconcept', 'concept'];

    for (final termVariant in termVariants.take(2)) {
      final encodedTerm = Uri.encodeComponent(termVariant);
      for (final field in fields) {
        final strategyName = '$field:$termVariant';
        final strategyUrl =
            '$baseUrl/api/imagecreator/search?$field=$encodedTerm&limit=1&log_missing=false';

        try {
          debugPrint('🔍 FAST ${field.toUpperCase()} SEARCH: "$termVariant" -> $strategyUrl');
          final response = await http.get(
            Uri.parse(strategyUrl),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 3));

          if (response.statusCode != 200) {
            continue;
          }

          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic> && data['images'] is List) {
            final images = data['images'] as List;
            if (images.isNotEmpty && images.first is Map<String, dynamic>) {
              final first = images.first as Map<String, dynamic>;
              final imageUrl =
                  first['image_url']?.toString() ??
                  first['url']?.toString() ??
                  first['imageUrl']?.toString();
              if (imageUrl != null && imageUrl.isNotEmpty) {
                _fallbackTermUrlCache[normalizedTerm] = imageUrl;
                debugPrint(
                  '✅ FAST ${field.toUpperCase()} HIT: "$termVariant" -> $imageUrl',
                );
                return imageUrl;
              }
              debugPrint(
                '⚠️ FAST ${field.toUpperCase()} had images but no URL key for "$termVariant"; keys=${first.keys.toList()}',
              );
            }
          } else {
            debugPrint(
              '⚠️ FAST ${field.toUpperCase()} unexpected payload for "$termVariant": $data',
            );
          }
        } catch (e) {
          debugPrint('PictogramService: fast $strategyName search error for "$normalizedTerm": $e');
        }
      }
    }

    return null;
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
  bool _areSingularPluralEquivalent(String a, String b) {
    final first = a.toLowerCase().trim();
    final second = b.toLowerCase().trim();
    if (first.isEmpty || second.isEmpty) return false;
    if (first == second) return true;

    String singularize(String word) {
      if (word.length <= 2) return word;
      if (word.endsWith('ies') && word.length > 3) {
        return '${word.substring(0, word.length - 3)}y';
      }
      if (word.endsWith('es') && word.length > 3) {
        final stem = word.substring(0, word.length - 2);
        if (stem.endsWith('s') ||
            stem.endsWith('x') ||
            stem.endsWith('z') ||
            stem.endsWith('ch') ||
            stem.endsWith('sh')) {
          return stem;
        }
      }
      if (word.endsWith('s') && !word.endsWith('ss') && word.length > 2) {
        return word.substring(0, word.length - 1);
      }
      return word;
    }

    return singularize(first) == singularize(second);
  }

  bool _isSafePrefixOrPluralMatch(String searchTerm, String candidate) {
    final search = searchTerm.toLowerCase().trim();
    final term = candidate.toLowerCase().trim();
    if (search.isEmpty || term.isEmpty) return false;

    // Exact and singular/plural matches are always allowed.
    if (search == term || _areSingularPluralEquivalent(search, term)) {
      return true;
    }

    // Prefix-only partials prevent suffix wildcard behavior (e.g., ears -> bears).
    return term.startsWith(search) || search.startsWith(term);
  }

  Map<String, dynamic> _selectBestImageMatch(List<dynamic> images, String searchTerm) {
    final searchTermLower = searchTerm.toLowerCase().trim();
    final isNumericLedPhrase = RegExp(r'^\d+\s+').hasMatch(searchTermLower);
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
      final subconceptIsNumericOnly = RegExp(r'^\d+$').hasMatch(subconceptNormalized);
      
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
        if (!(isNumericLedPhrase && subconceptIsNumericOnly) &&
            _isSafePrefixOrPluralMatch(searchTermLower, subconcept)) {
          subconceptScore = 300;
          subconceptReason = 'Subconcept safe prefix/plural match';
        } else if (!(isNumericLedPhrase && subconceptIsNumericOnly) &&
            _isSafePrefixOrPluralMatch(subconcept, searchTermLower)) {
          subconceptScore = 100;
          // Bonus for matching end of search term (head of compound)
          if (searchTermLower.endsWith(subconcept) && !genericEndings.contains(subconcept)) {
            subconceptScore += 200; // Boost to 300 to compete with tags
          } else if (searchTermLower.startsWith(subconcept)) {
            subconceptScore += 20; // Slight boost for start match
          }
          subconceptReason = 'Search term safe prefix/plural match';
        }
        
        int tagScore = 0;
        String tagReason = '';
        
        // Check tags for partial matches
        for (int i = 0; i < tags.length && i < 5; i++) {
          final tag = tags[i].toString().toLowerCase().trim();
          final tagIsNumericOnly = RegExp(r'^\d+$').hasMatch(tag);
          if (tag.isNotEmpty) {
            if (!(isNumericLedPhrase && tagIsNumericOnly) &&
                (_isSafePrefixOrPluralMatch(searchTermLower, tag) ||
                    _isSafePrefixOrPluralMatch(tag, searchTermLower))) {
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
  Future<String?> _trySearchWithTermSilent(
    String searchTerm,
    String baseUrl, {
    bool allowVariantRetry = true,
  }) async {
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
            final bestScore = bestImage['priorityScore'] as int? ?? 0;
            final imageUrl = bestImage['image_url'] as String?;
            final imageName = bestImage['name'] as String? ?? 'unknown';
            final subconcept = bestImage['subconcept'] as String? ?? '';
            final tags = bestImage['tags'] as List? ?? [];
            
            if (imageUrl != null && bestScore > 0) {
              debugPrint('🔍 ✅ Best match selected by frontend prioritization for "$searchTerm": $imageName');
              debugPrint('🔍 Image details: subconcept="$subconcept", tags=$tags');
              debugPrint('🔍 *** FRONTEND PRIORITIZATION COMPLETE - SELECTED IMAGE URL: $imageUrl ***');
              debugPrint('PictogramService: ✅ Comprehensive search found image URL for "$searchTerm": $imageUrl');
              debugPrint('🔍 RETURNING URL: $imageUrl');
              return imageUrl;
            }
            debugPrint('🔍 ⚠️ Best candidate score was 0 for "$searchTerm"; skipping URL return to avoid bad match');
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
              final bestScore = bestImage['priorityScore'] as int? ?? 0;
              final imageUrl = bestImage['image_url'] as String?;
              final imageName = bestImage['name'] as String? ?? 'unknown';
              if (imageUrl != null && bestScore > 0) {
                debugPrint('🔍 ✅ Silent search found image for "$searchTerm": $imageName');
                debugPrint('PictogramService: ✅ Silent search found image URL for "$searchTerm" using $strategyName: $imageUrl');
                debugPrint('🔍 *** FALLBACK PRIORITIZATION COMPLETE - SELECTED IMAGE URL: $imageUrl ***');
                debugPrint('🔍 RETURNING URL: $imageUrl');
                return imageUrl; // Return immediately on first success
              }
              debugPrint('🔍 ⚠️ Silent search best candidate score was 0 for "$searchTerm"; trying next strategy');
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
    
    if (allowVariantRetry) {
      final stripped = _stripDiacritics(searchTerm);
      if (stripped != searchTerm) {
        debugPrint(
          '🔍 PictogramService: Retrying silent search with de-accented variant "$stripped" for "$searchTerm"',
        );
        final variantResult = await _trySearchWithTermSilent(
          stripped,
          baseUrl,
          allowVariantRetry: false,
        );
        if (variantResult != null) {
          return variantResult;
        }
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
      ).timeout(const Duration(seconds: 7));
      
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

    // Preserve full phrase for number-led labels (e.g. "5 little monkeys").
    // Truncating these tends to over-match generic number symbols.
    if (RegExp(r'^\s*\d+\s+').hasMatch(summary)) {
      final preserved = summary.trim();
      debugPrint('🚨 ✅ PRESERVING NUMBER-LED PHRASE: "$preserved"');
      return preserved;
    }
    
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
    
    final questionWords = [
      'what', 'who', 'where', 'when', 'why', 'how',
      'que', 'qué', 'quien', 'quién', 'donde', 'dónde',
      'cuando', 'cuándo', 'como', 'cómo', 'porque', 'porqué'
    ];
    final words = summary.toLowerCase().trim().split(RegExp(r'\s+'));
    
    // Common action verbs that should be deprioritized in favor of objects/subjects
    final commonActionVerbs = [
      'watch', 'see', 'look', 'view', 'observe', 'listen', 'hear', 'play', 'do', 'make', 'get', 'go', 'come',
      'eat', 'drink', 'read', 'write', 'talk', 'speak', 'say', 'tell', 'ask', 'answer', 'call', 'walk',
      'run', 'sit', 'stand', 'work', 'study', 'learn', 'teach', 'help', 'use', 'try', 'want', 'need',
      'like', 'love', 'hate', 'think', 'know', 'understand', 'feel', 'take', 'give', 'put', 'find',
      'buy', 'sell', 'pay', 'spend', 'save', 'open', 'close', 'start', 'stop', 'finish', 'continue',
      'quiero', 'querer', 'quiere', 'queremos', 'quieres',
      'necesito', 'necesitar', 'necesita', 'necesitamos',
      'gusta', 'gustar', 'quiero', 'tengo', 'tener',
      'como', 'comer', 'bebo', 'beber', 'voy', 'ir', 'vengo', 'venir',
      'dame', 'dar', 'haz', 'hacer', 'puedo', 'poder', 'debo', 'deber'
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
      'they', 'them', 'their', 'theirs', 'themselves',
      'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas',
      'yo', 'tu', 'tú', 'mi', 'mis', 'mio', 'mía', 'mio', 'mios', 'mias',
      'me', 'te', 'se', 'nos', 'le', 'les', 'lo', 'su', 'sus',
      'de', 'del', 'al', 'en', 'con', 'para', 'por', 'y', 'o', 'que', 'qué'
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
             final normalizedKeyword = _stripDiacritics(cleanKeyword);
          return cleanKeyword.length > 2 && 
               !questionAndFillerWords.contains(cleanKeyword) &&
               !questionAndFillerWords.contains(normalizedKeyword) &&
               !genericTerms.contains(cleanKeyword) &&
               !genericTerms.contains(normalizedKeyword) &&
               !commonActionVerbs.contains(cleanKeyword) &&
               !commonActionVerbs.contains(normalizedKeyword);
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
             final normalizedKeyword = _stripDiacritics(cleanKeyword);
          return cleanKeyword.length > 2 && 
               !questionAndFillerWords.contains(cleanKeyword) &&
               !questionAndFillerWords.contains(normalizedKeyword) &&
               !genericTerms.contains(cleanKeyword) &&
               !genericTerms.contains(normalizedKeyword);
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
      final word = _stripDiacritics(words[i]).replaceAll(RegExp(r'[^\w]'), ''); // Remove punctuation while preserving letters
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

  Future<void> _persistCacheToPrefsNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = jsonEncode(_imageCache);
      await prefs.setString(_pictogramCachePrefsKey, cacheJson);
      await prefs.setString(
        _fallbackUrlCachePrefsKey,
        jsonEncode(_fallbackTermUrlCache),
      );
      await prefs.setString(
        _canonicalSearchCachePrefsKey,
        jsonEncode(_canonicalSearchCache),
      );
      await prefs.setString(
        _remoteFilePathCachePrefsKey,
        jsonEncode(_remoteFilePathCache),
      );
    } catch (e) {
      debugPrint('Error saving pictogram cache: $e');
    }
  }

  Future<void> _flushQueuedCachePersist() async {
    if (_cachePersistInFlight || !_cachePersistQueued) {
      return;
    }

    _cachePersistQueued = false;
    _cachePersistInFlight = true;
    try {
      await _persistCacheToPrefsNow();
    } finally {
      _cachePersistInFlight = false;
      if (_cachePersistQueued) {
        unawaited(_flushQueuedCachePersist());
      }
    }
  }

  /// Queue cache persistence (debounced) so UI lookups are not blocked by disk writes.
  Future<void> _saveCacheToPrefs() async {
    _cachePersistQueued = true;
    _cachePersistDebounceTimer?.cancel();
    _cachePersistDebounceTimer = Timer(
      _cachePersistDebounceDelay,
      () => unawaited(_flushQueuedCachePersist()),
    );
  }

  /// Load cache from SharedPreferences (global shared library)
  Future<void> loadCacheFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_pictogramCachePrefsKey);
      final fallbackUrlCacheJson = prefs.getString(_fallbackUrlCachePrefsKey);
      final canonicalCacheJson = prefs.getString(_canonicalSearchCachePrefsKey);
      final remoteFileCacheJson = prefs.getString(_remoteFilePathCachePrefsKey);
      final cachedEnvironment = prefs.getString(_pictogramEnvPrefsKey);
      final cachedMatchingVersion = prefs.getString(_pictogramCacheVersionPrefsKey);
      final currentEnvironment = EnvironmentConfig.environmentName;
      
      debugPrint('🔧 PictogramService: Loading global image cache (user: $_currentUserId)');
      debugPrint('🔧 PictogramService: Current environment: $currentEnvironment, Cached environment: $cachedEnvironment');

      // Clear cache when match-ranking logic changes so stale URL choices
      // (for example, old tag-priority picks) do not persist indefinitely.
      if (cachedMatchingVersion != _currentPictogramCacheVersion) {
        debugPrint(
          '⚠️ PictogramService: Cache version changed from $cachedMatchingVersion to $_currentPictogramCacheVersion - clearing cache',
        );
        _imageCache.clear();
        _fallbackTermUrlCache.clear();
        _canonicalSearchCache.clear();
        await prefs.remove(_pictogramCachePrefsKey);
        await prefs.remove(_fallbackUrlCachePrefsKey);
        await prefs.remove(_canonicalSearchCachePrefsKey);
        await prefs.remove(_remoteFilePathCachePrefsKey);
        await prefs.setString(
          _pictogramCacheVersionPrefsKey,
          _currentPictogramCacheVersion,
        );
      }
      
      // Clear cache if environment changed
      if (cachedEnvironment != null && cachedEnvironment != currentEnvironment) {
        debugPrint('⚠️ PictogramService: Environment changed from $cachedEnvironment to $currentEnvironment - clearing cache');
        _imageCache.clear();
        _fallbackTermUrlCache.clear();
        _canonicalSearchCache.clear();
        await prefs.remove(_pictogramCachePrefsKey);
        await prefs.remove(_fallbackUrlCachePrefsKey);
        await prefs.remove(_canonicalSearchCachePrefsKey);
        await prefs.remove(_remoteFilePathCachePrefsKey);
        await prefs.setString(_pictogramEnvPrefsKey, currentEnvironment);
        return;
      }
      
      if (cacheJson != null) {
        final Map<String, dynamic> decodedCache = jsonDecode(cacheJson);
        _imageCache.clear();
        decodedCache.forEach((key, value) {
          final cachedUrl = value?.toString();
          if (_isStaleLocalFileUrl(cachedUrl)) {
            return;
          }
          _imageCache[key] = cachedUrl;
        });
        debugPrint('🔧 PictogramService: Loaded ${_imageCache.length} cached items from global library');
      } else {
        debugPrint('🔧 PictogramService: No cached items found in global library');
      }

      if (fallbackUrlCacheJson != null) {
        final Map<String, dynamic> decodedFallback = jsonDecode(fallbackUrlCacheJson);
        _fallbackTermUrlCache.clear();
        decodedFallback.forEach((key, value) {
          final url = value?.toString();
          if (url != null && url.isNotEmpty) {
            _fallbackTermUrlCache[key] = url;
          }
        });
      }

      if (canonicalCacheJson != null) {
        final Map<String, dynamic> decodedCanonical = jsonDecode(canonicalCacheJson);
        _canonicalSearchCache.clear();
        decodedCanonical.forEach((key, value) {
          final term = value?.toString();
          if (term != null && term.isNotEmpty) {
            _canonicalSearchCache[key] = term;
          }
        });
      }

      if (remoteFileCacheJson != null) {
        final Map<String, dynamic> decodedRemoteFileCache = jsonDecode(
          remoteFileCacheJson,
        );
        _remoteFilePathCache.clear();
        decodedRemoteFileCache.forEach((key, value) {
          final remoteUrl = key.trim();
          final localPath = value?.toString().trim();
          if (remoteUrl.isEmpty || localPath == null || localPath.isEmpty) {
            return;
          }
          final localFile = File(localPath);
          if (localFile.existsSync()) {
            _remoteFilePathCache[remoteUrl] = localPath;
          }
        });
      }
      
      // Store current environment
      await prefs.setString(_pictogramEnvPrefsKey, currentEnvironment);
      await prefs.setString(
        _pictogramCacheVersionPrefsKey,
        _currentPictogramCacheVersion,
      );
      
      // Initialize local symbol library cache
      unawaited(_initLocalLibrary());
    } catch (e) {
      debugPrint('Error loading pictogram cache: $e');
    }
  }

  /// Clear the image cache
  Future<void> clearCache() async {
    _imageCache.clear();
    _fallbackTermUrlCache.clear();
    _canonicalSearchCache.clear();
    _inFlightImageLookups.clear();
    _skipButtonSearchUntilByKey.clear();
    _customImageMatches.clear();
    _customImages.clear();
    _remoteFilePathCache.clear();
    _customImagesPreloaded = false;
    _customImagesPreloadFuture = null;
    _profileImageUrl = null;
    _profileImageFetchedAt = null;
    _profileImageForUserId = null;
    CustomImageService.clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pictogramCachePrefsKey);
      await prefs.remove(_fallbackUrlCachePrefsKey);
      await prefs.remove(_canonicalSearchCachePrefsKey);
      await prefs.remove(_remoteFilePathCachePrefsKey);
      debugPrint('🔄 PictogramService: Cache cleared - all cached images removed');
    } catch (e) {
      debugPrint('Error clearing pictogram cache: $e');
    }
  }
  
  /// Clears only the profile-image-related caches (personal-pronoun entries and
  /// the in-memory _profileImageUrl). Use this when the local profile image file
  /// is deleted so the next pronoun lookup fetches a fresh URL from the server.
  void clearProfileImageCache() {
    _profileImageUrl = null;
    _profileImageFetchedAt = null;
    _profileImageForUserId = null;
    const pronounCacheKeys = {
      'i', 'me', 'my', 'mine', 'myself',
      'yo', 'mi', 'mio', 'mia', 'conmigo',
    };
    for (final key in pronounCacheKeys) {
      _imageCache.remove(key);
    }
    debugPrint('🔄 PictogramService: Profile image cache cleared');
  }

  /// Remove a single entry from the in-memory cache (allows re-lookup with updated keywords).
  void clearCacheEntry(String cacheKey) {
    _imageCache.remove(cacheKey);
  }

  /// Remove all null entries from both in-memory and SharedPreferences caches.
  /// Call this when entering the Tap page to force a fresh lookup for any word
  /// that previously returned no image (stale negatives from old search logic).
  Future<void> clearNullCacheEntries() async {
    final nullKeys = _imageCache.entries
        .where((e) => e.value == null)
        .map((e) => e.key)
        .toList();
    for (final key in nullKeys) {
      _imageCache.remove(key);
    }
    if (nullKeys.isNotEmpty) {
      debugPrint('🔄 PictogramService: Cleared ${nullKeys.length} null cache entries');
      await _saveCacheToPrefs();
    }
  }

  Future<void> _initLocalLibrary() async {
    if (_libraryLoaded) return;
    final existingFuture = _libraryLoadFuture;
    if (existingFuture != null) {
      await existingFuture;
      return;
    }

    final loadFuture = () async {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_libraryFilename');
        
        final prefs = await SharedPreferences.getInstance();
        final lastDownloadTimeMs = prefs.getInt(_libraryTimestampPrefsKey) ?? 0;
        final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

        if (file.existsSync() && lastDownloadTimeMs > oneDayAgo) {
          debugPrint('📚 PictogramService: Loading local symbol library from cache file');
          final jsonString = await file.readAsString();
          _parseLibraryJson(jsonString);
          _libraryLoaded = true;
          return;
        }

        // Either file doesn't exist or is older than 24 hours. Download a fresh copy.
        debugPrint('📚 PictogramService: Symbol library missing or older than 24h. Fetching fresh copy...');
        unawaited(_downloadAndSaveLibrary(file, prefs));
        
        // If the file does exist (even if old), load it as a fallback until the new download completes
        if (file.existsSync()) {
          debugPrint('📚 PictogramService: Loading stale local symbol library as temporary fallback');
          final jsonString = await file.readAsString();
          _parseLibraryJson(jsonString);
          _libraryLoaded = true;
        }
      } catch (e) {
        debugPrint('❌ PictogramService: Error initializing local library: $e');
      }
    }();

    _libraryLoadFuture = loadFuture;
    try {
      await loadFuture;
    } finally {
      if (identical(_libraryLoadFuture, loadFuture)) {
        _libraryLoadFuture = null;
      }
    }
  }

  void _parseLibraryJson(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map && decoded['images'] is List) {
        final images = decoded['images'] as List;
        _localLibraryTagIndex.clear();
        _localLibraryUrlTags.clear();
        _localLibraryUrlSubconcept.clear();
        for (final img in images) {
          if (img is Map) {
            final url = img['image_url']?.toString();
            if (url == null || url.isEmpty) continue;
            final normalizedTags = <String>[];

            final tags = img['tags'];
            if (tags is List) {
              for (final tag in tags) {
                if (tag is String) {
                  final normalizedTag = tag.toLowerCase().trim();
                  if (normalizedTag.isNotEmpty) {
                    // We map the tag to the first image URL that has it (replicates web app priority)
                    _localLibraryTagIndex.putIfAbsent(normalizedTag, () => url);
                    normalizedTags.add(normalizedTag);
                  }
                }
              }
            }

            // Always index canonical fields even if no tags are present.
            final subconceptRaw =
                img['subconcept']?.toString() ??
                img['subcategory']?.toString() ??
                '';
            final subconcept = subconceptRaw.toLowerCase().trim();
            if (subconcept.isNotEmpty) {
              final normalizedSubconcept = subconcept.replaceAll('_', ' ');
              _localLibraryUrlSubconcept[url] = normalizedSubconcept;
              normalizedTags.add(subconcept);
              normalizedTags.add(normalizedSubconcept);
            }

            if (normalizedTags.isNotEmpty) {
              _localLibraryUrlTags[url] = normalizedTags;
            }
          }
        }
        debugPrint('📚 PictogramService: Successfully indexed ${_localLibraryTagIndex.length} tags from local library');
      }
    } catch (e) {
      debugPrint('❌ PictogramService: Error parsing library JSON: $e');
    }
  }

  Future<void> _downloadAndSaveLibrary(File file, SharedPreferences prefs) async {
    try {
      final refreshedToken = await AuthenticatedHttpClient.getRefreshedIdToken();
      final tokenToUse = (refreshedToken != null && refreshedToken.isNotEmpty)
          ? refreshedToken
          : _currentIdToken;

      if (tokenToUse == null || tokenToUse.isEmpty) {
        debugPrint('📭 PictogramService: No token available to download library');
        return;
      }

      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/symbols/library-download'),
        headers: {
          'Authorization': 'Bearer $tokenToUse',
          'X-User-ID': _currentUserId ?? '',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await file.writeAsString(response.body);
        await prefs.setInt(_libraryTimestampPrefsKey, DateTime.now().millisecondsSinceEpoch);
        debugPrint('📚 PictogramService: Downloaded and saved new symbol library');
        _parseLibraryJson(response.body);
        _libraryLoaded = true;
      } else {
        debugPrint('❌ PictogramService: Failed to download symbol library: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ PictogramService: Error downloading symbol library: $e');
    }
  }


  bool _libraryUrlMatchesQuery(String url, String query) {
    final tags = _localLibraryUrlTags[url];
    if (tags == null || tags.isEmpty) return true; // no info to reject
    final queryNorm = _normalizeLookupKey(query);
    return tags.any((tag) => _areSingularPluralEquivalent(queryNorm, tag));
  }

  String? _searchLocalLibraryIndex(String text, {List<String>? keywords}) {
    if (_localLibraryTagIndex.isEmpty) {
      return null;
    }

    final rawText = text.trim();
    final normalizedPhrase = rawText
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final phraseCandidates = <String>{
      rawText.toLowerCase().trim(),
      normalizedPhrase,
      normalizedPhrase.replaceAll('&', 'and').replaceAll(RegExp(r'\s+'), ' ').trim(),
      normalizedPhrase.replaceAll(' and ', ' & ').trim(),
      normalizedPhrase.replaceAll(' ', '_').trim(),
    }.where((value) => value.isNotEmpty).toList(growable: false);

    // First pass: prefer full-phrase matches for static labels like song names.
    for (final phrase in phraseCandidates) {
      for (final entry in _localLibraryUrlSubconcept.entries) {
        if (_areSingularPluralEquivalent(phrase, entry.value)) {
          return entry.key;
        }
      }

      if (_localLibraryTagIndex.containsKey(phrase)) {
        final url = _localLibraryTagIndex[phrase]!;
        if (_libraryUrlMatchesQuery(url, phrase)) {
          return url;
        }
      }
    }

    final words = normalizedPhrase.split(RegExp(r'\s+'));
    final extracted = _extractKeywords(rawText);
    final searchTerms = extracted.isNotEmpty
        ? extracted
        : (words.isNotEmpty ? words : <String>[]);

    for (final term in searchTerms) {
      final termLower = term.toLowerCase().trim();

      // Priority: exact canonical field match (subconcept/subcategory)
      // should win over generic tag collisions.
      for (final entry in _localLibraryUrlSubconcept.entries) {
        if (_areSingularPluralEquivalent(termLower, entry.value)) {
          return entry.key;
        }
      }

      if (_localLibraryTagIndex.containsKey(termLower)) {
        final url = _localLibraryTagIndex[termLower]!;
        if (_libraryUrlMatchesQuery(url, termLower)) {
          return url;
        }
        debugPrint('📚 PictogramService: Rejected library match for "$term" — tags do not safely match query');
      }
      final termStripped = _stripDiacritics(termLower);
      if (termStripped != termLower && _localLibraryTagIndex.containsKey(termStripped)) {
        final url = _localLibraryTagIndex[termStripped]!;
        if (_libraryUrlMatchesQuery(url, termStripped)) {
          return url;
        }
      }
    }
    
    if (keywords != null) {
      for (final keyword in keywords) {
        final kwLower = keyword.toLowerCase().trim();

        for (final entry in _localLibraryUrlSubconcept.entries) {
          if (_areSingularPluralEquivalent(kwLower, entry.value)) {
            return entry.key;
          }
        }

        if (_localLibraryTagIndex.containsKey(kwLower)) {
          final url = _localLibraryTagIndex[kwLower]!;
          if (_libraryUrlMatchesQuery(url, kwLower)) {
            return url;
          }
        }
        final kwStripped = _stripDiacritics(kwLower);
        if (kwStripped != kwLower && _localLibraryTagIndex.containsKey(kwStripped)) {
          final url = _localLibraryTagIndex[kwStripped]!;
          if (_libraryUrlMatchesQuery(url, kwStripped)) {
            return url;
          }
        }
      }
    }

    return null;
  }

  Future<Map<String, String?>> batchSearchRemoteSymbols(List<String> terms) async {
    if (terms.isEmpty) return const {};

    final baseUrl = EnvironmentConfig.apiBaseUrl;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_currentIdToken != null) {
      headers['Authorization'] = 'Bearer $_currentIdToken';
    }
    if (_currentUserId != null) {
      headers['X-User-ID'] = _currentUserId!;
    }

    try {
      debugPrint('🌐 PictogramService: Batch searching ${terms.length} symbols remotely...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/symbols/batch-search'),
        headers: headers,
        body: jsonEncode({'terms': terms}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['results'] is Map) {
          final results = Map<String, dynamic>.from(data['results'] as Map);
          final parsedResults = <String, String?>{};
          for (final entry in results.entries) {
            final key = entry.key;
            final val = entry.value?.toString();
            parsedResults[key] = val;
          }
          return parsedResults;
        }
      } else {
        debugPrint('🌐 PictogramService: Batch search remote failed with HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ PictogramService: Batch search remote error: $e');
    }
    return const {};
  }

  void _updateCacheWithCustomImageMatches() {
    if (_customImageMatches.isEmpty) return;
    
    final keysToUpdate = <String, String>{};
    
    _imageCache.forEach((key, value) {
      // Extract normalized search term from the cache key (which might contain "locale:")
      final parts = key.split(':');
      final normalizedText = parts.last;
      
      if (_customImageMatches.containsKey(normalizedText)) {
        final customUrl = _customImageMatches[normalizedText];
        if (customUrl != null && customUrl != value) {
          keysToUpdate[key] = customUrl;
        }
      }
    });
    
    if (keysToUpdate.isNotEmpty) {
      keysToUpdate.forEach((key, customUrl) {
        debugPrint('⚡ PictogramService: Overwriting cached global image for "$key" with newly loaded custom image: $customUrl');
        _imageCache[key] = customUrl;
      });
      unawaited(_saveCacheToPrefs());
    }
  }

  void _indexCustomImageAliases(CustomImage image) {
    final rawCandidates = <String>{
      image.concept,
      image.subconcept,
      ...image.tags,
    };

    final aliasCandidates = <String>{};
    for (final candidate in rawCandidates) {
      aliasCandidates.add(candidate.trim());
      if (candidate.contains(',') || candidate.contains('/')) {
        aliasCandidates.addAll(
          candidate.split(RegExp(r'[,/]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty),
        );
      }
    }

    for (final alias in aliasCandidates) {
      final normalized = _normalizeLookupKey(alias);
      if (normalized.isEmpty) continue;
      _customImageMatches.putIfAbsent(normalized, () => image.imageUrl);
    }
  }

  /// Batch preload custom images and build match cache
  Future<void> preloadCustomImages(List<String> buttonTexts) async {
    if (_currentUserId == null || _currentIdToken == null) {
      debugPrint('📭 PictogramService: No user context for custom image preloading');
      return;
    }
    
    if (_customImagesPreloaded) {
      debugPrint('📚 PictogramService: Custom images already preloaded. Matching new button texts against ${_customImages.length} images.');
      _matchButtonTexts(buttonTexts, _customImages);
      return;
    }

    final existingPreload = _customImagesPreloadFuture;
    if (existingPreload != null) {
      await existingPreload;
      _matchButtonTexts(buttonTexts, _customImages);
      return;
    }

    final preloadFuture = () async {
      try {
        debugPrint('🚀 PictogramService: Batch preloading custom images for ${buttonTexts.length} buttons');

        // Fetch all custom images once
        final customImages = await CustomImageService.getCustomImages(
          idToken: _currentIdToken!,
          aacUserId: _currentUserId!,
          shouldLogMissing: false,
        );

        _customImages.clear();
        _customImages.addAll(customImages);

        if (customImages.isEmpty) {
          debugPrint('📭 PictogramService: No custom images to preload');
          _customImagesPreloaded = true;
          return;
        }

        debugPrint('🔍 PictogramService: Building match cache for ${customImages.length} custom images');

        // Prime fast exact lookup aliases for every custom image concept/tag.
        for (final image in customImages) {
          _indexCustomImageAliases(image);
        }

        _matchButtonTexts(buttonTexts, customImages);

        _customImagesPreloaded = true;
        debugPrint('🎯 PictogramService: Batch preload complete - ${_customImageMatches.length} matches cached');
      } catch (e) {
        debugPrint('❌ PictogramService: Batch preload error: $e');
      }
    }();

    _customImagesPreloadFuture = preloadFuture;
    try {
      await preloadFuture;
    } finally {
      if (identical(_customImagesPreloadFuture, preloadFuture)) {
        _customImagesPreloadFuture = null;
      }
    }
  }

  void _matchButtonTexts(List<String> buttonTexts, List<CustomImage> customImages) {
    if (buttonTexts.isEmpty || customImages.isEmpty) return;

    var updated = false;
    for (final buttonText in buttonTexts) {
      final normalizedButtonText = _normalizeLookupKey(buttonText);
      if (normalizedButtonText.isEmpty || _customImageMatches.containsKey(normalizedButtonText)) {
        continue;
      }

      for (final image in customImages) {
        if (image.matchesQuery(buttonText)) {
          _customImageMatches[normalizedButtonText] = image.imageUrl;
          updated = true;
          break; // Use first match
        }
      }
    }

    if (updated || _customImageMatches.isNotEmpty) {
      _updateCacheWithCustomImageMatches();
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

  /// Inject custom images for unit/diagnostic testing
  void injectMockCustomImages(List<CustomImage> images) {
    _customImages.clear();
    _customImages.addAll(images);
    _customImageMatches.clear();
    for (final image in images) {
      _indexCustomImageAliases(image);
    }
    _customImagesPreloaded = true;
    _updateCacheWithCustomImageMatches();
  }

  /// Get matched custom image URL if one exists for the given text and keywords
  String? getCustomImageMatch(String text, {List<String>? keywords}) {
    final customLookupTerms = _buildCustomLookupTerms(text, keywords);
    for (final term in customLookupTerms) {
      if (_customImageMatches.containsKey(term)) {
        return _customImageMatches[term];
      }
    }
    return null;
  }

  /// Pre-populate the image cache from Firestore localized_tags for the given locale.
  /// Should be called once at startup (after clearCache) so that when Spanish/French/etc.
  /// word buttons render, their images are already in cache and load instantly.
  Future<void> prefetchLocaleImages(String locale) async {
    if (_skipDirectFirestoreReads) {
      return;
    }

    final localeCandidates = _getLocaleFieldCandidates(locale);
    if (localeCandidates.isEmpty || localeCandidates.first.startsWith('en')) {
      return; // English uses the existing imagecreator/search path
    }

    debugPrint('🌍 PictogramService: Prefetching images for locale "$locale" (candidates=$localeCandidates)');
    try {
      int count = 0;
      final seenDocIds = <String>{};

      for (final langCode in localeCandidates) {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('aac_images')
              .where('localized_tags.$langCode', isNotEqualTo: null)
              .get();

          for (final doc in snapshot.docs) {
            if (!seenDocIds.add(doc.id)) continue;

            final data = doc.data();
            final imageUrl = _extractAacImageUrl(data);
            if (imageUrl == null || imageUrl.isEmpty) continue;

            final rawTags = data['localized_tags'];
            if (rawTags == null) continue;
            final localizedTags = Map<String, dynamic>.from(rawTags as Map);
            final tagsValue = localizedTags[langCode];
            final tags = tagsValue is List
                ? tagsValue.cast<String>()
                : tagsValue is String
                    ? [tagsValue]
                    : const <String>[];

            for (final tag in tags) {
              final cacheKeys = _buildCacheKeyVariants(tag, locale: locale);
              for (final cacheKey in cacheKeys) {
                _imageCache[cacheKey] = imageUrl;
                count++;
              }
            }
          }
        } catch (e) {
          _handleFirestoreReadError(e, 'prefetch localized_tags query');
          if (_skipDirectFirestoreReads) {
            break;
          }
          // Continue with remaining locale candidates.
        }
      }

      await _saveCacheToPrefs();
      debugPrint('🌍 PictogramService: Prefetched $count "$locale" tag→image entries');
    } catch (e) {
      debugPrint('❌ PictogramService: prefetchLocaleImages error: $e');
    }
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
      final cleanWord = _stripDiacritics(word).replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
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