import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/user_settings_provider.dart';
import 'services/wake_word_service.dart';
import 'admin_pages_buttons.dart';
import 'main.dart'; // Import for SpeechBubbleButton and related classes
import 'config/environment_config.dart';

class FavoritesPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;

  const FavoritesPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
  });

  @override
  FavoritesPageState createState() => FavoritesPageState();
}

class FavoritesPageState extends State<FavoritesPage> with RouteAware, TickerProviderStateMixin {
  // --- UI State Variables ---
  bool _isLoading = false;
  String? _statusMessage;
  
  // --- Favorites State ---
  List<Map<String, dynamic>> _favoriteButtons = [];
  List<Map<String, dynamic>> _articleOptions = [];
  bool _showingArticles = false;
  String? _currentTopic;
  String _speechHistory = '';
  String _questionDisplay = '';
  String _voiceStatusMessage = '';
  
  // Animation controller for spinner
  late AnimationController _animationController;
  
  // Wake word service
  WakeWordService? _wakeWordService;
  
  // Focus node for keyboard handling
  late FocusNode _keyboardFocusNode;
  
  // --- Scanning State ---
  bool _isScanning = false;
  bool _isScanningPaused = false;
  bool _waitingForUserInput = false;
  bool _isAnnouncingScanningPrompt = false;  // Track if announcing during scanning prompts (for Tab interrupt)
  Timer? _scanningTimer;
  int _scanningIndex = -1;
  int _scanCycleCount = 0;
  int _scanLoopLimit = 0;
  
  // --- Audio State ---
  FlutterTts? _flutterTts;
  Timer? _announcementTimer;
  Timer? _longWaitTimer;
  bool _isAnnouncing = false;
  AudioPlayer? _audioPlayer;
  
