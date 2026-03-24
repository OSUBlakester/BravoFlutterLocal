import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'services/user_settings_provider.dart';
import 'services/pictogram_service.dart';
import 'services/sight_word_service.dart';

import 'services/audio_device_service.dart';
import 'services/wake_word_service.dart';
import 'config/environment_config.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'admin_settings_scaffold.dart';
import 'admin_pages_buttons.dart';
import 'user_current_admin_page.dart';
import 'user_info_admin_page.dart';
import 'user_diary_admin_page.dart';
import 'audio_device_admin_page.dart';
import 'services/authenticated_http_client.dart';

// Font helper - using default system font to avoid AssetManifest.json errors on Android
String? _safeRobotoCondensed() {
  return null; // Use default system font (GoogleFonts causes unhandled async exceptions)
}

class FreestylePage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;
  final String? sourceContext;  // The context/topic from the originating page (LLM query)
  final String? sourcePage;     // The page name that led to freestyle  
  final bool isLLMGenerated;    // Whether the source was LLM-generated
  final String? originatingButtonText; // The text of the button that started the LLM query
  final void Function(String text)? onComposeAppend;

  const FreestylePage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
    this.sourceContext,
    this.sourcePage,
    this.isLLMGenerated = false,
    this.originatingButtonText,
    this.onComposeAppend,
  });

  @override
  State<FreestylePage> createState() => _FreestylePageState();
}

class _FreestylePageState extends State<FreestylePage> {
  // --- Audio session initialization tracking ---
  static bool _audioSessionInitialized = false;
  
  // --- Build Space ---
  String _buildSpaceText = "";
  final TextEditingController _buildSpaceController = TextEditingController();
  Timer? _buildSpaceDebounceTimer;
  
  // --- Word Options ---
  List<String> _currentWordOptions = [];
  bool _isLoadingWordOptions = false;
  
  // --- Spelling Modal ---
  bool _isSpellingModalOpen = false;
  String _currentSpellingWord = "";
  final TextEditingController _spellingWordController = TextEditingController();
  List<String> _currentPredictions = [];
  List<String> _validLetters = [];
  
  // --- Choose Word Modal ---
  bool _isChooseWordModalOpen = false;
  String _currentChooseWordCategory = "";
  List<String> _currentCategoryWords = [];
  bool _isLoadingCategoryWords = false;
  
  // --- Context-Aware Features ---
  String _currentContext = "";  // Current context for word generation
  bool _isFirstRound = true;    // Track if this is the first round (single words only)
  String _initialContext = "";  // Initial context (simplified for LLM pages)
  bool _initialIsFirstRound = true;  // Initial first-round setting (false for LLM pages)
  
  // Word categories for Choose Word feature
  final List<String> _wordCategories = [
    'People',
    'Places',  
    'Animals',
    'Around the House',
    'In the Room',
    'General things',
    'Actions',
    'Feelings & Emotions',
    'Questions & Comments',
    'Times and Dates',
    'Activities & Hobbies',
    'Medical & Health',
    'Food & Drinks',
    'Colors & Descriptions',
    'Numbers & Quantities',
    'School & Learning',
    'Transportation',
    'Weather',
    'Technology',
    'Sports & Games'
  ];
  
  // --- Scanning ---
  Timer? _scanningTimer;
  int? _scanningIndex;
  bool _isScanning = false;
  FocusNode? _gridFocusNode;
  String _currentScanningContext = "main"; // "main", "spelling-letters", "spelling-predictions"
  int _currentScanCycle = 0;
  bool _isScanningPaused = false;
  bool _waitingForUserInput = false;
  bool _isAnnouncingScanningPrompt = false;  // Track if announcing during scanning prompts (for Tab interrupt)
  
  // Wait-for-switch feature tracking
  bool _waitingForInitialSwitch = false;
  bool _switchStartRequested = false;
  
  // --- TTS ---
  late FlutterTts _flutterTts;
  
  // --- Wake Word Service ---
  WakeWordService? _wakeWordService;
  String? _wakeWordInterjection;
  String? _wakeWordName;
  List<String> _wakeWordVariants = [];

  // --- Basic Status Tracking ---
bool _microphoneEnabled = false;
String statusMessage = '';
  
  // --- Loading ---
  bool _isLoading = false;
  bool _isAnnouncementPlaying = false;
  
  // --- Admin ---
  bool _isAdminToolbarLocked = true;
  String? _currentPIN = '1234';
  int _pinAttempts = 0;
  
  // --- Status ---
  String? _statusMessage = '';

  // --- SPEECH BUBBLE OVERLAY VARIABLES ---
  bool _showSpeechBubble = false; // Track if speech bubble is visible
  String _speechBubbleText = ''; // Text to display in speech bubble
  Timer? _speechBubbleTimer; // Timer to auto-hide speech bubble

  // --- STATUS MESSAGE AUTO-RESET ---
  Timer? _statusMessageTimer; // Timer to auto-reset long status messages

  // --- DISPOSAL TRACKING ---
  bool _disposeCalled = false; // Track if dispose has been called
  
  // --- WAKE WORD HEALTH CHECK ---
  Timer? _wakeWordHealthCheckTimer; // Periodic check to ensure wake word service is running


// Fix the initState method - remove the blocking delay
@override
void initState() {
  super.initState();
  _flutterTts = FlutterTts();
  _gridFocusNode = FocusNode();
  
  // Initialize spelling word with valid letters
  _validLetters = _getAllLetters();
  
  // Initialize context-aware features
  _initializeContext();
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Initialize audio session first thing on app startup
    if (!_audioSessionInitialized) {
      debugPrint('FreestylePage: Initializing audio session...');
      await _initializeAudioSession();
      _audioSessionInitialized = true;
    }
    
    // Load initial word options
    await _loadWordOptions();
    
    // CRITICAL FIX: Start scanning immediately - don't wait for wake word service
    debugPrint('FreestylePage: Starting scanning immediately');
    _maybeStartScanning();
    
    // CRITICAL FIX: Initialize wake word service in parallel - don't block scanning
    debugPrint('🎤 Freestyle: Starting wake word service initialization in background');
    _initializeWakeWordService().then((_) {
      debugPrint('🎤 Freestyle: Wake word service initialization completed');
      // Start health check after wake word service is ready
      _startWakeWordHealthCheck();
    }).catchError((error) {
      debugPrint('🎤 Freestyle: Wake word service initialization failed: $error');
    });
  });
}


// Fix the initialization to completely stop any existing wake word service first
Future<void> _initializeWakeWordService() async {
  try {
    debugPrint('🎤 Freestyle: _initializeWakeWordService - START');
    
    // CRITICAL FIX: Stop any existing wake word service completely before creating new one
    debugPrint('🎤 Freestyle: Checking for existing WakeWordService instances and stopping them');
    
    // If there's already a service running from main page, stop it completely
    if (_wakeWordService != null) {
      debugPrint('🎤 Freestyle: Found existing WakeWordService, stopping it completely');
      await _wakeWordService!.stopAllRecognizers();
      await _wakeWordService!.stopWakeWordListening();
      _wakeWordService = null;
    }
    
    // EXTRA SAFETY: Add delay to ensure old sessions are completely terminated
    debugPrint('🎤 Freestyle: Waiting for old wake word sessions to terminate completely');
    await Future.delayed(const Duration(milliseconds: 1000));
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    
    _wakeWordInterjection = (settingsProvider.settings?.wakeWordInterjection ?? 'hey').trim().toLowerCase();
    _wakeWordName = (settingsProvider.settings?.wakeWordName ?? 'bravo').trim().toLowerCase();
    _wakeWordVariants = [
      '${_wakeWordInterjection} ${_wakeWordName}',
      '${_wakeWordInterjection}, ${_wakeWordName}',
      '${_wakeWordInterjection},${_wakeWordName}',
    ];
    debugPrint('🎤 Freestyle: Wake word variants configured: \'${_wakeWordVariants.join("' | '")}\'');
    
    // CRITICAL: Create completely fresh WakeWordService instance
    debugPrint('🎤 Freestyle: Creating completely fresh WakeWordService instance');
    _wakeWordService = WakeWordService(
      wakeWords: _wakeWordVariants,
    );
    
    // CRITICAL: Set global flag and IMMEDIATELY reset the _shouldRestartWakeWordListening flag
    debugPrint('🎤 Freestyle: Setting WakeWordService.wakeWordShouldBeActive = true');
    WakeWordService.wakeWordShouldBeActive = true;
    
    // CRITICAL FIX: IMMEDIATELY call resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true
    // This ensures the NEW service has the correct restart flag, regardless of old sessions
    debugPrint('🎤 Freestyle: IMMEDIATELY calling resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true on NEW service');
    _wakeWordService?.resumeWakeWordAutoRestart();
    
    // Set up callbacks AFTER resetting the flag
    debugPrint('🎤 Freestyle: Setting up callbacks');
    _initializeWakeWordCallbacks();
    
    setState(() {
      _microphoneEnabled = true;
    });
    
    debugPrint('🎤 Freestyle: Wake word service initialization complete with fresh session');
    
  } catch (e) {
    debugPrint('❌ Freestyle: Error initializing WakeWordService: $e');
  }
}



// Add a dedicated method to explicitly reset the _shouldRestartWakeWordListening flag
void _ensureWakeWordAutoRestartEnabled() {
  debugPrint('🎤 Freestyle: _ensureWakeWordAutoRestartEnabled called');
  
  if (_wakeWordService == null) {
    debugPrint('🎤 Freestyle: Wake word service is null, cannot reset restart flag');
    return;
  }
  
  // Set global flag
  WakeWordService.wakeWordShouldBeActive = true;
  
  // CRITICAL: Reset the internal _shouldRestartWakeWordListening flag
  debugPrint('🎤 Freestyle: Explicitly calling resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true');
  _wakeWordService?.resumeWakeWordAutoRestart();
  
  debugPrint('🎤 Freestyle: Wake word auto-restart should now be enabled');
}



// Fix the _initializeWakeWordCallbacks method - remove the non-existent onError callback
void _initializeWakeWordCallbacks() {
  if (_wakeWordService == null) return;
  
  debugPrint('🎤 Freestyle: Setting up callbacks with exact main.dart pattern');
  
  // EXACT SAME shouldAllowWakeWordRestart logic as main.dart
  _wakeWordService!.shouldAllowWakeWordRestart = () {
    final shouldAllow = mounted && !_disposeCalled;
    debugPrint('🎤 Freestyle: shouldAllowWakeWordRestart called - returning: $shouldAllow (mounted: $mounted, disposeCalled: $_disposeCalled)');
    return shouldAllow;
  };
  
 
// Find the onWakeWord callback in _initializeWakeWordCallbacks() and replace it with this:
_wakeWordService!.onWakeWord = (transcript) async {
  debugPrint('🎤 Freestyle: Wake word detected - navigating back to main page and triggering wake word process: "$transcript"');
  
  if (!mounted) {
    debugPrint('🎤 Freestyle: Widget not mounted, skipping navigation');
    return;
  }
  
  // Stop scanning on freestyle page immediately
  _stopAuditoryScanning();
  
  // Store the wake word detection for the main page to pick up
  debugPrint('🎤 Freestyle: Setting global flag for main page wake word trigger');
  WakeWordService.pendingWakeWordFromFreestyle = transcript;
  
  // Navigate back to main page IMMEDIATELY
  debugPrint('🎤 Freestyle: Navigating back to main page NOW');
  Navigator.of(context).pop(); // Return to main grid page immediately
};


  // REMOVE THE onError CALLBACK - IT DOESN'T EXIST
  // The timeout handling needs to be done in the onAnnounce callback instead
  
  // Enhanced timeout handling in onAnnounce callback
  _wakeWordService!.onAnnounce = (msg) async {
    debugPrint('🎤 Freestyle: onAnnounce called with: "$msg"');
    
    // For timeout messages, DON'T announce them on freestyle page - just silently restart
    if (msg.contains("I didn't hear anything") || msg.contains("Try again")) {
      debugPrint('🎤 Freestyle: Detected timeout announcement - IMMEDIATELY restarting wake word service');
      
      // CRITICAL: Immediately call resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true
      _wakeWordService?.resumeWakeWordAutoRestart();
      
      debugPrint('🎤 Freestyle: Wake word service restarted after timeout announcement');
    } else {
      // For non-timeout messages, announce them normally
      debugPrint('🎤 Freestyle: Non-timeout message, announcing: "$msg"');
      await _announceWithTimeout(msg, routing: 'system');
    }
  };
  
  // CRITICAL: Handle status updates without interfering with scanning
  _wakeWordService!.onStatusBarUpdate = (heardText) {
    if (!mounted) return;
    
    // Only update status if we actually heard something
    if (heardText.isNotEmpty) {
      debugPrint('🎤 Freestyle: Wake word service heard: "$heardText"');
      // Don't update UI status to avoid interfering with scanning - just log it
    }
  };
  
  debugPrint('🎤 Freestyle: Callbacks initialized with main.dart pattern');
}


// Update _forceRestartWakeWordService to explicitly reset the flag
Future<void> _forceRestartWakeWordService() async {
  debugPrint('🎤 Freestyle: _forceRestartWakeWordService called');
  
  if (_wakeWordService == null) return;
  
  try {
    // CRITICAL: Explicitly ensure auto-restart is enabled FIRST
    debugPrint('🎤 Freestyle: Ensuring wake word auto-restart is enabled before restart');
    _ensureWakeWordAutoRestartEnabled();
    
    // EXACT SAME PATTERN AS MAIN.DART _forceRestartWakeWordService
    debugPrint('🎤 Freestyle: waiting for audio session to stabilize');
    await Future.delayed(const Duration(milliseconds: 1500));
    
    // Always resume auto-restart first (like main.dart)
    debugPrint('🎤 Freestyle: calling resumeWakeWordAutoRestart');
    _wakeWordService!.resumeWakeWordAutoRestart();
    debugPrint('🎤 Freestyle: resumed auto-restart');
    
    // Wait a moment for any pending operations
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Don't check isListening - always force a restart for timeout recovery (like main.dart)
    debugPrint('🎤 Freestyle: forcing restart regardless of current state');
    
    // Start listening - the resumeWakeWordAutoRestart() now handles this automatically (like main.dart)
    await _wakeWordService!.startWakeWordListening();
    debugPrint('🎤 Freestyle: started wake word listening');
    
    // Verify it started
    await Future.delayed(const Duration(milliseconds: 500));
    if (_wakeWordService!.isListening) {
      debugPrint('🎤 Freestyle: SUCCESS - service is now listening and _shouldRestartWakeWordListening should be TRUE');
    } else {
      debugPrint('🎤 Freestyle: WARNING - service may not be listening properly, trying one more reset');
      
      // One more attempt
      _ensureWakeWordAutoRestartEnabled();
      await Future.delayed(const Duration(milliseconds: 300));
      await _wakeWordService!.startWakeWordListening();
      
      final finalListening = _wakeWordService!.isListening;
      debugPrint('🎤 Freestyle: Final attempt result - isListening: $finalListening');
    }
    
  } catch (e) {
    debugPrint('🎤 Freestyle: Error in _forceRestartWakeWordService: $e');
  }
}



