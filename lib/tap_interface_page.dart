import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import 'services/custom_image_service.dart';
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
import 'widgets/spelling_dialog.dart';
import 'services/schedule_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/authenticated_http_client.dart';
import 'package:url_launcher/url_launcher.dart';

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
      debugPrint('⏭️ Skipping duplicate log - missing image already recorded for: "$textTrimmed"');
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
  final bool shouldLogMissing; // Only log missing images in user-facing contexts, not preloading
  final ValueChanged<String>? onImageLogged; // Callback to track which images were logged
  final String? assignedImageUrl; // Pre-assigned image URL from database

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
  });

  State<TapInterfaceButton> createState() => _TapInterfaceButtonState();
}

class _TapInterfaceButtonState extends State<TapInterfaceButton> {
  String? _pictogramUrl;
  bool _isLoading = false;
  bool _isSightWord = false;
  String? _lastLoadedKey;

  static const Map<String, String> _numberWords = {
    'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
    'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
    'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14', 'fifteen': '15',
    'sixteen': '16', 'seventeen': '17', 'eighteen': '18', 'nineteen': '19', 'twenty': '20',
    'twenty-one': '21', 'twenty one': '21', 'twenty-two': '22', 'twenty two': '22',
    'twenty-three': '23', 'twenty three': '23', 'twenty-four': '24', 'twenty four': '24',
    'twenty-five': '25', 'twenty five': '25', 'twenty-six': '26', 'twenty six': '26',
    'twenty-seven': '27', 'twenty seven': '27', 'twenty-eight': '28', 'twenty eight': '28',
    'twenty-nine': '29', 'twenty nine': '29', 'thirty': '30',
    'thirty-one': '31', 'thirty one': '31', 'thirty-two': '32', 'thirty two': '32',
    'thirty-three': '33', 'thirty three': '33', 'thirty-four': '34', 'thirty four': '34',
    'thirty-five': '35', 'thirty five': '35', 'thirty-six': '36', 'thirty six': '36',
    'thirty-seven': '37', 'thirty seven': '37', 'thirty-eight': '38', 'thirty eight': '38',
    'thirty-nine': '39', 'thirty nine': '39', 'forty': '40',
    'forty-one': '41', 'forty one': '41', 'forty-two': '42', 'forty two': '42',
    'forty-three': '43', 'forty three': '43', 'forty-four': '44', 'forty four': '44',
    'forty-five': '45', 'forty five': '45', 'forty-six': '46', 'forty six': '46',
    'forty-seven': '47', 'forty seven': '47', 'forty-eight': '48', 'forty eight': '48',
    'forty-nine': '49', 'forty nine': '49', 'fifty': '50',
    'fifty-one': '51', 'fifty one': '51', 'fifty-two': '52', 'fifty two': '52',
    'fifty-three': '53', 'fifty three': '53', 'fifty-four': '54', 'fifty four': '54',
    'fifty-five': '55', 'fifty five': '55', 'fifty-six': '56', 'fifty six': '56',
    'fifty-seven': '57', 'fifty seven': '57', 'fifty-eight': '58', 'fifty eight': '58',
    'fifty-nine': '59', 'fifty nine': '59', 'sixty': '60',
    'sixty-one': '61', 'sixty one': '61', 'sixty-two': '62', 'sixty two': '62',
    'sixty-three': '63', 'sixty three': '63', 'sixty-four': '64', 'sixty four': '64',
    'sixty-five': '65', 'sixty five': '65', 'sixty-six': '66', 'sixty six': '66',
    'sixty-seven': '67', 'sixty seven': '67', 'sixty-eight': '68', 'sixty eight': '68',
    'sixty-nine': '69', 'sixty nine': '69', 'seventy': '70',
    'seventy-one': '71', 'seventy one': '71', 'seventy-two': '72', 'seventy two': '72',
    'seventy-three': '73', 'seventy three': '73', 'seventy-four': '74', 'seventy four': '74',
    'seventy-five': '75', 'seventy five': '75', 'seventy-six': '76', 'seventy six': '76',
    'seventy-seven': '77', 'seventy seven': '77', 'seventy-eight': '78', 'seventy eight': '78',
    'seventy-nine': '79', 'seventy nine': '79', 'eighty': '80',
    'eighty-one': '81', 'eighty one': '81', 'eighty-two': '82', 'eighty two': '82',
    'eighty-three': '83', 'eighty three': '83', 'eighty-four': '84', 'eighty four': '84',
    'eighty-five': '85', 'eighty five': '85', 'eighty-six': '86', 'eighty six': '86',
    'eighty-seven': '87', 'eighty seven': '87', 'eighty-eight': '88', 'eighty eight': '88',
    'eighty-nine': '89', 'eighty nine': '89', 'ninety': '90',
    'ninety-one': '91', 'ninety one': '91', 'ninety-two': '92', 'ninety two': '92',
    'ninety-three': '93', 'ninety three': '93', 'ninety-four': '94', 'ninety four': '94',
    'ninety-five': '95', 'ninety five': '95', 'ninety-six': '96', 'ninety six': '96',
    'ninety-seven': '97', 'ninety seven': '97', 'ninety-eight': '98', 'ninety eight': '98',
    'ninety-nine': '99', 'ninety nine': '99', 'hundred': '100', 'one hundred': '100'
  };

  String? _getNumberDisplay(String label) {
    final cleanLabel = label.trim().toLowerCase();
    if (int.tryParse(cleanLabel) != null) {
      return cleanLabel;
    }
    return _numberWords[cleanLabel];
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
    final enabledChanged = widget.enablePictograms != oldWidget.enablePictograms;
    final sightWordsChanged = widget.enableSightWords != oldWidget.enableSightWords;
    final gradeChanged = widget.sightWordGradeLevel != oldWidget.sightWordGradeLevel;
    
    if (labelChanged || enabledChanged || sightWordsChanged || gradeChanged) {
      _loadPictogram();
    }
  }

  Future<void> _loadPictogram() async {
    // Only skip if label is empty
    if (widget.label.trim().isEmpty) {
      return;
    }

    debugPrint('🖼️ TapInterfaceButton._loadPictogram: label="${widget.label}", enablePictograms=${widget.enablePictograms}');

    final cacheKey = widget.label;
    if (_lastLoadedKey == cacheKey && _pictogramUrl != null) {
      debugPrint('🖼️ Using cached pictogram for "${widget.label}"');
      return;
    }

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
        allWordsAreSightWords = await _checkIfAllWordsAreSightWords(widget.label, widget.sightWordGradeLevel);
        debugPrint('🖼️ Sight word check: allWords=$allWordsAreSightWords');
      }
      
      if (allWordsAreSightWords) {
        // Only suppress pictogram if ALL words are sight words
        debugPrint('🖼️ Skipping image for "${widget.label}" - all words are sight words');
        if (mounted) {
          setState(() {
            _pictogramUrl = null;
            _isSightWord = true; // Apply sight word formatting
            _isLoading = false;
            _lastLoadedKey = cacheKey;
          });
        }
      } else {
        // If pictograms are disabled, never show assigned or searched images
        if (!widget.enablePictograms) {
          debugPrint('🖼️ Skipping image for "${widget.label}" - enablePictograms is false');
          if (mounted) {
            setState(() {
              _pictogramUrl = null;
              _isSightWord = false;
              _isLoading = false;
              _lastLoadedKey = cacheKey;
            });
          }
        } else if (widget.assignedImageUrl != null && widget.assignedImageUrl!.isNotEmpty) {
          // FIRST: Check if there's a pre-assigned image URL from the database
          debugPrint('🖼️ Using assigned image for "${widget.label}": ${widget.assignedImageUrl}');
          if (mounted) {
            setState(() {
              _pictogramUrl = widget.assignedImageUrl;
              _isSightWord = false;
              _isLoading = false;
              _lastLoadedKey = cacheKey;
            });
          }
        } else {
          // SECOND: If no assigned image, search for pictogram
          debugPrint('🖼️ Loading pictogram for "${widget.label}"...');
          final pictogramService = PictogramService();
          pictogramService.enablePictograms = true;
        
          final result = await pictogramService.getPictogramResult(
            widget.label, 
            sightWordGradeLevel: widget.sightWordGradeLevel != null ? int.tryParse(widget.sightWordGradeLevel!) : null,
            keywords: widget.keywords,
            shouldLogMissing: widget.shouldLogMissing,
          );
        
          debugPrint('🖼️ Pictogram result for "${widget.label}": ${result?.imageUrl ?? "null"}');
        
          // If no image found after all search strategies, log it as missing (display layer logging)
          // Only log if shouldLogMissing is true (disabled during preloading)
          // AND we haven't already logged this image text in this session (prevent duplicates)
          if (widget.shouldLogMissing && result != null && result.imageUrl == null && !result.isSightWord) {
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
              debugPrint('⏭️ Skipping duplicate log for: "${widget.label}" (already logged in this session)');
            }
          }
        
          if (mounted) {
            setState(() {
              _pictogramUrl = result?.imageUrl;
              _isSightWord = false; // No sight word formatting for non-sight words
              _isLoading = false;
              _lastLoadedKey = cacheKey;
            });
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
    }
  }

  /// Check if text contains any sight words (not just all words)
  Future<bool> _checkForAnySightWords(String text, String? sightWordGradeLevel) async {
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
        debugPrint('🔤 TapInterfaceButton: "$text" contains sight words - suppressing pictogram');
      }