  // --- Settings ---
  Map<String, dynamic> _userSettings = {};
  int _gridColumns = 10;
  double _buttonSize = 80.0;
  bool _scanningOff = false;
  int _scanDelay = 3500;
  Color _darkColor = const Color(0xFF002244);
  Color _lightColor = const Color(0xFFFB4F14);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(); // Start repeating animation
    _keyboardFocusNode = FocusNode();
    _initializePage();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _keyboardFocusNode.dispose();
    _cleanupResources();
    super.dispose();
  }

  Future<void> _initializePage() async {
    debugPrint('FavoritesPage: Initializing...');
    
    try {
      // Load user settings
      await _loadUserSettings();
      
      // Initialize audio services
      await _initializeAudioServices();
      
      // Initialize wake word service
      await _initializeWakeWordService();
      
      // Load favorite buttons
      await _loadFavoriteButtons();
      
      // Start scanning after everything is loaded
      _startScanningAfterDelay();
      
      // Request focus for keyboard input after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
          debugPrint('FavoritesPage: Requested keyboard focus');
        }
      });
      
      // Also request focus again after a longer delay to ensure it sticks
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
          debugPrint('FavoritesPage: Re-requested keyboard focus for persistence');
        }
      });
      
    } catch (e) {
      debugPrint('Error initializing favorites page: $e');
      setState(() {
        _statusMessage = 'Error loading favorites: $e';
      });
    }
  }

  Future<void> _loadUserSettings() async {
    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      if (settingsProvider.settings == null) {
        settingsProvider.idToken = widget.idToken;
        settingsProvider.userId = widget.aacUserId;
        await settingsProvider.fetchSettings();
      }
      
      setState(() {
        _userSettings = settingsProvider.settings?.toJson() ?? {};
        _gridColumns = _userSettings['gridColumns'] ?? 10;
        _scanningOff = _userSettings['ScanningOff'] ?? false;
        _scanDelay = _userSettings['scanDelay'] ?? 3500;
        _scanLoopLimit = _userSettings['scanLoopLimit'] ?? 0;
        _darkColor = Color(_userSettings['darkColorValue'] ?? 0xFF002244);
        _lightColor = Color(_userSettings['lightColorValue'] ?? 0xFFFB4F14);
      });
      
      debugPrint('FavoritesPage: Settings loaded - scanning: ${!_scanningOff}, delay: $_scanDelay');
    } catch (e) {
      debugPrint('Error loading user settings: $e');
    }
  }

  Future<void> _initializeAudioServices() async {
    try {
      // Initialize TTS
      _flutterTts = FlutterTts();
      if (_flutterTts != null) {
        await _flutterTts!.setLanguage("en-US");
        await _flutterTts!.setSpeechRate(0.5);
        
// Get personalVolume from global settings (scanning uses personal volume, not system)
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final personalVolume = settingsProvider.settings?.personalVolume ?? 10;
      final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
      debugPrint('FavoritesPage: Using personalVolume: $personalVolume/10 → TTS volume: $ttsVolume (scanning)');
        await _flutterTts!.setVolume(ttsVolume);
        
        await _flutterTts!.setPitch(1.0);
      }
      
      // Initialize audio player
      _audioPlayer = AudioPlayer();
      
      debugPrint('FavoritesPage: Audio services initialized');
    } catch (e) {
      debugPrint('Error initializing audio services: $e');
    }
  }

  Future<int> _getEffectivePersonalVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        'FavoritesPage: Using LOCAL personal volume override: $overrideValue/10',
      );
      return overrideValue;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final settingsValue = settingsProvider.settings?.personalVolume ?? 10;
    debugPrint(
      'FavoritesPage: Using SETTINGS personal volume: $settingsValue/10',
    );
    return settingsValue;
  }

  Future<void> _speakScanningPrompt(String text) async {
    if (text.isEmpty || _flutterTts == null || _isAnnouncing) return;

    try {
      setState(() {
        _isAnnouncingScanningPrompt = true;
      });
      
      await _flutterTts!.stop();
      await _flutterTts!.setSpeechRate(0.5);
      final personalVolume = await _getEffectivePersonalVolume();
      final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
      debugPrint(
        'FavoritesPage: Scanning prompt volume personalVolume=$personalVolume/10 (TTS=$ttsVolume)',
      );
      await _flutterTts!.setVolume(ttsVolume);
      await _flutterTts!.setPitch(1.0);
      await _flutterTts!.speak(text);
    } catch (e) {
      debugPrint('FavoritesPage: Error speaking scanning prompt: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
    }
  }

  Future<void> _initializeWakeWordService() async {
    try {
      _wakeWordService = WakeWordService(
        wakeWords: ['hey buddy', 'hey bravo'],
      );
      
      // Set up wake word callback
      _wakeWordService!.onWakeWord = (transcript) async {
        debugPrint('FavoritesPage: Wake word detected: $transcript');
        // Handle wake word activation
        setState(() {
          _voiceStatusMessage = 'Wake word heard! Listening...';
        });
      };

      _wakeWordService!.onQuestionStatusUpdate = (questionText) {
        if (!mounted) return;
        setState(() {
          if (questionText.isNotEmpty) {
            _voiceStatusMessage = 'Hearing: "$questionText"';
          }
        });
      };
      
      // Set up question callback  
      _wakeWordService!.onQuestion = (question) async {
        debugPrint('FavoritesPage: Question received: $question');
        setState(() {
          _questionDisplay = question;
          _speechHistory = 'Q: $question${_speechHistory.isNotEmpty ? '\n' : ''}$_speechHistory';
          _voiceStatusMessage = 'Processing: $question';
        });
      };
      
      // Start listening
      _wakeWordService?.startWakeWordListening();
      
    } catch (e) {
      debugPrint('Error initializing wake word service: $e');
    }
  }

  Future<void> _loadFavoriteButtons() async {
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Loading favorites...';
      });
      
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/favorites'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _favoriteButtons = List<Map<String, dynamic>>.from(data['buttons'] ?? []);
          _isLoading = false;
          _statusMessage = null;
        });
        debugPrint('FavoritesPage: Loaded ${_favoriteButtons.length} favorite buttons');
      } else {
        throw Exception('Failed to load favorites: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading favorite buttons: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error loading favorites: $e';
      });
    }
  }

  Future<void> _handleFavoriteButtonPress(Map<String, dynamic> button) async {
    try {
      _stopScanning();
      
      // Announce the button if it has a speech phrase using built-in speaker
      if (button['speechPhrase'] != null && button['speechPhrase'].toString().trim().isNotEmpty) {
        debugPrint('FavoritesPage: Announcing favorite button: ${button['speechPhrase']}');
        await _announceViaBuiltinSpeaker(button['speechPhrase']);
      }
      
      setState(() {
        _isLoading = true;
        _statusMessage = 'Loading ${button['text']} articles...';
        _currentTopic = button['text'];
      });
      
      // Fetch articles for this topic
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/favorites/get-topic-content'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'topic': button['text'],
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Handle 'summaries' response format from backend
        final summaries = data['summaries'] as List<dynamic>? ?? [];
        
        // Convert summaries to options format
        // Convert summaries to options format - use actual summary field from backend
        final articles = summaries.map((summary) {
          if (summary is String) {
            // If it's just a string, we don't have a separate summary
            return {
              'option': summary, 
              'text': summary,
              'summary': summary // Use the full text as summary for now
            };
          } else if (summary is Map<String, dynamic>) {
            // Extract the proper fields from the backend response
            final fullText = summary['option'] ?? summary['text'] ?? summary.toString();
            final summaryText = summary['summary'] ?? summary['title'] ?? fullText;
            debugPrint('FavoritesPage: Article - Summary: "$summaryText", Full: "$fullText"');
            return {
              'option': fullText,
              'text': fullText,
              'summary': summaryText
            };
          }
          // Fallback for other types
          final fallbackText = summary.toString();
          return {
            'option': fallbackText, 
            'text': fallbackText,
            'summary': fallbackText
          };
        }).toList();
        
        setState(() {
          _articleOptions = articles;
          _showingArticles = true;
          _isLoading = false;
          _statusMessage = null;
        });
        
        _startScanningAfterDelay();
        debugPrint('FavoritesPage: Loaded ${articles.length} articles for ${button['text']}');
      } else {
        throw Exception('Failed to load articles: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error handling favorite button press: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error loading articles: $e';
      });
    }
  }

  Future<void> _handleArticleButtonPress(Map<String, dynamic> article) async {
    try {
      _stopScanning();
      
      final optionText = article['option'] ?? article['text'] ?? '';
      
      // Update speech history with the full option text
      setState(() {
        if (_questionDisplay.isNotEmpty) {
          final qPrefix = 'Q: $_questionDisplay';
          final lines = _speechHistory.split('\n');
          final matchIndex = lines.indexWhere((l) => l.startsWith(qPrefix));

          if (matchIndex >= 0) {
            lines[matchIndex] = 'Q: $_questionDisplay | A: $optionText';
            _speechHistory = lines.join('\n');
          } else {
            _speechHistory = 'Q: $_questionDisplay | A: $optionText${_speechHistory.isNotEmpty ? '\n' : ''}$_speechHistory';
          }

          _questionDisplay = ''; // Clear questionDisplay after using it
          _voiceStatusMessage = '';
        } else {
          _speechHistory = '$optionText${_speechHistory.isNotEmpty ? '\n' : ''}$_speechHistory';
        }
      });
      
      // Announce the full option text using built-in speaker
      debugPrint('FavoritesPage: Announcing article selection: "$optionText"');
      await _announceViaBuiltinSpeaker(optionText);
      
      // Navigate back to main grid page
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error handling article button press: $e');
    }
  }

  void _handleBackButton() {
    if (_showingArticles) {
      // Go back to favorites list
      setState(() {
        _showingArticles = false;
        _articleOptions = [];
        _currentTopic = null;
      });
      _startScanningAfterDelay();
    } else {
      // Go back to main grid page
      Navigator.of(context).pop();
    }
  }

  // --- Scanning Methods ---
  void _startScanningAfterDelay() {
    if (_scanningOff) return;
    
    Timer(Duration(milliseconds: _scanDelay), () {
      if (mounted && !_isLoading && !_isAnnouncing) {
        _startScanning();
      }
    });
  }

  void _startScanning() {
    if (_scanningOff || _isScanning || _isAnnouncing) return;
    
    final buttons = _showingArticles ? _articleOptions : _favoriteButtons;
    if (buttons.isEmpty) return;
    
    // Ensure keyboard focus is maintained
    if (!_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
      debugPrint('FavoritesPage: Re-requesting focus during _startScanning');
    }
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    setState(() {
      _isScanning = true;
      _scanningIndex = -1; // Start with "Go Back" button
      _scanCycleCount = 0;
    });

    // In auto mode, announce and start timer immediately.
    // In step mode, wait for the first Tab key before announcing/selecting any option.
    if (scanMode == 'auto') {
      _announceCurrentButton();
    }
    
    debugPrint('FavoritesPage: Scan mode: $scanMode');
    
    if (scanMode == 'auto') {
      debugPrint('FavoritesPage: Setting up periodic timer for auto mode...');
      _scanningTimer = Timer(Duration(milliseconds: _scanDelay), () {
        _scanNext();
      });
    } else {
      debugPrint('FavoritesPage: Step mode - timer not started, Tab key will advance');
    }
  }

  void _scanNext() {
    if (!_isScanning || _scanningOff || _isAnnouncing) return;
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    
    final buttons = _showingArticles ? _articleOptions : _favoriteButtons;
    final totalButtons = buttons.length + 1; // +1 for Go Back button
    
    setState(() {
      _scanningIndex++;
      if (_scanningIndex >= totalButtons) {
        _scanningIndex = -1; // Reset to Go Back button
        _scanCycleCount++;
        
        // Check scan loop limit
        if (_scanLoopLimit > 0 && _scanCycleCount >= _scanLoopLimit) {
          _pauseScanning();
          return;
        }
      }
    });
    
    // Announce current button
    _announceCurrentButton();
    
    // Schedule next scan only in auto mode
    if (scanMode == 'auto') {
      _scanningTimer = Timer(Duration(milliseconds: _scanDelay), () {
        _scanNext();
      });
    }
  }

  void _announceCurrentButton() async {
    try {
      String text;
      if (_scanningIndex == -1) {
        text = 'Go Back';
      } else {
        final buttons = _showingArticles ? _articleOptions : _favoriteButtons;
        if (_scanningIndex < buttons.length) {
          final button = buttons[_scanningIndex];
          text = _showingArticles ? (button['summary'] ?? button['text'] ?? '') : (button['text'] ?? '');
        } else {
          return;
        }
      }
      
      if (text.isNotEmpty) {
        await _speakScanningPrompt(text);
      }
    } catch (e) {
      debugPrint('Error announcing current button: $e');
    }
  }

  void _stopScanning() {
    _scanningTimer?.cancel();
    _scanningTimer = null;
    setState(() {
      _isScanning = false;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _scanningIndex = -1;
    });
  }

  void _pauseScanning() {
    _scanningTimer?.cancel();
    _scanningTimer = null;
    setState(() {
      _isScanning = false;
      _isScanningPaused = true;
      _waitingForUserInput = true;
    });
  }

  void _resumeScanning() {
    if (_isScanningPaused) {
      setState(() {
        _isScanningPaused = false;
        _waitingForUserInput = false;
        _isScanning = true;
      });
      _scanNext();
    }
  }

  void _handleSpacebarPress() {
    debugPrint('FavoritesPage: Spacebar pressed - _waitingForUserInput=$_waitingForUserInput, _isScanningPaused=$_isScanningPaused, _isScanning=$_isScanning, _scanningIndex=$_scanningIndex');
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    if (_isAnnouncing) {
      debugPrint('FavoritesPage: Spacebar ignored while announcement is in progress');
      return;
    }

    if (scanMode == 'step' && _isScanning && _scanningIndex < 0) {
      debugPrint('FavoritesPage: Spacebar ignored in step mode until first Tab advances scan');
      return;
    }
    
    if (_waitingForUserInput || _isScanningPaused) {
      debugPrint('FavoritesPage: Spacebar - Resuming scanning from paused state');
      _resumeScanning();
    } else if (_isScanning) {
      // Select current button
      debugPrint('FavoritesPage: Spacebar - Selecting button at index $_scanningIndex');
      if (_scanningIndex == -1) {
        _handleBackButton();
      } else {
        final buttons = _showingArticles ? _articleOptions : _favoriteButtons;
        if (_scanningIndex < buttons.length) {
          final button = buttons[_scanningIndex];
          if (_showingArticles) {
            _handleArticleButtonPress(button);
          } else {
            _handleFavoriteButtonPress(button);
          }
        }
      }
    }
  }

  // Add platform channel for audio routing (like main.dart)
  static const platform = MethodChannel('audio_routing');

  Future<void> _announceViaBuiltinSpeaker(String text) async {
    await announceViaBackend(text, routing: 'system');
  }

  Future<bool> _playAudioAndWaitForCompletion(
    AudioPlayer player, {
    required String text,
    required String label,
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<PlayerState> stateSub;

    stateSub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    try {
      await player.play();

      final wordCount = text
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
      final estimatedDurationMs = (wordCount * 700) + 3000;
      final mediaDurationMs = player.duration?.inMilliseconds ?? 0;
      int timeoutMs = estimatedDurationMs;
      if (mediaDurationMs > 0) {
        final mediaBasedTimeoutMs = mediaDurationMs + 2500;
        if (mediaBasedTimeoutMs > timeoutMs) {
          timeoutMs = mediaBasedTimeoutMs;
        }
      }
      timeoutMs = timeoutMs.clamp(5000, 120000);

      debugPrint(
        'FavoritesPage $label: Waiting for playback completion (timeout: ${timeoutMs}ms)',
      );

      await completer.future.timeout(Duration(milliseconds: timeoutMs));
      debugPrint('FavoritesPage $label: Playback completed within timeout');
      return true;
    } on TimeoutException {
      debugPrint(
        '⚠️ FavoritesPage $label: Playback completion timeout - forcing stop and fallback',
      );
      try {
        await player.stop();
      } catch (_) {}
      return false;
    } catch (e) {
      debugPrint('FavoritesPage $label: Playback failed: $e');
      return false;
    } finally {
      await stateSub.cancel();
    }
  }

  /// Announce using the backend TTS (same robust method as main.dart)
  Future<void> announceViaBackend(
    String text, {
    String routing = 'system',
    int? speechRate,
  }) async {
    final announceStart = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[TIMER] FavoritesPage announceViaBackend("$text") at $announceStart');
    final wasAnnouncing = _isAnnouncing;
    bool wakeWordPausedForAnnouncement = false;
    _scanningTimer?.cancel();
    _scanningTimer = null;
    if (mounted) {
      setState(() {
        _isAnnouncing = true;
      });
    } else {
      _isAnnouncing = true;
    }
    
    // Special handling for jokes - detect if text contains a question followed by an answer
    final jokePattern = RegExp(r'^(.+\?)\s*(.+[!.])$');
    final jokeMatch = jokePattern.firstMatch(text);
    
    if (jokeMatch != null) {
      final question = jokeMatch.group(1)?.trim() ?? '';
      final punchline = jokeMatch.group(2)?.trim() ?? '';
      
      debugPrint('FavoritesPage JOKE DETECTED: Question="$question" Punchline="$punchline"');
      
      // Announce the question first
      await announceViaBackend(question, routing: routing, speechRate: speechRate);
      
      // Add a 0.5-second pause
      await Future.delayed(Duration(milliseconds: 500));
      
      // Then announce the punchline
      await announceViaBackend(punchline, routing: routing, speechRate: speechRate);
      
      return; // Exit early for jokes
    }
    
    String idToken = widget.idToken;
    try {
      if (!wasAnnouncing) {
        try {
          debugPrint('FavoritesPage announceViaBackend: Pausing wake-word service for announcement');
          WakeWordService.wakeWordShouldBeActive = false;
          WakeWordService.pauseWakeWordService();
          await WakeWordService.pauseSpeechRecognition();
          wakeWordPausedForAnnouncement = true;
        } catch (wakePauseError) {
          debugPrint('FavoritesPage announceViaBackend: Failed to pause wake-word service: $wakePauseError');
        }
      }

      final startTotal = DateTime.now();

      debugPrint('[TIMER] FavoritesPage announceViaBackend: START for "$text" at ${startTotal.millisecondsSinceEpoch}');
      // Always refresh the token before backend call
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final refreshedToken = await user.getIdToken(true);
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
            debugPrint('FavoritesPage announceViaBackend: Token refreshed successfully');
          } else {
            debugPrint('FavoritesPage announceViaBackend: Token refresh returned null/empty, using original token');
          }
        } else {
          debugPrint('FavoritesPage announceViaBackend: No current user, using original token');
        }
      } catch (e) {
        debugPrint('FavoritesPage announceViaBackend: Token refresh failed: $e, using original token');
      }
      
      bool backendAudioPlayed = false;
      final startRequest = DateTime.now();
      debugPrint('[TIMER] FavoritesPage announceViaBackend: Requesting backend audio for "$text" at ${startRequest.millisecondsSinceEpoch}');
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/play-audio'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': text, 
          'routing_target': routing,
          if (speechRate != null) 'speech_rate': speechRate,
        }),
      );
      final endRequest = DateTime.now();
      debugPrint('[TIMER] FavoritesPage announceViaBackend: Backend response received at ${endRequest.millisecondsSinceEpoch} (delta: ${endRequest.difference(startRequest).inMilliseconds} ms)');
      debugPrint('FavoritesPage announceViaBackend: Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final audioUrl = RegExp('"audio_url"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        final base64Audio = RegExp('"audio_data"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audioContent"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        
        try {
          if (!kIsWeb && Platform.isIOS) {
            final player = AudioPlayer();
            await _flutterTts?.stop();
            await player.stop();
            debugPrint('[TIMER] FavoritesPage announceViaBackend: Before forceSpeaker (iOS) at ${DateTime.now().millisecondsSinceEpoch}');
            await platform.invokeMethod('forceSpeaker');
            debugPrint('[TIMER] FavoritesPage announceViaBackend: Before silence.mp3 warmup at ${DateTime.now().millisecondsSinceEpoch}');
            
            final silenceStart = DateTime.now();
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
              
              debugPrint('FavoritesPage iOS: silence.mp3 warmup completed successfully');
              await Future.delayed(const Duration(milliseconds: 150));
              
            } catch (e) {
              debugPrint('FavoritesPage announceViaBackend: silence.mp3 playback failed: $e');
            }
            final silenceEnd = DateTime.now();
            debugPrint('[TIMER] FavoritesPage announceViaBackend: After silence.mp3 warmup at ${silenceEnd.millisecondsSinceEpoch} (delta: ${silenceEnd.difference(silenceStart).inMilliseconds} ms)');
            await platform.invokeMethod('resetToDefault');
            await platform.invokeMethod('forceSpeaker');
            
            // Play base64 audio or audio URL
            if (base64Audio != null && base64Audio.isNotEmpty) {
              debugPrint('FavoritesPage announceViaBackend: Playing base64 audio (preferred)');
              final base64Start = DateTime.now();
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File('${tempDir.path}/favorites_tts.mp3').create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);

              final playedToCompletion = await _playAudioAndWaitForCompletion(
                player,
                text: text,
                label: 'announceViaBackend iOS base64',
              );

              if (playedToCompletion) {
                final base64End = DateTime.now();
                debugPrint('[TIMER] FavoritesPage announceViaBackend: After base64 audio playback at ${base64End.millisecondsSinceEpoch} (delta: ${base64End.difference(base64Start).inMilliseconds} ms)');
                backendAudioPlayed = true;
              } else {
                debugPrint('FavoritesPage announceViaBackend: iOS base64 playback incomplete - falling back to local TTS');
              }
              await Future.delayed(const Duration(milliseconds: 100));
              await platform.invokeMethod('resetToDefault');
              await tempFile.delete();
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              try {
                await platform.invokeMethod('forceSpeaker');
                debugPrint('[TIMER] FavoritesPage announceViaBackend: Before setUrl/play audioUrl at ${DateTime.now().millisecondsSinceEpoch}');
                final audioUrlStart = DateTime.now();
                await player.setUrl(audioUrl);

                final playedToCompletion = await _playAudioAndWaitForCompletion(
                  player,
                  text: text,
                  label: 'announceViaBackend iOS audioUrl',
                );

                if (playedToCompletion) {
                  final audioUrlEnd = DateTime.now();
                  debugPrint('[TIMER] FavoritesPage announceViaBackend: After audioUrl playback at ${audioUrlEnd.millisecondsSinceEpoch} (delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms)');
                  backendAudioPlayed = true;
                } else {
                  debugPrint('FavoritesPage announceViaBackend: iOS audioUrl playback incomplete - falling back to local TTS');
                }
                await Future.delayed(const Duration(milliseconds: 100));
                await platform.invokeMethod('resetToDefault');
              } catch (e) {
                debugPrint('FavoritesPage announceViaBackend: setUrl/play failed for audioUrl: $e');
              }
            }
            await player.dispose();
          } else if (!kIsWeb && Platform.isAndroid) {
            final player = AudioPlayer();
            await _flutterTts?.stop();
            await player.stop();
            debugPrint('[TIMER] FavoritesPage announceViaBackend: Before forceSpeaker (Android) at ${DateTime.now().millisecondsSinceEpoch}');
            
            try {
              await platform.invokeMethod('forceSpeaker');
              debugPrint('FavoritesPage Android forceSpeaker call completed successfully');
              
              debugPrint('FavoritesPage Android: Waiting additional 300ms for complete routing setup...');
              await Future.delayed(const Duration(milliseconds: 300));
              debugPrint('FavoritesPage Android: Audio routing setup complete');
            } catch (e) {
              debugPrint('FavoritesPage Android forceSpeaker call FAILED: $e');
            }
            
            // Android audio priming with silence.mp3
            debugPrint('[TIMER] FavoritesPage announceViaBackend: Before silence.mp3 priming (Android) at ${DateTime.now().millisecondsSinceEpoch}');
            final silenceStart = DateTime.now();
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
              
              debugPrint('FavoritesPage Android: silence.mp3 priming completed successfully');
              await Future.delayed(const Duration(milliseconds: 200));
              
            } catch (e) {
              debugPrint('FavoritesPage Android: silence.mp3 priming failed: $e');
            }
            final silenceEnd = DateTime.now();
            debugPrint('[TIMER] FavoritesPage announceViaBackend: After silence.mp3 priming at ${silenceEnd.millisecondsSinceEpoch} (delta: ${silenceEnd.difference(silenceStart).inMilliseconds} ms)');
            
            // Play base64 audio (preferred) or audio URL
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              debugPrint('FavoritesPage Android: Using base64 audio (PREFERRED - faster than audioUrl)');
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File('${tempDir.path}/favorites_tts.mp3').create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              
              final completer = Completer<void>();
              final sub = player.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) completer.complete();
                }
              });
              await player.play();
              await completer.future;
              await sub.cancel();
              
              final base64End = DateTime.now();
              debugPrint('[TIMER] FavoritesPage announceViaBackend: Android base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms');
              await Future.delayed(const Duration(milliseconds: 100));
              
              try {
                await platform.invokeMethod('resetToDefault');
                debugPrint('FavoritesPage Android resetToDefault call completed successfully after base64 playback');
              } catch (e) {
                debugPrint('FavoritesPage Android resetToDefault call FAILED after base64 playback: $e');
              }
              await tempFile.delete();
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              final audioUrlStart = DateTime.now();
              debugPrint('FavoritesPage Android: Fallback to audioUrl (slower than base64) for: $audioUrl');
              
              try {
                await player.setUrl(audioUrl);
                
                final completer = Completer<void>();
                final sub = player.playerStateStream.listen((state) {
                  if (state.processingState == ProcessingState.completed) {
                    if (!completer.isCompleted) completer.complete();
                  }
                });
                await player.play();
                await completer.future;
                await sub.cancel();
                
                debugPrint('FavoritesPage Android: AudioUrl playback completed successfully');
                backendAudioPlayed = true;
              } catch (e) {
                debugPrint('FavoritesPage Android ERROR: AudioUrl playback failed: $e');
                backendAudioPlayed = false;
              }
              
              final audioUrlEnd = DateTime.now();
              debugPrint('[TIMER] FavoritesPage announceViaBackend: Android audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms');
              await Future.delayed(const Duration(milliseconds: 100));
              
              try {
                await platform.invokeMethod('resetToDefault');
                debugPrint('FavoritesPage Android resetToDefault call completed successfully after audioUrl playback');
              } catch (e) {
                debugPrint('FavoritesPage Android resetToDefault call FAILED after audioUrl playback: $e');
              }
            }
            await player.dispose();
          } else {
            // Fallback for Web or other platforms
            debugPrint('FavoritesPage announceViaBackend: Using fallback just_audio for Web/other platforms');
            final player = AudioPlayer();
            
            await Future.delayed(const Duration(milliseconds: 100));
            debugPrint('FavoritesPage Fallback: Audio session warmup delay completed');
            
            if (audioUrl != null && audioUrl.isNotEmpty) {
              final audioUrlStart = DateTime.now();
              await player.setUrl(audioUrl);
              
              final completer = Completer<void>();
              final sub = player.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) completer.complete();
                }
              });
              
              await player.play();
              await completer.future;
              await sub.cancel();
              
              final audioUrlEnd = DateTime.now();
              debugPrint('[TIMER] FavoritesPage announceViaBackend: Fallback audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms');
              backendAudioPlayed = true;
            } else if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File('${tempDir.path}/favorites_tts.mp3').create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              
              final completer = Completer<void>();
              final sub = player.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) completer.complete();
                }
              });
              
              await player.play();
              await completer.future;
              await sub.cancel();
              
              final base64End = DateTime.now();
              debugPrint('[TIMER] FavoritesPage announceViaBackend: Fallback base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms');
              await tempFile.delete();
              backendAudioPlayed = true;
            }
            await player.dispose();
          }
        } catch (e) {
          debugPrint('FavoritesPage announceViaBackend: Audio playback failed: $e');
          backendAudioPlayed = false;
        }
      } else {
        debugPrint('FavoritesPage announceViaBackend: Backend error ${response.statusCode}: ${response.body}');
      }
      
      // Fallback: use local TTS if backend audio not played
      if (!backendAudioPlayed) {
        debugPrint('FavoritesPage announceViaBackend: Fallback to local TTS for "$text"');
        
        // For system routing, force speaker to match backend behavior
        if (routing == 'system' && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
          try {
            debugPrint('FavoritesPage announceViaBackend: Forcing speaker for local TTS fallback');
            await platform.invokeMethod('forceSpeaker');
          } catch (e) {
            debugPrint('FavoritesPage announceViaBackend: forceSpeaker failed for local TTS: $e');
          }
        }
        
        await _flutterTts?.stop();
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('FavoritesPage Fallback TTS: Audio system warmup delay completed');
        
        final ttsCompleter = Completer<void>();
        _flutterTts?.setCompletionHandler(() {
          debugPrint('FavoritesPage announceViaBackend: Fallback TTS completion handler triggered for "$text"');
          if (!ttsCompleter.isCompleted) {
            debugPrint('FavoritesPage announceViaBackend: Fallback TTS completion confirmed');
            ttsCompleter.complete();
          }
        });
        debugPrint('FavoritesPage announceViaBackend: Starting fallback local TTS: "$text"');
        await _flutterTts?.speak(text);

        final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final estimatedDurationMs = (wordCount * 700) + 3000;
        final timeout = Duration(milliseconds: estimatedDurationMs.clamp(5000, 120000));

        debugPrint('FavoritesPage announceViaBackend: Waiting for fallback TTS completion (timeout: ${timeout.inMilliseconds}ms)');
        try {
          await ttsCompleter.future.timeout(timeout);
          debugPrint('FavoritesPage announceViaBackend: Fallback TTS completed within timeout');
        } on TimeoutException {
          debugPrint('⚠️ FavoritesPage announceViaBackend: Fallback TTS timeout after ${timeout.inMilliseconds}ms - forcing completion');
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        }

        debugPrint('FavoritesPage announceViaBackend: Clearing fallback TTS completion handler');
        _flutterTts?.setCompletionHandler(() {});
      }
      
      // Reset audio routing after announcement
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        try {
          debugPrint('FavoritesPage resetToDefault called after option announcement');
          await platform.invokeMethod('resetToDefault');
          
          if (Platform.isIOS) {
            await Future.delayed(const Duration(milliseconds: 200));
            debugPrint('FavoritesPage iOS: Audio routing restored to default/Bluetooth');
          }
        } catch (e) {
          debugPrint('FavoritesPage resetToDefault not implemented or failed: $e');
        }
      }
      
      final endTotal = DateTime.now();
      debugPrint('[TIMER] FavoritesPage announceViaBackend: END at ${endTotal.millisecondsSinceEpoch} (total delta: ${endTotal.difference(startTotal).inMilliseconds} ms)');
      
    } catch (e) {
      debugPrint('FavoritesPage announceViaBackend: Exception: $e');
      // Fallback: use local TTS if something fails
      
      if (routing == 'system' && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        try {
          await platform.invokeMethod('forceSpeaker');
        } catch (speakerError) {
          debugPrint('FavoritesPage announceViaBackend: forceSpeaker failed in exception handler: $speakerError');
        }
      }
      
      await _flutterTts?.stop();
      await Future.delayed(const Duration(milliseconds: 100));
      final ttsCompleter = Completer<void>();
      _flutterTts?.setCompletionHandler(() {
        debugPrint('FavoritesPage announceViaBackend: Exception fallback TTS completion handler triggered for "$text"');
        if (!ttsCompleter.isCompleted) {
          debugPrint('FavoritesPage announceViaBackend: Exception fallback TTS completion confirmed');
          ttsCompleter.complete();
        }
      });
      debugPrint('FavoritesPage announceViaBackend: Starting exception fallback local TTS: "$text"');
      await _flutterTts?.speak(text);

      final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final estimatedDurationMs = (wordCount * 700) + 3000;
      final timeout = Duration(milliseconds: estimatedDurationMs.clamp(5000, 120000));

      debugPrint('FavoritesPage announceViaBackend: Waiting for exception fallback TTS completion (timeout: ${timeout.inMilliseconds}ms)');
      try {
        await ttsCompleter.future.timeout(timeout);
        debugPrint('FavoritesPage announceViaBackend: Exception fallback TTS completed within timeout');
      } on TimeoutException {
        debugPrint('⚠️ FavoritesPage announceViaBackend: Exception fallback TTS timeout after ${timeout.inMilliseconds}ms - forcing completion');
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      }

      debugPrint('FavoritesPage announceViaBackend: Clearing exception fallback TTS completion handler');
      _flutterTts?.setCompletionHandler(() {});
    } finally {
      if (wakeWordPausedForAnnouncement && !wasAnnouncing) {
        try {
          debugPrint('FavoritesPage announceViaBackend: Restoring wake-word service after announcement');
          WakeWordService.wakeWordShouldBeActive = true;
          await WakeWordService.resumeWakeWordService();
        } catch (wakeResumeError) {
          debugPrint('FavoritesPage announceViaBackend: Failed to restore wake-word service: $wakeResumeError');
        }
      }

      if (mounted) {
        setState(() {
          _isAnnouncing = wasAnnouncing;
        });
      } else {
        _isAnnouncing = wasAnnouncing;
      }
      final announceEnd = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[TIMER] FavoritesPage ANNOUNCE END: announceViaBackend("$text") at $announceEnd (total delta: ${announceEnd - announceStart}ms)');
    }
  }

  void _cleanupResources() {
    _scanningTimer?.cancel();
    _announcementTimer?.cancel();
    _longWaitTimer?.cancel();
    _flutterTts?.stop();
    _audioPlayer?.dispose();
    _wakeWordService?.stopAllRecognizers();
    // Note: WakeWordService doesn't have a dispose method, cleanup is handled automatically
  }

  // --- UI Build Methods ---
  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        _cleanupResources();
      },
      child: Focus(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (node, KeyEvent event) {
          debugPrint('FavoritesPage: KeyEvent received: ${event.runtimeType}, key: ${event.logicalKey}');
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
            debugPrint('FavoritesPage: Space key detected, calling _handleSpacebarPress');
            _handleSpacebarPress();
            _keyboardFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
            // Tab key for step-mode scanning advancement
            final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
            final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
            
            debugPrint('FavoritesPage: Tab pressed: scanMode=$scanMode, isScanning=$_isScanning, _isAnnouncingScanningPrompt=$_isAnnouncingScanningPrompt');
            
            if (scanMode == 'step' && _isScanning && _isAnnouncingScanningPrompt) {
              debugPrint('FavoritesPage: Tab: Interrupting scanning announcement');
              // Interrupt the current scanning prompt announcement
              _flutterTts?.stop();
              if (mounted) {
                setState(() {
                  _isAnnouncingScanningPrompt = false;
                });
              }
            }
            
            if (scanMode == 'step' && _isScanning && _scanningIndex >= -1) {
              debugPrint('FavoritesPage: Tab: Advancing in step mode from index $_scanningIndex');
              // Advance to next option
              _scanNext();
            }
            _keyboardFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: Text(
              _showingArticles ? _currentTopic ?? 'Articles' : 'Favorites',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: _darkColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _handleBackButton,
            ),
            actions: [
              // Admin button (like other special pages)
              Consumer<UserSettingsProvider>(
                builder: (context, settingsProvider, child) {
                  return PopupMenuButton<String>(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onSelected: (value) async {
                      switch (value) {
                        case 'admin_pages':
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const AdminPagesButtonsPage(),
                          ));
                          break;
                        // Remove admin settings option for now since we don't have the constructor
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'admin_pages',
                        child: Text('Admin Pages'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Speech History
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Speech History:'),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _speechHistory = '';
                            });
                          },
                          child: const Text('Clear'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            textStyle: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 80,
                      child: TextField(
                        controller: TextEditingController(text: _speechHistory),
                        readOnly: true,
                        canRequestFocus: false,
                        enableInteractiveSelection: false,
                        showCursor: false,
                        maxLines: null,
                        focusNode: FocusNode(canRequestFocus: false), // Prevent focus!
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Main content area
              Expanded(child: _buildBody()),
              if (_voiceStatusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      border: Border.all(color: Colors.blueGrey.shade100),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _voiceStatusMessage,
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingView();
    }
    
    if (_statusMessage != null) {
      return _buildErrorView();
    }
    
    if (_showingArticles) {
      return _buildArticlesGrid();
    } else {
      return _buildFavoritesGrid();
    }
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Use the speech bubble spinner image with rotation animation
          AnimatedBuilder(
            animation: _animationController,
            builder: (_, child) {
              return Transform.rotate(
                angle: _animationController.value * 6.28318, // 2 * pi for full rotation
                child: Image.asset(
                  'assets/speech_bubble_spinner.png',
                  width: 100,
                  height: 100,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            _statusMessage ?? 'Loading...',
            style: TextStyle(
              fontSize: 18,
              color: _darkColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: _lightColor,
          ),
          const SizedBox(height: 16),
          Text(
            _statusMessage ?? 'An error occurred',
            style: TextStyle(
              fontSize: 18,
              color: _darkColor,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (_showingArticles) {
                _handleFavoriteButtonPress({
                  'text': _currentTopic,
                });
              } else {
                _loadFavoriteButtons();
              }
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesGrid() {
    // Add "Go Back" button as first item
    final allButtons = [
      {'text': 'Go Back', 'isBackButton': true},
      ..._favoriteButtons.where((btn) => btn['hidden'] != true),
    ];
    
    if (allButtons.length == 1) {
      // Only "Go Back" button - show no favorites message
      return _buildNoFavoritesView();
    }
    
    return _buildGrid(allButtons, isArticles: false);
  }

  Widget _buildArticlesGrid() {
    // Add "Go Back" button as first item
    final allButtons = [
      {'text': 'Go Back', 'isBackButton': true},
      ..._articleOptions,
    ];
    
    return _buildGrid(allButtons, isArticles: true);
  }

  Widget _buildGrid(List<Map<String, dynamic>> buttons, {required bool isArticles}) {
    final availableWidth = MediaQuery.of(context).size.width - 40; // Account for padding
    final spacing = 10.0;
    final gridPadding = 20.0;
    
    double effectiveButtonSize = (availableWidth / _gridColumns).clamp(40.0, _buttonSize);
    final double fontSize = ((effectiveButtonSize / 10) * 1.44).clamp(14.4, 25.9);
    
    return Container(
      color: Colors.grey[100],
      padding: EdgeInsets.all(gridPadding),
      child: Scrollbar(
        thumbVisibility: true,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _gridColumns,
            childAspectRatio: 1.0,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: buttons.length,
          itemBuilder: (context, index) {
            final button = buttons[index];
            final isBackButton = button['isBackButton'] == true;
            final label = isBackButton 
                ? 'Go Back' 
                : isArticles 
                    ? (button['summary'] ?? '')
                    : (button['text'] ?? '');
            
            if (isArticles && !isBackButton) {
              debugPrint('FavoritesPage: Article button label: "$label" (summary: "${button['summary']}", full: "${button['option']}")');
            }
            
            // Calculate scanning index (-1 for Go Back, then 0-based for other buttons)
            final buttonScanIndex = isBackButton ? -1 : index - 1;
            final isHighlighted = buttonScanIndex == _scanningIndex && (_isScanning || _isScanningPaused);
            
            return Padding(
              padding: const EdgeInsets.all(2.0),
              child: SizedBox(
                width: effectiveButtonSize,
                height: effectiveButtonSize,
                child: SpeechBubbleButton(
                  label: label,
                  onPressed: () async {
                    if (_isScanningPaused && _waitingForUserInput) {
                      _resumeScanning();
                    } else {
                      if (isBackButton) {
                        _handleBackButton();
                      } else if (isArticles) {
                        await _handleArticleButtonPress(button);
                      } else {
                        await _handleFavoriteButtonPress(button);
                      }
                    }
                  },
                  isActive: true,
                  isHighlighted: isHighlighted,
                  darkColor: _darkColor,
                  lightColor: _lightColor,
                  fontSize: fontSize,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoFavoritesView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 80,
            color: _lightColor,
          ),
          const SizedBox(height: 20),
          Text(
            'No Favorites Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _darkColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You haven\'t set up any favorite topics yet.\nUse the web admin to add your favorites.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          // Still show Go Back button
          SizedBox(
            width: 200,
            height: 60,
            child: SpeechBubbleButton(
              label: 'Go Back',
              onPressed: _handleBackButton,
              isActive: true,
              isHighlighted: _scanningIndex == -1 && (_isScanning || _isScanningPaused),
              darkColor: _darkColor,
              lightColor: _lightColor,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}