// Remove the _startWakeWordHealthCheck method and replace with simple version
void _startWakeWordHealthCheck() {
  // Since we're now using the exact main.dart pattern, we don't need aggressive restarts
  // Just keep a simple health check that logs the service status
  debugPrint('🔍 FreestylePage: Wake word service initialized with main.dart pattern');
  
  // Optional: Keep a very light health check every 60 seconds just for logging
  _wakeWordHealthCheckTimer = Timer.periodic(Duration(seconds: 60), (timer) {
    if (_disposeCalled || !mounted) {
      timer.cancel();
      return;
    }
    
    if (_wakeWordService != null) {
      final isListening = _wakeWordService!.isListening;
      debugPrint('🔍 FreestylePage: Wake word service health check - isListening: $isListening');
    }
  });
}







// Update dispose method
@override
void dispose() {
  _disposeCalled = true;
  
  _scanningTimer?.cancel(); // Fixed: was scanningTimer, should be _scanningTimer
  _speechBubbleTimer?.cancel();
  _wakeWordHealthCheckTimer?.cancel();
  _statusMessageTimer?.cancel(); // This was also missing from the current dispose
  _buildSpaceDebounceTimer?.cancel(); // This was also missing
  
  // Clean up wake word service
  debugPrint('🎤 Freestyle: dispose - Cleaning up wake word service');
  if (_wakeWordService != null) {
    _wakeWordService!.stopWakeWordListening();
    _wakeWordService!.stopAllRecognizers();
  }
  
  _gridFocusNode?.dispose(); // Fixed: was gridFocusNode, should be _gridFocusNode
  _buildSpaceController.dispose(); // This was also missing
  _spellingWordController.dispose(); // This was also missing
  
  super.dispose();
}



  // --- Audio session initialization helper ---
  Future<void> _initializeAudioSession() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        debugPrint('_initializeAudioSession: Starting audio session initialization...');
        final platform = MethodChannel('audio_routing');
        final player = AudioPlayer();
        
        if (Platform.isIOS) {
          // Force speaker and play silence to initialize the audio session (same as announceViaBackend)
          await platform.invokeMethod('forceSpeaker');
          debugPrint('_initializeAudioSession: Playing silence.mp3 to warm up audio session...');
          
          await player.setAsset('assets/silence.mp3');
          
          // Wait for playback to complete (same pattern as announceViaBackend)
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
          debugPrint('_initializeAudioSession: iOS audio session initialized successfully');
        } else {
          // For Android, play silence to warm up audio session
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
          
          debugPrint('_initializeAudioSession: Android audio session initialized successfully');
        }
      } catch (e) {
        debugPrint('_initializeAudioSession: Error initializing audio session: $e');
      }
    }
  }

  // --- Context initialization ---
  void _initializeContext() {
    // Initialize context based on source information
    String? rawContext = widget.sourceContext ?? "general communication";
    
    // For LLM-generated pages, extract simple context from the prompt or use page name
    if (widget.isLLMGenerated == true && rawContext.length > 100) {
      // The context is likely an LLM generation prompt (contains formatting instructions)
      // Extract a simpler context for word option generation
      
      String simplifiedContext = widget.sourcePage ?? "general communication";
      
      // Strategy 1: Use originating button text if available (most reliable)
      if (widget.originatingButtonText != null && widget.originatingButtonText!.isNotEmpty) {
        simplifiedContext = widget.originatingButtonText!;
        debugPrint('🎯 FreestylePage: Using button text as context: "$simplifiedContext"');
      } else {
        // Strategy 2: Extract meaningful keywords from the prompt
        // Look for topic descriptions like "activity suggestions", "greetings", "questions about"
        final keywordPatterns = [
          RegExp(r'(activity|action)\s+suggestions?', caseSensitive: false),
          RegExp(r'(greeting|hello|goodbye|farewell)s?', caseSensitive: false),
          RegExp(r'(question|inquiry|queries)s?\s+(?:about\s+)?(.+?)(?:\.|,|based)', caseSensitive: false),
          RegExp(r'(conversation\s+starters?|topics?)', caseSensitive: false),
          RegExp(r'(express|expressive)\s+(.+?)(?:\.|,)', caseSensitive: false),
        ];
        
        for (final pattern in keywordPatterns) {
          final match = pattern.firstMatch(rawContext);
          if (match != null) {
            // Use the matched phrase as context
            simplifiedContext = match.group(0)!.trim();
            // Clean up "based on..." trailing text
            simplifiedContext = simplifiedContext.replaceAll(RegExp(r'\s+based\s*$'), '');
            debugPrint('🎯 FreestylePage: Extracted context from prompt: "$simplifiedContext"');
            break;
          }
        }
      }
      
      _currentContext = simplifiedContext;
      debugPrint('🎯 FreestylePage: Simplified LLM context from "${rawContext.substring(0, 50)}..." to "$_currentContext"');
      
      // For LLM-generated contexts, start with full phrases instead of single words
      // This ensures options match the LLM topic (e.g., full greetings, not just "hello")
      _isFirstRound = false;
      debugPrint('🎯 FreestylePage: Starting with full phrases for LLM-generated content');
    } else {
      _currentContext = rawContext;
      // For non-LLM pages (home, general), start with single words
      _isFirstRound = true;
    }
    
    // Store initial values for reset
    _initialContext = _currentContext;
    _initialIsFirstRound = _isFirstRound;
    
    debugPrint('🎯 FreestylePage: Initialized with context: "$_currentContext" (LLM generated: ${widget.isLLMGenerated})');
    debugPrint('🎯 FreestylePage: Originating button: "${widget.originatingButtonText}"');
    debugPrint('🎯 FreestylePage: Source page: "${widget.sourcePage}"');
    debugPrint('🎯 FreestylePage: First round (single words): $_isFirstRound');
  }

  // --- Auditory scanning methods ---
  void _maybeStartScanning() {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final isAuditoryEnabled = settingsProvider.settings?.enableAuditoryScanning ?? false;
    final waitForSwitch = settingsProvider.settings?.waitForSwitchToScan ?? false;
    
    debugPrint('FreestylePage _maybeStartScanning: called, enableAuditoryScanning = $isAuditoryEnabled, waitForSwitch = $waitForSwitch, current _isScanning = $_isScanning');
    
    if (!isAuditoryEnabled) {
      debugPrint('FreestylePage _maybeStartScanning: Auditory scanning disabled, stopping any existing scanning');
      _stopAuditoryScanning();
      return;
    }
    
    // Check if we should wait for switch press before starting
    if (waitForSwitch && !_isScanning && _currentWordOptions.isNotEmpty && !_waitingForInitialSwitch) {
      debugPrint('FreestylePage _maybeStartScanning: Waiting for switch press to begin scanning...');
      setState(() {
        _waitingForInitialSwitch = true;
        _switchStartRequested = false;
      });
      // Don't play prompt - only mood selection and first grid page should play it
      
      return; // IMPORTANT: Don't start scanning yet, wait for switch press
    }
    
    debugPrint('FreestylePage: Starting scanning');
    
    debugPrint('FreestylePage _maybeStartScanning: Auditory scanning enabled, calling _startAuditoryScanning()');
    _startAuditoryScanning();
    debugPrint('FreestylePage _maybeStartScanning: Method completed');
  }

  Future<void> _startAuditoryScanning() async {
    debugPrint('FreestylePage _startAuditoryScanning: called, current _isScanning=$_isScanning');
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final waitForSwitch = settingsProvider.settings?.waitForSwitchToScan ?? false;

    if (waitForSwitch && !_switchStartRequested) {
      debugPrint('FreestylePage _startAuditoryScanning: Switch not pressed, blocking scanning');
      return;
    }

    // CRITICAL: Don't start scanning if we're waiting for the user to press switch
    if (_waitingForInitialSwitch) {
      debugPrint('FreestylePage _startAuditoryScanning: Waiting for switch press, blocking scanning');
      return;
    }
    
    if (_isScanning) {
      debugPrint('FreestylePage _startAuditoryScanning: Already scanning, returning early');
      return;
    }
    
    debugPrint('FreestylePage _startAuditoryScanning: Setting scanning state variables');
    setState(() {
      _isScanning = true;
      _scanningIndex = -1;
      _currentScanCycle = 0;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _switchStartRequested = false;
    });
    
    int delay = settingsProvider.settings?.scanDelay ?? 3500;
    debugPrint('FreestylePage _startAuditoryScanning: Using scan delay of ${delay}ms');
    _scanningTimer?.cancel();
    
    // Only setup immediate prompt + periodic timer for auto mode
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    debugPrint('FreestylePage _startAuditoryScanning: Scan mode: $scanMode');
    
    if (scanMode == 'auto') {
      debugPrint('FreestylePage _startAuditoryScanning: Starting first scan step for auto mode...');
      _performScanStep();
      debugPrint('FreestylePage _startAuditoryScanning: Setting up periodic timer for auto mode...');
      _scanningTimer = Timer.periodic(
        Duration(milliseconds: delay),
        (_) => _performScanStep(),
      );
    } else {
      debugPrint('FreestylePage _startAuditoryScanning: Step mode - waiting for first Tab, timer not started');
    }
    
    debugPrint('FreestylePage _startAuditoryScanning: Requesting focus');
    _gridFocusNode?.requestFocus();
    debugPrint('FreestylePage _startAuditoryScanning: Setup complete, scanning should now be active');
  }

  void _stopAuditoryScanning() {
    debugPrint('FreestylePage stopAuditoryScanning: called, isScanning=$_isScanning');
    setState(() {
      _isScanning = false;
      _scanningTimer?.cancel();
      _scanningIndex = null;
      _currentScanCycle = 0;
      _isScanningPaused = false;
      _waitingForUserInput = false;
    });
    // Stop any ongoing TTS to prevent audio overlap
    _flutterTts.stop();
  }

  void _performScanStep() async {
    debugPrint('FreestylePage performScanStep: called');
    
    // Check if we're paused and waiting for user input
    if (_isScanningPaused && _waitingForUserInput) {
      debugPrint('FreestylePage performScanStep: Scanning is paused, waiting for user input');
      return;
    }
    
    List<Widget> scannableButtons = _getScannableButtons();
    if (scannableButtons.isEmpty) {
      debugPrint('FreestylePage performScanStep: No scannable buttons');
      return;
    }
    
    final int buttonCount = scannableButtons.length;
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanLoopLimit = settingsProvider.settings?.scanLoopLimit ?? 3;
    
    // IMPORTANT: Update index and announce in a single setState to prevent mis-sync
    int newIndex = _scanningIndex == null ? 0 : (_scanningIndex! + 1) % buttonCount;
    String buttonText = _getButtonTextForIndex(newIndex);
    
    debugPrint('🎯 FP performScanStep: OLD index=$_scanningIndex, NEW index=$newIndex (buttonCount=$buttonCount)');
    debugPrint('🎯 FP performScanStep: Will announce: "$buttonText"');
    
    setState(() {
      _scanningIndex = newIndex;
      
      // Check if we've completed a full cycle (back to index 0)
      if (_scanningIndex == 0 && _currentScanCycle > 0) {
        _currentScanCycle++;
        debugPrint('FreestylePage performScanStep: Completed scan cycle $_currentScanCycle');
      } else if (_scanningIndex == 0) {
        // First time reaching index 0, start counting cycles
        _currentScanCycle = 1;
        debugPrint('FreestylePage performScanStep: Starting scan cycle 1');
      }
    });
    
    // Check if we should pause BEFORE speaking the button
    if (scanLoopLimit > 0 && _currentScanCycle > scanLoopLimit) {
      debugPrint('FreestylePage performScanStep: Reached scan loop limit ($scanLoopLimit), pausing');
      _pauseScanning();
      return;
    }
    
    setState(() {
      _isAnnouncingScanningPrompt = true;
    });
    await _speakSystemVoice(buttonText);
    if (mounted) {
      setState(() {
        _isAnnouncingScanningPrompt = false;
      });
    }
  }

  Future<void> _pauseScanning() async {
    debugPrint('FreestylePage pauseScanning: called');
    setState(() {
      _isScanningPaused = true;
      _waitingForUserInput = true;
      _scanningTimer?.cancel();
    });
    
    await _speakSystemVoice("Scanning paused. Use your switch to resume");
  }

  Future<void> _speakSystemVoice(String text) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
      debugPrint('FreestylePage: Scanning prompt spoken: $text');
    } catch (e) {
      debugPrint('FreestylePage: _speakSystemVoice failed: $e');
    }
  }

  List<Widget> _getScannableButtons() {
    // This will be implemented based on current context
    if (_currentScanningContext == "spelling-letters") {
      return _getSpellingScannableButtons();
    } else if (_currentScanningContext == "choose-word-categories") {
      return _getChooseWordCategoryButtons();
    } else if (_currentScanningContext == "choose-word-options") {
      return _getChooseWordOptionButtons();
    } else {
      return _getMainScannableButtons();
    }
  }

  List<Widget> _getMainScannableButtons() {
    // Must match _buildAllButtons() exactly!
    List<Widget> buttons = [];
    bool buildSpaceEmpty = _buildSpaceText.trim().isEmpty;
    
    // Go Back button (always first)
    buttons.add(Container());
    
    // Speak Display and Clear Display buttons (only when build space is not empty)
    if (!buildSpaceEmpty) {
      buttons.add(Container()); // Speak Display
      buttons.add(Container()); // Clear Display
    }
    
    // Word option buttons
    for (int i = 0; i < _currentWordOptions.length; i++) {
      buttons.add(Container());
    }
    
    // Choose Word button
    buttons.add(Container());
    
    // More Options button
    buttons.add(Container());
    
    // Spell button (right after More Options)
    buttons.add(Container());
    
    return buttons;
  }

  int _getButtonIndexForWordOption(String word) {
    // Calculate button index matching _buildAllButtons() order
    bool buildSpaceEmpty = _buildSpaceText.trim().isEmpty;
    int currentIndex = 0;
    
    // Go Back button (always first)
    currentIndex++;
    
    // Speak Display and Clear Display buttons (only when build space is not empty)
    if (!buildSpaceEmpty) {
      currentIndex += 2; // Speak Display + Clear Display
    }
    
    // Find word in current options
    int wordIndex = _currentWordOptions.indexOf(word);
    if (wordIndex >= 0) {
      return currentIndex + wordIndex;
    }
    
    return -1; // Not found
  }

  List<Widget> _getSpellingScannableButtons() {
    // Return spelling modal buttons for spelling context
    List<Widget> buttons = [];
    
    // Control buttons - intelligently skip based on current word content
    bool currentWordEmpty = _spellingWordController.text.trim().isEmpty;
    
    if (!currentWordEmpty) {
      // Only add Add Word, Clear, and Backspace buttons if current word is not empty
      buttons.add(Container()); // Add Word placeholder
      buttons.add(Container()); // Clear placeholder
      buttons.add(Container()); // Backspace placeholder
    }
    
    // Always add Cancel button
    buttons.add(Container()); // Cancel placeholder
    
    // Add prediction buttons BEFORE valid letters (for scanning order)
    for (int i = 0; i < _currentPredictions.length; i++) {
      buttons.add(Container()); // Prediction placeholder
    }
    
    // Only add valid letter buttons (filtered) - these come AFTER predictions
    for (int i = 0; i < 26; i++) {
      String letter = String.fromCharCode(65 + i); // A-Z
      if (_validLetters.contains(letter)) {
        buttons.add(Container()); // Valid letter placeholder
      }
    }
    
    return buttons;
  }

  List<Widget> _getChooseWordCategoryButtons() {
    List<Widget> buttons = [];
    
    // Add category buttons
    for (int i = 0; i < _wordCategories.length; i++) {
      buttons.add(Container()); // Category placeholder
    }
    
    // Add Cancel button
    buttons.add(Container()); // Cancel placeholder
    
    return buttons;
  }

  List<Widget> _getChooseWordOptionButtons() {
    List<Widget> buttons = [];
    
    // Add word option buttons
    for (int i = 0; i < _currentCategoryWords.length; i++) {
      buttons.add(Container()); // Word option placeholder
    }
    
    // Add control buttons: Back to Categories, Something Else, Go Back
    buttons.add(Container()); // Back to Categories placeholder
    buttons.add(Container()); // Something Else placeholder
    buttons.add(Container()); // Go Back placeholder
    
    return buttons;
  }

  String _getButtonTextForIndex(int index) {
    // This will return the text to speak for the button at the given index
    if (_currentScanningContext == "choose-word-categories") {
      // Handle category selection context
      if (index < _wordCategories.length) {
        return _wordCategories[index];
      } else if (index == _wordCategories.length) {
        return "Cancel";
      }
    } else if (_currentScanningContext == "choose-word-options") {
      // Handle word options within a category
      if (index < _currentCategoryWords.length) {
        return _currentCategoryWords[index];
      } else {
        int controlIndex = index - _currentCategoryWords.length;
        const controlButtons = ["Back to Categories", "Something Else", "Go Back"];
        if (controlIndex < controlButtons.length) {
          return controlButtons[controlIndex];
        }
      }
    } else if (_currentScanningContext == "spelling-letters") {
      // Handle spelling context - control buttons + valid letters only + predictions
      bool currentWordEmpty = _spellingWordController.text.trim().isEmpty;
      int controlButtonCount = currentWordEmpty ? 1 : 4; // Only Cancel when empty, all 4 when not empty
      
      if (index < controlButtonCount) {
        // Control buttons - intelligently skip based on current word content
        if (currentWordEmpty) {
          // Only Cancel button available when current word is empty
          if (index == 0) return "Cancel";
        } else {
          // All control buttons available when current word has content
          if (index == 0) {
            // For Add Word, use the current word value as the prompt
            return _spellingWordController.text.trim().isNotEmpty 
                ? _spellingWordController.text 
                : "Add Word";
          }
          const controlButtonTexts = ["", "Clear", "Backspace", "Cancel"];
          return controlButtonTexts[index];
        }
      } else {
        // After control buttons, we have predictions first, then valid letters
        int predictionCount = _currentPredictions.length;
        
        if (index < controlButtonCount + predictionCount) {
          // Prediction buttons (come first after control buttons)
          int predictionIndex = index - controlButtonCount;
          if (predictionIndex < _currentPredictions.length) {
            return _currentPredictions[predictionIndex];
          }
        } else {
          // Valid letter buttons (come after predictions)
          int letterIndex = index - controlButtonCount - predictionCount;
          if (letterIndex < _validLetters.length) {
            return _validLetters[letterIndex].toLowerCase(); // Remove "Capital"
          }
        }
      }
    } else {
      // Handle main context with new button layout: [Go Back] [Speak Display] [Clear Display] [word options...] [Choose Word] [More Options] [Spell]
      bool buildSpaceEmpty = _buildSpaceText.trim().isEmpty;
      int currentIndex = 0;
      
      // Go Back button (always first)
      if (index == currentIndex) return "Go Back";
      currentIndex++;
      
      // Speak Display and Clear Display buttons (only when build space is not empty)
      if (!buildSpaceEmpty) {
        if (index == currentIndex) {
          return _buildSpaceText.trim().isNotEmpty ? _buildSpaceText : "Speak Display";
        }
        currentIndex++;
        
        if (index == currentIndex) return "Clear Display";
        currentIndex++;
      }
      
      // Word option buttons
      if (index >= currentIndex && index < currentIndex + _currentWordOptions.length) {
        int wordIndex = index - currentIndex;
        return _currentWordOptions[wordIndex];
      }
      currentIndex += _currentWordOptions.length;
      
      // Choose Word button
      if (index == currentIndex) return "Choose Word";
      currentIndex++;
      
      // More Options button
      if (index == currentIndex) return "More Options";
      currentIndex++;
      
      // Spell button (moved to end)
      if (index == currentIndex) return "Spell";
    }
    return "Button";
  }

  // --- Build Space Management ---
  void _onBuildSpaceChange() {
    _buildSpaceText = _buildSpaceController.text;
    _currentContext = _buildSpaceText.trim().isNotEmpty
        ? _buildSpaceText
        : (widget.sourceContext ?? "general communication");
    
    // Debounced reload of word options when build space changes
    _buildSpaceDebounceTimer?.cancel();
    _buildSpaceDebounceTimer = Timer(Duration(seconds: 1), () {
      _loadWordOptions();
    });
  }

  Future<void> _addWordToBuildSpace(String word) async {
    // Stop any ongoing TTS immediately to prevent overlapping audio
    await _flutterTts.stop();
    
    // Stop scanning immediately to prevent conflicts
    if (_isScanning) {
      _stopAuditoryScanning();
    }
    
    // Small delay to ensure TTS has stopped completely
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Announce the selected word first and wait for completion (like main page)
    await _announceWithTimeout(word, routing: 'system');
    
    if (_buildSpaceText.trim().isNotEmpty) {
      _buildSpaceText += ' $word';
    } else {
      _buildSpaceText = word;
    }
    _currentContext = _buildSpaceText;
    _buildSpaceController.text = _buildSpaceText;

    // After first word is selected, allow phrases in subsequent rounds
    if (_isFirstRound) {
      _isFirstRound = false;
      debugPrint('🎯 FreestylePage: First word selected - subsequent rounds can include phrases');
    }

    // Reload word options with new context
    await _loadWordOptions();

    // Use WidgetsBinding to ensure proper sequencing (matching main.dart pattern)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add delay to ensure audio system has settled after announcement
      Future.delayed(const Duration(milliseconds: 300), () {
        debugPrint('FreestylePage: Restarting wake word service and scanning after button announcement');
        
        // Restart wake word service after announcement completes (like main page)
        _forceRestartWakeWordService();

        // Restart scanning after wake word service restart
        _maybeStartScanning();
      });
    });
  }

  Future<void> _speakDisplayText() async {
    // Pause scanning during announcement to prevent interference
    bool wasScanning = _isScanning;
    if (_isScanning) {
      _scanningTimer?.cancel();
      setState(() {
        _scanningIndex = null; // Clear highlighting during announcement
      });
    }
    
    if (_buildSpaceText.trim().isEmpty) {
      await _announceWithTimeout("Nothing to speak", routing: "system");
      
      // *** RESTART SCANNING AFTER "NOTHING TO SPEAK" ANNOUNCEMENT ***
      if (wasScanning) {
        debugPrint('_speakDisplayText: "Nothing to speak" announced, restarting scanning');
        
        // Add delay to allow audio routing to reset before starting scanning
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('_speakDisplayText: Audio routing reset delay completed');
        
        // Check if widget is still mounted before proceeding
        if (!mounted) {
          debugPrint('_speakDisplayText: Widget not mounted, cannot restart scanning');
          return;
        }
        
        // Use direct approach instead of addPostFrameCallback
        debugPrint('_speakDisplayText: Directly resetting scanning state for "Nothing to speak"');
        // Reset scanning state properly (same pattern as main page)
        setState(() {
          _isScanning = false; // Reset scanning state
          _scanningIndex = null; // Clear any existing highlighting
          _isScanningPaused = false; // Reset paused state
          _waitingForUserInput = false; // Reset waiting state
        });
        debugPrint('_speakDisplayText: Calling _maybeStartScanning() to restart scanning after "Nothing to speak"');
        _maybeStartScanning(); // Use the proper scanning restart method
        
        // Restart wake word service after announcement (like main page)
        _forceRestartWakeWordService();
      }
      return;
    }
    
    // Check if autoClean is enabled
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final autoClean = settingsProvider.settings?.autoClean ?? false;
    
    debugPrint('FreestylePage: _speakDisplayText called with autoClean=$autoClean, _buildSpaceText="$_buildSpaceText"');
    
    String textToSpeak = _buildSpaceText;
    
    if (autoClean) {
      debugPrint('FreestylePage: Auto Clean is enabled, starting text cleanup');
      // Clean the text first
      textToSpeak = await _cleanupText(_buildSpaceText);
      debugPrint('FreestylePage: Auto Clean completed, original="$_buildSpaceText", cleaned="$textToSpeak"');
      if (textToSpeak != _buildSpaceText) {
        // Update the build space with cleaned text
        setState(() {
          _buildSpaceText = textToSpeak;
          _buildSpaceController.text = _buildSpaceText;
          _currentContext = _buildSpaceText;
        });
      }
    }
    
    // Use system routing for speech display (same as main page for consistency)
    await _announceWithTimeout(textToSpeak, routing: "system");

    if (textToSpeak.trim().isNotEmpty) {
      widget.onComposeAppend?.call(textToSpeak.trim());
    }
    
    // Record to speech history
    _recordToSpeechHistory(textToSpeak);
    
    // *** RESTART SCANNING AFTER SPEECH PHRASE ANNOUNCEMENT (same pattern as main page) ***
    if (wasScanning) {
      debugPrint('_speakDisplayText: Speech announced, restarting scanning');
      
      // Add delay to allow audio routing to reset before starting scanning
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint('_speakDisplayText: Audio routing reset delay completed');
      
      // Check if widget is still mounted before proceeding
      if (!mounted) {
        debugPrint('_speakDisplayText: Widget not mounted, cannot restart scanning');
        return;
      }
      
      // Use WidgetsBinding for proper sequencing (matching main.dart pattern)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Add delay to ensure audio system has settled
        Future.delayed(const Duration(milliseconds: 300), () {
          debugPrint('_speakDisplayText: Resetting scanning state and restarting after delay');
          
          // Reset scanning state properly (same pattern as main page)
          setState(() {
            _isScanning = false; // Reset scanning state
            _scanningIndex = null; // Clear any existing highlighting
            _isScanningPaused = false; // Reset paused state
            _waitingForUserInput = false; // Reset waiting state
          });
          
          debugPrint('_speakDisplayText: Calling _maybeStartScanning() to restart scanning');
          _maybeStartScanning(); // Use the proper scanning restart method
          
          // Restart wake word service after announcement (like main page)
          _forceRestartWakeWordService();
        });
      });
    }
  }

  // Helper method to clean text without UI updates
  Future<String> _cleanupText(String textToClean) async {
    if (textToClean.trim().isEmpty) {
      return textToClean;
    }
    
    try {
      debugPrint('FreestylePage: Starting text cleanup for: "$textToClean"');
      
      // Get current user settings
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      String idToken = settingsProvider.idToken ?? widget.idToken;
      String aacUserId = settingsProvider.userId ?? widget.aacUserId;

      // Refresh token before cleanup call
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final refreshedToken = await user.getIdToken(true);
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
            debugPrint('FreestylePage: Token refreshed for cleanup');
          }
        }
      } catch (e) {
        debugPrint('FreestylePage: Token refresh failed for cleanup: $e');
      }

      final url = '${EnvironmentConfig.apiBaseUrl}/api/freestyle/cleanup-text';
      final headers = {
        'Authorization': 'Bearer $idToken',
        'X-User-ID': aacUserId,
        'Content-Type': 'application/json',
      };
      
      debugPrint('FreestylePage: Cleanup URL: $url');
      debugPrint('FreestylePage: Cleanup headers: $headers');
      
      final body = json.encode({
        'text_to_cleanup': textToClean,
      });
      
      debugPrint('FreestylePage: Cleanup body: $body');
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );
      
      debugPrint('FreestylePage: Cleanup response status: ${response.statusCode}');
      debugPrint('FreestylePage: Cleanup response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final cleanedText = data['cleaned_text'] ?? textToClean;
        debugPrint('FreestylePage: Original text: "$textToClean"');
        debugPrint('FreestylePage: Cleaned text: "$cleanedText"');
        return cleanedText;
      } else {
        debugPrint('FreestylePage: Cleanup failed with status ${response.statusCode}: ${response.body}');
        return textToClean;
      }
    } catch (e) {
      debugPrint('FreestylePage: Error cleaning text: $e');
      return textToClean;
    }
  }

  void _recordToSpeechHistory(String textToRecord) {
    if (textToRecord.trim().isEmpty) return;
    
    setState(() {
      // This would normally update speech history in the UI
      // For now, we'll just set a status message
      _statusMessage = 'Added to speech history: $textToRecord';
    });
  }

  void _clearDisplayText() {
    setState(() {
      _buildSpaceText = "";
      _buildSpaceController.text = "";
      // Reset to initial context and first-round setting (preserves LLM behavior)
      _currentContext = _initialContext;
      _isFirstRound = _initialIsFirstRound;
    });
    debugPrint('🎯 FreestylePage: Display cleared - reset to initial state (single words: $_isFirstRound)');
    _loadWordOptions();
  }

  // --- Word Options Management ---
  Future<void> _loadWordOptions() async {
    if (_isLoadingWordOptions) return;
    
    setState(() {
      _isLoadingWordOptions = true;
      _statusMessage = 'Loading word options...';
    });
    
    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final effectiveContext = _buildSpaceText.trim().isNotEmpty
          ? _buildSpaceText
          : _currentContext;
      final shouldRequestDifferent = _buildSpaceText.trim().isNotEmpty || _currentWordOptions.isNotEmpty;
      final exclusions = _currentWordOptions.isNotEmpty ? List<String>.from(_currentWordOptions) : <String>[];
      final maxOptions = settingsProvider.settings?.freestyleOptions ?? 20;

      debugPrint('🎯 FreestylePage _loadWordOptions context: "$effectiveContext"');
      debugPrint('🎯 FreestylePage _loadWordOptions requestDifferent: $shouldRequestDifferent, exclusions: ${exclusions.length}');

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode({
          'build_space_text': _buildSpaceText,
          'context': effectiveContext,
          'source_page': widget.sourcePage,
          'is_llm_generated': widget.isLLMGenerated,
          'single_words_only': _isFirstRound,
          'originating_button_text': widget.originatingButtonText,
          'request_different_options': shouldRequestDifferent,
          'exclude_words': exclusions,
          'max_options': maxOptions,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('FreestylePage: Raw API response: ${response.body}');
        setState(() {
          // Handle both string arrays and object arrays
          final rawOptions = data['word_options'] ?? [];
          debugPrint('FreestylePage: Parsed rawOptions: $rawOptions');
          _currentWordOptions = rawOptions.map<String>((option) {
            String raw;
            if (option is String) {
              raw = option;
            } else if (option is Map<String, dynamic>) {
              // Try 'text' field first, then 'word', then fallback
              raw = option['text']?.toString() ?? option['word']?.toString() ?? option.toString();
              
              // Handle case where text contains malformed JSON like '{"option": "Food'
              if (raw.startsWith('{"option": "') || raw.startsWith("{\"option\": \"")) {
                // Extract the actual word from malformed JSON string
                final match = RegExp(r'\{"option":\s*"([^"]+)"?').firstMatch(raw);
                if (match != null && match.group(1) != null) {
                  raw = match.group(1)!;
                  debugPrint('FreestylePage: Extracted word from malformed JSON: "$raw"');
                }
              }
            } else {
              raw = option.toString();
            }
            return _normalizeOptionText(raw);
          }).where((text) {
            // Filter out introductory/explanatory text that's not actual word options
            final lowerText = text.toLowerCase();
            final trimmedText = text.trim();
            
            // Filter out JSON artifacts and invalid options
            if (trimmedText.isEmpty || 
                trimmedText == '[' || 
                trimmedText == ']' || 
                trimmedText == '{' || 
                trimmedText == '}' ||
                trimmedText == '```json' ||
                trimmedText == '```' ||
                trimmedText.startsWith('```') ||
                trimmedText.length == 1 && RegExp(r'[^\w]').hasMatch(trimmedText)) {
              debugPrint('FreestylePage: Filtering out invalid option: "$trimmedText"');
              return false;
            }
            
            return !(lowerText.contains('here are') || 
                    lowerText.contains('varied and diverse') ||
                    lowerText.contains('useful words') ||
                    lowerText.contains('communication for') ||
                    lowerText.contains('with related keywords') ||
                    lowerText.length > 50); // Skip very long descriptive text
          }).toList();
          debugPrint('FreestylePage: Final processed options: $_currentWordOptions');
          _statusMessage = 'Loaded ${_currentWordOptions.length} word options';
        });
      } else {
        // Fallback options
        debugPrint('FreestylePage: API returned ${response.statusCode}: ${response.body}');
        setState(() {
          _currentWordOptions = ["I", "want", "need", "can", "please", "thank you", "help", "yes", "no", "good"];
          _statusMessage = 'Using fallback word options (API ${response.statusCode})';
        });
      }
    } catch (e) {
      // Fallback options
      debugPrint('FreestylePage: Error loading word options: $e');
      setState(() {
        _currentWordOptions = ["I", "want", "need", "can", "please", "thank you", "help", "yes", "no", "good"];
        _statusMessage = 'Error loading options, using fallback ($e)';
      });
    } finally {
      setState(() {
        _isLoadingWordOptions = false;
      });
    }
  }

  Future<void> _loadMoreWordOptions() async {
    if (_isLoadingWordOptions) return;
    
    // Store previous options for comparison
    final List<String> previousOptions = List.from(_currentWordOptions);
    
    setState(() {
      _isLoadingWordOptions = true;
      _statusMessage = 'Loading more word options...';
    });
    
    try {
      final effectiveContext = _buildSpaceText.trim().isNotEmpty
          ? _buildSpaceText
          : _currentContext;

      // AGGRESSIVE APPROACH: Try multiple API strategies to get truly different words
      List<String> finalNewOptions = [];
      int attemptCount = 0;
      const maxAttempts = 3;
      
      while (finalNewOptions.length < 10 && attemptCount < maxAttempts) {
        attemptCount++;
        debugPrint('🔄 Something Else Attempt #$attemptCount');
        
        // Use different strategies each attempt
        Map<String, dynamic> requestBody;
        if (attemptCount == 1) {
          // First attempt: Request creative/alternative words
          requestBody = {
            'build_space_text': _buildSpaceText,
            'request_different_options': true,
            'request_creative_alternatives': true, // New parameter
            'exclude_previous_options': previousOptions,
            'alternative_word_types': ['descriptive', 'action', 'creative'], // New parameter
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'context': effectiveContext,
            'source_page': widget.sourcePage,
            'is_llm_generated': widget.isLLMGenerated,
            'single_words_only': _isFirstRound,
            'originating_button_text': widget.originatingButtonText,
          };
        } else if (attemptCount == 2) {
          // Second attempt: Request specific categories
          requestBody = {
            'build_space_text': _buildSpaceText,
            'request_different_options': true,
            'force_category': ['objects', 'places', 'activities'], // Force different categories
            'exclude_previous_options': [...previousOptions, ...finalNewOptions],
            'timestamp': DateTime.now().millisecondsSinceEpoch + attemptCount,
            'context': 'expanded vocabulary beyond basic communication',
            'source_page': widget.sourcePage,
            'is_llm_generated': widget.isLLMGenerated,
            'single_words_only': _isFirstRound,
            'originating_button_text': widget.originatingButtonText,
          };
        } else {
          // Third attempt: Fallback with random seed
          requestBody = {
            'build_space_text': _buildSpaceText,
            'request_different_options': true,
            'random_seed': DateTime.now().millisecondsSinceEpoch % 1000,
            'exclude_previous_options': [...previousOptions, ...finalNewOptions],
            'force_unique': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch + attemptCount * 100,
            'context': 'diverse vocabulary alternatives',
            'source_page': widget.sourcePage,
            'is_llm_generated': widget.isLLMGenerated,
            'single_words_only': _isFirstRound,
            'originating_button_text': widget.originatingButtonText,
          };
        }
        
        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'POST',
          '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options',
          baseHeaders: {
            'Content-Type': 'application/json',
            'X-User-ID': widget.aacUserId,
          },
          body: json.encode(requestBody),
        );
        
        debugPrint('   API Response Status: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final rawOptions = data['word_options'] ?? [];
          
          // Process options and filter for truly new ones
          final attemptOptions = rawOptions.map<String>((option) {
            String raw;
            if (option is String) {
              raw = option;
            } else if (option is Map<String, dynamic>) {
              raw = option['text']?.toString() ?? option['word']?.toString() ?? option.toString();
            } else {
              raw = option.toString();
            }
            return _normalizeOptionText(raw);
          }).where((text) {
            final lowerText = text.toLowerCase();
            final trimmedText = text.trim();
            final previousLower = previousOptions.map((e) => e.toLowerCase()).toList();
            final finalLower = finalNewOptions.map((e) => e.toLowerCase()).toList();
            
            // STRICT filtering: exclude if it matches ANY previous word (case-insensitive)
            return trimmedText.isNotEmpty && 
                   !previousLower.contains(lowerText) && // Case-insensitive comparison
                   !finalLower.contains(lowerText) &&
                   !(lowerText.contains('here are') || 
                     lowerText.contains('varied and diverse') ||
                     lowerText.contains('useful words') ||
                     lowerText.contains('communication for') ||
                     lowerText.contains('with related keywords') ||
                     lowerText.length > 50);
          }).toList();
          
          // Add unique options to our collection
          for (String option in attemptOptions) {
            final optionLower = option.toLowerCase();
            final existingLower = finalNewOptions.map((e) => e.toLowerCase()).toList();
            if (!existingLower.contains(optionLower) && finalNewOptions.length < 20) {
              finalNewOptions.add(option);
            }
          }
          
          debugPrint('   Attempt $attemptCount added ${attemptOptions.length} options, total now: ${finalNewOptions.length}');
        }
        
        // Small delay between attempts
        if (attemptCount < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
      
      // If we still don't have enough unique options, add fallback creative words
      if (finalNewOptions.length < 5) {
        final fallbackWords = [
          'awesome', 'amazing', 'wonderful', 'fantastic', 'brilliant',
          'create', 'build', 'make', 'fix', 'solve',
          'adventure', 'journey', 'explore', 'discover', 'find',
          'music', 'art', 'color', 'draw', 'paint',
          'family', 'friend', 'together', 'share', 'care',
          'outside', 'inside', 'around', 'between', 'through',
          'morning', 'afternoon', 'evening', 'night', 'day',
          'cold', 'warm', 'hot', 'cool', 'fresh'
        ];
        
        for (String fallback in fallbackWords) {
          final fallbackLower = fallback.toLowerCase();
          final previousLower = previousOptions.map((e) => e.toLowerCase()).toList();
          final finalLower = finalNewOptions.map((e) => e.toLowerCase()).toList();
          
          if (!previousLower.contains(fallbackLower) && 
              !finalLower.contains(fallbackLower) && 
              finalNewOptions.length < 15) {
            finalNewOptions.add(fallback);
          }
        }
      }
      
      // Calculate overlap for debugging
      final previousLower = previousOptions.map((e) => e.toLowerCase()).toList();
      final overlap = finalNewOptions.where((option) => 
          previousLower.contains(option.toLowerCase())).toList();
      
      debugPrint('🔍 FINAL Option Analysis:');
      debugPrint('   Previous count: ${previousOptions.length}');
      debugPrint('   New count: ${finalNewOptions.length}');
      debugPrint('   Overlap: ${overlap.length} words: $overlap');
      debugPrint('   Previous words: ${previousOptions.take(10).join(", ")}');
      debugPrint('   New words: ${finalNewOptions.take(10).join(", ")}');
      
      // Clear current options FIRST to force UI refresh
      setState(() {
        _currentWordOptions.clear();
      });
      
      setState(() {
        _currentWordOptions = finalNewOptions;
        _statusMessage = 'DIFFERENT OPTIONS #${DateTime.now().second}: ${finalNewOptions.length} truly new words loaded! (${overlap.length} overlap)';
      });
      
      // Reset scanning to the first new word option
      setState(() {
        _scanningIndex = 4; // First word option
      });
      
      // Announce the change with first new option
      if (_isScanning && _currentWordOptions.isNotEmpty) {
        Future.delayed(Duration(milliseconds: 200), () {
          _speakSystemVoice(_currentWordOptions[0]);
        });
      }
      
    } catch (e) {
      debugPrint('FreestylePage: Error loading more word options: $e');
      setState(() {
        _statusMessage = 'Error loading more options ($e)';
      });
    } finally {
      setState(() {
        _isLoadingWordOptions = false;
      });
    }
  }

  // --- Spelling Modal Management ---
  void _openSpellingModal() {
    setState(() {
      _isSpellingModalOpen = true;
      _currentSpellingWord = "";
      _spellingWordController.text = "";
      _currentPredictions = [];
      _currentScanningContext = "spelling-letters";
      _validLetters = _getAllLetters();
      // Reset scanning back to first button in spelling context
      _scanningIndex = _getFirstButtonIndex();
    });
    
    // Stop main scanning and start spelling scanning
    _stopAuditoryScanning();
    _maybeStartScanning();
    
    // Get initial word predictions even with empty current word
    _getWordPredictions();
    
    // Small delay to ensure the audio prompt is heard for the reset position
    if (_isScanning) {
      Future.delayed(Duration(milliseconds: 300), () {
        _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
      });
    }
  }

  void _closeSpellingModal() {
    setState(() {
      _isSpellingModalOpen = false;
      _currentScanningContext = "main";
      // Reset scanning back to first button when returning to main context
      _scanningIndex = _getFirstButtonIndex();
    });
    
    // Stop spelling scanning and start main scanning
    _stopAuditoryScanning();
    _maybeStartScanning();
    
    // Small delay to ensure the audio prompt is heard for the reset position
    if (_isScanning) {
      Future.delayed(Duration(milliseconds: 300), () {
        _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
      });
    }
  }

  List<String> _getAllLetters() {
    // Get letter order from user settings
    final settings = Provider.of<UserSettingsProvider>(context, listen: false).settings;
    final letterOrder = settings?.spellLetterOrder ?? 'alphabetical';
    
    if (letterOrder == 'qwerty') {
      // QWERTY keyboard layout - flatten the rows
      return ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P',
              'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L',
              'Z', 'X', 'C', 'V', 'B', 'N', 'M'];
    } else if (letterOrder == 'frequency') {
      // Frequency-based order: ETAOIN SHRDLU CMFWGY P BVKX JZQ
      return 'ETAOINSHRDLUCMFWGYPBVKXJZQ'.split('');
    } else {
      // Alphabetical (default)
      return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }
  }

  List<String> _getValidLetters(String currentWord) {
    print('DEBUG: getValidLetters called with: "$currentWord"');
    
    if (currentWord.isEmpty) {
      return _getAllLetters();
    }
    
    final lastChar = currentWord.toUpperCase().substring(currentWord.length - 1);
    final lastTwoChars = currentWord.length >= 2 
        ? currentWord.toUpperCase().substring(currentWord.length - 2) 
        : '';
    final wordSoFar = currentWord.toUpperCase();
    
    print('DEBUG: Last char: "$lastChar", Last two chars: "$lastTwoChars", Word so far: "$wordSoFar"');
    
    // Define likely letter combinations based on common English patterns
    const likelyAfter = {
      'A': ['B', 'C', 'D', 'F', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W', 'Y'],
      'B': ['A', 'E', 'I', 'L', 'O', 'R', 'U', 'Y'],
      'C': ['A', 'E', 'H', 'I', 'L', 'O', 'R', 'U'],
      'D': ['A', 'E', 'I', 'O', 'R', 'U', 'Y'],
      'E': ['A', 'D', 'L', 'M', 'N', 'R', 'S', 'T', 'V', 'W', 'X'],
      'F': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
      'G': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
      'H': ['A', 'E', 'I', 'O', 'U', 'Y'],
      'I': ['C', 'D', 'F', 'G', 'L', 'M', 'N', 'R', 'S', 'T'],
      'J': ['A', 'E', 'O', 'U'],
      'K': ['A', 'E', 'I', 'N'],
      'L': ['A', 'E', 'I', 'O', 'U', 'Y'],
      'M': ['A', 'E', 'I', 'O', 'U', 'Y'],
      'N': ['A', 'E', 'I', 'O', 'U'],
      'O': ['B', 'C', 'D', 'F', 'G', 'K', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W'],
      'P': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
      'Q': ['U'],
      'R': ['A', 'E', 'I', 'O', 'U', 'Y'],
      'S': ['A', 'C', 'E', 'H', 'I', 'K', 'L', 'M', 'N', 'O', 'P', 'T', 'U', 'W'],
      'T': ['A', 'E', 'H', 'I', 'O', 'R', 'U', 'W'],
      'U': ['B', 'C', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T'],
      'V': ['A', 'E', 'I', 'O'],
      'W': ['A', 'E', 'H', 'I', 'O'],
      'X': ['A', 'E', 'I'],
      'Y': ['A', 'E', 'O', 'U'],
      'Z': ['A', 'E', 'I', 'O']
    };
    
    // Two-letter patterns - what commonly follows specific two-letter combinations
    const likelyAfterTwoLetters = {
      'TH': ['A', 'E', 'I', 'O', 'R'],
      'CH': ['A', 'E', 'I', 'O', 'U'],
      'SH': ['A', 'E', 'I', 'O', 'U'],
      'WH': ['A', 'E', 'I', 'O', 'U'],
      'PH': ['A', 'E', 'I', 'O', 'U'],
      'ST': ['A', 'E', 'I', 'O', 'R', 'U'],
      'SP': ['A', 'E', 'I', 'O', 'R'],
      'SC': ['A', 'E', 'I', 'O', 'R'],
      'FL': ['A', 'E', 'I', 'O', 'U'],
      'BL': ['A', 'E', 'I', 'O', 'U'],
      'CL': ['A', 'E', 'I', 'O', 'U'],
      'GL': ['A', 'E', 'I', 'O', 'U'],
      'PL': ['A', 'E', 'I', 'O', 'U'],
      'BR': ['A', 'E', 'I', 'O', 'U'],
      'CR': ['A', 'E', 'I', 'O', 'U'],
      'DR': ['A', 'E', 'I', 'O', 'U'],
      'FR': ['A', 'E', 'I', 'O', 'U'],
      'GR': ['A', 'E', 'I', 'O', 'U'],
      'PR': ['A', 'E', 'I', 'O', 'U'],
      'TR': ['A', 'E', 'I', 'O', 'U'],
    };
    
    List<String> validLetters = [];
    
    // Check if we have a specific two-letter pattern
    if (currentWord.length >= 2 && likelyAfterTwoLetters[lastTwoChars] != null) {
      validLetters = likelyAfterTwoLetters[lastTwoChars]!;
      print('DEBUG: Using two-letter pattern for "$lastTwoChars": $validLetters');
    } else if (likelyAfter[lastChar] != null) {
      validLetters = likelyAfter[lastChar]!;
      print('DEBUG: Using single-letter pattern for "$lastChar": $validLetters');
    } else {
      validLetters = _getAllLetters();
      print('DEBUG: No pattern found, using all letters');
    }
    
    print('DEBUG: Final valid letters for "$currentWord": $validLetters');
    return validLetters;
  }

  void _handleLetterClick(String letter) {
    setState(() {
      _currentSpellingWord += letter.toLowerCase();
      _spellingWordController.text = _currentSpellingWord;
      _validLetters = _getValidLetters(_currentSpellingWord);
      // Reset scanning back to first button in spelling context
      _scanningIndex = _getFirstButtonIndex();
    });
    
    // Small delay to ensure the audio prompt is heard for the reset position
    if (_isScanning) {
      Future.delayed(Duration(milliseconds: 200), () {
        _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
      });
    }
    
    _getWordPredictions();
  }

  Future<void> _getWordPredictions() async {
    print('DEBUG: _getWordPredictions called with current word: "$_currentSpellingWord"'); // Debug output
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Debug the authentication tokens
      print('DEBUG: idToken length: ${widget.idToken.length}');
      print('DEBUG: aacUserId: "${widget.aacUserId}"');
      print('DEBUG: Build space text: "${_buildSpaceText}"');
      print('DEBUG: Current spelling word: "${_currentSpellingWord}"');
      
      final url = '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-prediction';
      final body = json.encode({
        'text': _buildSpaceText.trim().isEmpty ? "" : _buildSpaceText, // Context from build space
        'spelling_word': _currentSpellingWord, // Current partial word being spelled
        'predict_full_words': true, // Flag to ensure complete words are returned
      });
      
      print('DEBUG: API URL: $url');
      print('DEBUG: API Body: $body');
      
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        url,
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
        body: body,
      );
      
      print('DEBUG: Response status code: ${response.statusCode}');
      print('DEBUG: Response headers: ${response.headers}');
      print('DEBUG: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('DEBUG: Full API response: $data'); // Debug output
        List<String> predictions = List<String>.from(data['predictions'] ?? []);
        print('DEBUG: Raw predictions from API: $predictions'); // Debug output
        
        // Convert completions to full words
        if (_currentSpellingWord.trim().isNotEmpty) {
          predictions = predictions.map((prediction) {
            // If prediction doesn't start with our current word, it's likely a completion
            // so prepend the current word to make it a full word
            String currentWord = _currentSpellingWord.toLowerCase();
            String predictionLower = prediction.toLowerCase();
            
            if (predictionLower.startsWith(currentWord)) {
              // Already a full word
              return prediction;
            } else {
              // It's a completion, combine with current word
              return _currentSpellingWord + prediction;
            }
          }).toList();
        }
        
        setState(() {
          _currentPredictions = predictions;
        });
        print('DEBUG: Word predictions loaded: $_currentPredictions'); // Debug output
      } else {
        print('DEBUG: Word prediction API failed with status: ${response.statusCode}'); // Debug output
        print('DEBUG: Response body: ${response.body}'); // Debug output
        setState(() {
          _currentPredictions = [];
        });
      }
    } catch (e) {
      print('DEBUG: Word prediction error: $e'); // Debug output
      setState(() {
        _currentPredictions = [];
      });
      debugPrint('FreestylePage: Error getting word predictions: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handlePredictionClick(String word) async {
    // Automatically add the selected prediction to build space and close modal
    await _addWordToBuildSpace(word);
    _clearCurrentWord();
    _closeSpellingModal();
  }

  void _addCurrentWordToBuildSpace() async {
    if (_currentSpellingWord.trim().isNotEmpty) {
      await _addWordToBuildSpace(_currentSpellingWord);
      _clearCurrentWord();
      _closeSpellingModal();
    }
  }

  void _clearCurrentWord() {
    setState(() {
      _currentSpellingWord = "";
      _spellingWordController.text = "";
      _currentPredictions = [];
      _validLetters = _getAllLetters();
      // Reset scanning back to first button in spelling context
      _scanningIndex = _getFirstButtonIndex();
    });
    
    // Small delay to ensure the audio prompt is heard for the reset position
    if (_isScanning) {
      Future.delayed(Duration(milliseconds: 200), () {
        _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
      });
    }
  }

  void _backspaceCurrentWord() {
    if (_currentSpellingWord.isNotEmpty) {
      setState(() {
        _currentSpellingWord = _currentSpellingWord.substring(0, _currentSpellingWord.length - 1);
        _spellingWordController.text = _currentSpellingWord;
        _validLetters = _getValidLetters(_currentSpellingWord);
        // Reset scanning back to first button in spelling context
        _scanningIndex = _getFirstButtonIndex();
      });
      
      // Small delay to ensure the audio prompt is heard for the reset position
      if (_isScanning) {
        Future.delayed(Duration(milliseconds: 200), () {
          _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
        });
      }
      
      _getWordPredictions();
    }
  }

  // --- CHOOSE WORD MODAL METHODS ---
  void _openChooseWordModal() {
    setState(() {
      _isChooseWordModalOpen = true;
      _currentScanningContext = "choose-word-categories";
      _currentChooseWordCategory = "";
      _currentCategoryWords = [];
    });
    
    // Stop main scanning
    _stopAuditoryScanning();
    
    // Start category scanning after UI settles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartScanning();
    });
  }

  void _closeChooseWordModal() {
    setState(() {
      _isChooseWordModalOpen = false;
      _currentScanningContext = "main";
      _currentChooseWordCategory = "";
      _currentCategoryWords = [];
      // Reset scanning back to first button when returning to main context
      _scanningIndex = _getFirstButtonIndex();
    });
    
    // Stop category scanning and start main scanning
    _stopAuditoryScanning();
    _maybeStartScanning();
    
    // Small delay to ensure the audio prompt is heard for the reset position
    if (_isScanning) {
      Future.delayed(Duration(milliseconds: 300), () {
        _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
      });
    }
  }

  Future<void> _generateCategoryWords(String category) async {
    if (_isLoadingCategoryWords) return;
    
    setState(() {
      _isLoadingCategoryWords = true;
      _currentChooseWordCategory = category;
    });
    
    try {
      final response = await _getCategoryWords(category);
      if (mounted) {
        setState(() {
          _currentCategoryWords = response;
          _currentScanningContext = "choose-word-options";
          _isLoadingCategoryWords = false;
        });
        
        // Start scanning the word options immediately
        _stopAuditoryScanning();
        // Small delay to ensure UI state is settled
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeStartScanning();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCategoryWords = false;
        });
      }
      debugPrint('Error generating category words: $e');
    }
  }

  Future<List<String>> _getCategoryWords(String category) async {
    // Use the specialized category-words endpoint (same as web app)
    try {
      String idToken = widget.idToken;
      
      // Refresh token
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final refreshedToken = await user.getIdToken(true);
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
          }
        }
      } catch (e) {
        debugPrint('Token refresh failed: $e');
      }

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/category-words',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode({
          'category': category,
          'build_space_content': _buildSpaceText,
          'exclude_words': [], // Could add previously shown words here for "Something Else" functionality
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['words'] != null && data['words'] is List) {
          final List<dynamic> wordsList = data['words'];
          return wordsList.map((wordData) {
            // The API returns objects with 'text' and 'keyword' fields
            if (wordData is Map && wordData['text'] != null) {
              return wordData['text'].toString();
            } else if (wordData is String) {
              return wordData;
            } else {
              return wordData.toString();
            }
          }).toList();
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to get category words: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting category words: $e');
      // Return default words based on category
      return _getDefaultCategoryWords(category);
    }
  }

  List<String> _getDefaultCategoryWords(String category) {
    switch (category.toLowerCase()) {
      case 'people':
        return ['mom', 'dad', 'teacher', 'friend', 'doctor', 'nurse', 'family', 'classmate'];
      case 'places':
        return ['home', 'school', 'park', 'store', 'hospital', 'library', 'restaurant', 'playground'];
      case 'animals':
        return ['dog', 'cat', 'bird', 'fish', 'horse', 'cow', 'pig', 'rabbit'];
      case 'around the house':
        return ['kitchen', 'bedroom', 'bathroom', 'living room', 'garage', 'yard', 'stairs', 'door'];
      case 'in the room':
        return ['bed', 'chair', 'table', 'lamp', 'window', 'closet', 'dresser', 'mirror'];
      case 'general things':
        return ['book', 'toy', 'phone', 'computer', 'car', 'bike', 'keys', 'bag'];
      case 'actions':
        return ['eat', 'drink', 'sleep', 'walk', 'run', 'sit', 'stand', 'play'];
      case 'feelings & emotions':
        return ['happy', 'sad', 'angry', 'excited', 'calm', 'worried', 'proud', 'surprised'];
      case 'questions & comments':
        return ['what', 'where', 'when', 'why', 'how', 'good job', 'thank you', 'excuse me'];
      case 'times and dates':
        return ['morning', 'afternoon', 'evening', 'night', 'today', 'tomorrow', 'yesterday', 'now'];
      case 'activities & hobbies':
        return ['reading', 'drawing', 'music', 'sports', 'games', 'cooking', 'dancing', 'singing'];
      case 'medical & health':
        return ['doctor', 'medicine', 'hurt', 'sick', 'better', 'hospital', 'nurse', 'bandage'];
      case 'food & drinks':
        return ['apple', 'water', 'bread', 'milk', 'pizza', 'sandwich', 'cookie', 'juice'];
      case 'colors & descriptions':
        return ['red', 'blue', 'green', 'yellow', 'big', 'small', 'hot', 'cold'];
      case 'numbers & quantities':
        return ['one', 'two', 'three', 'four', 'many', 'few', 'more', 'less'];
      case 'school & learning':
        return ['teacher', 'student', 'homework', 'test', 'book', 'pencil', 'paper', 'learn'];
      case 'transportation':
        return ['car', 'bus', 'train', 'plane', 'bike', 'walk', 'drive', 'ride'];
      case 'weather':
        return ['sunny', 'rainy', 'cloudy', 'hot', 'cold', 'windy', 'snowy', 'warm'];
      case 'technology':
        return ['computer', 'phone', 'tablet', 'internet', 'app', 'video', 'game', 'music'];
      case 'sports & games':
        return ['soccer', 'basketball', 'baseball', 'tennis', 'swimming', 'running', 'play', 'win'];
      default:
        return ['yes', 'no', 'please', 'thank you', 'help', 'more', 'stop', 'go'];
    }
  }

  // --- SPEECH BUBBLE OVERLAY METHODS ---
  
  /// Show speech bubble overlay with announcement text
  void _showSpeechBubbleOverlay(String text) {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    
    // Check if speech bubble feature is enabled
    if (settingsProvider.settings?.displaySplash != true) {
      return; // Feature disabled
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
    
    debugPrint('Speech bubble displayed for ${duration}ms: "$text"');
  }
  
  /// Hide speech bubble overlay
  void _hideSpeechBubbleOverlay() {
    _speechBubbleTimer?.cancel();
    
    if (mounted) {
      setState(() {
        _showSpeechBubble = false;
        _speechBubbleText = '';
      });
    }
    
    debugPrint('Speech bubble hidden');
  }

  /// Timeout wrapper for _announceViaBackend to prevent app freezing
  Future<void> _announceWithTimeout(
    String text, {
    String routing = 'system',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      debugPrint('FreestylePage _announceWithTimeout: Starting announcement with ${timeout.inSeconds}s timeout: "$text"');
      
      await _announceViaBackend(text, routing: routing).timeout(
        timeout,
        onTimeout: () {
          debugPrint('🚨 FREESTYLE PAGE TIMEOUT: _announceViaBackend timed out after ${timeout.inSeconds} seconds for: "$text"');
          debugPrint('🚨 TIMEOUT RECOVERY: Attempting graceful recovery in FreestylePage');
          
          // Try to stop any ongoing audio
          try {
            _flutterTts.stop();
          } catch (e) {
            debugPrint('🚨 TIMEOUT RECOVERY: Error stopping TTS: $e');
          }
          
          // Try to reset audio routing if possible
          try {
            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              const platform = MethodChannel('audio_routing');
              platform.invokeMethod('resetToDefault');
            }
          } catch (e) {
            debugPrint('🚨 TIMEOUT RECOVERY: Error resetting audio routing: $e');
          }
          
          throw TimeoutException('FreestylePage announcement timed out after ${timeout.inSeconds} seconds', timeout);
        },
      );
      
      debugPrint('FreestylePage _announceWithTimeout: Announcement completed successfully within timeout');
      
    } catch (e) {
      if (e is TimeoutException) {
        debugPrint('🚨 FreestylePage _announceWithTimeout: Announcement timed out - showing user notification');
        
        // Show user-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Freestyle communication timed out. The app is still working normally.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
        
        // CRITICAL: Restart wake word service after timeout using proper sequencing
        debugPrint('🚨 FreestylePage: Restarting wake word service after timeout');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 300), () {
            _forceRestartWakeWordService();
          });
        });
      } else {
        debugPrint('🚨 FreestylePage _announceWithTimeout: Error during announcement: $e');
        rethrow; // Re-throw non-timeout exceptions
      }
    }
  }

  // --- Announcement method (identical to main page for consistency) ---
  Future<void> _announceViaBackend(String text, {String routing = 'system', bool preserveMicrophoneSession = false}) async {
    String idToken = widget.idToken;
    final aacUserId = widget.aacUserId;
    try {
      // Set announcement playing flag to suppress scanning audio
      _isAnnouncementPlaying = true;
      
      // Show speech bubble overlay if enabled in settings
      _showSpeechBubbleOverlay(text);
      
      // Initialize audio session on first use (fixes "Test" button issue on first app launch)
      if (!_audioSessionInitialized) {
        debugPrint('announceViaBackend: First call, initializing audio session...');
        await _initializeAudioSession();
        _audioSessionInitialized = true;
      }

      final startTotal = DateTime.now();

      debugPrint('[TIMER] announceViaBackend: START for "$text" at ${startTotal.millisecondsSinceEpoch}');
      // Try to refresh the token before backend call, but don't fail if it doesn't work
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final refreshedToken = await user.getIdToken(true);
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
            debugPrint('announceViaBackend: Successfully refreshed Firebase token');
          }
        }
      } catch (e) {
        debugPrint('announceViaBackend: Token refresh failed, using existing token: $e');
        // Continue with existing token - don't fail the entire announcement
      }
      
      bool backendAudioPlayed = false;
      final startRequest = DateTime.now();
      debugPrint('[TIMER] announceViaBackend: Requesting backend audio for "$text" at ${startRequest.millisecondsSinceEpoch}');
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/play-audio',
        baseHeaders: {
          'X-User-ID': aacUserId,
        },
        body: json.encode({'text': text, 'routing_target': 'system'}),
      );
      final endRequest = DateTime.now();
      debugPrint('[TIMER] announceViaBackend: Backend response received at ${endRequest.millisecondsSinceEpoch} (delta: ${endRequest.difference(startRequest).inMilliseconds} ms)');
      debugPrint('announceViaBackend: Response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final audioUrl = RegExp('"audio_url"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        final base64Audio = RegExp('"audio_data"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audioContent"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        try {
          if (!kIsWeb && Platform.isIOS) {
            final platform = MethodChannel('audio_routing');
            final player = AudioPlayer();
            await _flutterTts.stop();
            await player.stop();
            debugPrint('[TIMER] announceViaBackend: Before forceSpeaker (iOS) at ${DateTime.now().millisecondsSinceEpoch}');
            await platform.invokeMethod('forceSpeaker');
            debugPrint('[TIMER] announceViaBackend: Before silence.mp3 at ${DateTime.now().millisecondsSinceEpoch}');
            final silenceStart = DateTime.now();
            try {
              await player.setAsset('assets/silence.mp3');
              await player.play();
            } catch (e) {
              debugPrint('announceViaBackend: silence.mp3 playback failed: $e');
            }
            final silenceEnd = DateTime.now();
            debugPrint('[TIMER] announceViaBackend: After silence.mp3 at ${silenceEnd.millisecondsSinceEpoch} (delta: ${silenceEnd.difference(silenceStart).inMilliseconds} ms)');
            await platform.invokeMethod('resetToDefault');
            await platform.invokeMethod('forceSpeaker');
            debugPrint('Stopping scanning before backend audio playback');
            _stopAuditoryScanning();
            // --- PREFER BASE64 AUDIO OVER AUDIOURL ---
            if (base64Audio != null && base64Audio.isNotEmpty) {
              debugPrint('announceViaBackend: Playing base64 audio (preferred)');
              final base64Start = DateTime.now();
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File('${tempDir.path}/backend_tts.mp3').create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              // --- Wait for playback to finish before resetToDefault ---
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
              debugPrint('[TIMER] announceViaBackend: After base64 audio playback at ${base64End.millisecondsSinceEpoch} (delta: ${base64End.difference(base64Start).inMilliseconds} ms)');
              await Future.delayed(const Duration(milliseconds: 100));
              await platform.invokeMethod('resetToDefault');
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              try {
                await platform.invokeMethod('forceSpeaker');
                debugPrint('[TIMER] announceViaBackend: Before setUrl/play audioUrl at ${DateTime.now().millisecondsSinceEpoch}');
                final audioUrlStart = DateTime.now();
                await player.setUrl(audioUrl);
                // --- Wait for playback to finish before resetToDefault ---
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
                debugPrint('[TIMER] announceViaBackend: After audioUrl playback at ${audioUrlEnd.millisecondsSinceEpoch} (delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms)');
                await Future.delayed(const Duration(milliseconds: 100));
                await platform.invokeMethod('resetToDefault');
                backendAudioPlayed = true;
              } catch (e) {
                debugPrint('announceViaBackend: setUrl/play failed for audioUrl: $e');
              }
            } else {
              debugPrint('announceViaBackend: No audio_url or base64 audio found in response');
            }
          } else if (!kIsWeb && Platform.isWindows) {
            // Use AudioDeviceService for Windows
            final audioDeviceService = AudioDeviceService();
            await audioDeviceService.initialize();
            debugPrint('announceViaBackend: Using AudioDeviceService for TTS playback with system device routing');
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              await audioDeviceService.playTTSAudio(base64Audio, isPersonal: false);
              final base64End = DateTime.now();
              debugPrint('[TIMER] announceViaBackend: Windows base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms');
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              final player = AudioPlayer();
              final audioUrlStart = DateTime.now();
              await player.setUrl(audioUrl);
              await player.play();
              final audioUrlEnd = DateTime.now();
              debugPrint('[TIMER] announceViaBackend: Windows audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms');
              backendAudioPlayed = true;
            }
          } else if (!kIsWeb && Platform.isAndroid) {
            final platform = MethodChannel('audio_routing');
            final player = AudioPlayer();
            await _flutterTts.stop();
            await player.stop();
            debugPrint('[TIMER] announceViaBackend: Before forceSpeaker (Android) at ${DateTime.now().millisecondsSinceEpoch}');
            try {
              await platform.invokeMethod('forceSpeaker');
              debugPrint('Android forceSpeaker call completed successfully');
              
              // Add additional delay to ensure audio routing is fully established
              // This prevents the beginning of speech from being cut off
              debugPrint('Android: Waiting additional 300ms for complete routing setup...');
              await Future.delayed(const Duration(milliseconds: 300));
              debugPrint('Android: Audio routing setup complete');
            } catch (e) {
              debugPrint('Android forceSpeaker call FAILED: $e');
            }
            
            // *** ANDROID AUDIO PRIMING - Play silence.mp3 to wake up audio system ***
            debugPrint('[TIMER] announceViaBackend: Before silence.mp3 priming (Android) at ${DateTime.now().millisecondsSinceEpoch}');
            final silenceStart = DateTime.now();
            try {
              await player.setAsset('assets/silence.mp3');
              await player.play();
              debugPrint('Android: silence.mp3 priming completed successfully');
            } catch (e) {
              debugPrint('Android: silence.mp3 priming failed: $e');
            }
            final silenceEnd = DateTime.now();
            debugPrint('[TIMER] announceViaBackend: After silence.mp3 priming at ${silenceEnd.millisecondsSinceEpoch} (delta: ${silenceEnd.difference(silenceStart).inMilliseconds} ms)');
            
            debugPrint('Stopping scanning before backend audio playback');
            _stopAuditoryScanning();
            
            // --- PRIORITIZE BASE64 AUDIO (FASTER) OVER AUDIO URL ---
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              debugPrint('*** ANDROID DEEPSEK: Using base64 audio (PREFERRED - faster than audioUrl) ***');
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File('${tempDir.path}/backend_tts.mp3').create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              // --- Wait for playback to finish before resetToDefault ---
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
              debugPrint('[TIMER] announceViaBackend: Android base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms');
              await Future.delayed(const Duration(milliseconds: 100));
              try {
                await platform.invokeMethod('resetToDefault');
                debugPrint('Android resetToDefault call completed successfully after base64 playback');
              } catch (e) {
                debugPrint('Android resetToDefault call FAILED after base64 playback: $e');
              }
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              final audioUrlStart = DateTime.now();
              
              // Fallback to audioURL if base64Audio is not available
              debugPrint('*** ANDROID DEEPSEK: Fallback to audioUrl (slower than base64) for: $audioUrl ***');
              try {
                await player.setUrl(audioUrl);
                // --- Wait for playback to finish before resetToDefault ---
                final completer = Completer<void>();
                final sub = player.playerStateStream.listen((state) {
                  if (state.processingState == ProcessingState.completed) {
                    if (!completer.isCompleted) completer.complete();
                  }
                });
                await player.play();
                await completer.future;
                await sub.cancel();
                debugPrint('*** ANDROID DEEPSEK: AudioUrl playback completed successfully ***');
                backendAudioPlayed = true;
              } catch (e) {
                debugPrint('*** ANDROID ERROR: AudioUrl playback failed: $e ***');
                backendAudioPlayed = false;
              }
              
              final audioUrlEnd = DateTime.now();
              debugPrint('[TIMER] announceViaBackend: Android audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms');
              await Future.delayed(const Duration(milliseconds: 100));
              try {
                await platform.invokeMethod('resetToDefault');
                debugPrint('Android resetToDefault call completed successfully after audioUrl playback');
              } catch (e) {
                debugPrint('Android resetToDefault call FAILED after audioUrl playback: $e');
              }
            }
          } else {
            // Fallback: try just_audio
            final player = AudioPlayer();
            if (audioUrl != null && audioUrl.isNotEmpty) {
              final audioUrlStart = DateTime.now();
              await player.setUrl(audioUrl);
              await player.play();
              final audioUrlEnd = DateTime.now();
              debugPrint('[TIMER] announceViaBackend: Fallback audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms');
              backendAudioPlayed = true;
            } else if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File('${tempDir.path}/backend_tts.mp3').create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              await player.play();
              final base64End = DateTime.now();
              debugPrint('[TIMER] announceViaBackend: Fallback base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms');
              backendAudioPlayed = true;
            }
          }
        } catch (e) {
          debugPrint('announceViaBackend: Audio playback failed: $e');
          backendAudioPlayed = false;
        }
      } else {
        debugPrint(
          'announceViaBackend: Backend error ${response.statusCode}: ${response.body}',
        );
      }
      // Fallback: use local TTS if backend audio not played
      if (!backendAudioPlayed) {
        debugPrint('announceViaBackend: Fallback to local TTS for "$text"');
        await _flutterTts.stop();
        // Skip setVoice to avoid Fire tablet TTS voice errors
        // Wait for local TTS to finish before returning
        final ttsCompleter = Completer<void>();
        _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) ttsCompleter.complete();
      });
      await _flutterTts.speak(text);
      await ttsCompleter.future;
      // Remove handler after use (set to empty function)
      _flutterTts.setCompletionHandler(() {});
    }
      // After using forceSpeaker, reset to default device - but only if not preserving microphone session
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        try {
          final platform = MethodChannel('audio_routing');
          if (!preserveMicrophoneSession) {
            debugPrint('resetToDefault called after option announcement');
            await platform.invokeMethod('resetToDefault');
          } else {
            debugPrint('Preserving microphone session - skipping resetToDefault');
          }
        } catch (e) {
          debugPrint('resetToDefault not implemented or failed: $e');
        }
      }
      final endTotal = DateTime.now();
      debugPrint('[TIMER] announceViaBackend: END at ${endTotal.millisecondsSinceEpoch} (total delta: ${endTotal.difference(startTotal).inMilliseconds} ms)');
    } catch (e) {
      debugPrint('announceViaBackend: Exception: $e');
      // Fallback: use local TTS if something fails
      await _flutterTts.stop();
      // Skip setVoice to avoid Fire tablet TTS voice errors
      final ttsCompleter = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) ttsCompleter.complete();
      });
      await _flutterTts.speak(text);
      await ttsCompleter.future;
      _flutterTts.setCompletionHandler(() {});
    } finally {
      // Reset announcement flag to allow scanning audio again
      _isAnnouncementPlaying = false;
    }
  }

  // --- Handle scanning key press ---
  void _handleScanKeyPress() async {
    if (!_isScanning || _scanningIndex == null) return;
    
    if (_currentScanningContext == "choose-word-categories") {
      // Handle category selection
      if (_scanningIndex! < _wordCategories.length) {
        String selectedCategory = _wordCategories[_scanningIndex!];
        _generateCategoryWords(selectedCategory);
      } else if (_scanningIndex! == _wordCategories.length) {
        // Cancel button
        _closeChooseWordModal();
      }
    } else if (_currentScanningContext == "choose-word-options") {
      // Handle word selection within a category
      if (_scanningIndex! < _currentCategoryWords.length) {
        String selectedWord = _currentCategoryWords[_scanningIndex!];
        await _addWordToBuildSpace(selectedWord);
        _closeChooseWordModal();
      } else {
        int controlIndex = _scanningIndex! - _currentCategoryWords.length;
        switch (controlIndex) {
          case 0: // Back to Categories
            setState(() {
              _currentScanningContext = "choose-word-categories";
              _currentChooseWordCategory = "";
              _currentCategoryWords = [];
            });
            _stopAuditoryScanning();
            Future.delayed(Duration(milliseconds: 300), () {
              _maybeStartScanning();
            });
            break;
          case 1: // Something Else
            if (_currentChooseWordCategory.isNotEmpty) {
              _generateCategoryWords(_currentChooseWordCategory);
            }
            break;
          case 2: // Go Back
            _closeChooseWordModal();
            break;
        }
      }
    } else if (_currentScanningContext == "spelling-letters") {
      // Handle spelling modal scanning with dynamic layout
      bool currentWordEmpty = _spellingWordController.text.trim().isEmpty;
      int controlButtonCount = currentWordEmpty ? 1 : 4; // Only Cancel when empty, all 4 when not empty
      
      if (_scanningIndex! < controlButtonCount) {
        // Control buttons - dynamic based on current word state
        if (currentWordEmpty) {
          // Only Cancel button available when current word is empty
          switch (_scanningIndex!) {
            case 0: _closeSpellingModal(); break;
          }
        } else {
          // All control buttons available when current word has content
          switch (_scanningIndex!) {
            case 0: _addCurrentWordToBuildSpace(); break;
            case 1: _clearCurrentWord(); break;
            case 2: _backspaceCurrentWord(); break;
            case 3: _closeSpellingModal(); break;
          }
        }
      } else {
        // After control buttons, we have predictions first, then valid letters
        int predictionCount = _currentPredictions.length;
        
        if (_scanningIndex! < controlButtonCount + predictionCount) {
          // Prediction buttons (come first after control buttons)
          int predictionIndex = _scanningIndex! - controlButtonCount;
          if (predictionIndex < _currentPredictions.length) {
            _handlePredictionClick(_currentPredictions[predictionIndex]);
          }
        } else {
          // Valid letter buttons (come after predictions)
          int letterIndex = _scanningIndex! - controlButtonCount - predictionCount;
          if (letterIndex < _validLetters.length) {
            String letter = _validLetters[letterIndex];
            _handleLetterClick(letter);
          }
        }
      }
    } else {
      // Handle main context scanning with new button layout: [Go Back] [Speak Display] [Clear Display] [word options...] [Choose Word] [More Options] [Spell]
      bool buildSpaceEmpty = _buildSpaceText.trim().isEmpty;
      int currentIndex = 0;
      
      debugPrint('🎯 FP _handleScanKeyPress MAIN: _scanningIndex=$_scanningIndex, buildSpaceEmpty=$buildSpaceEmpty, wordOptions=${_currentWordOptions.length}');
      
      // Go Back button (always first)
      if (_scanningIndex! == currentIndex) {
        Navigator.of(context).pop();
        return;
      }
      currentIndex++;
      
      // Speak Display and Clear Display buttons (only when build space is not empty)
      if (!buildSpaceEmpty) {
        if (_scanningIndex! == currentIndex) {
          _speakDisplayText();
          return;
        }
        currentIndex++;
        
        if (_scanningIndex! == currentIndex) {
          _clearDisplayText();
          return;
        }
        currentIndex++;
      }
      
      // Word option buttons
      if (_scanningIndex! >= currentIndex && _scanningIndex! < currentIndex + _currentWordOptions.length) {
        int wordIndex = _scanningIndex! - currentIndex;
        await _addWordToBuildSpace(_currentWordOptions[wordIndex]);
        return;
      }
      currentIndex += _currentWordOptions.length;
      
      // Choose Word button
      if (_scanningIndex! == currentIndex) {
        _openChooseWordModal();
        return;
      }
      currentIndex++;
      
      // More Options button
      if (_scanningIndex! == currentIndex) {
        _loadMoreWordOptions();
        return;
      }
      currentIndex++;
      
      // Spell button (moved to end)
      if (_scanningIndex! == currentIndex) {
        _openSpellingModal();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _gridFocusNode!,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
          debugPrint('FreestylePage - Spacebar pressed: _waitingForInitialSwitch=$_waitingForInitialSwitch, _isScanningPaused=$_isScanningPaused, _waitingForUserInput=$_waitingForUserInput, _isScanning=$_isScanning');
          
          // Handle initial switch press to start scanning
          if (_waitingForInitialSwitch) {
            debugPrint('FreestylePage - Initial switch detected, starting scanning');
            setState(() {
              _waitingForInitialSwitch = false;
              _switchStartRequested = true;
            });
            _startAuditoryScanning();
            return KeyEventResult.handled;
          }
          
          if (_isScanningPaused && _waitingForUserInput) {
            // If scanning is paused, resume it
            setState(() {
              _isScanningPaused = false;
              _waitingForUserInput = false;
              _isScanning = false; // Ensure scanning restarts
            });
            _maybeStartScanning();
          } else if (_isScanning && _scanningIndex != null && _scanningIndex! >= 0) {
            // Normal button selection when scanning is active
            debugPrint('🎯 FP Spacebar: Pressed with _scanningIndex=$_scanningIndex, _isScanning=$_isScanning, _currentScanningContext=$_currentScanningContext');
            _handleScanKeyPress();
          }
          _gridFocusNode?.requestFocus();
          return KeyEventResult.handled;
        } else if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
          // Tab key for step-mode scanning advancement
          final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
          final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
          
          debugPrint('FreestylePage: Tab pressed: scanMode=$scanMode, isScanning=$_isScanning, _isAnnouncingScanningPrompt=$_isAnnouncingScanningPrompt');
          
          if (scanMode == 'step' && _isScanning && _isAnnouncingScanningPrompt) {
            debugPrint('FreestylePage: Tab: Interrupting scanning announcement');
            // Interrupt the current scanning prompt announcement
            _flutterTts.stop();
            if (mounted) {
              setState(() {
                _isAnnouncingScanningPrompt = false;
              });
            }
          }
          
          if (scanMode == 'step' && _isScanning && _scanningIndex != null) {
            debugPrint('FreestylePage: Tab: Advancing in step mode from index $_scanningIndex');
            // Advance to next option
            _performScanStep();
          }
          _gridFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Free Style Communication'),
        backgroundColor: const Color(0xFF002244),
        foregroundColor: const Color(0xFFFB4F14),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Admin toolbar lock/unlock button
          IconButton(
            icon: Icon(_isAdminToolbarLocked ? Icons.lock : Icons.lock_open),
            onPressed: () {
              if (_isAdminToolbarLocked) {
                _showPinDialog();
              } else {
                setState(() {
                  _isAdminToolbarLocked = true;
                });
              }
            },
            tooltip: _isAdminToolbarLocked ? 'Unlock Admin Toolbar' : 'Lock Admin Toolbar',
          ),
          // Admin buttons - Only show when unlocked
          if (!_isAdminToolbarLocked) ...[
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Admin Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AdminSettingsPage(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.grid_on),
              tooltip: 'Admin Pages & Buttons',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AdminPagesButtonsPage(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: 'User Current Location',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => UserCurrentAdminPage(
                      idToken: widget.idToken,
                      aacUserId: widget.aacUserId,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'User Info & Birthdays',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => UserInfoAdminPage(
                      idToken: widget.idToken,
                      aacUserId: widget.aacUserId,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.book),
              tooltip: 'User Diary',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => UserDiaryAdminPage(
                      idToken: widget.idToken,
                      aacUserId: widget.aacUserId,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.volume_up),
              tooltip: 'Audio Device Admin',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AudioDeviceAdminPage(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.grid_view),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back to Grid',
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Build Space Section
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Build Space:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF002244), width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _buildSpaceController,
                        onChanged: (_) => _onBuildSpaceChange(),
                        readOnly: true,
                        enableInteractiveSelection: false,
                        canRequestFocus: false,
                        showCursor: false,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF002244),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Your message will appear here as you select words...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],
                ),
              ),
              
              // Unified Button Grid (Control buttons + Word options + Choose Word + More Options + Spell)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Options:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (_isLoadingWordOptions)
                        const Center(child: CircularProgressIndicator())
                      else
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: true);
                              final userSettings = settingsProvider.settings;
                              final int gridCols = userSettings?.gridColumns ?? 10;
                              
                              final double spacing = 6;
                              
                              // Get all buttons in the correct order
                              final allButtons = _buildAllButtons();
                              
                              return GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridCols,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                  childAspectRatio: 1.33,
                                ),
                                itemCount: allButtons.length,
                                itemBuilder: (context, index) {
                                  return allButtons[index];
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // Status Message
              if (_statusMessage?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.grey[100],
                  width: double.infinity,
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
          
          // Loading Indicator
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          
          // Spelling Modal
          if (_isSpellingModalOpen)
            _buildSpellingModal(),
          
          // Choose Word Modal
          if (_isChooseWordModalOpen)
            _buildChooseWordModal(),
          
          // Speech Bubble Overlay
          if (_showSpeechBubble)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3), // Semi-transparent background
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(40),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[400]!, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Text(
                      _speechBubbleText,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }


  Widget _buildSpellingControlButton(String text, IconData icon, Color color, VoidCallback onPressed, int buttonIndex) {
    bool isHighlighted = false;
    
    // Check if this button is currently being scanned
    if (_isScanning && _scanningIndex != null && _currentScanningContext == "spelling-letters") {
      isHighlighted = _scanningIndex == buttonIndex;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFFB4F14) : color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isHighlighted ? [
          BoxShadow(
            color: const Color(0xFFFB4F14).withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ] : null,
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 14),
        label: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _buildWordOptionButton(String word) {
    bool isHighlighted = false;
    // Get the button index matching _buildAllButtons() order
    int buttonIndex = _getButtonIndexForWordOption(word);
    if (_isScanning && _scanningIndex != null && _currentScanningContext == "main") {
      isHighlighted = _scanningIndex == buttonIndex;
      if (isHighlighted) {
        debugPrint('🎯 FP _buildWordOptionButton: word="$word" highlighted at index=$buttonIndex (_scanningIndex=$_scanningIndex)');
      }
    }
    
    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        final bool enablePictograms = userSettings?.enablePictograms ?? false;
        final Color lightColor = userSettings?.lightColor ?? const Color(0xFFFB4F14);
        
        // Calculate font size using same logic as main grid page
        // Set button size based on columns
        double buttonSizePx;
        if (gridCols >= 16) {
          buttonSizePx = 50.0;
        } else if (gridCols >= 12) {
          buttonSizePx = 60.0;
        } else if (gridCols >= 9) {
          buttonSizePx = 80.0;
        } else if (gridCols >= 7) {
          buttonSizePx = 100.0;
        } else if (gridCols >= 5) {
          buttonSizePx = 130.0;
        } else {
          buttonSizePx = 160.0;
        }
        
        // Use same font size formula as main grid
        final double fontSize = ((buttonSizePx / 10) * 1.44).clamp(14.4, 25.9);
        
        return Stack(
          children: [
            // Main button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 1.0],
                  colors: isHighlighted
                      ? [Colors.white, lightColor.withOpacity(0.5)]
                      : [Colors.white, Colors.white],
                ),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: isHighlighted ? lightColor : Colors.grey.shade300,
                  width: isHighlighted ? 3.0 : 1.0,
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: lightColor.withOpacity(0.6),
                          blurRadius: 12.0,
                          spreadRadius: 1.0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6.0,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 2.0,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async => await _addWordToBuildSpace(word),
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: enablePictograms
                        ? _buildPictogramButtonContent(word, fontSize, sightWordGradeLevel: userSettings?.sightWordGradeLevel, enableSightWords: userSettings?.enableSightWords)
                        : _buildTextOnlyButtonContent(word, fontSize, isSightWord: false), // No sight word styling when pictograms disabled
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Build text-only content with sight word checking
  Widget _buildTextOnlyWithSightWordCheck(String word, double fontSize, String? sightWordGradeLevel) {
    return FutureBuilder<bool>(
      future: _checkIfSightWord(word, sightWordGradeLevel),
      builder: (context, snapshot) {
        final bool isSightWord = snapshot.data ?? false;
        return _buildTextOnlyButtonContent(word, fontSize, isSightWord: isSightWord);
      },
    );
  }

  // Helper method to check if a word is a sight word
  Future<bool> _checkIfSightWord(String word, String? sightWordGradeLevel, {bool enableSightWords = true}) async {
    if (!enableSightWords || sightWordGradeLevel == null) return false;
    
    final sightWordService = SightWordService();
    if (!sightWordService.isInitialized) return false;
    
    await sightWordService.setGradeLevel(sightWordGradeLevel);
    return sightWordService.isSightWordText(word);
  }

  // Build text-only button content (original layout) with optional sight word styling
  Widget _buildTextOnlyButtonContent(String word, double fontSize, {bool isSightWord = false}) {
    // Apply special formatting for sight words
    final double adjustedFontSize = isSightWord ? fontSize * 1.3 : fontSize; // 30% larger for sight words
    final FontWeight fontWeight = isSightWord ? FontWeight.w700 : FontWeight.w500; // Bolder for sight words
    final Color textColor = isSightWord ? const Color(0xFF0066CC) : const Color(0xFF002244); // Blue for sight words
    
    return Container(
      decoration: isSightWord ? BoxDecoration(
        // Subtle background highlight for sight words
        color: const Color(0xFFF0F8FF), // Very light blue background
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF0066CC).withOpacity(0.3),
          width: 1,
        ),
      ) : null,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(isSightWord ? 4.0 : 0.0), // Extra padding for sight words
          child: LayoutBuilder(
            builder: (context, constraints) {
              double optimalFontSize = _calculateOptimalFontSize(
                word, 
                adjustedFontSize, 
                constraints.maxWidth,
                fontWeight,
              );
              
              return Text(
                word,
                style: TextStyle(
                  color: textColor,
                  fontSize: optimalFontSize,
                  fontWeight: fontWeight,
                  fontFamily: _safeRobotoCondensed(),
                  // Add subtle shadow for sight words
                  shadows: isSightWord ? [
                    const Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Color(0x30000000),
                    ),
                  ] : null,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
      ),
    );
  }

  // Build pictogram button content (large image on top, text footer at bottom)
  Widget _buildPictogramButtonContent(String word, double fontSize, {String? sightWordGradeLevel, bool? enableSightWords}) {
    // Create pictogram service instance with enablePictograms configuration
    final pictogramService = PictogramService();
    pictogramService.enablePictograms = true;
    
    return FutureBuilder<PictogramResult?>(
      future: pictogramService.getPictogramResult(
        word, 
        sightWordGradeLevel: sightWordGradeLevel != null ? int.tryParse(sightWordGradeLevel) : null,
        enableSightWords: enableSightWords ?? true,
        shouldLogMissing: false, // Don't log missing images for dynamically generated freestyle words
      ),
      builder: (context, snapshot) {
        final PictogramResult? result = snapshot.data;
        final String? pictogramUrl = result?.imageUrl;
        final bool isSightWord = result?.isSightWord ?? false;
        
        if (pictogramUrl == null || pictogramUrl.isEmpty) {
          // No pictogram found - show text only with sight word styling
          return _buildTextOnlyButtonContent(word, fontSize, isSightWord: isSightWord);
        }

        // Pictogram found - show large image with footer text
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Large image container (takes up most space)
            Expanded(
              flex: 5, // Much larger flex ratio for bigger images
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0), // More padding around image
                child: _buildPictogramImage(pictogramUrl, word),
              ),
            ),
            // Text footer at bottom (compact)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
              decoration: BoxDecoration(
                color: const Color(0xFF002244).withOpacity(0.1), // Subtle background
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10.0),
                  bottomRight: Radius.circular(10.0),
                ),
              ),
              child: Text(
                word,
                style: TextStyle(
                  color: const Color(0xFF002244),
                  fontSize: (fontSize * 0.65).clamp(9.0, 14.0), // Smaller footer text
                  fontWeight: FontWeight.w600,
                  fontFamily: _safeRobotoCondensed(),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  // Build the pictogram image widget
  Widget _buildPictogramImage(String pictogramUrl, String word) {
    // Check if it's an emoji (fallback pictogram) or a URL
    if (!pictogramUrl.startsWith('http')) {
      // It's an emoji - display as much larger text
      return Center(
        child: Text(
          pictogramUrl,
          style: const TextStyle(fontSize: 48), // Much larger emoji
          textAlign: TextAlign.center,
        ),
      );
    }

    // It's a URL - display as network image
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        pictogramUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // Image failed to load - show text only
          debugPrint('Failed to load image for "$word": $error');
          return Center(
            child: Text(
              word,
              style: TextStyle(
                color: const Color(0xFF002244),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: _safeRobotoCondensed(),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }

  /// Normalize option text: strip leading numbering like "1.", "1)", "1 - ", "1: " and trim
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

  // Build all buttons in the correct order for the unified grid
  List<Widget> _buildAllButtons() {
    List<Widget> buttons = [];
    bool buildSpaceEmpty = _buildSpaceText.trim().isEmpty;
    int currentIndex = 0;
    
    // Go Back button (always first)
    buttons.add(_buildMainControlButton(
      'Go Back',
      Icons.arrow_back,
      const Color(0xFF6B7280),
      () => Navigator.of(context).pop(),
      currentIndex,
    ));
    currentIndex++;
    
    // Speak Display and Clear Display buttons (only when build space is not empty)
    if (!buildSpaceEmpty) {
      buttons.add(_buildMainControlButton(
        'Speak Display',
        Icons.volume_up,
        const Color(0xFF10B981),
        _speakDisplayText,
        currentIndex,
      ));
      currentIndex++;
      
      buttons.add(_buildMainControlButton(
        'Clear Display',
        Icons.delete,
        const Color(0xFFEF4444),
        _clearDisplayText,
        currentIndex,
      ));
      currentIndex++;
    }
    
    // Word option buttons
    for (int i = 0; i < _currentWordOptions.length; i++) {
      buttons.add(_buildWordOptionButton(_currentWordOptions[i]));
      currentIndex++;
    }
    
    // Choose Word button
    buttons.add(_buildMainControlButton(
      'Choose Word',
      Icons.list,
      const Color(0xFF8B5CF6),
      _openChooseWordModal,
      currentIndex,
    ));
    currentIndex++;
    
    // More Options button
    buttons.add(_buildMoreOptionsButton(currentIndex));
    currentIndex++;
    
    // Spell button (right after More Options)
    buttons.add(_buildMainControlButton(
      'Spell',
      Icons.keyboard,
      const Color(0xFF3B82F6),
      _openSpellingModal,
      currentIndex,
    ));
    currentIndex++;
    
    return buttons;
  }

  // Calculate optimal font size to prevent word splitting
  double _calculateOptimalFontSize(String text, double baseFontSize, double maxWidth, FontWeight fontWeight) {
    if (text.trim().isEmpty) return baseFontSize;
    
    // Words in the text
    final words = text.trim().split(RegExp(r'\s+'));
    
    // Helper to check if text fits at a given size without splitting words
    bool fitsWithoutSplitting(double fontSize) {
      // Use a larger safety margin (80%) to aggressively prevent word splitting
      final double safeMaxWidth = maxWidth * 0.80;

      // First check if any single word is wider than maxWidth
      for (final word in words) {
        final wordPainter = TextPainter(
          textDirection: TextDirection.ltr,
          textScaleFactor: 1.0, // Explicitly match Text widget scaling
          text: TextSpan(
            text: word,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              fontFamily: _safeRobotoCondensed(),
            ),
          ),
        );
        wordPainter.layout();
        if (wordPainter.width > safeMaxWidth) return false;
      }
      
      return true;
    }

    // Binary search for the largest font size that fits without splitting words
    double low = baseFontSize * 0.4;
    double high = baseFontSize * 1.5; // Allow it to go larger if it fits
    double bestSize = low;
    
    // Perform more iterations for better precision
    for (int i = 0; i < 8; i++) {
      double mid = (low + high) / 2;
      if (fitsWithoutSplitting(mid)) {
        bestSize = mid;
        low = mid;
      } else {
        high = mid;
      }
    }
    
    return bestSize.clamp(baseFontSize * 0.5, baseFontSize * 1.3);
  }

  Widget _buildMainControlButton(String text, IconData icon, Color color, VoidCallback onPressed, int buttonIndex) {
    bool isHighlighted = false;
    
    // Check if this button is currently being scanned
    if (_isScanning && _scanningIndex != null && _currentScanningContext == "main") {
      isHighlighted = _scanningIndex == buttonIndex;
      if (isHighlighted) {
        debugPrint('🎯 FP _buildMainControlButton: text="$text" highlighted at index=$buttonIndex (_scanningIndex=$_scanningIndex)');
      }
    }
    
    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        
        // Calculate font size based on grid columns (same logic as word buttons)
        double fontSize;
        if (gridCols >= 16) {
          fontSize = 8.0;
        } else if (gridCols >= 12) {
          fontSize = 9.0;
        } else if (gridCols >= 9) {
          fontSize = 10.0;
        } else if (gridCols >= 7) {
          fontSize = 11.0;
        } else if (gridCols >= 5) {
          fontSize = 12.0;
        } else {
          fontSize = 13.0;
        }
        
        return Stack(
          children: [
            // Main button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 1.0],
                  colors: isHighlighted
                      ? [Colors.white, color.withOpacity(0.5)]
                      : [Colors.white, Colors.white],
                ),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: isHighlighted ? color : Colors.grey.shade300,
                  width: isHighlighted ? 3.0 : 1.0,
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.6),
                          blurRadius: 12.0,
                          spreadRadius: 1.0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6.0,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 2.0,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        double optimalFontSize = _calculateOptimalFontSize(
                          text, 
                          fontSize, 
                          constraints.maxWidth,
                          FontWeight.w500,
                        );
                        
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, color: color, size: optimalFontSize + 4),
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: TextStyle(
                                  color: color,
                                  fontSize: optimalFontSize,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: _safeRobotoCondensed(),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMoreOptionsButton(int buttonIndex) {
    bool isHighlighted = false;
    
    // Check if this button is currently being scanned
    if (_isScanning && _scanningIndex != null && _currentScanningContext == "main") {
      isHighlighted = _scanningIndex == buttonIndex;
    }
    
    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        final Color lightColor = userSettings?.lightColor ?? const Color(0xFFFB4F14);
        
        // Calculate font size using same logic as main grid page
        // Set button size based on columns
        double buttonSizePx;
        if (gridCols >= 16) {
          buttonSizePx = 50.0;
        } else if (gridCols >= 12) {
          buttonSizePx = 60.0;
        } else if (gridCols >= 9) {
          buttonSizePx = 80.0;
        } else if (gridCols >= 7) {
          buttonSizePx = 100.0;
        } else if (gridCols >= 5) {
          buttonSizePx = 130.0;
        } else {
          buttonSizePx = 160.0;
        }
        
        // Use same font size formula as main grid
        final double fontSize = ((buttonSizePx / 10) * 1.44).clamp(14.4, 25.9);
        
        return Stack(
          children: [
            // Main button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 1.0],
                  colors: isHighlighted
                      ? [Colors.white, lightColor.withOpacity(0.5)]
                      : [Colors.white, Colors.white],
                ),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: isHighlighted ? lightColor : Colors.grey.shade300,
                  width: isHighlighted ? 3.0 : 1.0,
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: lightColor.withOpacity(0.6),
                          blurRadius: 12.0,
                          spreadRadius: 1.0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6.0,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 2.0,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loadMoreWordOptions,
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        double optimalFontSize = _calculateOptimalFontSize(
                          'More Options', 
                          fontSize, 
                          constraints.maxWidth,
                          FontWeight.w500,
                        );
                        
                        return Center(
                          child: Text(
                            'More Options',
                            style: TextStyle(
                              color: const Color(0xFF002244),
                              fontSize: optimalFontSize,
                              fontWeight: FontWeight.w500,
                              fontFamily: _safeRobotoCondensed(),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSpellingModal() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Spell a Word',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF002244),
                    ),
                  ),
                  IconButton(
                    onPressed: _closeSpellingModal,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Current Word
              TextField(
                controller: _spellingWordController,
                readOnly: true,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF002244),
                ),
                decoration: InputDecoration(
                  labelText: 'Current Word',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF002244), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              
              // Word Controls (conditionally shown based on current word content)
              Wrap(
                spacing: 8,
                children: [
                  // Only show Add Word, Clear, and Backspace if current word is not empty
                  if (_spellingWordController.text.trim().isNotEmpty) ...[
                    _buildSpellingControlButton('Add Word', Icons.add, const Color(0xFF10B981), _addCurrentWordToBuildSpace, 0),
                    _buildSpellingControlButton('Clear', Icons.backspace, const Color(0xFFEF4444), _clearCurrentWord, 1),
                    _buildSpellingControlButton('Backspace', Icons.arrow_back, const Color(0xFFF59E0B), _backspaceCurrentWord, 2),
                  ],
                  // Always show Cancel button
                  _buildSpellingControlButton(
                    'Cancel', 
                    Icons.close, 
                    const Color(0xFF6B7280), 
                    _closeSpellingModal, 
                    _spellingWordController.text.trim().isEmpty ? 0 : 3, // Dynamic index
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Predictions
              if (_currentPredictions.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Suggested Words:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _currentPredictions.length,
                    itemBuilder: (context, index) {
                      // Check if this prediction button is currently being scanned
                      bool isHighlighted = false;
                      if (_isScanning && _scanningIndex != null && _currentScanningContext == "spelling-letters") {
                        int controlButtonCount = _spellingWordController.text.trim().isEmpty ? 1 : 4;
                        // Predictions come right after control buttons
                        int predictionIndex = _scanningIndex! - controlButtonCount;
                        isHighlighted = predictionIndex == index;
                      }
                      
                      return Container(
                        margin: const EdgeInsets.only(right: 10),
                        child: ElevatedButton(
                          onPressed: () => _handlePredictionClick(_currentPredictions[index]),
                          child: Text(_currentPredictions[index]),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isHighlighted ? const Color(0xFFFB4F14) : const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shadowColor: isHighlighted ? const Color(0xFFFB4F14).withOpacity(0.4) : null,
                            elevation: isHighlighted ? 8 : 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
              
              // Alphabet Grid
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Letters:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Consumer<UserSettingsProvider>(
                  builder: (context, settingsProvider, child) {
                    final userSettings = settingsProvider.settings;
                    final int gridCols = userSettings?.gridColumns ?? 10;
                    final letterOrder = userSettings?.spellLetterOrder ?? 'alphabetical';
                    
                    // Get ordered letters
                    final allLetters = _getAllLetters();
                    
                    // Calculate grid columns based on letter order
                    int letterGridCols = 10; // default for alphabetical and frequency
                    if (letterOrder == 'qwerty') {
                      letterGridCols = 10; // QWERTY layout uses 10 columns for top row
                    }
                    
                    // Calculate letter button font size (smaller than main grid buttons)
                    double buttonSizePx;
                    if (gridCols >= 16) {
                      buttonSizePx = 50.0;
                    } else if (gridCols >= 12) {
                      buttonSizePx = 60.0;
                    } else if (gridCols >= 9) {
                      buttonSizePx = 80.0;
                    } else if (gridCols >= 7) {
                      buttonSizePx = 100.0;
                    } else if (gridCols >= 5) {
                      buttonSizePx = 130.0;
                    } else {
                      buttonSizePx = 160.0;
                    }
                    
                    // Use larger font size for letter buttons (120% of main grid)
                    final double letterFontSize = (((buttonSizePx / 10) * 1.44) * 1.2).clamp(16.0, 31.0);
                    
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: letterGridCols,
                        crossAxisSpacing: 4, // Reduced spacing
                        mainAxisSpacing: 4,  // Reduced spacing
                        childAspectRatio: 1.0,
                      ),
                      itemCount: allLetters.length,
                      itemBuilder: (context, index) {
                        final letter = allLetters[index];
                        final isEnabled = _validLetters.contains(letter);
                        
                        bool isHighlighted = false;
                        if (_isScanning && _scanningIndex != null && _currentScanningContext == "spelling-letters") {
                          // Calculate which valid letter is currently being scanned
                          int predictionCount = _currentPredictions.length;
                          int controlButtonCount = _spellingWordController.text.trim().isEmpty ? 1 : 4;
                          
                          // Letters come after control buttons AND predictions
                          int letterStartIndex = controlButtonCount + predictionCount;
                          if (_scanningIndex! >= letterStartIndex) {
                            // We're scanning a valid letter
                            int validLetterIndex = _scanningIndex! - letterStartIndex;
                            if (validLetterIndex < _validLetters.length) {
                              String scannedLetter = _validLetters[validLetterIndex];
                              isHighlighted = letter == scannedLetter;
                            }
                          }
                        }
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: isHighlighted ? const Color(0xFFFB4F14) : (isEnabled ? Colors.white : Colors.grey[300]),
                            border: Border.all(
                              color: isHighlighted ? const Color(0xFFFB4F14) : (isEnabled ? const Color(0xFF002244) : Colors.grey),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: isHighlighted ? [
                              BoxShadow(
                                color: const Color(0xFFFB4F14).withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ] : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isEnabled ? () => _handleLetterClick(letter) : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Center(
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    fontSize: letterFontSize,
                                    fontWeight: FontWeight.w500,
                                    color: isHighlighted ? Colors.white : (isEnabled ? const Color(0xFF002244) : Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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

  Widget _buildChooseWordModal() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentScanningContext == "choose-word-categories" 
                        ? 'Choose Word Category' 
                        : 'Choose Word - ${_currentChooseWordCategory}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF002244),
                    ),
                  ),
                  IconButton(
                    onPressed: _closeChooseWordModal,
                    icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Content based on current context
              Expanded(
                child: _currentScanningContext == "choose-word-categories"
                    ? _buildCategoryGrid()
                    : _buildWordOptionsGrid(),
              ),
              
              const SizedBox(height: 20),
              
              // Control buttons
              if (_currentScanningContext == "choose-word-categories")
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildChooseWordControlButton(
                      'Go Back',
                      Icons.arrow_back,
                      const Color(0xFF6B7280),
                      _closeChooseWordModal,
                      _wordCategories.length, // Button index after all categories
                      "choose-word-categories",
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildChooseWordControlButton(
                      'Back to Categories',
                      Icons.arrow_back,
                      const Color(0xFF3B82F6),
                      () {
                        setState(() {
                          _currentScanningContext = "choose-word-categories";
                          _currentChooseWordCategory = "";
                          _currentCategoryWords = [];
                        });
                        _stopAuditoryScanning();
                        Future.delayed(const Duration(milliseconds: 300), () {
                          _maybeStartScanning();
                        });
                      },
                      _currentCategoryWords.length, // Button index after all word options
                      "choose-word-options",
                    ),
                    _buildChooseWordControlButton(
                      'Something Else',
                      Icons.refresh,
                      const Color(0xFF8B5CF6),
                      () {
                        if (_currentChooseWordCategory.isNotEmpty) {
                          _generateCategoryWords(_currentChooseWordCategory);
                        }
                      },
                      _currentCategoryWords.length + 1, // Second control button
                      "choose-word-options",
                    ),
                    _buildChooseWordControlButton(
                      'Go Back',
                      Icons.close,
                      const Color(0xFF6B7280),
                      _closeChooseWordModal,
                      _currentCategoryWords.length + 2, // Third control button
                      "choose-word-options",
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = (userSettings?.gridColumns ?? 10).clamp(3, 8); // Limit columns for categories
        
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: _wordCategories.length,
          itemBuilder: (context, index) {
            final category = _wordCategories[index];
            final isHighlighted = _isScanning && 
                _scanningIndex != null && 
                _currentScanningContext == "choose-word-categories" && 
                _scanningIndex == index;
            
            return Stack(
              children: [
                // Main button - white background with dark border like main grid
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFF002244),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _generateCategoryWords(category),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: userSettings?.enablePictograms == true
                            ? _buildPictogramButtonContent(category, 14.0, sightWordGradeLevel: userSettings?.sightWordGradeLevel, enableSightWords: userSettings?.enableSightWords)
                            : Center(
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    color: Color(0xFF002244), // Dark text on white background
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                // Glow overlay when highlighted - using simpler approach
                if (isHighlighted)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFFB4F14),
                          width: 3.0,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFB4F14).withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWordOptionsGrid() {
    if (_isLoadingCategoryWords) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: _currentCategoryWords.length,
          itemBuilder: (context, index) {
            final word = _currentCategoryWords[index];
            final isHighlighted = _isScanning && 
                _scanningIndex != null && 
                _currentScanningContext == "choose-word-options" && 
                _scanningIndex == index;
            
            return Stack(
              children: [
                // Main button - white background with dark border like main grid
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFF002244),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await _addWordToBuildSpace(word);
                        _closeChooseWordModal();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: userSettings?.enablePictograms == true
                            ? _buildPictogramButtonContent(word, 12.0, sightWordGradeLevel: userSettings?.sightWordGradeLevel, enableSightWords: userSettings?.enableSightWords)
                            : Center(
                                child: Text(
                                  word,
                                  style: const TextStyle(
                                    color: Color(0xFF002244), // Dark text on white background
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                // Glow overlay when highlighted - using simpler approach
                if (isHighlighted)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFFB4F14),
                          width: 3.0,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFB4F14).withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPinDialog() {
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
                const Text('Enter your 4-digit PIN:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
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
  Widget _buildKeypadButton(String label, TextEditingController controller, Function setState, {bool isBackspace = false}) {
    return SizedBox(
      width: 50,
      height: 40,
      child: ElevatedButton(
        onPressed: () {
          if (isBackspace) {
            if (controller.text.isNotEmpty) {
              controller.text = controller.text.substring(0, controller.text.length - 1);
              setState(() {});
            }
          } else {
            if (controller.text.length < 4) {
              controller.text += label;
              setState(() {});
            }
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
          style: TextStyle(fontSize: isBackspace ? 16 : 18, fontWeight: FontWeight.bold),
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
            content: Text('Too many incorrect attempts. Click the lock icon to try again.'),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {
          _pinAttempts = 0; // Reset for next time
        });
      } else {
        // Show error in dialog and stay open
        Navigator.of(dialogContext).pop();
        _showPinDialog(); // Show dialog again with error count
      }
    }
  }

  // Helper method to get the correct first button index based on context and state
  int _getFirstButtonIndex() {
    // Always start with first available button (index 0) regardless of context
    // The button layout logic handles which buttons are available
    return 0;
  }

  Widget _buildChooseWordControlButton(String text, IconData icon, Color color, VoidCallback onPressed, int buttonIndex, String context) {
    bool isHighlighted = false;
    
    // Check if this button is currently being scanned
    if (_isScanning && _scanningIndex != null && _currentScanningContext == context) {
      if (context == "choose-word-categories") {
        // For categories context, control button is after all categories
        isHighlighted = _scanningIndex == buttonIndex;
      } else if (context == "choose-word-options") {
        // For word options context, control buttons are after all word options
        isHighlighted = _scanningIndex == buttonIndex;
      }
    }
    
    return Stack(
      children: [
        // Main button
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(text),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
        ),
        // Glow overlay when highlighted
        if (isHighlighted)
          Positioned.fill(
            child: CustomPaint(
              painter: _FreestyleButtonGlowPainter(
                glowColor: const Color(0xFFFB4F14),
              ),
            ),
          ),
      ],
    );
  }
}

// Glow painter for border-only highlighting like main grid page
class _FreestyleButtonGlowPainter extends CustomPainter {
  final Color glowColor;
  _FreestyleButtonGlowPainter({required this.glowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = 8.0;
    final Rect buttonRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final RRect rrect = RRect.fromRectAndRadius(buttonRect, Radius.circular(radius));
    
    final Paint glowPaint = Paint()
      ..color = glowColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);
    
    canvas.drawRRect(rrect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _FreestyleButtonGlowPainter oldDelegate) {
    return oldDelegate.glowColor != glowColor;
  }
}
