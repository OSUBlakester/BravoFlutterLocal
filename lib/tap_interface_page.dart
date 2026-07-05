import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'config/environment_config.dart';
import 'services/user_settings_provider.dart';
import 'services/pictogram_service.dart';
// Note: AuthPage and UserSelectionPage are in main.dart
import 'main.dart' show UserSelectionPage;
import 'services/tap_interface_service.dart';
import 'services/wake_word_service.dart';
import 'services/sight_word_service.dart';
import 'services/chat_history_service.dart';
import 'freestyle_page.dart';
import 'threads_page.dart';
import 'favorites_page.dart';
import 'games_page.dart';
import 'mood_selection_page.dart';
import 'email_page.dart';
import 'music_page.dart';
import 'widgets/spelling_dialog.dart';
import 'package:intl/intl.dart';
import 'services/schedule_service.dart';
import 'services/music_playback_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/authenticated_http_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Plays a brief click sound through the media audio channel when a sensitivity-gated tap is registered.
/// Global session tracking set for missing images (shared across all button instances)
final Set<String> _globalSessionLoggedMissingImages = {};

/// Log missing images to Firestore when displaying button with no image
/// Simple approach: trust the shouldLogMissing flag from the button widget
Future<void> _logMissingImage(String buttonText) async {
  try {
    // Get current user context
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;

    if (user == null) {
      debugPrint('⚠️ Cannot log missing image - no authenticated user');
      return;
    }

    final textTrimmed = buttonText.trim();
    final firestore = FirebaseFirestore.instance;

    // Check if this exact text was already logged for this user to prevent duplicates
    final existingQuery = await firestore
        .collection('missing_images')
        .where('text', isEqualTo: textTrimmed)
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (existingQuery.docs.isNotEmpty) {
      debugPrint(
        '⏭️ Skipping duplicate log - missing image already recorded for: "$textTrimmed"',
      );
      return;
    }

    // Only log if it doesn't already exist for this user
    await firestore.collection('missing_images').add({
      'text': textTrimmed,
      'timestamp': FieldValue.serverTimestamp(),
      'source': 'tap_interface_display_layer',
      'uid': user.uid,
    });

    debugPrint('📋 Logged missing image to Firestore: "$textTrimmed"');
  } catch (e) {
    debugPrint('❌ Error logging missing image: $e');
  }
}

// Reusable button widget with pictogram support for tap interface
class TapInterfaceButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final double fontSize;
  final bool enablePictograms;
  final String? sightWordGradeLevel;
  final bool enableSightWords;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;
  final FontWeight? fontWeight;
  final List<String>? keywords;
  final bool
  shouldLogMissing; // Only log missing images in user-facing contexts, not preloading
  final ValueChanged<String>?
  onImageLogged; // Callback to track which images were logged
  final String? assignedImageUrl; // Pre-assigned image URL from database
  final String?
  imageSearchText; // Full speech text for image search (label may be abbreviated)
  final bool cacheOnlyImageLookup;
  // When set, renders a 2px border + coloured glow to match web-app variant style.
  final Color? glowColor;
  final double borderWidth;
  // Active mascot name (e.g. 'buddy'). When non-empty, mascot-specific images
  // are preferred and pre-assigned generic URLs are bypassed.
  final String mascot;

  // Page-level tap sensitivity shared across all instances. 0 = instant (default).
  // Set by the page when loaded from SharedPreferences.
  static int tapMinDurationMs = 0;

  const TapInterfaceButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.fontSize,
    this.enablePictograms = true,
    this.sightWordGradeLevel,
    this.enableSightWords = true,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius,
    this.fontWeight,
    this.keywords,
    this.shouldLogMissing = true,
    this.onImageLogged,
    this.assignedImageUrl,
    this.imageSearchText,
    this.cacheOnlyImageLookup = false,
    this.glowColor,
    this.borderWidth = 1.0,
    this.mascot = '',
  });

  State<TapInterfaceButton> createState() => _TapInterfaceButtonState();
}

class _TapInterfaceButtonState extends State<TapInterfaceButton> {
  static final Map<String, bool> _allSightWordsCache = {};
  static String? _allSightWordsCacheGrade;
  static bool _isSightWordServiceReady = false;
  static bool _isSightWordServiceWarmupInProgress = false;

  String? _pictogramUrl;
  bool _isLoading = false;
  bool _isSightWord = false;
  String? _lastLoadedKey;
  bool _isLoadingPictogram =
      false; // guard against concurrent _loadPictogram calls

  bool _thresholdMet = false;
  bool _isPressing = false;
  Timer? _thresholdTimer;

  @override
  void dispose() {
    _thresholdTimer?.cancel();
    super.dispose();
  }

  void _handlePress() {
    final minMs = TapInterfaceButton.tapMinDurationMs;
    debugPrint('[TapSensitivity] _handlePress: minMs=$minMs thresholdMet=$_thresholdMet label="${widget.label}"');
    if (minMs <= 0) {
      widget.onPressed();
      return;
    }
    if (_thresholdMet) {
      widget.onPressed();
    }
  }

  void _onPointerDown(PointerDownEvent _) {
    _thresholdMet = false;
    _thresholdTimer?.cancel();
    if (mounted) setState(() => _isPressing = true);
    final minMs = TapInterfaceButton.tapMinDurationMs;
    if (minMs > 0) {
      _thresholdTimer = Timer(Duration(milliseconds: minMs), () {
        HapticFeedback.mediumImpact();
        if (mounted) setState(() => _thresholdMet = true);
      });
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    _thresholdTimer?.cancel();
    if (mounted) setState(() => _isPressing = false);
    // Small delay so _handlePress can read _thresholdMet before we reset it.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _thresholdMet = false);
    });
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _thresholdTimer?.cancel();
    if (mounted) setState(() { _isPressing = false; _thresholdMet = false; });
  }

  bool _looksLikeAbsoluteLocalPath(String value) {
    return value.startsWith('/var/') ||
        value.startsWith('/private/') ||
        value.startsWith('/data/') ||
        value.startsWith('/storage/') ||
        value.startsWith('/Users/');
  }

  String? _normalizePictogramUrl(String? rawUrl) {
    if (rawUrl == null) return null;

    var url = rawUrl.trim();
    if (url.isEmpty || url.toLowerCase() == 'null') return null;

    if (url.startsWith('file://')) return url;
    if (_looksLikeAbsoluteLocalPath(url)) return url;

    if (url.startsWith('gs://')) {
      final remainder = url.substring(5);
      final slash = remainder.indexOf('/');
      if (slash > 0) {
        final bucket = remainder.substring(0, slash);
        final objectPath = remainder.substring(slash + 1);
        return 'https://storage.googleapis.com/$bucket/$objectPath';
      }
    }

    if (url.startsWith('//')) {
      return 'https:$url';
    }

    if (url.startsWith('storage.googleapis.com/')) {
      return 'https://$url';
    }

    if (url.startsWith('/')) {
      return '${EnvironmentConfig.apiBaseUrl}$url';
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    return url;
  }

  static const Map<String, String> _numberWords = {
    'zero': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'ten': '10',
    'eleven': '11',
    'twelve': '12',
    'thirteen': '13',
    'fourteen': '14',
    'fifteen': '15',
    'sixteen': '16',
    'seventeen': '17',
    'eighteen': '18',
    'nineteen': '19',
    'twenty': '20',
    'twenty-one': '21',
    'twenty one': '21',
    'twenty-two': '22',
    'twenty two': '22',
    'twenty-three': '23',
    'twenty three': '23',
    'twenty-four': '24',
    'twenty four': '24',
    'twenty-five': '25',
    'twenty five': '25',
    'twenty-six': '26',
    'twenty six': '26',
    'twenty-seven': '27',
    'twenty seven': '27',
    'twenty-eight': '28',
    'twenty eight': '28',
    'twenty-nine': '29',
    'twenty nine': '29',
    'thirty': '30',
    'thirty-one': '31',
    'thirty one': '31',
    'thirty-two': '32',
    'thirty two': '32',
    'thirty-three': '33',
    'thirty three': '33',
    'thirty-four': '34',
    'thirty four': '34',
    'thirty-five': '35',
    'thirty five': '35',
    'thirty-six': '36',
    'thirty six': '36',
    'thirty-seven': '37',
    'thirty seven': '37',
    'thirty-eight': '38',
    'thirty eight': '38',
    'thirty-nine': '39',
    'thirty nine': '39',
    'forty': '40',
    'forty-one': '41',
    'forty one': '41',
    'forty-two': '42',
    'forty two': '42',
    'forty-three': '43',
    'forty three': '43',
    'forty-four': '44',
    'forty four': '44',
    'forty-five': '45',
    'forty five': '45',
    'forty-six': '46',
    'forty six': '46',
    'forty-seven': '47',
    'forty seven': '47',
    'forty-eight': '48',
    'forty eight': '48',
    'forty-nine': '49',
    'forty nine': '49',
    'fifty': '50',
    'fifty-one': '51',
    'fifty one': '51',
    'fifty-two': '52',
    'fifty two': '52',
    'fifty-three': '53',
    'fifty three': '53',
    'fifty-four': '54',
    'fifty four': '54',
    'fifty-five': '55',
    'fifty five': '55',
    'fifty-six': '56',
    'fifty six': '56',
    'fifty-seven': '57',
    'fifty seven': '57',
    'fifty-eight': '58',
    'fifty eight': '58',
    'fifty-nine': '59',
    'fifty nine': '59',
    'sixty': '60',
    'sixty-one': '61',
    'sixty one': '61',
    'sixty-two': '62',
    'sixty two': '62',
    'sixty-three': '63',
    'sixty three': '63',
    'sixty-four': '64',
    'sixty four': '64',
    'sixty-five': '65',
    'sixty five': '65',
    'sixty-six': '66',
    'sixty six': '66',
    'sixty-seven': '67',
    'sixty seven': '67',
    'sixty-eight': '68',
    'sixty eight': '68',
    'sixty-nine': '69',
    'sixty nine': '69',
    'seventy': '70',
    'seventy-one': '71',
    'seventy one': '71',
    'seventy-two': '72',
    'seventy two': '72',
    'seventy-three': '73',
    'seventy three': '73',
    'seventy-four': '74',
    'seventy four': '74',
    'seventy-five': '75',
    'seventy five': '75',
    'seventy-six': '76',
    'seventy six': '76',
    'seventy-seven': '77',
    'seventy seven': '77',
    'seventy-eight': '78',
    'seventy eight': '78',
    'seventy-nine': '79',
    'seventy nine': '79',
    'eighty': '80',
    'eighty-one': '81',
    'eighty one': '81',
    'eighty-two': '82',
    'eighty two': '82',
    'eighty-three': '83',
    'eighty three': '83',
    'eighty-four': '84',
    'eighty four': '84',
    'eighty-five': '85',
    'eighty five': '85',
    'eighty-six': '86',
    'eighty six': '86',
    'eighty-seven': '87',
    'eighty seven': '87',
    'eighty-eight': '88',
    'eighty eight': '88',
    'eighty-nine': '89',
    'eighty nine': '89',
    'ninety': '90',
    'ninety-one': '91',
    'ninety one': '91',
    'ninety-two': '92',
    'ninety two': '92',
    'ninety-three': '93',
    'ninety three': '93',
    'ninety-four': '94',
    'ninety four': '94',
    'ninety-five': '95',
    'ninety five': '95',
    'ninety-six': '96',
    'ninety six': '96',
    'ninety-seven': '97',
    'ninety seven': '97',
    'ninety-eight': '98',
    'ninety eight': '98',
    'ninety-nine': '99',
    'ninety nine': '99',
    'hundred': '100',
    'one hundred': '100',
  };

  // Common non-English number words used by translated Tap options.
  // Kept intentionally small (0-20 + common tens) and combined with keyword
  // matching so AI-generated options can still resolve to large-number display.
  static final Map<String, String> _localizedNumberWords = {
    // Spanish
    'cero': '0',
    'uno': '1',
    'dos': '2',
    'tres': '3',
    'cuatro': '4',
    'cinco': '5',
    'seis': '6',
    'siete': '7',
    'ocho': '8',
    'nueve': '9',
    'diez': '10',
    'once': '11',
    'doce': '12',
    'trece': '13',
    'catorce': '14',
    'quince': '15',
    'dieciseis': '16',
    'diecisiete': '17',
    'dieciocho': '18',
    'diecinueve': '19',
    'veinte': '20',
    'treinta': '30',
    'cuarenta': '40',
    'cincuenta': '50',
    'sesenta': '60',
    'setenta': '70',
    'ochenta': '80',
    'noventa': '90',
    'cien': '100',

    // French
    'zero': '0',
    'un': '1',
    'deux': '2',
    'trois': '3',
    'quatre': '4',
    'cinq': '5',
    'six': '6',
    'sept': '7',
    'huit': '8',
    'neuf': '9',
    'onze': '11',
    'douze': '12',
    'treize': '13',
    'quatorze': '14',
    'seize': '16',
    'vingt': '20',

    // German
    'eins': '1',
    'zwei': '2',
    'drei': '3',
    'vier': '4',
    'funf': '5',
    'sechs': '6',
    'sieben': '7',
    'acht': '8',
    'neun': '9',
    'zehn': '10',
    'elf': '11',
    'zwolf': '12',
    'dreizehn': '13',
    'vierzehn': '14',
    'funfzehn': '15',
    'sechzehn': '16',
    'siebzehn': '17',
    'achtzehn': '18',
    'neunzehn': '19',
    'zwanzig': '20',

    // Italian
    'due': '2',
    'tre': '3',
    'quattro': '4',
    'cinque': '5',
    'sei': '6',
    'sette': '7',
    'otto': '8',
    'nove': '9',
    'dieci': '10',
    'undici': '11',
    'dodici': '12',
    'tredici': '13',
    'quattordici': '14',
    'quindici': '15',
    'sedici': '16',
    'diciassette': '17',
    'diciotto': '18',
    'diciannove': '19',
    'venti': '20',

    // Portuguese
    'um': '1',
    'dois': '2',
    'sete': '7',
    'oito': '8',
    'dez': '10',
    'doze': '12',
    'treze': '13',
    'dezesseis': '16',
    'dezessete': '17',
    'dezoito': '18',
    'dezenove': '19',
    'vinte': '20',
  };

  String _normalizeDigits(String input) {
    final sb = StringBuffer();
    for (final rune in input.runes) {
      // Arabic-Indic digits U+0660..U+0669
      if (rune >= 0x0660 && rune <= 0x0669) {
        sb.writeCharCode('0'.codeUnitAt(0) + (rune - 0x0660));
      }
      // Extended Arabic-Indic digits U+06F0..U+06F9
      else if (rune >= 0x06F0 && rune <= 0x06F9) {
        sb.writeCharCode('0'.codeUnitAt(0) + (rune - 0x06F0));
      } else {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

  String _normalizeNumberToken(String input) {
    return _normalizeDigits(
      input
          .toLowerCase()
          .trim()
          .replaceAll('á', 'a')
          .replaceAll('à', 'a')
          .replaceAll('â', 'a')
          .replaceAll('ä', 'a')
          .replaceAll('ã', 'a')
          .replaceAll('å', 'a')
          .replaceAll('é', 'e')
          .replaceAll('è', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('ë', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ì', 'i')
          .replaceAll('î', 'i')
          .replaceAll('ï', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ò', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('ö', 'o')
          .replaceAll('õ', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ù', 'u')
          .replaceAll('û', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('ñ', 'n')
          .replaceAll('ç', 'c')
          .replaceAll(RegExp(r'\s+'), ' '),
    );
  }

  String? _getNumberDisplay(
    String label, {
    bool allowEmbeddedNumber = false,
  }) {
    final candidates = allowEmbeddedNumber
        ? <String>[label, ...(widget.keywords ?? const <String>[])]
        : <String>[label];

    for (final candidate in candidates) {
      final cleanLabel = _normalizeNumberToken(candidate);
      if (cleanLabel.isEmpty) continue;

      if (int.tryParse(cleanLabel) != null) {
        return cleanLabel;
      }

      if (allowEmbeddedNumber) {
        final directNumberMatch = RegExp(r'\b\d{1,3}\b').firstMatch(cleanLabel);
        if (directNumberMatch != null) {
          return directNumberMatch.group(0);
        }
      }

      final englishMapped = _numberWords[cleanLabel];
      if (englishMapped != null) {
        return englishMapped;
      }

      final localizedMapped = _localizedNumberWords[cleanLabel];
      if (localizedMapped != null) {
        return localizedMapped;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPictogram();
  }

  @override
  void didUpdateWidget(TapInterfaceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final labelChanged = widget.label != oldWidget.label;
    final searchTextChanged =
        widget.imageSearchText != oldWidget.imageSearchText;
    final enabledChanged =
        widget.enablePictograms != oldWidget.enablePictograms;
    final sightWordsChanged =
        widget.enableSightWords != oldWidget.enableSightWords;
    final gradeChanged =
        widget.sightWordGradeLevel != oldWidget.sightWordGradeLevel;
    final keywordsChanged = !listEquals(widget.keywords, oldWidget.keywords);
    final cacheOnlyChanged =
      widget.cacheOnlyImageLookup != oldWidget.cacheOnlyImageLookup;

    // When the button's word changes entirely, reset image state so the new word
    // gets a fresh lookup instead of keeping the old word's image.
    final mascotChanged = widget.mascot != oldWidget.mascot;

    if (labelChanged || searchTextChanged || keywordsChanged || mascotChanged) {
      _pictogramUrl = null;
      _lastLoadedKey = null;
      _isSightWord = false;
      _isLoadingPictogram = false;
      // Clear the PictogramService in-memory cache entry so the re-lookup
      // actually hits the network instead of returning the stale null.
      if (keywordsChanged && !labelChanged && !searchTextChanged) {
        final settingsProvider =
            Provider.of<UserSettingsProvider>(context, listen: false);
        final userLocale =
            settingsProvider.settings?.userLanguage ?? 'en-US';
        final isNonEnglish = !userLocale.startsWith('en');
        final effectiveSearchText =
            (widget.imageSearchText ?? widget.label).trim().toLowerCase();
        final ck = isNonEnglish
            ? '${userLocale.toLowerCase()}:$effectiveSearchText'
            : effectiveSearchText;
        PictogramService().clearCacheEntry(ck);
      }
    }

    if (labelChanged ||
        searchTextChanged ||
        enabledChanged ||
        sightWordsChanged ||
        gradeChanged ||
        keywordsChanged ||
        cacheOnlyChanged ||
        mascotChanged) {
      _loadPictogram();
    }
  }

  Future<void> _loadPictogram() async {
    if (widget.label.trim().isEmpty) return;

    // Once a button has an image, never replace it — later keyword-refresh rounds
    // should only fill in buttons that still have no image.
    if (_pictogramUrl != null) return;

    // Prevent concurrent calls from racing each other and producing different results.
    if (_isLoadingPictogram) return;

    debugPrint(
      '🖼️ TapInterfaceButton._loadPictogram: label="${widget.label}", enablePictograms=${widget.enablePictograms}',
    );

    // Use the display word as search text; the server resolves localized_tags for non-English locales.
    final effectiveSearchText = (widget.imageSearchText ?? widget.label).trim();

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final userLocale = settingsProvider.settings?.userLanguage ?? 'en-US';
    final isNonEnglish = !userLocale.startsWith('en');
    final activeMascot = widget.mascot;
    final mascotIsActive = activeMascot.isNotEmpty;
    final normalizedSearchTextForKey = effectiveSearchText.toLowerCase();
    final cacheKey = isNonEnglish
      ? '${userLocale.toLowerCase()}:$normalizedSearchTextForKey'
      : normalizedSearchTextForKey;
    final lookupAttemptKey =
        '$cacheKey|cacheOnly=${widget.cacheOnlyImageLookup ? 1 : 0}';

    if (_lastLoadedKey == lookupAttemptKey) {
      // Already attempted a lookup for this exact key; the result is in _pictogramUrl (null means no image found).
      return;
    }

    _isLoadingPictogram = true;

    // Show loading state only briefly to avoid flashing
    setState(() {
      _isLoading = true;
      _isSightWord = false;
    });

    try {
      // Check sight word status for both image suppression and formatting
      // Only apply sight word logic if enableSightWords is true
      bool allWordsAreSightWords = false;

      if (widget.enableSightWords) {
        debugPrint('🖼️ Sight-word check start for "${widget.label}"');
        allWordsAreSightWords = await _checkIfAllWordsAreSightWords(
          widget.label,
          widget.sightWordGradeLevel,
        ).timeout(
          const Duration(milliseconds: 400),
          onTimeout: () {
            debugPrint(
              '⚠️ Sight-word check timeout for "${widget.label}"; continuing with image lookup',
            );
            return false;
          },
        );
        debugPrint('🖼️ Sight-word check end for "${widget.label}": allWords=$allWordsAreSightWords');
      }

      if (allWordsAreSightWords) {
        // Only suppress pictogram if ALL words are sight words
        debugPrint(
          '🖼️ Skipping image for "${widget.label}" - all words are sight words',
        );
        if (mounted) {
          setState(() {
            _pictogramUrl = null;
            _isSightWord = true; // Apply sight word formatting
            _isLoading = false;
              _lastLoadedKey = lookupAttemptKey;
          });
        }
      } else {
        // If pictograms are disabled, never show assigned or searched images
        if (!widget.enablePictograms) {
          debugPrint(
            '🖼️ Skipping image for "${widget.label}" - enablePictograms is false',
          );
          if (mounted) {
            setState(() {
              _pictogramUrl = null;
              _isSightWord = false;
              _isLoading = false;
              _lastLoadedKey = lookupAttemptKey;
            });
          }
        } else {
          final pictogramService = PictogramService();
          final customMatch = pictogramService.getCustomImageMatch(
            effectiveSearchText,
            keywords: widget.keywords,
          );
          final isAssignedCustom = widget.assignedImageUrl != null &&
              (widget.assignedImageUrl!.contains('/custom_images/') ||
               widget.assignedImageUrl!.contains('/profile_images/'));

          if (isAssignedCustom) {
            debugPrint('🖼️ Using assigned custom image for "${widget.label}": ${widget.assignedImageUrl}');
            if (mounted) {
              setState(() {
                _pictogramUrl = _normalizePictogramUrl(widget.assignedImageUrl);
                _isSightWord = false;
                _isLoading = false;
                _lastLoadedKey = lookupAttemptKey;
              });
            }
          } else if (customMatch != null) {
            debugPrint('🖼️ Using matched custom image for "${widget.label}": $customMatch');
            if (mounted) {
              setState(() {
                _pictogramUrl = _normalizePictogramUrl(customMatch);
                _isSightWord = false;
                _isLoading = false;
                _lastLoadedKey = lookupAttemptKey;
              });
            }
          } else if (widget.assignedImageUrl != null &&
              widget.assignedImageUrl!.isNotEmpty &&
              !mascotIsActive) {
            // Skip the pre-assigned URL shortcut when a mascot is active so the
            // mascot-aware lookup can find the correct mascot-specific image.
            debugPrint('🖼️ Using assigned global image for "${widget.label}": ${widget.assignedImageUrl}');
            if (mounted) {
              setState(() {
                _pictogramUrl = _normalizePictogramUrl(widget.assignedImageUrl);
                _isSightWord = false;
                _isLoading = false;
                _lastLoadedKey = lookupAttemptKey;
              });
            }
          } else {
            // SECOND: If no assigned image and no custom image match, search for pictogram
            debugPrint(
              '🖼️ Loading pictogram for "${widget.label}" (effectiveSearchText="$effectiveSearchText", locale="$userLocale")...',
            );
            debugPrint('🖼️ Pictogram lookup start for "${widget.label}"');
            var currentUserId = settingsProvider.userId;
            var currentIdToken = settingsProvider.idToken;

          if (currentUserId == null ||
              currentUserId.isEmpty ||
              currentIdToken == null ||
              currentIdToken.isEmpty) {
            final authUser = FirebaseAuth.instance.currentUser;
            if (authUser != null) {
              currentUserId = currentUserId?.isNotEmpty == true
                  ? currentUserId
                  : authUser.uid;
              String? refreshedToken;
              try {
                refreshedToken = await authUser
                    .getIdToken(true)
                    .timeout(const Duration(seconds: 6));
              } catch (e) {
                debugPrint(
                  '[TapInterfaceButton] getIdToken(true) failed: $e',
                );
                try {
                  refreshedToken = await authUser
                      .getIdToken()
                      .timeout(const Duration(seconds: 4));
                } catch (fallbackError) {
                  debugPrint(
                    '[TapInterfaceButton] getIdToken() fallback failed: $fallbackError',
                  );
                }
              }
              if (refreshedToken != null && refreshedToken.isNotEmpty) {
                currentIdToken = refreshedToken;
                settingsProvider.idToken = refreshedToken;
              }
              if (currentUserId != null && currentUserId.isNotEmpty) {
                settingsProvider.userId = currentUserId;
              }
            }
          }

          if (currentUserId != null &&
              currentUserId.isNotEmpty &&
              currentIdToken != null &&
              currentIdToken.isNotEmpty) {
            pictogramService.setUserContext(
              userId: currentUserId,
              idToken: currentIdToken,
              mascot: widget.mascot.isNotEmpty
                  ? widget.mascot
                  : settingsProvider.settings?.mascot,
            );
          }
          pictogramService.enablePictograms = true;

          // Single pass lookup. Board-level warmup handles bulk priming.
          final result = await pictogramService.getPictogramResult(
            effectiveSearchText,
            sightWordGradeLevel: widget.sightWordGradeLevel != null
                ? int.tryParse(widget.sightWordGradeLevel!)
                : null,
            keywords: widget.keywords,
            shouldLogMissing: widget.shouldLogMissing,
            locale: userLocale,
            cacheOnly: widget.cacheOnlyImageLookup,
          );

          debugPrint(
            '🖼️ Pictogram result for "${widget.label}": ${result?.imageUrl ?? "null"}',
          );

          // If no image found after all search strategies, log it as missing (display layer logging)
          // Only log if shouldLogMissing is true (disabled during preloading)
          // AND we haven't already logged this image text in this session (prevent duplicates)
          if (widget.shouldLogMissing &&
              result != null &&
              result.imageUrl == null &&
              !result.isSightWord) {
            final buttonTextLower = widget.label.toLowerCase().trim();

            // Check session tracking set to avoid duplicate logs for the same image
            if (!_globalSessionLoggedMissingImages.contains(buttonTextLower)) {
              debugPrint('📋 LogMissingImage triggered for: "${widget.label}"');
              await _logMissingImage(widget.label);
              // Track that we've logged this image to prevent duplicates
              _globalSessionLoggedMissingImages.add(buttonTextLower);
              // Notify parent that we logged this image
              widget.onImageLogged?.call(widget.label);
            } else {
              debugPrint(
                '⏭️ Skipping duplicate log for: "${widget.label}" (already logged in this session)',
              );
            }
          }

          if (mounted) {
            setState(() {
              _pictogramUrl = _normalizePictogramUrl(result?.imageUrl);
              _isSightWord =
                  false; // No sight word formatting for non-sight words
              _isLoading = false;
              _lastLoadedKey = lookupAttemptKey;
            });
          }
        }
      }
    }
  } catch (e) {
      debugPrint('Error loading pictogram for "${widget.label}": $e');
      if (mounted) {
        setState(() {
          _isSightWord = false;
          _isLoading = false;
        });
      }
    } finally {
      debugPrint('🖼️ TapInterfaceButton._loadPictogram end: label="${widget.label}", url=${_pictogramUrl ?? "null"}');
      _isLoadingPictogram = false;
    }
  }

  /// Check if text contains any sight words (not just all words)
  Future<bool> _checkForAnySightWords(
    String text,
    String? sightWordGradeLevel,
  ) async {
    if (sightWordGradeLevel == null || sightWordGradeLevel.isEmpty) {
      return false;
    }

    try {
      final sightWordService = SightWordService();
      if (!sightWordService.isInitialized) {
        await sightWordService.initialize();
      }

      // Update grade level if needed
      await sightWordService.setGradeLevel(sightWordGradeLevel);

      // Get all current sight words
      final sightWords = sightWordService.getAllSightWords();
      if (sightWords.isEmpty) {
        return false;
      }

      // Clean and split the text into words
      final cleanText = text.trim().toLowerCase();
      final words = cleanText
          .split(RegExp(r'\s+'))
          .map((word) => word.replaceAll(RegExp(r'[^\w]'), ''))
          .where((word) => word.isNotEmpty)
          .toList();

      // Check if ANY word is a sight word
      final hasAnySightWords = words.any((word) => sightWords.contains(word));

      if (hasAnySightWords) {
        debugPrint(
          '🔤 TapInterfaceButton: "$text" contains sight words - suppressing pictogram',
        );
      }

      return hasAnySightWords;
    } catch (e) {
      debugPrint('🔤 TapInterfaceButton: Error checking sight words: $e');
      return false;
    }
  }

  /// Check if ALL words in text are sight words (for formatting)
  Future<bool> _checkIfAllWordsAreSightWords(
    String text,
    String? sightWordGradeLevel,
  ) async {
    if (sightWordGradeLevel == null || sightWordGradeLevel.isEmpty) {
      return false;
    }

    final normalizedText = text.trim().toLowerCase();
    final cacheKey = '${sightWordGradeLevel.trim()}::$normalizedText';
    if (_allSightWordsCache.containsKey(cacheKey)) {
      return _allSightWordsCache[cacheKey]!;
    }

    try {
      final sightWordService = SightWordService();

      if (!_isSightWordServiceReady && !_isSightWordServiceWarmupInProgress) {
        _isSightWordServiceWarmupInProgress = true;
        try {
          if (!sightWordService.isInitialized) {
            await sightWordService.initialize();
          }
          _isSightWordServiceReady = true;
        } finally {
          _isSightWordServiceWarmupInProgress = false;
        }
      } else if (!_isSightWordServiceReady && _isSightWordServiceWarmupInProgress) {
        // Another button is warming up the service; fail open for this frame.
        return false;
      }

      if (_allSightWordsCacheGrade != sightWordGradeLevel) {
        await sightWordService.setGradeLevel(sightWordGradeLevel);
        _allSightWordsCacheGrade = sightWordGradeLevel;
        _allSightWordsCache.clear();
      }

      // Use the built-in method that checks if ALL words are sight words
      final allAreSightWords = sightWordService.isSightWordText(text);
      _allSightWordsCache[cacheKey] = allAreSightWords;

      if (allAreSightWords) {
        debugPrint(
          '🔤 TapInterfaceButton: "$text" - ALL words are sight words, applying special formatting',
        );
      }

      return allAreSightWords;
    } catch (e) {
      debugPrint(
        '🔤 TapInterfaceButton: Error checking if all words are sight words: $e',
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);

    // Stable glow used for border/elevation — never changes mid-gesture.
    final widgetGlow = widget.glowColor;

    // Box-shadow only — ElevatedButton style never changes mid-touch so the
    // gesture recognizer state is preserved.
    // amber while pressing → green when threshold met → widget glow otherwise
    final glowColor = _thresholdMet
        ? const Color(0xFF22c55e)  // green-500
        : _isPressing
            ? const Color(0xFFF59E0B)  // amber-400
            : widgetGlow;

    final button = ElevatedButton(
      onPressed: _handlePress,
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.backgroundColor,
        foregroundColor: widget.foregroundColor,
        overlayColor: Colors.orange,
        elevation: widgetGlow != null ? 0 : 2,
        padding: widget.padding,
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: widgetGlow ?? widget.borderColor,
            width: widgetGlow != null ? 2.0 : widget.borderWidth,
          ),
        ),
      ),
      child: widget.label.isNotEmpty
          ? _buildPictogramContent()
          : _buildTextOnlyContent(),
    );

    final timed = Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: button,
    );

    // Always include DecoratedBox so the tree structure never changes mid-gesture
    // (adding/removing a parent mid-touch destroys the gesture recognizer state).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.25),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: timed,
    );
  }

  Widget _buildPictogramContent() {
    // For pure number options, always render the large-number display.
    final numberOnlyDisplay = _getNumberDisplay(widget.label);
    if (numberOnlyDisplay != null) {
      return _buildNumberLayout(numberOnlyDisplay);
    }

    if (_isLoading) {
      return _buildTextOnlyContent();
    }

    if (_pictogramUrl != null && _pictogramUrl?.isNotEmpty == true) {
      return _buildPictogramLayout();
    }

    // For labels that contain a number plus other words (e.g. "5 little ducks"),
    // only fall back to large-number display after pictogram lookup fails.
    final fallbackNumberDisplay = _getNumberDisplay(
      widget.label,
      allowEmbeddedNumber: true,
    );
    if (fallbackNumberDisplay != null) {
      return _buildNumberLayout(fallbackNumberDisplay);
    }

    return _buildTextOnlyContent();
  }

  Widget _buildNumberLayout(String numberDisplay) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Large Number as "Image"
        LayoutBuilder(
          builder: (context, constraints) {
            // Dynamic size based on available height
            final fontSize = (constraints.maxHeight * 0.7).clamp(20.0, 100.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: Text(
                numberDisplay,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: widget.foregroundColor.withOpacity(0.6),
                ),
              ),
            );
          },
        ),

        // Text layer - pinned to bottom
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2.0, left: 2.0, right: 2.0),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: (widget.fontSize * 0.9).clamp(10.0, 16.0),
                fontWeight: widget.fontWeight ?? FontWeight.w600,
                color: widget.foregroundColor,
                shadows: [
                  Shadow(
                    offset: const Offset(0, 0),
                    blurRadius: 4.0,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPictogramLayout() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Image layer - shifted up slightly to make room for text
        Padding(
          padding: const EdgeInsets.only(
            bottom: 18.0,
          ), // Increased padding for label strip
          child: _buildPictogramImage(),
        ),

        // Text layer - pinned to bottom with background strip
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(
                0.7,
              ), // Dark background for readability
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(6), // Match button radius roughly
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: (widget.fontSize * 0.9).clamp(10.0, 16.0),
                fontWeight: widget.fontWeight ?? FontWeight.w600,
                color: Colors.white, // White text for contrast
                // fontFamily: GoogleFonts.openSans().fontFamily,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPictogramImage() {
    if (_pictogramUrl == null) return const SizedBox();

    // Handle emoji pictograms - use LayoutBuilder for dynamic sizing
    final pictogramUrl = _pictogramUrl!;
    final isLocalFileImage = pictogramUrl.startsWith('file://') ||
      _looksLikeAbsoluteLocalPath(pictogramUrl);

    if (isLocalFileImage) {
      final localPath = pictogramUrl.startsWith('file://')
          ? Uri.parse(pictogramUrl).toFilePath()
          : pictogramUrl;
      final localFile = File(localPath);
      if (localFile.existsSync()) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final imageSize = (constraints.maxHeight * 1.5).clamp(30.0, 400.0);
            return Center(
              child: SizedBox(
                width: imageSize,
                height: imageSize,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    localFile,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildTextOnlyContent();
                    },
                  ),
                ),
              ),
            );
          },
        );
      }
    }

    if (!pictogramUrl.startsWith('http')) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Dynamic emoji size based on available height (115% of available height - bleed)
          final emojiSize = (constraints.maxHeight * 1.15).clamp(20.0, 200.0);
          return Center(
            child: Text(
              pictogramUrl,
              style: TextStyle(fontSize: emojiSize),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
    }

    // Handle network images - use LayoutBuilder for dynamic sizing
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dynamic image size based on available space (150% of available area - bleed) - increased by 25%
        final imageSize = (constraints.maxHeight * 1.5).clamp(30.0, 400.0);
        return Center(
          child: SizedBox(
            width: imageSize,
            height: imageSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                pictogramUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: (imageSize * 0.2).clamp(8.0, 12.0),
                      height: (imageSize * 0.2).clamp(8.0, 12.0),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildTextOnlyContent();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextOnlyContent() {
    final bool isSpecialSightWord = _isSightWord;
    // Use bolder weight for better readability on large text
    final FontWeight fontWeight = isSpecialSightWord
        ? FontWeight.w900
        : (widget.fontWeight ?? FontWeight.w600);
    final Color textColor = isSpecialSightWord
        ? const Color(0xFFFF4444)
        : widget.foregroundColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableHeight = constraints.maxHeight;
        final double availableWidth = constraints.maxWidth;
        final String text = widget.label;

        // Check for single word to optimize scaling (prevents splitting)
        final bool isSingleWord = !text.trim().contains(' ');

        if (isSingleWord) {
          // For single words, we can use FittedBox with maxLines 1
          // This guarantees no splitting and maximizes size
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: availableHeight * 0.8, // Start very large
                    fontWeight: fontWeight,
                    color: textColor,
                    shadows: isSpecialSightWord
                        ? [
                            const Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 3,
                              color: Color(0x40000000),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          );
        }

        // For phrases, we need to be careful about word splitting
        // Calculate font size based on length, but constrain by longest word width
        int textLength = text.length;

        // Base size on height/length
        double fontSize;
        if (textLength <= 5) {
          fontSize = availableHeight * 0.40;
        } else if (textLength <= 10) {
          fontSize = availableHeight * 0.28;
        } else if (textLength <= 20) {
          fontSize = availableHeight * 0.22;
        } else {
          fontSize = availableHeight * 0.18;
        }

        // Constraint: Ensure longest word fits in width
        // Estimate char width as ~0.75 of fontSize for bold text to prevent mid-word splitting
        // We use a conservative estimate because bold fonts are wide
        int maxWordLen = text
            .split(' ')
            .map((w) => w.length)
            .fold(0, (p, c) => p > c ? p : c);
        if (maxWordLen > 0) {
          // Subtract padding (8.0 on each side = 16.0)
          double maxFontSizeForWidth =
              (availableWidth - 16) / (maxWordLen * 0.75);
          if (fontSize > maxFontSizeForWidth) {
            fontSize = maxFontSizeForWidth;
          }
        }

        // Clamp to reasonable limits
        fontSize = fontSize.clamp(12.0, 90.0);

        // Sight words get a slight boost
        if (isSpecialSightWord) {
          fontSize = (fontSize * 1.1).clamp(12.0, 95.0);
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: textColor,
                height: 1.1, // Tighter line height for large text
                shadows: isSpecialSightWord
                    ? [
                        const Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 3,
                          color: Color(0x40000000),
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class TapInterfacePage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;
  final dynamic preloadedConfig;
  final List<String> preloadedWordOptions;
  final List<Map<String, String>> preloadedPhraseOptions;

  const TapInterfacePage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
    this.preloadedConfig,
    this.preloadedWordOptions = const [],
    this.preloadedPhraseOptions = const [],
  });

  @override
  State<TapInterfacePage> createState() => _TapInterfacePageState();
}

class _TapInterfacePageState extends State<TapInterfacePage> {
  static bool _didInitialTapCachePrep = false;
  static const _tapTranslations = <String, Map<String, String>>{
    'Something Else': {
      'es-US': 'Algo más',
      'fr-FR': 'Autre chose',
      'de-DE': 'Etwas anderes',
      'it-IT': 'Qualcos\'altro',
      'pt-BR': 'Outra coisa',
      'ar-XA': 'شيء آخر',
    },
    'Something Else A-Z': {
      'es-US': 'Algo más A-Z',
      'fr-FR': 'Autre chose A-Z',
      'de-DE': 'Etwas anderes A-Z',
      'it-IT': 'Qualcos\'altro A-Z',
      'pt-BR': 'Outra coisa A-Z',
      'ar-XA': 'شيء آخر أ-ي',
    },
    'Go Back': {
      'es-US': 'Regresar',
      'fr-FR': 'Retour',
      'de-DE': 'Zurück',
      'it-IT': 'Indietro',
      'pt-BR': 'Voltar',
      'ar-XA': 'رجوع',
    },
  };

  String _t(String key) {
    final provider = Provider.of<UserSettingsProvider>(context, listen: false);
    final locale = provider.settings?.userLanguage ?? 'en-US';
    return _tapTranslations[key]?[locale] ?? key;
  }

  static const Map<String, String> _localizedCategoryToCanonical = {
    // Spanish
    'ropa': 'clothing',
    'comida': 'food',
    'alimentos': 'food',
    'sentimientos': 'feelings',
    'emociones': 'feelings',
    'actividades': 'activities',
    'actividad': 'activities',
    'personas': 'people',
    'lugares': 'places',
    'acciones': 'actions',
    'necesidades': 'needs',
    'deseos': 'wants',
    'positivo': 'positive',
    'positivos': 'positive',
    'numeros': 'numbers',
    'números': 'numbers',
    'cantidades': 'numbers & quantities',
    'números y cantidades': 'numbers & quantities',
  };

  String _canonicalizeCategoryLabel(String label) {
    final normalized = label.trim().toLowerCase();
    return _localizedCategoryToCanonical[normalized] ?? normalized;
  }

  // --- Speech History ---
  String _speechHistory = "";
  final TextEditingController _speechHistoryController =
      TextEditingController();
  final List<String> _pastSpeechHistory =
      []; // Stores previously spoken phrases
  bool _isAudioSurfingEnabled = false;
  String? _audioSurfingPreviewOptionKey;

  // --- Current Build Space ---
  String _buildSpaceText = "";
  final TextEditingController _buildSpaceController = TextEditingController();

  // --- Performance Optimization ---
  final Map<String, String?> _imagePreloadCache =
      {}; // Cache for preloaded images
  bool _isPreloadingImages = false;

  Future<String?> _safeGetIdToken(
    User user, {
    bool forceRefresh = true,
  }) async {
    try {
      final token = await user
          .getIdToken(forceRefresh)
          .timeout(const Duration(seconds: 6));
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      debugPrint('[TapInterface] getIdToken(force=$forceRefresh) failed: $e');
    }

    if (forceRefresh) {
      try {
        final fallbackToken = await user
            .getIdToken()
            .timeout(const Duration(seconds: 4));
        if (fallbackToken != null && fallbackToken.isNotEmpty) {
          return fallbackToken;
        }
      } catch (e) {
        debugPrint('[TapInterface] getIdToken() fallback failed: $e');
      }
    }

    return null;
  }

  Future<void> _syncAuthContextForTap() async {
    try {
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );

      var effectiveUserId = widget.aacUserId.trim();
      var effectiveIdToken = widget.idToken.trim();

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        effectiveUserId =
            effectiveUserId.isNotEmpty ? effectiveUserId : user.uid;
        final refreshedToken = await _safeGetIdToken(user, forceRefresh: true);
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          effectiveIdToken = refreshedToken;
        } else {
          debugPrint(
            '[TapInterface] Auth token refresh failed in _syncAuthContextForTap; continuing with existing context.',
          );
        }
      }

      if (effectiveUserId.isNotEmpty) {
        userSettings.userId = effectiveUserId;
      }
      if (effectiveIdToken.isNotEmpty) {
        userSettings.idToken = effectiveIdToken;
      }

      if (effectiveUserId.isNotEmpty && effectiveIdToken.isNotEmpty) {
        PictogramService().setUserContext(
          userId: effectiveUserId,
          idToken: effectiveIdToken,
          mascot: userSettings.settings?.mascot,
        );
      }
    } catch (e) {
      debugPrint('[TapInterface] _syncAuthContextForTap failed safely: $e');
    }
  }

  // Cache for category options to avoid re-fetching
  final Map<String, List<Map<String, String>>> _categoryPhraseCache = {};
  final Map<String, List<String>> _categoryWordCache = {};
  final Map<String, Map<String, List<String>>> _categoryWordKeywordsCache = {};
  final Map<String, List<TapBoardButton>> _categoryBoardButtonsCache = {};
  final Map<String, List<String>> _categoryBrowseWordCache = {};
  final Map<String, Map<String, List<String>>> _categoryBrowseWordKeywordsCache =
      {};
  final Map<String, DateTime> _categoryOptionsCacheTimestamp = {};
  static const Duration _categoryOptionsCacheTtl = Duration(minutes: 10);
  // Stores the filtered AI dynamic words generated by _loadWordOptionsBasedOnBuildSpace
  // for each board, keyed by categoryCacheKey. Used to skip the AI word API call
  // on re-visits (e.g. Go Back) when board buttons are already cached.
  final Map<String, List<String>> _categoryAIWordCache = {};

  // --- New Tap Interface State ---
  TapInterfaceConfig? _tapConfig;
  TapBoardsResponse? _tapBoards;
  TapInterfaceCategory? _selectedCategory;
  List<String> _temporaryNavigationReturnStack = [];
  bool _temporaryNavigationPending = false;
  // Breadcrumb stack for the Go Back button — each entry is
  // (boardId, textAddedToSpeech) so Go Back can undo the exact phrase.
  List<({String boardId, String addedText})> _navigationBreadcrumbs = [];
  String? _activeBoardModifierBoardId;
  String? _activeBoardModifierId;

  // --- Option Display State ---
  List<Map<String, String>> _phraseOptions =
      []; // Top rows - {summary, fullText}
  List<String> _wordOptions = []; // Dynamic word rows - AI-generated words
  // Accumulates all words ever shown so Something Else never repeats them.
  // Reset when the category/board changes.
  final Set<String> _usedWordOptions = {};
  List<TapBoardButton> _boardWordOptions =
      []; // Static word rows - board-backed buttons

  // --- Past / Plural variant mode ---
  // null = normal, 'past' = show pastTense variants, 'plural' = show plural variants
  String? _variantMode;

  // 'left' | 'right' | 'top' | 'bottom'  — stored in SharedPreferences.
  String _menuPosition = 'left';

  // Minimum tap hold duration in ms — stored in SharedPreferences.
  // 0 = instant (no filter), 100/200/300 = increasing sensitivity filter.
  int _tapMinDurationMs = 0;

  // Tracks when the most recent pointer-down on an action-bar button occurred,
  // used by _withSensitivity to enforce the minimum tap duration.
  DateTime? _actionBarPointerDownTime;

  /// Wraps [fn] with the same minimum-hold-duration check used by TapInterfaceButton.
  void Function() _withSensitivity(void Function() fn) {
    return () {
      final minMs = TapInterfaceButton.tapMinDurationMs;
      if (minMs <= 0) {
        fn();
        return;
      }
      final down = _actionBarPointerDownTime;
      if (down != null &&
          DateTime.now().difference(down).inMilliseconds >= minMs) {
        HapticFeedback.mediumImpact();
        fn();
      }
    };
  }

  // Session-wide cache keyed as '$mode:$originalWord' → variant form.
  final Map<String, String> _variantCache = {};
  bool _variantApplyInProgress = false;
  Map<String, List<String>> _wordKeywords =
      {}; // Keywords for each word option to improve image matching
  int _optionsRebuildKey = 0; // Force UI rebuild when options change
  bool _isJokesMode =
      false; // Track if we're showing jokes (for Something Else handling)
  String?
  _activeWordLetterFilter; // Persist selected A-Z filter for Something Else refreshes

  bool _isLoadingPhraseOptions = false; // Separate loading state for phrases
  bool _isLoadingWordOptions = false; // Separate loading state for words
  bool _cacheOnlyInitialImageLookup = false;
  // bool _isLoadingOptions = false;       // General loading state for operations affecting both sections
  bool _isLoadingConfig = false;
  String? _lastInitialWordOptionsLocale;
  bool _isRefreshingInitialWordOptionsForLocale = false;

  // --- Speech Bubble Overlay Variables ---
  bool _showSpeechBubble = false;
  String _speechBubbleText = '';
  Timer? _speechBubbleTimer;

  // --- Admin State ---
  bool _isAdminToolbarLocked = true;
  String _currentPIN = '1234'; // Default PIN
  int _pinAttempts = 0; // Track failed PIN attempts

  // --- Floating status toast ---
  Timer? _statusToastTimer;

  // --- TTS ---
  late FlutterTts _flutterTts;
  static bool _audioSessionInitialized = false;
  static bool _partnerVoiceWarmupCompleted = false;
  static String _partnerVoiceWarmupKey = '';

  // --- Services ---
  late TapInterfaceService _tapService;

  // --- Wake Word Service ---
  WakeWordService? _wakeWordService;
  bool _isListeningForWakeWord = false;
  bool _isListeningForQuestion = false;
  bool _isHandlingWakeWordTurn = false;
  String _currentQuestion = '';
  String _statusMessage = '';

  // --- Retry Logic (matching main.dart) ---
  int _llmRetryCount = 0;
  static const int _maxLLMRetries = 2;
  String? _lastQuestion;

  // --- Text Prompt Tracking ---
  bool _textPromptUsed = false; // Track if the text prompt has been used once

  // --- Schedule Check ---
  Timer? _scheduleCheckTimer;
  final Set<String> _handledSchedules = {};

  // --- Tap Debounce ---
  Timer? _tapDebounceTimer;
  bool _isTapInProgress = false;
  static const int _tapDebounceMs = 900; // Debounce tap handlers for 900ms

  // --- Session-based Missing Image Deduplication ---
  final Set<String> _sessionLoggedMissingImages =
      {}; // Track which images we've logged in this session
  final Map<String, String> _translationCache =
      {}; // Cache user->partner translations for fast repeats

  static const Map<String, String> _localeLabelToTag = {
    'english (us)': 'en-US',
    'spanish (us)': 'es-US',
    'french (france)': 'fr-FR',
    'german (germany)': 'de-DE',
    'italian (italy)': 'it-IT',
    'portuguese (brazil)': 'pt-BR',
    'arabic': 'ar-XA',
  };

  @override
  void initState() {
    super.initState();
    // Clear session-based missing image tracking for a fresh start
    _globalSessionLoggedMissingImages.clear();
    debugPrint('🔄 Cleared session missing image tracking on page init');

    _flutterTts = FlutterTts();
    _buildSpaceController.addListener(_onBuildSpaceChange);
    _speechHistoryController.addListener(_onSpeechHistoryChange);

    // Initialize services
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    unawaited(_syncAuthContextForTap());
    _tapService = TapInterfaceService(userSettingsProvider: userSettings);

    // Initialize Wake Word Service
    _initializeWakeWordService();

    // Initialize PIN from user settings
    _updatePINFromSettings(userSettings);

    // Start schedule check
    _startScheduleCheck();

    // Load locally-stored preferences.
    SharedPreferences.getInstance().then((prefs) {
      final savedPosition = prefs.getString('tap_menu_position') ?? 'left';
      final savedSensitivity = prefs.getInt('tap_min_duration_ms') ?? 0;
      debugPrint('[TapSensitivity] Loaded from SharedPreferences: tap_min_duration_ms=$savedSensitivity');
      TapInterfaceButton.tapMinDurationMs = savedSensitivity;
      debugPrint('[TapSensitivity] Static set to: ${TapInterfaceButton.tapMinDurationMs}');
      if (mounted) {
        setState(() {
          _menuPosition = savedPosition;
          _tapMinDurationMs = savedSensitivity;
        });
      }
    });

    // Load tap interface configuration
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncAuthContextForTap();
      // Refresh settings on page entry so language-dependent Tap requests
      // (words/phrases/image locale) use the latest user profile values.
      try {
        await userSettings
            .fetchSettings()
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint(
          '[TapInterface] Settings refresh timed out/failed on startup: $e',
        );
      }

      // Never block Tap startup on location override hydration.
      unawaited(_hydrateLocationOverrideFromCurrentUser());
      if (!mounted) return;
      final locale = userSettings.settings?.userLanguage ?? 'en-US';

      // Start Tap config loading immediately. Cache prep runs in background.
      _loadTapInterfaceConfig(); // word loading is handled inside after config resolves

      if (!_didInitialTapCachePrep) {
        unawaited(() async {
          try {
            await _clearAllCaches().timeout(const Duration(seconds: 8));
            if (!locale.startsWith('en')) {
              await PictogramService().prefetchLocaleImages(locale).timeout(
                const Duration(seconds: 8),
              );
            }
          } catch (e) {
            debugPrint('[TapInterface] Initial cache prep timed out/failed: $e');
          }
        }());
        _didInitialTapCachePrep = true;
      } else {
        if (!locale.startsWith('en')) {
          unawaited(
            PictogramService().prefetchLocaleImages(locale).timeout(
              const Duration(seconds: 8),
            ),
          );
        }
      }
      _primeAudioSystem();
      _initializeAudioSessionProactively();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final settingsProvider = Provider.of<UserSettingsProvider>(context);
    final currentLocale =
        _normalizeLocaleTag(settingsProvider.settings?.userLanguage) ??
        'en-US';

    if (_tapConfig == null || _isLoadingConfig) {
      return;
    }

    if (_selectedCategory != null || _wordOptions.isEmpty) {
      return;
    }

    if (_lastInitialWordOptionsLocale == currentLocale ||
        _isRefreshingInitialWordOptionsForLocale) {
      return;
    }

    _isRefreshingInitialWordOptionsForLocale = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || _selectedCategory != null) return;
        debugPrint(
          '[TapInterface] Refreshing initial word options for locale $currentLocale',
        );
        await _loadInitialFreestyleOptions();
      } finally {
        _isRefreshingInitialWordOptionsForLocale = false;
      }
    });
  }

  String? _normalizeLocaleTag(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final labelMatch = _localeLabelToTag[raw.toLowerCase()];
    if (labelMatch != null) return labelMatch;

    final cleaned = raw.replaceAll('_', '-');
    final match = RegExp(
      r'^([a-zA-Z]{2})(?:-([a-zA-Z]{2,3}))?$',
    ).firstMatch(cleaned);
    if (match == null) return null;

    final language = match.group(1)!.toLowerCase();
    final region = match.group(2)?.toUpperCase();
    return region == null ? language : '$language-$region';
  }

  void _applyLocationOverrideLocale(dynamic localeValue) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final normalizedLocale = _normalizeLocaleTag(localeValue);

    if (normalizedLocale == null) {
      settingsProvider.clearLocationOverride();
      return;
    }

    final configuredEntry = settingsProvider.settings?.locationOverrideLanguages
        .firstWhere(
          (e) => e.locale == normalizedLocale,
          orElse: () =>
              LocationLanguageEntry(locale: normalizedLocale, voice: ''),
        );

    settingsProvider.setLocationOverride(
      normalizedLocale,
      configuredEntry?.voice ?? '',
    );
  }

  Future<void> _hydrateLocationOverrideFromCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String idToken = widget.idToken;
      if (user != null) {
        final refreshedToken = await _safeGetIdToken(user, forceRefresh: true);
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          idToken = refreshedToken;
        }
      }

      final response = await http
          .get(
            Uri.parse('${EnvironmentConfig.apiBaseUrl}/get-user-current'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'X-User-ID': widget.aacUserId,
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _applyLocationOverrideLocale(data['locationLanguageOverride']);
      }
    } catch (e) {
      debugPrint('🔄 TAP INTERFACE: Failed to hydrate location override: $e');
    }
  }

  /// Comprehensive validation method to catch any remaining duplicates
  void _validateWordOptions() {
    final wordsLower = <String>{};
    final duplicates = <String>[];

    for (final word in _wordOptions) {
      final lowerWord = word.toLowerCase();
      if (wordsLower.contains(lowerWord)) {
        duplicates.add(word);
      } else {
        wordsLower.add(lowerWord);
      }
    }

    if (duplicates.isNotEmpty) {
      debugPrint(
        '🚨 VALIDATION FAILED: Found ${duplicates.length} duplicates in _wordOptions:',
      );
      debugPrint('🚨 Duplicates: $duplicates');
      debugPrint('🚨 Full _wordOptions: $_wordOptions');

      // Auto-fix by running deduplication
      final fixedOptions = _deduplicateWords(_wordOptions);
      if (fixedOptions.length != _wordOptions.length) {
        debugPrint(
          '🔧 AUTO-FIX: Deduplicating _wordOptions (${_wordOptions.length} → ${fixedOptions.length})',
        );
        setState(() {
          _wordOptions = fixedOptions;
        });
      }
    } else {
      debugPrint(
        '✅ VALIDATION PASSED: No duplicates found in _wordOptions (${_wordOptions.length} words)',
      );
    }
  }

  /// Calculate effective crossAxisCount for main content sections that accounts for Categories column
  ///
  /// The layout uses flex 1:9 ratio (Categories:MainContent). To ensure consistent button sizes,
  /// we need to account for the Categories column when calculating button sizes for the main content.
  ///
  /// For example: if admin setting is 6 columns, the effective layout should be:
  /// - Categories: 1 column (takes 1/10 of width)
  /// - Main content: 6 columns (takes 9/10 of width)
  ///
  /// This ensures all buttons appear the same visual size across sections.
  int _getEffectiveMainContentColumns(int adminColumns) {
    // The main content area gets 9/10 of the total width (flex: 9 vs flex: 1 for categories)
    // To maintain consistent button sizing, we use the admin setting directly for the main content area
    return adminColumns;
  }

  /// Calculate aspect ratio that ensures Categories buttons match main content button heights
  ///
  /// Categories uses 1 column in 1/10 width, Main content uses N columns in 9/10 width
  /// To make buttons the same visual size: categoryAspectRatio = mainAspectRatio * (mainColumns / 1) * (1/10) / (9/10)
  /// Simplified: categoryAspectRatio = mainAspectRatio * mainColumns / 9
  /// Calculate Phrases section layout based on tapPhrasesRows setting
  Map<String, int> _calculatePhraseSectionLayout(
    int tapPhrasesRows,
    int gridColumns,
  ) {
    if (tapPhrasesRows == 0) {
      return {'rows': 0, 'flex': 0}; // Hidden
    }

    final rows = tapPhrasesRows;
    final flex = rows <= 1 ? 0 : (rows == 2 ? 2 : 3);

    debugPrint(
      '📊 Phrases Layout: tapPhrasesRows=$tapPhrasesRows, columns=$gridColumns, rows=$rows, flex=$flex',
    );
    return {'rows': rows, 'flex': flex};
  }

  /// Total phrase button slots = tapPhrasesRows × gridColumns
  int _phraseSlotCount(UserSettings? userSettings) {
    final rows = userSettings?.tapPhrasesRows ?? 0;
    final cols = _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6);
    return rows * cols;
  }

  /// Returns the text labels of board buttons currently visible in static rows.
  /// Used to tell the LLM what to exclude from dynamic suggestions.
  List<String> _displayedStaticButtonLabels(UserSettings? userSettings) {
    if (_boardWordOptions.isEmpty) return [];
    final totalRows = userSettings?.tapWordsRows ?? 3;
    final dynamicRows = userSettings?.tapDynamicRows ?? 1;
    final staticRows = (totalRows - dynamicRows).clamp(0, totalRows);
    if (staticRows == 0) return [];
    // Use row field directly — avoids column-count mismatch between settings and board layout.
    return _boardWordOptions
        .where(
          (btn) =>
              btn.row < staticRows &&
              !btn.hidden &&
              !btn.isNavigationButton &&
              btn.text.isNotEmpty,
        )
        .map((btn) => btn.text)
        .toList();
  }

  /// Total words button slots = tapWordsRows × gridColumns
  int _wordsSlotCount(UserSettings? userSettings) {
    final rows = userSettings?.tapWordsRows ?? 3;
    final cols = _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6);
    return rows * cols;
  }

  /// Static word slots (board buttons) = (tapWordsRows - tapDynamicRows) × gridColumns
  int _staticWordSlotCount(UserSettings? userSettings) {
    final total = userSettings?.tapWordsRows ?? 3;
    final dynamic = userSettings?.tapDynamicRows ?? 1;
    final cols = _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6);
    return (total - dynamic).clamp(0, total) * cols;
  }

  /// Calculate flex value for Words section based on Phrases section size
  int _calculateWordsSectionFlex(UserSettings? userSettings) {
    final tapPhrasesRows = userSettings?.tapPhrasesRows ?? 0;

    if (tapPhrasesRows == 0) return 1;
    if (tapPhrasesRows <= 2) return 1;
    return 2;
  }

  /// Calculate the proper height for single-row phrases section
  double _calculateSingleRowPhrasesHeight(UserSettings? userSettings) {
    // Component heights:
    const headerHeight = 0.0; // Header removed
    const gridPadding = 6.0; // 3px padding all around
    const containerBorder = 4.0; // 2px border top + bottom
    const extraBottomPadding =
        10.0; // Extra padding to ensure buttons aren't cut off

    // Calculate button height based on aspect ratio
    // Note: In a real layout, button width would be (available_width / columns)
    // For estimation, we'll use a reasonable assumption based on typical screen width
    final columns = _getEffectiveMainContentColumns(
      userSettings?.gridColumns ?? 6,
    );
    const assumedAvailableWidth =
        800.0; // Reasonable assumption for main content width
    final buttonWidth = assumedAvailableWidth / columns;
    final buttonHeight =
        buttonWidth / 1.1; // aspect ratio is 1.1 (width/height)

    final totalHeight =
        headerHeight +
        buttonHeight +
        gridPadding +
        containerBorder +
        extraBottomPadding;

    debugPrint(
      '📐 Phrases Height Calculation: header=$headerHeight, buttonH=$buttonHeight (buttonW=$buttonWidth, cols=$columns), padding=$gridPadding, border=$containerBorder, extraPadding=$extraBottomPadding = total=$totalHeight',
    );

    return totalHeight;
  }


  /// Build the Phrases section widget. Height is set by the caller (SizedBox).
  Widget _buildPhrasesSection(
    UserSettings? userSettings,
    double buttonSize,
    double gridWidth,
  ) {
    final tapPhrasesRows = userSettings?.tapPhrasesRows ?? 0;

    if (tapPhrasesRows == 0) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green[25] ?? Colors.green.shade50,
            Colors.green[50] ?? Colors.green.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.green[300] ?? Colors.green.shade300,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            offset: const Offset(0, 3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: gridWidth,
            child: Stack(
              children: [
                if (_phraseOptions.isNotEmpty && !_isLoadingPhraseOptions)
                  _buildPhrasesGrid(userSettings)
                else if (!_isLoadingPhraseOptions)
                  const Center(
                    child: Text(
                      'No phrases available',
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ),
                if (_isLoadingPhraseOptions)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the phrases grid with consistent button generation
  static const Set<String> _phraseImageWeakTerms = {
    'i',
    'me',
    'my',
    'mine',
    'myself',
    'you',
    'your',
    'yours',
    'he',
    'she',
    'it',
    'we',
    'they',
    'am',
    'is',
    'are',
    'was',
    'were',
    'be',
    'being',
    'been',
    'do',
    'does',
    'did',
    'can',
    'could',
    'will',
    'would',
    'should',
    'may',
    'might',
    'must',
    'like',
    'want',
    'need',
    'have',
    'has',
    'had',
    'get',
    'go',
    'come',
    'make',
    'say',
    'tell',
    'think',
    'know',
    'feel',
    'please',
    'help',
    'the',
    'a',
    'an',
    'to',
    'for',
    'of',
    'in',
    'on',
    'at',
    'with',
    'and',
    'or',
    'but',
  };

  String _normalizePhraseImageToken(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"^[^a-z0-9']+|[^a-z0-9']+$"), '');
  }

  String? _derivePhraseImageSearchText(String fullText, List<String>? keywords) {
    final keywordList = keywords ?? const <String>[];

    for (final keyword in keywordList) {
      final normalized = _normalizePhraseImageToken(keyword);
      if (normalized.isEmpty) continue;
      if (_phraseImageWeakTerms.contains(normalized)) continue;
      return normalized;
    }

    final words = fullText
        .split(RegExp(r'\s+'))
        .map(_normalizePhraseImageToken)
        .where((w) => w.isNotEmpty)
        .toList();

    for (var i = words.length - 1; i >= 0; i--) {
      final word = words[i];
      if (_phraseImageWeakTerms.contains(word)) continue;
      return word;
    }

    for (final keyword in keywordList) {
      final normalized = _normalizePhraseImageToken(keyword);
      if (normalized.isNotEmpty) return normalized;
    }

    return fullText.trim().isEmpty ? null : fullText.trim();
  }

  Widget _buildPhrasesGrid(UserSettings? userSettings) {
    final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
    final tapPictogramsEnabled = !tapPictogramsDisabled;
    final tapSightWordLogicEnabled =
        !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: _getEffectiveMainContentColumns(
        userSettings?.gridColumns ?? 6,
      ),
      childAspectRatio: 1.0,
      crossAxisSpacing: 2,
      mainAxisSpacing: 2,
      children: List.generate(_phraseSlotCount(userSettings) + 1, (index) {
        if (index == _phraseSlotCount(userSettings)) {
          return TapInterfaceButton(
            label: _t('Something Else'),
            onPressed: () => _loadMorePhraseOptions(),
            backgroundColor: Colors.green[50] ?? Colors.green.shade50,
            foregroundColor: Colors.black87,
            borderColor: Colors.green[300] ?? Colors.green.shade300,
            fontSize: 8,
            enablePictograms: tapPictogramsEnabled,
            sightWordGradeLevel: userSettings?.sightWordGradeLevel,
            enableSightWords: tapSightWordLogicEnabled,
            padding: const EdgeInsets.all(2),
            shouldLogMissing:
                false, // Don't log missing images for dynamic buttons
            cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
            mascot: userSettings?.mascot ?? '',
          );
        } else if (index < _phraseOptions.length) {
          final phraseOption = _phraseOptions[index];
          final fullText = phraseOption['fullText'] ?? '';
          final isPreviewArmed =
              _isAudioSurfingEnabled &&
              _audioSurfingPreviewOptionKey == 'phrase::$fullText';
          final keywordsString = phraseOption['keywords'] ?? '';
          final keywords = keywordsString.isNotEmpty
              ? keywordsString
                    .split('|')
                    .where((s) => s.trim().isNotEmpty)
                    .toList()
              : null;
          final phraseImageSearchText = _derivePhraseImageSearchText(
            fullText,
            keywords,
          );

          return TapInterfaceButton(
            label: phraseOption['summary'] ?? '',
            imageSearchText: phraseImageSearchText,
            onPressed: () => _handlePhraseOptionTap(fullText),
            backgroundColor: isPreviewArmed
                ? (Colors.amber[300] ?? Colors.amber.shade300)
                : (Colors.green[50] ?? Colors.green.shade50),
            foregroundColor: Colors.black87,
            borderColor: isPreviewArmed
                ? (Colors.deepOrange[700] ?? Colors.deepOrange.shade700)
                : (Colors.green[300] ?? Colors.green.shade300),
            fontSize: 8,
            enablePictograms: tapPictogramsEnabled,
            sightWordGradeLevel: userSettings?.sightWordGradeLevel,
            enableSightWords: tapSightWordLogicEnabled,
            padding: const EdgeInsets.all(2),
            keywords: keywords,
            shouldLogMissing:
                false, // Don't log missing images for LLM-generated phrases
            cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
            mascot: userSettings?.mascot ?? '',
          );
        } else {
          return Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.green[200] ?? Colors.green.shade200,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                '—',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          );
        }
      }),
    );
  }


  /// Calculate appropriate column count for modal dialog based on its smaller size
  ///
  /// Modal constraints: maxWidth: 495px vs full screen width
  /// We need to scale down the column count proportionally to maintain similar button sizes
  int _getModalColumnCount(int adminColumns) {
    // Now that modal width is responsive, we can use a more direct relationship
    // Fewer admin columns = larger buttons = fewer modal columns for larger buttons
    // More admin columns = smaller buttons = more modal columns for smaller buttons
    if (adminColumns <= 3) return 2; // Very large buttons -> 2 columns
    if (adminColumns <= 6) return 3; // Medium-large buttons -> 3 columns
    if (adminColumns <= 10) return 4; // Medium buttons -> 4 columns
    if (adminColumns <= 14) return 5; // Small buttons -> 5 columns
    return 6; // Very small buttons -> 6 columns
  }

  @override
  void dispose() {
    _buildSpaceController.dispose();
    _speechHistoryController.dispose();
    _speechBubbleTimer?.cancel(); // Clean up speech bubble timer
    _scheduleCheckTimer?.cancel(); // Clean up schedule check timer
    _tapDebounceTimer?.cancel(); // Clean up tap debounce timer
    _flutterTts.stop();

    // Don't stop the wake word service completely since grid page may still need it
    // Just clear our callbacks so grid page can take over again
    if (_wakeWordService != null) {
      print('TapInterface: Cleaning up wake word callbacks on dispose');
      // Reset callbacks to null so grid page can set them again
      _wakeWordService!.onWakeWord = null;
      _wakeWordService!.onQuestion = null;
      _wakeWordService!.shouldAllowWakeWordRestart = null;
    }

    super.dispose();
  }

  // --- Wake Word Service Methods ---
  // Wake Word functionality has been successfully integrated into the tap interface
  // Following the same patterns as the grid page implementation
  void _initializeWakeWordService() {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );

    // Check if we have wake word settings (using the actual property names)
    if (userSettings.settings?.wakeWordName.isNotEmpty == true) {
      // Use the existing global wake word service instance from main.dart
      // This ensures we don't create competing instances
      _wakeWordService = WakeWordService.getCurrentInstance();

      if (_wakeWordService != null) {
        print('TapInterface: Using existing wake word service instance');
        WakeWordService.setWakeWordLocale(
          userSettings.effectivePartnerLanguage,
        );
        _setupWakeWordCallbacks();
        _startWakeWordListening();
      } else {
        print(
          'TapInterface: No existing wake word service found, creating new one',
        );
        // Fallback: create new instance if none exists
        final wakeWordInterjection =
            (userSettings.settings?.wakeWordInterjection ?? 'hey')
                .trim()
                .toLowerCase();
        final wakeWordName = (userSettings.settings?.wakeWordName ?? 'bravo')
            .trim()
            .toLowerCase();
        final wakeWordVariants = <String>{
          '$wakeWordInterjection $wakeWordName',
          '$wakeWordInterjection, $wakeWordName',
          '$wakeWordInterjection,$wakeWordName',
          'hey $wakeWordName',
          'hey, $wakeWordName',
          'hey,$wakeWordName',
        }.toList();

        WakeWordService.setWakeWordLocale(
          userSettings.effectivePartnerLanguage,
        );

        _wakeWordService = WakeWordService(wakeWords: wakeWordVariants);
        _setupWakeWordCallbacks();
        _startWakeWordListening();
      }
    }
  }

  void _setupWakeWordCallbacks() {
    if (_wakeWordService == null) return;

    print(
      'TapInterface: Setting up wake word callbacks to override grid page callbacks',
    );

    _wakeWordService!.onWakeWord = (transcript) async {
      print('TapInterface: Wake word detected: $transcript');

      if (!mounted) return;

      setState(() {
        _isHandlingWakeWordTurn = true;
        _isListeningForQuestion = false;
        _isListeningForWakeWord = false;
      });
      _showStatusToast('Wake word heard! Preparing to listen...');

      // Mirror grid behavior: play the listening prompt first, then begin
      // question capture so we do not transcribe the app's own cue.
      _wakeWordService?.pauseWakeWordAutoRestart();

      try {
        await _announceViaBackend(
          "I'm listening",
          sourceLocaleOverride: 'en-US',
        );

        if (!mounted) return;

        setState(() {
          _isListeningForQuestion = true;
        });
        _showStatusToast('Listening for your question...');

        final partnerLocale = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        ).effectivePartnerLanguage;

        await _wakeWordService?.startQuestionListening(localeId: partnerLocale);
      } catch (e) {
        debugPrint('[TapInterface] Wake-word question setup failed: $e');
        if (mounted) {
          setState(() {
            _isListeningForQuestion = false;
            _isHandlingWakeWordTurn = false;
          });
        }
        _startWakeWordListening();
      }
    };

    _wakeWordService!.onQuestion = (question) async {
      print('TapInterface: Question detected: $question');

      if (!mounted) return;

      // Mirror grid behavior: translate partner speech into the AAC user's
      // language before updating UI and generating options.
      String translatedQuestion = question;
      final langProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final userLang = langProvider.settings?.userLanguage ?? 'en-US';
      final partnerLang = langProvider.effectivePartnerLanguage;

      if (userLang != partnerLang) {
        translatedQuestion = await _translateForPartner(
          question,
          fromLocale: partnerLang,
          toLocale: userLang,
          idToken: widget.idToken,
          aacUserId: widget.aacUserId,
        );
        debugPrint(
          '[TapInterface] onQuestion translated "$question" ($partnerLang->$userLang) -> "$translatedQuestion"',
        );
      }

      setState(() {
        _currentQuestion = translatedQuestion;
        _isListeningForQuestion = false;
        _isHandlingWakeWordTurn = true;
        _statusMessage = '';
      });

      // Show the question in speech bubble
      _showSpeechBubbleOverlay(translatedQuestion);

      // START GENERATING OPTIONS IMMEDIATELY (don't wait)
      // This runs in parallel with the announcement
      final optionGenerationFuture = _generateOptionsFromQuestion(
        translatedQuestion,
      );

      if (translatedQuestion != question) {
        // Prompt the AAC user in their own language using local system-voice audio
        // at 50% volume (same as Preview feature), matching grid page's _speakPersonalVoice.
        // Uses 0.5 speech rate for clarity (matches grid page standard).
        await _announceLowVolumeSystemAudio(
          translatedQuestion,
          volumeScale: 0.5,
          speechRate: 0.5,
        );
      } else {
        // Announce processing acknowledgment in partner language.
        await _announceViaBackend(
          'Okay, processing your question. Give me a moment.',
          sourceLocaleOverride: 'en-US',
        );
      }

      // Now wait for options to complete (if not done already)
      await optionGenerationFuture;

      // Resume wake word listening
      if (mounted) {
        setState(() {
          _isHandlingWakeWordTurn = false;
        });
      }
      _startWakeWordListening();
    };

    _wakeWordService!.onAnnounce = (message) {
      if (!mounted) return;

      // Clear stale question-listening UI before speaking timeout/error prompts.
      setState(() {
        _isListeningForQuestion = false;
        _isHandlingWakeWordTurn = true;
        _statusMessage = '';
      });

      unawaited(
        _announceViaBackend(
          message,
          sourceLocaleOverride: 'en-US',
        ),
      );
    };

    _wakeWordService!.onTimeout = () {
      if (!mounted) return;

      setState(() {
        _isListeningForQuestion = false;
        _isHandlingWakeWordTurn = false;
        _statusMessage = '';
      });

      _startWakeWordListening();
    };

    _wakeWordService!.onStatusBarUpdate = (heardText) {
      if (!mounted) return;
      // IMPORTANT: Do not show wake-word phase transcription on the status bar.
      // Transcription should only appear after wake word is heard.
    };

    _wakeWordService!.onQuestionStatusUpdate = (questionText) {
      if (!mounted || !_isListeningForQuestion) return;
      if (questionText.trim().isEmpty) return;

      _showStatusToast('Hearing: "$questionText"');
    };

    _wakeWordService!.shouldAllowWakeWordRestart = () {
      return !_isListeningForQuestion && !_isHandlingWakeWordTurn && mounted;
    };

    print('TapInterface: Wake word callbacks setup complete');
  }

  void _startWakeWordListening() async {
    if (_wakeWordService == null) return;

    // Ensure global wake-word gate is open before attempting to listen.
    WakeWordService.wakeWordShouldBeActive = true;

    setState(() {
      _isListeningForQuestion = false;
      _isListeningForWakeWord = true;
      _statusMessage = '';
    });

    _wakeWordService!.resumeWakeWordAutoRestart();
    await _wakeWordService!.startWakeWordListening();
  }

  Future<void> _generateOptionsFromQuestion(String question) async {
    try {
      print(
        '[TapInterface] _generateOptionsFromQuestion: Starting for question: "$question"',
      );

      // Store question for retry if this is the first attempt
      if (_llmRetryCount == 0) {
        _lastQuestion = question;
        print('[TapInterface] 🔄 Stored question for potential retry');
      } else {
        print('[TapInterface] 🔄 Retry attempt #$_llmRetryCount');
      }

      // Get current category context
      String categoryContext = _selectedCategory?.label ?? 'general';

      // Generate phrase options using existing LLM method with mood context
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';

      String phraseContext =
          'answering the question: "$question" in the context of $categoryContext';
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        phraseContext =
            'answering the question: "$question" in the context of $categoryContext while feeling $currentMood';
      }

      print(
        '[TapInterface] Generating phrase options with context: $phraseContext',
      );

      // START BOTH API CALLS IN PARALLEL (like category selection does)
      final phraseFuture = _tapService.generateLLMPhraseOptions(
        context: phraseContext,
        maxOptions:
            20, // Request more to ensure we have enough for 17 display slots
        currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
      );

      // Get required word count
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;

      // Generate word options using generateCategoryWords (same as category selection)
      // CRITICAL FIX: Use the full question as category (matching web app behavior)
      // This prevents "Who is your favorite superhero" from being reduced to "people and family members"
      String categoryForWords = question;

      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        categoryForWords = '$categoryForWords (feeling $currentMood)';
      }

      print(
        '[TapInterface] Generating word options for question: $categoryForWords',
      );

      final wordFuture = _tapService.generateCategoryWords(
        category: categoryForWords,
        buildSpaceContent: _buildSpaceText,
        excludeWords: [],
        maxOptions: requiredWordCount + 15, // Request extra for deduplication
        requestDifferentOptions: false,
        currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
      );

      // Wait for BOTH to complete in parallel
      print(
        '[TapInterface] Waiting for phrase and word options to generate in parallel...',
      );
      final results = await Future.wait([phraseFuture, wordFuture]);
      final phraseOptions = results[0] as List<Map<String, String>>;
      final wordOptionsStrings = results[1] as List<String>;

      print('[TapInterface] Received ${phraseOptions.length} phrase options');
      print(
        '[TapInterface] Received ${wordOptionsStrings.length} word options',
      );

      if (!mounted) {
        print('[TapInterface] Widget unmounted, aborting option update');
        return;
      }

      // Successful generation - reset retry counter
      _llmRetryCount = 0;
      _lastQuestion = null;

      // Build final word list outside setState (async-safe)
      final deduplicatedWords = _deduplicateWords(wordOptionsStrings);
      debugPrint(
        'TapInterface: Original words: ${wordOptionsStrings.length}, Deduplicated: ${deduplicatedWords.length}',
      );

      final preLocalizedWords = <String>[
        ...deduplicatedWords.take(requiredWordCount),
      ];

      if (preLocalizedWords.length < requiredWordCount) {
        print(
          '[TapInterface] Adding ${requiredWordCount - preLocalizedWords.length} fallback words',
        );
        final fallbackWords = _getFallbackWordOptions();
        final currentWordsLower = preLocalizedWords
            .map((w) => w.toLowerCase())
            .toSet();

        final uniqueFallbacks = fallbackWords
            .where((word) => !currentWordsLower.contains(word.toLowerCase()))
            .toList();

        final neededCount = requiredWordCount - preLocalizedWords.length;
        preLocalizedWords.addAll(uniqueFallbacks.take(neededCount));
      }

      final localizedQuestionWords = await _localizeWordsForUserIfNeeded(
        preLocalizedWords,
      );
      final finalQuestionWords = _deduplicateWords(localizedQuestionWords)
          .take(requiredWordCount)
          .toList();

      setState(() {
        // Update phrase options (top 2 rows) - need exactly 17 for proper display
        _phraseOptions.clear();
        print('[TapInterface] Adding ${phraseOptions.length} phrase options');
        _phraseOptions.addAll(phraseOptions.take(17));

        // If we don't have enough phrase options, add fallbacks
        if (_phraseOptions.length < 17) {
          print(
            '[TapInterface] Adding ${17 - _phraseOptions.length} fallback phrases',
          );
          final fallbackPhrases = [
            'I understand',
            'Tell me more',
            'That makes sense',
            'I see',
            'Good point',
            'Can you explain?',
            'What do you think?',
            'I agree',
            'Interesting',
            'Thank you',
            'You\'re right',
            'I need help',
            'Let me think',
            'That\'s good',
            'I\'m not sure',
            'Maybe',
            'Okay',
          ];
          final neededCount = 17 - _phraseOptions.length;
          final additionalPhrases = fallbackPhrases
              .take(neededCount)
              .map(
                (text) => {
                  'summary': text.length > 30
                      ? '${text.substring(0, 30)}...'
                      : text,
                  'fullText': text,
                },
              )
              .toList();
          _phraseOptions.addAll(additionalPhrases);
        }

        print(
          '[TapInterface] Final phrase options count: ${_phraseOptions.length}',
        );

        // Update word options (bottom 3 rows)
        _wordOptions.clear();
        _wordKeywords.clear(); // Clear keywords when clearing word options
        _wordOptions.addAll(finalQuestionWords);

        print(
          '[TapInterface] Final word options count: ${_wordOptions.length}',
        );

        // Update status message to show options are ready
        _statusMessage =
            'Options ready! Tap to select, or say "${_getFormattedWakeWord()}" to ask a question.';
      });

      print(
        '[TapInterface] _generateOptionsFromQuestion: Completed successfully',
      );

      // Show success feedback
      _showSpeechBubbleOverlay('I found some options for you!');
    } catch (e, stackTrace) {
      print('[TapInterface] ERROR in _generateOptionsFromQuestion: $e');
      print('[TapInterface] Stack trace: $stackTrace');
      print(
        '[TapInterface] 🚨 ERROR DETAILS: retryCount=$_llmRetryCount, maxRetries=$_maxLLMRetries, hasStoredQuestion=${_lastQuestion != null}',
      );

      if (!mounted) return;

      // Retry logic matching main.dart
      if (_llmRetryCount < _maxLLMRetries && _lastQuestion != null) {
        _llmRetryCount++;
        print(
          '[TapInterface] 🔄 RETRY #$_llmRetryCount: Attempting retry after error...',
        );

        setState(() {
          _statusMessage =
              'Processing failed - Retrying ($_llmRetryCount/$_maxLLMRetries)...';
        });

        // Wait a moment before retrying
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          print(
            '[TapInterface] 🔄 RETRY #$_llmRetryCount: Re-executing question generation',
          );
          // Recursively retry with the stored question
          await _generateOptionsFromQuestion(_lastQuestion!);
        }
        return; // Exit to prevent showing error message during retry
      }

      // All retries exhausted or no stored question
      print(
        '[TapInterface] 🚨 FINAL FAILURE: All retries exhausted ($_llmRetryCount attempts) or no stored question',
      );
      _llmRetryCount = 0;
      _lastQuestion = null;

      _showSpeechBubbleOverlay(
        'Sorry, I had trouble understanding. Let me try again.',
      );
      setState(() {
        _statusMessage =
            'Say "${_getFormattedWakeWord()}" to try asking your question again...';
      });
    }
  }

  void _onBuildSpaceChange() {
    setState(() {
      _buildSpaceText = _buildSpaceController.text;
    });
  }

  void _onSpeechHistoryChange() {
    setState(() {
      // Since speech history now serves as build space, sync the text
      _buildSpaceText = _speechHistoryController.text;
    });
  }

  // --- Wake Word Helper Method ---

  String _getFormattedWakeWord() {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    if (userSettings.settings?.wakeWordName.isNotEmpty == true) {
      final wakeWordInterjection =
          (userSettings.settings?.wakeWordInterjection ?? 'hey').trim();
      final wakeWordName = (userSettings.settings?.wakeWordName ?? 'bravo')
          .trim();
      // Capitalize properly: "Hey Bravo"
      final formattedInterjection =
          wakeWordInterjection.substring(0, 1).toUpperCase() +
          wakeWordInterjection.substring(1).toLowerCase();
      final formattedName =
          wakeWordName.substring(0, 1).toUpperCase() +
          wakeWordName.substring(1).toLowerCase();
      return '$formattedInterjection $formattedName';
    }
    return 'Hey Bravo'; // Fallback
  }

  // --- New Tap Interface Methods ---

  Future<void> _loadTapInterfaceConfig() async {
    setState(() {
      _isLoadingConfig = true;
    });

    try {
      final config = await _tapService.fetchTapInterfaceConfig();
      final boards = await _tapService.fetchTapBoards();
      final ensuredConfig = _ensureEmailTapCategory(config);

      // Debug: Log all categories and their speech text
      if (ensuredConfig != null) {
        debugPrint(
          '[TapInterface] 📋 Loaded tap config with ${ensuredConfig.buttons.length} categories:',
        );
        for (var i = 0; i < ensuredConfig.buttons.length; i++) {
          final category = ensuredConfig.buttons[i];
          debugPrint(
            '[TapInterface] Category $i: "${category.label}" - Speech Text: "${category.speechText}" (null: ${category.speechText == null})',
          );
        }
      } else {
        debugPrint('[TapInterface] ❌ No tap config loaded! Using local fallback configuration.');
      }

      final finalConfig = ensuredConfig ?? _createLocalFallbackConfig();

      setState(() {
        _tapConfig = finalConfig;
        _tapBoards = boards ?? const TapBoardsResponse(boards: [], boardSettings: TapBoardSettings());
        _isLoadingConfig = false;
      });

      _openConfiguredHomeBoard()
          .timeout(const Duration(seconds: 12))
          .then((opened) {
            if (opened) {
              debugPrint('[TapInterface] Opened configured home board on startup');
            } else {
              // No home board configured (or startup home board open failed)
              // -> load general initial options so the page never appears blank.
              _loadInitialFreestyleOptions();
              _loadInitialPhraseOptions();
            }
          })
          .catchError((e) {
            debugPrint(
              '[TapInterface] Home board startup load timed out/failed: $e. Falling back to initial options.',
            );
            if (!mounted) return;
            _loadInitialFreestyleOptions();
            _loadInitialPhraseOptions();
          });

      // Preload category images in background for better performance
      _preloadCategoryImages();
    } catch (e) {
      debugPrint('Error loading tap interface config (exception): $e. Using local fallback.');
      
      final fallbackConfig = _createLocalFallbackConfig();
      
      setState(() {
        _tapConfig = fallbackConfig;
        _tapBoards = const TapBoardsResponse(boards: [], boardSettings: TapBoardSettings());
        _isLoadingConfig = false;
      });

      _loadInitialFreestyleOptions();
      _loadInitialPhraseOptions();
    }
  }

  TapInterfaceConfig? _ensureEmailTapCategory(TapInterfaceConfig? config) {
    if (config == null) return null;

    final hasEmailCategory = config.buttons.any((category) {
      final special = (category.specialPage ?? '').trim().toLowerCase();
      final label = category.label.trim().toLowerCase();
      return special == 'email' ||
          special == 'email-page' ||
          special == 'email_page' ||
          special == 'mail' ||
          label == 'email';
    });

    if (hasEmailCategory) {
      return config;
    }

    final augmentedButtons = <TapInterfaceCategory>[...config.buttons];
    augmentedButtons.add(
      TapInterfaceCategory(
        id: 'special-email',
        label: 'Email',
        speechText: 'Email',
        specialPage: 'email',
        hidden: true,
        optionType: 'phrase',
      ),
    );

    debugPrint(
      '[TapInterface] Added fallback Email special category (missing from server config).',
    );

    return TapInterfaceConfig(
      id: config.id,
      name: config.name,
      description: config.description,
      isActive: config.isActive,
      createdAt: config.createdAt,
      updatedAt: config.updatedAt,
      buttons: augmentedButtons,
    );
  }

  TapInterfaceConfig _createLocalFallbackConfig() {
    final defaultCategories = [
      TapInterfaceCategory(
        id: 'quick_talk',
        label: 'Quick Talk',
        speechText: 'Quick Talk',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/quick_talk.png',
        optionType: 'phrase',
      ),
      TapInterfaceCategory(
        id: 'food_drink',
        label: 'Food & Drink',
        speechText: 'Food and Drink',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/food_drink.png',
        optionType: 'phrase',
      ),
      TapInterfaceCategory(
        id: 'feelings',
        label: 'Feelings',
        speechText: 'Feelings',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/feelings.png',
        optionType: 'phrase',
      ),
      TapInterfaceCategory(
        id: 'people',
        label: 'People',
        speechText: 'People',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/people.png',
        optionType: 'phrase',
      ),
      TapInterfaceCategory(
        id: 'activities',
        label: 'Activities',
        speechText: 'Activities',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/activities.png',
        optionType: 'phrase',
      ),
      TapInterfaceCategory(
        id: 'places',
        label: 'Places',
        speechText: 'Places',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/places.png',
        optionType: 'phrase',
      ),
      TapInterfaceCategory(
        id: 'freestyle',
        label: 'Freestyle',
        speechText: 'Freestyle',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/freestyle.png',
        specialPage: 'freestyle',
        optionType: 'word',
      ),
      TapInterfaceCategory(
        id: 'email_special_fallback',
        label: 'Email',
        speechText: 'Email',
        imageUrl: 'https://storage.googleapis.com/bravo-dev-465400-aac-images/categories/email.png',
        specialPage: 'email',
        optionType: 'phrase',
      ),
    ];

    return TapInterfaceConfig(
      id: 'default_fallback_config',
      name: 'Default Fallback Config',
      description: 'Used when server config fails to load',
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      buttons: defaultCategories,
    );
  }

  TapInterfaceCategory? _findCategoryByBoardId(
    String boardId, [
    List<TapInterfaceCategory>? categories,
  ]) {
    final sourceCategories = categories ?? _tapConfig?.buttons ?? const [];
    for (final category in sourceCategories) {
      if ((category.boardId ?? '').trim() == boardId.trim()) {
        return category;
      }
      final nested = _findCategoryByBoardId(boardId, category.children);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }

  TapInterfaceCategory _buildCategoryFromBoard(
    TapBoard board, {
    bool isHomeBoard = false,
  }) {
    return TapInterfaceCategory(
      id: board.id,
      label: board.label,
      boardId: board.id,
      speechText: board.speechText,
      imageUrl: board.imageUrl,
      customAudioFile: board.customAudioFile,
      backgroundColor: board.backgroundColor,
      textColor: board.textColor,
      llmPrompt: board.llmPrompt,
      staticOptions: board.staticOptions,
      isHomeBoard: isHomeBoard,
      boardWordOptions: board.buttons
          .where((button) => !button.hidden)
          .toList(),
      hidden: board.hidden,
      optionType: 'phrase',
    );
  }

  TapInterfaceCategory? _resolveTargetCategory(String boardId) {
    final existingCategory = _findCategoryByBoardId(boardId);
    if (existingCategory != null) {
      return existingCategory;
    }

    final boards = _tapBoards?.boards ?? const <TapBoard>[];
    for (final board in boards) {
      if (board.id.trim() == boardId.trim()) {
        return _buildCategoryFromBoard(
          board,
          isHomeBoard:
              (_tapBoards?.boardSettings.homeBoardId ?? '').trim() ==
              board.id.trim(),
        );
      }
    }

    return null;
  }

  Future<bool> _openConfiguredHomeBoard() async {
    final homeBoardId = (_tapBoards?.boardSettings.homeBoardId ?? '').trim();
    if (homeBoardId.isEmpty) {
      return false;
    }

    final homeCategory = _resolveTargetCategory(homeBoardId);
    if (homeCategory == null) {
      debugPrint(
        '[TapInterface] Configured home board not found: $homeBoardId',
      );
      return false;
    }

    await _handleCategoryTap(homeCategory);
    return true;
  }

  String? _normalizeBoardId(String? rawBoardId) {
    final normalized = (rawBoardId ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _getCategoryBoardId([TapInterfaceCategory? category]) {
    final sourceCategory = category ?? _selectedCategory;
    return _normalizeBoardId(sourceCategory?.boardId ?? sourceCategory?.id);
  }

  String? _getCurrentBoardIdForTemporaryNavigation() {
    final currentBoardId = _getCategoryBoardId(_selectedCategory);
    if (currentBoardId != null) {
      return currentBoardId;
    }

    return _normalizeBoardId(_tapBoards?.boardSettings.homeBoardId);
  }

  bool _hasExplicitWordOptions(TapInterfaceCategory category) {
    return category.hasBoardWordOptions || category.hasStaticOptions;
  }

  bool _isConfiguredHomeCategory(TapInterfaceCategory category) {
    if (category.isHomeBoard) {
      return true;
    }

    final configuredHomeBoardId = _normalizeBoardId(
      _tapBoards?.boardSettings.homeBoardId,
    );
    final categoryBoardId = _getCategoryBoardId(category);
    if (configuredHomeBoardId != null &&
        categoryBoardId != null &&
        configuredHomeBoardId == categoryBoardId) {
      return true;
    }

    return category.label.trim().toLowerCase() == 'home';
  }

  bool _shouldUseDefaultHomeStarterWords(TapInterfaceCategory category) {
    return _isConfiguredHomeCategory(category) &&
        !_hasExplicitWordOptions(category);
  }

  String _getDefaultHomeStarterPrompt(int desiredCount) {
    return '''Generate exactly $desiredCount AAC starter words/short phrases for a Home communication board.

STYLE TARGET:
- Keep output similar to classic AAC starters (pronouns, core verbs, helpers, basic feelings, time/location words)
- Prefer 1-2 words per option (allow up to 3 words when useful)
- Avoid long personalized greetings unless context strongly calls for one
- Keep options broadly useful for starting many conversations

REQUIRED COVERAGE MIX:
- pronouns/self-reference (I, you, we)
- core actions (want, need, go, see, help, talk, play)
- social/politeness (please, yes, no, okay)
- descriptors/feelings (good, bad, happy, sad)
- time/place words (here, there, now, later)
- context-aware words based on current location/activity/people when available

VARIETY RULES:
- Do not output duplicates
- Include some familiar core words and some context-aware variation
- Keep the list practical and AAC-friendly''';
  }

  List<String> _getFallbackHomeStarterWords({int? count}) {
    final locale = _normalizeLocaleTag(
      Provider.of<UserSettingsProvider>(context, listen: false)
              .settings
              ?.userLanguage ??
          'en-US',
    ) ??
        'en-US';

    final starterPool = _localizeHomeWordsOffline(const <String>[
      'I',
      'You',
      'We',
      'Me',
      'My',
      'Want',
      'Need',
      'Like',
      'Go',
      'See',
      'Help',
      'More',
      'Please',
      'Yes',
      'No',
      'Okay',
      'Stop',
      'Again',
      'Good',
      'Bad',
      'Happy',
      'Sad',
      'Tired',
      'This',
      'That',
      'Here',
      'There',
      'Now',
      'Later',
      'Today',
      'Talk',
      'Play',
      'Eat',
      'Drink',
      'Look',
    ], locale);

    if (count == null || count >= starterPool.length) {
      return starterPool;
    }
    return starterPool.take(count).toList();
  }

  bool _looksEnglishHeavy(List<String> words) {
    if (words.isEmpty) return false;
    const hints = <String>{
      'i', 'you', 'we', 'want', 'need', 'like', 'go', 'see', 'help', 'more',
      'please', 'yes', 'no', 'okay', 'stop', 'again', 'good', 'bad',
      'happy', 'sad', 'tired', 'this', 'that', 'here', 'there', 'now',
      'later', 'today', 'talk', 'play', 'eat', 'drink', 'look',
    };

    var hitCount = 0;
    for (final word in words) {
      final token = word.toLowerCase().trim();
      if (hints.contains(token)) {
        hitCount++;
      }
    }

    return hitCount >= (words.length * 0.45).ceil();
  }

  List<String> _localizeHomeWordsOffline(List<String> words, String locale) {
    if (locale.startsWith('en') || words.isEmpty) return words;

    final localeLang = locale.split('-').first.toLowerCase();

    final dictionaries = <String, Map<String, String>>{
      'es': {
        'i': 'yo', 'you': 'tu', 'we': 'nosotros', 'me': 'me', 'my': 'mi',
        'want': 'quiero', 'need': 'necesito', 'like': 'gusta', 'go': 'ir',
        'see': 'ver', 'help': 'ayuda', 'more': 'mas', 'please': 'por favor',
        'yes': 'si', 'no': 'no', 'okay': 'ok', 'stop': 'detener',
        'again': 'otra vez', 'good': 'bueno', 'bad': 'malo',
        'happy': 'feliz', 'sad': 'triste', 'tired': 'cansado',
        'this': 'esto', 'that': 'eso', 'here': 'aqui', 'there': 'alli',
        'now': 'ahora', 'later': 'luego', 'today': 'hoy',
        'talk': 'hablar', 'play': 'jugar', 'eat': 'comer',
        'drink': 'beber', 'look': 'mirar',
      },
      'fr': {
        'i': 'je', 'you': 'tu', 'we': 'nous', 'me': 'moi', 'my': 'mon',
        'want': 'veux', 'need': 'besoin', 'like': 'aime', 'go': 'aller',
        'see': 'voir', 'help': 'aide', 'more': 'plus', 'please': 's il vous plait',
        'yes': 'oui', 'no': 'non', 'okay': 'd accord', 'stop': 'arreter',
        'again': 'encore', 'good': 'bon', 'bad': 'mauvais',
        'happy': 'heureux', 'sad': 'triste', 'tired': 'fatigue',
        'this': 'ceci', 'that': 'cela', 'here': 'ici', 'there': 'la',
        'now': 'maintenant', 'later': 'plus tard', 'today': 'aujourd hui',
        'talk': 'parler', 'play': 'jouer', 'eat': 'manger',
        'drink': 'boire', 'look': 'regarder',
      },
      'de': {
        'i': 'ich', 'you': 'du', 'we': 'wir', 'me': 'mich', 'my': 'mein',
        'want': 'will', 'need': 'brauche', 'like': 'mag', 'go': 'gehen',
        'see': 'sehen', 'help': 'hilfe', 'more': 'mehr', 'please': 'bitte',
        'yes': 'ja', 'no': 'nein', 'okay': 'ok', 'stop': 'stopp',
        'again': 'wieder', 'good': 'gut', 'bad': 'schlecht',
        'happy': 'glucklich', 'sad': 'traurig', 'tired': 'mude',
        'this': 'das', 'that': 'jenes', 'here': 'hier', 'there': 'dort',
        'now': 'jetzt', 'later': 'spater', 'today': 'heute',
        'talk': 'sprechen', 'play': 'spielen', 'eat': 'essen',
        'drink': 'trinken', 'look': 'schauen',
      },
      'it': {
        'i': 'io', 'you': 'tu', 'we': 'noi', 'me': 'me', 'my': 'mio',
        'want': 'voglio', 'need': 'bisogno', 'like': 'piace', 'go': 'andare',
        'see': 'vedere', 'help': 'aiuto', 'more': 'piu', 'please': 'per favore',
        'yes': 'si', 'no': 'no', 'okay': 'ok', 'stop': 'ferma',
        'again': 'ancora', 'good': 'buono', 'bad': 'cattivo',
        'happy': 'felice', 'sad': 'triste', 'tired': 'stanco',
        'this': 'questo', 'that': 'quello', 'here': 'qui', 'there': 'li',
        'now': 'adesso', 'later': 'dopo', 'today': 'oggi',
        'talk': 'parlare', 'play': 'giocare', 'eat': 'mangiare',
        'drink': 'bere', 'look': 'guardare',
      },
      'pt': {
        'i': 'eu', 'you': 'voce', 'we': 'nos', 'me': 'me', 'my': 'meu',
        'want': 'quero', 'need': 'preciso', 'like': 'gosto', 'go': 'ir',
        'see': 'ver', 'help': 'ajuda', 'more': 'mais', 'please': 'por favor',
        'yes': 'sim', 'no': 'nao', 'okay': 'ok', 'stop': 'parar',
        'again': 'de novo', 'good': 'bom', 'bad': 'ruim',
        'happy': 'feliz', 'sad': 'triste', 'tired': 'cansado',
        'this': 'isso', 'that': 'aquilo', 'here': 'aqui', 'there': 'la',
        'now': 'agora', 'later': 'depois', 'today': 'hoje',
        'talk': 'falar', 'play': 'brincar', 'eat': 'comer',
        'drink': 'beber', 'look': 'olhar',
      },
      'ar': {
        'i': 'انا', 'you': 'انت', 'we': 'نحن', 'me': 'لي', 'my': 'لي',
        'want': 'اريد', 'need': 'احتاج', 'like': 'احب', 'go': 'اذهب',
        'see': 'ارى', 'help': 'مساعدة', 'more': 'اكثر', 'please': 'من فضلك',
        'yes': 'نعم', 'no': 'لا', 'okay': 'حسنا', 'stop': 'توقف',
        'again': 'مرة اخرى', 'good': 'جيد', 'bad': 'سيء',
        'happy': 'سعيد', 'sad': 'حزين', 'tired': 'متعب',
        'this': 'هذا', 'that': 'ذلك', 'here': 'هنا', 'there': 'هناك',
        'now': 'الان', 'later': 'لاحقا', 'today': 'اليوم',
        'talk': 'اتكلم', 'play': 'العب', 'eat': 'اكل',
        'drink': 'اشرب', 'look': 'انظر',
      },
    };

    final dict = dictionaries[localeLang];
    if (dict == null) return words;

    return words.map((word) {
      final key = word.toLowerCase().trim();
      return dict[key] ?? word;
    }).toList();
  }

  String? _peekTemporaryReturnBoard() {
    if (_temporaryNavigationReturnStack.isEmpty) {
      return null;
    }
    return _normalizeBoardId(_temporaryNavigationReturnStack.last);
  }

  void _pushTemporaryReturnBoard(String? boardId) {
    final normalizedBoardId = _normalizeBoardId(boardId);
    if (normalizedBoardId == null) {
      return;
    }

    _temporaryNavigationReturnStack = [
      ..._temporaryNavigationReturnStack,
      normalizedBoardId,
    ];
    _temporaryNavigationPending = true;
  }

  String? _popTemporaryReturnBoard() {
    if (_temporaryNavigationReturnStack.isEmpty) {
      return null;
    }

    final boardId = _temporaryNavigationReturnStack.last;
    _temporaryNavigationReturnStack = _temporaryNavigationReturnStack.sublist(
      0,
      _temporaryNavigationReturnStack.length - 1,
    );
    return _normalizeBoardId(boardId);
  }

  void _clearTemporaryNavigationState() {
    _temporaryNavigationReturnStack = [];
    _temporaryNavigationPending = false;
  }

  String? _getActiveBoardModifierId(String? boardId) {
    final normalizedBoardId = _normalizeBoardId(boardId);
    if (normalizedBoardId == null) {
      return null;
    }

    return _activeBoardModifierBoardId == normalizedBoardId
        ? _activeBoardModifierId
        : null;
  }

  void _setActiveBoardModifier(String? boardId, String? modifierId) {
    final normalizedBoardId = _normalizeBoardId(boardId);
    final normalizedModifierId = _normalizeBoardId(modifierId);
    if (normalizedBoardId == null || normalizedModifierId == null) {
      _activeBoardModifierBoardId = null;
      _activeBoardModifierId = null;
      return;
    }

    _activeBoardModifierBoardId = normalizedBoardId;
    _activeBoardModifierId = normalizedModifierId;
  }

  void _clearActiveBoardModifier([String? boardId]) {
    final normalizedBoardId = _normalizeBoardId(boardId);
    if (normalizedBoardId == null ||
        _activeBoardModifierBoardId == normalizedBoardId) {
      _activeBoardModifierBoardId = null;
      _activeBoardModifierId = null;
    }
  }

  int? _asNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    final parsed = int.tryParse(value.toString());
    return parsed;
  }

  bool _asBool(dynamic value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return fallback;
  }

  TapBoardButton _applyActiveBoardModifierToButton(
    TapBoardButton option,
    String? boardId,
  ) {
    final modifierId = _getActiveBoardModifierId(boardId);
    if (modifierId == null || option.modifierVariants.isEmpty) {
      return option;
    }

    final rawVariant = option.modifierVariants[modifierId];
    if (rawVariant is! Map) {
      return option;
    }

    final variant = Map<String, dynamic>.from(rawVariant);
    final hasVariantModifierTrigger = variant.containsKey(
      'modifier_trigger_id',
    );
    final hasVariantTargetBoard = variant.containsKey('target_board_id');
    final hasVariantTemporaryNavigation = variant.containsKey(
      'temporary_navigation',
    );
    final variantLabel = (variant['label'] ?? '').toString().trim();

    return option.copyWith(
      text: variantLabel.isNotEmpty ? variantLabel : option.text,
      speechText: variant['speech_text'] is String
          ? variant['speech_text'] as String
          : option.speechText,
      modifierTriggerId: hasVariantModifierTrigger
          ? _asNullableInt(variant['modifier_trigger_id'])
          : option.modifierTriggerId,
      actionType: (variant['action_type'] ?? option.actionType)?.toString(),
      afterSelection: (variant['after_selection'] ?? option.afterSelection)
          .toString(),
      targetBoardId: hasVariantTargetBoard
          ? _normalizeBoardId(variant['target_board_id']?.toString())
          : option.targetBoardId,
      temporaryNavigation: hasVariantTemporaryNavigation
          ? _asBool(
              variant['temporary_navigation'],
              fallback: option.temporaryNavigation,
            )
          : option.temporaryNavigation,
      backgroundColor: (variant['background_color'] ?? option.backgroundColor)
          ?.toString(),
      textColor: (variant['text_color'] ?? option.textColor)?.toString(),
    );
  }

  Future<bool> _returnFromTemporaryNavigationIfNeeded() async {
    if (!_temporaryNavigationPending) {
      return false;
    }

    final temporaryReturnBoardId = _popTemporaryReturnBoard();
    _temporaryNavigationPending = false;
    if (temporaryReturnBoardId == null) {
      _clearTemporaryNavigationState();
      return false;
    }

    final returnCategory = _resolveTargetCategory(temporaryReturnBoardId);
    if (returnCategory == null) {
      _clearTemporaryNavigationState();
      return false;
    }

    await _handleCategoryTap(returnCategory);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Past / Plural variant mode helpers
  // ---------------------------------------------------------------------------

  // Ported from the web app's COMMON_WORD_VARIANTS dictionary.
  // Keys are lowercase originals; values map 'past' and 'plural' variants.
  // null means the variant doesn't apply (verbs have null plural; demonstratives
  // have null past).
  static const Map<String, Map<String, String?>> _commonWordVariants = {
    // ── Demonstratives / pronouns (plural only) ─────────────────────────────
    'this':    {'past': null, 'plural': 'these'},
    'that':    {'past': null, 'plural': 'those'},
    'it':      {'past': null, 'plural': 'them'},
    'its':     {'past': null, 'plural': 'their'},
    'itself':  {'past': null, 'plural': 'themselves'},
    // ── Irregular verbs (past only) ──────────────────────────────────────────
    'am':      {'past': 'was',     'plural': null},
    'is':      {'past': 'was',     'plural': null},
    'are':     {'past': 'were',    'plural': null},
    'was':     {'past': 'was',     'plural': null},
    'be':      {'past': 'was',     'plural': null},
    'have':    {'past': 'had',     'plural': null},
    'has':     {'past': 'had',     'plural': null},
    'do':      {'past': 'did',     'plural': null},
    'does':    {'past': 'did',     'plural': null},
    'go':      {'past': 'went',    'plural': null},
    'goes':    {'past': 'went',    'plural': null},
    'get':     {'past': 'got',     'plural': null},
    'got':     {'past': 'got',     'plural': null},
    'make':    {'past': 'made',    'plural': null},
    'say':     {'past': 'said',    'plural': null},
    'see':     {'past': 'saw',     'plural': null},
    'take':    {'past': 'took',    'plural': null},
    'come':    {'past': 'came',    'plural': null},
    'know':    {'past': 'knew',    'plural': null},
    'think':   {'past': 'thought', 'plural': null},
    'feel':    {'past': 'felt',    'plural': null},
    'tell':    {'past': 'told',    'plural': null},
    'give':    {'past': 'gave',    'plural': null},
    'find':    {'past': 'found',   'plural': null},
    'put':     {'past': 'put',     'plural': null},
    'run':     {'past': 'ran',     'plural': null},
    'eat':     {'past': 'ate',     'plural': null},
    'sit':     {'past': 'sat',     'plural': null},
    'stand':   {'past': 'stood',   'plural': null},
    'write':   {'past': 'wrote',   'plural': null},
    'read':    {'past': 'read',    'plural': null},
    'hear':    {'past': 'heard',   'plural': null},
    'hold':    {'past': 'held',    'plural': null},
    'bring':   {'past': 'brought', 'plural': null},
    'leave':   {'past': 'left',    'plural': null},
    'keep':    {'past': 'kept',    'plural': null},
    'let':     {'past': 'let',     'plural': null},
    'begin':   {'past': 'began',   'plural': null},
    'show':    {'past': 'showed',  'plural': null},
    'ride':    {'past': 'rode',    'plural': null},
    'drive':   {'past': 'drove',   'plural': null},
    'swim':    {'past': 'swam',    'plural': null},
    'fly':     {'past': 'flew',    'plural': null},
    'fall':    {'past': 'fell',    'plural': null},
    'hurt':    {'past': 'hurt',    'plural': null},
    'cut':     {'past': 'cut',     'plural': null},
    'hit':     {'past': 'hit',     'plural': null},
    'buy':     {'past': 'bought',  'plural': null},
    'pay':     {'past': 'paid',    'plural': null},
    'send':    {'past': 'sent',    'plural': null},
    'meet':    {'past': 'met',     'plural': null},
    'lose':    {'past': 'lost',    'plural': null},
    'win':     {'past': 'won',     'plural': null},
    'build':   {'past': 'built',   'plural': null},
    'draw':    {'past': 'drew',    'plural': null},
    'sing':    {'past': 'sang',    'plural': null},
    'throw':   {'past': 'threw',   'plural': null},
    'catch':   {'past': 'caught',  'plural': null},
    'bite':    {'past': 'bit',     'plural': null},
    'blow':    {'past': 'blew',    'plural': null},
    'break':   {'past': 'broke',   'plural': null},
    'wake':    {'past': 'woke',    'plural': null},
    'sleep':   {'past': 'slept',   'plural': null},
    'choose':  {'past': 'chose',   'plural': null},
    'cry':     {'past': 'cried',   'plural': null},
    // ── Regular verbs (past only) ────────────────────────────────────────────
    'play':    {'past': 'played',   'plural': null},
    'want':    {'past': 'wanted',   'plural': null},
    'need':    {'past': 'needed',   'plural': null},
    'help':    {'past': 'helped',   'plural': null},
    'talk':    {'past': 'talked',   'plural': null},
    'walk':    {'past': 'walked',   'plural': null},
    'look':    {'past': 'looked',   'plural': null},
    'like':    {'past': 'liked',    'plural': null},
    'love':    {'past': 'loved',    'plural': null},
    'try':     {'past': 'tried',    'plural': null},
    'ask':     {'past': 'asked',    'plural': null},
    'call':    {'past': 'called',   'plural': null},
    'stop':    {'past': 'stopped',  'plural': null},
    'wait':    {'past': 'waited',   'plural': null},
    'watch':   {'past': 'watched',  'plural': null},
    'listen':  {'past': 'listened', 'plural': null},
    'open':    {'past': 'opened',   'plural': null},
    'close':   {'past': 'closed',   'plural': null},
    'turn':    {'past': 'turned',   'plural': null},
    'push':    {'past': 'pushed',   'plural': null},
    'pull':    {'past': 'pulled',   'plural': null},
    'pick':    {'past': 'picked',   'plural': null},
    'start':   {'past': 'started',  'plural': null},
    'finish':  {'past': 'finished', 'plural': null},
    'learn':   {'past': 'learned',  'plural': null},
    'work':    {'past': 'worked',   'plural': null},
    'dance':   {'past': 'danced',   'plural': null},
    'cook':    {'past': 'cooked',   'plural': null},
    'clean':   {'past': 'cleaned',  'plural': null},
    'wash':    {'past': 'washed',   'plural': null},
    'change':  {'past': 'changed',  'plural': null},
    'jump':    {'past': 'jumped',   'plural': null},
    'climb':   {'past': 'climbed',  'plural': null},
    'laugh':   {'past': 'laughed',  'plural': null},
    'smile':   {'past': 'smiled',   'plural': null},
    'hug':     {'past': 'hugged',   'plural': null},
    'kiss':    {'past': 'kissed',   'plural': null},
    'touch':   {'past': 'touched',  'plural': null},
    'count':   {'past': 'counted',  'plural': null},
    // ── Nouns/words with both past-verb and plural-noun forms ────────────────
    'drink':   {'past': 'drank',    'plural': 'drinks'},
    'brush':   {'past': 'brushed',  'plural': 'brushes'},
    'dress':   {'past': 'dressed',  'plural': 'dresses'},
    // ── Nouns (plural only — no meaningful past tense) ───────────────────────
    'book':    {'past': null, 'plural': 'books'},
    'toy':     {'past': null, 'plural': 'toys'},
    'ball':    {'past': null, 'plural': 'balls'},
    'game':    {'past': null, 'plural': 'games'},
    'food':    {'past': null, 'plural': 'foods'},
    'snack':   {'past': null, 'plural': 'snacks'},
    'cookie':  {'past': null, 'plural': 'cookies'},
    'apple':   {'past': null, 'plural': 'apples'},
    'cracker': {'past': null, 'plural': 'crackers'},
    'chip':    {'past': null, 'plural': 'chips'},
    'sandwich':{'past': null, 'plural': 'sandwiches'},
    'pizza':   {'past': null, 'plural': 'pizzas'},
    'shoe':    {'past': null, 'plural': 'shoes'},
    'sock':    {'past': null, 'plural': 'socks'},
    'shirt':   {'past': null, 'plural': 'shirts'},
    'pant':    {'past': null, 'plural': 'pants'},
    'hat':     {'past': null, 'plural': 'hats'},
    'cup':     {'past': null, 'plural': 'cups'},
    'box':     {'past': null, 'plural': 'boxes'},
    'bag':     {'past': null, 'plural': 'bags'},
    'chair':   {'past': null, 'plural': 'chairs'},
    'friend':  {'past': null, 'plural': 'friends'},
    'person':  {'past': null, 'plural': 'people'},
    'child':   {'past': null, 'plural': 'children'},
    'kid':     {'past': null, 'plural': 'kids'},
    'animal':  {'past': null, 'plural': 'animals'},
    'dog':     {'past': null, 'plural': 'dogs'},
    'cat':     {'past': null, 'plural': 'cats'},
    'bird':    {'past': null, 'plural': 'birds'},
    'fish':    {'past': null, 'plural': 'fish'},
    // ── Transportation ───────────────────────────────────────────────────────
    'car':          {'past': null, 'plural': 'cars'},
    'bus':          {'past': null, 'plural': 'buses'},
    'bike':         {'past': null, 'plural': 'bikes'},
    'bicycle':      {'past': null, 'plural': 'bicycles'},
    'train':        {'past': null, 'plural': 'trains'},
    'plane':        {'past': null, 'plural': 'planes'},
    'airplane':     {'past': null, 'plural': 'airplanes'},
    'truck':        {'past': null, 'plural': 'trucks'},
    'van':          {'past': null, 'plural': 'vans'},
    'boat':         {'past': null, 'plural': 'boats'},
    'ship':         {'past': null, 'plural': 'ships'},
    'helicopter':   {'past': null, 'plural': 'helicopters'},
    'motorcycle':   {'past': null, 'plural': 'motorcycles'},
    'scooter':      {'past': null, 'plural': 'scooters'},
    'taxi':         {'past': null, 'plural': 'taxis'},
    'ambulance':    {'past': null, 'plural': 'ambulances'},
    'wheelchair':   {'past': null, 'plural': 'wheelchairs'},
    'stroller':     {'past': null, 'plural': 'strollers'},
    // ── Animals ─────────────────────────────────────────────────────────────
    'horse':     {'past': null, 'plural': 'horses'},
    'cow':       {'past': null, 'plural': 'cows'},
    'pig':       {'past': null, 'plural': 'pigs'},
    'sheep':     {'past': null, 'plural': 'sheep'},
    'chicken':   {'past': null, 'plural': 'chickens'},
    'duck':      {'past': null, 'plural': 'ducks'},
    'rabbit':    {'past': null, 'plural': 'rabbits'},
    'snake':     {'past': null, 'plural': 'snakes'},
    'turtle':    {'past': null, 'plural': 'turtles'},
    'frog':      {'past': null, 'plural': 'frogs'},
    'elephant':  {'past': null, 'plural': 'elephants'},
    'lion':      {'past': null, 'plural': 'lions'},
    'tiger':     {'past': null, 'plural': 'tigers'},
    'bear':      {'past': null, 'plural': 'bears'},
    'monkey':    {'past': null, 'plural': 'monkeys'},
    'giraffe':   {'past': null, 'plural': 'giraffes'},
    'wolf':      {'past': null, 'plural': 'wolves'},
    'bee':       {'past': null, 'plural': 'bees'},
    'butterfly': {'past': null, 'plural': 'butterflies'},
    'ant':       {'past': null, 'plural': 'ants'},
    'spider':    {'past': null, 'plural': 'spiders'},
    'mouse':     {'past': null, 'plural': 'mice'},
    'dinosaur':  {'past': null, 'plural': 'dinosaurs'},
    // ── People ──────────────────────────────────────────────────────────────
    'girl':    {'past': null, 'plural': 'girls'},
    'boy':     {'past': null, 'plural': 'boys'},
    'man':     {'past': null, 'plural': 'men'},
    'woman':   {'past': null, 'plural': 'women'},
    'baby':    {'past': null, 'plural': 'babies'},
    'parent':  {'past': null, 'plural': 'parents'},
    'teacher': {'past': null, 'plural': 'teachers'},
    'doctor':  {'past': null, 'plural': 'doctors'},
    'nurse':   {'past': null, 'plural': 'nurses'},
    'helper':  {'past': null, 'plural': 'helpers'},
    'brother': {'past': null, 'plural': 'brothers'},
    'sister':  {'past': null, 'plural': 'sisters'},
    'student': {'past': null, 'plural': 'students'},
    // ── Food & drink ────────────────────────────────────────────────────────
    'banana':      {'past': null, 'plural': 'bananas'},
    'orange':      {'past': null, 'plural': 'oranges'},
    'grape':       {'past': null, 'plural': 'grapes'},
    'strawberry':  {'past': null, 'plural': 'strawberries'},
    'blueberry':   {'past': null, 'plural': 'blueberries'},
    'cherry':      {'past': null, 'plural': 'cherries'},
    'peach':       {'past': null, 'plural': 'peaches'},
    'pear':        {'past': null, 'plural': 'pears'},
    'mango':       {'past': null, 'plural': 'mangoes'},
    'carrot':      {'past': null, 'plural': 'carrots'},
    'potato':      {'past': null, 'plural': 'potatoes'},
    'tomato':      {'past': null, 'plural': 'tomatoes'},
    'noodle':      {'past': null, 'plural': 'noodles'},
    'egg':         {'past': null, 'plural': 'eggs'},
    'burger':      {'past': null, 'plural': 'burgers'},
    'taco':        {'past': null, 'plural': 'tacos'},
    'donut':       {'past': null, 'plural': 'donuts'},
    'muffin':      {'past': null, 'plural': 'muffins'},
    'cupcake':     {'past': null, 'plural': 'cupcakes'},
    'pancake':     {'past': null, 'plural': 'pancakes'},
    'waffle':      {'past': null, 'plural': 'waffles'},
    'pretzel':     {'past': null, 'plural': 'pretzels'},
    'candy':       {'past': null, 'plural': 'candies'},
    'straw':       {'past': null, 'plural': 'straws'},
    'plate':       {'past': null, 'plural': 'plates'},
    // ── Body parts ──────────────────────────────────────────────────────────
    'hand':    {'past': null, 'plural': 'hands'},
    'foot':    {'past': null, 'plural': 'feet'},
    'tooth':   {'past': null, 'plural': 'teeth'},
    'eye':     {'past': null, 'plural': 'eyes'},
    'ear':     {'past': null, 'plural': 'ears'},
    'finger':  {'past': null, 'plural': 'fingers'},
    'toe':     {'past': null, 'plural': 'toes'},
    'arm':     {'past': null, 'plural': 'arms'},
    'leg':     {'past': null, 'plural': 'legs'},
    'knee':    {'past': null, 'plural': 'knees'},
    'elbow':   {'past': null, 'plural': 'elbows'},
    'shoulder':{'past': null, 'plural': 'shoulders'},
    'cheek':   {'past': null, 'plural': 'cheeks'},
    // ── Clothing ────────────────────────────────────────────────────────────
    'coat':     {'past': null, 'plural': 'coats'},
    'jacket':   {'past': null, 'plural': 'jackets'},
    'glove':    {'past': null, 'plural': 'gloves'},
    'boot':     {'past': null, 'plural': 'boots'},
    'sneaker':  {'past': null, 'plural': 'sneakers'},
    'sandal':   {'past': null, 'plural': 'sandals'},
    'jeans':    {'past': null, 'plural': 'jeans'},
    'skirt':    {'past': null, 'plural': 'skirts'},
    'shorts':   {'past': null, 'plural': 'shorts'},
    'diaper':   {'past': null, 'plural': 'diapers'},
    'mitten':   {'past': null, 'plural': 'mittens'},
    'scarf':    {'past': null, 'plural': 'scarves'},
    'pajama':   {'past': null, 'plural': 'pajamas'},
    // ── Household / objects ──────────────────────────────────────────────────
    'table':      {'past': null, 'plural': 'tables'},
    'door':       {'past': null, 'plural': 'doors'},
    'window':     {'past': null, 'plural': 'windows'},
    'phone':      {'past': null, 'plural': 'phones'},
    'tablet':     {'past': null, 'plural': 'tablets'},
    'pillow':     {'past': null, 'plural': 'pillows'},
    'blanket':    {'past': null, 'plural': 'blankets'},
    'towel':      {'past': null, 'plural': 'towels'},
    'toothbrush': {'past': null, 'plural': 'toothbrushes'},
    'spoon':      {'past': null, 'plural': 'spoons'},
    'fork':       {'past': null, 'plural': 'forks'},
    'knife':      {'past': null, 'plural': 'knives'},
    'bowl':       {'past': null, 'plural': 'bowls'},
    'glass':      {'past': null, 'plural': 'glasses'},
    'bottle':     {'past': null, 'plural': 'bottles'},
    'pot':        {'past': null, 'plural': 'pots'},
    'pan':        {'past': null, 'plural': 'pans'},
    'tissue':     {'past': null, 'plural': 'tissues'},
    'bed':        {'past': null, 'plural': 'beds'},
    'couch':      {'past': null, 'plural': 'couches'},
    'lamp':       {'past': null, 'plural': 'lamps'},
    'key':        {'past': null, 'plural': 'keys'},
    'button':     {'past': null, 'plural': 'buttons'},
    // ── School / art ────────────────────────────────────────────────────────
    'pencil':   {'past': null, 'plural': 'pencils'},
    'crayon':   {'past': null, 'plural': 'crayons'},
    'marker':   {'past': null, 'plural': 'markers'},
    'eraser':   {'past': null, 'plural': 'erasers'},
    'ruler':    {'past': null, 'plural': 'rulers'},
    'notebook': {'past': null, 'plural': 'notebooks'},
    'backpack': {'past': null, 'plural': 'backpacks'},
    'sticker':  {'past': null, 'plural': 'stickers'},
    'balloon':  {'past': null, 'plural': 'balloons'},
    'puzzle':   {'past': null, 'plural': 'puzzles'},
    'block':    {'past': null, 'plural': 'blocks'},
    'card':     {'past': null, 'plural': 'cards'},
    'doll':     {'past': null, 'plural': 'dolls'},
    // ── Nature ──────────────────────────────────────────────────────────────
    'flower':  {'past': null, 'plural': 'flowers'},
    'tree':    {'past': null, 'plural': 'trees'},
    'leaf':    {'past': null, 'plural': 'leaves'},
    'rock':    {'past': null, 'plural': 'rocks'},
    'stick':   {'past': null, 'plural': 'sticks'},
    'bug':     {'past': null, 'plural': 'bugs'},
    'star':    {'past': null, 'plural': 'stars'},
    // ── Places ──────────────────────────────────────────────────────────────
    'store':      {'past': null, 'plural': 'stores'},
    'library':    {'past': null, 'plural': 'libraries'},
    'park':       {'past': null, 'plural': 'parks'},
    'playground': {'past': null, 'plural': 'playgrounds'},
    'garden':     {'past': null, 'plural': 'gardens'},
    'farm':       {'past': null, 'plural': 'farms'},
    'zoo':        {'past': null, 'plural': 'zoos'},
    'beach':      {'past': null, 'plural': 'beaches'},
    'mountain':   {'past': null, 'plural': 'mountains'},
    'room':       {'past': null, 'plural': 'rooms'},
    'bathroom':   {'past': null, 'plural': 'bathrooms'},
    'bedroom':    {'past': null, 'plural': 'bedrooms'},
    'kitchen':    {'past': null, 'plural': 'kitchens'},
    'restaurant': {'past': null, 'plural': 'restaurants'},
    'hospital':   {'past': null, 'plural': 'hospitals'},
    // ── Other common nouns ───────────────────────────────────────────────────
    'color':   {'past': null, 'plural': 'colors'},
    'idea':    {'past': null, 'plural': 'ideas'},
    'wish':    {'past': null, 'plural': 'wishes'},
    'plan':    {'past': null, 'plural': 'plans'},
    'story':   {'past': null, 'plural': 'stories'},
    'video':   {'past': null, 'plural': 'videos'},
    'picture': {'past': null, 'plural': 'pictures'},
    'place':   {'past': null, 'plural': 'places'},
    'thing':   {'past': null, 'plural': 'things'},
    'word':    {'past': null, 'plural': 'words'},
    'question':{'past': null, 'plural': 'questions'},
    'answer':  {'past': null, 'plural': 'answers'},
    'activity':{'past': null, 'plural': 'activities'},
    'exercise':{'past': null, 'plural': 'exercises'},
    'task':    {'past': null, 'plural': 'tasks'},
    'event':   {'past': null, 'plural': 'events'},
    'trip':    {'past': null, 'plural': 'trips'},
    'gift':    {'past': null, 'plural': 'gifts'},
    'item':    {'past': null, 'plural': 'items'},
    'option':  {'past': null, 'plural': 'options'},
    'choice':  {'past': null, 'plural': 'choices'},
    // ── Common AAC multi-word starters (past only) ───────────────────────────
    'i want':       {'past': 'i wanted', 'plural': null},
    'i need':       {'past': 'i needed', 'plural': null},
    'i feel':       {'past': 'i felt',   'plural': null},
    'i like':       {'past': 'i liked',  'plural': null},
    'i love':       {'past': 'i loved',  'plural': null},
    'i see':        {'past': 'i saw',    'plural': null},
    'i went':       {'past': 'i went',   'plural': null},
    'i got':        {'past': 'i got',    'plural': null},
    'can i':        {'past': 'could i',  'plural': null},
    'let\'s':       {'past': 'we',       'plural': null},
    'to play':      {'past': 'played',   'plural': null},
    'to go':        {'past': 'went',     'plural': null},
    'to eat':       {'past': 'ate',      'plural': null},
    'to drink':     {'past': 'drank',    'plural': null},
    'to see':       {'past': 'saw',      'plural': null},
    'to do':        {'past': 'did',      'plural': null},
    'to get':       {'past': 'got',      'plural': null},
    'to make':      {'past': 'made',     'plural': null},
    'to take':      {'past': 'took',     'plural': null},
    'to come':      {'past': 'came',     'plural': null},
    'to go to':     {'past': 'went to',  'plural': null},
    'feeling good':    {'past': 'felt good',    'plural': null},
    'feeling bad':     {'past': 'felt bad',     'plural': null},
    'feeling happy':   {'past': 'felt happy',   'plural': null},
    'feeling sad':     {'past': 'felt sad',     'plural': null},
    'feeling sick':    {'past': 'felt sick',    'plural': null},
    'feeling tired':   {'past': 'felt tired',   'plural': null},
    'feeling hungry':  {'past': 'felt hungry',  'plural': null},
    'feeling scared':  {'past': 'felt scared',  'plural': null},
    'feeling excited': {'past': 'felt excited', 'plural': null},
  };

  /// Tier 2: check the lookup table. Returns null if not found.
  String? _lookupVariant(String word, String mode) {
    final key = word.toLowerCase().trim();
    final entry = _commonWordVariants[key];
    if (entry == null) return null;
    final variant = entry[mode];
    // Return null if the variant is identical to the original (no-op words)
    if (variant == null || variant.toLowerCase() == key) return null;
    return variant;
  }

  // Suffixes that strongly indicate the word is NOT a noun that should be
  // pluralised (verbs, adjectives, adverbs). Words matching these are skipped
  // by the programmatic pluraliser so we don't turn "happy" into "happys".
  static const List<String> _nonNounSuffixes = [
    'ing', 'ed', 'ly', 'ful', 'less', 'ish', 'ous', 'ive', 'ent', 'ant',
    'ble', 'al', 'ic', 'fy', 'ify', 'ize', 'ise', 'er', 'est',
  ];

  /// Tier 2.5: Programmatic English pluralizer — only for plural mode.
  ///
  /// Applies standard English pluralization rules for regular nouns that are
  /// NOT in the lookup table. Skips words that look like verbs or adjectives
  /// (based on suffix heuristics). This handles the long tail of nouns like
  /// "bike", "train", "flower" without needing the LLM.
  String? _programmaticPlural(String word) {
    final lower = word.toLowerCase().trim();

    // Skip single characters, pure numbers, and empty strings.
    if (lower.length <= 1 || RegExp(r'^\d+$').hasMatch(lower)) return null;

    // Skip words that already end in 's' or look like plurals.
    if (lower.endsWith('ss')) {
      // "class" → "classes", "grass" → "grasses"
    } else if (lower.endsWith('s') && !lower.endsWith('ss')) {
      return null; // probably already plural or a verb ("runs", "eats")
    }

    // Skip words that look like verbs / adjectives.
    for (final suffix in _nonNounSuffixes) {
      if (lower.endsWith(suffix) && lower.length > suffix.length + 1) {
        return null;
      }
    }

    // Also skip words in our known-verbs list (any word that has a past entry).
    final entry = _commonWordVariants[lower];
    if (entry != null && entry['past'] != null) return null;

    // Apply standard English plural rules.
    if (lower.endsWith('fe')) {
      return '${lower.substring(0, lower.length - 2)}ves'; // knife→knives
    }
    if (lower.endsWith('lf')) {
      return '${lower.substring(0, lower.length - 1)}ves'; // half→halves
    }
    if (lower.endsWith('ch') || lower.endsWith('sh') ||
        lower.endsWith('ss') || lower.endsWith('x') || lower.endsWith('z')) {
      return '${lower}es'; // beach→beaches, dish→dishes, box→boxes
    }
    if (lower.endsWith('y') && lower.length > 1 &&
        !'aeiou'.contains(lower[lower.length - 2])) {
      return '${lower.substring(0, lower.length - 1)}ies'; // baby→babies
    }
    if (lower.endsWith('o') && !lower.endsWith('oo')) {
      // potato→potatoes, but zoo→zoos (handled by lookup table)
      return '${lower}es';
    }
    return '${lower}s'; // default: just add s
  }

  // Demonstratives that change for plural phrases (mirrors web app).
  static const Map<String, String> _demonstrativePlurals = {
    'this': 'these',
    'that': 'those',
    'it':   'them',
    'its':  'their',
  };

  /// Tier 3: phrase pattern resolver for multi-word phrases not in the table.
  ///
  /// Plural mode (mirrors web app `resolveVariantPhrase` plural branch):
  ///   "this/that/it + ..." → convert demonstrative; also pluralise last word
  ///   if it has a known plural mapping.
  ///
  /// Past mode:
  ///   Convert the first recognisable verb; also handles "to VERB ..." pattern.
  String? _resolveVariantPhrase(String phrase, String mode) {
    final words = phrase.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return null;

    final firstLower = words.first.toLowerCase();

    if (mode == 'plural') {
      final demonstrative = _demonstrativePlurals[firstLower];
      if (demonstrative != null) {
        final result = List<String>.from(words);
        result[0] = demonstrative;
        // Also try to pluralise the last word.
        final lastLower = words.last.toLowerCase();
        final lastEntry = _commonWordVariants[lastLower];
        final lastPlural = lastEntry?['plural'];
        if (lastPlural != null) {
          result[result.length - 1] = lastPlural;
        }
        return result.join(' ');
      }
      return null; // Other plural phrases go to tier 4 (LLM)
    }

    // Past mode: convert first verb in phrase.
    final rest = words.skip(1).join(' ');
    final verbVariant = _lookupVariant(firstLower, mode);
    if (verbVariant != null) {
      final cap = phrase[0] == phrase[0].toUpperCase()
          ? verbVariant[0].toUpperCase() + verbVariant.substring(1)
          : verbVariant;
      return '$cap $rest';
    }

    // "to <verb> ..." → drop "to", past-tense the verb.
    if (firstLower == 'to' && words.length >= 2) {
      final verb = words[1].toLowerCase();
      final verbVar = _lookupVariant(verb, mode);
      if (verbVar != null) {
        final tail = words.length > 2 ? ' ${words.skip(2).join(' ')}' : '';
        final cap = phrase[0] == phrase[0].toUpperCase()
            ? verbVar[0].toUpperCase() + verbVar.substring(1)
            : verbVar;
        return '$cap$tail';
      }
    }

    return null;
  }

  /// Resolves the variant for a single word/phrase using tiers 2–3 (local).
  /// Returns null when neither tier can resolve it (needs LLM — tier 4).
  String? _resolveVariantLocal(String word, String mode) {
    return _lookupVariant(word, mode)
        ?? _resolveVariantPhrase(word, mode)
        ?? (mode == 'plural' ? _programmaticPlural(word) : null);
  }

  /// Applies [mode] ('past' | 'plural') to all currently visible options.
  /// Tiers 2–3 are resolved synchronously from local data; tier 4 batches
  /// anything unresolved into a single POST to /api/tap-interface/word-variants.
  Future<void> _applyVariantModeToCurrentBoard(String mode) async {
    // Run tiers 1-3 synchronously every call (they only skip already-cached
    // words so re-entry is safe). Only the LLM (tier 4) is guarded against
    // concurrent calls so we don't fire duplicate network requests.
    try {
      // Collect every visible word/phrase that isn't already cached.
      final allWords = <String>{
        ..._boardWordOptions.map((b) => b.text),
        ..._wordOptions,
      };

      final wordsForLlm = <String>[];

      for (final word in allWords) {
        final cacheKey = '$mode:$word';
        if (_variantCache.containsKey(cacheKey)) continue;

        // Tier 1: pre-stored field on the button object (handled at render time)
        // — already has the variant, no cache entry needed.
        final boardBtn = _boardWordOptions
            .where((b) => b.text == word)
            .firstOrNull;
        if (boardBtn != null) {
          final stored = mode == 'past' ? boardBtn.pastTense : boardBtn.plural;
          if (stored != null && stored.isNotEmpty && stored != word) {
            _variantCache[cacheKey] = stored;
            continue;
          }
        }

        // Tier 2 + 3: local lookup / phrase resolver
        final local = _resolveVariantLocal(word, mode);
        if (local != null) {
          _variantCache[cacheKey] = local;
          continue;
        }

        // Tier 4 needed
        wordsForLlm.add(word);
      }

      // Show tier 1-3 results immediately — don't make the user wait for the
      // LLM round-trip before seeing local matches.
      if (mounted) setState(() {});

      // Tier 4: batch LLM call for anything unresolved.
      // Guard against concurrent LLM calls (tiers 1-3 above are always safe
      // to re-run because they only write to already-absent cache keys).
      if (wordsForLlm.isNotEmpty && mounted && !_variantApplyInProgress) {
        _variantApplyInProgress = true;
        try {
          final userSettings = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final userId = userSettings.userId ?? widget.aacUserId;
          final response =
              await AuthenticatedHttpClient.makeAuthenticatedRequest(
                'POST',
                '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/word-variants',
                baseHeaders: {
                  'Content-Type': 'application/json',
                  'X-User-ID': userId,
                },
                body: jsonEncode({'words': wordsForLlm, 'mode': mode}),
              );
          debugPrint('[TapInterface] word-variants $mode status=${response.statusCode} words=$wordsForLlm');
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final variants =
                (data['variants'] as Map<String, dynamic>?) ?? {};
            debugPrint('[TapInterface] word-variants response: $variants');
            for (final entry in variants.entries) {
              final original = entry.key;
              final variant = entry.value?.toString() ?? '';
              if (variant.isNotEmpty &&
                  variant.toLowerCase() != original.toLowerCase()) {
                _variantCache['$mode:$original'] = variant;
              }
            }
          } else {
            debugPrint('[TapInterface] ⚠️ word-variants non-200: ${response.body}');
          }
        } catch (e) {
          debugPrint('[TapInterface] ⚠️ word-variants API error: $e');
        } finally {
          _variantApplyInProgress = false;
        }
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleGoBack() async {
    if (_navigationBreadcrumbs.isEmpty) return;
    final crumb = _navigationBreadcrumbs.last;
    setState(() {
      _navigationBreadcrumbs = _navigationBreadcrumbs.sublist(
        0,
        _navigationBreadcrumbs.length - 1,
      );
    });
    // Undo the exact phrase spoken when the navigate button was tapped.
    if (crumb.addedText.isNotEmpty) {
      _removePhraseFromSpeechHistory(crumb.addedText);
    }
    final returnCategory = _resolveTargetCategory(crumb.boardId);
    if (returnCategory != null) {
      await _handleCategoryTap(returnCategory);
    } else {
      await _openConfiguredHomeBoard();
    }
  }

  int _getBoardColumnCount() {
    if (_boardWordOptions.isEmpty) {
      return 1;
    }

    var maxCol = 0;
    for (final button in _boardWordOptions) {
      if (button.col > maxCol) {
        maxCol = button.col;
      }
    }
    return maxCol + 1;
  }

  TapBoardButton? _getBoardButtonAtIndex(int index) {
    final boardColumns = _getBoardColumnCount();
    if (boardColumns <= 0) {
      return null;
    }

    final row = index ~/ boardColumns;
    final col = index % boardColumns;
    for (final button in _boardWordOptions) {
      if (button.row == row && button.col == col && !button.hidden) {
        return button;
      }
    }
    return null;
  }

  /// Batch-preload pictogram images for a freshly committed set of phrase/word
  /// options.  Runs entirely in the background so it never blocks the UI.
  void _preloadImagesForOptions({
    List<Map<String, String>>? phrases,
    List<String>? words,
    Map<String, List<String>>? wordKeywords,
  }) {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    if (userSettings.settings?.disableTapPictograms == true) return;
    if (userSettings.settings?.enablePictograms == false) return;

    final locale =
        _normalizeLocaleTag(userSettings.settings?.userLanguage) ?? 'en-US';

    final pictogramService = PictogramService();
    final currentUserId = userSettings.userId ?? widget.aacUserId;
    final currentIdToken = userSettings.idToken ?? widget.idToken;
    if (currentUserId.isNotEmpty && currentIdToken.isNotEmpty) {
      pictogramService.setUserContext(
        userId: currentUserId,
        idToken: currentIdToken,
        mascot: userSettings.settings?.mascot,
      );
    }
    pictogramService.enablePictograms = true;

    Future.microtask(() async {
      try {
        // Collect all terms we need images for.
        final allTerms = <String>[];

        if (phrases != null) {
          for (final p in phrases) {
            final fullText = p['fullText'] ?? '';
            final keywordsStr = p['keywords'] ?? '';
            final kws = keywordsStr.isNotEmpty
                ? keywordsStr
                      .split('|')
                      .where((s) => s.trim().isNotEmpty)
                      .toList()
                : null;
            final anchor = _derivePhraseImageSearchText(fullText, kws);
            if (anchor != null && anchor.isNotEmpty) allTerms.add(anchor);
          }
        }

        if (words != null) allTerms.addAll(words);

        if (allTerms.isNotEmpty) {
          final kwMap = wordKeywords ?? const <String, List<String>>{};
          await pictogramService.prefetchButtonPictograms(
            words: allTerms,
            keywordMap: kwMap,
            locale: locale,
            maxItems: allTerms.length,
          );
        }

        // Re-prime custom image match cache for the new set of terms.
        if (allTerms.isNotEmpty) {
          await pictogramService.preloadCustomImages(allTerms);
        }
      } catch (e) {
        debugPrint('[TapInterface] _preloadImagesForOptions error: $e');
      }
    });
  }

  /// Warm currently visible Words terms before revealing the section.
  /// This reduces phased image pop-in on board refresh.
  Future<void> _warmVisibleWordImages({
    required List<String> words,
    required Map<String, List<String>> wordKeywords,
    required List<TapBoardButton> boardButtons,
  }) async {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    if (userSettings.settings?.disableTapPictograms == true) return;
    if (userSettings.settings?.enablePictograms == false) return;

    final locale =
        _normalizeLocaleTag(userSettings.settings?.userLanguage) ?? 'en-US';
    final pictogramService = PictogramService();

    final currentUserId = userSettings.userId ?? widget.aacUserId;
    final currentIdToken = userSettings.idToken ?? widget.idToken;
    if (currentUserId.isNotEmpty && currentIdToken.isNotEmpty) {
      pictogramService.setUserContext(
        userId: currentUserId,
        idToken: currentIdToken,
        mascot: userSettings.settings?.mascot,
      );
    }
    pictogramService.enablePictograms = true;

    final preloadTerms = <String>[];
    preloadTerms.addAll(words);
    if (boardButtons.isNotEmpty) {
      for (final button in boardButtons) {
        if (button.hidden) continue;
        final term = (button.imageSearchText ?? button.text).trim();
        if (term.isNotEmpty) preloadTerms.add(term);
      }
    }

    if (preloadTerms.isEmpty) return;

    try {
      await pictogramService
          .prefetchButtonPictograms(
            words: preloadTerms,
            keywordMap: wordKeywords,
            locale: locale,
            maxItems: preloadTerms.length,
            shouldLogMissing: true,
          )
          .timeout(const Duration(milliseconds: 4200));
    } catch (e) {
      debugPrint('[TapInterface] Word warmup timeout/error: $e');
    }
  }

  Future<void> _warmVisiblePhraseImages({
    required List<Map<String, String>> phrases,
  }) async {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    if (userSettings.settings?.disableTapPictograms == true) return;
    if (userSettings.settings?.enablePictograms == false) return;

    final locale =
        _normalizeLocaleTag(userSettings.settings?.userLanguage) ?? 'en-US';
    final pictogramService = PictogramService();

    final currentUserId = userSettings.userId ?? widget.aacUserId;
    final currentIdToken = userSettings.idToken ?? widget.idToken;
    if (currentUserId.isNotEmpty && currentIdToken.isNotEmpty) {
      pictogramService.setUserContext(
        userId: currentUserId,
        idToken: currentIdToken,
        mascot: userSettings.settings?.mascot,
      );
    }
    pictogramService.enablePictograms = true;

    final phraseTerms = <String>[];
    for (final phrase in phrases) {
      final fullText = phrase['fullText'] ?? '';
      final keywordsStr = phrase['keywords'] ?? '';
      final keywords = keywordsStr.isNotEmpty
          ? keywordsStr.split('|').where((s) => s.trim().isNotEmpty).toList()
          : null;
      final anchor = _derivePhraseImageSearchText(fullText, keywords);
      if (anchor != null && anchor.isNotEmpty) {
        phraseTerms.add(anchor);
      }
    }

    if (phraseTerms.isEmpty) return;

    try {
      await pictogramService
          .prefetchButtonPictograms(
            words: phraseTerms,
            locale: locale,
            maxItems: phraseTerms.length,
            shouldLogMissing: true,
          )
          .timeout(const Duration(milliseconds: 3000));
    } catch (e) {
      debugPrint('[TapInterface] Phrase warmup timeout/error: $e');
    }
  }

  /// Preload category images in background for better performance
  void _preloadCategoryImages() async {
    if (_tapConfig == null || _isPreloadingImages) return;

    setState(() {
      _isPreloadingImages = true;
    });

    try {
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      if (userSettings.settings?.enablePictograms != true) {
        return; // Skip if pictograms disabled
      }

      final pictogramService = PictogramService();
      final currentUserId = userSettings.userId ?? widget.aacUserId;
      final currentIdToken = userSettings.idToken ?? widget.idToken;
      if (currentUserId.isNotEmpty && currentIdToken.isNotEmpty) {
        pictogramService.setUserContext(
          userId: currentUserId,
          idToken: currentIdToken,
          mascot: userSettings.settings?.mascot,
        );
      }
      pictogramService.enablePictograms = true;

      debugPrint(
        '🚀 Preloading ${_tapConfig!.buttons.length} category images...',
      );

      // Preload images for all categories in parallel (faster)
      final locale = userSettings.settings?.userLanguage ?? 'en-US';
      final futures = _tapConfig!.buttons.map((category) async {
        try {
          final result = await pictogramService.getPictogramResult(
            category.label,
            shouldLogMissing: false,
            locale: locale,
          );
          if (result?.imageUrl != null) {
            _imagePreloadCache[category.label] = result!.imageUrl;
            debugPrint('✅ Preloaded image for "${category.label}"');
          }
        } catch (e) {
          debugPrint('❌ Failed to preload image for "${category.label}": $e');
        }
      }).toList();

      // Wait for category image preloading to complete
      await Future.wait(futures);

      // Batch preload custom images for all button texts
      try {
        final allButtonTexts = <String>[];

        // Collect all category labels
        allButtonTexts.addAll(_tapConfig!.buttons.map((cat) => cat.label));

        // Collect all subcategory labels
        for (final category in _tapConfig!.buttons) {
          allButtonTexts.addAll(category.children.map((child) => child.label));
        }

        debugPrint(
          '🎯 Starting custom image batch preload for ${allButtonTexts.length} buttons...',
        );
        await pictogramService.preloadCustomImages(allButtonTexts);
      } catch (e) {
        debugPrint('❌ Custom image batch preload error: $e');
      }

      debugPrint('🚀 Category image preloading completed');
    } catch (e) {
      debugPrint('❌ Category image preloading failed: $e');
    } finally {
      setState(() {
        _isPreloadingImages = false;
      });
    }
  }

  /// Preload custom images for modal category children (non-blocking)
  void _preloadModalCustomImages(TapInterfaceCategory category) {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    if (userSettings.settings?.enablePictograms != true) return;

    // Run asynchronously without blocking modal display
    Future.microtask(() async {
      try {
        final pictogramService = PictogramService();
        final currentUserId = userSettings.userId ?? widget.aacUserId;
        final currentIdToken = userSettings.idToken ?? widget.idToken;
        if (currentUserId.isNotEmpty && currentIdToken.isNotEmpty) {
          pictogramService.setUserContext(
            userId: currentUserId,
            idToken: currentIdToken,
            mascot: userSettings.settings?.mascot,
          );
        }
        final childLabels = category.children
            .map((child) => child.label)
            .toList();

        if (childLabels.isNotEmpty) {
          debugPrint(
            '🎯 Preloading custom images for ${childLabels.length} modal buttons in "${category.label}"',
          );
          await pictogramService.preloadCustomImages(childLabels);
        }
      } catch (e) {
        debugPrint('❌ Modal custom image preload error: $e');
      }
    });
  }

  Future<void> _loadInitialFreestyleOptions({
    Map<String, dynamic>? contextData,
  }) async {
    try {
      setState(() {
        _isLoadingWordOptions = true;
      });

      debugPrint('[TapInterface] === INITIAL WORD OPTIONS LOADING ===');

      String initialContext = 'general communication topics';

      if (contextData != null) {
        final location = contextData['location'] as String? ?? '';
        final activity = contextData['activity'] as String? ?? '';
        final people = contextData['people'] as String? ?? '';

        List<String> contextParts = [];
        if (location.isNotEmpty) contextParts.add('at $location');
        if (activity.isNotEmpty) contextParts.add('doing $activity');
        if (people.isNotEmpty) contextParts.add('with $people');

        if (contextParts.isNotEmpty) {
          initialContext =
              'communication topics for someone ${contextParts.join(' ')}';
        }
      }

      // Load initial freestyle word options using dynamic count
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';

      final wordOpts = await _tapService.generateFreestyleOptions(
        context: initialContext,
        buildSpaceText: '',
        singleWordsOnly: true,
        maxOptions:
            requiredWordCount + 15, // Request extra to ensure we have enough
        currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
      );

      debugPrint(
        '[TapInterface] Initial API returned ${wordOpts.length} word options for $requiredWordCount slots',
      );
      debugPrint('[TapInterface] Initial options: $wordOpts');

      if (mounted) {
        // Ensure we have exactly the required number of options
        List<String> initialOptions = [];
        if (wordOpts.isNotEmpty) {
          initialOptions = wordOpts.take(requiredWordCount).toList();
        }

        // If we don't have enough, supplement with fallback
        if (initialOptions.length < requiredWordCount) {
          debugPrint(
            '[TapInterface] Only have ${initialOptions.length} initial options, need $requiredWordCount. Adding fallbacks...',
          );
          final currentWordsSet = initialOptions.toSet();
          final fallbackOptions = _getFallbackWordOptions();
          final additionalOptions = fallbackOptions
              .where((word) => !currentWordsSet.contains(word))
              .take(requiredWordCount - initialOptions.length)
              .toList();
          initialOptions.addAll(additionalOptions);
          debugPrint(
            '[TapInterface] Added ${additionalOptions.length} fallback options, total now: ${initialOptions.length}',
          );
        }

        final sourceInitialOptions = List<String>.from(initialOptions);
        initialOptions = await _localizeWordsForUserIfNeeded(initialOptions);
        final localizedInitialKeywords = _buildLocalizedKeywordFallbackMap(
          sourceInitialOptions,
          initialOptions,
        );

        // Clear stale null cache entries so all words get a fresh image lookup
        // with the current keywords (fixes regression where persisted nulls blocked lookups).
        await PictogramService().clearNullCacheEntries();

        setState(() {
          _wordOptions = _deduplicateWords(initialOptions);
          _wordKeywords = localizedInitialKeywords;
          _isLoadingWordOptions = false;
        });
        final resolvedLocale =
            _normalizeLocaleTag(userSettings.settings?.userLanguage) ??
            'en-US';
        _lastInitialWordOptionsLocale = resolvedLocale;

        final preloadWords = List<String>.from(_wordOptions);
        final preloadKeywords = Map<String, List<String>>.from(_wordKeywords);
        Future.microtask(() async {
          try {
            await PictogramService().prefetchButtonPictograms(
              words: preloadWords,
              keywordMap: preloadKeywords,
              locale: resolvedLocale,
              maxItems: preloadWords.length,
            );
          } catch (e) {
            debugPrint('[TapInterface] Pictogram prefetch error: $e');
          }
        });
        _validateWordOptions(); // Validate after setting options
        debugPrint(
          '[TapInterface] Initial UI set with exactly ${_wordOptions.length} word options',
        );
      }
    } catch (e) {
      debugPrint('[TapInterface] ERROR in initial freestyle options: $e');
      if (mounted) {
        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        final sourceFallback = _getFallbackWordOptions()
            .take(requiredWordCount)
            .toList();
        final localizedFallback = await _localizeWordsForUserIfNeeded(
          sourceFallback,
        );
        setState(() {
          _isLoadingWordOptions = false;
          _wordOptions = _deduplicateWords(localizedFallback);
          _wordKeywords = _buildLocalizedKeywordFallbackMap(
            sourceFallback,
            localizedFallback,
          );
        });
        final resolvedLocale =
            _normalizeLocaleTag(userSettings.settings?.userLanguage) ??
            'en-US';
        _lastInitialWordOptionsLocale = resolvedLocale;

        final preloadWords = List<String>.from(_wordOptions);
        final preloadKeywords = Map<String, List<String>>.from(_wordKeywords);
        Future.microtask(() async {
          try {
            await PictogramService().prefetchButtonPictograms(
              words: preloadWords,
              keywordMap: preloadKeywords,
              locale: resolvedLocale,
              maxItems: preloadWords.length,
            );
          } catch (e) {
            debugPrint('[TapInterface] Pictogram prefetch error (fallback): $e');
          }
        });
        debugPrint('[TapInterface] Using fallback options: $_wordOptions');
      }
    }
  }

  /// Helper method to deduplicate words (case-insensitive) while preserving original capitalization
  /// Extract a category/topic from a question for word generation
  /// Example: "Where do you want to go for our vacation" -> "vacation destinations"
  String _extractCategoryFromQuestion(String question) {
    final lowerQuestion = question.toLowerCase();

    // Superhero/character related (check BEFORE generic "who" check)
    if (lowerQuestion.contains('superhero') ||
        lowerQuestion.contains('super hero')) {
      return 'superheroes and comic book characters';
    }

    // Favorite [specific thing] questions - extract the specific topic
    if (lowerQuestion.contains('favorite') ||
        lowerQuestion.contains('favourite')) {
      if (lowerQuestion.contains('movie') || lowerQuestion.contains('film')) {
        return 'movies and films';
      }
      if (lowerQuestion.contains('book')) {
        return 'books and stories';
      }
      if (lowerQuestion.contains('song') || lowerQuestion.contains('music')) {
        return 'songs and music';
      }
      if (lowerQuestion.contains('color') || lowerQuestion.contains('colour')) {
        return 'colors';
      }
      if (lowerQuestion.contains('animal')) {
        return 'animals';
      }
      if (lowerQuestion.contains('sport')) {
        return 'sports and athletics';
      }
      if (lowerQuestion.contains('team')) {
        return 'sports teams';
      }
    }

    // Vacation/travel related
    if (lowerQuestion.contains('vacation') ||
        lowerQuestion.contains('holiday')) {
      return 'vacation destinations and travel places';
    }

    // Food related
    if (lowerQuestion.contains('eat') ||
        lowerQuestion.contains('food') ||
        lowerQuestion.contains('dinner') ||
        lowerQuestion.contains('lunch') ||
        lowerQuestion.contains('breakfast') ||
        lowerQuestion.contains('snack')) {
      return 'foods and meals';
    }

    // Activity related
    if (lowerQuestion.contains('play') ||
        lowerQuestion.contains('game') ||
        lowerQuestion.contains('activity') ||
        lowerQuestion.contains('do')) {
      return 'activities and games';
    }

    // Feelings related
    if (lowerQuestion.contains('feel') || lowerQuestion.contains('emotion')) {
      return 'feelings and emotions';
    }

    // People related (only for generic "who" questions without specific topics)
    if (lowerQuestion.contains('who')) {
      return 'people and family members';
    }

    // Place related (where questions)
    if (lowerQuestion.contains('where') || lowerQuestion.contains('place')) {
      if (lowerQuestion.contains('go')) {
        return 'places to go and destinations';
      }
      return 'locations and places';
    }

    // Time related
    if (lowerQuestion.contains('when') || lowerQuestion.contains('time')) {
      return 'times and schedules';
    }

    // Default: use the question itself as a topic
    // Remove question words and extract the main subject
    String topic = lowerQuestion
        .replaceAll(
          RegExp(
            r'\b(what|where|when|who|why|how|do|does|did|is|are|was|were|can|could|would|should)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'[?!.,]'), '')
        .trim();

    if (topic.isEmpty) {
      return 'general conversation topics';
    }

    return topic;
  }

  List<String> _deduplicateWords(List<String> words) {
    final deduplicatedWords = <String>[];
    final seenLowercase = <String>{};
    final duplicatesRemoved = <String>[];
    final duplicateDetails = <String, List<String>>{};

    for (final word in words) {
      final lowerWord = word.toLowerCase();
      if (!seenLowercase.contains(lowerWord)) {
        seenLowercase.add(lowerWord);
        deduplicatedWords.add(word); // Keep original capitalization
      } else {
        duplicatesRemoved.add(word);
        // Track which words had duplicates
        duplicateDetails[lowerWord] ??= [];
        duplicateDetails[lowerWord]!.add(word);
      }
    }

    if (duplicatesRemoved.isNotEmpty) {
      debugPrint(
        '🔧 DEDUPLICATION: Removed ${duplicatesRemoved.length} duplicates: $duplicatesRemoved',
      );
      debugPrint(
        '🔧 DEDUPLICATION: Original count: ${words.length}, Final count: ${deduplicatedWords.length}',
      );

      // Show detailed duplicate information
      for (final entry in duplicateDetails.entries) {
        final baseWord = entry.key;
        final variants = entry.value;
        debugPrint(
          '🔧 DUPLICATE FOUND: "$baseWord" had variants: ${variants.join(", ")}',
        );
      }

      // Show full input list for debugging
      debugPrint('🔧 DEDUPLICATION INPUT: $words');
      debugPrint('🔧 DEDUPLICATION OUTPUT: $deduplicatedWords');
    }

    return deduplicatedWords;
  }

  Future<List<String>> _localizeWordsForUserIfNeeded(List<String> words) async {
    if (words.isEmpty) return words;
    try {
      final localized = await _tapService.localizeWordListForUserLocale(
        words: words,
      );
      return localized.isNotEmpty ? localized : words;
    } catch (e) {
      debugPrint('[TapInterface] Word localization enforcement failed: $e');
      return words;
    }
  }

  Map<String, List<String>> _buildLocalizedKeywordFallbackMap(
    List<String> sourceWords,
    List<String> localizedWords, {
    Map<String, List<String>> existingKeywords = const {},
  }) {
    final localizedKeywordsMap = <String, List<String>>{};
    final mapLength = sourceWords.length < localizedWords.length
        ? sourceWords.length
        : localizedWords.length;

    for (var i = 0; i < mapLength; i++) {
      final sourceWord = sourceWords[i].trim();
      final localizedWord = localizedWords[i].trim();
      if (sourceWord.isEmpty || localizedWord.isEmpty) continue;

      final mergedKeywords = <String>[];
      final seen = <String>{};

      void addKeyword(String keyword) {
        final normalized = keyword.trim();
        if (normalized.isEmpty) return;
        final dedupeKey = normalized.toLowerCase();
        if (seen.add(dedupeKey)) {
          mergedKeywords.add(normalized);
        }
      }

      addKeyword(sourceWord);
      final sourceKeywords = existingKeywords[sourceWord] ?? const <String>[];
      for (final keyword in sourceKeywords) {
        addKeyword(keyword);
      }

      if (mergedKeywords.isNotEmpty) {
        localizedKeywordsMap[localizedWord] = mergedKeywords;
      }
    }

    return localizedKeywordsMap;
  }

  /// Validates if words are appropriate for the given category
  List<String> _validateWordsForCategory(
    List<String> words,
    String categoryLabel,
  ) {
    final validWords = <String>[];
    final inappropriateWords = <String>[];

    // Define category-specific validation rules
    final categoryLower = _canonicalizeCategoryLabel(categoryLabel);

    for (final word in words) {
      final wordLower = word.toLowerCase();
      bool isAppropriate = true;

      if (categoryLower.contains('number') ||
          categoryLower.contains('amount') ||
          categoryLower.contains('quantit')) {
        // For Numbers & Quantities category, only allow actual numbers and quantity words
        final numberWords = [
          'zero',
          'one',
          'two',
          'three',
          'four',
          'five',
          'six',
          'seven',
          'eight',
          'nine',
          'ten',
          'eleven',
          'twelve',
          'thirteen',
          'fourteen',
          'fifteen',
          'sixteen',
          'seventeen',
          'eighteen',
          'nineteen',
          'twenty',
          'thirty',
          'forty',
          'fifty',
          'sixty',
          'seventy',
          'eighty',
          'ninety',
          'hundred',
          'thousand',
          'million',
          'many',
          'few',
          'some',
          'all',
          'none',
          'more',
          'less',
          'most',
          'least',
          'several',
          'couple',
          'half',
          'whole',
          'quarter',
          'third',
          'first',
          'second',
          'last',
          'next',
          'another',
          'both',
          'single',
          'double',
          'triple',
          'multiple',
          'enough',
          'plenty',
          'empty',
          'full',
          'extra',
        ];
        isAppropriate =
            numberWords.contains(wordLower) ||
            RegExp(r'^\d+$').hasMatch(wordLower);

        // Also reject obvious non-number words like sports teams or places
        final inappropriateForNumbers = [
          'broncos',
          'disney',
          'world',
          'park',
          'team',
          'game',
          'movie',
          'show',
          'place',
          'location',
        ];
        if (inappropriateForNumbers.any(
          (inappropriate) => wordLower.contains(inappropriate),
        )) {
          isAppropriate = false;
        }
      }

      if (isAppropriate) {
        validWords.add(word);
      } else {
        inappropriateWords.add(word);
      }
    }

    if (inappropriateWords.isNotEmpty) {
      debugPrint(
        '[TapInterface] 🚨 FILTERED OUT inappropriate words for "$categoryLabel": $inappropriateWords',
      );
      debugPrint(
        '[TapInterface] ✅ KEEPING valid words for "$categoryLabel": ${validWords.take(10).toList()}...',
      );
    }

    return validWords;
  }

  List<String> _getFallbackWordOptions() {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final locale =
        _normalizeLocaleTag(settingsProvider.settings?.userLanguage) ??
        'en-US';

    // Keep startup deterministic: if backend/localization is delayed, seed
    // fallback words directly in the user's language.
    if (locale.startsWith('es')) {
      return [
        'yo', 'quiero', 'necesito', 'ayuda', 'por favor', 'gracias', 'si',
        'no', 'mas', 'para', 'detener', 'comer', 'beber', 'jugar', 'casa',
        'escuela', 'trabajo', 'feliz', 'triste', 'cansado', 'terminado',
        'puedo', 'tener', 'ir', 'venir', 'aqui', 'ahi', 'ahora', 'luego',
        'hoy', 'manana', 'adentro', 'afuera', 'grande', 'pequeno', 'caminar',
        'correr', 'sentar', 'leer', 'escribir', 'escuchar', 'hablar', 'mama',
        'papa', 'familia', 'amigo', 'doctor', 'persona', 'coche', 'parque',
      ];
    }

    if (locale.startsWith('fr')) {
      return [
        'je', 'veux', 'besoin', 'aide', 's il vous plait', 'merci', 'oui',
        'non', 'plus', 'arreter', 'manger', 'boire', 'jouer', 'maison',
        'ecole', 'travail', 'heureux', 'triste', 'fatigue', 'fini', 'peux',
        'avoir', 'aller', 'venir', 'ici', 'la', 'maintenant', 'plus tard',
        'aujourd hui', 'demain', 'dedans', 'dehors', 'grand', 'petit', 'marcher',
        'courir', 'asseoir', 'lire', 'ecrire', 'ecouter', 'parler', 'maman',
        'papa', 'famille', 'ami', 'docteur', 'personne', 'voiture', 'parc',
      ];
    }

    if (locale.startsWith('de')) {
      return [
        'ich', 'will', 'brauche', 'hilfe', 'bitte', 'danke', 'ja', 'nein',
        'mehr', 'stopp', 'essen', 'trinken', 'spielen', 'haus', 'schule',
        'arbeit', 'glucklich', 'traurig', 'mude', 'fertig', 'kann', 'haben',
        'gehen', 'kommen', 'hier', 'dort', 'jetzt', 'spater', 'heute',
        'morgen', 'drinnen', 'draussen', 'gross', 'klein', 'laufen',
        'sitzen', 'lesen', 'schreiben', 'zuhoren', 'sprechen', 'mama',
        'papa', 'familie', 'freund', 'arzt', 'person', 'auto', 'park',
      ];
    }

    if (locale.startsWith('it')) {
      return [
        'io', 'voglio', 'ho bisogno', 'aiuto', 'per favore', 'grazie', 'si',
        'no', 'piu', 'ferma', 'mangiare', 'bere', 'giocare', 'casa', 'scuola',
        'lavoro', 'felice', 'triste', 'stanco', 'finito', 'posso', 'avere',
        'andare', 'venire', 'qui', 'li', 'adesso', 'dopo', 'oggi', 'domani',
        'dentro', 'fuori', 'grande', 'piccolo', 'camminare', 'correre',
        'sedere', 'leggere', 'scrivere', 'ascoltare', 'parlare', 'mamma',
        'papa', 'famiglia', 'amico', 'dottore', 'persona', 'auto', 'parco',
      ];
    }

    if (locale.startsWith('pt')) {
      return [
        'eu', 'quero', 'preciso', 'ajuda', 'por favor', 'obrigado', 'sim',
        'nao', 'mais', 'parar', 'comer', 'beber', 'brincar', 'casa', 'escola',
        'trabalho', 'feliz', 'triste', 'cansado', 'pronto', 'posso', 'ter',
        'ir', 'vir', 'aqui', 'la', 'agora', 'depois', 'hoje', 'amanha',
        'dentro', 'fora', 'grande', 'pequeno', 'andar', 'correr', 'sentar',
        'ler', 'escrever', 'escutar', 'falar', 'mae', 'pai', 'familia',
        'amigo', 'medico', 'pessoa', 'carro', 'parque',
      ];
    }

    if (locale.startsWith('ar')) {
      return [
        'انا', 'اريد', 'احتاج', 'مساعدة', 'من فضلك', 'شكرا', 'نعم', 'لا',
        'اكثر', 'توقف', 'اكل', 'اشرب', 'العب', 'بيت', 'مدرسة', 'عمل', 'سعيد',
        'حزين', 'متعب', 'انتهيت', 'استطيع', 'اذهب', 'تعال', 'هنا', 'هناك',
        'الان', 'لاحقا', 'اليوم', 'غدا', 'داخل', 'خارج', 'كبير', 'صغير',
        'امشي', 'اجري', 'اجلس', 'اقرا', 'اكتب', 'اسمع', 'اتكلم', 'ماما',
        'بابا', 'عائلة', 'صديق', 'طبيب', 'شخص', 'سيارة', 'حديقة',
      ];
    }

    // Default English fallback pool.
    return [
      'I', 'want', 'need', 'like', 'go', 'help', 'please', 'thank', 'you',
      'yes', 'no', 'good', 'bad', 'more', 'stop', 'eat', 'drink', 'play',
      'home', 'work', 'school', 'happy', 'sad', 'tired', 'done', 'okay',
      'can', 'will', 'have', 'get', 'see', 'know', 'think', 'feel', 'look',
      'come', 'here', 'there', 'now', 'later', 'today', 'tomorrow',
      'yesterday', 'up', 'down', 'in', 'out', 'on', 'off', 'big', 'small',
      'hot', 'cold', 'walk', 'run', 'sit', 'stand', 'read', 'write', 'watch',
      'listen', 'talk', 'call', 'text', 'drive', 'cook', 'clean', 'sleep',
      'wake', 'mom', 'dad', 'family', 'friend', 'teacher', 'doctor', 'person',
      'baby', 'child', 'man', 'woman', 'boy', 'girl', 'everyone', 'someone',
      'nobody', 'house', 'room', 'kitchen', 'bathroom', 'bedroom', 'outside',
      'inside', 'store', 'park', 'hospital', 'restaurant', 'car', 'bus',
      'train', 'always', 'never', 'sometimes', 'often', 'soon', 'before',
      'after', 'first', 'last', 'next', 'again', 'still', 'already',
      'finish', 'angry', 'excited', 'worried', 'scared', 'proud', 'calm',
      'confused', 'surprised', 'lonely', 'grateful', 'nervous', 'relaxed',
      'hurt', 'love', 'what', 'where', 'when', 'why', 'how', 'who', 'which',
      'maybe', 'sure', 'sorry', 'excuse', 'welcome', 'goodbye', 'hello', 'hi',
    ];
  }

  List<String> _getFallbackPhraseOptions() {
    // Return comprehensive phrase pool for fallback when LLM is unavailable
    return [
      'Hello there',
      'How are you?',
      'I am fine',
      'Thank you very much',
      'Please help me',
      'Yes, that sounds good',
      'No, I don\'t think so',
      'I would like that',
      'Can you help?',
      'I am hungry',
      'I want to go',
      'I need to rest',
      'That was great',
      'I feel good',
      'See you later',
      'Good morning',
      'Good afternoon',
      'Good evening',
      'Have a nice day',
      'I am tired',
      'I am happy',
      'I am sad',
      'I am excited',
      'Let me think',
      'That\'s interesting',
      'I understand',
      'I don\'t understand',
      'Can you repeat?',
      'Excuse me',
      'I\'m sorry',
      'No problem',
      'You\'re welcome',
      'Nice to meet you',
      'Take care',
      'I love you',
      'I miss you',
      'How was your day?',
      'What are you doing?',
      'Where are you going?',
      'I want to eat',
      'I want to drink',
      'I want to sleep',
      'I want to play',
      'I want to work',
      'I am done',
      'I am finished',
      'I am ready',
      'Wait for me',
      'I am coming',
    ];
  }

  Future<void> _loadInitialPhraseOptions({
    Map<String, dynamic>? contextData,
  }) async {
    try {
      debugPrint('[TapInterface] Loading initial phrase options...');
      setState(() {
        _isLoadingPhraseOptions = true;
      });

      // Generate basic phrase options for the top 2 rows using the new method with mood context
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';

      String initialContext =
          'general conversation starters and common phrases';

      // If specific context data is provided (e.g. from loading a favorite), use it to make options more relevant
      if (contextData != null) {
        final location = contextData['location'] as String? ?? '';
        final activity = contextData['activity'] as String? ?? '';
        final people = contextData['people'] as String? ?? '';

        List<String> contextParts = [];
        if (location.isNotEmpty) contextParts.add('at $location');
        if (activity.isNotEmpty) contextParts.add('doing $activity');
        if (people.isNotEmpty) contextParts.add('with $people');

        if (contextParts.isNotEmpty) {
          initialContext =
              'conversation starters and phrases for someone ${contextParts.join(' ')}';
        }
      }

      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        initialContext += ' while feeling $currentMood';
      }

      if (mounted) {
        try {
          final userSettings = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final requiredPhraseCount = _phraseSlotCount(userSettings.settings);

          final phraseOpts = await _tapService.generateLLMPhraseOptions(
            context: initialContext,
            maxOptions:
                requiredPhraseCount +
                10, // Request extra to ensure we have enough
            currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
          );

          if (mounted) {
            // Take exactly the required number of options for display (leaving 1 slot for Something Else button)
            List<Map<String, String>> initialPhraseOptions = phraseOpts
                .take(requiredPhraseCount)
                .toList();

            // If we don't have enough options, supplement with fallback
            if (initialPhraseOptions.length < requiredPhraseCount) {
              debugPrint(
                '[TapInterface] Only have ${initialPhraseOptions.length} initial phrase options, need $requiredPhraseCount. Adding fallbacks...',
              );
              final currentTexts = initialPhraseOptions
                  .map((p) => p['fullText'] ?? '')
                  .toSet();
              final fallbackPhraseTexts = [
                'Hello there',
                'How are you doing?',
                'Thank you very much',
                'Please help me',
                'Yes, that sounds good',
                'No, I don\'t think so',
                'I need help',
                'That\'s great',
                'I understand',
                'Let me think',
                'Good morning',
                'Good afternoon',
                'Good evening',
                'See you later',
                'Have a nice day',
                'Take care',
                'You\'re welcome',
              ];
              final additionalOptions = fallbackPhraseTexts
                  .where((text) => !currentTexts.contains(text))
                  .take(requiredPhraseCount - initialPhraseOptions.length)
                  .map(
                    (text) => {
                      'summary': text.length > 30
                          ? '${text.substring(0, 30)}...'
                          : text,
                      'fullText': text,
                    },
                  )
                  .toList();
              initialPhraseOptions.addAll(additionalOptions);
              debugPrint(
                '[TapInterface] Added ${additionalOptions.length} fallback phrase options, total now: ${initialPhraseOptions.length}',
              );
            }

            setState(() {
              _phraseOptions = initialPhraseOptions;
            });
            debugPrint(
              '[TapInterface] Loaded exactly ${_phraseOptions.length} phrase options for display',
            );
            _preloadImagesForOptions(phrases: initialPhraseOptions);
          }
        } catch (e) {
          debugPrint('[TapInterface] Error loading phrase options: $e');
          if (mounted) {
            setState(() {
              _phraseOptions = [
                {'summary': 'Hello', 'fullText': 'Hello there'},
                {'summary': 'How are you?', 'fullText': 'How are you doing?'},
                {'summary': 'Thank you', 'fullText': 'Thank you very much'},
                {'summary': 'Please', 'fullText': 'Please help me'},
                {'summary': 'Yes', 'fullText': 'Yes, that sounds good'},
                {'summary': 'No', 'fullText': 'No, I don\'t think so'},
              ];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[TapInterface] Error in _loadInitialPhraseOptions: $e');
      if (mounted) {
        setState(() {
          _phraseOptions = [
            {'summary': 'Hello', 'fullText': 'Hello there'},
            {'summary': 'How are you?', 'fullText': 'How are you doing?'},
            {'summary': 'Thank you', 'fullText': 'Thank you very much'},
          ];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPhraseOptions = false;
        });
      }
    }
  }

  void _showAllCategoriesModal() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.95,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.library_books, color: Colors.purple[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'All Boards',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              // Categories Grid
              Expanded(
                child: Consumer<UserSettingsProvider>(
                  builder: (context, provider, child) {
                    final userSettings = provider.settings;
                    final tapPictogramsDisabled =
                        userSettings?.disableTapPictograms ?? false;
                    final tapPictogramsEnabled = !tapPictogramsDisabled;
                    final tapSightWordLogicEnabled =
                        !tapPictogramsDisabled &&
                        (userSettings?.enableSightWords ?? true);
                    final gridColumns = userSettings?.gridColumns ?? 6;

                    return GridView.count(
                      crossAxisCount: gridColumns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      children: (_tapConfig?.buttons ?? [])
                          .where((category) => !category.hidden)
                          .map((category) {
                            final isSelected = _selectedCategory == category;
                            final headerTextColor =
                                Colors.purple[700] ?? Colors.purple.shade700;
                            return TapInterfaceButton(
                              label: category.label,
                              onPressed: () {
                                Navigator.of(context).pop(); // Close modal
                                _handleCategoryTap(category);
                              },
                              backgroundColor: isSelected
                                  ? headerTextColor.withOpacity(0.8)
                                  : Colors.white,
                              foregroundColor: isSelected
                                  ? Colors.white
                                  : Colors.black87,
                              borderColor: isSelected
                                  ? headerTextColor
                                  : Colors.purple[300] ??
                                        Colors.purple.shade300,
                              fontSize: 18,
                              enablePictograms: tapPictogramsEnabled,
                              sightWordGradeLevel:
                                  userSettings?.sightWordGradeLevel,
                              enableSightWords: tapSightWordLogicEnabled,
                              padding: const EdgeInsets.all(2),
                              assignedImageUrl: category
                                  .imageUrl, // Pass assigned image URL from database
                              shouldLogMissing:
                                  false, // Don't log missing images for category navigation buttons
                                cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
                                mascot: userSettings?.mascot ?? '',
                            );
                          })
                          .toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCategoryTap(TapInterfaceCategory category) async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[TapInterface] === CATEGORY TAP START ===');
    debugPrint(
      '[TapInterface] Category: ${category.label} (ID: ${category.id})',
    );
    debugPrint(
      '[TapInterface] Category mode: hasChildren=${category.hasChildren}, hasBoardWordOptions=${category.hasBoardWordOptions}, hasStaticOptions=${category.hasStaticOptions}, hasWordsPrompt=${category.hasWordsPrompt}, hasLLMQuery=${category.hasLLMQuery}, boardId=${category.boardId}',
    );

    // Announce the speech text if available FIRST
    if (category.speechText != null && category.speechText!.isNotEmpty) {
      _announceViaBackend(category.speechText!).catchError((e) {
        debugPrint('[TapInterface] ❌ Error announcing speech text: $e');
      });
    }

    // Play custom audio if available AFTER speech announcement
    if (category.hasCustomAudioFile) {
      _playCustomAudio(category.customAudioFile!).catchError((e) {
        debugPrint('[TapInterface] ❌ Error playing custom audio: $e');
      });
    }

    // Check for special page
    if (category.hasSpecialPage) {
      _handleSpecialPage(category.specialPage!);
      return;
    }

    if (category.hasChildren) {
      _showCategoryModal(category);
      return;
    }

    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final locale =
        _normalizeLocaleTag(userSettings.settings?.userLanguage) ?? 'en-US';
    final categoryCacheKey = '${category.id}|$locale';

    final cacheTimestamp = _categoryOptionsCacheTimestamp[categoryCacheKey];
    final cacheIsFresh =
        cacheTimestamp != null &&
        DateTime.now().difference(cacheTimestamp) <= _categoryOptionsCacheTtl;
    final cachedPhrases = _categoryPhraseCache[categoryCacheKey] ?? const [];
    final cachedWords = _categoryWordCache[categoryCacheKey] ?? const [];
    final cachedBoardButtons =
        _categoryBoardButtonsCache[categoryCacheKey] ?? const <TapBoardButton>[];
    final hasCachedPhraseOptions = cachedPhrases.isNotEmpty;
    final hasCachedWordOptions =
      cachedWords.isNotEmpty || cachedBoardButtons.isNotEmpty;
    final hasCachedCategoryOptions =
        cacheIsFresh &&
        _categoryPhraseCache.containsKey(categoryCacheKey) &&
        _categoryWordCache.containsKey(categoryCacheKey) &&
      hasCachedPhraseOptions &&
      hasCachedWordOptions;

    debugPrint(
      '[TapInterface] Category cache: key=$categoryCacheKey, fresh=$cacheIsFresh, hasCachedCategoryOptions=$hasCachedCategoryOptions, hasCachedPhraseOptions=$hasCachedPhraseOptions, hasCachedWordOptions=$hasCachedWordOptions, cachedPhrases=${cachedPhrases.length}, cachedWords=${cachedWords.length}, cachedBoardButtons=${cachedBoardButtons.length}',
    );

    if (hasCachedCategoryOptions) {
      debugPrint(
        '[TapInterface] ⚡ Using cached options for category: ${category.label} (key=$categoryCacheKey)',
      );
      final cachedWordKeywords =
          _categoryWordKeywordsCache[categoryCacheKey] ??
          const <String, List<String>>{};
      setState(() {
        _selectedCategory = category;
        _phraseOptions = cachedPhrases;
        _wordOptions = cachedWords;
        _wordKeywords = cachedWordKeywords;
        _boardWordOptions = cachedBoardButtons;
        _textPromptUsed = false;
        _isLoadingPhraseOptions = true;
        _isLoadingWordOptions = true;
        _variantMode = null;
      });

      if (cachedBoardButtons.isNotEmpty) {
        // For boards: show content immediately, warm images in the background.
        _warmVisiblePhraseImages(phrases: cachedPhrases); // fire-and-forget
        _warmVisibleWordImages(
          words: cachedWords,
          wordKeywords: cachedWordKeywords,
          boardButtons: cachedBoardButtons,
        ); // fire-and-forget
        if (!mounted || _selectedCategory?.id != category.id) return;
        setState(() {
          _isLoadingPhraseOptions = false;
          _isLoadingWordOptions = false;
          _optionsRebuildKey++;
        });
      } else {
        await Future.wait([
          _warmVisiblePhraseImages(phrases: cachedPhrases),
          _warmVisibleWordImages(
            words: cachedWords,
            wordKeywords: cachedWordKeywords,
            boardButtons: const [],
          ),
        ]);
        if (!mounted || _selectedCategory?.id != category.id) {
          return;
        }
        setState(() {
          _isLoadingPhraseOptions = false;
          _isLoadingWordOptions = false;
          _optionsRebuildKey++;
        });
      }
      // For boards, the word cache stores raw board-button texts, not filtered
      // AI words. Use the AI word cache when available (fast path: no API call),
      // otherwise fall back to generating them fresh.
      if (cachedBoardButtons.isNotEmpty && mounted &&
          _selectedCategory?.id == category.id) {
        final cachedAIWords = _categoryAIWordCache[categoryCacheKey];
        if (cachedAIWords != null && cachedAIWords.isNotEmpty) {
          setState(() {
            _wordOptions = cachedAIWords;
          });
        } else {
          _loadWordOptionsBasedOnBuildSpace();
        }
      }
      return;
    }

    debugPrint(
      '[TapInterface] Setting _selectedCategory to: ${category.label}',
    );
    final previousBoardId = _getCategoryBoardId(_selectedCategory);
    final nextBoardId = _getCategoryBoardId(category);
    if (previousBoardId != null && previousBoardId != nextBoardId) {
      _clearActiveBoardModifier(previousBoardId);
    }

    // Synchronously resolve board buttons so they appear in the same frame as
    // the navigation instead of waiting for the async _loadCategoryWords chain.
    List<TapBoardButton> synchronousButtons = [];
    if (category.hasBoardWordOptions && category.boardWordOptions.isNotEmpty) {
      synchronousButtons =
          category.boardWordOptions.where((b) => !b.hidden).toList();
    } else if ((category.boardId ?? '').trim().isNotEmpty) {
      final board = _tapBoards?.boards
          .where((b) => b.id.trim() == category.boardId!.trim())
          .firstOrNull;
      if (board != null) {
        synchronousButtons = board.buttons.where((b) => !b.hidden).toList();
      }
    }

    setState(() {
      _selectedCategory = category;
      _activeWordLetterFilter = null;
      _currentQuestion = '';
      _isLoadingPhraseOptions = true;
      _isLoadingWordOptions = true;
      _phraseOptions = [];
      _wordOptions = [];
      _usedWordOptions.clear();
      _boardWordOptions = synchronousButtons; // pre-fill; async load will localize
      _textPromptUsed = false;
      _variantMode = null;
    });

    // If we already have board buttons, kick off dynamic-word generation now
    // rather than waiting for _loadCategoryWords to complete its async chain.
    // Track whether we did so to avoid a redundant second call from .then().
    final bool startedAIWordLoadSynchronously = synchronousButtons.isNotEmpty;
    if (startedAIWordLoadSynchronously && mounted) {
      _loadWordOptionsBasedOnBuildSpace();
    }

    // We need to know if we are still on the same category when results come back
    final String targetCategoryId = category.id;

    // 1. Load Phrases
    _loadCategoryPhrases(category)
      .then((phrases) async {
          debugPrint(
            '[TapInterface] 🕒 Phrases loaded in ${stopwatch.elapsedMilliseconds}ms',
          );
          if (!mounted) return;
          if (_selectedCategory?.id != targetCategoryId) {
            debugPrint(
              '[TapInterface] ⚠️ Ignoring phrase results for old category',
            );
            return;
          }

          setState(() {
            _phraseOptions = phrases;
            _categoryPhraseCache[categoryCacheKey] = phrases;
            _categoryOptionsCacheTimestamp[categoryCacheKey] = DateTime.now();
            _isLoadingPhraseOptions = true;
          });
          await _warmVisiblePhraseImages(phrases: phrases);
          if (!mounted || _selectedCategory?.id != targetCategoryId) {
            return;
          }
          setState(() {
            _isLoadingPhraseOptions = false;
            _optionsRebuildKey++;
          });
        })
        .catchError((e) {
          debugPrint('[TapInterface] ❌ Error loading phrases: $e');
          if (mounted && _selectedCategory?.id == targetCategoryId) {
            setState(() {
              _isLoadingPhraseOptions = false;
            });
          }
        });

    // 2. Load Words
    _loadCategoryWords(category)
      .then((result) async {
          debugPrint(
            '[TapInterface] 🕒 Words loaded in ${stopwatch.elapsedMilliseconds}ms',
          );
          if (!mounted) return;
          if (_selectedCategory?.id != targetCategoryId) {
            debugPrint(
              '[TapInterface] ⚠️ Ignoring word results for old category',
            );
            return;
          }

          final words = result['words'] as List<String>;
          final keywords = result['keywords'] as Map<String, List<String>>;
          final boardButtons =
              result['boardButtons'] as List<TapBoardButton>? ?? const [];

          setState(() {
            _wordOptions = words;
            _boardWordOptions = boardButtons;
            _wordKeywords = keywords;
            _categoryWordCache[categoryCacheKey] = List<String>.from(words);
            _categoryWordKeywordsCache[categoryCacheKey] = keywords;
            _categoryBoardButtonsCache[categoryCacheKey] = boardButtons;
            _categoryOptionsCacheTimestamp[categoryCacheKey] = DateTime.now();
            _isLoadingWordOptions = true;

            // IMPORTANT: Clear session-tracked missing images when loading fresh words for new category
            // This allows us to log any missing images from this category's word set
            _globalSessionLoggedMissingImages.clear();
            debugPrint(
              '📋 Cleared session-tracked missing images for new category: ${category.label}',
            );
          });

          if (boardButtons.isNotEmpty) {
            // For boards: show buttons immediately — don't block on image warming.
            // Pictograms will appear as they load in the background.
            _warmVisibleWordImages(
              words: words,
              wordKeywords: keywords,
              boardButtons: boardButtons,
            ); // fire-and-forget
            if (!mounted || _selectedCategory?.id != targetCategoryId) return;
            setState(() {
              _isLoadingWordOptions = false;
              _optionsRebuildKey++;
            });
            // Start AI dynamic-row generation. Skip if the synchronous pre-fill
            // already kicked it off — avoids a redundant second API call.
            if (!startedAIWordLoadSynchronously) {
              _loadWordOptionsBasedOnBuildSpace();
            }
          } else {
            // For non-board categories: original behaviour (wait for image warm-up
            // so pictograms are ready when words appear).
            await _warmVisibleWordImages(
              words: words,
              wordKeywords: keywords,
              boardButtons: boardButtons,
            );
            if (!mounted || _selectedCategory?.id != targetCategoryId) return;
            setState(() {
              _isLoadingWordOptions = false;
              _optionsRebuildKey++;
            });
          }
        })
        .catchError((e) {
          debugPrint('[TapInterface] ❌ Error loading words: $e');
          if (mounted && _selectedCategory?.id == targetCategoryId) {
            setState(() {
              _wordOptions = [];
              _boardWordOptions = [];
              _isLoadingWordOptions = false;
            });
          }
        });
  }

  Future<void> _handleSpecialPage(String specialPage) async {
    debugPrint('[TapInterface] Handling special page: $specialPage');

    switch (specialPage.toLowerCase()) {
      case 'spell':
        showDialog(
          context: context,
          builder: (context) => SpellingDialog(
            idToken: widget.idToken,
            aacUserId: widget.aacUserId,
            currentContext: _buildSpaceText,
            onWordSelected: (word) {
              setState(() {
                // Add to speech history / build space
                if (_speechHistory.isNotEmpty) {
                  _speechHistory += ' $word';
                } else {
                  _speechHistory = word;
                }
                _speechHistoryController.text = _speechHistory;

                // Sync build space variables
                _buildSpaceText = _speechHistory;
                _buildSpaceController.text = _speechHistory;

                // Clear board word options so _loadWordOptionsBasedOnBuildSpace
                // doesn't skip the refresh due to the active-board guard
                _boardWordOptions = [];
              });
              Navigator.pop(context);

              // Announce the word
              _announceViaBackend(word);

              // Refresh word and phrase options based on updated speech text
              _loadWordOptionsBasedOnBuildSpace();
              _loadPhraseOptionsBasedOnBuildSpace();
            },
          ),
        );
        break;
      case 'freestyle':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FreestylePage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: widget.displayName,
              sourcePage: 'tap_interface',
            ),
          ),
        );
        break;
      case 'games':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GamesPage(
              fromInterface: 'tap',
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              announceFunction:
                  (
                    text, {
                    routing = 'system',
                    speechRate,
                    showSpeechBubble = false,
                  }) async {
                    await _announceViaBackendSimple(
                      text,
                      routing: routing,
                      preserveMicrophoneSession: true,
                    );
                  },
            ),
          ),
        );
        break;
      case 'threads':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ThreadsPage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
            ),
          ),
        );
        break;
      case 'favorites':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FavoritesPage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: widget.displayName,
            ),
          ),
        );
        break;
      case 'email':
      case 'email-page':
      case 'email_page':
      case 'mail':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => EmailPage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: widget.displayName,
            ),
          ),
        );
        break;
      case 'music':
      case 'spotify':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MusicPage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: widget.displayName,
              onTalkAboutMusic: (musicContext) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FreestylePage(
                      idToken: widget.idToken,
                      aacUserId: widget.aacUserId,
                      displayName: widget.displayName,
                      sourceContext: musicContext,
                      sourcePage: 'music',
                    ),
                  ),
                );
              },
              onTalkAboutSomethingElse: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FreestylePage(
                      idToken: widget.idToken,
                      aacUserId: widget.aacUserId,
                      displayName: widget.displayName,
                      sourcePage: 'music',
                    ),
                  ),
                );
              },
            ),
          ),
        );
        break;
      case 'mood':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MoodSelectionPage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: widget.displayName,
            ),
          ),
        );

        // Refresh settings and content after returning from mood selection
        if (mounted) {
          debugPrint(
            '🔄 TAP INTERFACE: Returned from mood selection, refreshing settings...',
          );
          await _refreshSettingsFromAdmin();
          await _refreshContentFromAdmin();
        }
        break;
      case 'jokes':
        await _loadJokeOptions();
        break;
      case 'guess-who':
      case 'guesswho':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GamesPage(
              fromInterface: 'tap',
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              initialGame: 'guess_who',
            ),
          ),
        );
        break;
      default:
        debugPrint('[TapInterface] Unknown special page: $specialPage');
    }
  }

  Future<List<Map<String, String>>> _loadCategoryPhrases(
    TapInterfaceCategory category,
  ) async {
    // Always try to load category-specific phrases, even if no explicit llmPrompt
    // NOTE: Static options are now used for WORDS, not phrases, per user request.
    // Phrases should use llmPrompt or label.

    final canonicalCategoryLabel = _canonicalizeCategoryLabel(category.label);

    try {
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final locale =
          _normalizeLocaleTag(userSettings.settings?.userLanguage) ?? 'en-US';
      final isNonEnglishLocale = !locale.startsWith('en');
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';

      String categoryContext;
      if (category.hasLLMQuery) {
        categoryContext = await _localizePromptForUserLocaleIfNeeded(
          category.llmPrompt!,
          locale,
        );
        debugPrint(
          '[TapInterface] Phrase source: category llmPrompt (len=${categoryContext.length}) for ${category.label}',
        );
      } else {
        // Generate more specific contextual prompt from category name
        switch (canonicalCategoryLabel) {
          case 'food':
          case 'foods':
            categoryContext =
                'phrases for ordering food, expressing food preferences, and talking about meals';
            break;
          case 'activities':
          case 'activity':
            categoryContext =
                'phrases for suggesting activities, talking about hobbies, and expressing interests';
            break;
          case 'people':
            categoryContext =
                'phrases for talking about family, friends, and people in your life';
            break;
          case 'places':
            categoryContext =
                'phrases for talking about locations, directions, and where you want to go';
            break;
          case 'actions':
            categoryContext =
                'phrases for expressing actions, things you want to do, and movement';
            break;
          case 'needs':
          case 'wants':
            categoryContext =
                'phrases for expressing needs, wants, and requests for help';
            break;
          case 'positive':
            categoryContext =
                'positive adjectives and phrases for expressing approval, compliments, and good feelings';
            break;
          case 'clothing':
          case 'clothes':
            categoryContext =
                'phrases for clothing, getting dressed, choosing outfits, and discussing what to wear';
            break;
          default:
            categoryContext =
                'conversation phrases and expressions related to $canonicalCategoryLabel';
        }

        debugPrint(
          '[TapInterface] Phrase source: generated category context "$canonicalCategoryLabel" (len=${categoryContext.length}) for ${category.label}',
        );
      }

      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        categoryContext =
            '$categoryContext appropriate for someone feeling $currentMood';
      }

      final phraseOpts = await _tapService
          .generateLLMPhraseOptions(
            context: categoryContext,
            // Keep non-English requests leaner to reduce generation latency.
            maxOptions: isNonEnglishLocale ? 20 : 25,
            currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
        '[TapInterface] Phrase generation success: ${phraseOpts.length} options for ${category.label}',
      );

      List<Map<String, String>> categoryPhraseOptions = phraseOpts
          .take(17)
          .toList();

      // Supplement with fallbacks if needed
      if (categoryPhraseOptions.length < 17) {
        final currentTexts = categoryPhraseOptions
            .map((p) => p['fullText'] ?? '')
            .toSet();
        final fallbackOptions = _getFallbackOptionsForCategory(
          canonicalCategoryLabel,
          isWords: false,
        );
        final additionalOptions = fallbackOptions
            .where((text) => !currentTexts.contains(text))
            .take(17 - categoryPhraseOptions.length)
            .map(
              (text) => {
                'summary': text.length > 30
                    ? '${text.substring(0, 30)}...'
                    : text,
                'fullText': text,
              },
            )
            .toList();
        categoryPhraseOptions.addAll(additionalOptions);
      }

      return categoryPhraseOptions;
    } catch (e) {
      debugPrint('🚨 PHRASE DEBUG: LLM phrase generation FAILED: $e');
      // Fallback to generic phrases, NOT static options (which are for Words)
      final fallbackPhrases = _getFallbackOptionsForCategory(
        canonicalCategoryLabel,
        isWords: false,
      );
      return fallbackPhrases
          .map(
            (text) => {
              'summary': text.length > 30
                  ? '${text.substring(0, 30)}...'
                  : text,
              'fullText': text,
            },
          )
          .toList();
    }
  }

  Future<Map<String, dynamic>> _loadCategoryWords(
    TapInterfaceCategory category,
  ) async {
    List<String> wordOpts = [];
    Map<String, List<String>> keywordsMap = {};
    var boardButtons = category.hasBoardWordOptions
        ? category.boardWordOptions.where((button) => !button.hidden).toList()
        : <TapBoardButton>[];

    try {
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      final canonicalCategoryLabel = _canonicalizeCategoryLabel(category.label);
      final locale =
          _normalizeLocaleTag(userSettings.settings?.userLanguage) ?? 'en-US';
      final isNonEnglishLocale = !locale.startsWith('en');
      final isPureCategoryBrowse = _buildSpaceText.trim().isEmpty;
      final browseCacheKey =
          '$locale::${canonicalCategoryLabel.toLowerCase()}::$requiredWordCount';

      if (isPureCategoryBrowse && _categoryBrowseWordCache.containsKey(browseCacheKey)) {
        final cachedWords = _categoryBrowseWordCache[browseCacheKey] ?? const <String>[];
        final cachedKeywords =
            _categoryBrowseWordKeywordsCache[browseCacheKey] ??
            const <String, List<String>>{};

        if (cachedWords.isNotEmpty) {
          debugPrint(
            '[TapInterface] ⚡ Category browse word cache hit: ${category.label} ($browseCacheKey)',
          );
          return {
            'words': cachedWords.take(requiredWordCount).toList(),
            'keywords': cachedKeywords,
            'boardButtons': boardButtons,
          };
        }
      }

      if (boardButtons.isEmpty && (category.boardId ?? '').trim().isNotEmpty) {
        final boards = _tapBoards?.boards ?? const <TapBoard>[];
        for (final board in boards) {
          if (board.id.trim() == category.boardId!.trim()) {
            boardButtons = board.buttons
                .where((button) => !button.hidden)
                .toList();
            debugPrint(
              '[TapInterface] Words source: boardId=${category.boardId} resolved ${boardButtons.length} board buttons for ${category.label}',
            );
            break;
          }
        }
      }

      if (boardButtons.isNotEmpty) {
        debugPrint(
          '[TapInterface] Words source: board buttons (no category words API) for ${category.label}',
        );
        var localizedButtonTexts = await _localizeWordsForUserIfNeeded(
          boardButtons.map((button) => button.text).toList(),
        );

        if (_isConfiguredHomeCategory(category)) {
          final userLocale = _normalizeLocaleTag(
                Provider.of<UserSettingsProvider>(context, listen: false)
                        .settings
                        ?.userLanguage ??
                    'en-US',
              ) ??
              'en-US';
          if (!userLocale.startsWith('en') &&
              _looksEnglishHeavy(localizedButtonTexts)) {
            debugPrint(
              '[TapInterface] Home board localization looked English-heavy; applying offline home-word localization fallback for $userLocale',
            );
            localizedButtonTexts = _localizeHomeWordsOffline(
              localizedButtonTexts,
              userLocale,
            );
          }
        }

        final localizedBoardButtons = <TapBoardButton>[];
        for (var i = 0; i < boardButtons.length; i++) {
          final sourceImageSearchText =
              (boardButtons[i].imageSearchText ?? boardButtons[i].text).trim();
          final localizedText =
              i < localizedButtonTexts.length &&
                  localizedButtonTexts[i].trim().isNotEmpty
              ? localizedButtonTexts[i]
              : boardButtons[i].text;
          if (sourceImageSearchText.isNotEmpty) {
            keywordsMap[localizedText] = <String>[sourceImageSearchText];
          }
          localizedBoardButtons.add(
            boardButtons[i].copyWith(
              text: localizedText,
              imageSearchText: sourceImageSearchText,
            ),
          );
        }

        return {
          'words': localizedBoardButtons.map((button) => button.text).toList(),
          'keywords': keywordsMap,
          'boardButtons': localizedBoardButtons,
        };
      }

      // Check for static options first (per user request: Static Options -> Words section)
      if (category.hasStaticOptions) {
        debugPrint(
          '[TapInterface] Using static options for Words section: ${category.staticOptions}',
        );
        debugPrint(
          '[TapInterface] Words source: static options for ${category.label}',
        );
        final staticWords = category.staticOptionsList;
        final localizedStaticWords = await _localizeWordsForUserIfNeeded(
          staticWords,
        );

        for (var i = 0; i < localizedStaticWords.length; i++) {
          final localizedWord = localizedStaticWords[i];
          final sourceWord = i < staticWords.length ? staticWords[i].trim() : '';
          keywordsMap[localizedWord] =
              sourceWord.isNotEmpty ? <String>[sourceWord] : <String>[];
        }

        return {
          'words': _deduplicateWords(
            localizedStaticWords.take(requiredWordCount).toList(),
          ),
          'keywords': keywordsMap,
          'boardButtons': boardButtons,
        };
      }

      final useHomeStarterPrompt = _shouldUseDefaultHomeStarterWords(category);

      String promptText;
      final moodForWordRequest =
          (!isNonEnglishLocale && currentMood != 'No Mood Selected')
          ? currentMood
          : null;
      if (category.wordsPrompt != null && category.wordsPrompt!.isNotEmpty) {
        promptText = await _localizePromptForUserLocaleIfNeeded(
          category.wordsPrompt!,
          locale,
        );
      } else if (useHomeStarterPrompt) {
        promptText = _getDefaultHomeStarterPrompt(requiredWordCount + 10);
      } else {
        // Non-English locales use a simpler prompt to reduce request complexity.
        promptText = canonicalCategoryLabel;
        if (moodForWordRequest != null && moodForWordRequest.isNotEmpty) {
          promptText =
              '$canonicalCategoryLabel appropriate for someone feeling $moodForWordRequest';
        }
      }

      var buildSpaceForWordRequest = _buildSpaceText;
      if (isNonEnglishLocale) {
        final tokens = buildSpaceForWordRequest
            .split(RegExp(r'\s+'))
            .where((token) => token.trim().isNotEmpty)
            .toList();
        if (tokens.length > 6) {
          buildSpaceForWordRequest = tokens
              .sublist(tokens.length - 6)
              .join(' ');
        }
      }

      if (category.wordsPrompt != null && category.wordsPrompt!.isNotEmpty) {
        debugPrint(
          '[TapInterface] Words source: custom wordsPrompt (len=${category.wordsPrompt!.length}) for ${category.label}',
        );
        final customWordResults = await _tapService
            .generateCustomWordOptions(
              prompt: promptText,
              maxOptions: requiredWordCount + 10,
            )
            .timeout(const Duration(seconds: 10));

        for (final result in customWordResults) {
          final text = result['text'] as String? ?? '';
          final kws = result['keywords'] as List<String>? ?? <String>[];
          if (text.isNotEmpty) {
            wordOpts.add(text);
            if (kws.isNotEmpty) {
              keywordsMap[text] = kws;
            }
          }
        }
      } else {
        debugPrint(
          '[TapInterface] Words source: generateCategoryWordsWithKeywords category="$promptText" for ${category.label}',
        );
        // Use keywords-aware method so image search works for non-English words.
        // The backend returns {text: "word", keywords: ["english", "keyword"]} objects.
        final wordsWithKeywords = await _tapService
            .generateCategoryWordsWithKeywords(
              category: promptText,
              buildSpaceContent: buildSpaceForWordRequest,
              excludeWords: [],
              // Non-English requests overfetch less to cut LLM workload.
              maxOptions: requiredWordCount + (isNonEnglishLocale ? 4 : 10),
              currentMood: moodForWordRequest,
            )
            .timeout(const Duration(seconds: 20));

        for (final entry in wordsWithKeywords) {
          final text = entry['text'] as String? ?? '';
          final kws = entry['keywords'] as List<String>? ?? <String>[];
          if (text.isNotEmpty) {
            wordOpts.add(text);
            if (kws.isNotEmpty) keywordsMap[text] = kws;
          }
        }
      }

      // Validate and deduplicate
      final validatedWords = _validateWordsForCategory(
        wordOpts,
        canonicalCategoryLabel,
      );
      var deduplicatedWords = _deduplicateWords(validatedWords);

      // Keep Home starter words anchored to practical AAC core words.
      if (useHomeStarterPrompt) {
        final localizedCoreSeed = await _localizeWordsForUserIfNeeded(
          _getFallbackHomeStarterWords(count: requiredWordCount),
        );
        deduplicatedWords = _deduplicateWords(
          <String>[
            ...localizedCoreSeed,
            ...deduplicatedWords,
          ],
        );
      }

      List<String> finalWordOptions = deduplicatedWords
          .take(requiredWordCount)
          .toList();


      final preLocalizedFinalWordOptions = List<String>.from(finalWordOptions);
      finalWordOptions = await _localizeWordsForUserIfNeeded(finalWordOptions);

      // Keep keyword lookup aligned with the displayed localized word text.
      // Always preserve the original source word as a fallback search term,
      // even when the backend did not provide extra keywords.
      final localizedKeywordsMap = _buildLocalizedKeywordFallbackMap(
        preLocalizedFinalWordOptions,
        finalWordOptions,
        existingKeywords: keywordsMap,
      );

      if (isPureCategoryBrowse && finalWordOptions.isNotEmpty) {
        _categoryBrowseWordCache[browseCacheKey] = finalWordOptions;
        _categoryBrowseWordKeywordsCache[browseCacheKey] = localizedKeywordsMap;
      }

      return {
        'words': finalWordOptions,
        'keywords': localizedKeywordsMap,
        'boardButtons': boardButtons,
      };
    } catch (e) {
      debugPrint('TapInterface: Words API failed: $e');
      return {
        'words': const <String>[],
        'keywords': const <String, List<String>>{},
        'boardButtons': boardButtons,
      };
    }
  }

  List<String> _getFallbackOptionsForCategory(
    String categoryLabel, {
    bool isWords = false,
  }) {
    final userLocale = _normalizeLocaleTag(
          Provider.of<UserSettingsProvider>(context, listen: false)
              .settings
              ?.userLanguage,
        ) ??
        'en-US';
    final isSpanish = userLocale.startsWith('es');

    // Locale-aware fallback for categories that commonly time out.
    if (isSpanish) {
      switch (categoryLabel.toLowerCase()) {
        case 'clothing':
        case 'clothes':
        case 'ropa':
          if (isWords) {
            return [
              'camisa',
              'pantalones',
              'zapatos',
              'calcetines',
              'chaqueta',
              'sombrero',
              'vestido',
              'shorts',
              'sueter',
              'abrigo',
              'cinturon',
              'guantes',
              'botas',
              'manga corta',
              'manga larga',
              'boton',
              'cremallera',
              'bolsillo',
              'limpio',
              'sucio',
            ];
          }
          return [
            'Quiero una camisa',
            'Necesito pantalones',
            'Ayudame a vestirme',
            'Donde estan mis zapatos?',
            'Quiero calcetines',
            'Necesito mi chaqueta',
            'Esta camisa es comoda',
            'Estos pantalones estan muy apretados',
            'Quiero otra ropa',
            'Sube la cremallera',
            'Abrocha mi camisa',
            'Necesito ropa limpia',
            'Quiero cambiarme de ropa',
            'Ayudame con mis zapatos',
            'Esta es mi camisa favorita',
            'Quiero mi sombrero',
            'Necesito mi abrigo',
            'Esta ropa se siente bien',
          ];
      }
    }

    switch (categoryLabel.toLowerCase()) {
      case 'clothing':
      case 'clothes':
      case 'ropa':
        if (isWords) {
          return [
            'shirt',
            'pants',
            'shoes',
            'socks',
            'jacket',
            'hat',
            'dress',
            'shorts',
            'sweater',
            'coat',
            'belt',
            'gloves',
            'boots',
            'shirt sleeve',
            'long sleeve',
            'button',
            'zipper',
            'pocket',
            'clean',
            'dirty',
          ];
        } else {
          return [
            'I want a shirt',
            'I need pants',
            'Please help me get dressed',
            'Where are my shoes?',
            'I want socks',
            'I need my jacket',
            'This shirt is comfortable',
            'These pants are too tight',
            'I want a different outfit',
            'Please zip my jacket',
            'Please button my shirt',
            'I need clean clothes',
            'I want to change clothes',
            'I need help with my shoes',
            'This is my favorite shirt',
            'I want my hat',
            'I need my coat',
            'These clothes feel good',
          ];
        }
      case 'feelings':
        if (isWords) {
          return [
            'happy',
            'sad',
            'angry',
            'excited',
            'tired',
            'worried',
            'scared',
            'proud',
            'frustrated',
            'calm',
            'confused',
            'surprised',
            'lonely',
            'grateful',
            'hopeful',
            'disappointed',
            'relaxed',
            'nervous',
            'content',
            'jealous',
            'embarrassed',
            'curious',
            'bored',
            'amazed',
            'hurt',
            'loved',
            'stressed',
          ];
        } else {
          return [
            'I feel happy',
            'I am sad',
            'I feel angry',
            'I am excited',
            'I am tired',
            'I feel worried',
            'I am scared',
            'I feel proud',
            'I am frustrated',
            'I feel calm',
            'I am confused',
            'I feel surprised',
            'I am lonely',
            'I feel grateful',
            'I feel hopeful',
            'I am disappointed',
            'I feel relaxed',
            'I am nervous',
          ];
        }
      case 'actions':
        if (isWords) {
          return [
            'go',
            'come',
            'walk',
            'run',
            'sit',
            'stand',
            'eat',
            'drink',
            'sleep',
            'play',
            'work',
            'read',
            'write',
            'watch',
            'listen',
            'talk',
            'help',
            'stop',
            'start',
            'move',
            'dance',
            'sing',
            'cook',
            'clean',
            'drive',
            'call',
            'text',
          ];
        } else {
          return [
            'I want to go',
            'I will come',
            'Let me walk',
            'I can run',
            'I need to sit',
            'I will stand',
            'I want to eat',
            'I need to drink',
            'I want to sleep',
            'I want to play',
            'I need to work',
            'I want to read',
            'I will write',
            'I want to watch',
            'I will listen',
            'I want to talk',
            'I need help',
            'Please stop',
          ];
        }
      case 'people':
        if (isWords) {
          return [
            'mom',
            'dad',
            'sister',
            'brother',
            'friend',
            'teacher',
            'doctor',
            'family',
            'baby',
            'child',
            'person',
            'everyone',
            'someone',
            'me',
            'you',
            'we',
            'they',
            'grandma',
            'grandpa',
            'cousin',
            'uncle',
            'aunt',
            'neighbor',
            'classmate',
            'coworker',
            'boss',
            'student',
          ];
        } else {
          return [
            'I want mom',
            'I need dad',
            'My sister',
            'My brother',
            'My friend',
            'The teacher',
            'See doctor',
            'My family',
            'The baby',
            'That child',
            'This person',
            'I see everyone',
            'I need someone',
            'It is me',
            'I see you',
            'We are here',
            'They are there',
            'My grandma',
          ];
        }
      case 'places':
        if (isWords) {
          return [
            'home',
            'school',
            'work',
            'store',
            'park',
            'hospital',
            'restaurant',
            'bathroom',
            'bedroom',
            'kitchen',
            'outside',
            'inside',
            'here',
            'there',
            'city',
            'country',
            'beach',
            'library',
            'church',
            'office',
            'car',
            'bus',
            'train',
            'airplane',
            'hotel',
            'gym',
            'pool',
          ];
        } else {
          return [
            'I want to go home',
            'I am at school',
            'I go to work',
            'Go to store',
            'I like the park',
            'Go to hospital',
            'Go to restaurant',
            'I need bathroom',
            'In my bedroom',
            'In the kitchen',
            'I go outside',
            'I am inside',
            'I am here',
            'I go there',
            'In the city',
            'In the country',
            'At the beach',
            'Go to library',
          ];
        }
      case 'food':
      case 'foods':
        if (isWords) {
          return [
            'pizza',
            'sandwich',
            'soup',
            'salad',
            'burger',
            'chicken',
            'fish',
            'pasta',
            'rice',
            'bread',
            'fruit',
            'apple',
            'banana',
            'water',
            'juice',
            'milk',
            'coffee',
            'tea',
            'cake',
            'cookie',
            'ice cream',
            'snack',
            'breakfast',
            'lunch',
            'dinner',
            'hungry',
            'thirsty',
          ];
        } else {
          return [
            'I want pizza',
            'I like sandwiches',
            'I want soup',
            'I need salad',
            'I want burger',
            'I like chicken',
            'I want fish',
            'I need pasta',
            'I want rice',
            'I like bread',
            'I want fruit',
            'I like apples',
            'I want banana',
            'I need water',
            'I want juice',
            'I need milk',
            'I want coffee',
            'I like tea',
          ];
        }
      case 'activities':
      case 'activity':
        if (isWords) {
          return [
            'play',
            'game',
            'music',
            'dance',
            'sing',
            'read',
            'book',
            'movie',
            'TV',
            'computer',
            'phone',
            'walk',
            'run',
            'swim',
            'bike',
            'drive',
            'cook',
            'clean',
            'shop',
            'visit',
            'party',
            'fun',
            'hobby',
            'sport',
            'exercise',
            'rest',
            'relax',
          ];
        } else {
          return [
            'I want to play',
            'I like games',
            'I want music',
            'I love to dance',
            'I like to sing',
            'I want to read',
            'I need a book',
            'I want movie',
            'I watch TV',
            'I use computer',
            'I need phone',
            'I want to walk',
            'I like to run',
            'I want to swim',
            'I ride bike',
            'I want to cook',
            'I will clean',
            'I go shopping',
          ];
        }
      case 'needs':
      case 'wants':
        if (isWords) {
          return [
            'help',
            'water',
            'food',
            'rest',
            'sleep',
            'bathroom',
            'medicine',
            'phone',
            'money',
            'time',
            'space',
            'quiet',
            'comfort',
            'support',
            'love',
            'attention',
            'break',
            'change',
            'choice',
            'freedom',
            'safety',
            'warmth',
            'cool',
            'light',
            'dark',
            'clean',
            'fix',
          ];
        } else {
          return [
            'I need help',
            'I want water',
            'I need food',
            'I need rest',
            'I want to sleep',
            'I need bathroom',
            'I need medicine',
            'I want my phone',
            'I need money',
            'I need time',
            'I need space',
            'I want quiet',
            'I need comfort',
            'I want support',
            'I need love',
            'I want attention',
            'I need a break',
          ];
        }
      case 'positive':
        if (isWords) {
          return [
            'awesome',
            'amazing',
            'great',
            'fantastic',
            'wonderful',
            'excellent',
            'perfect',
            'brilliant',
            'outstanding',
            'incredible',
            'superb',
            'marvelous',
            'terrific',
            'fabulous',
            'spectacular',
            'phenomenal',
            'magnificent',
            'exceptional',
            'remarkable',
            'impressive',
            'beautiful',
            'lovely',
            'gorgeous',
            'stunning',
            'breathtaking',
            'cool',
            'sweet',
          ];
        } else {
          return [
            'That is awesome',
            'This is amazing',
            'That is great',
            'This is fantastic',
            'That is wonderful',
            'This is excellent',
            'That is perfect',
            'This is brilliant',
            'That is outstanding',
            'This is incredible',
            'That is superb',
            'This is marvelous',
            'That is terrific',
            'This is fabulous',
            'That is spectacular',
            'This is phenomenal',
            'That is magnificent',
            'This is exceptional',
          ];
        }
      case 'numbers':
      case 'numbers & quantities':
      case 'numbers and quantities':
      case 'amounts':
      case 'quantity':
      case 'quantities':
        if (isWords) {
          return [
            'one',
            'two',
            'three',
            'four',
            'five',
            'six',
            'seven',
            'eight',
            'nine',
            'ten',
            'eleven',
            'twelve',
            'many',
            'few',
            'some',
            'all',
            'none',
            'more',
            'less',
            'most',
            'least',
            'half',
            'whole',
            'first',
            'last',
            'second',
            'third',
          ];
        } else {
          return [
            'I want one',
            'Give me two',
            'I need three',
            'I want four',
            'I see five',
            'I need six',
            'I want many',
            'I have few',
            'I want some',
            'I need all',
            'I have none',
            'I want more',
            'I need less',
            'I want most',
            'That is first',
            'That is last',
            'I want half',
            'I need whole',
          ];
        }
      default:
        // For unknown categories, generate generic but more varied options
        debugPrint(
          '🚨 PHRASE DEBUG: Unknown category "$categoryLabel", using generic options',
        );
        if (isSpanish) {
          if (isWords) {
            return [
              'ayuda',
              'por favor',
              'gracias',
              'si',
              'no',
              'bien',
              'ok',
              'listo',
              'mas',
              'alto',
              'ir',
              'venir',
              'quiero',
              'necesito',
              'gusta',
              'feliz',
              'triste',
              'cansado',
              'terminado',
              'espera',
              'aqui',
              'alla',
              'ahora',
              'luego',
              'grande',
              'pequeno',
              'caliente',
              'frio',
            ];
          }
          return [
            'Necesito ayuda',
            'Por favor ayudame',
            'Gracias',
            'Si por favor',
            'No gracias',
            'Eso esta bien',
            'Eso esta ok',
            'Ya termine',
            'Quiero mas',
            'Por favor para',
            'Quiero ir',
            'Ven aqui por favor',
            'Quiero eso',
            'Necesito esto',
            'Me gusta',
            'Estoy feliz',
            'Me siento triste',
            'Estoy cansado',
          ];
        }
        if (isWords) {
          return [
            'help',
            'please',
            'thank',
            'yes',
            'no',
            'good',
            'okay',
            'done',
            'more',
            'stop',
            'go',
            'come',
            'want',
            'need',
            'like',
            'happy',
            'sad',
            'tired',
            'finished',
            'wait',
            'here',
            'there',
            'now',
            'later',
            'big',
            'small',
            'hot',
            'cold',
          ];
        } else {
          return [
            'I need help',
            'Please help me',
            'Thank you',
            'Yes please',
            'No thank you',
            'That is good',
            'That is okay',
            'I am done',
            'I want more',
            'Please stop',
            'I want to go',
            'Please come here',
            'I want that',
            'I need this',
            'I like it',
            'I am happy',
            'I feel sad',
            'I am tired',
          ];
        }
    }
  }

  void _showCategoryModal(TapInterfaceCategory category) {
    // Trigger custom image preloading for this category's children if not done yet
    _preloadModalCustomImages(category);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final userSettings = settingsProvider.settings;

        final adminColumns = userSettings?.gridColumns ?? 6;
        final modalColumns = _getEffectiveMainContentColumns(
          adminColumns,
        ); // Use same column count as main page

        // Make modal width responsive to button size settings
        // Base calculation: larger buttons (fewer columns) = larger modal
        final baseModalWidth = 300.0; // Minimum modal width
        final widthPerColumn =
            60.0; // Additional width per column (keep buttons same size)
        final responsiveModalWidth =
            baseModalWidth + (modalColumns * widthPerColumn);
        final responsiveModalHeight =
            responsiveModalWidth * 0.8; // Maintain aspect ratio

        // Scale up the container to show more buttons (50% larger)
        final scaledWidth = responsiveModalWidth * 1.5;
        final scaledHeight = responsiveModalHeight * 1.5;

        debugPrint(
          '🚨 MODAL DEBUG: Admin gridColumns=$adminColumns, modalColumns=$modalColumns, modalWidth=$scaledWidth',
        );

        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: BoxConstraints(
              maxWidth: scaledWidth,
              maxHeight: scaledHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ), // Slightly smaller text
                ),
                const SizedBox(height: 12), // Reduced spacing
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          modalColumns, // Same column count as main page
                      childAspectRatio:
                          1.1, // Same as Words and Phrases sections
                      crossAxisSpacing: 2, // Same spacing as main sections
                      mainAxisSpacing: 2,
                    ),
                    itemCount: category.children
                        .where((child) => !child.hidden)
                        .length,
                    itemBuilder: (context, index) {
                      final visibleChildren = category.children
                          .where((child) => !child.hidden)
                          .toList();
                      final child = visibleChildren[index];
                      debugPrint(
                        '🚨 SUB-MENU BUTTON SETTINGS: userSettings=$userSettings',
                      );
                      debugPrint(
                        '🚨 SUB-MENU PICTOGRAMS VALUE: ${userSettings?.enablePictograms ?? false} for "${child.label}"',
                      );
                      final tapPictogramsDisabled =
                          userSettings?.disableTapPictograms ?? false;
                      final tapPictogramsEnabled = !tapPictogramsDisabled;
                      final tapSightWordLogicEnabled =
                          !tapPictogramsDisabled &&
                          (userSettings?.enableSightWords ?? true);

                      return TapInterfaceButton(
                        label: child.label,
                        onPressed: () {
                          Navigator.of(context).pop();
                          _handleCategoryTap(child);
                        },
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        borderColor: Colors.grey[300] ?? Colors.grey.shade300,
                        fontSize: 12, // Same as main sections
                        enablePictograms: tapPictogramsEnabled,
                        sightWordGradeLevel: userSettings?.sightWordGradeLevel,
                        enableSightWords: tapSightWordLogicEnabled,
                        padding: const EdgeInsets.all(
                          2,
                        ), // Same as main sections
                        assignedImageUrl: child
                            .imageUrl, // Pass the assigned image URL from database
                        shouldLogMissing:
                            false, // Don't log missing images for sub-category navigation buttons
                        cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
                        mascot: userSettings?.mascot ?? '',
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Menu Actions ---

  // --- Speech Actions ---
  Future<void> _handleSpeakButtonPress() async {
    await _speakSpeechHistory();
  }

  Future<void> _speakSpeechHistory() async {
    if (_speechHistory.trim().isEmpty) {
      await _announceViaBackend(
        "Nothing to speak",
        translateForPartner: true,
        useSystemVoice: false,
        isSpeakDisplayRequest: true,
      );
      return;
    }

    debugPrint(
      '[TapInterface] _speakSpeechHistory called - speaking as-is: "$_speechHistory"',
    );

    // Always speak as-is (no cleanup)
    String textToSpeak = _speechHistory;

    await _announceViaBackend(
      textToSpeak,
      translateForPartner: true,
      useSystemVoice: false,
      isSpeakDisplayRequest: true,
    );

    // Add to past speech history
    setState(() {
      _pastSpeechHistory.add(textToSpeak);
    });

    debugPrint('[TapInterface] Spoke speech history: "$textToSpeak"');
  }

  Future<void> _handleAutoCleanSpeakButtonPress() async {
    if (_speechHistory.trim().isEmpty) {
      await _announceViaBackend(
        "Nothing to speak",
        translateForPartner: true,
        useSystemVoice: false,
        isSpeakDisplayRequest: true,
      );
      return;
    }

    debugPrint(
      '[TapInterface] Auto Clean + Speak called, starting text cleanup for: "$_speechHistory"',
    );

    // Always use LLM cleanup to make text conversational
    String textToSpeak = await _cleanupText(_speechHistory);
    debugPrint(
      '[TapInterface] Auto Clean completed, original="$_speechHistory", cleaned="$textToSpeak"',
    );

    if (textToSpeak != _speechHistory) {
      // Update the speech history with cleaned text
      setState(() {
        _speechHistory = textToSpeak;
        _speechHistoryController.text = _speechHistory;
      });
    }

    await _announceViaBackend(
      textToSpeak,
      translateForPartner: true,
      useSystemVoice: false,
      isSpeakDisplayRequest: true,
    );

    // Add to past speech history
    setState(() {
      _pastSpeechHistory.add(textToSpeak);
    });

    debugPrint('[TapInterface] Spoke cleaned speech history: "$textToSpeak"');
  }

  Future<void> _composeEmailWithSpeechText() async {
    final messageBody = _speechHistory.trim();
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;
    final recipient = (userSettings?.emailDefaultRecipient ?? '').trim();
    final configuredSubject = (userSettings?.emailSubjectTemplate ?? '').trim();
    final subject = configuredSubject.isEmpty
        ? 'Message from Bravo AAC'
        : configuredSubject;

    if (messageBody.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to email yet. Build a message first.'),
        ),
      );
      return;
    }

    if (!kIsWeb && !Platform.isIOS) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email MVP is currently enabled for iOS only.'),
        ),
      );
      return;
    }

    final mailtoUri = Uri(
      scheme: 'mailto',
      path: recipient,
      queryParameters: {'subject': subject, 'body': messageBody},
    );

    try {
      final launched = await launchUrl(
        mailtoUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        await Clipboard.setData(ClipboardData(text: messageBody));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No mail app configured. Message copied to clipboard.',
            ),
          ),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: messageBody));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open Mail. Message copied to clipboard.'),
        ),
      );
    }
  }

  Future<void> _speakText(
    String text, {
    String? localeOverride,
    String? voiceOverride,
  }) async {
    try {
      await _flutterTts.stop();

      // Get user settings for voice configuration
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final userSettings = settingsProvider.settings;

        // Always use built-in speaker for tap interface (no audio routing changes)
      await _flutterTts.setSharedInstance(true);

        final effectiveLocale =
          _normalizeLocaleTag(localeOverride) ??
          _normalizeLocaleTag(settingsProvider.effectivePartnerLanguage) ??
          'en-US';

      // Configure TTS settings
      if (userSettings != null) {
        debugPrint('[TapInterface] === TTS CONFIGURATION ===');
        debugPrint('[TapInterface] User settings found');
        debugPrint(
          '[TapInterface] Selected voice: "${userSettings.selectedTtsVoiceName}"',
        );
        debugPrint(
          '[TapInterface] Raw speech rate: ${userSettings.speechRate}',
        );

        await _flutterTts.setLanguage(effectiveLocale);

        final preferredVoiceName =
            (voiceOverride ?? userSettings.selectedTtsVoiceName).trim();

        // Set the preferred voice for the active locale.
        if (preferredVoiceName.isNotEmpty) {
          debugPrint(
            '[TapInterface] Setting TTS voice to: $preferredVoiceName (locale=$effectiveLocale)',
          );
          await _flutterTts.setVoice({
            'name': preferredVoiceName,
            'locale': effectiveLocale,
          });
        } else {
          debugPrint(
            '[TapInterface] No explicit voice selected, using locale default ($effectiveLocale)',
          );
        }

        // Set speech rate - use the same approach as main.dart
        // Normal range should be 0.5-1.0, with 0.5 being slower and clear
        double speechRate =
            0.5; // Default to clear, slower speech like main.dart
        debugPrint(
          '[TapInterface] Setting TTS speech rate to: $speechRate (using main.dart default for clarity)',
        );
        await _flutterTts.setSpeechRate(speechRate);

        // Set pitch to normal
        await _flutterTts.setPitch(1.0);

        // Get personalVolume from global settings (scanning uses personal volume, not system)
        final personalVolume = userSettings.personalVolume;
        final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
        debugPrint(
          '[TapInterface] Using personalVolume: $personalVolume/10 → TTS volume: $ttsVolume (scanning)',
        );
        await _flutterTts.setVolume(ttsVolume);
      } else {
        debugPrint('[TapInterface] No user settings, using defaults');
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setPitch(1.0);
        // Default using personalVolume if no settings available
        const defaultPersonalVolume = 10;
        await _flutterTts.setVolume(
          (defaultPersonalVolume / 10.0).clamp(0.0, 1.0),
        );
      }

      debugPrint('[TapInterface] Speaking: "$text"');
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[TapInterface] TTS error: $e');
    }
  }

  // Backend announcement method that uses the EXACT same system as grid page
  /// Suppress Android notification sounds during audio operations
  Future<void> _suppressAndroidNotificationSounds() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        debugPrint('[TapInterface] Suppressing Android notification sounds');
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('suppressNotificationSounds');
      } catch (e) {
        debugPrint('[TapInterface] Failed to suppress notification sounds: $e');
      }
    }
  }

  /// Restore Android notification sounds
  Future<void> _restoreAndroidNotificationSounds() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        debugPrint('[TapInterface] Restoring Android notification sounds');
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('restoreNotificationSounds');
      } catch (e) {
        debugPrint('[TapInterface] Failed to restore notification sounds: $e');
      }
    }
  }

  /// Set application volume based on user settings
  Future<void> _setApplicationVolume({UserSettings? settings}) async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        const platform = MethodChannel('audio_routing');

        // Get application volume from settings or default to 10 (maximum)
        final applicationVolume = settings?.applicationVolume ?? 10;

        debugPrint(
          '[TapInterface] Setting application volume to level: $applicationVolume/10',
        );

        if (Platform.isAndroid) {
          await platform.invokeMethod('setApplicationVolume', {
            'applicationVolume': applicationVolume,
          });
        } else {
          // For iOS, still use setMaxVolume for now (can be enhanced later)
          await platform.invokeMethod('setMaxVolume');
        }

        debugPrint(
          '[TapInterface] ✅ Application volume set to $applicationVolume/10 successfully',
        );

        // Re-suppress notifications after volume change
        if (!kIsWeb && Platform.isAndroid) {
          try {
            await platform.invokeMethod('suppressNotificationSounds');
            debugPrint(
              '[TapInterface] Re-suppressed notifications after volume change',
            );
          } catch (e) {
            debugPrint(
              '[TapInterface] Failed to re-suppress notifications after volume change: $e',
            );
          }
        }
      } catch (e) {
        debugPrint('[TapInterface] ⚠️  Failed to set application volume: $e');
      }
    }
  }

  /// Initialize audio session for optimal TTS performance (prevents first TTS using system voice)
  Future<void> _initializeAudioSessionProactively() async {
    if (!_audioSessionInitialized) {
      debugPrint(
        '[TapInterface] Proactively initializing audio session to prevent system voice...',
      );
      await _initializeAudioSession();
      _audioSessionInitialized = true;
    }
  }

  Future<void> _initializeAudioSession() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        debugPrint('[TapInterface] Starting audio session initialization...');
        const platform = MethodChannel('audio_routing');
        final player = AudioPlayer();

        // Set application volume based on user settings
        try {
          // Get settings from provider
          final settingsProvider = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          await _setApplicationVolume(settings: settingsProvider.settings);
          debugPrint(
            '[TapInterface] Application volume configuration completed',
          );
        } catch (e) {
          debugPrint('[TapInterface] Failed to set application volume: $e');
        }

        if (Platform.isIOS) {
          // iOS audio session setup
          await platform.invokeMethod('forceSpeaker');
          await player.setAsset('assets/silence.mp3');

          final completer = Completer<void>();
          final sub = player.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed) {
              if (!completer.isCompleted) completer.complete();
            }
          });
          await player.play();
          await completer.future;
          await sub.cancel();

          await platform.invokeMethod('resetToDefault');
          debugPrint('[TapInterface] iOS audio session initialized');
        } else {
          // Android audio priming sequence
          try {
            await platform.invokeMethod('forceSpeaker');
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (e) {
            debugPrint('[TapInterface] Android speaker setup failed: $e');
          }

          try {
            await player.setAsset('assets/silence.mp3');

            final completer = Completer<void>();
            final sub = player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                if (!completer.isCompleted) completer.complete();
              }
            });

            await player.play();
            await completer.future;
            await sub.cancel();

            await Future.delayed(const Duration(milliseconds: 200));
            debugPrint('[TapInterface] Android silence priming completed');

            await platform.invokeMethod('resetToDefault');
          } catch (e) {
            debugPrint('[TapInterface] Android audio priming failed: $e');
          }
        }
      } catch (e) {
        debugPrint('[TapInterface] Audio session initialization failed: $e');
      }
    }
  }

  /// Prime the audio system by playing a brief silence to establish audio session
  /// This prevents the first TTS from being cut off due to audio system initialization delays
  Future<void> _primeAudioSystem() async {
    try {
      debugPrint('[TapInterface] Priming audio system...');

      // Suppress Android notification chirps during initialization
      await _suppressAndroidNotificationSounds();

      // Wait a brief moment after page load to ensure everything is initialized
      await Future.delayed(const Duration(milliseconds: 800));

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      if (settingsProvider.idToken == null ||
          settingsProvider.idToken!.isEmpty) {
        debugPrint('[TapInterface] Auth not ready for audio priming, skipping');
        return;
      }

      // Create a very brief silence (empty audio) to prime the system
      const silentText = " "; // Single space - generates minimal audio

      // Use the same TTS method with preserveMicrophoneSession=true
      await _announceViaBackendSimple(
        silentText,
        routing: 'system',
        preserveMicrophoneSession: true,
      );

      debugPrint('[TapInterface] Audio system primed successfully');
    } catch (e) {
      debugPrint('[TapInterface] Audio priming failed (non-critical): $e');
      // Non-critical error - continue normally
    }
  }

  Future<void> _announceViaBackend(
    String text, {
    bool useSystemVoice = false,
    double? volumeScale,
    String? sourceLocaleOverride,
    bool translateForPartner = true,
    bool isSpeakDisplayRequest = false,
  }) async {
    try {
      debugPrint(
        '[TapInterface] 🔊 _announceViaBackend called with text: "$text"',
      );

      // Handle [PAUSE] markers (used in jokes and other content)
      if (text.contains('[PAUSE]')) {
        final parts = text
            .split('[PAUSE]')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        for (int i = 0; i < parts.length; i++) {
          await _announceViaBackend(
            parts[i],
            useSystemVoice: useSystemVoice,
            volumeScale: volumeScale,
            sourceLocaleOverride: sourceLocaleOverride,
            translateForPartner: translateForPartner,
            isSpeakDisplayRequest: isSpeakDisplayRequest,
          );
          if (i < parts.length - 1) {
            await Future.delayed(const Duration(milliseconds: 800));
          }
        }
        return;
      }

      debugPrint('[TapInterface] Using announceViaBackendSimple for: "$text"');

      // For full-duplex on iOS, we do NOT disable wake word - we let it work in parallel
      // This allows the WakeWordService auto-restart to function properly on timeout
      debugPrint(
        '[TapInterface] Using full-duplex audio (preserveMicrophoneSession=true) - wake word remains active',
      );
      await _announceViaBackendSimple(
        text,
        routing: 'system',
        preserveMicrophoneSession: true,
        useSystemVoice: useSystemVoice,
        volumeScale: volumeScale,
        sourceLocaleOverride: sourceLocaleOverride,
        translateForPartner: translateForPartner,
        isSpeakDisplayRequest: isSpeakDisplayRequest,
      );
    } catch (e) {
      debugPrint('[TapInterface] Backend announcement error: $e');
      // Fallback to local TTS if backend fails
      await _speakText(text);
    }
  }

  // Simplified announcement method - copied from grid page's announceViaBackendSimple
  Future<void> _announceViaBackendSimple(
    String text, {
    String routing = 'system',
    int? speechRate,
    bool preserveMicrophoneSession = false,
    bool useSystemVoice = false,
    double? volumeScale,
    String? sourceLocaleOverride,
    bool translateForPartner = true,
    bool isSpeakDisplayRequest = false,
  }) async {
    bool pausedWakeWordForAnnouncement = false;
    String partnerLangForRouting = 'en-US';
    String resolvedPartnerVoice = '';
    String fallbackSpeechText = text;
    bool lazyLoadedSettings = false;
    final shouldDuckMusic = routing == 'system';
    final musicService = Provider.of<MusicPlaybackService>(
      context,
      listen: false,
    );
    final callId = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      if (shouldDuckMusic) {
        await musicService.beginAnnouncementDucking();
      }

      debugPrint(
        '[TapInterface][$callId] 🎵 _announceViaBackendSimple called with text: "$text", routing: $routing',
      );
      debugPrint('[TapInterface][$callId] announceViaBackendSimple: "$text"');

      // Suppress Android notification sounds during announcement
      await _suppressAndroidNotificationSounds();

      // Initialize audio session on first use (fixes first TTS using system voice)
      if (!_audioSessionInitialized) {
        debugPrint(
          '[TapInterface] First TTS call, initializing audio session...',
        );
        await _initializeAudioSession();
        _audioSessionInitialized = true;

        // Keep this brief to avoid first-tap lag while still allowing route setup.
        await Future.delayed(const Duration(milliseconds: 80));
      }

      // Show speech bubble overlay if enabled in settings
      _showSpeechBubbleOverlay(text);

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final idToken = settingsProvider.idToken;
      final userId = settingsProvider.userId ?? '';
      UserSettings? userSettings = settingsProvider.settings;

      // First-tap hardening: ensure settings are loaded before partner-route
      // announcement so voice overrides are available immediately.
      if (routing == 'system' && !useSystemVoice && userSettings == null) {
        try {
          await settingsProvider.fetchSettings();
          userSettings = settingsProvider.settings;
          lazyLoadedSettings = true;
          debugPrint(
            '[TapInterface][$callId] Loaded user settings lazily for first system announcement',
          );
        } catch (e) {
          debugPrint(
            '[TapInterface][$callId] Unable to preload settings for first announcement: $e',
          );
        }
      }

      if (idToken == null || idToken.isEmpty) {
        debugPrint(
          '[TapInterface] Missing auth token, falling back to local TTS',
        );
        await _speakText(text);
        return;
      }

      // Resolve language/voice for partner-facing announcements.
      // System routing should always speak in effective partner language
      // (default partner language OR active location override language).
        partnerLangForRouting =
          _normalizeLocaleTag(settingsProvider.effectivePartnerLanguage) ??
          'en-US';
      String announcedText = text;
      bool _looksLikelyEnglishText(String value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return false;

        // Fast heuristic: common English function words + ascii letters.
        final lower = trimmed.toLowerCase();
        final hasEnglishFunctionWord = RegExp(
          r'\b(the|and|is|are|to|for|with|please|i|you|want|need|help|can|yes|no)\b',
        ).hasMatch(lower);
        final asciiLetterRatio =
            trimmed.runes.where((r) => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)).length /
            trimmed.runes.length;
        return hasEnglishFunctionWord || asciiLetterRatio > 0.75;
      }

      bool translationFailed = false;
      if (routing == 'system' && translateForPartner) {
        final userLang = _normalizeLocaleTag(
              sourceLocaleOverride ?? userSettings?.userLanguage ?? 'en-US',
            ) ??
            'en-US';
        final partnerLang = _normalizeLocaleTag(
              settingsProvider.effectivePartnerLanguage,
            ) ??
            'en-US';

        // Prefer explicit partner/location voice, but never fall back to system voice
        // when the user has selected a TTS voice.
        resolvedPartnerVoice = settingsProvider.effectivePartnerVoice.trim();
        if (resolvedPartnerVoice.isEmpty && !useSystemVoice) {
          resolvedPartnerVoice =
              (userSettings?.selectedTtsVoiceName ?? '').trim();
        }

        // If text looks English but user language is non-English, force EN source
        // so partner translation still occurs.
        var translationSourceLocale = userLang;
        if (_looksLikelyEnglishText(text) && !partnerLang.startsWith('en')) {
          translationSourceLocale = 'en-US';
        }

        debugPrint(
          '[TapInterface] Translation decision: source=$translationSourceLocale userLang=$userLang partnerLang=$partnerLang text="$text"',
        );

        if (translationSourceLocale != partnerLang) {
          try {
            String translatedAttempt = await _translateForPartner(
              text,
              fromLocale: translationSourceLocale,
              toLocale: partnerLang,
              idToken: idToken,
              aacUserId: userId,
            ).timeout(const Duration(seconds: 5));

            // If translation result is unchanged for a non-English partner,
            // retry quickly with user locale as source (or en-US fallback)
            // to handle intermittent source-locale mismatch.
            final unchanged =
                translatedAttempt.trim().toLowerCase() ==
                text.trim().toLowerCase();
            if (unchanged && !partnerLang.startsWith('en')) {
              final retrySource =
                  (translationSourceLocale == userLang && userLang != 'en-US')
                  ? 'en-US'
                  : userLang;
              if (retrySource != partnerLang && retrySource != translationSourceLocale) {
                debugPrint(
                  '[TapInterface] Translation unchanged; retrying with alternate source=$retrySource',
                );
                translatedAttempt = await _translateForPartner(
                  text,
                  fromLocale: retrySource,
                  toLocale: partnerLang,
                  idToken: idToken,
                  aacUserId: userId,
                ).timeout(const Duration(seconds: 3));
              }
            }

            if (translatedAttempt.trim().toLowerCase() == text.trim().toLowerCase() &&
                !partnerLang.startsWith('en')) {
              translationFailed = true;
              debugPrint(
                '[TapInterface] Translation remained unchanged after retry. Flagging as failed translation.',
              );
            } else {
              announcedText = translatedAttempt;
              debugPrint(
                '[TapInterface] Announcement translated ($translationSourceLocale->$partnerLang): "$announcedText"',
              );
            }
          } catch (e) {
            translationFailed = true;
            debugPrint(
              '[TapInterface] Translation failed, speaking original text: $e',
            );
          }
        }
      }

      if (translationFailed) {
        // If translation failed, we fall back to the user's language and voice settings
        // instead of pronouncing English text using a Spanish TTS voice.
        partnerLangForRouting = _normalizeLocaleTag(
              sourceLocaleOverride ?? userSettings?.userLanguage ?? 'en-US',
            ) ??
            'en-US';
        resolvedPartnerVoice = (userSettings?.selectedTtsVoiceName ?? '').trim();
        debugPrint(
          '[TapInterface] Translation failed fallback: partnerLangForRouting reset to $partnerLangForRouting, resolvedPartnerVoice reset to $resolvedPartnerVoice',
        );
      }

      // Keep speech bubble aligned with actual announced text.
      _showSpeechBubbleOverlay(announcedText);
      fallbackSpeechText = announcedText;

      // Include partner-aware voice settings in the request
      final voiceSettings = {
        'text': announcedText,
        'routing_target': routing,
        if (speechRate != null) 'speech_rate': speechRate,
        if (speechRate != null) 'speech_rate_override': speechRate,
        if (routing == 'system' && partnerLangForRouting.isNotEmpty)
          'language': partnerLangForRouting,
        if (routing == 'system' && partnerLangForRouting.isNotEmpty)
          'locale': partnerLangForRouting,
        if (routing == 'system' && partnerLangForRouting.isNotEmpty)
          'partner_language': partnerLangForRouting,
        if (routing == 'system' && resolvedPartnerVoice.isNotEmpty)
          'voice': resolvedPartnerVoice,
        if (routing == 'system' && resolvedPartnerVoice.isNotEmpty)
          'partner_voice_name': resolvedPartnerVoice,
        if (routing == 'system' && resolvedPartnerVoice.isNotEmpty)
          'voice_name_override': resolvedPartnerVoice,
        if (routing == 'system' && resolvedPartnerVoice.isNotEmpty)
          'selected_tts_voice_name': resolvedPartnerVoice,
        if (!useSystemVoice &&
            routing != 'system' &&
            userSettings?.selectedTtsVoiceName != null &&
            userSettings!.selectedTtsVoiceName.isNotEmpty)
          'voice': userSettings.selectedTtsVoiceName,
        if (!useSystemVoice &&
            routing != 'system' &&
            userSettings?.selectedTtsVoiceName != null &&
            userSettings!.selectedTtsVoiceName.isNotEmpty)
          'voice_name_override': userSettings.selectedTtsVoiceName,
        if (!useSystemVoice && userSettings?.speechRate != null)
          'speed': userSettings!.speechRate,
        if (!useSystemVoice && userSettings?.speechRate != null)
          'speech_rate_override': userSettings!.speechRate,
        if (volumeScale != null) 'volume_scale': volumeScale,
      };

      debugPrint(
        '[TapInterface][$callId] TTS request with voice settings: $voiceSettings',
      );

      debugPrint(
        '[TapInterface][$callId] Routing telemetry: lazyLoadedSettings=$lazyLoadedSettings partnerLang=$partnerLangForRouting resolvedPartnerVoice="$resolvedPartnerVoice" useSystemVoice=$useSystemVoice translateForPartner=$translateForPartner',
      );

        // Fast-start fallback only when partner translation/voice reliability is
        // not critical. For partner-language announcements, prioritize correctness.
        const backendQuickStartDeadline = Duration(milliseconds: 900);
        final requiresReliablePartnerSpeech =
          routing == 'system' &&
          (translateForPartner && !partnerLangForRouting.startsWith('en') ||
           (!useSystemVoice && resolvedPartnerVoice.isNotEmpty));

        final shouldWarmupPartnerVoice =
            routing == 'system' &&
            !useSystemVoice &&
            resolvedPartnerVoice.isNotEmpty;
        final warmupKey = '$partnerLangForRouting|$resolvedPartnerVoice';
        if (shouldWarmupPartnerVoice &&
            (!_partnerVoiceWarmupCompleted || _partnerVoiceWarmupKey != warmupKey)) {
          final warmupPayload = {
            'text': '.',
            'routing_target': routing,
            'voice': resolvedPartnerVoice,
            'partner_voice_name': resolvedPartnerVoice,
            'voice_name_override': resolvedPartnerVoice,
            'warmup': true,
          };

          try {
            debugPrint(
              '[TapInterface][$callId] Warming backend partner voice for first call (key=$warmupKey)',
            );
            await AuthenticatedHttpClient.makeAuthenticatedRequest(
              'POST',
              '${EnvironmentConfig.apiBaseUrl}/play-audio',
              baseHeaders: {
                'Content-Type': 'application/json',
                'X-User-ID': userId,
                'X-AAC-Warmup': '1',
              },
              body: json.encode(warmupPayload),
              timeoutSeconds: 8,
            );
            _partnerVoiceWarmupCompleted = true;
            _partnerVoiceWarmupKey = warmupKey;
            debugPrint(
              '[TapInterface][$callId] Backend partner voice warmup completed',
            );
          } catch (e) {
            debugPrint(
              '[TapInterface][$callId] Backend partner voice warmup skipped/failed: $e',
            );
          }
        }

        // Speak Display hardening: re-prime backend voice before every audible
        // Speak Display request to prevent alternating system/custom voice output.
      final shouldPrimeSpeakDisplayVoice =
          isSpeakDisplayRequest &&
          routing == 'system' &&
          !useSystemVoice &&
          resolvedPartnerVoice.isNotEmpty;
        if (shouldPrimeSpeakDisplayVoice) {
        final primePayload = {
          ...voiceSettings,
          'text': ' ',
          'warmup': true,
          'speak_display_voice_prime': true,
        };

        try {
          debugPrint(
            '[TapInterface][$callId] Priming backend voice for Speak Display (key=$partnerLangForRouting|$resolvedPartnerVoice)',
          );
          await AuthenticatedHttpClient.makeAuthenticatedRequest(
            'POST',
            '${EnvironmentConfig.apiBaseUrl}/play-audio',
            baseHeaders: {
              'Content-Type': 'application/json',
              'X-User-ID': userId,
              'X-AAC-Speak-Display-Prime': '1',
            },
            body: json.encode(primePayload),
            timeoutSeconds: 10,
          );
          debugPrint(
            '[TapInterface][$callId] Speak Display backend voice primed',
          );
        } catch (e) {
          debugPrint(
            '[TapInterface][$callId] Speak Display voice priming failed/skipped: $e',
          );
        }
      }

      // Request backend audio using authenticated client (handles token refresh)
      final responseFuture = AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/play-audio',
        baseHeaders: {'Content-Type': 'application/json', 'X-User-ID': userId},
        body: json.encode(voiceSettings),
        timeoutSeconds: 30,
      );

      http.Response? response;
      try {
        response = requiresReliablePartnerSpeech
            ? await responseFuture
            : await responseFuture.timeout(backendQuickStartDeadline);
      } on TimeoutException {
        debugPrint(
          '[TapInterface][$callId] Backend TTS exceeded quick-start deadline (${backendQuickStartDeadline.inMilliseconds}ms). Using local TTS for faster response.',
        );
        await _speakText(
          announcedText,
          localeOverride: partnerLangForRouting,
          voiceOverride: resolvedPartnerVoice,
        );
        return;
      }

      bool backendAudioPlayed = false;

      if (!kIsWeb &&
          Platform.isIOS &&
          preserveMicrophoneSession &&
          _wakeWordService != null) {
        try {
          debugPrint(
            '[TapInterface] Pausing wake-word recognizer during backend announcement playback',
          );
          _wakeWordService!.pauseWakeWordAutoRestart();
          await _wakeWordService!.stopAllRecognizers();
          pausedWakeWordForAnnouncement = true;
        } catch (e) {
          debugPrint('[TapInterface] Failed to pause wake-word recognizer: $e');
        }
      }

      String _detectAudioExtension(List<int> bytes) {
        if (bytes.length >= 4 &&
            bytes[0] == 0x52 && // R
            bytes[1] == 0x49 && // I
            bytes[2] == 0x46 && // F
            bytes[3] == 0x46) {
          return 'wav';
        }

        if (bytes.length >= 3 &&
            bytes[0] == 0x49 && // I
            bytes[1] == 0x44 && // D
            bytes[2] == 0x33) {
          return 'mp3';
        }

        if (bytes.length >= 2 &&
            bytes[0] == 0xFF &&
            (bytes[1] & 0xE0) == 0xE0) {
          return 'mp3';
        }

        return 'mp3';
      }

      Future<void> _waitForPlaybackComplete(AudioPlayer player) async {
        await player.playerStateStream
            .firstWhere(
              (state) => state.processingState == ProcessingState.completed,
            )
            .timeout(const Duration(seconds: 12));
      }

      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final audioUrl = RegExp(
          '"audio_url"\\s*:\\s*"([^"]+)"',
        ).firstMatch(jsonStr)?.group(1);
        final base64Audio =
            RegExp(
              '"audio_data"\\s*:\\s*"([^"]+)"',
            ).firstMatch(jsonStr)?.group(1) ??
            RegExp(
              '"audioContent"\\s*:\\s*"([^"]+)"',
            ).firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);

        debugPrint(
          '[TapInterface] Backend response received, audio data found: ${base64Audio != null}',
        );

        if (base64Audio != null && base64Audio.isNotEmpty) {
          final player = AudioPlayer();

          try {
            if (!kIsWeb && Platform.isIOS) {
              await _flutterTts.stop();
              await player.stop();
            }

            // Detect backend audio format and use matching extension.
            final bytes = base64Decode(base64Audio);
            final ext = _detectAudioExtension(bytes);
            final headerHex = bytes
                .take(8)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ');
            debugPrint(
              '[TapInterface] Decoded backend audio: ${bytes.length} bytes, ext=$ext, header=$headerHex',
            );

            final tempDir = Directory.systemTemp;
            final tempFile = await File(
              '${tempDir.path}/tap_backend_tts_${DateTime.now().microsecondsSinceEpoch}.$ext',
            ).create();
            await tempFile.writeAsBytes(bytes, flush: true);
            await player.setFilePath(tempFile.path);
            debugPrint('[TapInterface] Audio file set, starting playback...');
            await player.play();

            // Wait for completion
            debugPrint('[TapInterface] Waiting for audio to complete...');
            await _waitForPlaybackComplete(player);
            debugPrint(
              '[TapInterface] Audio playback completed, processing...',
            );

            // No audio routing reset needed on Tap Interface

            backendAudioPlayed = true;
            debugPrint('[TapInterface][$callId] Backend audio played successfully');

            // On iOS with full-duplex mode, the wake word service continues listening automatically
            // since we never disabled wakeWordShouldBeActive in the first place
          } catch (e) {
            debugPrint('[TapInterface] Audio playback failed: $e');

            // Secondary fallback: try server-hosted audio_url before local TTS fallback.
            if (audioUrl != null && audioUrl.isNotEmpty) {
              try {
                await player.setUrl(audioUrl);
                await player.play();
                await _waitForPlaybackComplete(player);
                backendAudioPlayed = true;
                debugPrint(
                  '[TapInterface] Backend audio_url playback succeeded after base64 failure',
                );
              } catch (urlError) {
                debugPrint(
                  '[TapInterface] audio_url playback also failed: $urlError',
                );
              }
            }
          } finally {
            await player.dispose();
          }
        } else if (audioUrl != null && audioUrl.isNotEmpty) {
          final player = AudioPlayer();
          try {
            if (!kIsWeb && Platform.isIOS) {
              await _flutterTts.stop();
              await player.stop();
            }

            await player.setUrl(audioUrl);
            await player.play();
            await _waitForPlaybackComplete(player);

            // No audio routing reset needed on Tap Interface

            backendAudioPlayed = true;
            debugPrint('[TapInterface] Backend audio_url played successfully');
          } catch (e) {
            debugPrint('[TapInterface] audio_url playback failed: $e');
          } finally {
            await player.dispose();
          }
        }
      }

      // Simple TTS fallback if backend audio failed
      if (!backendAudioPlayed) {
        debugPrint('[TapInterface][$callId] Backend failed, using local TTS fallback');
        await _speakText(
          announcedText,
          localeOverride: partnerLangForRouting,
          voiceOverride: resolvedPartnerVoice,
        );

        // Wake word service continues listening automatically during fallback TTS too
      }
    } catch (e) {
      debugPrint('[TapInterface][$callId] announceViaBackendSimple exception: $e');
      // Simple fallback
      await _speakText(
        fallbackSpeechText,
        localeOverride: partnerLangForRouting,
        voiceOverride: resolvedPartnerVoice,
      );

      // Wake word service continues listening automatically
    } finally {
      if (pausedWakeWordForAnnouncement && _wakeWordService != null) {
        try {
          debugPrint(
            '[TapInterface] Resuming wake-word recognizer after announcement playback',
          );
          _wakeWordService!.resumeWakeWordAutoRestart();

          // We explicitly stopped recognizers before playback, so also explicitly
          // restart listening here (resume flag alone does not start a new session).
          if (mounted && !_isListeningForQuestion) {
            _startWakeWordListening();
          }
        } catch (e) {
          debugPrint(
            '[TapInterface] Failed to resume wake-word recognizer: $e',
          );
        }
      }

      // Always restore notification sounds
      await _restoreAndroidNotificationSounds();

      if (shouldDuckMusic) {
        await musicService.endAnnouncementDucking();
      }
    }
  }

  Future<String> _localizePromptForUserLocaleIfNeeded(
    String prompt,
    String targetLocale,
  ) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) return prompt;

    final normalizedTargetLocale =
        _normalizeLocaleTag(targetLocale) ?? targetLocale;
    if (normalizedTargetLocale.startsWith('en')) {
      return trimmedPrompt;
    }

    final translatedPrompt = await _translateForPartner(
      trimmedPrompt,
      fromLocale: 'en-US',
      toLocale: normalizedTargetLocale,
      idToken: widget.idToken,
      aacUserId: widget.aacUserId,
    );

    return translatedPrompt.trim().isEmpty ? trimmedPrompt : translatedPrompt;
  }

  /// Translate user-language text into partner-language text via backend.
  /// Returns original text on failures so announcements still proceed.
  Future<String> _translateForPartner(
    String text, {
    required String fromLocale,
    required String toLocale,
    required String idToken,
    required String aacUserId,
  }) async {
    if (text.isEmpty || fromLocale == toLocale) return text;

    final cacheKey = '$fromLocale|$toLocale|$text';
    final cached = _translationCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/translate-lines',
        baseHeaders: {
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'lines': [text],
          'source_locale': fromLocale,
          'target_locale': toLocale,
        }),
        timeoutSeconds: 10,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final translatedLines = data['translated_lines'];
        if (translatedLines is List && translatedLines.isNotEmpty) {
          final translated = translatedLines.first.toString().trim();
          if (translated.isNotEmpty) {
            _translationCache[cacheKey] = translated;
            return translated;
          }
        }
      }
    } catch (e) {
      debugPrint('[TapInterface] _translateForPartner failed: $e');
    }

    return text;
  }

  Future<void> _playCustomAudio(String audioUrl) async {
    try {
      debugPrint(
        '[TapInterface] 🎵 _playCustomAudio called with URL: "$audioUrl"',
      );

      // Ensure audio session is initialized
      if (!_audioSessionInitialized) {
        await _initializeAudioSessionProactively();
      }

      final player = AudioPlayer();

      try {
        // No audio routing overrides needed on Tap Interface

        // Check if this is a data URL (base64 encoded)
        if (audioUrl.startsWith('data:audio/')) {
          // Extract base64 data from data URL
          final base64Match = RegExp(
            r'data:audio/[^;]+;base64,(.+)',
          ).firstMatch(audioUrl);
          if (base64Match != null) {
            final base64Audio = base64Match.group(1)!;

            // Create temporary file and play (same approach as backend TTS)
            final bytes = base64Decode(base64Audio);
            final tempDir = Directory.systemTemp;
            final tempFile = await File(
              '${tempDir.path}/custom_button_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
            ).create();
            await tempFile.writeAsBytes(bytes, flush: true);

            await player.setFilePath(tempFile.path);
            debugPrint(
              '[TapInterface] 🎵 Playing custom audio from temporary file',
            );
          } else {
            throw Exception('Invalid data URL format');
          }
        } else {
          // Regular URL - try to load directly
          await player.setUrl(audioUrl);
          debugPrint('[TapInterface] 🎵 Playing custom audio from URL');
        }

        await player.play();

        // Wait for completion
        await player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        );

        debugPrint('[TapInterface] ✅ Custom audio playback completed');

        // No audio routing reset needed on Tap Interface
      } finally {
        // Always dispose the player
        await player.dispose();
      }
    } catch (e) {
      debugPrint('[TapInterface] ❌ Custom audio playback error: $e');
      // Don't throw - this should be non-blocking
    }
  }

  /// Clear only the text in the speech box without resetting the page
  /// NOTE: This does NOT clear _pastSpeechHistory (handled separately by Clear History button)
  void _clearSpeechText() {
    debugPrint('[TapInterface] === CLEARING SPEECH TEXT ONLY ===');
    setState(() {
      _speechHistory = "";
      _speechHistoryController.text = "";
      _buildSpaceText = "";
      _buildSpaceController.text = "";
      // _pastSpeechHistory is NOT cleared here - only cleared by History button
    });
  }

  /// Reset everything - clear text, category, and options
  /// NOTE: This does NOT clear _pastSpeechHistory (handled separately by Clear History button)
  void _resetPage() {
    debugPrint('[TapInterface] === RESETTING PAGE ===');
    debugPrint('[TapInterface] Before reset - Build space: "$_buildSpaceText"');
    debugPrint(
      '[TapInterface] Before reset - Selected category: ${_selectedCategory?.label}',
    );
    debugPrint(
      '[TapInterface] Before reset - Word options count: ${_wordOptions.length}',
    );
    debugPrint(
      '[TapInterface] Before reset - Phrase options count: ${_phraseOptions.length}',
    );

    setState(() {
      _speechHistory = "";
      _speechHistoryController.text = "";
      _buildSpaceText = "";
      _buildSpaceController.text = "";
      _selectedCategory = null;
      _clearTemporaryNavigationState();
      _clearActiveBoardModifier();
      _isJokesMode = false; // Clear jokes mode on page reset
      _currentQuestion = ''; // Clear question when entering freestyle mode
      _phraseOptions.clear();
      _wordOptions.clear();
      _usedWordOptions.clear();
      _boardWordOptions.clear();
      _wordKeywords.clear(); // Clear keywords when clearing word options
      _textPromptUsed = false; // Reset text prompt usage flag
      // _pastSpeechHistory is NOT cleared here - only cleared by History button
    });

    // Reload initial options after clearing
    debugPrint('[TapInterface] Page reset, reloading initial options');
    _openConfiguredHomeBoard().then((opened) {
      if (!opened) {
        _loadInitialFreestyleOptions();
        _loadInitialPhraseOptions();
      }
    });
  }

  void _backspaceSpeechHistory() {
    String currentText = _speechHistoryController.text;
    if (currentText.isEmpty) return;

    List<String> words = currentText.trim().split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      words.removeLast();
      String newText = words.join(' ');

      setState(() {
        _speechHistory = newText;
        _speechHistoryController.text = newText;
        _buildSpaceText = newText;
        _buildSpaceController.text = newText;
      });

      // Refresh word options based on the new text
      _loadWordOptionsBasedOnBuildSpace();
    }
  }

  // Removes [phrase] (as a whole token) from the end of the speech history.
  // Handles multi-word phrases like "to play" without leaving partial words.
  void _removePhraseFromSpeechHistory(String phrase) {
    final current = _speechHistoryController.text.trim();
    if (current.isEmpty || phrase.isEmpty) return;
    final suffix = phrase.trim();
    String newText;
    if (current.endsWith(suffix)) {
      newText = current.substring(0, current.length - suffix.length).trimRight();
    } else {
      // Fallback: remove the last word if the phrase isn't at the end.
      final words = current.split(RegExp(r'\s+'));
      words.removeLast();
      newText = words.join(' ');
    }
    setState(() {
      _speechHistory = newText;
      _speechHistoryController.text = newText;
      _buildSpaceText = newText;
      _buildSpaceController.text = newText;
    });
    _loadWordOptionsBasedOnBuildSpace();
  }

  void _clearSpeechHistory() {
    setState(() {
      _pastSpeechHistory.clear();
    });
  }

  // Helper method to clean text without UI updates (same as freestyle page)
  Future<String> _cleanupText(String textToClean) async {
    if (textToClean.trim().isEmpty) {
      return textToClean;
    }

    try {
      debugPrint('[TapInterface] Starting text cleanup for: "$textToClean"');

      // Get current user settings
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      String idToken = settingsProvider.idToken ?? '';
      String aacUserId = settingsProvider.userId ?? '';

      // Refresh token before cleanup call
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final refreshedToken = await _safeGetIdToken(
            user,
            forceRefresh: true,
          );
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
            debugPrint('[TapInterface] Token refreshed for cleanup');
          }
        }
      } catch (e) {
        debugPrint('[TapInterface] Token refresh failed for cleanup: $e');
      }

      final userLanguage = settingsProvider.settings?.userLanguage ?? 'en-US';
      final url = '${EnvironmentConfig.apiBaseUrl}/api/freestyle/cleanup-text';
      final headers = {
        'Authorization': 'Bearer $idToken',
        'X-User-ID': aacUserId,
        'Content-Type': 'application/json',
      };
      final body = json.encode({
        'text_to_cleanup': textToClean,
        'target_locale': userLanguage,
      });

      debugPrint('[TapInterface] Cleanup URL: $url');
      debugPrint('[TapInterface] Cleanup headers: $headers');
      debugPrint('[TapInterface] Cleanup body: $body');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      debugPrint(
        '[TapInterface] Cleanup response status: ${response.statusCode}',
      );
      debugPrint('[TapInterface] Cleanup response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final cleanedText = data['cleaned_text'] ?? textToClean;
        debugPrint('[TapInterface] Original text: "$textToClean"');
        debugPrint('[TapInterface] Cleaned text: "$cleanedText"');
        return cleanedText;
      } else {
        debugPrint(
          '[TapInterface] Cleanup failed with status ${response.statusCode}: ${response.body}',
        );
        return textToClean;
      }
    } catch (e) {
      debugPrint('[TapInterface] Error cleaning text: $e');
      return textToClean;
    }
  }

  void _showSpeechHistoryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Speech History'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _pastSpeechHistory.isEmpty
              ? const Center(
                  child: Text(
                    'No speech history yet.',
                    style: TextStyle(fontSize: 14),
                  ),
                )
              : ListView.separated(
                  itemCount: _pastSpeechHistory.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final historyItem =
                        _pastSpeechHistory[_pastSpeechHistory.length -
                            1 -
                            index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey[300] ?? Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              historyItem,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Copy this item',
                            child: Container(
                              height: 54,
                              width: 64,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue[400] ?? Colors.blue.shade400,
                                    Colors.blue[600] ?? Colors.blue.shade600,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: historyItem),
                                  );
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copied to clipboard'),
                                      duration: Duration(milliseconds: 1200),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.copy,
                                  size: 29,
                                  color: Colors.white,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Speak this item',
                            child: Container(
                              height: 54,
                              width: 64,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.green[400] ?? Colors.green.shade400,
                                    Colors.green[600] ?? Colors.green.shade600,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.3),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  await _announceViaBackend(historyItem);
                                },
                                icon: const Icon(
                                  Icons.volume_up,
                                  size: 32,
                                  color: Colors.white,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          Tooltip(
            message: 'Close',
            child: Container(
              height: 64,
              width: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue[400] ?? Colors.blue.shade400,
                    Colors.blue[600] ?? Colors.blue.shade600,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 45, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),
          Tooltip(
            message: 'Clear History',
            child: Container(
              height: 64,
              width: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red[400] ?? Colors.red.shade400,
                    Colors.red[600] ?? Colors.red.shade600,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  _clearSpeechHistory();
                  Navigator.pop(context);
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 45,
                  color: Colors.white,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Status Toast ---
  void _showStatusToast(String msg) {
    _statusToastTimer?.cancel();
    setState(() => _statusMessage = msg);
    if (msg.isNotEmpty && !_isListeningForWakeWord && !_isListeningForQuestion) {
      _statusToastTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _statusMessage = '');
      });
    }
  }

  // --- Admin Actions ---
  void _toggleAdminToolbarLock() {
    if (_isAdminToolbarLocked) {
      // If currently locked, show PIN dialog to unlock
      _showPINDialog();
    } else {
      // If currently unlocked, just lock it
      setState(() {
        _isAdminToolbarLocked = true;
      });
    }
  }

  void _showPINDialog() {
    final TextEditingController pinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Admin PIN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter your PIN:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, letterSpacing: 3),
                  decoration: const InputDecoration(
                    hintText: '••••',
                    counterText: '',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _validatePIN(pinController.text, context),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Or tap numbers below:',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                // Compact numeric keypad
                StatefulBuilder(
                  builder: (context, setKeypadState) {
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '1',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '2',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '3',
                              pinController,
                              setKeypadState,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '4',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '5',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '6',
                              pinController,
                              setKeypadState,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '7',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '8',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '9',
                              pinController,
                              setKeypadState,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '⌫',
                              pinController,
                              setKeypadState,
                              isBackspace: true,
                            ),
                            _buildKeypadButton(
                              '0',
                              pinController,
                              setKeypadState,
                            ),
                            const SizedBox(width: 40), // Empty space
                          ],
                        ),
                      ],
                    );
                  },
                ),
                if (_pinAttempts > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Incorrect PIN. Attempts: $_pinAttempts/2',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _validatePIN(pinController.text, context),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
  }

  /// Build a simple keypad button for PIN entry
  Widget _buildKeypadButton(
    String label,
    TextEditingController controller,
    Function setState, {
    bool isBackspace = false,
  }) {
    return SizedBox(
      width: 50,
      height: 40,
      child: ElevatedButton(
        onPressed: () {
          if (isBackspace) {
            if (controller.text.isNotEmpty) {
              controller.text = controller.text.substring(
                0,
                controller.text.length - 1,
              );
              setState(() {});
            }
          } else {
            controller.text += label;
            setState(() {});
          }
        },
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          side: BorderSide(color: Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isBackspace ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _validatePIN(String enteredPIN, BuildContext dialogContext) {
    if (enteredPIN == _currentPIN) {
      // Correct PIN
      setState(() {
        _isAdminToolbarLocked = false;
        _pinAttempts = 0;
      });
      Navigator.of(dialogContext).pop();
    } else {
      // Incorrect PIN
      setState(() {
        _pinAttempts++;
      });

      if (_pinAttempts >= 2) {
        // After 2 failed attempts, close dialog and stop prompting
        Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Too many incorrect attempts. Click the lock icon to try again.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {
          _pinAttempts = 0; // Reset for next time
        });
      } else {
        // Show dialog again with error count
        Navigator.of(dialogContext).pop();
        _showPINDialog();
      }
    }
  }

  // --- PIN Management Methods ---
  void _updatePINFromSettings(UserSettingsProvider settingsProvider) {
    final newPIN = settingsProvider.settings?.toolbarPIN ?? '1234';
    if (_currentPIN != newPIN) {
      setState(() {
        _currentPIN = newPIN;
      });
      debugPrint(
        'Updated Tap Interface admin toolbar PIN (length: ${_currentPIN.length})',
      );
    }
  }

  Future<void> _onAdminButtonPressed(String route) async {
    // Navigate to the admin page and wait for return
    debugPrint('🔄 TAP INTERFACE: Navigating to admin page: $route');

    await Navigator.pushNamed(context, route);

    // When user returns from admin page, refresh settings
    debugPrint(
      '🔄 TAP INTERFACE: Returned from admin page, refreshing settings...',
    );
    await _refreshSettingsFromAdmin();

    // Also refresh content context (location/activity/people)
    await _refreshContentFromAdmin();

    // Refresh PIN from settings in case it was changed
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    _updatePINFromSettings(userSettings);
  }

  /// Refresh content context after returning from admin pages
  Future<void> _refreshContentFromAdmin() async {
    try {
      debugPrint(
        '🔄 TAP INTERFACE: Fetching fresh content context from server...',
      );

      // Refresh token before API call
      final user = FirebaseAuth.instance.currentUser;
      String idToken = widget.idToken;
      if (user != null) {
        try {
          final refreshedToken = await _safeGetIdToken(
            user,
            forceRefresh: true,
          );
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
          }
        } catch (e) {
          debugPrint('Token refresh failed: $e');
        }
      }

      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/get-user-current'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('🔄 TAP INTERFACE: Got fresh context: $data');
        _applyLocationOverrideLocale(data['locationLanguageOverride']);

        if (mounted) {
          // Reload options with new context
          // We run these in parallel to save time
          await Future.wait([
            _loadInitialFreestyleOptions(contextData: data),
            _loadInitialPhraseOptions(contextData: data),
          ]);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Content refreshed based on new location'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('🔄 TAP INTERFACE: Error refreshing content: $e');
    }
  }

  /// Refresh settings after returning from admin pages
  Future<void> _refreshSettingsFromAdmin() async {
    try {
      // Reload local SharedPreferences (menu position, tap sensitivity).
      final prefs = await SharedPreferences.getInstance();
      final savedPosition = prefs.getString('tap_menu_position') ?? 'left';
      final savedSensitivity = prefs.getInt('tap_min_duration_ms') ?? 0;
      debugPrint('[TapSensitivity] _refreshSettingsFromAdmin: tap_min_duration_ms=$savedSensitivity menuPosition=$savedPosition');
      TapInterfaceButton.tapMinDurationMs = savedSensitivity;
      if (mounted) {
        setState(() {
          _menuPosition = savedPosition;
          _tapMinDurationMs = savedSensitivity;
        });
      }

      if (!mounted) return;
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );

      debugPrint('🔄 TAP INTERFACE: Fetching fresh settings from server...');

      // Force refresh settings from server
      await settingsProvider.fetchSettings();

      debugPrint('🔄 TAP INTERFACE: Settings refreshed successfully');

      // Show a brief confirmation to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings updated'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('🔄 TAP INTERFACE: Error refreshing settings: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh settings: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Clear all image caches to ensure fresh data, especially on Android
  Future<void> _clearAllCaches() async {
    // Capture locale before any awaits to avoid async BuildContext use.
    final userLocale =
        Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        ).settings?.userLanguage ??
        'en-US';

    try {
      debugPrint(
        '🔄 TAP INTERFACE: Clearing all image caches for fresh startup...',
      );

      // Preserve persistent pictogram cache so successful matches survive
      // across sessions. Only clear stale negatives.
      await PictogramService().clearNullCacheEntries();

      // Keep custom image cache warm across Tap page entries to avoid
      // re-downloading/matching delays on first board render.

      // Warm up standard control buttons so locale-specific UI controls like
      // "Something Else" (e.g. "Algo más") have an image before the grid renders.
      if (!userLocale.startsWith('en')) {
        debugPrint(
          '🌍 TAP INTERFACE: Preloading localized control button images for "$userLocale"',
        );
        await PictogramService().prefetchButtonPictograms(
          words: [
            _t('Something Else'),
            _t('Something Else A-Z'),
          ],
          locale: userLocale,
          maxItems: 2,
        );
      }

      debugPrint('✅ TAP INTERFACE: Soft cache cleanup completed successfully');

      // After clearing, immediately prefetch locale images from Firestore so that
      // word buttons have images in cache before the LLM calls return (~2-5s).
      // Fire-and-forget: runs concurrently with _loadInitialFreestyleOptions.
      if (!userLocale.startsWith('en')) {
        debugPrint(
          '🌍 TAP INTERFACE: Starting locale image prefetch for "$userLocale"',
        );
        await PictogramService().prefetchLocaleImages(userLocale);
      }

      if (mounted) {
        setState(() {
          _optionsRebuildKey++;
        });
      }
    } catch (e) {
      debugPrint('❌ TAP INTERFACE: Error clearing caches: $e');
    }
  }

  void _switchUserAccount() async {
    try {
      // Get current Firebase user and token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user logged in');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No user currently logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Match GridPage behavior: use current valid token retrieval
      final idToken = await _safeGetIdToken(user, forceRefresh: false);
      if (idToken == null) {
        debugPrint('Failed to get user token');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to get authentication token'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Fetch all user profiles to show selection page
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/account/users'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('Switch account API response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final userProfiles = json.decode(response.body);
        debugPrint('User profiles received: ${userProfiles.length} profiles');

        if (userProfiles is List && userProfiles.isNotEmpty) {
          debugPrint(
            '🔄 TapInterface: Navigating to UserSelectionPage with ${userProfiles.length} profiles',
          );
          // Navigate to the proper UserSelectionPage (same as used during login)
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => UserSelectionPage(
                idToken: idToken,
                userProfiles: userProfiles,
              ),
            ),
          );
        } else {
          debugPrint('No user profiles found in response');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No user accounts found for this login'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        debugPrint('Failed to fetch user profiles: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load user accounts (${response.statusCode})',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error switching user account: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error switching user account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _signOut() async {
    try {
      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      // Navigate to root which should show auth page after sign out
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      debugPrint('Error signing out: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error signing out'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Removed _showUserSelectionDialog and _switchToUser methods
  // Now using the proper UserSelectionPage from main.dart

  // ── Category panel + main interface layout ──────────────────────────────────

  /// Builds the purple category board panel.
  /// [horizontal] = true → renders as a fixed-height horizontal strip (top/bottom).
  /// [horizontal] = false → renders as a flex-1 vertical column (left/right).
  Widget _buildCategoryPanel(
    UserSettings? userSettings,
    Color headerTextColor, {
    required bool horizontal,
  }) {
    final tapPictogramsEnabled =
        !(userSettings?.disableTapPictograms ?? false);
    final tapSightWordLogicEnabled =
        tapPictogramsEnabled && (userSettings?.enableSightWords ?? true);
    final categories =
        (_tapConfig?.buttons ?? []).where((c) => !c.hidden).toList();

    // The "BOARDS" header button — tapping opens the all-categories modal.
    final header = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showAllCategoriesModal,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal[300]!, width: 1.5),
            borderRadius: BorderRadius.circular(6),
            color: Colors.teal[50],
          ),
          child: horizontal
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.library_books, size: 30, color: Colors.teal[800]),
                    const SizedBox(width: 4),
                    Text(
                      'BOARDS',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[800],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BOARDS',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[800],
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Divider(color: Colors.teal[300], height: 1, thickness: 1),
                    const SizedBox(height: 4),
                    Icon(Icons.library_books, size: 48, color: Colors.teal[800]),
                  ],
                ),
        ),
      ),
    );

    // Builds a single category button.
    Widget categoryButton(TapInterfaceCategory category) {
      final isSelected = _selectedCategory == category;
      return TapInterfaceButton(
        label: category.label,
        onPressed: () {
          setState(() => _navigationBreadcrumbs = []);
          _handleCategoryTap(category);
        },
        backgroundColor:
            isSelected ? headerTextColor.withValues(alpha: 0.8) : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        borderColor: isSelected
            ? headerTextColor
            : Colors.purple[300] ?? Colors.purple.shade300,
        fontSize: 18,
        enablePictograms: tapPictogramsEnabled,
        sightWordGradeLevel: userSettings?.sightWordGradeLevel,
        enableSightWords: tapSightWordLogicEnabled,
        padding: const EdgeInsets.all(2),
        assignedImageUrl: category.imageUrl,
        shouldLogMissing: false,
        cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
        mascot: userSettings?.mascot ?? '',
      );
    }

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.purple[25] ?? Colors.purple.shade50,
          Colors.purple[50] ?? Colors.purple.shade100,
        ],
        begin: horizontal ? Alignment.topCenter : Alignment.topLeft,
        end: horizontal ? Alignment.bottomCenter : Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.purple[300] ?? Colors.purple.shade300,
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.purple.withValues(alpha: 0.2),
          offset: const Offset(0, 3),
          blurRadius: 8,
        ),
      ],
    );

    if (horizontal) {
      // Top / bottom: single row of buttons with horizontal scroll.
      // Fixed height for horizontal strip: roughly one button tall.
      const stripHeight = 120.0;
      return Container(
        height: stripHeight,
        decoration: decoration,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            // BOARDS header on the left edge.
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(height: stripHeight - 8, child: header),
            ),
            // Scrollable list of category buttons.
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (context, i) => const SizedBox(width: 4),
                itemBuilder: (_, i) => AspectRatio(
                  aspectRatio: 1.0,
                  child: categoryButton(categories[i]),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Left / right: vertical column with scrollable grid.
      return Container(
        decoration: decoration,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple[50] ?? Colors.purple.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              child: header,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: categories.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => AspectRatio(
                    aspectRatio: 1.0,
                    child: categoryButton(categories[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  /// Builds the full main interface area (categories panel + options grid)
  /// arranged according to [_menuPosition].
  Widget _buildMainInterface(
    UserSettings? userSettings,
    Color headerTextColor,
  ) {
    final horizontal =
        _menuPosition == 'top' || _menuPosition == 'bottom';
    final panel = _buildCategoryPanel(
      userSettings,
      headerTextColor,
      horizontal: horizontal,
    );
    final grid = _buildOptionsGrid(userSettings, headerTextColor);

    switch (_menuPosition) {
      case 'top':
        return Column(
          children: [
            panel,
            const SizedBox(height: 8),
            Expanded(child: grid),
          ],
        );
      case 'bottom':
        return Column(
          children: [
            Expanded(child: grid),
            const SizedBox(height: 8),
            panel,
          ],
        );
      case 'right':
        return Row(
          children: [
            Expanded(flex: 9, child: grid),
            const SizedBox(width: 8),
            SizedBox(
              width: 173,
              child: panel,
            ),
          ],
        );
      default: // 'left'
        return Row(
          children: [
            SizedBox(
              width: 173,
              child: panel,
            ),
            const SizedBox(width: 8),
            Expanded(flex: 9, child: grid),
          ],
        );
    }
  }

  Widget _buildOptionsGrid(UserSettings? userSettings, Color headerTextColor) {
    if (_phraseOptions.isEmpty &&
        _wordOptions.isEmpty &&
        _boardWordOptions.isEmpty &&
        !_isLoadingPhraseOptions &&
        !_isLoadingWordOptions) {
      return Center(
        child: Text(
          'No options available',
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        final availableH = constraints.maxHeight;

        final phrasesRows = userSettings?.tapPhrasesRows ?? 0;
        final wordsRows = userSettings?.tapWordsRows ?? 3;
        final cols = _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6);
        final totalRows = phrasesRows + wordsRows;

        // Per-section vertical overhead: border (2px×2) + padding for each section.
        // Phrases section uses Padding(all(3)) → 6px vertical; Words uses Padding(all(6)) → 12px.
        const kPhrasesVOverhead = 10.0; // 4px border + 6px padding
        const kWordsVOverhead = 16.0;   // 4px border + 12px padding
        const kSectionGap = 8.0;
        const kSpacing = 2.0;

        final phraseRowSpacing = phrasesRows > 1 ? kSpacing * (phrasesRows - 1) : 0.0;
        final wordsRowSpacing = wordsRows > 1 ? kSpacing * (wordsRows - 1) : 0.0;
        final totalOverhead = (phrasesRows > 0 ? kPhrasesVOverhead + kSectionGap : 0.0)
            + kWordsVOverhead;

        final buttonSize = ((availableH - totalOverhead - phraseRowSpacing - wordsRowSpacing)
                / totalRows)
            .clamp(24.0, double.infinity);

        // Exact pixel width of the grid (cols square buttons + spacing between them).
        final gridW = buttonSize * cols + kSpacing * (cols - 1);

        // Horizontal centering: blank space on each side when buttons don't fill the width.
        // Use the larger section horizontal overhead (words = 12px padding + 4px border = 16px).
        final sectionW = gridW + 16.0;
        final hPad = ((availableW - sectionW) / 2.0).clamp(0.0, double.infinity);

        final phrasesSectionH = phrasesRows > 0
            ? phrasesRows * buttonSize + phraseRowSpacing + kPhrasesVOverhead
            : 0.0;
        final wordsSectionH = wordsRows * buttonSize + wordsRowSpacing + kWordsVOverhead;

        Widget column = Column(
          key: ValueKey(_optionsRebuildKey),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phrasesRows > 0) ...[
              SizedBox(
                height: phrasesSectionH,
                child: _buildPhrasesSection(userSettings, buttonSize, gridW),
              ),
              const SizedBox(height: kSectionGap),
            ],
            SizedBox(
              height: wordsSectionH,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue[25] ?? Colors.blue.shade50,
                      Colors.blue[50] ?? Colors.blue.shade100,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue[300] ?? Colors.blue.shade300,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.2),
                      offset: const Offset(0, 3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: gridW,
                      child: Stack(
                        children: [
                          if (!_isLoadingWordOptions ||
                              _wordOptions.isNotEmpty ||
                              _boardWordOptions.isNotEmpty)
                            _buildWordsGrid(userSettings),
                          if (_isLoadingWordOptions)
                            _wordOptions.isEmpty && _boardWordOptions.isEmpty
                                ? const Center(child: CircularProgressIndicator())
                                : const Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                      backgroundColor: Colors.transparent,
                                    ),
                                  ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        if (hPad > 0.5) {
          column = Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: column,
          );
        }

        return column;
      },
    );
  }

  /// Builds the unified words grid: static board-button rows on top, AI dynamic rows on bottom.
  Widget _buildWordsGrid(UserSettings? userSettings) {
    final totalSlots = _wordsSlotCount(userSettings);
    final staticSlots = _staticWordSlotCount(userSettings);
    final gridCols = _getEffectiveMainContentColumns(
      userSettings?.gridColumns ?? 6,
    );
    final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
    final tapPictogramsEnabled = !tapPictogramsDisabled;
    final tapSightWordLogicEnabled =
        !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);

    // In question mode, or when no board is loaded, all slots are dynamic
    final questionMode = _currentQuestion.isNotEmpty;
    final noBoardLoaded = _boardWordOptions.isEmpty;
    final effectiveStaticSlots =
        (noBoardLoaded || questionMode) ? 0 : staticSlots;
    final dynamicSlots = totalSlots - effectiveStaticSlots;

    // Something Else / Go Back controls sit at the end of the dynamic section.
    // Go Back and Something Else A-Z are mutually exclusive (board loaded vs not).
    final hasSomethingElseAZ =
        noBoardLoaded && (_selectedCategory?.hasLLMQuery ?? false);
    final hasGoBack = _navigationBreadcrumbs.isNotEmpty;
    final somethingElseAZOffset =
        hasSomethingElseAZ && dynamicSlots >= 2 ? dynamicSlots - 2 : -1;
    final goBackOffset =
        hasGoBack && dynamicSlots >= 2 ? dynamicSlots - 2 : -1;
    final somethingElseOffset = dynamicSlots >= 1 ? dynamicSlots - 1 : -1;

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: gridCols,
      childAspectRatio: 1.0,
      crossAxisSpacing: 2,
      mainAxisSpacing: 2,
      children: List.generate(totalSlots, (index) {
        final isStaticSlot = index < effectiveStaticSlots;

        if (isStaticSlot) {
          // --- Static board-button cell ---
          final rawBoardButton = _getBoardButtonAtIndex(index);
          if (rawBoardButton == null) {
            return _buildEmptyWordCell(isDynamic: false);
          }

          final pendingReturnBoardId =
              _temporaryNavigationPending
              ? _peekTemporaryReturnBoard()
              : null;
          final boardIdForModifiers =
              pendingReturnBoardId ?? _getCategoryBoardId(_selectedCategory);
          final boardButton = _applyActiveBoardModifierToButton(
            rawBoardButton,
            boardIdForModifiers,
          );

          final boardOptionKey =
              'board::${_selectedCategory?.id ?? 'none'}::${boardButton.id}';
          final isPreviewArmed =
              _isAudioSurfingEnabled &&
              _audioSurfingPreviewOptionKey == boardOptionKey;

          // Apply Past/Plural variant text (tier 1 → cache fallback)
          String displayLabel = boardButton.text;
          bool hasVariant = false;
          if (_variantMode != null) {
            String? variantText;
            // Tier 1: pre-stored field on the button
            if (_variantMode == 'past' && boardButton.pastTense != null) {
              variantText = boardButton.pastTense;
            } else if (_variantMode == 'plural' && boardButton.plural != null) {
              variantText = boardButton.plural;
            }
            // Tier 2-4: resolved via _applyVariantModeToCurrentBoard and cached
            variantText ??= _variantCache['$_variantMode:${boardButton.text}'];
            if (variantText != null && variantText.isNotEmpty) {
              displayLabel = variantText;
              hasVariant = true;
            }
          }

          // Use orange nav-button styling only for dedicated nav buttons
          // (actionType == 'navigate'). Content buttons that happen to navigate
          // to a sub-board (afterSelection == 'navigate', actionType == 'announce')
          // keep their blue content styling so the color doesn't change when
          // the app updates them from use_ai → navigate.
          final isPureNavButton = boardButton.actionType == 'navigate';

          final Color? variantGlowColor = hasVariant && _variantMode == 'past'
              ? const Color(0xFFea580c) // orange-600
              : hasVariant && _variantMode == 'plural'
              ? const Color(0xFF2563eb) // blue-600
              : isPreviewArmed
              ? const Color(0xFFd97706) // amber-600
              : null;
          final Color borderColor = variantGlowColor ??
              (isPureNavButton
                  ? (Colors.orange[300] ?? Colors.orange.shade300)
                  : (Colors.blue[300] ?? Colors.blue.shade300));

          return TapInterfaceButton(
            key: ValueKey(
              'board_${boardButton.id}_${hasVariant ? displayLabel : ''}',
            ),
            label: displayLabel,
            imageSearchText: boardButton.imageSearchText,
            onPressed: () => _handleBoardWordOptionTap(
              boardButton,
              variantLabel: hasVariant ? displayLabel : null,
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            borderColor: borderColor,
            glowColor: variantGlowColor,
            fontSize: 8,
            enablePictograms: tapPictogramsEnabled,
            sightWordGradeLevel: userSettings?.sightWordGradeLevel,
            enableSightWords: tapSightWordLogicEnabled,
            padding: const EdgeInsets.all(2),
            keywords: _wordKeywords[boardButton.text],
            assignedImageUrl: boardButton.imageUrl,
            shouldLogMissing: !boardButton.isNavigationButton,
            cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
            mascot: userSettings?.mascot ?? '',
          );
        } else {
          // --- Dynamic (AI) cell ---
          final dynamicIndex = index - effectiveStaticSlots;
          const dynamicBorderColor = Color(0xFF8b5cf6); // purple-500

          if (dynamicIndex == goBackOffset) {
            return TapInterfaceButton(
              label: _t('Go Back'),
              onPressed: _handleGoBack,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              borderColor: Colors.orange[300] ?? Colors.orange.shade300,
              fontSize: 8,
              enablePictograms: tapPictogramsEnabled,
              sightWordGradeLevel: userSettings?.sightWordGradeLevel,
              enableSightWords: tapSightWordLogicEnabled,
              padding: const EdgeInsets.all(2),
              shouldLogMissing: false,
              cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
              mascot: userSettings?.mascot ?? '',
            );
          } else if (dynamicIndex == somethingElseOffset) {
            return TapInterfaceButton(
              label: _t('Something Else'),
              onPressed: () =>
                  _loadMoreWordOptions(startsWithLetter: _activeWordLetterFilter),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              borderColor: Colors.blue[300] ?? Colors.blue.shade300,
              fontSize: 8,
              enablePictograms: tapPictogramsEnabled,
              sightWordGradeLevel: userSettings?.sightWordGradeLevel,
              enableSightWords: tapSightWordLogicEnabled,
              padding: const EdgeInsets.all(2),
              shouldLogMissing: false,
              cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
              mascot: userSettings?.mascot ?? '',
            );
          } else if (dynamicIndex == somethingElseAZOffset) {
            return TapInterfaceButton(
              label: _t('Something Else A-Z'),
              onPressed: _showSomethingElseAZDialog,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              borderColor: Colors.teal[300] ?? Colors.teal.shade300,
              fontSize: 8,
              enablePictograms: tapPictogramsEnabled,
              sightWordGradeLevel: userSettings?.sightWordGradeLevel,
              enableSightWords: tapSightWordLogicEnabled,
              padding: const EdgeInsets.all(2),
              shouldLogMissing: false,
              cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
              mascot: userSettings?.mascot ?? '',
            );
          } else if (dynamicIndex < _wordOptions.length) {
            final wordOption = _wordOptions[dynamicIndex];
            // Resolve variant label if a mode is active
            final cachedVariant = _variantMode != null
                ? _variantCache['$_variantMode:$wordOption']
                : null;
            final displayWord = cachedVariant ?? wordOption;
            final wordHasVariant = cachedVariant != null;
            final wordOptionKey =
                'word::${_selectedCategory?.id ?? 'none'}::$wordOption';
            final isPreviewArmed =
                _isAudioSurfingEnabled &&
                _audioSurfingPreviewOptionKey == wordOptionKey;
            final keywords = _wordKeywords[wordOption];
            final Color? wordGlowColor = wordHasVariant && _variantMode == 'past'
                ? const Color(0xFFea580c) // orange-600
                : wordHasVariant && _variantMode == 'plural'
                ? const Color(0xFF2563eb) // blue-600
                : isPreviewArmed
                ? const Color(0xFFd97706) // amber-600
                : null;
            return TapInterfaceButton(
              key: ValueKey(
                'dyn_${_selectedCategory?.id}_${wordOption}_${wordHasVariant ? displayWord : ''}',
              ),
              label: displayWord,
              onPressed: () => _handleWordOptionTap(displayWord),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              borderColor: wordGlowColor ?? dynamicBorderColor,
              glowColor: wordGlowColor,
              borderWidth: 2.5,
              fontSize: 8,
              enablePictograms: tapPictogramsEnabled,
              sightWordGradeLevel: userSettings?.sightWordGradeLevel,
              enableSightWords: tapSightWordLogicEnabled,
              padding: const EdgeInsets.all(2),
              keywords: keywords,
              shouldLogMissing: true,
              cacheOnlyImageLookup: _cacheOnlyInitialImageLookup,
              mascot: userSettings?.mascot ?? '',
            );
          } else {
            return _buildEmptyWordCell(isDynamic: true);
          }
        }
      }),
    );
  }

  Widget _buildEmptyWordCell({required bool isDynamic}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDynamic
              ? const Color(0xFF8b5cf6).withOpacity(0.3)
              : (Colors.blue[200] ?? Colors.blue.shade200),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  // --- Speech Bubble Overlay Methods (like main.dart) ---

  void _showSpeechBubbleOverlay(String text) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );

    // Check if speech bubble feature is enabled
    if (settingsProvider.settings?.displaySplash != true) {
      return; // Feature is disabled
    }

    // Cancel any existing timer
    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = true;
        _speechBubbleText = text;
      });
    }

    // Get duration from settings (default 3000ms)
    final duration = settingsProvider.settings?.displaySplashtime ?? 3000;

    // Auto-hide after specified duration
    _speechBubbleTimer = Timer(Duration(milliseconds: duration), () {
      _hideSpeechBubbleOverlay();
    });

    debugPrint(
      'TapInterface: Speech bubble displayed for ${duration}ms: "$text"',
    );
  }

  void _hideSpeechBubbleOverlay() {
    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = false;
        _speechBubbleText = '';
      });
    }

    debugPrint('TapInterface: Speech bubble hidden');
  }

  Future<void> _announceAudioSurfPreview(String text) async {
    try {
      await _flutterTts.stop();

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final userSettings = settingsProvider.settings;

      await _flutterTts.setSharedInstance(true);
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setPitch(1.0);

      final baseVolume = ((userSettings?.personalVolume ?? 10) / 10.0).clamp(
        0.0,
        1.0,
      );
      final previewVolume = (baseVolume * 0.30).clamp(0.0, 0.35);
      await _flutterTts.setVolume(previewVolume);

      final ttsCompleter = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      });

      debugPrint(
        '[TapInterface] Audio Surfing whisper preview volume=$previewVolume for "$text"',
      );
      await _flutterTts.speak(text);

      final wordCount = text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      final estimatedDurationMs = (wordCount * 700) + 3000;
      final timeout = Duration(
        milliseconds: estimatedDurationMs.clamp(5000, 60000),
      );
      try {
        await ttsCompleter.future.timeout(timeout);
      } on TimeoutException {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      }

      _flutterTts.setCompletionHandler(() {});
    } catch (e) {
      debugPrint(
        '[TapInterface] Audio Surfing preview failed, falling back to normal announce: $e',
      );
      await _announceViaBackend(text);
    }
  }

  /// Announce text using local FlutterTts at low volume (system voice, not TTS voice).
  /// Used for translated wake-word questions and similar system-level announcements.
  /// Mirrors the grid page's _speakPersonalVoice pattern for consistency.
  /// - volumeScale: multiplier on base volume (default 0.5 for 50%)
  /// - speechRate: TTS speech rate (default 0.5 for clear audio, matches grid page)
  Future<void> _announceLowVolumeSystemAudio(
    String text, {
    double volumeScale = 0.5,
    double speechRate = 0.5,
  }) async {
    try {
      await _flutterTts.stop();

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final userSettings = settingsProvider.settings;

      await _flutterTts.setSharedInstance(true);
      await _flutterTts.setSpeechRate(speechRate);
      await _flutterTts.setPitch(1.0);

      final baseVolume = ((userSettings?.personalVolume ?? 10) / 10.0).clamp(
        0.0,
        1.0,
      );
      final announceVolume = (baseVolume * volumeScale).clamp(0.0, 1.0);
      await _flutterTts.setVolume(announceVolume);

      final ttsCompleter = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      });

      debugPrint(
        '[TapInterface] Low-volume system announcement (rate=$speechRate, vol=$announceVolume) for "$text"',
      );
      await _flutterTts.speak(text);

      final wordCount = text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      final estimatedDurationMs = (wordCount * 1400) + 1000; // Adjusted for slower speech
      final timeout = Duration(
        milliseconds: estimatedDurationMs.clamp(5000, 60000),
      );
      try {
        await ttsCompleter.future.timeout(timeout);
      } on TimeoutException {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      }

      _flutterTts.setCompletionHandler(() {});
    } catch (e) {
      debugPrint(
        '[TapInterface] Low-volume system announcement failed, falling back to backend: $e',
      );
      // Fallback to backend announcement
      await _announceViaBackend(text);
    }
  }

  Future<bool> _handleAudioSurfingTap(
    String optionKey,
    String announceText,
  ) async {
    if (!_isAudioSurfingEnabled) {
      return true;
    }

    final isSecondTap = _audioSurfingPreviewOptionKey == optionKey;
    if (isSecondTap) {
      setState(() {
        _audioSurfingPreviewOptionKey = null;
      });
      return true;
    }

    setState(() {
      _audioSurfingPreviewOptionKey = optionKey;
      _statusMessage =
          'Audio Surfing preview. Tap the same option again to select it.';
    });

    _showSpeechBubbleOverlay(announceText);
    await _announceAudioSurfPreview(announceText);
    return false;
  }

  // --- Option Tap Handlers ---

  Future<void> _handlePhraseOptionTap(String fullText) async {
    // Debounce: prevent rapid multiple taps
    if (_isTapInProgress) {
      debugPrint('[TapInterface] ⏱️ Tap debounced - tap already in progress');
      return;
    }

    _setTapInProgress();

    debugPrint('[TapInterface] === PHRASE OPTION TAPPED ===');
    debugPrint('[TapInterface] Phrase option tapped: "$fullText"');
    debugPrint(
      '[TapInterface] Current speech history BEFORE: "$_speechHistory"',
    );
    debugPrint(
      '[TapInterface] Speech history controller BEFORE: "${_speechHistoryController.text}"',
    );

    final proceedWithSelection = await _handleAudioSurfingTap(
      'phrase::$fullText',
      fullText,
    );
    if (!proceedWithSelection) {
      return;
    }

    // Show speech bubble immediately
    _showSpeechBubbleOverlay(fullText);

    // Announce the full text immediately using backend TTS (same voice as "I am listening")
    await _announceViaBackend(fullText);

    // Add to past speech history (visible in History button)
    setState(() {
      _pastSpeechHistory.add(fullText);
      debugPrint(
        '[TapInterface] Added to _pastSpeechHistory: "$fullText" (total: ${_pastSpeechHistory.length})',
      );
    });

    // Add to speech history (which serves as build space)
    if (_speechHistory.trim().isNotEmpty) {
      _speechHistory += ' $fullText';
    } else {
      _speechHistory = fullText;
    }
    _speechHistoryController.text = _speechHistory;

    // Also update _buildSpaceText for compatibility with existing logic
    _buildSpaceText = _speechHistory;

    // Record to chat history (same as web app)
    final chatService = ChatHistoryService();
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    chatService
        .recordChatHistoryWithProvider(
          question: '',
          response: fullText.trim(),
          userSettingsProvider: userSettings,
        )
        .catchError((error) {
          print('❌ Failed to record phrase chat history: $error');
        });

    debugPrint('[TapInterface] Speech history AFTER: "$_speechHistory"');
    debugPrint(
      '[TapInterface] Speech history controller AFTER: "${_speechHistoryController.text}"',
    );
    debugPrint('[TapInterface] Build space text AFTER: "$_buildSpaceText"');

    debugPrint(
      '[TapInterface] Added phrase to speech history: "$_speechHistory"',
    );

    // Update status message
    setState(() {
      _statusMessage =
          'Phrase added to speech. Say "${_getFormattedWakeWord()}" to ask a question.';
    });

    if (await _returnFromTemporaryNavigationIfNeeded()) {
      return;
    }

    // Regenerate word options based on new speech history content
    await _loadWordOptionsBasedOnBuildSpace();

    // Regenerate phrase options based on new speech history content
    await _loadPhraseOptionsBasedOnBuildSpace();
  }

  Future<void> _handleWordOptionTap(String word) async {
    // Debounce: prevent rapid multiple taps
    if (_isTapInProgress) {
      debugPrint('[TapInterface] ⏱️ Tap debounced - tap already in progress');
      return;
    }

    _setTapInProgress();

    debugPrint('[TapInterface] === WORD OPTION TAPPED ===');
    debugPrint('[TapInterface] Word option tapped: "$word"');
    debugPrint(
      '[TapInterface] Current speech history BEFORE: "$_speechHistory"',
    );
    debugPrint(
      '[TapInterface] Speech history controller BEFORE: "${_speechHistoryController.text}"',
    );
    debugPrint(
      '[TapInterface] Selected category wordsPrompt: "${_selectedCategory?.wordsPrompt}"',
    );
    debugPrint('[TapInterface] Text prompt already used: $_textPromptUsed');

    final proceedWithSelection = await _handleAudioSurfingTap(
      'word::${_selectedCategory?.id ?? 'none'}::$word',
      word,
    );
    if (!proceedWithSelection) {
      return;
    }

    // Reset variant mode on selection
    if (_variantMode != null) {
      setState(() => _variantMode = null);
    }

    String textToAdd = word;
    String textToAnnounce = word;

    // Check if we have a wordsPrompt for text completion AND it hasn't been used yet
    if (_selectedCategory?.wordsPrompt != null &&
        _selectedCategory!.wordsPrompt!.isNotEmpty &&
        !_textPromptUsed) {
      // Combine wordsPrompt with the selected word for completion (first use only)
      textToAdd = '${_selectedCategory!.wordsPrompt!} $word';
      textToAnnounce = textToAdd; // Announce the full completed phrase
      _textPromptUsed = true; // Mark the text prompt as used
      debugPrint(
        '[TapInterface] Text completion (first use): "${_selectedCategory!.wordsPrompt!}" + "$word" = "$textToAdd"',
      );
    } else {
      // For subsequent selections, just use the word without the prompt
      debugPrint(
        '[TapInterface] Using word only (prompt already used or not available): "$word"',
      );
    }

    // Show speech bubble for the announced text
    _showSpeechBubbleOverlay(textToAnnounce);

    // Announce the text (either just the word or the completed phrase)
    await _announceViaBackend(textToAnnounce);

    // NOTE: Do NOT add individual words to _pastSpeechHistory
    // Only phrases (selected from phrases section) and the Speak button should record to history
    // Individual words are only for building/staging text, not final utterances

    // Add to speech history (which serves as build space)
    if (_speechHistory.trim().isNotEmpty) {
      _speechHistory += ' $textToAdd';
    } else {
      _speechHistory = textToAdd;
    }
    _speechHistoryController.text = _speechHistory;

    // Also update _buildSpaceText for compatibility with existing logic
    _buildSpaceText = _speechHistory;

    // Record to chat history (same as web app)
    final chatService = ChatHistoryService();
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    chatService
        .recordChatHistoryWithProvider(
          question: '',
          response: textToAnnounce
              .trim(), // Use the announced text for chat history
          userSettingsProvider: userSettings,
        )
        .catchError((error) {
          print('❌ Failed to record word chat history: $error');
        });

    debugPrint(
      '[TapInterface] Speech history AFTER adding "$textToAdd": "$_speechHistory"',
    );
    debugPrint(
      '[TapInterface] Speech history controller AFTER: "${_speechHistoryController.text}"',
    );

    // Update status message
    setState(() {
      _statusMessage =
          'Text added to speech. Say "${_getFormattedWakeWord()}" to ask a question.';
    });

    if (await _returnFromTemporaryNavigationIfNeeded()) {
      return;
    }

    // Regenerate word options based on new speech history content
    await _loadWordOptionsBasedOnBuildSpace();

    // Regenerate phrase options based on new speech history content
    await _loadPhraseOptionsBasedOnBuildSpace();
  }

  Future<void> _handleBoardWordOptionTap(TapBoardButton button, {String? variantLabel}) async {
    // Debounce: prevent rapid multiple taps
    if (_isTapInProgress) {
      debugPrint('[TapInterface] ⏱️ Tap debounced - tap already in progress');
      return;
    }

    _setTapInProgress();

    final pendingReturnBoardId = _temporaryNavigationPending
        ? _peekTemporaryReturnBoard()
        : null;
    final boardIdForModifiers =
        pendingReturnBoardId ?? _getCategoryBoardId(_selectedCategory);
    final effectiveButton = _applyActiveBoardModifierToButton(
      button,
      boardIdForModifiers,
    );

    final optionKey = 'board::${_selectedCategory?.id ?? 'none'}::${button.id}';
    final previewLabel = effectiveButton.speechText ?? effectiveButton.text;
    final proceedWithSelection = await _handleAudioSurfingTap(
      optionKey,
      previewLabel,
    );
    if (!proceedWithSelection) {
      return;
    }

    // Reset variant mode on selection
    if (_variantMode != null) {
      setState(() => _variantMode = null);
    }

    // Navigation buttons with content text (e.g. "food", "more") should still
    // speak and add their label to the build space. Only suppress for buttons
    // that carry no meaningful content text (pure nav buttons have empty text).
    // Use the variant label (e.g. "cars", "went") when one is active so the
    // announced word matches what the button showed.
    final textToAdd = variantLabel ?? effectiveButton.text;
    final textToAnnounce = variantLabel ?? effectiveButton.speechText ?? effectiveButton.text;

    if (textToAnnounce.isNotEmpty) {
      _showSpeechBubbleOverlay(textToAnnounce);
      await _announceViaBackend(textToAnnounce);
    }

    if (effectiveButton.customAudioFile != null &&
        effectiveButton.customAudioFile!.isNotEmpty) {
      _playCustomAudio(effectiveButton.customAudioFile!);
    }

    if (textToAdd.isNotEmpty) {
      if (_speechHistory.trim().isNotEmpty) {
        _speechHistory += ' $textToAdd';
      } else {
        _speechHistory = textToAdd;
      }
      _speechHistoryController.text = _speechHistory;
      _buildSpaceText = _speechHistory;
    }

    if (textToAnnounce.trim().isNotEmpty) {
      final chatService = ChatHistoryService();
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      chatService
          .recordChatHistoryWithProvider(
            question: '',
            response: textToAnnounce.trim(),
            userSettingsProvider: userSettings,
          )
          .catchError((error) {
            debugPrint('❌ Failed to record board button chat history: $error');
          });
    }

    final hadActiveModifier =
        _getActiveBoardModifierId(boardIdForModifiers) != null;
    final nextModifierId = effectiveButton.modifierTriggerId?.toString();
    if ((nextModifierId ?? '').trim().isNotEmpty) {
      _setActiveBoardModifier(boardIdForModifiers, nextModifierId);
    } else if (hadActiveModifier) {
      _clearActiveBoardModifier(boardIdForModifiers);
    }

    final effectiveTargetBoardId = _normalizeBoardId(
      effectiveButton.targetBoardId,
    );
    if (effectiveButton.temporaryNavigation && effectiveTargetBoardId != null) {
      final returnBoardId = _getCurrentBoardIdForTemporaryNavigation();
      if (returnBoardId != null) {
        _pushTemporaryReturnBoard(returnBoardId);
      }

      final targetCategory = _resolveTargetCategory(effectiveTargetBoardId);
      if (targetCategory != null) {
        await _handleCategoryTap(targetCategory);
        return;
      }
    }

    if (await _returnFromTemporaryNavigationIfNeeded()) {
      return;
    }

    if ((nextModifierId ?? '').trim().isNotEmpty || hadActiveModifier) {
      setState(() {});
    }

    final effectiveAfterSelection = effectiveButton.afterSelection.isNotEmpty
        ? effectiveButton.afterSelection
        : 'use_ai';

    if (effectiveAfterSelection == 'navigate' &&
        effectiveTargetBoardId != null) {
      _clearTemporaryNavigationState();
      final currentBoardId = _getCategoryBoardId(_selectedCategory);
      if (currentBoardId != null) {
        setState(() {
          _navigationBreadcrumbs = [
            ..._navigationBreadcrumbs,
            (boardId: currentBoardId, addedText: textToAdd),
          ];
        });
      }
      final targetCategory = _resolveTargetCategory(effectiveTargetBoardId);
      if (targetCategory != null) {
        await _handleCategoryTap(targetCategory);
        return;
      }
    }

    if (effectiveAfterSelection == 'navigate_home') {
      _clearTemporaryNavigationState();
      setState(() => _navigationBreadcrumbs = []);
      await _openConfiguredHomeBoard();
      return;
    }

    if (effectiveAfterSelection == 'use_ai' ||
        effectiveAfterSelection == 'do_nothing') {
      if (effectiveAfterSelection == 'use_ai') {
        // Push current board so user can Go Back after AI board is generated.
        final currentBoardId = _getCategoryBoardId(_selectedCategory);
        if (currentBoardId != null) {
          setState(() {
            _navigationBreadcrumbs = [
              ..._navigationBreadcrumbs,
              (boardId: currentBoardId, addedText: textToAdd),
            ];
          });
        }
        await _generateAndSaveAIBoard(
          tappedButton: effectiveButton,
          parentBoardId: boardIdForModifiers,
        );
        return;
      }
      // do_nothing: text was added, no further action
    }
  }

  // ---------------------------------------------------------------------------
  // AI Board Generation (use_ai afterSelection)
  // ---------------------------------------------------------------------------

  /// Converts a [TapBoardButton] to the JSON payload expected by the backend.
  Map<String, dynamic> _buttonToJson(TapBoardButton btn) => {
    'id': btn.id,
    'text': btn.text,
    'label': btn.text,
    'speech_text': btn.speechText,
    'row': btn.row,
    'col': btn.col,
    'after_selection': btn.afterSelection,
    'target_board_id': btn.targetBoardId,
    'action_type': btn.actionType,
    'hidden': btn.hidden,
    'button_type': btn.buttonType,
    'image_url': btn.imageUrl,
    'background_color': btn.backgroundColor,
    'text_color': btn.textColor,
    'past_tense': btn.pastTense,
    'plural': btn.plural,
  };

  /// When a static button has `after_selection: use_ai`, this method:
  /// 1. Generates static board buttons via LLM based on current speech history.
  /// 2. Saves the new board via POST /api/tap-interface/boards.
  /// 3. Updates [tappedButton] on [parentBoardId] to navigate to the new board.
  /// 4. Reloads the board config and navigates to the new board.
  Future<void> _generateAndSaveAIBoard({
    required TapBoardButton tappedButton,
    required String? parentBoardId,
  }) async {
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final settings = userSettings.settings;
    final userId = userSettings.userId ?? widget.aacUserId;

    final gridCols = _getEffectiveMainContentColumns(
      settings?.gridColumns ?? 6,
    );
    final tapWordsRows = settings?.tapWordsRows ?? 3;
    final tapDynamicRows = settings?.tapDynamicRows ?? 1;
    final staticRows = (tapWordsRows - tapDynamicRows).clamp(0, tapWordsRows);
    final staticSlotCount = staticRows * gridCols;

    if (staticSlotCount == 0) {
      // Nothing static to generate — fall back to plain AI refresh.
      setState(() {
        _boardWordOptions = [];
        _wordOptions = [];
      });
      await _loadWordOptionsBasedOnBuildSpace();
      await _loadPhraseOptionsBasedOnBuildSpace();
      return;
    }

    setState(() {
      _isLoadingWordOptions = true;
      _showStatusToast('Generating board…');
    });

    try {
      // ── 1. Reuse existing board if one already exists for this button ─────
      // Board label = tapped button text (no prefix — keeps alphabetical sort clean).
      final boardLabel = tappedButton.text;
      final existingBoard = _tapBoards?.boards.where(
        (b) => b.label.trim().toLowerCase() == boardLabel.trim().toLowerCase(),
      ).firstOrNull;

      if (existingBoard != null && existingBoard.buttons.isNotEmpty) {
        debugPrint(
          '[TapInterface] ♻️ Reusing existing board "${existingBoard.label}" (${existingBoard.id})',
        );
        // Navigate immediately — board data is already in _tapBoards.
        final existingCategory = _buildCategoryFromBoard(existingBoard);
        setState(() => _statusMessage = '');
        await _handleCategoryTap(existingCategory);

        // Update the source button in the background so future taps navigate
        // directly (no need to block navigation on this).
        _updateSourceButton(
          parentBoardId: parentBoardId,
          tappedButton: tappedButton,
          newBoardId: existingBoard.id,
          userId: userId,
        ).then((_) async {
          if (!mounted) return;
          final freshBoards = await _tapService.fetchTapBoards();
          if (mounted && freshBoards != null) {
            setState(() => _tapBoards = freshBoards);
          }
        }).catchError((e) {
          debugPrint('[TapInterface] ❌ Background source update error: $e');
        });
        return;
      }

      // ── 2. Generate static button labels (same short-word style as dynamic row)
      final speechContext = _speechHistory.trim();
      // Use the tapped button's text (the board topic) as context, not the parent
      // board's label — e.g. tapping "am" on the "I" board should generate words
      // like "hungry, tired, happy" (topic = "am"), not "I"-topic words.
      final context = tappedButton.text.trim().isNotEmpty
          ? tappedButton.text.trim()
          : 'general communication';
      final currentMood = settings?.currentMood;

      final rawWords = await _tapService.generateFreestyleOptions(
        context: context,
        buildSpaceText: speechContext,
        singleWordsOnly: true,
        maxOptions: staticSlotCount + 5,
        currentMood: (currentMood != null && currentMood != 'No Mood Selected')
            ? currentMood
            : null,
        excludeOptions: _displayedStaticButtonLabels(settings),
      );

      // Client-side dedup of any options that are identical to the static buttons
      final excludeSet = _displayedStaticButtonLabels(settings)
          .map((e) => e.toLowerCase().trim())
          .toSet();
      final optionLabels = rawWords
          .where((s) => s.isNotEmpty && !excludeSet.contains(s.toLowerCase().trim()))
          .take(staticSlotCount)
          .toList();

      // ── 3. Build button list ──────────────────────────────────────────────
      final buttons = <Map<String, dynamic>>[];
      for (var i = 0; i < optionLabels.length; i++) {
        final row = i ~/ gridCols;
        final col = i % gridCols;
        buttons.add({
          'id': 'btn_${row}_$col',
          'text': optionLabels[i],
          'label': optionLabels[i],
          'speech_text': optionLabels[i],
          'row': row,
          'col': col,
          'after_selection': 'use_ai',
          'action_type': 'announce',
          'hidden': false,
          'button_type': 'static',
        });
      }

      // ── 4. Navigate immediately with a temp board ID ──────────────────────
      // Assign a client-side temp ID so we can navigate before the POST
      // completes. The POST (which can be slow) runs in the background and
      // swaps in the real server-assigned ID when done.
      final tempBoardId =
          '_temp_${DateTime.now().millisecondsSinceEpoch}';
      final newBoardButtonObjects = buttons
          .map((b) => TapBoardButton.fromJson(b))
          .toList();
      final tempBoard = TapBoard(
        id: tempBoardId,
        label: boardLabel,
        boardType: 'static',
        buttons: newBoardButtonObjects,
      );
      setState(() {
        _tapBoards = TapBoardsResponse(
          boards: [...(_tapBoards?.boards ?? const <TapBoard>[]), tempBoard],
          boardSettings:
              _tapBoards?.boardSettings ?? const TapBoardSettings(),
        );
        _statusMessage = '';
      });

      await _handleCategoryTap(_buildCategoryFromBoard(tempBoard));

      // ── 5. Persist board + link source button in the background ───────────
      // None of these operations block the user from interacting with the new
      // board. When the POST returns the real ID we swap it into _tapBoards
      // and update any breadcrumbs that still hold the temp ID.
      () async {
        try {
          final createResponse =
              await AuthenticatedHttpClient.makeAuthenticatedRequest(
                'POST',
                '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/boards',
                baseHeaders: {
                  'X-User-ID': userId,
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'label': boardLabel,
                  'board_type': 'static',
                  'buttons': buttons,
                }),
              );

          if (createResponse.statusCode != 200 &&
              createResponse.statusCode != 201) {
            debugPrint(
              '[TapInterface] ⚠️ Board POST failed (${createResponse.statusCode}) — temp board stays in memory',
            );
            return;
          }

          final createData =
              jsonDecode(createResponse.body) as Map<String, dynamic>;
          final realBoardId =
              (createData['board'] as Map<String, dynamic>?)?['id']
                  as String? ??
              (createData['id'] as String?);

          if (realBoardId == null || realBoardId.isEmpty) {
            debugPrint('[TapInterface] ⚠️ Board POST returned no ID');
            return;
          }

          // Replace temp board with real board; patch breadcrumbs.
          if (mounted && _tapBoards != null) {
            final realBoard = TapBoard(
              id: realBoardId,
              label: boardLabel,
              boardType: 'static',
              buttons: newBoardButtonObjects,
            );
            setState(() {
              _tapBoards = TapBoardsResponse(
                boards: _tapBoards!.boards
                    .where((b) => b.id != tempBoardId)
                    .toList()
                  ..add(realBoard),
                boardSettings: _tapBoards!.boardSettings,
              );
              // Update any breadcrumb that still carries the temp ID.
              _navigationBreadcrumbs = _navigationBreadcrumbs
                  .map(
                    (c) => c.boardId == tempBoardId
                        ? (boardId: realBoardId, addedText: c.addedText)
                        : c,
                  )
                  .toList();
            });
          }

          // Link the source button and refresh authoritative boards state.
          await _updateSourceButton(
            parentBoardId: parentBoardId,
            tappedButton: tappedButton,
            newBoardId: realBoardId,
            userId: userId,
          );
          if (!mounted) return;
          final freshBoards = await _tapService.fetchTapBoards();
          if (mounted && freshBoards != null) {
            setState(() => _tapBoards = freshBoards);
          }
        } catch (e) {
          debugPrint('[TapInterface] ❌ Background board save error: $e');
        }
      }();
    } catch (e) {
      debugPrint('[TapInterface] ❌ _generateAndSaveAIBoard error: $e');
      if (mounted) {
        setState(() {
          _isLoadingWordOptions = false;
          _statusMessage = '';
        });
        // Fallback: plain AI refresh so the user isn't left with a blank screen.
        await _loadWordOptionsBasedOnBuildSpace();
        await _loadPhraseOptionsBasedOnBuildSpace();
      }
    }
  }

  /// Updates the [tappedButton] on [parentBoardId] to navigate directly to
  /// [newBoardId] on future taps (changing `after_selection` from `use_ai` to
  /// `navigate`).  Skips silently when the parent board can't be found or is
  /// read-only, so the caller doesn't need to guard against it.
  Future<void> _updateSourceButton({
    required String? parentBoardId,
    required TapBoardButton tappedButton,
    required String newBoardId,
    required String userId,
  }) async {
    if (parentBoardId == null || parentBoardId.isEmpty) return;

    // The Home board category typically has no explicit board_id, so
    // _getCategoryBoardId falls back to the category's own id.  If that id
    // isn't found in the boards list, try the configured home_board_id instead.
    TapBoard? parentBoard = _tapBoards?.boards.where(
      (b) => b.id == parentBoardId,
    ).firstOrNull;

    String effectiveBoardId = parentBoardId;
    if (parentBoard == null) {
      final homeBoardId = _normalizeBoardId(
        _tapBoards?.boardSettings.homeBoardId,
      );
      if (homeBoardId != null && homeBoardId.isNotEmpty) {
        final homeBoard = _tapBoards?.boards.where(
          (b) => b.id == homeBoardId,
        ).firstOrNull;
        if (homeBoard != null) {
          parentBoard = homeBoard;
          effectiveBoardId = homeBoardId;
          debugPrint(
            '[TapInterface] 🏠 Home board fallback: using homeBoardId $homeBoardId',
          );
        }
      }
    }

    final sourceButtons =
        parentBoard?.buttons.isNotEmpty == true
        ? parentBoard!.buttons
        : _boardWordOptions;

    if (sourceButtons.isEmpty) {
      debugPrint('[TapInterface] ⚠️ No source buttons found for board $parentBoardId');
      return;
    }

    final updatedButtons = sourceButtons.map((btn) {
      final isMatch = btn.id == tappedButton.id ||
          btn.text.toLowerCase().trim() == tappedButton.text.toLowerCase().trim();
      if (isMatch) {
        return {
          ..._buttonToJson(btn),
          'after_selection': 'navigate',
          'target_board_id': newBoardId,
        };
      }
      return _buttonToJson(btn);
    }).toList();

    final boardLabel = parentBoard?.label ?? _selectedCategory?.label ?? 'Board';
    final boardType = parentBoard?.boardType ?? 'static';

    final putResp = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'PUT',
      '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/boards/$effectiveBoardId',
      baseHeaders: {
        'X-User-ID': userId,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'label': boardLabel,
        'board_type': boardType,
        'default_columns': parentBoard?.defaultColumns ?? 12,
        'max_rows': parentBoard?.maxRows ?? 7,
        'hidden': parentBoard?.hidden ?? false,
        'llm_prompt': parentBoard?.llmPrompt,
        'buttons': updatedButtons,
      }),
    );

    debugPrint('[TapInterface] PUT $effectiveBoardId → ${putResp.statusCode}');

    // Only fall back to the nav config patch when the PUT was rejected.
    // legacy_category boards return 403 because they are read-only via PUT;
    // their buttons live in board_word_options inside the nav config, so we
    // must patch the config directly.
    //
    // For custom / AI-generated boards the PUT succeeds (200/201) and is the
    // authoritative update. Calling the nav config patch for those boards is
    // NOT safe: the generated button IDs (btn_0_0, btn_0_1 …) can collide with
    // IDs of unrelated buttons that happen to be stored in the nav config,
    // causing the wrong button to be patched (e.g. Home board's "I" button
    // getting its target changed to the most recently generated board).
    final putSucceeded =
        putResp.statusCode == 200 || putResp.statusCode == 201;
    if (!putSucceeded) {
      await _updateLegacyButtonViaNavConfig(
        tappedButton: tappedButton,
        newBoardId: newBoardId,
        userId: userId,
      );
    }
  }

  /// Patches a button's after_selection+target_board_id inside the full nav
  /// config (required for legacy_category boards which are read-only via PUT).
  Future<void> _updateLegacyButtonViaNavConfig({
    required TapBoardButton tappedButton,
    required String newBoardId,
    required String userId,
  }) async {
    try {
      // 1. Fetch raw config JSON
      final getResp = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/config',
        baseHeaders: {
          'X-User-ID': userId,
          'Content-Type': 'application/json',
        },
      );
      if (getResp.statusCode != 200) {
        debugPrint(
          '[TapInterface] ❌ Config GET failed: ${getResp.statusCode}',
        );
        return;
      }

      final configJson = jsonDecode(getResp.body) as Map<String, dynamic>;

      // 2. Walk all buttons arrays looking for the matching button by ID or text
      bool patched = false;

      void patchButtonList(List<dynamic> buttonList) {
        for (var i = 0; i < buttonList.length; i++) {
          final btn = buttonList[i];
          if (btn is! Map<String, dynamic>) continue;

          final btnId = (btn['id'] ?? '').toString();
          final btnText = (btn['text'] ?? btn['label'] ?? '').toString().toLowerCase().trim();
          final tapText = tappedButton.text.toLowerCase().trim();
          final tapId = tappedButton.id;

          if (btnId == tapId || btnText == tapText) {
            buttonList[i] = {
              ...btn,
              'after_selection': 'navigate',
              'target_board_id': newBoardId,
            };
            patched = true;
            debugPrint(
              '[TapInterface] ✅ Patched legacy button "$btnText" in nav config',
            );
            return;
          }

          // Recurse into board_word_options
          final wordOpts = btn['board_word_options'];
          if (wordOpts is List) patchButtonList(wordOpts);

          // Recurse into children
          final children = btn['children'];
          if (children is List) patchButtonList(children);
        }
      }

      // Search top-level buttons
      final topButtons = configJson['buttons'];
      if (topButtons is List) patchButtonList(topButtons);

      // Also search any boards embedded in the config
      final boards = configJson['boards'];
      if (!patched && boards is List) {
        for (final board in boards) {
          if (board is! Map<String, dynamic>) continue;
          final boardBtns = board['buttons'];
          if (boardBtns is List) patchButtonList(boardBtns);
          if (patched) break;
        }
      }

      if (!patched) {
        debugPrint(
          '[TapInterface] ⚠️ Button "${tappedButton.text}" not found in nav config',
        );
        return;
      }

      // 3. POST updated config back
      final postResp = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/tap-interface/config',
        baseHeaders: {
          'X-User-ID': userId,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(configJson),
      );

      if (postResp.statusCode == 200 || postResp.statusCode == 201) {
        debugPrint('[TapInterface] ✅ Nav config updated for legacy button patch');
      } else {
        debugPrint(
          '[TapInterface] ❌ Nav config POST failed: ${postResp.statusCode}: ${postResp.body}',
        );
      }
    } catch (e) {
      debugPrint('[TapInterface] ❌ _updateLegacyButtonViaNavConfig error: $e');
    }
  }

  /// Enable tap debouncing to prevent rapid multiple taps on buttons
  void _setTapInProgress() {
    _isTapInProgress = true;
    _tapDebounceTimer?.cancel();
    _tapDebounceTimer = Timer(Duration(milliseconds: _tapDebounceMs), () {
      _isTapInProgress = false;
      debugPrint('[TapInterface] ✅ Tap debounce cleared - ready for next tap');
    });
  }

  Future<void> _loadWordOptionsBasedOnBuildSpace() async {
    // Snapshot the active category so stale async completions don't overwrite
    // results from a newer navigation.
    final snapshotCategoryId = _selectedCategory?.id;
    try {
      setState(() {
        _isLoadingWordOptions = true;
      });

      debugPrint('[TapInterface] === WORD OPTIONS REFRESH ===');
      debugPrint('[TapInterface] Build space text: "$_buildSpaceText"');
      debugPrint(
        '[TapInterface] Selected category: ${_selectedCategory?.label}',
      );
      debugPrint(
        '[TapInterface] Build space empty: ${_buildSpaceText.isEmpty}',
      );
      debugPrint(
        '[TapInterface] _selectedCategory != null: ${_selectedCategory != null}',
      );

      List<String> wordOpts = [];

      // Decide which API to use based on context
      if (_selectedCategory != null && _buildSpaceText.isEmpty) {
        debugPrint('[TapInterface] Using Category Words API');

        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final currentMood =
            userSettings.settings?.currentMood ?? 'No Mood Selected';
        final maxWordOptions = userSettings.settings?.freestyleOptions ?? 29;

        // Exclude words already visible in static rows so dynamic options are distinct
        final excludeStatic =
            _displayedStaticButtonLabels(userSettings.settings);

        final selectedCategory = _selectedCategory;
        String categoryLabel;
        if (selectedCategory != null &&
            _shouldUseDefaultHomeStarterWords(selectedCategory)) {
          // Home board with no explicit word options — use the built-in AAC
          // starter-word prompt.
          categoryLabel = _getDefaultHomeStarterPrompt(maxWordOptions);
        } else if (selectedCategory?.llmPrompt != null &&
            selectedCategory!.llmPrompt!.isNotEmpty) {
          // Board has a configured LLM prompt — use it verbatim so the dynamic
          // row respects the board's intended vocabulary (e.g. the Home board's
          // "Generate high-frequency starters…" prompt rather than just the
          // label "home", which produces literal house-related words).
          categoryLabel = selectedCategory.llmPrompt!;
          if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
            categoryLabel =
                '$categoryLabel appropriate for someone feeling $currentMood';
          }
        } else {
          categoryLabel = selectedCategory?.label ?? '';
          if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
            categoryLabel =
                '${selectedCategory?.label ?? ''} appropriate for someone feeling $currentMood';
          }
        }

        wordOpts = await _tapService.generateCategoryWords(
          category: categoryLabel,
          buildSpaceContent: _buildSpaceText,
          excludeWords: excludeStatic,
          maxOptions: maxWordOptions,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint(
          '[TapInterface] Category Words API returned ${wordOpts.length} words',
        );
      } else {
        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final currentMood =
            userSettings.settings?.currentMood ?? 'No Mood Selected';
        final maxWordOptions = userSettings.settings?.freestyleOptions ?? 29;

        final excludeStatic =
            _displayedStaticButtonLabels(userSettings.settings);

        String ctx;
        if (_selectedCategory != null) {
          ctx = _selectedCategory?.label ?? '';
        } else if (_buildSpaceText.isNotEmpty) {
          ctx = _buildSpaceText;
        } else {
          ctx = 'general communication topics';
        }

        String contextWithMood = ctx;
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          contextWithMood = '$ctx appropriate for someone feeling $currentMood';
        }

        wordOpts = await _tapService.generateFreestyleOptions(
          context: contextWithMood,
          buildSpaceText: _buildSpaceText,
          singleWordsOnly: true,
          maxOptions: maxWordOptions,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
          excludeOptions: excludeStatic,
        );
        debugPrint(
          '[TapInterface] Freestyle API returned ${wordOpts.length} word options',
        );
      }

      debugPrint(
        '[TapInterface] First 5 options: ${wordOpts.take(5).toList()}',
      );

      // Client-side exclusion: always filter static labels out of dynamic options
      // regardless of which API path was taken (server-side exclusion is unreliable).
      if (mounted) {
        final excludeForFilter = _displayedStaticButtonLabels(
          Provider.of<UserSettingsProvider>(context, listen: false).settings,
        );
        if (excludeForFilter.isNotEmpty) {
          final excludeSet =
              excludeForFilter.map((e) => e.toLowerCase().trim()).toSet();
          wordOpts = wordOpts
              .where((w) => !excludeSet.contains(w.toLowerCase().trim()))
              .toList();
        }
      }

      if (mounted) {
        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;

        List<String> newOptions;
        if (wordOpts.isNotEmpty) {
          // Deduplicate words to avoid case-sensitive duplicates
          final deduplicatedWords = _deduplicateWords(wordOpts);
          debugPrint(
            '[TapInterface] Word options refresh - Original: ${wordOpts.length}, Deduplicated: ${deduplicatedWords.length}',
          );
          newOptions = deduplicatedWords.take(requiredWordCount).toList();

          // CRITICAL FIX: Ensure we always have exactly the required number of options
          if (newOptions.length < requiredWordCount) {
            debugPrint(
              '[TapInterface] ⚠️  Only have ${newOptions.length} options after deduplication, need $requiredWordCount. Adding fallbacks...',
            );
            final currentWordsLower = newOptions
                .map((w) => w.toLowerCase())
                .toSet();
            final fallbackOptions = _getFallbackWordOptions()
                .where(
                  (word) => !currentWordsLower.contains(word.toLowerCase()),
                )
                .take(requiredWordCount - newOptions.length)
                .toList();
            newOptions.addAll(fallbackOptions);
            debugPrint(
              '[TapInterface] Added ${fallbackOptions.length} fallback options, total now: ${newOptions.length}',
            );
          }
        } else {
          debugPrint(
            '[TapInterface] API returned no options, using fallback words',
          );
          newOptions = _getFallbackWordOptions()
              .take(requiredWordCount)
              .toList();
        }

        newOptions = await _localizeWordsForUserIfNeeded(newOptions);

        if (!mounted || _selectedCategory?.id != snapshotCategoryId) return;
        // Cache filtered AI words so Go Back and re-visits skip this API call.
        final locale =
            Provider.of<UserSettingsProvider>(
              context,
              listen: false,
            ).settings?.userLanguage ??
            'en-US';
        _categoryAIWordCache['${snapshotCategoryId}|$locale'] = newOptions;
        setState(() {
          _wordOptions = newOptions;
          _isLoadingWordOptions = false;
          _globalSessionLoggedMissingImages.clear();
        });
        // If a variant mode was active when dynamic words loaded, process the
        // new words now (they weren't in _wordOptions when the user pressed the
        // toggle, so they were never resolved).
        if (_variantMode != null) {
          _applyVariantModeToCurrentBoard(_variantMode!);
        }
        debugPrint(
          '[TapInterface] Updated UI with ${_wordOptions.length} word options',
        );
        debugPrint(
          '[TapInterface] First 5 UI options: ${_wordOptions.take(5).toList()}',
        );
      }
    } catch (e) {
      debugPrint('[TapInterface] ERROR in word options refresh: $e');

      if (mounted && _selectedCategory?.id == snapshotCategoryId) {
        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        final localizedFallback = await _localizeWordsForUserIfNeeded(
          _getFallbackWordOptions().take(requiredWordCount).toList(),
        );
        setState(() {
          _wordOptions = localizedFallback;
          _isLoadingWordOptions = false;
        });
      }
    }
  }

  Future<void> _loadPhraseOptionsBasedOnBuildSpace() async {
    try {
      setState(() {
        _isLoadingPhraseOptions = true;
      });

      debugPrint('[TapInterface] === PHRASE OPTIONS REFRESH ===');
      debugPrint('[TapInterface] Build space text: "$_buildSpaceText"');
      debugPrint('[TapInterface] Current question: "$_currentQuestion"');
      debugPrint(
        '[TapInterface] Selected category: ${_selectedCategory?.label}',
      );
      debugPrint(
        '[TapInterface] Build space empty: ${_buildSpaceText.isEmpty}',
      );

      List<Map<String, String>> phraseOpts = [];
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';
      final requiredPhraseCount = _phraseSlotCount(userSettings.settings);

      String phraseContext = '';

      // Priority 1: Question mode (when user asks a question)
      if (_currentQuestion.isNotEmpty) {
        debugPrint('[TapInterface] Using QUESTION mode context');
        String categoryContext = _selectedCategory?.label ?? 'general';
        phraseContext =
            'answering the question: "$_currentQuestion" in the context of $categoryContext';
        if (_buildSpaceText.isNotEmpty) {
          phraseContext =
              '$phraseContext, following up after: "$_buildSpaceText"';
        }
        debugPrint('[TapInterface] Question context: "$phraseContext"');
      }
      // Priority 2: Category mode (when a category is selected)
      else if (_selectedCategory != null) {
        debugPrint('[TapInterface] Using CATEGORY mode context');
        if (_selectedCategory!.hasLLMQuery) {
          phraseContext = _selectedCategory!.llmPrompt!;
        } else {
          // Generate contextual prompt from category name
          switch (_selectedCategory!.label.toLowerCase()) {
            case 'food':
            case 'foods':
              phraseContext =
                  'phrases for ordering food, expressing food preferences, and talking about meals';
              break;
            case 'activities':
            case 'activity':
              phraseContext =
                  'phrases for suggesting activities, talking about hobbies, and expressing interests';
              break;
            case 'people':
              phraseContext =
                  'phrases for talking about family, friends, and people in your life';
              break;
            case 'places':
              phraseContext =
                  'phrases for talking about locations, directions, and where you want to go';
              break;
            case 'actions':
              phraseContext =
                  'phrases for expressing actions, things you want to do, and movement';
              break;
            case 'needs':
            case 'wants':
              phraseContext =
                  'phrases for expressing needs, wants, and requests for help';
              break;
            case 'positive':
              phraseContext =
                  'positive adjectives and phrases for expressing approval, compliments, and good feelings';
              break;
            default:
              phraseContext =
                  'conversation phrases and expressions related to ${_selectedCategory!.label.toLowerCase()}';
          }
        }

        // Add build space context if present
        if (_buildSpaceText.isNotEmpty) {
          phraseContext =
              '$phraseContext, following up after saying: "$_buildSpaceText"';
        }
      }
      // Priority 3: Initial/General mode (no category, no question)
      else {
        debugPrint('[TapInterface] Using GENERAL/INITIAL mode context');
        if (_buildSpaceText.isNotEmpty) {
          phraseContext =
              'general conversation phrases and follow-ups after saying: "$_buildSpaceText"';
        } else {
          phraseContext = 'general conversation starters and common phrases';
        }
      }

      // Add mood context to all modes
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        phraseContext =
            '$phraseContext appropriate for someone feeling $currentMood';
      }

      debugPrint(
        '[TapInterface] Final phrase refresh context: "$phraseContext"',
      );

      // Only refresh if we have a context
      if (phraseContext.isNotEmpty) {
        final phraseOptions = await _tapService.generateLLMPhraseOptions(
          context: phraseContext,
          maxOptions:
              requiredPhraseCount +
              10, // Request extra to ensure we have enough
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint(
          '[TapInterface] Phrase refresh API returned ${phraseOptions.length} options',
        );

        phraseOpts = phraseOptions.take(requiredPhraseCount).toList();

        // Supplement with fallbacks if needed
        if (phraseOpts.length < requiredPhraseCount) {
          debugPrint(
            '[TapInterface] Only have ${phraseOpts.length} phrase options, need $requiredPhraseCount. Adding fallbacks...',
          );
          final currentTexts = phraseOpts
              .map((p) => p['fullText'] ?? '')
              .toSet();

          // Choose fallback source based on mode
          List<String> fallbackOptions;
          if (_selectedCategory != null) {
            fallbackOptions = _getFallbackOptionsForCategory(
              _selectedCategory!.label,
              isWords: false,
            );
          } else {
            fallbackOptions = _getFallbackPhraseOptions();
          }

          final additionalOptions = fallbackOptions
              .where((text) => !currentTexts.contains(text))
              .take(requiredPhraseCount - phraseOpts.length)
              .map(
                (text) => {
                  'summary': text.length > 30
                      ? '${text.substring(0, 30)}...'
                      : text,
                  'fullText': text,
                },
              )
              .toList();
          phraseOpts.addAll(additionalOptions);
          debugPrint(
            '[TapInterface] Added ${additionalOptions.length} fallback phrase options, total now: ${phraseOpts.length}',
          );
        }
      } else {
        debugPrint(
          '[TapInterface] No phrase context available, skipping refresh',
        );
      }

      debugPrint(
        '[TapInterface] First 5 phrase options: ${phraseOpts.take(5).map((p) => p['fullText']).toList()}',
      );

      if (mounted) {
        setState(() {
          if (phraseOpts.isNotEmpty) {
            _phraseOptions = phraseOpts;
          }
          _isLoadingPhraseOptions = false;

          // Clear session-tracked missing images when loading fresh phrases
          _globalSessionLoggedMissingImages.clear();
          debugPrint(
            '📋 Cleared session-tracked missing images for refreshed phrase options',
          );
        });
        if (phraseOpts.isNotEmpty) {
          _preloadImagesForOptions(phrases: phraseOpts);
        }
        debugPrint(
          '[TapInterface] Updated UI with ${_phraseOptions.length} phrase options',
        );
        debugPrint(
          '[TapInterface] First 5 UI phrase options: ${_phraseOptions.take(5).map((p) => p['fullText']).toList()}',
        );
      }
    } catch (e) {
      debugPrint('[TapInterface] ERROR in phrase options refresh: $e');

      if (mounted) {
        setState(() {
          _isLoadingPhraseOptions = false;
        });
      }
    }
  }

  // --- Jokes Loading ---

  Future<void> _loadJokeOptions() async {
    setState(() {
      _isLoadingPhraseOptions = true;
      _isLoadingWordOptions = false;
      _isJokesMode = true;
      _showStatusToast('Loading jokes...');
      _wordOptions = []; // No word options for jokes
      _phraseOptions = [];
      // Create a synthetic category for jokes display
      _selectedCategory = TapInterfaceCategory(id: 'jokes', label: 'Jokes');
    });

    try {
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final jokeCount = _phraseSlotCount(userSettings.settings);
      final userId = userSettings.userId ?? widget.aacUserId;

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/jokes/contextual?limit=$jokeCount',
        baseHeaders: {'X-User-ID': userId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> jokes = data['jokes'] ?? [];
        debugPrint('[TapInterface] Jokes response: ${jokes.length} jokes');

        // Helper to add [PAUSE] to joke text
        String addPauseToJokeText(String text) {
          if (text.isEmpty) return '';
          if (text.contains('[PAUSE]')) return text;
          final questionIndex = text.indexOf('?');
          if (questionIndex != -1 && questionIndex < text.length - 1) {
            return '${text.substring(0, questionIndex + 1)} [PAUSE] ${text.substring(questionIndex + 1).trim()}';
          }
          if (text.contains(' - '))
            return text.replaceFirst(' - ', ' [PAUSE] ');
          if (text.contains(' — '))
            return text.replaceFirst(' — ', ' [PAUSE] ');
          if (text.contains(': ')) return text.replaceFirst(': ', ': [PAUSE] ');
          return text;
        }

        final jokePhrases = jokes
            .map<Map<String, String>>((joke) {
              final jokeText = (joke['text'] ?? '').toString().trim();
              final summary = (joke['summary'] ?? 'Joke').toString().trim();
              final tags = joke['tags'];
              String keywords = '';
              if (tags != null) {
                if (tags is List) {
                  keywords = tags.join('|');
                } else {
                  keywords = tags.toString();
                }
              } else {
                keywords = 'joke|humor';
              }
              return {
                'summary': summary.isNotEmpty ? summary : 'Joke',
                'fullText': addPauseToJokeText(jokeText),
                'keywords': keywords,
              };
            })
            .where((p) => p['fullText']!.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _phraseOptions = jokePhrases;
            _isLoadingPhraseOptions = false;
          });
          _showStatusToast('Loaded ${jokePhrases.length} jokes');
        }
      } else {
        debugPrint('[TapInterface] Jokes error: ${response.statusCode}');
        if (mounted) {
          setState(() => _isLoadingPhraseOptions = false);
          _showStatusToast('Error loading jokes: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('[TapInterface] Jokes exception: $e');
      if (mounted) {
        setState(() => _isLoadingPhraseOptions = false);
        _showStatusToast('Error loading jokes: $e');
      }
    }
  }

  // --- Something Else Methods ---

  Future<void> _loadMorePhraseOptions() async {
    if (_isLoadingPhraseOptions) return;

    // If in jokes mode, re-fetch jokes instead of LLM query
    if (_isJokesMode) {
      await _loadJokeOptions();
      return;
    }

    setState(() {
      _isLoadingPhraseOptions = true;
      _showStatusToast('Loading different phrase options...');
    });

    try {
      List<Map<String, String>> newPhraseOptions = [];

      debugPrint(
        'TapInterface: _loadMorePhraseOptions - current question: "$_currentQuestion"',
      );
      debugPrint(
        'TapInterface: _loadMorePhraseOptions - selected category: ${_selectedCategory?.label}',
      );
      debugPrint(
        'TapInterface: _loadMorePhraseOptions - has LLM query: ${_selectedCategory?.hasLLMQuery}',
      );
      debugPrint(
        'TapInterface: _loadMorePhraseOptions - current phrase count: ${_phraseOptions.length}',
      );

      // Get current phrase texts to exclude
      final currentPhraseTexts = _phraseOptions
          .map((p) => p['fullText'] ?? '')
          .toList();
      debugPrint(
        'TapInterface: _loadMorePhraseOptions - excluding texts: $currentPhraseTexts',
      );

      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';

      String phraseContext;

      // Check if we're answering a voice question
      if (_currentQuestion.isNotEmpty) {
        // Use the question context (like initial question handling)
        String categoryContext = _selectedCategory?.label ?? 'general';
        phraseContext =
            'answering the question: "$_currentQuestion" in the context of $categoryContext';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          phraseContext =
              'answering the question: "$_currentQuestion" in the context of $categoryContext while feeling $currentMood';
        }
        debugPrint('TapInterface: Using question context: $phraseContext');
      } else if (_selectedCategory != null && _selectedCategory!.hasLLMQuery) {
        // Use category context (original behavior)
        phraseContext = _selectedCategory!.llmPrompt ?? '';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          phraseContext =
              '${_selectedCategory!.llmPrompt ?? ''} appropriate for someone feeling $currentMood';
        }
        debugPrint('TapInterface: Using category context: $phraseContext');
      } else {
        phraseContext = '';
      }

      if (phraseContext.isNotEmpty) {
        final phraseOpts = await _tapService.generateLLMPhraseOptions(
          context: phraseContext,
          maxOptions: 25, // Request extra options to ensure we have enough
          requestDifferentOptions: true,
          excludeOptions: currentPhraseTexts,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        newPhraseOptions = phraseOpts
            .take(17)
            .toList(); // Use only 17 for display
        debugPrint(
          'TapInterface: LLM returned ${phraseOpts.length} options, using ${newPhraseOptions.length} for display',
        );

        // If we still don't have enough options, supplement with fallback
        if (newPhraseOptions.length < 17 && _selectedCategory != null) {
          debugPrint(
            'TapInterface: Need ${17 - newPhraseOptions.length} more phrase options, adding fallbacks',
          );
          final currentTexts = newPhraseOptions
              .map((p) => p['fullText'] ?? '')
              .toSet();
          final fallbackOptions = _getFallbackOptionsForCategory(
            _selectedCategory!.label,
            isWords: false,
          );
          final additionalOptions = fallbackOptions
              .where((text) => !currentTexts.contains(text))
              .take(17 - newPhraseOptions.length)
              .map(
                (text) => {
                  'summary': text.length > 30
                      ? '${text.substring(0, 30)}...'
                      : text,
                  'fullText': text,
                },
              )
              .toList();
          newPhraseOptions.addAll(additionalOptions);
          debugPrint(
            'TapInterface: Added ${additionalOptions.length} fallback options, total now: ${newPhraseOptions.length}',
          );
        }
      }

      // If no new options or fallback needed
      if (newPhraseOptions.isEmpty && _selectedCategory != null) {
        debugPrint('TapInterface: No LLM options returned, trying fallbacks');
        if (_selectedCategory!.hasStaticOptions) {
          // Use different static options (skip already shown ones)
          final currentTexts = _phraseOptions
              .map((p) => p['fullText'] ?? '')
              .toSet();
          final availableOptions = _selectedCategory!.staticOptionsList
              .where((text) => !currentTexts.contains(text))
              .toList();

          newPhraseOptions = availableOptions
              .take(17)
              .map(
                (text) => {
                  'summary': text.length > 30
                      ? '${text.substring(0, 30)}...'
                      : text,
                  'fullText': text,
                },
              )
              .toList();
          debugPrint(
            'TapInterface: Using ${newPhraseOptions.length} different static options',
          );
        } else {
          // Use different fallback options
          final currentTexts = _phraseOptions
              .map((p) => p['fullText'] ?? '')
              .toSet();
          final fallbackOptions = _getFallbackOptionsForCategory(
            _selectedCategory!.label,
            isWords: false,
          );
          final availableOptions = fallbackOptions
              .where((text) => !currentTexts.contains(text))
              .toList();

          newPhraseOptions = availableOptions
              .take(17)
              .map(
                (text) => {
                  'summary': text.length > 30
                      ? '${text.substring(0, 30)}...'
                      : text,
                  'fullText': text,
                },
              )
              .toList();
          debugPrint(
            'TapInterface: Using ${newPhraseOptions.length} different fallback options',
          );
        }
      } else if (newPhraseOptions.isEmpty) {
        debugPrint(
          'TapInterface: No category selected or no options available at all',
        );
      }

      // COMPREHENSIVE FALLBACK: If we still have no options, generate some basic ones
      if (newPhraseOptions.isEmpty) {
        debugPrint(
          'TapInterface: Using comprehensive fallback - generating basic phrase options',
        );
        final currentTexts = _phraseOptions
            .map((p) => p['fullText'] ?? '')
            .toSet();

        // Create a large pool of basic conversational phrases
        final basicPhrases = [
          'Hello there',
          'How are you?',
          'I am fine',
          'Thank you very much',
          'Please help me',
          'Yes, that sounds good',
          'No, I don\'t think so',
          'I would like that',
          'Can you help?',
          'I am hungry',
          'I want to go',
          'I need to rest',
          'That was great',
          'I feel good',
          'See you later',
          'Good morning',
          'Good afternoon',
          'Good evening',
          'Have a nice day',
          'I am tired',
          'I am happy',
          'I am sad',
          'I am excited',
          'Let me think',
          'That\'s interesting',
          'I understand',
          'I don\'t understand',
          'Can you repeat?',
          'Excuse me',
          'I\'m sorry',
          'No problem',
          'You\'re welcome',
          'Nice to meet you',
          'Take care',
          'I love you',
          'I miss you',
          'How was your day?',
          'What are you doing?',
          'Where are you going?',
          'I want to eat',
          'I want to drink',
          'I want to sleep',
          'I want to play',
          'I want to work',
          'I am done',
          'I am finished',
          'I am ready',
          'Wait for me',
          'I am coming',
        ];

        // Filter out already shown options
        final availableBasicPhrases = basicPhrases
            .where((text) => !currentTexts.contains(text))
            .toList();

        // Take up to 17 different options
        newPhraseOptions = availableBasicPhrases
            .take(17)
            .map(
              (text) => {
                'summary': text.length > 30
                    ? '${text.substring(0, 30)}...'
                    : text,
                'fullText': text,
              },
            )
            .toList();

        debugPrint(
          'TapInterface: Comprehensive fallback provided ${newPhraseOptions.length} basic phrase options',
        );
      }

      setState(() {
        _phraseOptions = newPhraseOptions;
        _isLoadingPhraseOptions = false;
      });
      _showStatusToast(newPhraseOptions.isNotEmpty
          ? 'Loaded ${newPhraseOptions.length} different phrase options'
          : 'No more phrase options available');
    } catch (e) {
      debugPrint('TapInterface: Error loading different phrase options: $e');
      setState(() => _isLoadingPhraseOptions = false);
      _showStatusToast('Error loading different phrase options');
    }
  }

  List<String> _getTapInterfaceLetterOrder() {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;
    final letterOrder = settings?.spellLetterOrder ?? 'alphabetical';

    if (letterOrder == 'qwerty') {
      return [
        'Q',
        'W',
        'E',
        'R',
        'T',
        'Y',
        'U',
        'I',
        'O',
        'P',
        'A',
        'S',
        'D',
        'F',
        'G',
        'H',
        'J',
        'K',
        'L',
        'Z',
        'X',
        'C',
        'V',
        'B',
        'N',
        'M',
      ];
    }

    if (letterOrder == 'frequency') {
      return 'ETAOINSHRDLUCMFWGYPBVKXJZQ'.split('');
    }

    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
  }

  Future<void> _showSomethingElseAZDialog() async {
    if (_selectedCategory == null) {
      setState(() {
        _showStatusToast('Select a category first to use Something Else A-Z.');
      });
      return;
    }

    if (!(_selectedCategory?.hasLLMQuery ?? false)) {
      setState(() {
        _statusMessage =
            'Something Else A-Z is available only for AI-generated boards.';
      });
      return;
    }

    final letters = _getTapInterfaceLetterOrder();
    final selectedLetter = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(dialogContext).size.width * 0.9,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose a Letter',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const columns = 5;
                      const spacing = 6.0;
                      final tileSize =
                          ((constraints.maxWidth - ((columns - 1) * spacing)) /
                                  columns)
                              .clamp(58.0, 82.0)
                              .toDouble();

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: letters
                            .map(
                              (letter) => SizedBox(
                                width: tileSize,
                                height: tileSize,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(letter),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.blue[50] ?? Colors.blue.shade50,
                                    foregroundColor: Colors.black87,
                                    side: BorderSide(
                                      color:
                                          Colors.blue[300] ??
                                          Colors.blue.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size(tileSize, tileSize),
                                  ),
                                  child: Text(
                                    letter,
                                    style: TextStyle(
                                      fontSize: (tileSize * 0.42).clamp(
                                        22.0,
                                        32.0,
                                      ),
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedLetter == null || selectedLetter.isEmpty) {
      return;
    }

    setState(() {
      _activeWordLetterFilter = selectedLetter.toLowerCase();
    });

    await _loadMoreWordOptions(startsWithLetter: selectedLetter);
  }

  Future<void> _loadMoreWordOptions({String? startsWithLetter}) async {
    if (_isLoadingWordOptions) return;

    // Get user settings at the beginning of the function
    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );

    final normalizedLetter = startsWithLetter?.trim().toLowerCase();
    final isLetterMode =
        normalizedLetter != null && normalizedLetter.isNotEmpty;
    if (isLetterMode && _selectedCategory == null) {
      setState(() {
        _showStatusToast('Select a category first to filter by letter.');
      });
      return;
    }

    if (isLetterMode && !(_selectedCategory?.hasLLMQuery ?? false)) {
      setState(() {
        _statusMessage =
            'Something Else A-Z is available only for AI-generated boards.';
      });
      return;
    }

    setState(() => _isLoadingWordOptions = true);
    if (isLetterMode) {
      _showStatusToast('Loading words starting with "${normalizedLetter.toUpperCase()}"...');
    }

    try {
      List<String> newWordOptions = [];

      debugPrint('TapInterface: === SOMETHING ELSE DEBUG ===');
      debugPrint(
        'TapInterface: _loadMoreWordOptions - current question: "$_currentQuestion"',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - selected category: ${_selectedCategory?.label}',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - build space text: "$_buildSpaceText"',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - speech history: "$_speechHistory"',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - current word count: ${_wordOptions.length}',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - current words to exclude: $_wordOptions',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - _selectedCategory != null: ${_selectedCategory != null}',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - _buildSpaceText.isEmpty: ${_buildSpaceText.isEmpty}',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - _currentQuestion.isNotEmpty: ${_currentQuestion.isNotEmpty}',
      );
      debugPrint(
        'TapInterface: _loadMoreWordOptions - startsWithLetter: $startsWithLetter',
      );

      final currentMood =
          userSettings.settings?.currentMood ?? 'No Mood Selected';
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;

      // Question mode only takes priority when not letter-filtering by category.
      if (!isLetterMode && _currentQuestion.isNotEmpty) {
        // Use generateCategoryWords with extracted category (same as initial question handling)
        debugPrint(
          '[TapInterface] Using generateCategoryWords API with QUESTION-derived category',
        );

        String categoryForWords = _extractCategoryFromQuestion(
          _currentQuestion,
        );
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          categoryForWords =
              '$categoryForWords appropriate for someone feeling $currentMood';
        }

        debugPrint(
          '[TapInterface] Category extracted from question: $categoryForWords',
        );

        // Request 2x to account for duplicates with current options
        final wordOptionsStrings = await _tapService.generateCategoryWords(
          category: categoryForWords,
          buildSpaceContent: _buildSpaceText,
          excludeWords: {..._usedWordOptions, ..._wordOptions.map((w) => w.toLowerCase())}.toList(),
          maxOptions:
              requiredWordCount *
              2, // Request double to ensure we have enough after filtering
          requestDifferentOptions: true,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );

        // Deduplicate and exclude all previously shown options
        final deduplicatedWords = _deduplicateWords(wordOptionsStrings);
        final currentWordsLower = {..._usedWordOptions, ..._wordOptions.map((w) => w.toLowerCase())}
            .toSet();
        newWordOptions = deduplicatedWords
            .where((word) => !currentWordsLower.contains(word.toLowerCase()))
            .take(requiredWordCount) // Take exactly the required count
            .toList();

        debugPrint(
          '[TapInterface] Question-based API returned ${wordOptionsStrings.length} words, ${newWordOptions.length} after dedup/filter/limit',
        );
      } else if (_selectedCategory != null) {
        // Use category-words API with request_different_options = true.
        // The category always takes priority regardless of whether the user has
        // already placed words in the build space; buildSpaceContent is forwarded
        // as additional context so the results stay sentence-coherent.
        debugPrint(
          '[TapInterface] Using Category Words API for different words',
        );

        final currentMood =
            userSettings.settings?.currentMood ?? 'No Mood Selected';
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        final selectedCategory = _selectedCategory;
        final letterInstruction = isLetterMode
            ? ' Generate many single-word options that start with letter "${normalizedLetter.toUpperCase()}". Return only words that begin with that letter.'
            : '';
        String categoryLabel;
        if (selectedCategory != null &&
            _shouldUseDefaultHomeStarterWords(selectedCategory)) {
          // Home board with no explicit word options — use the built-in AAC starter prompt.
          categoryLabel =
              _getDefaultHomeStarterPrompt(requiredWordCount + 10) +
              letterInstruction;
        } else if (selectedCategory?.llmPrompt != null &&
            selectedCategory!.llmPrompt!.isNotEmpty) {
          // Board has a configured LLM prompt — use it verbatim (same as initial load)
          // so we don't fall back to the category label and get off-topic words.
          categoryLabel = selectedCategory.llmPrompt!;
          if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
            categoryLabel =
                '$categoryLabel appropriate for someone feeling $currentMood';
          }
          categoryLabel = '$categoryLabel$letterInstruction';
        } else {
          categoryLabel = selectedCategory?.label ?? '';
          if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
            categoryLabel =
                '${selectedCategory?.label ?? ''} appropriate for someone feeling $currentMood';
          }
          categoryLabel = '$categoryLabel$letterInstruction';
        }

        final int requestedOptionsCount = isLetterMode
            ? (requiredWordCount * 6).clamp(60, 220)
            : requiredWordCount + 10;

        final rawWordOptions = await _tapService.generateCategoryWords(
          category: categoryLabel,
          buildSpaceContent: _buildSpaceText,
          excludeWords: {..._usedWordOptions, ..._wordOptions.map((w) => w.toLowerCase())}.toList(),
          maxOptions:
              requestedOptionsCount, // Request larger batches for letter filtering
          requestDifferentOptions: true, // Request different options
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint(
          '[TapInterface] Category Words API returned ${rawWordOptions.length} raw words',
        );

        // Validate words for category appropriateness
        newWordOptions = _validateWordsForCategory(
          rawWordOptions,
          _selectedCategory?.label ?? '',
        );
        debugPrint(
          '[TapInterface] After validation: ${newWordOptions.length}/${rawWordOptions.length} words are appropriate',
        );
        debugPrint(
          '[TapInterface] NEW Category words: ${newWordOptions.take(10).toList()}...',
        );
        debugPrint(
          '[TapInterface] OLD UI words: ${_wordOptions.take(10).toList()}...',
        );

        // Check for overlap to debug the issue
        final overlap = newWordOptions
            .where((word) => _wordOptions.contains(word))
            .toList();
        debugPrint(
          '[TapInterface] Category word overlap count: ${overlap.length} out of ${newWordOptions.length}',
        );
        if (overlap.isNotEmpty) {
          debugPrint(
            '[TapInterface] Overlapping category words: ${overlap.take(5).toList()}...',
          );
        }
      } else {
        // Use freestyle word-options API with request_different_options = true
        String context;

        if (_selectedCategory != null) {
          context = _selectedCategory?.label ?? '';
          debugPrint(
            '[TapInterface] Using Freestyle API with CATEGORY context for different options: "$context"',
          );
        } else if (_buildSpaceText.isNotEmpty) {
          context = _buildSpaceText;
          debugPrint(
            '[TapInterface] Using Freestyle API with BUILD SPACE context for different options: "$context"',
          );
        } else {
          // When no category is selected, provide a more specific context to help generate good initial options
          context =
              'communication essentials and common words for everyday conversation';
          debugPrint(
            '[TapInterface] Using Freestyle API with ENHANCED GENERAL context for different options: "$context"',
          );
        }

        final List<String> exclusions = {..._usedWordOptions, ..._wordOptions.map((w) => w.toLowerCase())}.toList();
        debugPrint(
          '[TapInterface] Excluding ${exclusions.length} current words: ${exclusions.take(5).toList()}${exclusions.length > 5 ? '...' : ''}',
        );

        final currentMood =
            userSettings.settings?.currentMood ?? 'No Mood Selected';

        String contextWithMood = context;
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          contextWithMood =
              '$context appropriate for someone feeling $currentMood';
        }

        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;

        newWordOptions = await _tapService.generateFreestyleOptions(
          context: contextWithMood,
          buildSpaceText: _buildSpaceText,
          singleWordsOnly: true,
          maxOptions:
              requiredWordCount +
              10, // Request extra options to ensure we have enough
          requestDifferentOptions: true, // Request different options
          excludeOptions:
              exclusions, // Only exclude if we have something to exclude
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint(
          '[TapInterface] Freestyle API returned ${newWordOptions.length} different word options, will use up to $requiredWordCount',
        );
        debugPrint(
          '[TapInterface] NEW API words: ${newWordOptions.take(10).toList()}...',
        );
        debugPrint(
          '[TapInterface] OLD UI words: ${_wordOptions.take(10).toList()}...',
        );

        // Check for overlap to debug the issue
        final overlap = newWordOptions
            .where((word) => _wordOptions.contains(word))
            .toList();
        debugPrint(
          '[TapInterface] Word overlap count: ${overlap.length} out of ${newWordOptions.length}',
        );
        if (overlap.isNotEmpty) {
          debugPrint(
            '[TapInterface] Overlapping words: ${overlap.take(5).toList()}...',
          );
        }
      }

      if (isLetterMode) {
        final existingWordsLower = _wordOptions
            .map((w) => w.toLowerCase())
            .toSet();
        final beforeCount = newWordOptions.length;
        newWordOptions = _deduplicateWords(newWordOptions).where((word) {
          final lower = word.toLowerCase();
          return lower.startsWith(normalizedLetter) &&
              !existingWordsLower.contains(lower);
        }).toList();

        debugPrint(
          '[TapInterface] Letter filter "$normalizedLetter" kept ${newWordOptions.length}/$beforeCount options after excluding currently displayed words',
        );

        if (newWordOptions.length < requiredWordCount &&
            _selectedCategory != null) {
          debugPrint(
            '[TapInterface] Letter mode returned too few options; requesting additional category words for letter ${normalizedLetter.toUpperCase()}',
          );

          final Set<String> expandedExclusions = {
            ..._wordOptions,
            ...newWordOptions,
          };
          final extraPrompt =
              '${_selectedCategory!.label}. Provide a large variety of single words that start with letter "${normalizedLetter.toUpperCase()}" only.';

          final extraResults = await _tapService.generateCategoryWords(
            category: extraPrompt,
            buildSpaceContent: _buildSpaceText,
            excludeWords: expandedExclusions.toList(),
            maxOptions: (requiredWordCount * 8).clamp(80, 280),
            requestDifferentOptions: true,
            currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
          );

          final mergedResults = _deduplicateWords([
            ...newWordOptions,
            ...extraResults,
          ]);

          newWordOptions = mergedResults
              .where((word) => word.toLowerCase().startsWith(normalizedLetter))
              .where((word) => !existingWordsLower.contains(word.toLowerCase()))
              .take(requiredWordCount)
              .toList();

          debugPrint(
            '[TapInterface] After second letter-mode request: ${newWordOptions.length} options',
          );

          // If still low, keep requesting additional letter-constrained batches
          // with expanding exclusions to avoid duplicates.
          int additionalAttempts = 0;
          while (newWordOptions.length < requiredWordCount &&
              additionalAttempts < 3) {
            additionalAttempts += 1;
            final rollingExclusions = <String>{
              ..._wordOptions,
              ...newWordOptions,
            };

            final iterativePrompt =
                '${_selectedCategory!.label}. Attempt $additionalAttempts. Generate ONLY single words that start with "${normalizedLetter.toUpperCase()}". Return many different options not previously shown.';

            final iterativeBatch = await _tapService.generateCategoryWords(
              category: iterativePrompt,
              buildSpaceContent: _buildSpaceText,
              excludeWords: rollingExclusions.toList(),
              maxOptions: (requiredWordCount * 10).clamp(100, 320),
              requestDifferentOptions: true,
              currentMood: currentMood != 'No Mood Selected'
                  ? currentMood
                  : null,
            );

            final mergedIterative = _deduplicateWords([
              ...newWordOptions,
              ...iterativeBatch,
            ]);

            newWordOptions = mergedIterative
                .where(
                  (word) => word.toLowerCase().startsWith(normalizedLetter),
                )
                .where(
                  (word) => !existingWordsLower.contains(word.toLowerCase()),
                )
                .take(requiredWordCount)
                .toList();

            debugPrint(
              '[TapInterface] After iterative letter-mode request #$additionalAttempts: ${newWordOptions.length} options',
            );
          }
        }
      }

      // If no new options, try fallback with exclusion
      if (newWordOptions.isEmpty) {
        debugPrint(
          '[TapInterface] No API options returned, trying fallback exclusion logic',
        );
        final fallbackOptions = (_selectedCategory != null)
            ? _getFallbackOptionsForCategory(
                _selectedCategory!.label,
                isWords: true,
              )
            : _getFallbackWordOptions();
        final currentWordsSet = _wordOptions.toSet();
        debugPrint(
          '[TapInterface] Fallback options available: ${fallbackOptions.length}',
        );
        debugPrint(
          '[TapInterface] Current words to exclude: ${currentWordsSet.length} words',
        );

        final filteredOptions = fallbackOptions
            .where((word) => !currentWordsSet.contains(word))
            .where(
              (word) =>
                  !isLetterMode ||
                  word.toLowerCase().startsWith(normalizedLetter),
            )
            .toList();
        debugPrint(
          '[TapInterface] After exclusion: ${filteredOptions.length} words available',
        );

        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        newWordOptions = filteredOptions.take(requiredWordCount).toList();
        debugPrint(
          '[TapInterface] Final fallback selection: ${newWordOptions.length} words',
        );
        debugPrint(
          '[TapInterface] First 5 fallback words: ${newWordOptions.take(5).toList()}',
        );
      }

      // Deduplicate words to avoid case-sensitive duplicates like "Want"/"want"
      newWordOptions = _deduplicateWords(newWordOptions);
      debugPrint(
        '[TapInterface] After deduplication: ${newWordOptions.length} unique words',
      );

      // Only pad with fallbacks if NOT answering a question
      // For questions, we only want relevant answers, not generic words
      if (_currentQuestion.isEmpty &&
          newWordOptions.length < requiredWordCount) {
        debugPrint(
          '[TapInterface] Only have ${newWordOptions.length} options, need $requiredWordCount. Adding more fallbacks...',
        );
        final currentWordsLower = newWordOptions
            .map((w) => w.toLowerCase())
            .toSet();
        final allFallbackOptions = isLetterMode
            ? [
                ...(_selectedCategory != null
                    ? _getFallbackOptionsForCategory(
                        _selectedCategory!.label,
                        isWords: true,
                      )
                    : const <String>[]),
                ..._getFallbackWordOptions(),
              ]
            : (_selectedCategory != null
                  ? _getFallbackOptionsForCategory(
                      _selectedCategory!.label,
                      isWords: true,
                    )
                  : _getFallbackWordOptions());
        final additionalOptions = allFallbackOptions
            .where((word) => !currentWordsLower.contains(word.toLowerCase()))
            .where(
              (word) =>
                  !isLetterMode ||
                  word.toLowerCase().startsWith(normalizedLetter),
            )
            .take(requiredWordCount - newWordOptions.length)
            .toList();
        newWordOptions.addAll(additionalOptions);
        debugPrint(
          '[TapInterface] Added ${additionalOptions.length} additional fallback options, total now: ${newWordOptions.length}',
        );
      } else if (_currentQuestion.isNotEmpty &&
          newWordOptions.length < requiredWordCount) {
        debugPrint(
          '[TapInterface] Question mode: Only have ${newWordOptions.length} relevant answers (not padding with generic words)',
        );
      }

      // Trim to exactly the required count if we have too many
      if (newWordOptions.length > requiredWordCount) {
        newWordOptions = newWordOptions.take(requiredWordCount).toList();
        debugPrint(
          '[TapInterface] Trimmed to exactly $requiredWordCount options',
        );
      }

      final sourceNewWordOptions = List<String>.from(newWordOptions);
      newWordOptions = await _localizeWordsForUserIfNeeded(newWordOptions);
      final localizedNewWordKeywords = _buildLocalizedKeywordFallbackMap(
        sourceNewWordOptions,
        newWordOptions,
      );

      setState(() {
        debugPrint(
          '[TapInterface] BEFORE setState - current _wordOptions: ${_wordOptions.take(5).toList()}...',
        );
        debugPrint(
          '[TapInterface] BEFORE setState - newWordOptions: ${newWordOptions.take(5).toList()}...',
        );

        final oldWordOptions = List<String>.from(
          _wordOptions,
        ); // Save old options for comparison

        // Accumulate old words so subsequent Something Else calls never repeat them.
        _usedWordOptions.addAll(_wordOptions.map((w) => w.toLowerCase()));

        // Assign new list references directly — do NOT call .clear() on the
        // old list because _categoryWordCache may share the same list object,
        // and mutating it would silently corrupt the cache.
        _wordOptions = List<String>.from(
          newWordOptions.take(requiredWordCount),
        );
        _wordKeywords = localizedNewWordKeywords;

        // CRITICAL DEBUG: Check for duplicates in final word options
        final finalWordsLower = <String>{};
        final finalDuplicates = <String>[];
        for (final word in _wordOptions) {
          final lowerWord = word.toLowerCase();
          if (finalWordsLower.contains(lowerWord)) {
            finalDuplicates.add(word);
          } else {
            finalWordsLower.add(lowerWord);
          }
        }

        if (finalDuplicates.isNotEmpty) {
          debugPrint(
            '🚨 CRITICAL: Found duplicates in FINAL _wordOptions: $finalDuplicates',
          );
          debugPrint('🚨 CRITICAL: Full _wordOptions list: $_wordOptions');
        } else {
          debugPrint('✅ GOOD: No duplicates found in final _wordOptions');
        }

        debugPrint(
          '[TapInterface] AFTER setState - updated _wordOptions: ${_wordOptions.take(5).toList()}...',
        );
        debugPrint('[TapInterface] setState comparison: OLD vs NEW');
        debugPrint(
          '[TapInterface]   OLD first 5: ${oldWordOptions.take(5).toList()}',
        );
        debugPrint(
          '[TapInterface]   NEW first 5: ${_wordOptions.take(5).toList()}',
        );

        final areIdentical =
            List.from(oldWordOptions.take(10)) ==
            List.from(_wordOptions.take(10));
        debugPrint(
          '[TapInterface] Are first 10 words identical? $areIdentical',
        );

        _isLoadingWordOptions = false;

        // IMPORTANT: Clear session-tracked missing images when loading fresh options
        // This allows us to re-log any missing images from the new word set
        _globalSessionLoggedMissingImages.clear();
        debugPrint(
          '📋 Cleared session-tracked missing images for fresh word options',
        );
      });
      if (!newWordOptions.isNotEmpty && isLetterMode) {
        _showStatusToast('No more category words starting with "${normalizedLetter.toUpperCase()}"');
      } else if (!newWordOptions.isNotEmpty) {
        _showStatusToast('No more word options available');
      } else if (isLetterMode) {
        _showStatusToast('Loaded ${newWordOptions.length} words starting with "${normalizedLetter.toUpperCase()}"');
      }
    } catch (e) {
      debugPrint('[TapInterface] ERROR loading different word options: $e');
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      final localizedFallback = await _localizeWordsForUserIfNeeded(
        (_getFallbackOptionsForCategory(
              _selectedCategory?.label ?? 'generic',
              isWords: true,
            )
            .where(
              (word) =>
                  !isLetterMode ||
                  word.toLowerCase().startsWith(normalizedLetter),
            )
            .take(requiredWordCount)
            .toList()),
      );
      setState(() {
        _wordOptions = localizedFallback;
        _isLoadingWordOptions = false;
      });
      _showStatusToast(isLetterMode
          ? 'Error loading words for "${normalizedLetter.toUpperCase()}"'
          : 'Error loading different word options');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: true,
    );
    final musicService = Provider.of<MusicPlaybackService>(
      context,
      listen: true,
    );
    final userSettings = settingsProvider.settings;

    // Keep sensitivity static in sync with loaded state on every build.
    TapInterfaceButton.tapMinDurationMs = _tapMinDurationMs;

    // Get user-selected colors
    final Color headerTextColor = userSettings != null
        ? Color(userSettings.lightColorValue)
        : Colors.blue;
    final Color backgroundColor = userSettings != null
        ? Color(userSettings.darkColorValue)
        : Colors.grey[100] ?? Colors.grey;

    if (_tapConfig == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // --- MAIN CONTENT AREA ---
          SafeArea(
            child: Column(
              children: [
                // --- TOP SECTION: Speech History (Build Space) ---
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        offset: const Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: Listener(
                    // Single pointer-down tracker for the whole action bar.
                    // _withSensitivity() reads this timestamp to enforce the
                    // minimum tap hold duration across all action bar buttons.
                    onPointerDown: (_) =>
                        _actionBarPointerDownTime = DateTime.now(),
                    child: Row(
                    children: [
                      // Home Button (Icon Only) - Returns to original page
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: 'Home',
                        child: Container(
                          height: 44,
                          width: 55,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blueGrey[300] ??
                                    Colors.blueGrey.shade300,
                                Colors.blueGrey[500] ??
                                    Colors.blueGrey.shade500,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueGrey.withOpacity(0.25),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(_resetPage),
                            icon: const Icon(
                              Icons.home,
                              size: 31,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Speech History Text Field (serves as build space)
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey[300] ?? Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: TextField(
                            controller: _speechHistoryController,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Build your message here...',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Speak Button (Icon Only) - Always speaks as-is
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: 'Speak',
                        child: Container(
                          height: 44,
                          width: 72,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green[400] ?? Colors.green.shade400,
                                Colors.green[600] ?? Colors.green.shade600,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(_handleSpeakButtonPress),
                            icon: const Icon(
                              Icons.volume_up,
                              size: 34,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Auto Clean + Speak Button (Icon Only) - Always uses LLM cleanup
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: 'Auto Clean + Speak',
                        child: Container(
                          height: 44,
                          width: 72,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.purple[400] ?? Colors.purple.shade400,
                                Colors.purple[600] ?? Colors.purple.shade600,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(_handleAutoCleanSpeakButtonPress),
                            icon: const Icon(
                              Icons.auto_fix_high,
                              size: 31,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Backspace Button (Icon Only)
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: 'Backspace',
                        child: Container(
                          height: 44,
                          width: 55,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber[600] ?? Colors.amber.shade600,
                                Colors.amber[800] ?? Colors.amber.shade800,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(_backspaceSpeechHistory),
                            icon: const Icon(
                              Icons.backspace,
                              size: 34,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Clear Text Button (Icon Only) - NEW
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: 'Clear Text',
                        child: Container(
                          height: 44,
                          width: 55,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.red[400] ?? Colors.red.shade400,
                                Colors.red[600] ?? Colors.red.shade600,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(_clearSpeechText),
                            icon: const Icon(
                              Icons.close,
                              size: 34,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Audio Surfing Toggle Button (Icon Only)
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: _isAudioSurfingEnabled
                            ? 'Audio Surfing: ON'
                            : 'Audio Surfing: OFF',
                        child: Container(
                          height: 44,
                          width: 55,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isAudioSurfingEnabled
                                  ? [
                                      Colors.teal[400] ?? Colors.teal.shade400,
                                      Colors.teal[600] ?? Colors.teal.shade600,
                                    ]
                                  : [
                                      Colors.grey[400] ?? Colors.grey.shade400,
                                      Colors.grey[600] ?? Colors.grey.shade600,
                                    ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_isAudioSurfingEnabled
                                            ? Colors.teal
                                            : Colors.grey)
                                        .withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(() {
                              setState(() {
                                _isAudioSurfingEnabled =
                                    !_isAudioSurfingEnabled;
                                _audioSurfingPreviewOptionKey = null;
                              });
                              _showStatusToast(_isAudioSurfingEnabled
                                  ? 'Audio Surfing enabled. Tap once to preview, tap again to select.'
                                  : 'Audio Surfing disabled.');
                            }),
                            icon: Icon(
                              _isAudioSurfingEnabled
                                  ? Icons.surround_sound
                                  : Icons.hearing,
                              size: 31,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // History Button (Icon Only)
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: 'History',
                        child: Container(
                          height: 44,
                          width: 55,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue[400] ?? Colors.blue.shade400,
                                Colors.blue[600] ?? Colors.blue.shade600,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _withSensitivity(_showSpeechHistoryDialog),
                            icon: const Icon(
                              Icons.menu_book,
                              size: 34,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Past Tense Toggle
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: _variantMode == 'past'
                            ? 'Past: ON (tap to disable)'
                            : 'Past Tense Mode',
                        child: GestureDetector(
                          onTapDown: (_) =>
                              _actionBarPointerDownTime = DateTime.now(),
                          onTap: _withSensitivity(() {
                            final newMode =
                                _variantMode == 'past' ? null : 'past';
                            setState(() => _variantMode = newMode);
                            if (newMode != null) {
                              _applyVariantModeToCurrentBoard(newMode);
                            }
                          }),
                          child: Container(
                            height: 44,
                            width: 55,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _variantMode == 'past'
                                    ? [
                                        const Color(0xFFea580c),
                                        const Color(0xFFc2410c),
                                      ]
                                    : [
                                        const Color(0xFFf97316),
                                        const Color(0xFFea580c),
                                      ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFea580c)
                                      .withValues(alpha: _variantMode == 'past' ? 0.5 : 0.25),
                                  offset: const Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '-d',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Plural Toggle
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: _variantMode == 'plural'
                            ? 'Plural: ON (tap to disable)'
                            : 'Plural Mode',
                        child: GestureDetector(
                          onTapDown: (_) =>
                              _actionBarPointerDownTime = DateTime.now(),
                          onTap: _withSensitivity(() {
                            final newMode =
                                _variantMode == 'plural' ? null : 'plural';
                            setState(() => _variantMode = newMode);
                            if (newMode != null) {
                              _applyVariantModeToCurrentBoard(newMode);
                            }
                          }),
                          child: Container(
                            height: 44,
                            width: 55,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _variantMode == 'plural'
                                    ? [
                                        const Color(0xFF2563eb),
                                        const Color(0xFF1d4ed8),
                                      ]
                                    : [
                                        const Color(0xFF3b82f6),
                                        const Color(0xFF2563eb),
                                      ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563eb)
                                      .withValues(alpha: _variantMode == 'plural' ? 0.5 : 0.25),
                                  offset: const Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '-S',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),

                // --- MAIN INTERFACE ---
                Expanded(
                  child: _buildMainInterface(userSettings, headerTextColor),
                ),
              ],
            ),
          ),

          // --- FLOATING STATUS TOAST ---
          if (_statusMessage.isNotEmpty)
            Positioned(
              bottom: 72,
              left: 16,
              right: 72,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey('toast_$_statusMessage'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: (_isListeningForQuestion
                              ? Colors.orange.shade700
                              : _isListeningForWakeWord
                              ? Colors.green.shade700
                              : Colors.blueGrey.shade700)
                          .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),

          // --- FLOATING ADMIN PANEL (when unlocked) ---
          if (!_isAdminToolbarLocked)
            Positioned(
              bottom: 72,
              right: 8,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.97),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.black87),
                        tooltip: 'Admin Settings',
                        onPressed: () => _onAdminButtonPressed('/admin-settings'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.touch_app, color: Colors.black87),
                        tooltip: 'Tap Interface Admin',
                        onPressed: () => _onAdminButtonPressed('/admin-tap-interface'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.location_on, color: Colors.black87),
                        tooltip: 'User Current Location',
                        onPressed: () => _onAdminButtonPressed('/admin-user-current'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline, color: Colors.black87),
                        tooltip: 'User Info',
                        onPressed: () => _onAdminButtonPressed('/admin-user-info'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.book, color: Colors.black87),
                        tooltip: 'User Diary',
                        onPressed: () => _onAdminButtonPressed('/admin-user-diary'),
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        color: Colors.grey[300],
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                      ),
                      IconButton(
                        icon: const Icon(Icons.account_circle, color: Colors.black87),
                        tooltip: 'Switch User Account',
                        onPressed: _switchUserAccount,
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.black87),
                        tooltip: 'Sign Out',
                        onPressed: _signOut,
                      ),
                      if (musicService.isPlaying) ...[
                        Container(
                          height: 28,
                          width: 1,
                          color: Colors.grey[300],
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle, color: Colors.red),
                          tooltip: 'Stop Playing Music',
                          onPressed: musicService.stopPlayback,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // --- FLOATING LOCK BUTTON ---
          Positioned(
            bottom: 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(24),
              color: _isAdminToolbarLocked
                  ? Colors.white.withValues(alpha: 0.85)
                  : Colors.orange.shade50,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _toggleAdminToolbarLock,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    _isAdminToolbarLocked ? Icons.lock : Icons.lock_open,
                    color: _isAdminToolbarLocked
                        ? Colors.black54
                        : Colors.orange.shade700,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Schedule Check Methods ---

  void _startScheduleCheck() {
    // Delay initial check until after first frame so auth context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 2));
      _checkSchedules(isRuntime: false);
    });

    // Periodic check every minute
    _scheduleCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkSchedules(isRuntime: true);
    });
  }

  Future<void> _checkSchedules({required bool isRuntime}) async {
    try {
      debugPrint('[ScheduleCheck] ========== Starting check (isRuntime=$isRuntime) ==========');

      // Fetch user's current context state first to check if they are already at this favorite
      String? currentFavoriteName;
      try {
        final stateResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'GET',
          '${EnvironmentConfig.apiBaseUrl}/get-user-current',
          baseHeaders: {'X-User-ID': widget.aacUserId},
        );
        debugPrint('[ScheduleCheck] get-user-current status: ${stateResponse.statusCode}');
        if (stateResponse.statusCode == 200) {
          final stateData = json.decode(stateResponse.body);
          currentFavoriteName = stateData['favorite_name'] as String?;
          debugPrint('[ScheduleCheck] Currently loaded favorite: "$currentFavoriteName"');
        } else {
          debugPrint('[ScheduleCheck] get-user-current failed: ${stateResponse.body}');
        }
      } catch (e) {
        debugPrint('[ScheduleCheck] Failed to fetch current user state: $e');
      }

      // Fetch favorites list
      debugPrint('[ScheduleCheck] Fetching favorites from: ${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites');
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites',
        baseHeaders: {'X-User-ID': widget.aacUserId},
      );

      debugPrint('[ScheduleCheck] Favorites response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final favorites = List<Map<String, dynamic>>.from(
          data['favorites'] ?? [],
        );

        debugPrint('[ScheduleCheck] Total favorites returned: ${favorites.length}');

        final now = DateTime.now();
        // Always use en_US locale so day names match what the backend stores ("Monday", etc.)
        final currentDay = DateFormat('EEEE', 'en_US').format(now);
        final currentTimeMinutes = now.hour * 60 + now.minute;

        debugPrint('[ScheduleCheck] Current: $currentDay ${now.hour}:${now.minute.toString().padLeft(2, '0')} ($currentTimeMinutes min)');
        debugPrint('[ScheduleCheck] Handled schedules: $_handledSchedules');

        for (final fav in favorites) {
          final favName = fav['name'] ?? '(unnamed)';
          final schedule = fav['schedule'];

          if (schedule == null) {
            debugPrint('[ScheduleCheck]   "$favName": no schedule');
            continue;
          }

          final enabled = schedule['enabled'];
          if (enabled != true) {
            debugPrint('[ScheduleCheck]   "$favName": schedule disabled (enabled=$enabled)');
            continue;
          }

          // Check if current day is in scheduled days list
          bool isDayMatch = false;
          final daysOfWeek = schedule['days_of_week'];
          if (daysOfWeek is List) {
            isDayMatch = daysOfWeek.contains(currentDay);
            debugPrint('[ScheduleCheck]   "$favName": days=$daysOfWeek, currentDay="$currentDay", isDayMatch=$isDayMatch');
          } else if (schedule['day_of_week'] != null) {
            isDayMatch = schedule['day_of_week'] == currentDay;
            debugPrint('[ScheduleCheck]   "$favName": day_of_week=${schedule['day_of_week']}, currentDay="$currentDay", isDayMatch=$isDayMatch');
          } else {
            debugPrint('[ScheduleCheck]   "$favName": no days_of_week field found in schedule: $schedule');
          }

          if (!isDayMatch) continue;

          final startTimeStr = schedule['start_time'] as String?;
          final endTimeStr = schedule['end_time'] as String?;
          debugPrint('[ScheduleCheck]   "$favName": startTime=$startTimeStr, endTime=$endTimeStr');

          if (startTimeStr == null || endTimeStr == null) {
            debugPrint('[ScheduleCheck]   "$favName": missing start/end time, skipping');
            continue;
          }

          // Parse start and end times
          final startParts = startTimeStr.split(':').map(int.parse).toList();
          final endParts = endTimeStr.split(':').map(int.parse).toList();
          if (startParts.length < 2 || endParts.length < 2) {
            debugPrint('[ScheduleCheck]   "$favName": could not parse times, skipping');
            continue;
          }

          final startTimeMinutes = startParts[0] * 60 + startParts[1];
          final endTimeMinutes = endParts[0] * 60 + endParts[1];

          final minutesUntilStart = startTimeMinutes - currentTimeMinutes;
          final isUpcoming = minutesUntilStart >= 0 && minutesUntilStart <= 15;
          final isAlreadyActive = currentTimeMinutes > startTimeMinutes && currentTimeMinutes <= endTimeMinutes;

          debugPrint('[ScheduleCheck]   "$favName": start=$startTimeMinutes min, end=$endTimeMinutes min, now=$currentTimeMinutes min, minutesUntilStart=$minutesUntilStart, isUpcoming=$isUpcoming, isAlreadyActive=$isAlreadyActive');

          if (isUpcoming || isAlreadyActive) {
            final key = "$favName-$currentDay-$startTimeStr";
            debugPrint('[ScheduleCheck]   "$favName": MATCH! key="$key"');

            if (_handledSchedules.contains(key)) {
              debugPrint('[ScheduleCheck]   "$favName": already handled, skipping');
              continue;
            }

            if (currentFavoriteName == favName) {
              debugPrint('[ScheduleCheck]   "$favName": already loaded as current favorite, marking handled silently');
              _handledSchedules.add(key);
              continue;
            }

            debugPrint('[ScheduleCheck]   "$favName": showing dialog (mounted=$mounted)');
            if (mounted) {
              _showLoadFavoriteDialog(fav, key, minutesUntilStart: isUpcoming ? minutesUntilStart : 0);
            } else {
              debugPrint('[ScheduleCheck]   "$favName": widget not mounted, cannot show dialog!');
            }
            break; // Only prompt for one location at a time
          } else {
            debugPrint('[ScheduleCheck]   "$favName": outside window (minutesUntilStart=$minutesUntilStart), skipping');
          }
        }

        debugPrint('[ScheduleCheck] ========== Check complete ==========');
      } else {
        debugPrint('[ScheduleCheck] Failed to load favorites: status=${response.statusCode}, body=${response.body}');
      }
    } catch (e, stack) {
      debugPrint('[ScheduleCheck] Error checking schedules: $e\n$stack');
    }
  }

  Future<void> _showLoadFavoriteDialog(Map<String, dynamic> favorite, String scheduleKey, {int minutesUntilStart = 0}) async {
    final name = favorite['name'];
    final message = minutesUntilStart > 0
        ? 'The location "$name" is scheduled to start in $minutesUntilStart minute${minutesUntilStart == 1 ? '' : 's'}. Do you want to load it now?'
        : 'The scheduled location "$name" is now active. Do you want to load it?';
    await showDialog(
      context: context,
      barrierDismissible: false, // User must choose Yes or No
      builder: (context) => AlertDialog(
        title: const Text('Scheduled Location'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              _handledSchedules.add(scheduleKey);
              Navigator.pop(context);
            },
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              _handledSchedules.add(scheduleKey);
              Navigator.pop(context);
              _loadFavorite(favorite);
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFavorite(Map<String, dynamic> favorite) async {
    try {
      // Use UTC timestamp with explicit timezone to match backend expectations
      final loadTimestamp = DateTime.now().toUtc().toIso8601String();

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/user_current',
        baseHeaders: {'X-User-ID': widget.aacUserId},
        body: json.encode({
          'location': favorite['location'] ?? '',
          'locationLanguageOverride':
              _normalizeLocaleTag(favorite['locationLanguageOverride']) ?? '',
          'people': favorite['people'] ?? '',
          'activity': favorite['activity'] ?? '',
          'loaded_at': loadTimestamp,
          'favorite_name': favorite['name'],
          'saved_at': loadTimestamp,
        }),
      );

      if (response.statusCode == 200) {
        _applyLocationOverrideLocale(favorite['locationLanguageOverride']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded favorite: ${favorite['name']}')),
          );
          // Refresh options based on new context
          _loadInitialFreestyleOptions(contextData: favorite);
          _loadInitialPhraseOptions(contextData: favorite);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load favorite')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading favorite: $e');
    }
  }
}