      return hasAnySightWords;
    } catch (e) {
      debugPrint('🔤 TapInterfaceButton: Error checking sight words: $e');
      return false;
    }
  }

  /// Check if ALL words in text are sight words (for formatting)
  Future<bool> _checkIfAllWordsAreSightWords(String text, String? sightWordGradeLevel) async {
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
      
      // Use the built-in method that checks if ALL words are sight words
      final allAreSightWords = sightWordService.isSightWordText(text);
      
      if (allAreSightWords) {
        debugPrint('🔤 TapInterfaceButton: "$text" - ALL words are sight words, applying special formatting');
      }

      return allAreSightWords;
    } catch (e) {
      debugPrint('🔤 TapInterfaceButton: Error checking if all words are sight words: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: widget.onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.backgroundColor,
        foregroundColor: widget.foregroundColor,
        elevation: 2,
        padding: widget.padding,
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          side: BorderSide(color: widget.borderColor),
        ),
      ),
      // Tap interface always shows images (ignores enablePictograms setting)
      child: widget.label.isNotEmpty
          ? _buildPictogramContent()
          : _buildTextOnlyContent(),
    );
  }

  Widget _buildPictogramContent() {
    // Check for number first
    final numberDisplay = _getNumberDisplay(widget.label);
    if (numberDisplay != null) {
      return _buildNumberLayout(numberDisplay);
    }

    if (_isLoading) {
      return _buildTextOnlyContent();
    }

    if (_pictogramUrl != null && _pictogramUrl?.isNotEmpty == true) {
      return _buildPictogramLayout();
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
          padding: const EdgeInsets.only(bottom: 18.0), // Increased padding for label strip
          child: _buildPictogramImage(),
        ),
        
        // Text layer - pinned to bottom with background strip
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7), // Dark background for readability
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
    final FontWeight fontWeight = isSpecialSightWord ? FontWeight.w900 : (widget.fontWeight ?? FontWeight.w600);
    final Color textColor = isSpecialSightWord ? const Color(0xFFFF4444) : widget.foregroundColor;
    
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
                    shadows: isSpecialSightWord ? [
                      const Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 3,
                        color: Color(0x40000000),
                      ),
                    ] : null,
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
        int maxWordLen = text.split(' ').map((w) => w.length).fold(0, (p, c) => p > c ? p : c);
        if (maxWordLen > 0) {
           // Subtract padding (8.0 on each side = 16.0)
           double maxFontSizeForWidth = (availableWidth - 16) / (maxWordLen * 0.75);
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
                shadows: isSpecialSightWord ? [
                  const Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 3,
                    color: Color(0x40000000),
                  ),
                ] : null,
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
  // --- Speech History ---
  String _speechHistory = "";
  final TextEditingController _speechHistoryController = TextEditingController();
  final List<String> _pastSpeechHistory = []; // Stores previously spoken phrases
  bool _isAudioSurfingEnabled = false;
  String? _audioSurfingPreviewOptionKey;
  
  // --- Current Build Space ---
  String _buildSpaceText = "";
  final TextEditingController _buildSpaceController = TextEditingController();
  
  // --- Performance Optimization ---
  final Map<String, String?> _imagePreloadCache = {}; // Cache for preloaded images
  bool _isPreloadingImages = false;
  
  // Cache for category options to avoid re-fetching
  final Map<String, List<Map<String, String>>> _categoryPhraseCache = {};
  final Map<String, List<String>> _categoryWordCache = {};
  final Map<String, Map<String, List<String>>> _categoryWordKeywordsCache = {};
  
  // --- New Tap Interface State ---
  TapInterfaceConfig? _tapConfig;
  TapInterfaceCategory? _selectedCategory;

  
  // --- Option Display State ---
  List<Map<String, String>> _phraseOptions = []; // Top 2 rows - {summary, fullText}
  List<String> _wordOptions = []; // Bottom 3 rows - single words/building
  Map<String, List<String>> _wordKeywords = {}; // Keywords for each word option to improve image matching
  int _optionsRebuildKey = 0; // Force UI rebuild when options change
  bool _isJokesMode = false; // Track if we're showing jokes (for Something Else handling)

  bool _isLoadingPhraseOptions = false; // Separate loading state for phrases
  bool _isLoadingWordOptions = false;   // Separate loading state for words
  // bool _isLoadingOptions = false;       // General loading state for operations affecting both sections
  bool _isLoadingConfig = false;
  
  // --- Speech Bubble Overlay Variables ---
  bool _showSpeechBubble = false;
  String _speechBubbleText = '';
  Timer? _speechBubbleTimer;
  
  // --- Admin State ---
  bool _isAdminToolbarLocked = true;
  String _currentPIN = '1234'; // Default PIN
  int _pinAttempts = 0; // Track failed PIN attempts
  
  // --- TTS ---
  late FlutterTts _flutterTts;
  static bool _audioSessionInitialized = false;
  
  // --- Services ---
  late TapInterfaceService _tapService;
  
  // --- Wake Word Service ---
  WakeWordService? _wakeWordService;
  bool _isListeningForWakeWord = false;
  bool _isListeningForQuestion = false;
  String _currentQuestion = '';
  String _statusMessage = '';
  bool _showBottomStatusText = false;
  
  // --- Retry Logic (matching main.dart) ---
  int _llmRetryCount = 0;
  static const int _maxLLMRetries = 2;
  String? _lastQuestion;
  
  // --- Text Prompt Tracking ---
  bool _textPromptUsed = false; // Track if the text prompt has been used once
  
  // --- Schedule Check ---
  Timer? _scheduleCheckTimer;
  
  // --- Session-based Missing Image Deduplication ---
  final Set<String> _sessionLoggedMissingImages = {}; // Track which images we've logged in this session

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
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    _tapService = TapInterfaceService(userSettingsProvider: userSettings);
    
    // Initialize Wake Word Service
    _initializeWakeWordService();
    
    // Initialize PIN from user settings
    _updatePINFromSettings(userSettings);
    
    // Start schedule check
    _startScheduleCheck();
    
    // Load tap interface configuration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Clear all image caches on app startup to ensure fresh data
      _clearAllCaches();
      
      _loadTapInterfaceConfig();
      _loadInitialFreestyleOptions();
      _loadInitialPhraseOptions();
      _primeAudioSystem(); // Prime audio system to prevent first TTS from being cut off
      
      // Proactively initialize audio session to prevent first TTS using system voice
      _initializeAudioSessionProactively();
    });
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
      debugPrint('🚨 VALIDATION FAILED: Found ${duplicates.length} duplicates in _wordOptions:');
      debugPrint('🚨 Duplicates: $duplicates');
      debugPrint('🚨 Full _wordOptions: $_wordOptions');
      
      // Auto-fix by running deduplication
      final fixedOptions = _deduplicateWords(_wordOptions);
      if (fixedOptions.length != _wordOptions.length) {
        debugPrint('🔧 AUTO-FIX: Deduplicating _wordOptions (${_wordOptions.length} → ${fixedOptions.length})');
        setState(() {
          _wordOptions = fixedOptions;
        });
      }
    } else {
      debugPrint('✅ VALIDATION PASSED: No duplicates found in _wordOptions (${_wordOptions.length} words)');
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
  /// Calculate Phrases section rows and flex value based on LLMOptions
  Map<String, int> _calculatePhraseSectionLayout(int llmOptions, int gridColumns) {
    if (llmOptions == 0) {
      return {'rows': 0, 'flex': 0}; // Hide section
    }
    
    final effectiveColumns = _getEffectiveMainContentColumns(gridColumns);
    final totalButtons = llmOptions + 1; // Include "Something Else" button
    final rows = (totalButtons / effectiveColumns).ceil();
    
    // Flex calculation:
    // 1 row = fixed height (154px), no flex needed  
    // 2 rows = flex 2 (enough for 2 full rows of buttons without cutoff)
    // 3+ rows = flex 3 (larger height for many rows, with scrolling)
    final flex = rows <= 1 ? 0 : (rows == 2 ? 2 : 3);
    
    debugPrint('📊 Phrases Layout: llmOptions=$llmOptions, totalButtons=$totalButtons, columns=$effectiveColumns, rows=$rows, flex=$flex');
    return {'rows': rows, 'flex': flex};
  }

  /// Calculate flex value for Words section based on Phrases section size
  int _calculateWordsSectionFlex(UserSettings? userSettings) {
    final llmOptions = userSettings?.llmOptions ?? 10;
    final phraseLayout = _calculatePhraseSectionLayout(llmOptions, userSettings?.gridColumns ?? 6);
    
    // Calculate Words section flex based on Phrases section
    if (llmOptions == 0) {
      return 1; // Take full space if no phrases
    } else if (phraseLayout['rows'] == 1 || phraseLayout['rows'] == 2) {
      return 1; // Single and double row phrases use fixed height, Words takes remaining flex space
    } else {
      // 3+ row phrases use flex, Words section gets flex 2
      return 2; 
    }
  }

  /// Calculate the proper height for single-row phrases section
  double _calculateSingleRowPhrasesHeight(UserSettings? userSettings) {
    // Component heights:
    const headerHeight = 0.0; // Header removed
    const gridPadding = 6.0; // 3px padding all around
    const containerBorder = 4.0; // 2px border top + bottom
    const extraBottomPadding = 10.0; // Extra padding to ensure buttons aren't cut off
    
    // Calculate button height based on aspect ratio
    // Note: In a real layout, button width would be (available_width / columns)
    // For estimation, we'll use a reasonable assumption based on typical screen width
    final columns = _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6);
    const assumedAvailableWidth = 800.0; // Reasonable assumption for main content width
    final buttonWidth = assumedAvailableWidth / columns;
    final buttonHeight = buttonWidth / 1.1; // aspect ratio is 1.1 (width/height)
    
    final totalHeight = headerHeight + buttonHeight + gridPadding + containerBorder + extraBottomPadding;
    
    debugPrint('📐 Phrases Height Calculation: header=$headerHeight, buttonH=$buttonHeight (buttonW=$buttonWidth, cols=$columns), padding=$gridPadding, border=$containerBorder, extraPadding=$extraBottomPadding = total=$totalHeight');
    
    return totalHeight;
  }

  /// Build the Phrases section widget with dynamic sizing
  Widget _buildPhrasesSection(UserSettings? userSettings) {
    final llmOptions = userSettings?.llmOptions ?? 10;
    final gridColumns = userSettings?.gridColumns ?? 6;
    final layout = _calculatePhraseSectionLayout(llmOptions, gridColumns);
    
    // Hide section if llmOptions is 0
    if (llmOptions == 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dynamic height based on available width
        final availableWidth = constraints.maxWidth;
        final effectiveColumns = _getEffectiveMainContentColumns(gridColumns);
        
        // Calculate button size
        // Width = (TotalWidth - (Spacing * (Cols - 1)) - GridPaddingHorizontal - BorderHorizontal) / Cols
        // GridPadding = 3 * 2 = 6
        // Border = 2 * 2 = 4
        // Spacing = 2
        final contentWidth = availableWidth - 10; // 6 padding + 4 border
        final totalSpacing = 2.0 * (effectiveColumns - 1);
        final buttonWidth = (contentWidth - totalSpacing) / effectiveColumns;
        final buttonHeight = buttonWidth / 1.1; // Aspect ratio 1.1
        
        // Calculate total height needed
        const headerHeight = 0.0;
        const verticalPadding = 6.0; // 3 top + 3 bottom grid padding
        const verticalBorder = 4.0; // 2 top + 2 bottom border
        
        final rows = layout['rows'] as int;
        
        // Calculate height for min(rows, 2) rows
        // If rows > 2, we show 2 rows height and scroll
        final rowsToCalculate = rows >= 2 ? 2 : 1;
        
        final gridHeight = (buttonHeight * rowsToCalculate) + (2.0 * (rowsToCalculate - 1));
        final totalHeight = headerHeight + gridHeight + verticalPadding + verticalBorder;
        
        // Add a little buffer for safety
        final finalHeight = totalHeight + 4.0;

        return Container(
          height: finalHeight,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[25] ?? Colors.green.shade50, Colors.green[50] ?? Colors.green.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[300] ?? Colors.green.shade300, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.2),
                offset: const Offset(0, 3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            children: [
              // Grid content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Stack(
                    children: [
                      // Show grid if we have options (even if loading)
                      if (_phraseOptions.isNotEmpty)
                        _buildPhrasesGrid(userSettings, rows > 2)
                      else if (!_isLoadingPhraseOptions)
                        const Center(child: Text('No phrases available', style: TextStyle(color: Colors.grey, fontSize: 10))),
                        
                      // Show loading indicator
                      if (_isLoadingPhraseOptions)
                        _phraseOptions.isEmpty 
                            ? const Center(child: CircularProgressIndicator())
                            : const Positioned(
                                top: 0, left: 0, right: 0, 
                                child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent)
                              ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  /// Build the phrases grid with consistent button generation
  Widget _buildPhrasesGrid(UserSettings? userSettings, bool allowScrolling) {
    final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
    final tapPictogramsEnabled = !tapPictogramsDisabled;
    final tapSightWordLogicEnabled = !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);

    return GridView.count(
      physics: allowScrolling ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6),
      childAspectRatio: 1.1,
      crossAxisSpacing: 2,
      mainAxisSpacing: 2,
      children: List.generate(
        (userSettings?.llmOptions ?? 10) + 1,
        (index) {
          if (index == (userSettings?.llmOptions ?? 10)) {
            return TapInterfaceButton(
              label: 'Something Else',
              onPressed: () => _loadMorePhraseOptions(),
              backgroundColor: Colors.green[50] ?? Colors.green.shade50,
              foregroundColor: Colors.black87,
              borderColor: Colors.green[300] ?? Colors.green.shade300,
              fontSize: 8,
              enablePictograms: tapPictogramsEnabled,
              sightWordGradeLevel: userSettings?.sightWordGradeLevel,
              enableSightWords: tapSightWordLogicEnabled,
              padding: const EdgeInsets.all(2),
              shouldLogMissing: false, // Don't log missing images for dynamic buttons
            );
          } else if (index < _phraseOptions.length) {
            final phraseOption = _phraseOptions[index];
            final fullText = phraseOption['fullText'] ?? '';
            final isPreviewArmed = _isAudioSurfingEnabled &&
                _audioSurfingPreviewOptionKey == 'phrase::$fullText';
            final keywordsString = phraseOption['keywords'] ?? '';
            final keywords = keywordsString.isNotEmpty 
                ? keywordsString.split('|').where((s) => s.trim().isNotEmpty).toList()
                : null;
            
            return TapInterfaceButton(
              label: phraseOption['summary'] ?? '',
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
              shouldLogMissing: false, // Don't log missing images for LLM-generated phrases
            );
          } else {
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green[200] ?? Colors.green.shade200),
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
        },
      ),
    );
  }

  double _getCategoryAspectRatio(int mainColumns, double mainAspectRatio) {
    // Categories get 1/10 of total width with 1 column
    // Main content gets 9/10 of total width with mainColumns
    // To match button sizes: category button width = (1/10 total) / 1 = 1/10 total
    // Main button width = (9/10 total) / mainColumns = 9/(10*mainColumns) total
    // For equal widths: 1/10 = 9/(10*mainColumns) → mainColumns = 9 (this is the flex ratio)
    // 
    // Since layout uses flex 1:9, and we want equal button sizes:
    // Category aspect ratio should be: mainAspectRatio * (mainColumns/9) * (1/1)
    return mainAspectRatio * mainColumns / 9.0;
  }

  /// Calculate appropriate column count for modal dialog based on its smaller size
  /// 
  /// Modal constraints: maxWidth: 495px vs full screen width
  /// We need to scale down the column count proportionally to maintain similar button sizes
  int _getModalColumnCount(int adminColumns) {
    // Now that modal width is responsive, we can use a more direct relationship
    // Fewer admin columns = larger buttons = fewer modal columns for larger buttons
    // More admin columns = smaller buttons = more modal columns for smaller buttons
    if (adminColumns <= 3) return 2;        // Very large buttons -> 2 columns
    if (adminColumns <= 6) return 3;        // Medium-large buttons -> 3 columns  
    if (adminColumns <= 10) return 4;       // Medium buttons -> 4 columns
    if (adminColumns <= 14) return 5;       // Small buttons -> 5 columns
    return 6;                               // Very small buttons -> 6 columns
  }

  @override
  void dispose() {
    _buildSpaceController.dispose();
    _speechHistoryController.dispose();
    _speechBubbleTimer?.cancel(); // Clean up speech bubble timer
    _scheduleCheckTimer?.cancel(); // Clean up schedule check timer
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
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    
    // Check if we have wake word settings (using the actual property names)
    if (userSettings.settings?.wakeWordName.isNotEmpty == true) {
      // Use the existing global wake word service instance from main.dart
      // This ensures we don't create competing instances
      _wakeWordService = WakeWordService.getCurrentInstance();
      
      if (_wakeWordService != null) {
        print('TapInterface: Using existing wake word service instance');
        _setupWakeWordCallbacks();
        _startWakeWordListening();
      } else {
        print('TapInterface: No existing wake word service found, creating new one');
        // Fallback: create new instance if none exists
        final wakeWordInterjection = (userSettings.settings?.wakeWordInterjection ?? 'hey').trim().toLowerCase();
        final wakeWordName = (userSettings.settings?.wakeWordName ?? 'bravo').trim().toLowerCase();
        final wakeWordVariants = [
          '$wakeWordInterjection $wakeWordName',
          '$wakeWordInterjection, $wakeWordName',
          '$wakeWordInterjection,$wakeWordName',
        ];
        
        _wakeWordService = WakeWordService(wakeWords: wakeWordVariants);
        _setupWakeWordCallbacks();
        _startWakeWordListening();
      }
    }
  }
  
  void _setupWakeWordCallbacks() {
    if (_wakeWordService == null) return;
    
    print('TapInterface: Setting up wake word callbacks to override grid page callbacks');
    
    _wakeWordService!.onWakeWord = (transcript) async {
      print('TapInterface: Wake word detected: $transcript');
      
      if (!mounted) return;
      
      setState(() {
        _showBottomStatusText = true;
        _isListeningForQuestion = true;
        _isListeningForWakeWord = false;
        _statusMessage = 'Listening for your question...';
      });
      
      // Show speech bubble and announce "I am listening" using backend TTS like grid page
      _showSpeechBubbleOverlay('I am listening...');
      await _announceViaBackend('I am listening');
      
      // Start question listening
      await _wakeWordService?.startQuestionListening();
    };
    
    _wakeWordService!.onQuestion = (question) async {
      print('TapInterface: Question detected: $question');
      
      if (!mounted) return;
      
      setState(() {
        _currentQuestion = question;
        _isListeningForQuestion = false;
        _showBottomStatusText = false;
        _statusMessage = '';
      });
      
      // Show the question in speech bubble
      _showSpeechBubbleOverlay(question);
      
      // START GENERATING OPTIONS IMMEDIATELY (don't wait)
      // This runs in parallel with the announcement
      final optionGenerationFuture = _generateOptionsFromQuestion(question);
      
      // Announce while generation is happening
      await _announceViaBackend('Okay, processing: $question. Give me a moment.');
      
      // Now wait for options to complete (if not done already)
      await optionGenerationFuture;
      
      // Resume wake word listening
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

      setState(() {
        _showBottomStatusText = true;
        _statusMessage = 'Hearing: "$questionText"';
      });
    };
    
    _wakeWordService!.shouldAllowWakeWordRestart = () {
      return !_isListeningForQuestion && mounted;
    };
    
    print('TapInterface: Wake word callbacks setup complete');
  }
  
  void _startWakeWordListening() async {
    if (_wakeWordService == null) return;
    
    setState(() {
      _showBottomStatusText = false;
      _isListeningForQuestion = false;
      _isListeningForWakeWord = true;
      _statusMessage = '';
    });
    
    _wakeWordService!.resumeWakeWordAutoRestart();
    await _wakeWordService!.startWakeWordListening();
  }
  
  Future<void> _generateOptionsFromQuestion(String question) async {
    try {
      print('[TapInterface] _generateOptionsFromQuestion: Starting for question: "$question"');
      
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
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      
      String phraseContext = 'answering the question: "$question" in the context of $categoryContext';
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        phraseContext = 'answering the question: "$question" in the context of $categoryContext while feeling $currentMood';
      }
      
      print('[TapInterface] Generating phrase options with context: $phraseContext');
      
      // START BOTH API CALLS IN PARALLEL (like category selection does)
      final phraseFuture = _tapService.generateLLMPhraseOptions(
        context: phraseContext,
        maxOptions: 20, // Request more to ensure we have enough for 17 display slots
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
      
      print('[TapInterface] Generating word options for question: $categoryForWords');
      
      final wordFuture = _tapService.generateCategoryWords(
        category: categoryForWords,
        buildSpaceContent: _buildSpaceText,
        excludeWords: [],
        maxOptions: requiredWordCount + 15, // Request extra for deduplication
        requestDifferentOptions: false,
        currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
      );
      
      // Wait for BOTH to complete in parallel
      print('[TapInterface] Waiting for phrase and word options to generate in parallel...');
      final results = await Future.wait([phraseFuture, wordFuture]);
      final phraseOptions = results[0] as List<Map<String, String>>;
      final wordOptionsStrings = results[1] as List<String>;
      
      print('[TapInterface] Received ${phraseOptions.length} phrase options');
      print('[TapInterface] Received ${wordOptionsStrings.length} word options');
      
      if (!mounted) {
        print('[TapInterface] Widget unmounted, aborting option update');
        return;
      }
      
      // Successful generation - reset retry counter
      _llmRetryCount = 0;
      _lastQuestion = null;
      
      setState(() {
        // Update phrase options (top 2 rows) - need exactly 17 for proper display
        _phraseOptions.clear();
        
        // Validate phraseOptions is a proper list before using
        if (phraseOptions is List) {
          print('[TapInterface] Adding ${phraseOptions.length} phrase options');
          _phraseOptions.addAll(phraseOptions.take(17));
        } else {
          print('[TapInterface] ERROR: phraseOptions is not a List, type: ${phraseOptions.runtimeType}');
        }
        
        // If we don't have enough phrase options, add fallbacks
        if (_phraseOptions.length < 17) {
          print('[TapInterface] Adding ${17 - _phraseOptions.length} fallback phrases');
          final fallbackPhrases = [
            'I understand', 'Tell me more', 'That makes sense', 'I see', 'Good point',
            'Can you explain?', 'What do you think?', 'I agree', 'Interesting', 'Thank you',
            'You\'re right', 'I need help', 'Let me think', 'That\'s good', 'I\'m not sure',
            'Maybe', 'Okay'
          ];
          final neededCount = 17 - _phraseOptions.length;
          final additionalPhrases = fallbackPhrases.take(neededCount).map((text) => {
            'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
            'fullText': text,
          }).toList();
          _phraseOptions.addAll(additionalPhrases);
        }
        
        print('[TapInterface] Final phrase options count: ${_phraseOptions.length}');
        
        // Deduplicate word options (case-insensitive) to avoid "Want"/"want" duplicates
        final deduplicatedWords = _deduplicateWords(wordOptionsStrings);
        
        debugPrint('TapInterface: Original words: ${wordOptionsStrings.length}, Deduplicated: ${deduplicatedWords.length}');
        
        final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        
        // Update word options (bottom 3 rows)
        _wordOptions.clear();
        _wordKeywords.clear(); // Clear keywords when clearing word options
        _wordOptions.addAll(deduplicatedWords.take(requiredWordCount));
        
        print('[TapInterface] Added ${_wordOptions.length} word options');
        
        // If we don't have enough word options after deduplication, add fallbacks
        if (_wordOptions.length < requiredWordCount) {
          print('[TapInterface] Adding ${requiredWordCount - _wordOptions.length} fallback words');
          final fallbackWords = _getFallbackWordOptions();
          final currentWordsLower = _wordOptions.map((w) => w.toLowerCase()).toSet();
          
          // Filter fallbacks to avoid duplicates with existing words (case-insensitive)
          final uniqueFallbacks = fallbackWords
              .where((word) => !currentWordsLower.contains(word.toLowerCase()))
              .toList();
          
          final neededCount = requiredWordCount - _wordOptions.length;
          _wordOptions.addAll(uniqueFallbacks.take(neededCount));
        }
        
        print('[TapInterface] Final word options count: ${_wordOptions.length}');
        
        // Update status message to show options are ready
        _statusMessage = 'Options ready! Tap to select, or say "${_getFormattedWakeWord()}" to ask a question.';
      });
      
      print('[TapInterface] _generateOptionsFromQuestion: Completed successfully');
      
      // Show success feedback
      _showSpeechBubbleOverlay('I found some options for you!');
      
    } catch (e, stackTrace) {
      print('[TapInterface] ERROR in _generateOptionsFromQuestion: $e');
      print('[TapInterface] Stack trace: $stackTrace');
      print('[TapInterface] 🚨 ERROR DETAILS: retryCount=$_llmRetryCount, maxRetries=$_maxLLMRetries, hasStoredQuestion=${_lastQuestion != null}');
      
      if (!mounted) return;
      
      // Retry logic matching main.dart
      if (_llmRetryCount < _maxLLMRetries && _lastQuestion != null) {
        _llmRetryCount++;
        print('[TapInterface] 🔄 RETRY #$_llmRetryCount: Attempting retry after error...');
        
        setState(() {
          _statusMessage = 'Processing failed - Retrying ($_llmRetryCount/$_maxLLMRetries)...';
        });
        
        // Wait a moment before retrying
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          print('[TapInterface] 🔄 RETRY #$_llmRetryCount: Re-executing question generation');
          // Recursively retry with the stored question
          await _generateOptionsFromQuestion(_lastQuestion!);
        }
        return; // Exit to prevent showing error message during retry
      }
      
      // All retries exhausted or no stored question
      print('[TapInterface] 🚨 FINAL FAILURE: All retries exhausted ($_llmRetryCount attempts) or no stored question');
      _llmRetryCount = 0;
      _lastQuestion = null;
      
      _showSpeechBubbleOverlay('Sorry, I had trouble understanding. Let me try again.');
      setState(() {
        _statusMessage = 'Say "${_getFormattedWakeWord()}" to try asking your question again...';
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
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    if (userSettings.settings?.wakeWordName.isNotEmpty == true) {
      final wakeWordInterjection = (userSettings.settings?.wakeWordInterjection ?? 'hey').trim();
      final wakeWordName = (userSettings.settings?.wakeWordName ?? 'bravo').trim();
      // Capitalize properly: "Hey Bravo"
      final formattedInterjection = wakeWordInterjection.substring(0, 1).toUpperCase() + wakeWordInterjection.substring(1).toLowerCase();
      final formattedName = wakeWordName.substring(0, 1).toUpperCase() + wakeWordName.substring(1).toLowerCase();
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
      final ensuredConfig = _ensureEmailTapCategory(config);
      
      // Debug: Log all categories and their speech text
      if (ensuredConfig != null) {
        debugPrint('[TapInterface] 📋 Loaded tap config with ${ensuredConfig.buttons.length} categories:');
        for (var i = 0; i < ensuredConfig.buttons.length; i++) {
          final category = ensuredConfig.buttons[i];
          debugPrint('[TapInterface] Category $i: "${category.label}" - Speech Text: "${category.speechText}" (null: ${category.speechText == null})');
        }
      } else {
        debugPrint('[TapInterface] ❌ No tap config loaded!');
      }
      
      setState(() {
        _tapConfig = ensuredConfig;
        _isLoadingConfig = false;
      });
      
      // Preload category images in background for better performance
      _preloadCategoryImages();
      
    } catch (e) {
      debugPrint('Error loading tap interface config: $e');
      setState(() {
        _isLoadingConfig = false;
      });
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
        hidden: false,
        optionType: 'phrase',
      ),
    );

    debugPrint('[TapInterface] Added fallback Email special category (missing from server config).');

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

  /// Preload category images in background for better performance
  void _preloadCategoryImages() async {
    if (_tapConfig == null || _isPreloadingImages) return;
    
    setState(() {
      _isPreloadingImages = true;
    });

    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      if (userSettings.settings?.enablePictograms != true) {
        return; // Skip if pictograms disabled
      }

      final pictogramService = PictogramService();
      pictogramService.enablePictograms = true;
      
      debugPrint('🚀 Preloading ${_tapConfig!.buttons.length} category images...');
      
      // Preload images for all categories in parallel (faster)
      final futures = _tapConfig!.buttons.map((category) async {
        try {
          final result = await pictogramService.getPictogramResult(category.label, shouldLogMissing: false);
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
        
        debugPrint('🎯 Starting custom image batch preload for ${allButtonTexts.length} buttons...');
        await pictogramService.preloadCustomImages(allButtonTexts);
        
      } catch (e) {
        debugPrint('❌ Custom image batch preload error: $e');
      }
      
      // Wait for all preloads to complete or timeout after 2 seconds
      await Future.wait(futures).timeout(Duration(seconds: 2));
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
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    if (userSettings.settings?.enablePictograms != true) return;
    
    // Run asynchronously without blocking modal display
    Future.microtask(() async {
      try {
        final pictogramService = PictogramService();
        final childLabels = category.children.map((child) => child.label).toList();
        
        if (childLabels.isNotEmpty) {
          debugPrint('🎯 Preloading custom images for ${childLabels.length} modal buttons in "${category.label}"');
          await pictogramService.preloadCustomImages(childLabels);
        }
      } catch (e) {
        debugPrint('❌ Modal custom image preload error: $e');
      }
    });
  }

  Future<void> _loadInitialFreestyleOptions({Map<String, dynamic>? contextData}) async {
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
          initialContext = 'communication topics for someone ${contextParts.join(' ')}';
        }
      }
      
      // Load initial freestyle word options using dynamic count
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      
      final wordOpts = await _tapService.generateFreestyleOptions(
        context: initialContext,
        buildSpaceText: '',
        singleWordsOnly: true,
        maxOptions: requiredWordCount + 15, // Request extra to ensure we have enough
        currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
      );
      
      debugPrint('[TapInterface] Initial API returned ${wordOpts.length} word options for $requiredWordCount slots');
      debugPrint('[TapInterface] Initial options: $wordOpts');
      
      if (mounted) {
        // Ensure we have exactly the required number of options
        List<String> initialOptions = [];
        if (wordOpts.isNotEmpty) {
          initialOptions = wordOpts.take(requiredWordCount).toList();
        }
        
        // If we don't have enough, supplement with fallback
        if (initialOptions.length < requiredWordCount) {
          debugPrint('[TapInterface] Only have ${initialOptions.length} initial options, need $requiredWordCount. Adding fallbacks...');
          final currentWordsSet = initialOptions.toSet();
          final fallbackOptions = _getFallbackWordOptions();
          final additionalOptions = fallbackOptions
              .where((word) => !currentWordsSet.contains(word))
              .take(requiredWordCount - initialOptions.length)
              .toList();
          initialOptions.addAll(additionalOptions);
          debugPrint('[TapInterface] Added ${additionalOptions.length} fallback options, total now: ${initialOptions.length}');
        }
        
        setState(() {
          _wordOptions = _deduplicateWords(initialOptions);
          _isLoadingWordOptions = false;
        });
        _validateWordOptions(); // Validate after setting options
        debugPrint('[TapInterface] Initial UI set with exactly ${_wordOptions.length} word options');
      }
      
    } catch (e) {
      debugPrint('[TapInterface] ERROR in initial freestyle options: $e');
      if (mounted) {
        final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        setState(() {
          _isLoadingWordOptions = false;
          _wordOptions = _deduplicateWords(_getFallbackWordOptions().take(requiredWordCount).toList());
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
    if (lowerQuestion.contains('superhero') || lowerQuestion.contains('super hero')) {
      return 'superheroes and comic book characters';
    }
    
    // Favorite [specific thing] questions - extract the specific topic
    if (lowerQuestion.contains('favorite') || lowerQuestion.contains('favourite')) {
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
    if (lowerQuestion.contains('vacation') || lowerQuestion.contains('holiday')) {
      return 'vacation destinations and travel places';
    }
    
    // Food related
    if (lowerQuestion.contains('eat') || lowerQuestion.contains('food') || 
        lowerQuestion.contains('dinner') || lowerQuestion.contains('lunch') || 
        lowerQuestion.contains('breakfast') || lowerQuestion.contains('snack')) {
      return 'foods and meals';
    }
    
    // Activity related
    if (lowerQuestion.contains('play') || lowerQuestion.contains('game') || 
        lowerQuestion.contains('activity') || lowerQuestion.contains('do')) {
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
        .replaceAll(RegExp(r'\b(what|where|when|who|why|how|do|does|did|is|are|was|were|can|could|would|should)\b'), '')
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
      debugPrint('🔧 DEDUPLICATION: Removed ${duplicatesRemoved.length} duplicates: $duplicatesRemoved');
      debugPrint('🔧 DEDUPLICATION: Original count: ${words.length}, Final count: ${deduplicatedWords.length}');
      
      // Show detailed duplicate information
      for (final entry in duplicateDetails.entries) {
        final baseWord = entry.key;
        final variants = entry.value;
        debugPrint('🔧 DUPLICATE FOUND: "$baseWord" had variants: ${variants.join(", ")}');
      }
      
      // Show full input list for debugging
      debugPrint('🔧 DEDUPLICATION INPUT: $words');
      debugPrint('🔧 DEDUPLICATION OUTPUT: $deduplicatedWords');
    }
    
    return deduplicatedWords;
  }

  /// Validates if words are appropriate for the given category
  List<String> _validateWordsForCategory(List<String> words, String categoryLabel) {
    final validWords = <String>[];
    final inappropriateWords = <String>[];
    
    // Define category-specific validation rules
    final categoryLower = categoryLabel.toLowerCase();
    
    for (final word in words) {
      final wordLower = word.toLowerCase();
      bool isAppropriate = true;
      
      if (categoryLower.contains('number') || categoryLower.contains('amount') || categoryLower.contains('quantit')) {
        // For Numbers & Quantities category, only allow actual numbers and quantity words
        final numberWords = [
          'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
          'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
          'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand', 'million',
          'many', 'few', 'some', 'all', 'none', 'more', 'less', 'most', 'least', 'several', 'couple',
          'half', 'whole', 'quarter', 'third', 'first', 'second', 'last', 'next', 'another', 'both',
          'single', 'double', 'triple', 'multiple', 'enough', 'plenty', 'empty', 'full', 'extra'
        ];
        isAppropriate = numberWords.contains(wordLower) || RegExp(r'^\d+$').hasMatch(wordLower);
        
        // Also reject obvious non-number words like sports teams or places
        final inappropriateForNumbers = [
          'broncos', 'disney', 'world', 'park', 'team', 'game', 'movie', 'show', 'place', 'location'
        ];
        if (inappropriateForNumbers.any((inappropriate) => wordLower.contains(inappropriate))) {
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
      debugPrint('[TapInterface] 🚨 FILTERED OUT inappropriate words for "$categoryLabel": $inappropriateWords');
      debugPrint('[TapInterface] ✅ KEEPING valid words for "$categoryLabel": ${validWords.take(10).toList()}...');
    }
    
    return validWords;
  }

  List<String> _getFallbackWordOptions() {
    // Return comprehensive word pool for fallback exclusion logic
    return [
      // Basic communication
      'I', 'want', 'need', 'like', 'go', 'help', 'please', 'thank', 'you',
      'yes', 'no', 'good', 'bad', 'more', 'stop', 'eat', 'drink', 'play',
      'home', 'work', 'school', 'happy', 'sad', 'tired', 'done', 'okay',
      
      // Extended basic words
      'can', 'will', 'have', 'get', 'see', 'know', 'think', 'feel', 'look',
      'come', 'here', 'there', 'now', 'later', 'today', 'tomorrow', 'yesterday',
      'up', 'down', 'in', 'out', 'on', 'off', 'big', 'small', 'hot', 'cold',
      
      // Actions
      'walk', 'run', 'sit', 'stand', 'read', 'write', 'watch', 'listen',
      'talk', 'call', 'text', 'drive', 'cook', 'clean', 'sleep', 'wake',
      
      // People and relationships
      'mom', 'dad', 'family', 'friend', 'teacher', 'doctor', 'person', 'baby',
      'child', 'man', 'woman', 'boy', 'girl', 'everyone', 'someone', 'nobody',
      
      // Places
      'house', 'room', 'kitchen', 'bathroom', 'bedroom', 'outside', 'inside',
      'store', 'park', 'hospital', 'restaurant', 'car', 'bus', 'train',
      
      // Time and frequency
      'always', 'never', 'sometimes', 'often', 'soon', 'before', 'after',
      'first', 'last', 'next', 'again', 'still', 'already', 'finish',
      
      // Feelings and states
      'angry', 'excited', 'worried', 'scared', 'proud', 'calm', 'confused',
      'surprised', 'lonely', 'grateful', 'nervous', 'relaxed', 'hurt', 'love',
      
      // Questions and responses
      'what', 'where', 'when', 'why', 'how', 'who', 'which', 'maybe',
      'sure', 'sorry', 'excuse', 'welcome', 'goodbye', 'hello', 'hi'
    ];
  }

  List<String> _getFallbackPhraseOptions() {
    // Return comprehensive phrase pool for fallback when LLM is unavailable
    return [
      'Hello there', 'How are you?', 'I am fine', 'Thank you very much', 'Please help me',
      'Yes, that sounds good', 'No, I don\'t think so', 'I would like that', 'Can you help?',
      'I am hungry', 'I want to go', 'I need to rest', 'That was great', 'I feel good',
      'See you later', 'Good morning', 'Good afternoon', 'Good evening', 'Have a nice day',
      'I am tired', 'I am happy', 'I am sad', 'I am excited', 'Let me think',
      'That\'s interesting', 'I understand', 'I don\'t understand', 'Can you repeat?', 'Excuse me',
      'I\'m sorry', 'No problem', 'You\'re welcome', 'Nice to meet you', 'Take care',
      'I love you', 'I miss you', 'How was your day?', 'What are you doing?', 'Where are you going?',
      'I want to eat', 'I want to drink', 'I want to sleep', 'I want to play', 'I want to work',
      'I am done', 'I am finished', 'I am ready', 'Wait for me', 'I am coming',
    ];
  }



  Future<void> _loadInitialPhraseOptions({Map<String, dynamic>? contextData}) async {
    try {
      debugPrint('[TapInterface] Loading initial phrase options...');
      setState(() {
        _isLoadingPhraseOptions = true;
      });

      // Generate basic phrase options for the top 2 rows using the new method with mood context
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      
      String initialContext = 'general conversation starters and common phrases';
      
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
          initialContext = 'conversation starters and phrases for someone ${contextParts.join(' ')}';
        }
      }
      
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        initialContext += ' while feeling $currentMood';
      }
      
      if (mounted) {
        try {
          final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
          final requiredPhraseCount = userSettings.settings?.llmOptions ?? 10;
          
          final phraseOpts = await _tapService.generateLLMPhraseOptions(
            context: initialContext,
            maxOptions: requiredPhraseCount + 10, // Request extra to ensure we have enough
            currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
          );
          
          if (mounted) {
            // Take exactly the required number of options for display (leaving 1 slot for Something Else button)
            List<Map<String, String>> initialPhraseOptions = phraseOpts.take(requiredPhraseCount).toList();
            
            // If we don't have enough options, supplement with fallback
            if (initialPhraseOptions.length < requiredPhraseCount) {
              debugPrint('[TapInterface] Only have ${initialPhraseOptions.length} initial phrase options, need $requiredPhraseCount. Adding fallbacks...');
              final currentTexts = initialPhraseOptions.map((p) => p['fullText'] ?? '').toSet();
              final fallbackPhraseTexts = [
                'Hello there', 'How are you doing?', 'Thank you very much', 'Please help me',
                'Yes, that sounds good', 'No, I don\'t think so', 'I need help', 'That\'s great',
                'I understand', 'Let me think', 'Good morning', 'Good afternoon', 'Good evening',
                'See you later', 'Have a nice day', 'Take care', 'You\'re welcome'
              ];
              final additionalOptions = fallbackPhraseTexts
                  .where((text) => !currentTexts.contains(text))
                  .take(requiredPhraseCount - initialPhraseOptions.length)
                  .map((text) => {
                    'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
                    'fullText': text,
                  }).toList();
              initialPhraseOptions.addAll(additionalOptions);
              debugPrint('[TapInterface] Added ${additionalOptions.length} fallback phrase options, total now: ${initialPhraseOptions.length}');
            }
            
            setState(() {
              _phraseOptions = initialPhraseOptions;
            });
            debugPrint('[TapInterface] Loaded exactly ${_phraseOptions.length} phrase options for display');
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
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                    final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
                    final tapPictogramsEnabled = !tapPictogramsDisabled;
                    final tapSightWordLogicEnabled = !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);
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
                        final headerTextColor = Colors.purple[700] ?? Colors.purple.shade700;
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
                              : Colors.purple[300] ?? Colors.purple.shade300,
                          fontSize: 18,
                            enablePictograms: tapPictogramsEnabled,
                          sightWordGradeLevel: userSettings?.sightWordGradeLevel,
                            enableSightWords: tapSightWordLogicEnabled,
                          padding: const EdgeInsets.all(2),
                          assignedImageUrl: category.imageUrl, // Pass assigned image URL from database
                          shouldLogMissing: false, // Don't log missing images for category navigation buttons
                        );
                      }).toList(),
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
    debugPrint('[TapInterface] Category: ${category.label} (ID: ${category.id})');
    
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

    // CACHE DISABLED: Always reload to generate fresh options
    /*
    // Check cache first
    if (_categoryPhraseCache.containsKey(category.id) && _categoryWordCache.containsKey(category.id)) {
      debugPrint('[TapInterface] ⚡ Using cached options for category: ${category.label}');
      setState(() {
        _selectedCategory = category;
        _phraseOptions = _categoryPhraseCache[category.id]!;
        _wordOptions = _categoryWordCache[category.id]!;
        _wordKeywords = _categoryWordKeywordsCache[category.id] ?? {};
        _textPromptUsed = false;
        _isLoadingPhraseOptions = false;
        _isLoadingWordOptions = false;
      });
      return;
    }
    */

    debugPrint('[TapInterface] Setting _selectedCategory to: ${category.label}');
    setState(() {
      _selectedCategory = category;
      _currentQuestion = ''; // Clear question when entering category mode
      // Don't block the whole UI, just the sections
      _isLoadingPhraseOptions = true;
      _isLoadingWordOptions = true;
      _phraseOptions = [];
      _wordOptions = [];
      _textPromptUsed = false;
    });

    // We need to know if we are still on the same category when results come back
    final String targetCategoryId = category.id;

    // 1. Load Phrases
    _loadCategoryPhrases(category).then((phrases) {
      debugPrint('[TapInterface] 🕒 Phrases loaded in ${stopwatch.elapsedMilliseconds}ms');
      if (!mounted) return;
      if (_selectedCategory?.id != targetCategoryId) {
        debugPrint('[TapInterface] ⚠️ Ignoring phrase results for old category');
        return;
      }
      
      setState(() {
        _phraseOptions = phrases;
        // _categoryPhraseCache[targetCategoryId] = phrases; // Cache disabled
        _isLoadingPhraseOptions = false;
      });
    }).catchError((e) {
      debugPrint('[TapInterface] ❌ Error loading phrases: $e');
      if (mounted && _selectedCategory?.id == targetCategoryId) {
        setState(() {
           _isLoadingPhraseOptions = false;
        });
      }
    });

    // 2. Load Words
    _loadCategoryWords(category).then((result) {
      debugPrint('[TapInterface] 🕒 Words loaded in ${stopwatch.elapsedMilliseconds}ms');
      if (!mounted) return;
      if (_selectedCategory?.id != targetCategoryId) {
        debugPrint('[TapInterface] ⚠️ Ignoring word results for old category');
        return;
      }

      final words = result['words'] as List<String>;
      final keywords = result['keywords'] as Map<String, List<String>>;
      
      setState(() {
        _wordOptions = words;
        _wordKeywords = keywords;
        // _categoryWordCache[targetCategoryId] = words; // Cache disabled
        // _categoryWordKeywordsCache[targetCategoryId] = keywords; // Cache disabled
        _isLoadingWordOptions = false;
        
        // IMPORTANT: Clear session-tracked missing images when loading fresh words for new category
        // This allows us to log any missing images from this category's word set
        _globalSessionLoggedMissingImages.clear();
        debugPrint('📋 Cleared session-tracked missing images for new category: ${category.label}');
      });
    }).catchError((e) {
      debugPrint('[TapInterface] ❌ Error loading words: $e');
      if (mounted && _selectedCategory?.id == targetCategoryId) {
         // Fallback for words
        final fallbackOptions = _getFallbackOptionsForCategory(category.label, isWords: true);
        setState(() {
          _wordOptions = _deduplicateWords(fallbackOptions);
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
              });
              Navigator.pop(context);
              
              // Announce the word
              _announceViaBackend(word);
              
              // Refresh word options
              _loadWordOptionsBasedOnBuildSpace();
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
              announceFunction: (text, {routing = 'system', speechRate, showSpeechBubble = false}) async {
                await _announceViaBackendSimple(text, routing: routing, preserveMicrophoneSession: true);
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
           debugPrint('🔄 TAP INTERFACE: Returned from mood selection, refreshing settings...');
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

  Future<List<Map<String, String>>> _loadCategoryPhrases(TapInterfaceCategory category) async {
    // Always try to load category-specific phrases, even if no explicit llmPrompt
    // NOTE: Static options are now used for WORDS, not phrases, per user request.
    // Phrases should use llmPrompt or label.
    
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      
      String categoryContext;
      if (category.hasLLMQuery) {
        categoryContext = category.llmPrompt!;
      } else {
        // Generate more specific contextual prompt from category name
        switch (category.label.toLowerCase()) {
          case 'food':
          case 'foods':
            categoryContext = 'phrases for ordering food, expressing food preferences, and talking about meals';
            break;
          case 'activities':
          case 'activity':
            categoryContext = 'phrases for suggesting activities, talking about hobbies, and expressing interests';
            break;
          case 'people':
            categoryContext = 'phrases for talking about family, friends, and people in your life';
            break;
          case 'places':
            categoryContext = 'phrases for talking about locations, directions, and where you want to go';
            break;
          case 'actions':
            categoryContext = 'phrases for expressing actions, things you want to do, and movement';
            break;
          case 'needs':
          case 'wants':
            categoryContext = 'phrases for expressing needs, wants, and requests for help';
            break;
          case 'positive':
            categoryContext = 'positive adjectives and phrases for expressing approval, compliments, and good feelings';
            break;
          default:
            categoryContext = 'conversation phrases and expressions related to ${category.label.toLowerCase()}';
        }
      }
      
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        categoryContext = '$categoryContext appropriate for someone feeling $currentMood';
      }
      
      final phraseOpts = await _tapService.generateLLMPhraseOptions(
        context: categoryContext,
        maxOptions: 25,
        currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
      ).timeout(const Duration(seconds: 10));
      
      List<Map<String, String>> categoryPhraseOptions = phraseOpts.take(17).toList();
      
      // Supplement with fallbacks if needed
      if (categoryPhraseOptions.length < 17) {
        final currentTexts = categoryPhraseOptions.map((p) => p['fullText'] ?? '').toSet();
        final fallbackOptions = _getFallbackOptionsForCategory(category.label, isWords: false);
        final additionalOptions = fallbackOptions
            .where((text) => !currentTexts.contains(text))
            .take(17 - categoryPhraseOptions.length)
            .map((text) => {
              'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
              'fullText': text,
            }).toList();
        categoryPhraseOptions.addAll(additionalOptions);
      }
      
      return categoryPhraseOptions;
    } catch (e) {
      debugPrint('🚨 PHRASE DEBUG: LLM phrase generation FAILED: $e');
      // Fallback to generic phrases, NOT static options (which are for Words)
      final fallbackPhrases = _getFallbackOptionsForCategory(category.label, isWords: false);
      return fallbackPhrases.map((text) => {
        'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
        'fullText': text,
      }).toList();
    }
  }

  Future<Map<String, dynamic>> _loadCategoryWords(TapInterfaceCategory category) async {
    List<String> wordOpts = [];
    Map<String, List<String>> keywordsMap = {};
    
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      
      // Check for static options first (per user request: Static Options -> Words section)
      if (category.hasStaticOptions) {
        debugPrint('[TapInterface] Using static options for Words section: ${category.staticOptions}');
        final staticWords = category.staticOptionsList;
        
        // Create simple keywords map (empty for now as static options don't have keywords yet)
        for (var word in staticWords) {
          keywordsMap[word] = [];
        }
        
        return {
          'words': _deduplicateWords(staticWords.take(requiredWordCount).toList()),
          'keywords': keywordsMap
        };
      }

      String promptText;
      if (category.wordsPrompt != null && category.wordsPrompt!.isNotEmpty) {
        promptText = category.wordsPrompt!;
      } else {
        promptText = category.label;
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          promptText = '${category.label} appropriate for someone feeling $currentMood';
        }
      }
      
      if (category.wordsPrompt != null && category.wordsPrompt!.isNotEmpty) {
        final customWordResults = await _tapService.generateCustomWordOptions(
          prompt: category.wordsPrompt!,
          maxOptions: requiredWordCount + 10,
        ).timeout(const Duration(seconds: 10));
        
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
        wordOpts = await _tapService.generateCategoryWords(
          category: promptText,
          buildSpaceContent: _buildSpaceText,
          excludeWords: [],
          maxOptions: requiredWordCount + 10,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        ).timeout(const Duration(seconds: 10));
      }
      
      // Validate and deduplicate
      final validatedWords = _validateWordsForCategory(wordOpts, category.label);
      final deduplicatedWords = _deduplicateWords(validatedWords);
      
      List<String> finalWordOptions = deduplicatedWords.take(requiredWordCount).toList();
      
      // Fallbacks
      if (finalWordOptions.length < requiredWordCount) {
        final currentWordsLower = finalWordOptions.map((w) => w.toLowerCase()).toSet();
        final fallbackOptions = _getFallbackOptionsForCategory(category.label, isWords: true);
        final additionalOptions = fallbackOptions
            .where((word) => !currentWordsLower.contains(word.toLowerCase()))
            .take(requiredWordCount - finalWordOptions.length)
            .toList();
        finalWordOptions.addAll(additionalOptions);
      }
      
      return {
        'words': finalWordOptions, // Already deduplicated, no need to do it again
        'keywords': keywordsMap
      };
    } catch (e) {
      debugPrint('TapInterface: Words API failed: $e');
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      final fallbackWords = _getFallbackOptionsForCategory(category.label, isWords: true);
      return {
        'words': _deduplicateWords(fallbackWords.take(requiredWordCount).toList()),
        'keywords': <String, List<String>>{}
      };
    }
  }

  List<String> _getFallbackOptionsForCategory(String categoryLabel, {bool isWords = false}) {
    switch (categoryLabel.toLowerCase()) {
      case 'feelings':
        if (isWords) {
          return ['happy', 'sad', 'angry', 'excited', 'tired', 'worried', 'scared', 'proud', 'frustrated', 'calm', 'confused', 'surprised', 'lonely', 'grateful', 'hopeful', 'disappointed', 'relaxed', 'nervous', 'content', 'jealous', 'embarrassed', 'curious', 'bored', 'amazed', 'hurt', 'loved', 'stressed'];
        } else {
          return ['I feel happy', 'I am sad', 'I feel angry', 'I am excited', 'I am tired', 'I feel worried', 'I am scared', 'I feel proud', 'I am frustrated', 'I feel calm', 'I am confused', 'I feel surprised', 'I am lonely', 'I feel grateful', 'I feel hopeful', 'I am disappointed', 'I feel relaxed', 'I am nervous'];
        }
      case 'actions':
        if (isWords) {
          return ['go', 'come', 'walk', 'run', 'sit', 'stand', 'eat', 'drink', 'sleep', 'play', 'work', 'read', 'write', 'watch', 'listen', 'talk', 'help', 'stop', 'start', 'move', 'dance', 'sing', 'cook', 'clean', 'drive', 'call', 'text'];
        } else {
          return ['I want to go', 'I will come', 'Let me walk', 'I can run', 'I need to sit', 'I will stand', 'I want to eat', 'I need to drink', 'I want to sleep', 'I want to play', 'I need to work', 'I want to read', 'I will write', 'I want to watch', 'I will listen', 'I want to talk', 'I need help', 'Please stop'];
        }
      case 'people':
        if (isWords) {
          return ['mom', 'dad', 'sister', 'brother', 'friend', 'teacher', 'doctor', 'family', 'baby', 'child', 'person', 'everyone', 'someone', 'me', 'you', 'we', 'they', 'grandma', 'grandpa', 'cousin', 'uncle', 'aunt', 'neighbor', 'classmate', 'coworker', 'boss', 'student'];
        } else {
          return ['I want mom', 'I need dad', 'My sister', 'My brother', 'My friend', 'The teacher', 'See doctor', 'My family', 'The baby', 'That child', 'This person', 'I see everyone', 'I need someone', 'It is me', 'I see you', 'We are here', 'They are there', 'My grandma'];
        }
      case 'places':
        if (isWords) {
          return ['home', 'school', 'work', 'store', 'park', 'hospital', 'restaurant', 'bathroom', 'bedroom', 'kitchen', 'outside', 'inside', 'here', 'there', 'city', 'country', 'beach', 'library', 'church', 'office', 'car', 'bus', 'train', 'airplane', 'hotel', 'gym', 'pool'];
        } else {
          return ['I want to go home', 'I am at school', 'I go to work', 'Go to store', 'I like the park', 'Go to hospital', 'Go to restaurant', 'I need bathroom', 'In my bedroom', 'In the kitchen', 'I go outside', 'I am inside', 'I am here', 'I go there', 'In the city', 'In the country', 'At the beach', 'Go to library'];
        }
      case 'food':
      case 'foods':
        if (isWords) {
          return ['pizza', 'sandwich', 'soup', 'salad', 'burger', 'chicken', 'fish', 'pasta', 'rice', 'bread', 'fruit', 'apple', 'banana', 'water', 'juice', 'milk', 'coffee', 'tea', 'cake', 'cookie', 'ice cream', 'snack', 'breakfast', 'lunch', 'dinner', 'hungry', 'thirsty'];
        } else {
          return ['I want pizza', 'I like sandwiches', 'I want soup', 'I need salad', 'I want burger', 'I like chicken', 'I want fish', 'I need pasta', 'I want rice', 'I like bread', 'I want fruit', 'I like apples', 'I want banana', 'I need water', 'I want juice', 'I need milk', 'I want coffee', 'I like tea'];
        }
      case 'activities':
      case 'activity':
        if (isWords) {
          return ['play', 'game', 'music', 'dance', 'sing', 'read', 'book', 'movie', 'TV', 'computer', 'phone', 'walk', 'run', 'swim', 'bike', 'drive', 'cook', 'clean', 'shop', 'visit', 'party', 'fun', 'hobby', 'sport', 'exercise', 'rest', 'relax'];
        } else {
          return ['I want to play', 'I like games', 'I want music', 'I love to dance', 'I like to sing', 'I want to read', 'I need a book', 'I want movie', 'I watch TV', 'I use computer', 'I need phone', 'I want to walk', 'I like to run', 'I want to swim', 'I ride bike', 'I want to cook', 'I will clean', 'I go shopping'];
        }
      case 'needs':
      case 'wants':
        if (isWords) {
          return ['help', 'water', 'food', 'rest', 'sleep', 'bathroom', 'medicine', 'phone', 'money', 'time', 'space', 'quiet', 'comfort', 'support', 'love', 'attention', 'break', 'change', 'choice', 'freedom', 'safety', 'warmth', 'cool', 'light', 'dark', 'clean', 'fix'];
        } else {
          return ['I need help', 'I want water', 'I need food', 'I need rest', 'I want to sleep', 'I need bathroom', 'I need medicine', 'I want my phone', 'I need money', 'I need time', 'I need space', 'I want quiet', 'I need comfort', 'I want support', 'I need love', 'I want attention', 'I need a break'];
        }
      case 'positive':
        if (isWords) {
          return ['awesome', 'amazing', 'great', 'fantastic', 'wonderful', 'excellent', 'perfect', 'brilliant', 'outstanding', 'incredible', 'superb', 'marvelous', 'terrific', 'fabulous', 'spectacular', 'phenomenal', 'magnificent', 'exceptional', 'remarkable', 'impressive', 'beautiful', 'lovely', 'gorgeous', 'stunning', 'breathtaking', 'cool', 'sweet'];
        } else {
          return ['That is awesome', 'This is amazing', 'That is great', 'This is fantastic', 'That is wonderful', 'This is excellent', 'That is perfect', 'This is brilliant', 'That is outstanding', 'This is incredible', 'That is superb', 'This is marvelous', 'That is terrific', 'This is fabulous', 'That is spectacular', 'This is phenomenal', 'That is magnificent', 'This is exceptional'];
        }
      case 'numbers':
      case 'numbers & quantities':
      case 'numbers and quantities':
      case 'amounts':
      case 'quantity':
      case 'quantities':
        if (isWords) {
          return ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'many', 'few', 'some', 'all', 'none', 'more', 'less', 'most', 'least', 'half', 'whole', 'first', 'last', 'second', 'third'];
        } else {
          return ['I want one', 'Give me two', 'I need three', 'I want four', 'I see five', 'I need six', 'I want many', 'I have few', 'I want some', 'I need all', 'I have none', 'I want more', 'I need less', 'I want most', 'That is first', 'That is last', 'I want half', 'I need whole'];
        }
      default:
        // For unknown categories, generate generic but more varied options
        debugPrint('🚨 PHRASE DEBUG: Unknown category "$categoryLabel", using generic options');
        if (isWords) {
          return ['help', 'please', 'thank', 'yes', 'no', 'good', 'okay', 'done', 'more', 'stop', 'go', 'come', 'want', 'need', 'like', 'happy', 'sad', 'tired', 'finished', 'wait', 'here', 'there', 'now', 'later', 'big', 'small', 'hot', 'cold'];
        } else {
          return ['I need help', 'Please help me', 'Thank you', 'Yes please', 'No thank you', 'That is good', 'That is okay', 'I am done', 'I want more', 'Please stop', 'I want to go', 'Please come here', 'I want that', 'I need this', 'I like it', 'I am happy', 'I feel sad', 'I am tired'];
        }
    }
  }

  void _showCategoryModal(TapInterfaceCategory category) {
    // Trigger custom image preloading for this category's children if not done yet
    _preloadModalCustomImages(category);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
        final userSettings = settingsProvider.settings;
        
        final adminColumns = userSettings?.gridColumns ?? 6;
        final modalColumns = _getEffectiveMainContentColumns(adminColumns); // Use same column count as main page
        
        // Make modal width responsive to button size settings
        // Base calculation: larger buttons (fewer columns) = larger modal
        final baseModalWidth = 300.0; // Minimum modal width
        final widthPerColumn = 60.0; // Additional width per column (keep buttons same size)
        final responsiveModalWidth = baseModalWidth + (modalColumns * widthPerColumn);
        final responsiveModalHeight = responsiveModalWidth * 0.8; // Maintain aspect ratio
        
        // Scale up the container to show more buttons (50% larger)
        final scaledWidth = responsiveModalWidth * 1.5;
        final scaledHeight = responsiveModalHeight * 1.5;
        
        debugPrint('🚨 MODAL DEBUG: Admin gridColumns=$adminColumns, modalColumns=$modalColumns, modalWidth=$scaledWidth');
        
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // Slightly smaller text
                ),
                const SizedBox(height: 12), // Reduced spacing
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: modalColumns, // Same column count as main page
                      childAspectRatio: 1.1, // Same as Words and Phrases sections
                      crossAxisSpacing: 2, // Same spacing as main sections
                      mainAxisSpacing: 2,
                    ),
                    itemCount: category.children.where((child) => !child.hidden).length,
                    itemBuilder: (context, index) {
                      final visibleChildren = category.children.where((child) => !child.hidden).toList();
                      final child = visibleChildren[index];
                      debugPrint('🚨 SUB-MENU BUTTON SETTINGS: userSettings=$userSettings');
                      debugPrint('🚨 SUB-MENU PICTOGRAMS VALUE: ${userSettings?.enablePictograms ?? false} for "${child.label}"');
                      final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
                      final tapPictogramsEnabled = !tapPictogramsDisabled;
                      final tapSightWordLogicEnabled = !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);
                      
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
                        padding: const EdgeInsets.all(2), // Same as main sections
                        assignedImageUrl: child.imageUrl, // Pass the assigned image URL from database
                        shouldLogMissing: false, // Don't log missing images for sub-category navigation buttons
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
      await _announceViaBackend("Nothing to speak");
      return;
    }
    
    debugPrint('[TapInterface] _speakSpeechHistory called - speaking as-is: "$_speechHistory"');
    
    // Always speak as-is (no cleanup)
    String textToSpeak = _speechHistory;
    
    await _announceViaBackend(textToSpeak);
    
    // Add to past speech history
    setState(() {
      _pastSpeechHistory.add(textToSpeak);
    });
    
    debugPrint('[TapInterface] Spoke speech history: "$textToSpeak"');
  }
  
  Future<void> _handleAutoCleanSpeakButtonPress() async {
    if (_speechHistory.trim().isEmpty) {
      await _announceViaBackend("Nothing to speak");
      return;
    }
    
    debugPrint('[TapInterface] Auto Clean + Speak called, starting text cleanup for: "$_speechHistory"');
    
    // Always use LLM cleanup to make text conversational
    String textToSpeak = await _cleanupText(_speechHistory);
    debugPrint('[TapInterface] Auto Clean completed, original="$_speechHistory", cleaned="$textToSpeak"');
    
    if (textToSpeak != _speechHistory) {
      // Update the speech history with cleaned text
      setState(() {
        _speechHistory = textToSpeak;
        _speechHistoryController.text = _speechHistory;
      });
    }
    
    await _announceViaBackend(textToSpeak);
    
    // Add to past speech history
    setState(() {
      _pastSpeechHistory.add(textToSpeak);
    });
    
    debugPrint('[TapInterface] Spoke cleaned speech history: "$textToSpeak"');
  }

  Future<void> _composeEmailWithSpeechText() async {
    final messageBody = _speechHistory.trim();
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false).settings;
    final recipient = (userSettings?.emailDefaultRecipient ?? '').trim();
    final configuredSubject = (userSettings?.emailSubjectTemplate ?? '').trim();
    final subject = configuredSubject.isEmpty ? 'Message from Bravo AAC' : configuredSubject;

    if (messageBody.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to email yet. Build a message first.')),
      );
      return;
    }

    if (!kIsWeb && !Platform.isIOS) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email MVP is currently enabled for iOS only.')),
      );
      return;
    }

    final mailtoUri = Uri(
      scheme: 'mailto',
      path: recipient,
      queryParameters: {
        'subject': subject,
        'body': messageBody,
      },
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
            content: Text('No mail app configured. Message copied to clipboard.'),
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

  Future<void> _speakText(String text) async {
    try {
      await _flutterTts.stop();
      
      // Get user settings for voice configuration
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;
      
      // Always use built-in speaker for tap interface (no audio routing changes)
      await _flutterTts.setSharedInstance(true);
      
      // Configure TTS settings
      if (userSettings != null) {
        debugPrint('[TapInterface] === TTS CONFIGURATION ===');
        debugPrint('[TapInterface] User settings found');
        debugPrint('[TapInterface] Selected voice: "${userSettings.selectedTtsVoiceName}"');
        debugPrint('[TapInterface] Raw speech rate: ${userSettings.speechRate}');
        
        // Set the user's selected voice
        if (userSettings.selectedTtsVoiceName.isNotEmpty) {
          debugPrint('[TapInterface] Setting TTS voice to: ${userSettings.selectedTtsVoiceName}');
          await _flutterTts.setVoice({
            'name': userSettings.selectedTtsVoiceName,
            'locale': 'en-US',
          });
        } else {
          debugPrint('[TapInterface] No voice selected, using default');
        }
        
        // Set speech rate - use the same approach as main.dart
        // Normal range should be 0.5-1.0, with 0.5 being slower and clear
        double speechRate = 0.5; // Default to clear, slower speech like main.dart
        debugPrint('[TapInterface] Setting TTS speech rate to: $speechRate (using main.dart default for clarity)');
        await _flutterTts.setSpeechRate(speechRate);
        
        // Set pitch to normal
        await _flutterTts.setPitch(1.0);
        
        // Get personalVolume from global settings (scanning uses personal volume, not system)
        final personalVolume = userSettings.personalVolume;
        final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
        debugPrint('[TapInterface] Using personalVolume: $personalVolume/10 → TTS volume: $ttsVolume (scanning)');
        await _flutterTts.setVolume(ttsVolume);
      } else {
        debugPrint('[TapInterface] No user settings, using defaults');
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setPitch(1.0);
        // Default using personalVolume if no settings available
        const defaultPersonalVolume = 10;
        await _flutterTts.setVolume((defaultPersonalVolume / 10.0).clamp(0.0, 1.0));
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
        
        debugPrint('[TapInterface] Setting application volume to level: $applicationVolume/10');
        
        if (Platform.isAndroid) {
          await platform.invokeMethod('setApplicationVolume', {'applicationVolume': applicationVolume});
        } else {
          // For iOS, still use setMaxVolume for now (can be enhanced later)
          await platform.invokeMethod('setMaxVolume');
        }
        
        debugPrint('[TapInterface] ✅ Application volume set to $applicationVolume/10 successfully');
        
        // Re-suppress notifications after volume change
        if (!kIsWeb && Platform.isAndroid) {
          try {
            await platform.invokeMethod('suppressNotificationSounds');
            debugPrint('[TapInterface] Re-suppressed notifications after volume change');
          } catch (e) {
            debugPrint('[TapInterface] Failed to re-suppress notifications after volume change: $e');
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
      debugPrint('[TapInterface] Proactively initializing audio session to prevent system voice...');
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
          final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
          await _setApplicationVolume(settings: settingsProvider.settings);
          debugPrint('[TapInterface] Application volume configuration completed');
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
      
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      if (settingsProvider.idToken == null || settingsProvider.idToken!.isEmpty) {
        debugPrint('[TapInterface] Auth not ready for audio priming, skipping');
        return;
      }
      
      // Create a very brief silence (empty audio) to prime the system
      const silentText = " "; // Single space - generates minimal audio
      
      // Use the same TTS method with preserveMicrophoneSession=true
      await _announceViaBackendSimple(silentText, routing: 'system', preserveMicrophoneSession: true);
      
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
  }) async {
    try {
      debugPrint('[TapInterface] 🔊 _announceViaBackend called with text: "$text"');
      
      // Handle [PAUSE] markers (used in jokes and other content)
      if (text.contains('[PAUSE]')) {
        final parts = text.split('[PAUSE]').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        for (int i = 0; i < parts.length; i++) {
          await _announceViaBackend(
            parts[i],
            useSystemVoice: useSystemVoice,
            volumeScale: volumeScale,
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
      debugPrint('[TapInterface] Using full-duplex audio (preserveMicrophoneSession=true) - wake word remains active');
      await _announceViaBackendSimple(
        text,
        routing: 'system',
        preserveMicrophoneSession: true,
        useSystemVoice: useSystemVoice,
        volumeScale: volumeScale,
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
  }) async {
    try {
      debugPrint('[TapInterface] 🎵 _announceViaBackendSimple called with text: "$text", routing: $routing');
      debugPrint('[TapInterface] announceViaBackendSimple: "$text"');
      
      // Suppress Android notification sounds during announcement
      await _suppressAndroidNotificationSounds();
      
      // Initialize audio session on first use (fixes first TTS using system voice)
      if (!_audioSessionInitialized) {
        debugPrint('[TapInterface] First TTS call, initializing audio session...');
        await _initializeAudioSession();
        _audioSessionInitialized = true;
        
        // Add a small delay after initialization to ensure it takes effect
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // Show speech bubble overlay if enabled in settings
      _showSpeechBubbleOverlay(text);
      
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final idToken = settingsProvider.idToken;
      final userId = settingsProvider.userId ?? '';
      
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[TapInterface] Missing auth token, falling back to local TTS');
        await _speakText(text);
        return;
      }
      
      // Include user's voice settings in the request
      final userSettings = settingsProvider.settings;
      final voiceSettings = {
        'text': text, 
        'routing_target': routing,
        if (speechRate != null) 'speech_rate': speechRate,
        if (!useSystemVoice && userSettings?.selectedTtsVoiceName != null && userSettings!.selectedTtsVoiceName.isNotEmpty)
          'voice': userSettings.selectedTtsVoiceName,
        if (!useSystemVoice && userSettings?.speechRate != null)
          'speed': userSettings!.speechRate,
        if (volumeScale != null) 'volume_scale': volumeScale,
      };
      
      debugPrint('[TapInterface] TTS request with voice settings: $voiceSettings');
      
      // Request backend audio using authenticated client (handles token refresh)
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/play-audio',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': userId,
        },
        body: json.encode(voiceSettings),
        timeoutSeconds: 30,
      );
      
      bool backendAudioPlayed = false;
      
      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final base64Audio = RegExp('"audio_data"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audioContent"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        
        debugPrint('[TapInterface] Backend response received, audio data found: ${base64Audio != null}');
        
        if (base64Audio != null && base64Audio.isNotEmpty) {
          final player = AudioPlayer();
          
          try {
            // CRITICAL: Only force speaker routing if NOT preserving microphone session
            // On iPad with tap interface, we need full-duplex (microphone + speaker simultaneously)
            // So we should NOT call forceSpeaker() which may interrupt the microphone
            if (!kIsWeb && Platform.isIOS && !preserveMicrophoneSession) {
              const platform = MethodChannel('audio_routing');
              await platform.invokeMethod('forceSpeaker');
            }
            
            // Create temporary file and play (same approach as grid page)
            final bytes = base64Decode(base64Audio);
            final tempDir = Directory.systemTemp;
            final tempFile = await File('${tempDir.path}/tap_backend_tts.mp3').create();
            await tempFile.writeAsBytes(bytes, flush: true);
            await player.setFilePath(tempFile.path);
            debugPrint('[TapInterface] Audio file set, starting playback...');
            await player.play();
            
            // Wait for completion
            debugPrint('[TapInterface] Waiting for audio to complete...');
            await player.playerStateStream
                .firstWhere((state) => state.processingState == ProcessingState.completed);
            debugPrint('[TapInterface] Audio playback completed, processing...');
            
            // Reset audio routing if not preserving microphone session
            if (!kIsWeb && Platform.isIOS && !preserveMicrophoneSession) {
              const platform = MethodChannel('audio_routing');
              await platform.invokeMethod('resetToDefault');
            }
            
            backendAudioPlayed = true;
            debugPrint('[TapInterface] Backend audio played successfully');
            
            // On iOS with full-duplex mode, the wake word service continues listening automatically
            // since we never disabled wakeWordShouldBeActive in the first place
          } catch (e) {
            debugPrint('[TapInterface] Audio playback failed: $e');
          } finally {
            await player.dispose();
          }
        }
      }
      
      // Simple TTS fallback if backend audio failed
      if (!backendAudioPlayed) {
        debugPrint('[TapInterface] Backend failed, using local TTS fallback');
        await _speakText(text);
        
        // Wake word service continues listening automatically during fallback TTS too
      }
      
    } catch (e) {
      debugPrint('[TapInterface] announceViaBackendSimple exception: $e');
      // Simple fallback
      await _speakText(text);
      
      // Wake word service continues listening automatically
    } finally {
      // Always restore notification sounds
      await _restoreAndroidNotificationSounds();
    }
  }

  Future<void> _playCustomAudio(String audioUrl) async {
    try {
      debugPrint('[TapInterface] 🎵 _playCustomAudio called with URL: "$audioUrl"');
      
      // Ensure audio session is initialized
      if (!_audioSessionInitialized) {
        await _initializeAudioSessionProactively();
      }
      
      final player = AudioPlayer();
      
      try {
        // Force speaker routing before playing (same as TTS)
        if (!kIsWeb && Platform.isIOS) {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('forceSpeaker');
        }
        
        // Check if this is a data URL (base64 encoded)
        if (audioUrl.startsWith('data:audio/')) {
          // Extract base64 data from data URL
          final base64Match = RegExp(r'data:audio/[^;]+;base64,(.+)').firstMatch(audioUrl);
          if (base64Match != null) {
            final base64Audio = base64Match.group(1)!;
            
            // Create temporary file and play (same approach as backend TTS)
            final bytes = base64Decode(base64Audio);
            final tempDir = Directory.systemTemp;
            final tempFile = await File('${tempDir.path}/custom_button_audio_${DateTime.now().millisecondsSinceEpoch}.mp3').create();
            await tempFile.writeAsBytes(bytes, flush: true);
            
            await player.setFilePath(tempFile.path);
            debugPrint('[TapInterface] 🎵 Playing custom audio from temporary file');
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
        await player.playerStateStream
            .firstWhere((state) => state.processingState == ProcessingState.completed);
        
        debugPrint('[TapInterface] ✅ Custom audio playback completed');
        
        // Reset audio routing to default
        if (!kIsWeb && Platform.isIOS) {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
        }
        
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
    debugPrint('[TapInterface] Before reset - Selected category: ${_selectedCategory?.label}');
    debugPrint('[TapInterface] Before reset - Word options count: ${_wordOptions.length}');
    debugPrint('[TapInterface] Before reset - Phrase options count: ${_phraseOptions.length}');
    
    setState(() {
      _speechHistory = "";
      _speechHistoryController.text = "";
      _buildSpaceText = "";
      _buildSpaceController.text = "";
      _selectedCategory = null;
      _isJokesMode = false; // Clear jokes mode on page reset
      _currentQuestion = ''; // Clear question when entering freestyle mode
      _phraseOptions.clear();
      _wordOptions.clear();
      _wordKeywords.clear(); // Clear keywords when clearing word options
      _textPromptUsed = false; // Reset text prompt usage flag
      // _pastSpeechHistory is NOT cleared here - only cleared by History button
    });
    
    // Reload initial options after clearing
    debugPrint('[TapInterface] Page reset, reloading initial options');
    _loadInitialFreestyleOptions();
    _loadInitialPhraseOptions();
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
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      String idToken = settingsProvider.idToken ?? '';
      String aacUserId = settingsProvider.userId ?? '';
      
      // Refresh token before cleanup call
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final refreshedToken = await user.getIdToken(true);
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
            debugPrint('[TapInterface] Token refreshed for cleanup');
          }
        }
      } catch (e) {
        debugPrint('[TapInterface] Token refresh failed for cleanup: $e');
      }
      
      final url = '${EnvironmentConfig.apiBaseUrl}/api/freestyle/cleanup-text';
      final headers = {
        'Authorization': 'Bearer $idToken',
        'X-User-ID': aacUserId,
        'Content-Type': 'application/json',
      };
      final body = json.encode({
        'text_to_cleanup': textToClean,
      });
      
      debugPrint('[TapInterface] Cleanup URL: $url');
      debugPrint('[TapInterface] Cleanup headers: $headers');
      debugPrint('[TapInterface] Cleanup body: $body');
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );
      
      debugPrint('[TapInterface] Cleanup response status: ${response.statusCode}');
      debugPrint('[TapInterface] Cleanup response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final cleanedText = data['cleaned_text'] ?? textToClean;
        debugPrint('[TapInterface] Original text: "$textToClean"');
        debugPrint('[TapInterface] Cleaned text: "$cleanedText"');
        return cleanedText;
      } else {
        debugPrint('[TapInterface] Cleanup failed with status ${response.statusCode}: ${response.body}');
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
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final historyItem =
                        _pastSpeechHistory[_pastSpeechHistory.length - 1 - index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300] ?? Colors.grey.shade300),
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
                            message: 'Speak this item',
                            child: Container(
                              height: 34,
                              width: 40,
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
                                  size: 20,
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
              height: 40,
              width: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[400] ?? Colors.blue.shade400, Colors.blue[600] ?? Colors.blue.shade600],
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
                icon: const Icon(Icons.close, size: 28, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),
          Tooltip(
            message: 'Clear History',
            child: Container(
              height: 40,
              width: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red[400] ?? Colors.red.shade400, Colors.red[600] ?? Colors.red.shade600],
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
                icon: const Icon(Icons.delete_outline, size: 28, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),
        ],
      ),
    );
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
                            _buildKeypadButton('1', pinController, setKeypadState),
                            _buildKeypadButton('2', pinController, setKeypadState),
                            _buildKeypadButton('3', pinController, setKeypadState),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton('4', pinController, setKeypadState),
                            _buildKeypadButton('5', pinController, setKeypadState),
                            _buildKeypadButton('6', pinController, setKeypadState),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton('7', pinController, setKeypadState),
                            _buildKeypadButton('8', pinController, setKeypadState),
                            _buildKeypadButton('9', pinController, setKeypadState),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton('⌫', pinController, setKeypadState, isBackspace: true),
                            _buildKeypadButton('0', pinController, setKeypadState),
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
      debugPrint('Updated Tap Interface admin toolbar PIN (length: ${_currentPIN.length})');
    }
  }

  Future<void> _onAdminButtonPressed(String route) async {
    // Navigate to the admin page and wait for return
    debugPrint('🔄 TAP INTERFACE: Navigating to admin page: $route');
    
    await Navigator.pushNamed(context, route);
    
    // When user returns from admin page, refresh settings
    debugPrint('🔄 TAP INTERFACE: Returned from admin page, refreshing settings...');
    await _refreshSettingsFromAdmin();
    
    // Also refresh content context (location/activity/people)
    await _refreshContentFromAdmin();
    
    // Refresh PIN from settings in case it was changed
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    _updatePINFromSettings(userSettings);
  }

  /// Refresh content context after returning from admin pages
  Future<void> _refreshContentFromAdmin() async {
    try {
      debugPrint('🔄 TAP INTERFACE: Fetching fresh content context from server...');
      
      // Refresh token before API call
      final user = FirebaseAuth.instance.currentUser;
      String idToken = widget.idToken;
      if (user != null) {
        try {
          final refreshedToken = await user.getIdToken(true);
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
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      
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
    try {
      debugPrint('🔄 TAP INTERFACE: Clearing all image caches for fresh startup...');
      
      // Clear pictogram service cache
      await PictogramService.clearGlobalCache();
      
      // Clear custom image service cache
      CustomImageService.clearCache();
      
      debugPrint('✅ TAP INTERFACE: All image caches cleared successfully');
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
      final idToken = await user.getIdToken();
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
          debugPrint('🔄 TapInterface: Navigating to UserSelectionPage with ${userProfiles.length} profiles');
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
            content: Text('Failed to load user accounts (${response.statusCode})'),
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

  Widget _buildOptionsGrid(UserSettings? userSettings, Color headerTextColor) {
    // Check if we have any options to display
    if (_phraseOptions.isEmpty && _wordOptions.isEmpty && !_isLoadingPhraseOptions && !_isLoadingWordOptions) {
      return Center(
        child: Text(
          'No options available',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      );
    }

    return Column(
      key: ValueKey(_optionsRebuildKey), // Force complete rebuild when options change
      children: [
        // Top section: Phrase options - DYNAMIC SIZING
        _buildPhrasesSection(userSettings),
          
        // Bottom section: Word options (like freestyle page) - NON-SCROLLABLE
        if (_wordOptions.isNotEmpty || _isLoadingWordOptions) ...[
            Expanded(
            flex: _calculateWordsSectionFlex(userSettings),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[25] ?? Colors.blue.shade50, Colors.blue[50] ?? Colors.blue.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[300] ?? Colors.blue.shade300, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.2),
                    offset: const Offset(0, 3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Grid content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Stack(
                        children: [
                          // Show grid if we have options (even if loading)
                          if (_wordOptions.isNotEmpty || !_isLoadingWordOptions)
                            GridView.count(
                              physics: const AlwaysScrollableScrollPhysics(), // Enable scrolling for dynamic content
                              padding: EdgeInsets.zero, // Remove default padding that creates space above
                              crossAxisCount: _getEffectiveMainContentColumns(userSettings?.gridColumns ?? 6), // Dynamic columns accounting for Categories
                              childAspectRatio: 1.1,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                              children: List.generate(
                                // When answering a question, use actual word count; otherwise use freestyleOptions setting
                                _currentQuestion.isNotEmpty 
                                  ? _wordOptions.length + 1  // Actual words + Something Else button
                                  : (userSettings?.freestyleOptions ?? 29) + 1, // Setting + Something Else button
                                (index) {
                                  final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
                                  final tapPictogramsEnabled = !tapPictogramsDisabled;
                                  final tapSightWordLogicEnabled = !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);
                                  final maxIndex = _currentQuestion.isNotEmpty 
                                    ? _wordOptions.length 
                                    : (userSettings?.freestyleOptions ?? 29);
                                  
                                  if (index == maxIndex) {
                                    // Last slot - "Something Else" button
                                    return TapInterfaceButton(
                                      label: 'Something Else',
                                      onPressed: () => _loadMoreWordOptions(),
                                      backgroundColor: Colors.blue[50] ?? Colors.blue.shade50,
                                      foregroundColor: Colors.black87,
                                      borderColor: Colors.blue[300] ?? Colors.blue.shade300,
                                      fontSize: 8,
                                      enablePictograms: tapPictogramsEnabled,
                                      sightWordGradeLevel: userSettings?.sightWordGradeLevel,
                                      enableSightWords: tapSightWordLogicEnabled,
                                      padding: const EdgeInsets.all(2),
                                      shouldLogMissing: false, // Don't log missing images for UI control buttons
                                    );
                                  } else if (index < _wordOptions.length) {
                                    final wordOption = _wordOptions[index];
                                    final wordOptionKey =
                                        'word::${_selectedCategory?.id ?? 'none'}::$wordOption';
                                    final isPreviewArmed = _isAudioSurfingEnabled &&
                                        _audioSurfingPreviewOptionKey == wordOptionKey;
                                    final keywords = _wordKeywords[wordOption];
                                    return TapInterfaceButton(
                                      label: wordOption,
                                      onPressed: () => _handleWordOptionTap(wordOption),
                                      backgroundColor: isPreviewArmed
                                        ? (Colors.amber[300] ?? Colors.amber.shade300)
                                          : (Colors.blue[50] ?? Colors.blue.shade50),
                                      foregroundColor: Colors.black87,
                                      borderColor: isPreviewArmed
                                        ? (Colors.deepOrange[700] ?? Colors.deepOrange.shade700)
                                          : (Colors.blue[300] ?? Colors.blue.shade300),
                                      fontSize: 8,
                                      enablePictograms: tapPictogramsEnabled,
                                      sightWordGradeLevel: userSettings?.sightWordGradeLevel,
                                      enableSightWords: tapSightWordLogicEnabled,
                                      padding: const EdgeInsets.all(2),
                                      keywords: keywords, // Pass keywords for better image matching
                                      shouldLogMissing: false, // Don't log missing images for LLM/backend-generated words
                                    );
                                  } else {
                                    // Empty slot
                                    return Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.blue[200] ?? Colors.blue.shade200),
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
                                },
                              ),
                            ),
                            
                          // Show loading indicator
                          if (_isLoadingWordOptions)
                            _wordOptions.isEmpty
                                ? const Center(child: CircularProgressIndicator())
                                : const Positioned(
                                    top: 0, left: 0, right: 0,
                                    child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent)
                                  ),
                        ],
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ],
      ],
    );
  }

  // --- Speech Bubble Overlay Methods (like main.dart) ---
  
  void _showSpeechBubbleOverlay(String text) {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    
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
    
    debugPrint('TapInterface: Speech bubble displayed for ${duration}ms: "$text"');
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

      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;

      await _flutterTts.setSharedInstance(true);
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setPitch(1.0);

      final baseVolume = ((userSettings?.personalVolume ?? 10) / 10.0).clamp(0.0, 1.0);
      final previewVolume = (baseVolume * 0.30).clamp(0.0, 0.35);
      await _flutterTts.setVolume(previewVolume);

      final ttsCompleter = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      });

      debugPrint('[TapInterface] Audio Surfing whisper preview volume=$previewVolume for "$text"');
      await _flutterTts.speak(text);

      final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final estimatedDurationMs = (wordCount * 700) + 3000;
      final timeout = Duration(milliseconds: estimatedDurationMs.clamp(5000, 60000));
      try {
        await ttsCompleter.future.timeout(timeout);
      } on TimeoutException {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      }

      _flutterTts.setCompletionHandler(() {});
    } catch (e) {
      debugPrint('[TapInterface] Audio Surfing preview failed, falling back to normal announce: $e');
      await _announceViaBackend(text);
    }
  }

  Future<bool> _handleAudioSurfingTap(String optionKey, String announceText) async {
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
      _statusMessage = 'Audio Surfing preview. Tap the same option again to select it.';
    });

    _showSpeechBubbleOverlay(announceText);
    await _announceAudioSurfPreview(announceText);
    return false;
  }

  // --- Option Tap Handlers ---

  Future<void> _handlePhraseOptionTap(String fullText) async {
    debugPrint('[TapInterface] === PHRASE OPTION TAPPED ===');
    debugPrint('[TapInterface] Phrase option tapped: "$fullText"');
    debugPrint('[TapInterface] Current speech history BEFORE: "$_speechHistory"');
    debugPrint('[TapInterface] Speech history controller BEFORE: "${_speechHistoryController.text}"');
    
    final proceedWithSelection = await _handleAudioSurfingTap('phrase::$fullText', fullText);
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
      debugPrint('[TapInterface] Added to _pastSpeechHistory: "$fullText" (total: ${_pastSpeechHistory.length})');
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
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    chatService.recordChatHistoryWithProvider(
      question: '',
      response: fullText.trim(),
      userSettingsProvider: userSettings,
    ).catchError((error) {
      print('❌ Failed to record phrase chat history: $error');
    });
    
    debugPrint('[TapInterface] Speech history AFTER: "$_speechHistory"');
    debugPrint('[TapInterface] Speech history controller AFTER: "${_speechHistoryController.text}"');
    debugPrint('[TapInterface] Build space text AFTER: "$_buildSpaceText"');
    
    debugPrint('[TapInterface] Added phrase to speech history: "$_speechHistory"');
    
    // Update status message
    setState(() {
      _statusMessage = 'Phrase added to speech. Say "${_getFormattedWakeWord()}" to ask a question.';
    });
    
    // Regenerate word options based on new speech history content
    await _loadWordOptionsBasedOnBuildSpace();
    
    // Regenerate phrase options based on new speech history content
    await _loadPhraseOptionsBasedOnBuildSpace();
  }

  Future<void> _handleWordOptionTap(String word) async {
    debugPrint('[TapInterface] === WORD OPTION TAPPED ===');
    debugPrint('[TapInterface] Word option tapped: "$word"');
    debugPrint('[TapInterface] Current speech history BEFORE: "$_speechHistory"');
    debugPrint('[TapInterface] Speech history controller BEFORE: "${_speechHistoryController.text}"');
    debugPrint('[TapInterface] Selected category wordsPrompt: "${_selectedCategory?.wordsPrompt}"');
    debugPrint('[TapInterface] Text prompt already used: $_textPromptUsed');
    
    final proceedWithSelection = await _handleAudioSurfingTap(
      'word::${_selectedCategory?.id ?? 'none'}::$word',
      word,
    );
    if (!proceedWithSelection) {
      return;
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
      debugPrint('[TapInterface] Text completion (first use): "${_selectedCategory!.wordsPrompt!}" + "$word" = "$textToAdd"');
    } else {
      // For subsequent selections, just use the word without the prompt
      debugPrint('[TapInterface] Using word only (prompt already used or not available): "$word"');
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
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    chatService.recordChatHistoryWithProvider(
      question: '',
      response: textToAnnounce.trim(), // Use the announced text for chat history
      userSettingsProvider: userSettings,
    ).catchError((error) {
      print('❌ Failed to record word chat history: $error');
    });
    
    debugPrint('[TapInterface] Speech history AFTER adding "$textToAdd": "$_speechHistory"');
    debugPrint('[TapInterface] Speech history controller AFTER: "${_speechHistoryController.text}"');
    
    // Update status message
    setState(() {
      _statusMessage = 'Text added to speech. Say "${_getFormattedWakeWord()}" to ask a question.';
    });
    
    // Regenerate word options based on new speech history content
    await _loadWordOptionsBasedOnBuildSpace();
    
    // Regenerate phrase options based on new speech history content
    await _loadPhraseOptionsBasedOnBuildSpace();
  }

  Future<void> _loadWordOptionsBasedOnBuildSpace() async {
    try {
      setState(() {
        _isLoadingWordOptions = true;
      });

      debugPrint('[TapInterface] === WORD OPTIONS REFRESH ===');
      debugPrint('[TapInterface] Build space text: "$_buildSpaceText"');
      debugPrint('[TapInterface] Selected category: ${_selectedCategory?.label}');
      debugPrint('[TapInterface] Build space empty: ${_buildSpaceText.isEmpty}');
      debugPrint('[TapInterface] _selectedCategory != null: ${_selectedCategory != null}');
      
      List<String> wordOpts = [];
      
      // Decide which API to use based on context
      if (_selectedCategory != null && _buildSpaceText.isEmpty) {
        // If we have a selected category but no build space text,
        // use category-words API to get different words for the same category with mood context
        debugPrint('[TapInterface] Using Category Words API for different words');
        
        final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
        final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
        
        String categoryLabel = _selectedCategory?.label ?? '';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          categoryLabel = '${_selectedCategory?.label ?? ''} appropriate for someone feeling $currentMood';
        }
        
        final maxWordOptions = userSettings.settings?.freestyleOptions ?? 29;
        wordOpts = await _tapService.generateCategoryWords(
          category: categoryLabel,
          buildSpaceContent: _buildSpaceText,
          excludeWords: [], // Don't exclude words - let deduplication handle it
          maxOptions: maxWordOptions,
        );
        debugPrint('[TapInterface] Category Words API returned ${wordOpts.length} different words');
      } else {
        // For build space interactions or when no category is selected,
        // use the freestyle word-options API
        String context;
        if (_selectedCategory != null) {
          context = _selectedCategory?.label ?? ''; // Use category as primary context
          debugPrint('[TapInterface] Using Freestyle API with CATEGORY context: "$context"');
        } else if (_buildSpaceText.isNotEmpty) {
          context = _buildSpaceText;
          debugPrint('[TapInterface] Using Freestyle API with BUILD SPACE context: "$context"');
        } else {
          context = 'general communication topics';
          debugPrint('[TapInterface] Using Freestyle API with GENERAL context: "$context"');
        }
        
        final userSettings = Provider.of<UserSettingsProvider>(this.context, listen: false);
        final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
        
        String contextWithMood = context;
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          contextWithMood = '$context appropriate for someone feeling $currentMood';
        }
        
        final maxWordOptions = userSettings.settings?.freestyleOptions ?? 29;
        wordOpts = await _tapService.generateFreestyleOptions(
          context: contextWithMood,
          buildSpaceText: _buildSpaceText,
          singleWordsOnly: true, // Always single words for word options
          maxOptions: maxWordOptions,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint('[TapInterface] Freestyle API returned ${wordOpts.length} word options');
      }
      
      debugPrint('[TapInterface] First 5 options: ${wordOpts.take(5).toList()}');
      
      if (mounted) {
        final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        
        List<String> newOptions;
        if (wordOpts.isNotEmpty) {
          // Deduplicate words to avoid case-sensitive duplicates
          final deduplicatedWords = _deduplicateWords(wordOpts);
          debugPrint('[TapInterface] Word options refresh - Original: ${wordOpts.length}, Deduplicated: ${deduplicatedWords.length}');
          newOptions = deduplicatedWords.take(requiredWordCount).toList();
          
          // CRITICAL FIX: Ensure we always have exactly the required number of options
          if (newOptions.length < requiredWordCount) {
            debugPrint('[TapInterface] ⚠️  Only have ${newOptions.length} options after deduplication, need $requiredWordCount. Adding fallbacks...');
            final currentWordsLower = newOptions.map((w) => w.toLowerCase()).toSet();
            final fallbackOptions = _getFallbackWordOptions()
                .where((word) => !currentWordsLower.contains(word.toLowerCase()))
                .take(requiredWordCount - newOptions.length)
                .toList();
            newOptions.addAll(fallbackOptions);
            debugPrint('[TapInterface] Added ${fallbackOptions.length} fallback options, total now: ${newOptions.length}');
          }
        } else {
          debugPrint('[TapInterface] API returned no options, using fallback words');
          newOptions = _getFallbackWordOptions().take(requiredWordCount).toList();
        }
        setState(() {
          _wordOptions = newOptions;
          _isLoadingWordOptions = false;
          
          // IMPORTANT: Clear session-tracked missing images when loading fresh words
          // This allows us to log any missing images from the updated word set
          _globalSessionLoggedMissingImages.clear();
          debugPrint('📋 Cleared session-tracked missing images for refreshed word options');
        });
        debugPrint('[TapInterface] Updated UI with ${_wordOptions.length} word options');
        debugPrint('[TapInterface] First 5 UI options: ${_wordOptions.take(5).toList()}');
      }

    } catch (e) {
      debugPrint('[TapInterface] ERROR in word options refresh: $e');
      
      if (mounted) {
        final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        setState(() {
          _wordOptions = _getFallbackWordOptions().take(requiredWordCount).toList();
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
      debugPrint('[TapInterface] Selected category: ${_selectedCategory?.label}');
      debugPrint('[TapInterface] Build space empty: ${_buildSpaceText.isEmpty}');
      
      List<Map<String, String>> phraseOpts = [];
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      final requiredPhraseCount = userSettings.settings?.llmOptions ?? 10;
      
      String phraseContext = '';
      
      // Priority 1: Question mode (when user asks a question)
      if (_currentQuestion.isNotEmpty) {
        debugPrint('[TapInterface] Using QUESTION mode context');
        String categoryContext = _selectedCategory?.label ?? 'general';
        phraseContext = 'answering the question: "$_currentQuestion" in the context of $categoryContext';
        if (_buildSpaceText.isNotEmpty) {
          phraseContext = '$phraseContext, following up after: "$_buildSpaceText"';
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
              phraseContext = 'phrases for ordering food, expressing food preferences, and talking about meals';
              break;
            case 'activities':
            case 'activity':
              phraseContext = 'phrases for suggesting activities, talking about hobbies, and expressing interests';
              break;
            case 'people':
              phraseContext = 'phrases for talking about family, friends, and people in your life';
              break;
            case 'places':
              phraseContext = 'phrases for talking about locations, directions, and where you want to go';
              break;
            case 'actions':
              phraseContext = 'phrases for expressing actions, things you want to do, and movement';
              break;
            case 'needs':
            case 'wants':
              phraseContext = 'phrases for expressing needs, wants, and requests for help';
              break;
            case 'positive':
              phraseContext = 'positive adjectives and phrases for expressing approval, compliments, and good feelings';
              break;
            default:
              phraseContext = 'conversation phrases and expressions related to ${_selectedCategory!.label.toLowerCase()}';
          }
        }
        
        // Add build space context if present
        if (_buildSpaceText.isNotEmpty) {
          phraseContext = '$phraseContext, following up after saying: "$_buildSpaceText"';
        }
      }
      // Priority 3: Initial/General mode (no category, no question)
      else {
        debugPrint('[TapInterface] Using GENERAL/INITIAL mode context');
        if (_buildSpaceText.isNotEmpty) {
          phraseContext = 'general conversation phrases and follow-ups after saying: "$_buildSpaceText"';
        } else {
          phraseContext = 'general conversation starters and common phrases';
        }
      }
      
      // Add mood context to all modes
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        phraseContext = '$phraseContext appropriate for someone feeling $currentMood';
      }
      
      debugPrint('[TapInterface] Final phrase refresh context: "$phraseContext"');
      
      // Only refresh if we have a context
      if (phraseContext.isNotEmpty) {
        final phraseOptions = await _tapService.generateLLMPhraseOptions(
          context: phraseContext,
          maxOptions: requiredPhraseCount + 10, // Request extra to ensure we have enough
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint('[TapInterface] Phrase refresh API returned ${phraseOptions.length} options');
        
        phraseOpts = phraseOptions.take(requiredPhraseCount).toList();
        
        // Supplement with fallbacks if needed
        if (phraseOpts.length < requiredPhraseCount) {
          debugPrint('[TapInterface] Only have ${phraseOpts.length} phrase options, need $requiredPhraseCount. Adding fallbacks...');
          final currentTexts = phraseOpts.map((p) => p['fullText'] ?? '').toSet();
          
          // Choose fallback source based on mode
          List<String> fallbackOptions;
          if (_selectedCategory != null) {
            fallbackOptions = _getFallbackOptionsForCategory(_selectedCategory!.label, isWords: false);
          } else {
            fallbackOptions = _getFallbackPhraseOptions();
          }
          
          final additionalOptions = fallbackOptions
              .where((text) => !currentTexts.contains(text))
              .take(requiredPhraseCount - phraseOpts.length)
              .map((text) => {
                'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
                'fullText': text,
              }).toList();
          phraseOpts.addAll(additionalOptions);
          debugPrint('[TapInterface] Added ${additionalOptions.length} fallback phrase options, total now: ${phraseOpts.length}');
        }
      } else {
        debugPrint('[TapInterface] No phrase context available, skipping refresh');
      }
      
      debugPrint('[TapInterface] First 5 phrase options: ${phraseOpts.take(5).map((p) => p['fullText']).toList()}');
      
      if (mounted) {
        setState(() {
          if (phraseOpts.isNotEmpty) {
            _phraseOptions = phraseOpts;
          }
          _isLoadingPhraseOptions = false;
          
          // Clear session-tracked missing images when loading fresh phrases
          _globalSessionLoggedMissingImages.clear();
          debugPrint('📋 Cleared session-tracked missing images for refreshed phrase options');
        });
        debugPrint('[TapInterface] Updated UI with ${_phraseOptions.length} phrase options');
        debugPrint('[TapInterface] First 5 UI phrase options: ${_phraseOptions.take(5).map((p) => p['fullText']).toList()}');
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
      _statusMessage = 'Loading jokes...';
      _wordOptions = []; // No word options for jokes
      _phraseOptions = [];
      // Create a synthetic category for jokes display
      _selectedCategory = TapInterfaceCategory(
        id: 'jokes',
        label: 'Jokes',
      );
    });

    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final llmOptions = userSettings.settings?.llmOptions ?? 10;
      final idToken = userSettings.idToken ?? widget.idToken;
      final userId = userSettings.userId ?? widget.aacUserId;

      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/jokes/contextual?limit=$llmOptions'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': userId,
        },
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
          if (text.contains(' - ')) return text.replaceFirst(' - ', ' [PAUSE] ');
          if (text.contains(' — ')) return text.replaceFirst(' — ', ' [PAUSE] ');
          if (text.contains(': ')) return text.replaceFirst(': ', ': [PAUSE] ');
          return text;
        }

        final jokePhrases = jokes
            .map<Map<String, String>>((joke) {
              final jokeText = (joke['text'] ?? '').toString().trim();
              final summary = (joke['summary'] ?? 'Joke').toString().trim();
              return {
                'summary': summary.isNotEmpty ? summary : 'Joke',
                'fullText': addPauseToJokeText(jokeText),
              };
            })
            .where((p) => p['fullText']!.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _phraseOptions = jokePhrases;
            _isLoadingPhraseOptions = false;
            _statusMessage = 'Loaded ${jokePhrases.length} jokes';
          });
        }
      } else {
        debugPrint('[TapInterface] Jokes error: ${response.statusCode}');
        if (mounted) {
          setState(() {
            _isLoadingPhraseOptions = false;
            _statusMessage = 'Error loading jokes: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      debugPrint('[TapInterface] Jokes exception: $e');
      if (mounted) {
        setState(() {
          _isLoadingPhraseOptions = false;
          _statusMessage = 'Error loading jokes: $e';
        });
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
      _statusMessage = 'Loading different phrase options...';
    });
    
    try {
      List<Map<String, String>> newPhraseOptions = [];
      
      debugPrint('TapInterface: _loadMorePhraseOptions - current question: "$_currentQuestion"');
      debugPrint('TapInterface: _loadMorePhraseOptions - selected category: ${_selectedCategory?.label}');
      debugPrint('TapInterface: _loadMorePhraseOptions - has LLM query: ${_selectedCategory?.hasLLMQuery}');
      debugPrint('TapInterface: _loadMorePhraseOptions - current phrase count: ${_phraseOptions.length}');
      
      // Get current phrase texts to exclude
      final currentPhraseTexts = _phraseOptions.map((p) => p['fullText'] ?? '').toList();
      debugPrint('TapInterface: _loadMorePhraseOptions - excluding texts: $currentPhraseTexts');
      
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      
      String phraseContext;
      
      // Check if we're answering a voice question
      if (_currentQuestion.isNotEmpty) {
        // Use the question context (like initial question handling)
        String categoryContext = _selectedCategory?.label ?? 'general';
        phraseContext = 'answering the question: "$_currentQuestion" in the context of $categoryContext';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          phraseContext = 'answering the question: "$_currentQuestion" in the context of $categoryContext while feeling $currentMood';
        }
        debugPrint('TapInterface: Using question context: $phraseContext');
      } else if (_selectedCategory != null && _selectedCategory!.hasLLMQuery) {
        // Use category context (original behavior)
        phraseContext = _selectedCategory!.llmPrompt ?? '';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          phraseContext = '${_selectedCategory!.llmPrompt ?? ''} appropriate for someone feeling $currentMood';
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
        newPhraseOptions = phraseOpts.take(17).toList(); // Use only 17 for display
        debugPrint('TapInterface: LLM returned ${phraseOpts.length} options, using ${newPhraseOptions.length} for display');
        
        // If we still don't have enough options, supplement with fallback
        if (newPhraseOptions.length < 17 && _selectedCategory != null) {
          debugPrint('TapInterface: Need ${17 - newPhraseOptions.length} more phrase options, adding fallbacks');
          final currentTexts = newPhraseOptions.map((p) => p['fullText'] ?? '').toSet();
          final fallbackOptions = _getFallbackOptionsForCategory(_selectedCategory!.label, isWords: false);
          final additionalOptions = fallbackOptions
              .where((text) => !currentTexts.contains(text))
              .take(17 - newPhraseOptions.length)
              .map((text) => {
                'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
                'fullText': text,
              }).toList();
          newPhraseOptions.addAll(additionalOptions);
          debugPrint('TapInterface: Added ${additionalOptions.length} fallback options, total now: ${newPhraseOptions.length}');
        }
      }
      
      // If no new options or fallback needed
      if (newPhraseOptions.isEmpty && _selectedCategory != null) {
        debugPrint('TapInterface: No LLM options returned, trying fallbacks');
        if (_selectedCategory!.hasStaticOptions) {
          // Use different static options (skip already shown ones)
          final currentTexts = _phraseOptions.map((p) => p['fullText'] ?? '').toSet();
          final availableOptions = _selectedCategory!.staticOptionsList
              .where((text) => !currentTexts.contains(text))
              .toList();
          
          newPhraseOptions = availableOptions.take(17).map((text) => {
            'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
            'fullText': text,
          }).toList();
          debugPrint('TapInterface: Using ${newPhraseOptions.length} different static options');
        } else {
          // Use different fallback options
          final currentTexts = _phraseOptions.map((p) => p['fullText'] ?? '').toSet();
          final fallbackOptions = _getFallbackOptionsForCategory(_selectedCategory!.label, isWords: false);
          final availableOptions = fallbackOptions
              .where((text) => !currentTexts.contains(text))
              .toList();
          
          newPhraseOptions = availableOptions.take(17).map((text) => {
            'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
            'fullText': text,
          }).toList();
          debugPrint('TapInterface: Using ${newPhraseOptions.length} different fallback options');
        }
      } else if (newPhraseOptions.isEmpty) {
        debugPrint('TapInterface: No category selected or no options available at all');
      }
      
      // COMPREHENSIVE FALLBACK: If we still have no options, generate some basic ones
      if (newPhraseOptions.isEmpty) {
        debugPrint('TapInterface: Using comprehensive fallback - generating basic phrase options');
        final currentTexts = _phraseOptions.map((p) => p['fullText'] ?? '').toSet();
        
        // Create a large pool of basic conversational phrases
        final basicPhrases = [
          'Hello there', 'How are you?', 'I am fine', 'Thank you very much', 'Please help me',
          'Yes, that sounds good', 'No, I don\'t think so', 'I would like that', 'Can you help?',
          'I am hungry', 'I want to go', 'I need to rest', 'That was great', 'I feel good',
          'See you later', 'Good morning', 'Good afternoon', 'Good evening', 'Have a nice day',
          'I am tired', 'I am happy', 'I am sad', 'I am excited', 'Let me think',
          'That\'s interesting', 'I understand', 'I don\'t understand', 'Can you repeat?', 'Excuse me',
          'I\'m sorry', 'No problem', 'You\'re welcome', 'Nice to meet you', 'Take care',
          'I love you', 'I miss you', 'How was your day?', 'What are you doing?', 'Where are you going?',
          'I want to eat', 'I want to drink', 'I want to sleep', 'I want to play', 'I want to work',
          'I am done', 'I am finished', 'I am ready', 'Wait for me', 'I am coming',
        ];
        
        // Filter out already shown options
        final availableBasicPhrases = basicPhrases
            .where((text) => !currentTexts.contains(text))
            .toList();
        
        // Take up to 17 different options
        newPhraseOptions = availableBasicPhrases.take(17).map((text) => {
          'summary': text.length > 30 ? '${text.substring(0, 30)}...' : text,
          'fullText': text,
        }).toList();
        
        debugPrint('TapInterface: Comprehensive fallback provided ${newPhraseOptions.length} basic phrase options');
      }
      
      setState(() {
        _phraseOptions = newPhraseOptions;
        _isLoadingPhraseOptions = false;
        _statusMessage = newPhraseOptions.isNotEmpty 
            ? 'Loaded ${newPhraseOptions.length} different phrase options'
            : 'No more phrase options available';
      });
      
    } catch (e) {
      debugPrint('TapInterface: Error loading different phrase options: $e');
      setState(() {
        _isLoadingPhraseOptions = false;
        _statusMessage = 'Error loading different phrase options';
      });
    }
  }

  Future<void> _loadMoreWordOptions() async {
    if (_isLoadingWordOptions) return;
    
    // Get user settings at the beginning of the function
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    
    setState(() {
      _isLoadingWordOptions = true;
      _statusMessage = 'Loading different word options...';
    });
    
    try {
      List<String> newWordOptions = [];
      
      debugPrint('TapInterface: === SOMETHING ELSE DEBUG ===');
      debugPrint('TapInterface: _loadMoreWordOptions - current question: "$_currentQuestion"');
      debugPrint('TapInterface: _loadMoreWordOptions - selected category: ${_selectedCategory?.label}');
      debugPrint('TapInterface: _loadMoreWordOptions - build space text: "$_buildSpaceText"');
      debugPrint('TapInterface: _loadMoreWordOptions - speech history: "$_speechHistory"');
      debugPrint('TapInterface: _loadMoreWordOptions - current word count: ${_wordOptions.length}');
      debugPrint('TapInterface: _loadMoreWordOptions - current words to exclude: $_wordOptions');
      debugPrint('TapInterface: _loadMoreWordOptions - _selectedCategory != null: ${_selectedCategory != null}');
      debugPrint('TapInterface: _loadMoreWordOptions - _buildSpaceText.isEmpty: ${_buildSpaceText.isEmpty}');
      debugPrint('TapInterface: _loadMoreWordOptions - _currentQuestion.isNotEmpty: ${_currentQuestion.isNotEmpty}');
      
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      
      // Check if we're answering a voice question - this takes priority
      if (_currentQuestion.isNotEmpty) {
        // Use generateCategoryWords with extracted category (same as initial question handling)
        debugPrint('[TapInterface] Using generateCategoryWords API with QUESTION-derived category');
        
        String categoryForWords = _extractCategoryFromQuestion(_currentQuestion);
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          categoryForWords = '$categoryForWords appropriate for someone feeling $currentMood';
        }
        
        debugPrint('[TapInterface] Category extracted from question: $categoryForWords');
        
        // Request 2x to account for duplicates with current options
        final wordOptionsStrings = await _tapService.generateCategoryWords(
          category: categoryForWords,
          buildSpaceContent: _buildSpaceText,
          excludeWords: _wordOptions, // Exclude current words
          maxOptions: requiredWordCount * 2, // Request double to ensure we have enough after filtering
          requestDifferentOptions: true,
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        
        // Deduplicate and exclude current options
        final deduplicatedWords = _deduplicateWords(wordOptionsStrings);
        final currentWordsLower = _wordOptions.map((w) => w.toLowerCase()).toSet();
        newWordOptions = deduplicatedWords
            .where((word) => !currentWordsLower.contains(word.toLowerCase()))
            .take(requiredWordCount) // Take exactly the required count
            .toList();
        
        debugPrint('[TapInterface] Question-based API returned ${wordOptionsStrings.length} words, ${newWordOptions.length} after dedup/filter/limit');
      } else if (_selectedCategory != null && _buildSpaceText.isEmpty) {
        // Use category-words API with request_different_options = true
        debugPrint('[TapInterface] Using Category Words API for different words');
        
        final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
        
        String categoryLabel = _selectedCategory?.label ?? '';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          categoryLabel = '${_selectedCategory?.label ?? ''} appropriate for someone feeling $currentMood';
        }
        
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        
        final rawWordOptions = await _tapService.generateCategoryWords(
          category: categoryLabel,
          buildSpaceContent: _buildSpaceText,
          excludeWords: _wordOptions, // Exclude current words to get different ones
          maxOptions: requiredWordCount + 10, // Request extra options to ensure we have enough
          requestDifferentOptions: true, // Request different options
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint('[TapInterface] Category Words API returned ${rawWordOptions.length} raw words');
        
        // Validate words for category appropriateness
        newWordOptions = _validateWordsForCategory(rawWordOptions, _selectedCategory?.label ?? '');
        debugPrint('[TapInterface] After validation: ${newWordOptions.length}/${rawWordOptions.length} words are appropriate');
        debugPrint('[TapInterface] NEW Category words: ${newWordOptions.take(10).toList()}...');
        debugPrint('[TapInterface] OLD UI words: ${_wordOptions.take(10).toList()}...');
        
        // Check for overlap to debug the issue
        final overlap = newWordOptions.where((word) => _wordOptions.contains(word)).toList();
        debugPrint('[TapInterface] Category word overlap count: ${overlap.length} out of ${newWordOptions.length}');
        if (overlap.isNotEmpty) {
          debugPrint('[TapInterface] Overlapping category words: ${overlap.take(5).toList()}...');
        }
      } else {
        // Use freestyle word-options API with request_different_options = true
        String context;
        
        if (_selectedCategory != null) {
          context = _selectedCategory?.label ?? '';
          debugPrint('[TapInterface] Using Freestyle API with CATEGORY context for different options: "$context"');
        } else if (_buildSpaceText.isNotEmpty) {
          context = _buildSpaceText;
          debugPrint('[TapInterface] Using Freestyle API with BUILD SPACE context for different options: "$context"');
        } else {
          // When no category is selected, provide a more specific context to help generate good initial options
          context = 'communication essentials and common words for everyday conversation';
          debugPrint('[TapInterface] Using Freestyle API with ENHANCED GENERAL context for different options: "$context"');
        }
        
        // CRITICAL FIX: Only use excludeOptions if we actually have options to exclude
        // Otherwise, the API might not know what "different" means and return empty results
        List<String> exclusions = _wordOptions.isNotEmpty ? _wordOptions : [];
        debugPrint('[TapInterface] Excluding ${exclusions.length} current words: ${exclusions.take(5).toList()}${exclusions.length > 5 ? '...' : ''}');
        
        final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
        
        String contextWithMood = context;
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          contextWithMood = '$context appropriate for someone feeling $currentMood';
        }
        
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        
        newWordOptions = await _tapService.generateFreestyleOptions(
          context: contextWithMood,
          buildSpaceText: _buildSpaceText,
          singleWordsOnly: true,
          maxOptions: requiredWordCount + 10, // Request extra options to ensure we have enough
          requestDifferentOptions: true, // Request different options
          excludeOptions: exclusions, // Only exclude if we have something to exclude
          currentMood: currentMood != 'No Mood Selected' ? currentMood : null,
        );
        debugPrint('[TapInterface] Freestyle API returned ${newWordOptions.length} different word options, will use up to $requiredWordCount');
        debugPrint('[TapInterface] NEW API words: ${newWordOptions.take(10).toList()}...');
        debugPrint('[TapInterface] OLD UI words: ${_wordOptions.take(10).toList()}...');
        
        // Check for overlap to debug the issue
        final overlap = newWordOptions.where((word) => _wordOptions.contains(word)).toList();
        debugPrint('[TapInterface] Word overlap count: ${overlap.length} out of ${newWordOptions.length}');
        if (overlap.isNotEmpty) {
          debugPrint('[TapInterface] Overlapping words: ${overlap.take(5).toList()}...');
        }
      }
      
      // If no new options, try fallback with exclusion
      if (newWordOptions.isEmpty) {
        debugPrint('[TapInterface] No API options returned, trying fallback exclusion logic');
        final fallbackOptions = _getFallbackWordOptions();
        final currentWordsSet = _wordOptions.toSet();
        debugPrint('[TapInterface] Fallback options available: ${fallbackOptions.length}');
        debugPrint('[TapInterface] Current words to exclude: ${currentWordsSet.length} words');
        
        final filteredOptions = fallbackOptions
            .where((word) => !currentWordsSet.contains(word))
            .toList();
        debugPrint('[TapInterface] After exclusion: ${filteredOptions.length} words available');
        
        final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
        final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
        newWordOptions = filteredOptions.take(requiredWordCount).toList();
        debugPrint('[TapInterface] Final fallback selection: ${newWordOptions.length} words');
        debugPrint('[TapInterface] First 5 fallback words: ${newWordOptions.take(5).toList()}');
      }
      
      // Deduplicate words to avoid case-sensitive duplicates like "Want"/"want"
      newWordOptions = _deduplicateWords(newWordOptions);
      debugPrint('[TapInterface] After deduplication: ${newWordOptions.length} unique words');
      
      // Only pad with fallbacks if NOT answering a question
      // For questions, we only want relevant answers, not generic words
      if (_currentQuestion.isEmpty && newWordOptions.length < requiredWordCount) {
        debugPrint('[TapInterface] Only have ${newWordOptions.length} options, need $requiredWordCount. Adding more fallbacks...');
        final currentWordsLower = newWordOptions.map((w) => w.toLowerCase()).toSet();
        final allFallbackOptions = _getFallbackWordOptions();
        final additionalOptions = allFallbackOptions
            .where((word) => !currentWordsLower.contains(word.toLowerCase()))
            .take(requiredWordCount - newWordOptions.length)
            .toList();
        newWordOptions.addAll(additionalOptions);
        debugPrint('[TapInterface] Added ${additionalOptions.length} additional fallback options, total now: ${newWordOptions.length}');
      } else if (_currentQuestion.isNotEmpty && newWordOptions.length < requiredWordCount) {
        debugPrint('[TapInterface] Question mode: Only have ${newWordOptions.length} relevant answers (not padding with generic words)');
      }
      
      // Trim to exactly the required count if we have too many
      if (newWordOptions.length > requiredWordCount) {
        newWordOptions = newWordOptions.take(requiredWordCount).toList();
        debugPrint('[TapInterface] Trimmed to exactly $requiredWordCount options');
      }
      
      setState(() {
        debugPrint('[TapInterface] BEFORE setState - current _wordOptions: ${_wordOptions.take(5).toList()}...');
        debugPrint('[TapInterface] BEFORE setState - newWordOptions: ${newWordOptions.take(5).toList()}...');
        
        final oldWordOptions = List<String>.from(_wordOptions); // Save old options for comparison
        
        // CRITICAL FIX: Force clear the old options first to ensure UI update
        _wordOptions.clear();
        _wordKeywords.clear(); // Clear keywords when clearing word options
        debugPrint('[TapInterface] CLEARED old _wordOptions to force UI update');
        
        // Add new options
        _wordOptions = List<String>.from(newWordOptions.take(requiredWordCount)); // Force new list creation
        
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
          debugPrint('🚨 CRITICAL: Found duplicates in FINAL _wordOptions: $finalDuplicates');
          debugPrint('🚨 CRITICAL: Full _wordOptions list: $_wordOptions');
        } else {
          debugPrint('✅ GOOD: No duplicates found in final _wordOptions');
        }
        
        debugPrint('[TapInterface] AFTER setState - updated _wordOptions: ${_wordOptions.take(5).toList()}...');
        debugPrint('[TapInterface] setState comparison: OLD vs NEW');
        debugPrint('[TapInterface]   OLD first 5: ${oldWordOptions.take(5).toList()}');
        debugPrint('[TapInterface]   NEW first 5: ${_wordOptions.take(5).toList()}');
        
        final areIdentical = List.from(oldWordOptions.take(10)) == List.from(_wordOptions.take(10));
        debugPrint('[TapInterface] Are first 10 words identical? $areIdentical');
        
        // CRITICAL FIX: Force a complete rebuild by updating other state variables
        _isLoadingWordOptions = false;
        _optionsRebuildKey++; // Force widget tree rebuild
        
        // IMPORTANT: Clear session-tracked missing images when loading fresh options
        // This allows us to re-log any missing images from the new word set
        _globalSessionLoggedMissingImages.clear();
        debugPrint('📋 Cleared session-tracked missing images for fresh word options');
        
        final timestamp = DateTime.now();
        _statusMessage = newWordOptions.isNotEmpty 
            ? 'FRESH OPTIONS #$_optionsRebuildKey loaded at ${timestamp.hour}:${timestamp.minute}:${timestamp.second} - ${newWordOptions.length} words'
            : 'No more word options available';
            
        debugPrint('[TapInterface] setState completed with forced rebuild. Rebuild key: $_optionsRebuildKey, Status: $_statusMessage');
      });
      
    } catch (e) {
      debugPrint('[TapInterface] ERROR loading different word options: $e');
      final requiredWordCount = userSettings.settings?.freestyleOptions ?? 29;
      setState(() {
        _wordOptions = _getFallbackOptionsForCategory('generic', isWords: true).take(requiredWordCount).toList();
        _isLoadingWordOptions = false;
        _statusMessage = 'Error loading different word options';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: true);
    final userSettings = settingsProvider.settings;
    
    // Get user-selected colors
    final Color headerTextColor = userSettings != null 
        ? Color(userSettings.lightColorValue) 
        : Colors.blue;
    final Color backgroundColor = userSettings != null 
        ? Color(userSettings.darkColorValue) 
        : Colors.grey[100] ?? Colors.grey;

    if (_tapConfig == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                  child: Row(
                    children: [
                      // Home Button (Icon Only) - Returns to original page
                      Tooltip(
                        message: 'Home',
                        child: Container(
                          height: 40,
                          width: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blueGrey[300] ?? Colors.blueGrey.shade300,
                                Colors.blueGrey[500] ?? Colors.blueGrey.shade500,
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
                            onPressed: _resetPage,
                            icon: const Icon(Icons.home, size: 28, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Speech History Text Field (serves as build space)
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300] ?? Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: TextField(
                            controller: _speechHistoryController,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Build your message here...',
                              hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // Speak Button (Icon Only) - Always speaks as-is
                      Tooltip(
                        message: 'Speak',
                        child: Container(
                          height: 40,
                          width: 65,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[400] ?? Colors.green.shade400, Colors.green[600] ?? Colors.green.shade600],
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
                            onPressed: _handleSpeakButtonPress,
                            icon: const Icon(Icons.volume_up, size: 31, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Auto Clean + Speak Button (Icon Only) - Always uses LLM cleanup
                      Tooltip(
                        message: 'Auto Clean + Speak',
                        child: Container(
                          height: 40,
                          width: 65,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.purple[400] ?? Colors.purple.shade400, Colors.purple[600] ?? Colors.purple.shade600],
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
                            onPressed: _handleAutoCleanSpeakButtonPress,
                            icon: const Icon(Icons.auto_fix_high, size: 28, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Backspace Button (Icon Only)
                      Tooltip(
                        message: 'Backspace',
                        child: Container(
                          height: 40,
                          width: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.amber[600] ?? Colors.amber.shade600, Colors.amber[800] ?? Colors.amber.shade800],
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
                            onPressed: _backspaceSpeechHistory,
                            icon: const Icon(Icons.backspace, size: 31, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Clear Text Button (Icon Only) - NEW
                      Tooltip(
                        message: 'Clear Text',
                        child: Container(
                          height: 40,
                          width: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.red[400] ?? Colors.red.shade400, Colors.red[600] ?? Colors.red.shade600],
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
                            onPressed: _clearSpeechText,
                            icon: const Icon(Icons.close, size: 31, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Audio Surfing Toggle Button (Icon Only)
                      Tooltip(
                        message: _isAudioSurfingEnabled ? 'Audio Surfing: ON' : 'Audio Surfing: OFF',
                        child: Container(
                          height: 40,
                          width: 50,
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
                                color: (_isAudioSurfingEnabled ? Colors.teal : Colors.grey).withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: () {
                              setState(() {
                                _isAudioSurfingEnabled = !_isAudioSurfingEnabled;
                                _audioSurfingPreviewOptionKey = null;
                                _statusMessage = _isAudioSurfingEnabled
                                    ? 'Audio Surfing enabled. Tap once to preview, tap again to select.'
                                    : 'Audio Surfing disabled.';
                              });
                            },
                            icon: Icon(
                              _isAudioSurfingEnabled ? Icons.surround_sound : Icons.hearing,
                              size: 28,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Email Button (Icon Only)
                      Tooltip(
                        message: 'Compose Email',
                        child: Container(
                          height: 40,
                          width: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.indigo[400] ?? Colors.indigo.shade400,
                                Colors.indigo[600] ?? Colors.indigo.shade600,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _composeEmailWithSpeechText,
                            icon: const Icon(Icons.mail_outline, size: 26, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),
                      
                      // History Button (Icon Only)
                      Tooltip(
                        message: 'History',
                        child: Container(
                          height: 40,
                          width: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.blue[400] ?? Colors.blue.shade400, Colors.blue[600] ?? Colors.blue.shade600],
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
                            onPressed: _showSpeechHistoryDialog,
                            icon: const Icon(Icons.menu_book, size: 31, color: Colors.white),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // --- MAIN INTERFACE ---
                Expanded(
                  child: Row(
                    children: [
                      // Column 1: Categories
                      Expanded(
                        flex: 1,
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.purple[25] ?? Colors.purple.shade50, Colors.purple[50] ?? Colors.purple.shade100],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple[300] ?? Colors.purple.shade300, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.2),
                                offset: const Offset(0, 3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Section header
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
                                child: Material(
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
                                      child: Column(
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
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.library_books, size: 32, color: Colors.teal[800]),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Grid content
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: GridView.count(
                            padding: const EdgeInsets.only(bottom: 16),
                            crossAxisCount: 1, // Always 1 column for categories
                            childAspectRatio: _getCategoryAspectRatio(userSettings?.gridColumns ?? 6, 1.1), // Calculated to match main content button sizes
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                            children: (_tapConfig?.buttons ?? [])
                                .where((category) => !category.hidden)
                                .map((category) {
                              final isSelected = _selectedCategory == category;
                              final tapPictogramsDisabled = userSettings?.disableTapPictograms ?? false;
                              final tapPictogramsEnabled = !tapPictogramsDisabled;
                              final tapSightWordLogicEnabled = !tapPictogramsDisabled && (userSettings?.enableSightWords ?? true);
                              return TapInterfaceButton(
                                label: category.label,
                                onPressed: () => _handleCategoryTap(category),
                                backgroundColor: isSelected 
                                    ? headerTextColor.withOpacity(0.8) 
                                    : Colors.white,
                                foregroundColor: isSelected 
                                    ? Colors.white 
                                    : Colors.black87,
                                borderColor: isSelected 
                                    ? headerTextColor 
                                    : Colors.purple[300] ?? Colors.purple.shade300,
                                fontSize: 12,
                                enablePictograms: tapPictogramsEnabled,
                                sightWordGradeLevel: userSettings?.sightWordGradeLevel,
                                enableSightWords: tapSightWordLogicEnabled,
                                padding: const EdgeInsets.all(2),
                                assignedImageUrl: category.imageUrl, // Pass assigned image URL from database
                                shouldLogMissing: false, // Don't log missing images for category sidebar buttons
                              );
                            }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                
                      // Columns 2-10: Options Grid
                      Expanded(
                        flex: 9,
                        child: _buildOptionsGrid(userSettings, headerTextColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // --- ADMIN TOOLBAR ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Status Message - takes up remaining space (fade in/out)
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: (_showBottomStatusText && _statusMessage.isNotEmpty)
                          ? Container(
                              key: ValueKey('tap_status_$_statusMessage'),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: _isListeningForQuestion 
                                  ? Colors.orange.shade50 
                                  : _isListeningForWakeWord 
                                    ? Colors.green.shade50 
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isListeningForQuestion 
                                    ? Colors.orange.shade200 
                                    : _isListeningForWakeWord 
                                      ? Colors.green.shade200 
                                      : Colors.blue.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                _statusMessage,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _isListeningForQuestion 
                                    ? Colors.orange.shade700 
                                    : _isListeningForWakeWord 
                                      ? Colors.green.shade700 
                                      : Colors.blue.shade700,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : const SizedBox(key: ValueKey('tap_status_hidden')),
                    ),
                  ),
                    
                  // Admin buttons - Only show when unlocked
                  if (!_isAdminToolbarLocked) ...[
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
                    // Separator
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey[400],
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    // Switch User Account button
                    IconButton(
                      icon: const Icon(Icons.account_circle, color: Colors.black87),
                      tooltip: 'Switch User Account',
                      onPressed: _switchUserAccount,
                    ),
                    // Sign Out button
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.black87),
                      tooltip: 'Sign Out',
                      onPressed: _signOut,
                    ),
                  ],

                  // Lock/Unlock Icon (moved to right side)
                  IconButton(
                    icon: Icon(
                      _isAdminToolbarLocked ? Icons.lock : Icons.lock_open,
                      color: Colors.black87,
                    ),
                    tooltip: _isAdminToolbarLocked ? 'Unlock Admin Toolbar' : 'Lock Admin Toolbar',
                    onPressed: _toggleAdminToolbarLock,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Schedule Check Methods ---

  void _startScheduleCheck() {
    // Initial check (Login Check)
    _checkSchedules(isRuntime: false);

    // Periodic check (Runtime Check)
    _scheduleCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkSchedules(isRuntime: true);
    });
  }

  Future<void> _checkSchedules({required bool isRuntime}) async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final favorites = List<Map<String, dynamic>>.from(data['favorites'] ?? []);

        for (final fav in favorites) {
          bool shouldPrompt = false;
          if (isRuntime) {
            if (ScheduleService.didScheduleJustStart(fav)) {
              shouldPrompt = true;
            }
          } else {
            if (ScheduleService.isScheduleActive(fav)) {
              shouldPrompt = true;
            }
          }

          if (shouldPrompt && mounted) {
            _showLoadFavoriteDialog(fav);
            break; // Only show one prompt at a time
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking schedules: $e');
    }
  }

  Future<void> _showLoadFavoriteDialog(Map<String, dynamic> favorite) async {
    final name = favorite['name'];
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scheduled Favorite'),
        content: Text('The schedule for "$name" is active. Do you want to load this location?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
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
      
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/user_current'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'location': favorite['location'] ?? '',
          'people': favorite['people'] ?? '',
          'activity': favorite['activity'] ?? '',
          'loaded_at': loadTimestamp,
          'favorite_name': favorite['name'],
          'saved_at': loadTimestamp,
        }),
      );

      if (response.statusCode == 200) {
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
