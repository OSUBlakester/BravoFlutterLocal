import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/environment_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/user_settings_provider.dart';
import 'services/audio_device_provider.dart';
import 'services/audio_device_service.dart';
import 'services/wake_word_service.dart';
import 'services/authenticated_http_client.dart';
import 'admin_settings_scaffold.dart';
import 'admin_pages_buttons.dart';
import 'user_current_admin_page.dart';
import 'user_info_admin_page.dart';
import 'user_diary_admin_page.dart';
import 'audio_device_admin_page.dart';
import 'main.dart'; // Import for GridPage

class ThreadsPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;

  const ThreadsPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
  });

  @override
  ThreadsPageState createState() => ThreadsPageState();
}

class ThreadsPageState extends State<ThreadsPage> with RouteAware {
  // --- UI State Variables ---
  bool _isLoading = false;
  String? _statusMessage;
  
  // --- Thread State ---
  Map<String, dynamic>? _currentThread;
  List<Map<String, dynamic>> _threadMessages = [];
  List<Map<String, dynamic>> _currentOptions = [];
  
  // --- Scanning State ---
  bool _isScanning = false;
  bool _isScanningPaused = false;
  bool _waitingForUserInput = false;
  bool _isAnnouncementPlaying = false;
  bool _isAnnouncingScanningPrompt = false;  // Track if announcing during scanning prompts (for Tab interrupt)
  int? _scanningIndex;
  Timer? _scanningTimer;
  Timer? _statusMessageTimer; // Timer to auto-reset long status messages
  bool _suppressScanning = false;
  int _currentScanCycle = 0; // Track how many complete cycles we've done
  
  // Wait-for-switch feature tracking
  bool _waitingForInitialSwitch = false;
  bool _switchStartRequested = false;
  
  // --- Audio & TTS ---
  
  // --- Wake Word Service - CLEAN ARCHITECTURE ---
  // ThreadsPage is a PASSIVE consumer of the shared service
  // NO restart management, NO service lifecycle control
  final FlutterTts _flutterTts = FlutterTts();
  bool _audioSessionInitialized = false;
  
  // --- Focus Management ---
  FocusNode? _threadFocusNode;
  
  // --- Admin Toolbar State ---
  bool _isAdminToolbarLocked = true;
  String? _currentPIN = '1234';
  
  // --- Question Input ---
  final TextEditingController _questionController = TextEditingController();
  bool _highlightQuestionBox = false;
  
  // --- Question Processing State ---
  bool _processingQuestion = false; // Add guard to prevent duplicate processing
  
  // --- Wake Word Service Connection - CLEAN ARCHITECTURE ---
  // Reference to shared service instance (for callback setup only)
  WakeWordService? _wakeWordService;
  String _wakeWordInterjection = 'hey';
  String _wakeWordName = 'bravo';
  List<String> _wakeWordVariants = [];
  bool _isListeningForQuestion = false;
  
  // --- Microphone State (matching main.dart pattern) ---
  bool _microphoneEnabled = true;  // Whether microphone is enabled/available
  bool _microphoneListening = false; // Whether actively listening for question (red icon)
  
  // --- History ScrollController ---
  final ScrollController _historyScrollController = ScrollController();

  // --- Speech Bubble Overlay Variables ---
  bool _showSpeechBubble = false; // Track if speech bubble is visible
  String _speechBubbleText = ''; // Text to display in speech bubble
  Timer? _speechBubbleTimer; // Timer to auto-hide speech bubble

  // --- Status Message Variables (for "Last heard" debugging) ---
  String _lastHeardWords = ''; // Last heard words for debugging

  // --- Health Check Variables ---
  Timer? _healthCheckTimer;
  DateTime? _lastActivityTime;

  @override
  void initState() {
    super.initState();
    print('🟢 ThreadsPage initState called - starting initialization');
    print('🟢 ThreadsPage - idToken: ${widget.idToken.isNotEmpty ? "Present" : "Missing"}');
    print('🟢 ThreadsPage - aacUserId: ${widget.aacUserId}');
    
    _threadFocusNode = FocusNode();
    
    print('🟢 ThreadsPage - setting up TTS');
    _setupTTS();
    
    print('🟢 ThreadsPage - setting up wake word service (dedicated instance)');
    // Make setup async to wait for proper initialization
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _setupWakeWordConnection();
    });
    
    // Don't use static callbacks anymore - we have our own instance
    print('🟢 ThreadsPage - Wake word service setup initiated with dedicated instance');
    
    // Add a small delay to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🟢 ThreadsPage post-frame callback - starting favorite location check');
      try {
        _checkFavoriteLocationAndOpenThread();
        
        // Set initial status message to show wake word listening is active
        if (mounted) {
          setState(() {
            _statusMessage = 'Wake word listening active - say "Hey Brady"';
          });
        }
      } catch (e) {
        print('🔴 ThreadsPage ERROR in post-frame callback: $e');
        print('🔴 ThreadsPage ERROR stack trace: ${StackTrace.current}');
      }
    });
    
    print('🟢 ThreadsPage initState completed successfully');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer for proper navigation lifecycle management
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      // Import routeObserver from main.dart if not already available
      // For now, we'll handle this differently since we don't have direct access
      print('🟢 ThreadsPage didChangeDependencies - Route observer integration ready');
    }
  }

  // --- STATUS MESSAGE AUTO-RESET HELPER METHOD ---
  void _updateStatusMessageWithAutoReset(String message, {Duration resetAfter = const Duration(seconds: 3)}) {
    // Cancel any existing timer
    _statusMessageTimer?.cancel();
    
    // Update the status message
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
    
    // Set up auto-reset timer for long hearing messages
    if (message.contains('Listening:') || message.contains('Hearing:') || message.contains('Listening for wake word:')) {
      _statusMessageTimer = Timer(resetAfter, () {
        if (mounted) {
          setState(() {
            _statusMessage = ''; // Clear the status message
          });
        }
      });
    }
  }

  @override
  void dispose() {
    print('🟢 ThreadsPage - dispose called, cleaning up');
    
    // Stop health check timer
    _stopHealthCheck();
    
    // Reset processing flags
    _processingQuestion = false;
    
    _threadFocusNode?.dispose();
    _questionController.dispose();
    _historyScrollController.dispose();
    _scanningTimer?.cancel();
    _statusMessageTimer?.cancel(); // Clean up status message timer
    _speechBubbleTimer?.cancel(); // Clean up speech bubble timer
    _flutterTts.stop();
    super.dispose();
  }

  // --- TTS Setup ---
  Future<void> _setupTTS() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
    } catch (e) {
      debugPrint('TTS setup error: $e');
    }
  }

  // --- Speech Bubble Overlay Methods ---
  
  /// Show speech bubble overlay with announcement text
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
    
    debugPrint('ThreadsPage Speech bubble displayed for ${duration}ms: "$text"');
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
    
    debugPrint('ThreadsPage Speech bubble hidden');
  }

  // --- Ultra-fast TTS announcement using exact POC approach for built-in speaker routing (matching main.dart) ---
  Future<void> _announceSimpleTTS(String text) async {
    try {
      debugPrint('[POC TTS] ThreadsPage: Starting exact POC-style TTS for: "$text"');
      
      // CRITICAL POC FIX: Use new pauseSpeechRecognition to stop audio interference without losing wake word state
      debugPrint('[POC TTS] ThreadsPage: Pausing speech recognition to prevent audio interference...');
      await WakeWordService.pauseSpeechRecognition();
      await Future.delayed(Duration(milliseconds: 100)); // POC-style brief pause
      
      // Minimal delay before audio routing change (like POC)
      await Future.delayed(Duration(milliseconds: 100));
      
      // Skip early forceSpeaker call - let _announceViaBackend handle audio routing consistently
      debugPrint('[POC TTS] ThreadsPage: Delegating audio routing to _announceViaBackend for consistency');
      
      debugPrint('[POC TTS] ThreadsPage: Playing "$text" announcement through speaker...');
      
      // Show speech bubble if enabled (same as main.dart)
      setState(() {
        _showSpeechBubble = true;
        _speechBubbleText = text;
      });
      debugPrint('ThreadsPage: Speech bubble displayed for 3000ms: "$text"');
      
      // FAST ANNOUNCEMENT: Use backend TTS similar to main.dart's announceViaBackendSimple approach
      debugPrint('[POC TTS] ThreadsPage: Using fast backend TTS without Bluetooth setup...');
      
      // Call backend TTS with preservation of microphone session (like main.dart announceViaBackendSimple)
      await _announceViaBackend(text, routing: 'system', preserveMicrophoneSession: true);
      
      debugPrint('[POC TTS] ThreadsPage: Fast backend TTS announcement completed');
      
      // Minimal delay since we're not doing complex audio routing
      await Future.delayed(Duration(milliseconds: 100)); // Very short delay
      debugPrint('[POC TTS] ThreadsPage: Ready for immediate question listening');
      
      debugPrint('[POC TTS] ThreadsPage: Fast announcement completed, ready for next step...');
    } catch (e) {
      debugPrint('[POC TTS] ThreadsPage: Error: $e');
      // Fallback to simple local TTS if backend fails
      try {
        await _flutterTts.stop();
        await _flutterTts.speak(text);
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (fallbackError) {
        debugPrint('[POC TTS] ThreadsPage: Fallback TTS also failed: $fallbackError');
      }
    }
  }

  // --- Initialize Wake Word Connection (connect to shared service) ---
  Future<void> _setupWakeWordConnection() async {
    try {
      debugPrint('🎤 ThreadsPage _setupWakeWordConnection: Connecting to shared wake word service');
      
      // Get wake word settings from provider (EXACT same logic as main.dart)
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      
      _wakeWordInterjection = (settingsProvider.settings?.wakeWordInterjection ?? 'hey').trim().toLowerCase();
      _wakeWordName = (settingsProvider.settings?.wakeWordName ?? 'bravo').trim().toLowerCase();
      _wakeWordVariants = [
        '${_wakeWordInterjection} ${_wakeWordName}',
        '${_wakeWordInterjection}, ${_wakeWordName}',
        '${_wakeWordInterjection},${_wakeWordName}',
      ];
      debugPrint('🎤 ThreadsPage wake word variants configured: \'${_wakeWordVariants.join("' | '")}\'');
      
      // USE SHARED INSTANCE instead of creating a new one (prevents conflicts)
      _wakeWordService = WakeWordService.getCurrentInstance();
      
      if (_wakeWordService == null) {
        debugPrint('🔴 ThreadsPage: No shared WakeWordService instance available - may not be initialized yet');
        return;
      }
      
      debugPrint('🎤 ThreadsPage: Using shared WakeWordService instance');
      
      // Setup wake word callbacks directly on shared instance (same as main.dart)
      _setupWakeWordCallbacks();
      
      // Set microphone as enabled since we have permission
      if (mounted) {
        setState(() {
          _microphoneEnabled = true;
          _microphoneListening = false;
        });
      }
      
      debugPrint('🎤 ThreadsPage starting wake word service after initialization.');
      
      // CRITICAL: Ensure auto-restart is enabled for the shared instance
      _wakeWordService?.resumeWakeWordAutoRestart();
      
      // Start fresh wake word listening for this page
      await _wakeWordService?.startWakeWordListening();
      debugPrint('🎤 ThreadsPage initial wake word listening started.');
      
      debugPrint('🎤 ThreadsPage wake word service initialization complete.');
      
    } catch (e) {
      debugPrint('🔴 ThreadsPage ERROR initializing wake word service: $e');
    }
  }

  // --- Wake Word Callbacks Setup (context-aware for shared service) ---
  void _setupWakeWordCallbacks() {
    if (_wakeWordService == null) return;
    
    debugPrint('🎤 ThreadsPage - Setting up context-aware wake word service callbacks on shared instance');
    
    // Store the original callback if it exists
    final originalOnWakeWord = _wakeWordService!.onWakeWord;
    
    _wakeWordService!.onWakeWord = (transcript) async {
      final callbackStart = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[TIMER] Shared service CALLBACK START: onWakeWord at $callbackStart');
      
      // Check if ThreadsPage is currently active and mounted
      if (!mounted) {
        debugPrint('[WakeWord] Shared service: ThreadsPage not mounted, delegating to main app');
        if (originalOnWakeWord != null) {
          originalOnWakeWord(transcript);
        }
        return;
      }
      
      // Check if we're currently in the foreground by looking at the current route
      final currentRoute = ModalRoute.of(context);
      final isThreadsPageActive = currentRoute?.settings.name == '/threads' || 
                                  context.widget.runtimeType.toString() == 'ThreadsPage';
      
      if (!isThreadsPageActive) {
        debugPrint('[WakeWord] Shared service: ThreadsPage not active, delegating to main app');
        if (originalOnWakeWord != null) {
          originalOnWakeWord(transcript);
        }
        return;
      }
      
      debugPrint('ThreadsPage: Wake word detected in transcript (active page): $transcript');
      
      setState(() {
        _statusMessage = 'Wake word heard! Preparing to listen...';
        _isListeningForQuestion = true;
        _highlightQuestionBox = true;
        _microphoneListening = true;
      });

      _stopAuditoryScanning();
      debugPrint('ThreadsPage: Auditory scanning stopped.');

      // SIMPLIFIED: Quick stop like POC - no complex delays
      debugPrint('[WakeWord] ThreadsPage: Quick stop like POC...');
      _wakeWordService?.pauseWakeWordAutoRestart();
      
      // POC APPROACH: Simple concurrent execution - start question listening while announcement plays  
      debugPrint('[TIMER] ThreadsPage: Before announceViaBackend at ${DateTime.now().millisecondsSinceEpoch}');
      
      // Set up state for announcement
      setState(() {
        _statusMessage = 'Playing announcement...';
      });
      
      try {
        debugPrint('[WakeWord] ThreadsPage: POC approach: concurrent announcement + question setup...');
        
        // SIMPLIFIED FAST APPROACH: Use same POC approach as main.dart
        debugPrint('[WakeWord] ThreadsPage: Playing short announcement for faster response...');
        
        // Remove redundant forceSpeaker - let announcement method handle audio routing consistently
        debugPrint('[WakeWord] ThreadsPage: Delegating audio routing to announcement method');
        
        debugPrint('[WakeWord] ThreadsPage: About to call FAST announcement (skipping complex audio routing)...');
        final fastAnnounceStart = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[TIMER] ThreadsPage: Fast announce START at $fastAnnounceStart');
        
        // Use ultra-fast TTS like main.dart _announceSimpleTTS (shorter message like main.dart)
        final announcementFuture = _announceSimpleTTS('Listening');
        
        // Wait for the announcement to actually complete before proceeding  
        await announcementFuture;
        
        final fastAnnounceEnd = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[TIMER] ThreadsPage: Fast announce COMPLETE at $fastAnnounceEnd (delta: ${fastAnnounceEnd - fastAnnounceStart}ms)');
        
        debugPrint('[POC TTS] ThreadsPage: Fast backend TTS announcement completed');
        debugPrint('[POC TTS] ThreadsPage: Ready for immediate question listening');
        debugPrint('[POC TTS] ThreadsPage: Fast announcement completed, starting question listening...');
        
        debugPrint('[WakeWord] ThreadsPage: Both fast announcement and audio setup completed');
        debugPrint('[TIMER] ThreadsPage: After fast announcement at ${DateTime.now().millisecondsSinceEpoch}');
        
        if (mounted) {
          setState(() {
            _statusMessage = 'Ready to listen...';
          });
        }
        
        // NOW start question listening immediately - POC approach
        debugPrint('[TIMER] ThreadsPage: Before startQuestionListening at ${DateTime.now().millisecondsSinceEpoch}');
        debugPrint('[WakeWord] ThreadsPage: Starting question listening immediately (POC approach)...');
        
        final questionListenStart = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[TIMER] ThreadsPage: Question listening call START at $questionListenStart');
        
        _wakeWordService!.startQuestionListening();
        
        final questionListenEnd = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[TIMER] ThreadsPage: Question listening call END at $questionListenEnd (delta: ${questionListenEnd - questionListenStart}ms)');
        
        debugPrint('[WakeWord] ThreadsPage: Question listening started successfully');
        debugPrint('[TIMER] ThreadsPage: After startQuestionListening at ${DateTime.now().millisecondsSinceEpoch}');
        
        final callbackEnd = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[TIMER] ThreadsPage: CALLBACK END: onWakeWord at $callbackEnd (total delta: ${callbackEnd - callbackStart}ms)');
        
      } catch (e) {
        debugPrint('[WakeWord] ThreadsPage: Error with concurrent setup: $e');
        // SHARED SERVICE: Let service handle errors, don't force restart
        return;
      }
      
      // Set up timeout protection for stuck listening states (reduced to 10 seconds)
      Timer(const Duration(seconds: 10), () {
        if (_isListeningForQuestion) {
          debugPrint('[WakeWord] ThreadsPage: TIMEOUT: Question listening stuck after 10 seconds, forcing reset...');
          if (!mounted) {
            debugPrint('[WakeWord] ThreadsPage: Widget not mounted during timeout, skipping reset');
            return;
          }
          
          setState(() {
            _isListeningForQuestion = false;
            _highlightQuestionBox = false;
            _microphoneListening = false;
            _statusMessage = 'Listening timeout - try again';
          });
          
          // The shared service handles its own timeout recovery
        }
      });
    };
      
      _wakeWordService!.onQuestion = (question) async {
        debugPrint('ThreadsPage: Question detected: $question');
        
        // CRITICAL: Check if widget is still mounted before setState
        if (!mounted) {
          debugPrint('[WakeWord] ThreadsPage onQuestion: Widget not mounted, skipping setState');
          return;
        }
        
        // CRITICAL: Prevent duplicate question processing
        if (_processingQuestion) {
          debugPrint('[WakeWord] ThreadsPage onQuestion: Already processing a question, skipping duplicate');
          return;
        }
        
        _processingQuestion = true; // Set guard flag
        
        try {
          // *** CAPTURE PAUSED STATE BEFORE PROCESSING QUESTION ***
          final wasScanningPaused = _isScanningPaused && _waitingForUserInput;
          debugPrint('ThreadsPage onQuestion: Captured paused state: $wasScanningPaused');
          
          setState(() {
            _questionController.text = question;
            _highlightQuestionBox = false;
            _isListeningForQuestion = false;
            _microphoneListening = false; // Return to green microphone icon
            _isLoading = true;
            _statusMessage = 'Processing: $question';
          });
          
          // Announce processing like main.dart does
          await _announceWithTimeout('Okay, processing: $question. Give me a moment.', routing: 'system', speechRate: 140);
          
          // CRITICAL: Record the question to thread history with 'incoming' sender_type (like threads.js)
          await _addMessageToThread(question, 'incoming');
          
          // Add delay before processing like main.dart
          await Future.delayed(const Duration(seconds: 2));
          
          // Process the question directly instead of going through _handleQuestionInput
          await _getLLMResponseForThreads(question, wasInPausedState: wasScanningPaused);
        } finally {
          _processingQuestion = false; // Always reset guard flag
        }
      };
      
      _wakeWordService!.onQuestionHighlight = (highlight) {
        if (!mounted) return;
        setState(() {
          _highlightQuestionBox = highlight;
        });
      };
      
      _wakeWordService!.onTimeout = () async {
        print('🚨 ThreadsPage - onTimeout callback FIRED');
        if (!mounted) return;
        print('🟢 ThreadsPage - Question listening timeout - performing basic state reset');
        
        setState(() {
          _highlightQuestionBox = false;
          _isListeningForQuestion = false;
          _microphoneListening = false; // Return to green microphone icon
          _statusMessage = 'Ready for wake word...';
        });
        
        // CRITICAL: Clear any scanning pause flags that might prevent restart
        print('🟢 ThreadsPage - Clearing scanning pause flags after timeout');
        _waitingForUserInput = false;
        _isScanningPaused = false;
        _suppressScanning = false;
        
        // Reset scan cycle count for fresh start
        _currentScanCycle = 0;
        
        // The wake word service will handle the restart and trigger onAnnounce
        // which will control the proper timing of scanning restart
        print('🟢 ThreadsPage - Timeout state reset complete, wake word service will handle announcement and restart');
      };
      
      _wakeWordService!.onStatusBarUpdate = (heardText) {
        // CRITICAL: Check if widget is still mounted before setState
        if (!mounted) {
          debugPrint('[WakeWord] ThreadsPage onStatusBarUpdate: Widget not mounted, skipping setState');
          return;
        }
        
        debugPrint('[WakeWord] ThreadsPage onStatusBarUpdate: heardText="$heardText"');
        
        setState(() {
          _lastHeardWords = heardText;
          
          // Update status for both wake word and question listening
          if (_isListeningForQuestion && heardText.isNotEmpty) {
            // During question processing, show "Hearing: ..." messages
            _statusMessage = 'Hearing: "$heardText"';
            debugPrint('[WakeWord] ThreadsPage: Question hearing status updated to: "$_statusMessage"');
          } else if (!_isListeningForQuestion && heardText.isNotEmpty) {
            // During wake word detection, show what's being heard with auto-reset
            _updateStatusMessageWithAutoReset('Listening for wake word: "$heardText"', resetAfter: const Duration(seconds: 3));
          } else if (heardText.isEmpty) {
            // Clear status when no speech is detected
            debugPrint('[WakeWord] ThreadsPage: No speech detected, clearing status message');
            _statusMessageTimer?.cancel();
            _statusMessage = '';
          }
        });
      };
      
      _wakeWordService!.onAnnounce = (message) async {
        debugPrint('🚨 ThreadsPage - onAnnounce callback FIRED with message: $message');
        if (!mounted) return;
        
        // CRITICAL: Check if we're already playing an announcement to prevent conflicts
        if (_isAnnouncementPlaying) {
          debugPrint('� ThreadsPage - onAnnounce BLOCKED: announcement already playing');
          return;
        }
        
        // Special handling for timeout announcements (match main.dart pattern exactly)
        if (message.contains("I didn't hear anything") || message.contains("Try again")) {
          debugPrint('🟢 ThreadsPage - Detected timeout announcement, pausing wake word service first');
          
          // CRITICAL: Pause wake word service BEFORE announcement to prevent interference
          _wakeWordService?.pauseWakeWordAutoRestart();
          await _wakeWordService?.stopAllRecognizers();
          
          // Stop any current scanning
          if (_isScanning) {
            _stopAuditoryScanning();
          }
          
          // CRITICAL FIX: Use direct _announceViaBackend call like main.dart (NO timeout wrapper, preserve microphone session)
          debugPrint('🟢 ThreadsPage - Playing timeout announcement with wake word service stopped');
          await _announceViaBackend(message, routing: 'system', preserveMicrophoneSession: true);
          debugPrint('🟢 ThreadsPage - Timeout announcement completed successfully');
          
          // Add delay and restart scanning like main.dart
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted && _currentOptions.isNotEmpty) {
            _maybeStartScanning();
          }
          
        } else {
          // CRITICAL FIX: Normal announcements - use direct _announceViaBackend call like main.dart (NO timeout wrapper, preserve microphone session)
          debugPrint('🟢 ThreadsPage - Playing normal wake word announcement: $message');
          await _announceViaBackend(message, routing: 'system', preserveMicrophoneSession: true);
        }
        
        debugPrint('🟢 ThreadsPage - Wake word announcement completed: $message');
      };
      
      _wakeWordService!.shouldAllowWakeWordRestart = () {
        // Always allow wake word restart on ThreadsPage to maintain microphone session
        return true;
      };
    
    print('🟢 ThreadsPage - Wake word callbacks set up successfully on dedicated instance');
  }
  
  // --- Restart Wake Word Service Method (with debounce) ---
  // --- Get LLM Response (Thread-optimized version matching main.dart pattern) ---
  Future<void> _getLLMResponseForThreads(String question, {bool wasInPausedState = false}) async {
    try {
      debugPrint('ThreadsPage _getLLMResponseForThreads: Starting LLM call, wasInPausedState=$wasInPausedState');
      
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;
      final llmOptions = userSettings?.llmOptions ?? 10;
      final summaryOff = userSettings?.summaryOff ?? false;
      
      // Use simplified prompt format like main.dart to avoid 500 errors
      final summaryInstruction = summaryOff
          ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
          : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      
      final promptForLLM =
          'Provide up to "${llmOptions}" short, single-phrase options related to: "${question}".\n'
          'Do not include any introductory or concluding text.\n'
          'Format your response as a JSON list where each item has "option" and "summary" keys.\n'
          'The "option" key should contain the FULL option text. If the option contains a question and answer, like a joke, the option contain the question and the answer.\n'
          '${summaryInstruction}\n'
          'Example: [{"option": "...", "summary": "..."}]';
      
      debugPrint('🤖🤖🤖 THREADS LLM REQUEST STARTED 🤖🤖🤖');
      debugPrint('🤖 ThreadsPage Question: $question');
      
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode({'prompt': promptForLLM}),
        timeoutSeconds: 30,
      );
      
      debugPrint('🤖 ThreadsPage LLM Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        debugPrint('ThreadsPage: Successfully received LLM response');
        final List<dynamic> data = json.decode(response.body);
        List<Map<String, dynamic>> threadOptions = data.map((item) => {
          'text': item['summary'] ?? item['option'] ?? '',
          'summary': item['summary'] ?? '',
          'option': item['option'] ?? '',
          'speechPhrase': item['option'] ?? '',
          'isThreadOption': true,
        }).toList();
        
        // Add thread-specific control buttons like main.dart adds standard buttons
        debugPrint('ThreadsPage: Adding Free Style and Ask Again buttons for thread responses');
        
        // Add "Free Style" button
        threadOptions.add({
          'text': 'Free Style',
          'speechPhrase': 'Free Style',
          'isThreadOption': true,
          'threadSpecial': 'freeStyle',
        });
        
        // Add "Please ask me again" button
        threadOptions.add({
          'text': 'Please ask me again',
          'speechPhrase': 'Please ask me again',
          'isThreadOption': true,
          'threadSpecial': 'askAgain',
        });
        
        // Add standard thread control buttons
        _addStandardThreadButtons(threadOptions);
        
        // NOTE: Question is already added to thread in onQuestion callback, don't duplicate it here
        
        _stopAuditoryScanning();
        setState(() {
          _currentOptions = threadOptions;
          _isLoading = false;
          _statusMessage = null;
        });
        
        // Wait for any announcements to complete before starting scanning
        await _waitForAnnouncementComplete();
        
        // Setup Bluetooth audio routing before presenting options (moved from beginning to avoid LLM delay)
        debugPrint('ThreadsPage _getLLMResponseForThreads: Setting up Bluetooth audio routing for response options...');
        if (!kIsWeb && Platform.isIOS) {
          try {
            const platform = MethodChannel('audio_routing');
            debugPrint('ThreadsPage _getLLMResponseForThreads: Switching to default audio routing (Bluetooth)...');
            await platform.invokeMethod('resetToDefault');
            await Future.delayed(Duration(milliseconds: 100)); // Brief settle time
            
            debugPrint('ThreadsPage _getLLMResponseForThreads: Playing silence.mp3 to prime Bluetooth audio path...');
            final player = AudioPlayer();
            await player.setAsset('assets/silence.mp3');
            
            // Wait for silence to complete to ensure Bluetooth audio path is ready
            final completer = Completer<void>();
            final sub = player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                debugPrint('ThreadsPage _getLLMResponseForThreads: Silence playback completed - Bluetooth audio path primed');
                completer.complete();
              }
            });
            
            await player.play();
            await completer.future;
            await sub.cancel();
            await player.dispose();
            
            debugPrint('ThreadsPage _getLLMResponseForThreads: Bluetooth audio priming completed successfully');
          } catch (e) {
            debugPrint('ThreadsPage _getLLMResponseForThreads: Error with audio routing/priming: $e');
          }
        }
        
        // Auto-resume scanning logic matching main.dart
        if (wasInPausedState) {
          debugPrint('ThreadsPage _getLLMResponseForThreads: Auto-resuming scanning because we were paused before LLM');
          _currentScanCycle = 0;
          _suppressScanning = false;
          _waitingForUserInput = false;
          _isScanningPaused = false;
          
          _maybeStartScanning();
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Future.delayed(const Duration(milliseconds: 500));
            await _speakSystemVoice("New options available. Scanning resumed.");
          });
        } else {
          debugPrint('ThreadsPage _getLLMResponseForThreads: Starting normal scanning after LLM');
          _maybeStartScanning();
        }
        
        // SHARED SERVICE: Let the service handle its own auto-restart after LLM processing
        // Only restart if there was a specific error or timeout
        debugPrint('[ThreadsPage LLM] LLM processing complete - shared service will auto-restart as needed');
        
      } else {
        debugPrint('ThreadsPage: LLM request failed with status ${response.statusCode}');
        debugPrint('ThreadsPage: LLM error response: ${response.body}');
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error: ${response.body}';
        });
        // SHARED SERVICE: Only restart on actual HTTP errors, not normal operations
        debugPrint('[ThreadsPage LLM] HTTP error occurred - shared service will handle auto-restart');
      }
    } catch (e) {
      debugPrint('ThreadsPage: LLM request exception: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: $e';
      });
      // SHARED SERVICE: Only restart on exceptions that might affect the service
      debugPrint('[ThreadsPage LLM] Exception occurred - shared service will handle auto-restart: $e');
    }
  }

  // --- Wait for Announcement Complete (matching main.dart) ---
  Future<void> _waitForAnnouncementComplete() async {
    while (_isAnnouncementPlaying) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // --- Audio Session Initialization ---
  Future<void> _initializeAudioSession() async {
    if (_audioSessionInitialized) return;
    
    try {
      if (!kIsWeb && Platform.isIOS) {
        final platform = MethodChannel('audio_routing');
        await platform.invokeMethod('initializeAudioSession');
        debugPrint('ThreadsPage: iOS audio session initialized');
      } else if (!kIsWeb && Platform.isAndroid) {
        // Android doesn't need initializeAudioSession, routing handled per-call
        debugPrint('ThreadsPage: Android audio session - no initialization needed');
      }
      _audioSessionInitialized = true;
      debugPrint('Audio session initialized for threads page');
    } catch (e) {
      debugPrint('Audio session initialization failed: $e');
    }
  }

  // --- Check Favorite Location and Open Thread ---
  Future<void> _checkFavoriteLocationAndOpenThread() async {
    print('🟡 ThreadsPage: _checkFavoriteLocationAndOpenThread started');
    
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Checking favorite location...';
      });
      print('🟡 ThreadsPage: State updated to loading');

      print('🟡 ThreadsPage: Making HTTP request to get-user-current');
      print('🟡 ThreadsPage: URL: ${EnvironmentConfig.apiBaseUrl}/get-user-current');
      print('🟡 ThreadsPage: Headers - Authorization: Bearer ${widget.idToken.substring(0, 20)}...');
      print('🟡 ThreadsPage: Headers - X-User-ID: ${widget.aacUserId}');
      
      // Check if favorite location was loaded within 4 hours
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/get-user-current'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );

      print('🟡 ThreadsPage: HTTP request completed');
      print('🟡 ThreadsPage: Response status: ${response.statusCode}');
      print('🟡 ThreadsPage: Response body: ${response.body}');
      print('🟡 ThreadsPage: Response headers: ${response.headers}');

      if (response.statusCode == 200) {
        print('🟢 ThreadsPage: Successful response, parsing JSON');
        final data = json.decode(response.body);
        final loadedAt = data['loaded_at'];
        final favoriteName = data['favorite_name'];
        
        print('🟢 ThreadsPage: Parsed data - loadedAt: $loadedAt, favoriteName: $favoriteName');
        
        if (loadedAt != null && favoriteName != null) {
          final loadedTime = DateTime.parse(loadedAt);
          final now = DateTime.now();
          final difference = now.difference(loadedTime);
          
          print('🟢 ThreadsPage: Time check - difference: ${difference.inHours} hours');
          
          if (difference.inHours < 4) {
            // Favorite location is recent, open the thread
            print('🟢 ThreadsPage: Favorite location is recent, opening thread with name: $favoriteName');
            await _openThread(favoriteName);
            return;
          } else {
            print('🟠 ThreadsPage: Favorite location is too old (${difference.inHours} hours)');
          }
        } else {
          print('🟠 ThreadsPage: Missing loadedAt or favoriteName in response');
        }
        
        // No recent favorite location
        print('🟠 ThreadsPage: No recent favorite location found, announcing and returning');
        try {
          // Use a timeout to prevent hanging on announcement
          await _announceViaBackend('A favorite location has not been loaded recently. Returning to grid page.')
            .timeout(const Duration(seconds: 10));
        } catch (e) {
          print('🔴 ThreadsPage: Announcement timeout or error: $e');
        }
        
        await Future.delayed(const Duration(seconds: 1)); // Reduced delay
        if (mounted) {
          print('🟠 ThreadsPage: Navigating back to GridPage');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => GridPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: 'User', // Use placeholder since ThreadsPage doesn't store displayName
              ),
            ),
            (route) => false,
          );
        }
      } else {
        print('🔴 ThreadsPage: HTTP error response');
        throw Exception('Failed to check favorite location: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      print('🔴 ThreadsPage: CRITICAL ERROR in _checkFavoriteLocationAndOpenThread');
      print('🔴 ThreadsPage: Error: $e');
      print('🔴 ThreadsPage: Error type: ${e.runtimeType}');
      print('🔴 ThreadsPage: Stack trace: $stackTrace');
      
      try {
        setState(() {
          _statusMessage = 'Error opening thread: $e';
          _isLoading = false;
        });
      } catch (setStateError) {
        print('🔴 ThreadsPage: Additional error in setState: $setStateError');
      }
      
      try {
        print('🔴 ThreadsPage: Attempting to announce error');
        try {
          await _announceViaBackend('Error opening thread: ${e.toString()}. Returning to grid page.')
            .timeout(const Duration(seconds: 10));
        } catch (announceError) {
          print('🔴 ThreadsPage: Error announcement timeout or failed: $announceError');
        }
        await Future.delayed(const Duration(seconds: 1)); // Reduced delay
        if (mounted) {
          print('🔴 ThreadsPage: Navigating back to GridPage after error');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => GridPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: 'User',
              ),
            ),
            (route) => false,
          );
        }
      } catch (announceError) {
        print('🔴 ThreadsPage: Error in error announcement: $announceError');
        if (mounted) {
          print('🔴 ThreadsPage: Emergency navigation pop');
          Navigator.of(context).pop();
        }
      }
    } finally {
      print('🟡 ThreadsPage: Finally block - cleaning up');
      if (mounted) {
        try {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
          print('🟡 ThreadsPage: Final state cleanup completed');
        } catch (finalError) {
          print('🔴 ThreadsPage: Error in final state cleanup: $finalError');
        }
      } else {
        print('🟠 ThreadsPage: Widget not mounted during cleanup');
      }
    }
  }

  // --- Open Thread ---
  Future<void> _openThread(String favoriteName) async {
    print('🟡 ThreadsPage: _openThread called with favoriteName: $favoriteName');
    
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Opening thread for $favoriteName...';
      });
      print('🟡 ThreadsPage: State updated to loading for thread opening');

      print('🟡 ThreadsPage: Making HTTP request to /api/threads/open');
      print('🟡 ThreadsPage: URL: ${EnvironmentConfig.apiBaseUrl}/api/threads/open');
      print('🟡 ThreadsPage: Request body: {"favorite_name": "$favoriteName"}');
      
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/threads/open'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'favorite_name': favoriteName}),
      );

      print('🟡 ThreadsPage: HTTP request completed for thread open');
      print('🟡 ThreadsPage: Response status: ${response.statusCode}');
      print('🟡 ThreadsPage: Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('🟢 ThreadsPage: Successful thread open response, parsing JSON');
        final result = json.decode(response.body);
        
        print('🟢 ThreadsPage: Parsed thread result: $result');
        
        if (result['success'] == true) {
          print('🟢 ThreadsPage: Thread operation successful, updating state');
          setState(() {
            _currentThread = result['thread'];
            _threadMessages = List<Map<String, dynamic>>.from(result['recent_messages'] ?? []);
          });
          
          // Load ALL messages for the thread using the dedicated endpoint
          await _loadAllThreadMessages();
          
          // Auto-scroll to bottom to show latest messages - multiple attempts for reliability
          _scrollToBottom();
          
          // Add a delayed scroll to ensure the UI is fully built
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _scrollToBottom();
            }
          });
          
          // Also scroll after the next frame is built
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scrollToBottom();
            }
          });

          if (result['is_new'] == true) {
            print('🟢 ThreadsPage: New thread created, generating initial options');
            // REMOVED: await _announceViaBackend('New thread started for $favoriteName. What would you like to talk about?');
            
            await _generateInitialThreadOptions();
          } else {
            print('🟢 ThreadsPage: Existing thread opened, generating options from history');
            // Generate options first, then announce based on success
            try {
              await _generateThreadOptionsFromHistory();
              // REMOVED: await _announceViaBackend('Thread opened for $favoriteName. Here are some conversation options.');
            } catch (e) {
              print('🔴 ThreadsPage: Failed to generate options: $e');
              // REMOVED: await _announceViaBackend('Thread opened for $favoriteName, but I\'m having trouble generating options. Please try again.');
            }
          }
        } else {
          print('🔴 ThreadsPage: Thread operation failed - success was false');
          throw Exception(result['error'] ?? 'Failed to open thread - success was false');
        }
      } else {
        print('🔴 ThreadsPage: HTTP error response for thread open');
        throw Exception('Failed to open thread: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      print('🔴 ThreadsPage: CRITICAL ERROR in _openThread');
      print('🔴 ThreadsPage: Error: $e');
      print('🔴 ThreadsPage: Error type: ${e.runtimeType}');
      print('🔴 ThreadsPage: Stack trace: $stackTrace');
      
      try {
        setState(() {
          _statusMessage = 'Error opening thread: $e';
        });
      } catch (setStateError) {
        print('🔴 ThreadsPage: Additional error in setState during thread error: $setStateError');
      }
      
      try {
        print('🔴 ThreadsPage: Attempting to announce thread error');
        await _announceViaBackend('Error opening thread: ${e.toString()}. Returning to grid page.');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          print('🔴 ThreadsPage: Navigating back to GridPage after thread error');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => GridPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: 'User',
              ),
            ),
            (route) => false,
          );
        }
      } catch (announceError) {
        print('🔴 ThreadsPage: Error in thread error announcement: $announceError');
        if (mounted) {
          print('🔴 ThreadsPage: Emergency navigation back to GridPage from thread error');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => GridPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: 'User',
              ),
            ),
            (route) => false,
          );
        }
      }
    } finally {
      print('🟡 ThreadsPage: Finally block for thread opening');
      if (mounted) {
        try {
          setState(() {
            _isLoading = false;
          });
          print('🟡 ThreadsPage: Thread opening cleanup completed');
        } catch (finalError) {
          print('🔴 ThreadsPage: Error in thread opening final cleanup: $finalError');
        }
      } else {
        print('🟠 ThreadsPage: Widget not mounted during thread opening cleanup');
      }
    }
  }

  // --- Generate Initial Thread Options ---
  Future<void> _generateInitialThreadOptions() async {
    debugPrint('ThreadsPage: _generateInitialThreadOptions called');
    
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('ThreadsPage: Getting UserSettingsProvider');
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;
      final llmOptions = userSettings?.llmOptions ?? 10;
      final summaryOff = userSettings?.summaryOff ?? false;
      
      debugPrint('ThreadsPage: LLM options count: $llmOptions');
      
      // Build context for LLM using thread information - matching web app logic
      String contextPrompt;
      if (_threadMessages.isEmpty) {
        // New thread - use the web app logic from threads.js lines 149-151
        contextPrompt = 'The user is starting a new communication thread at ${_currentThread?['location'] ?? 'current location'} with ${_currentThread?['people'] ?? 'people present'} during ${_currentThread?['activity'] ?? 'current activity'}. Generate $llmOptions conversation starter options that would be appropriate for this setting.';
      } else {
        // Existing thread with history - use web app logic from threads.js lines 152-160
        final recentHistory = _threadMessages.take(10).map((msg) => 
          '${msg['sender_type'] == 'user' ? 'User' : 'Others'}: ${msg['content']}'
        ).join('\n');
        
        contextPrompt = 'The user is in an ongoing conversation thread at ${_currentThread?['location'] ?? 'current location'} with ${_currentThread?['people'] ?? 'people present'} during ${_currentThread?['activity'] ?? 'current activity'}. Here\'s the recent conversation history:\n\n$recentHistory\n\nGenerate $llmOptions response options that would be appropriate to continue or restart this conversation.';
      }
      
      // Add summary instruction matching web app logic from threads.js lines 162-165
      final summaryInstruction = summaryOff
          ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
          : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      
      final prompt = '$contextPrompt\n\nReturn ONLY a JSON list where each item has "option" and "summary" keys.\n$summaryInstruction\nThe "option" key should contain the FULL option text.\nExample: [{"option": "...", "summary": "..."}]';

      debugPrint('ThreadsPage: Making LLM request with context-aware prompt: $prompt');

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode({'prompt': prompt}),
        timeoutSeconds: 30,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<Map<String, dynamic>> options = data.map((item) => {
          'text': item['summary'] ?? item['option'] ?? '',
          'speechPhrase': item['option'] ?? '',
          'isThreadOption': true,
        }).toList();

        // Add standard thread control buttons
        _addStandardThreadButtons(options);
        
        setState(() {
          _currentOptions = options;
          // Reset paused state when new options are available for scanning (initial thread options)
          _waitingForUserInput = false;
          _isScanningPaused = false;
          // Ensure microphone icon shows green (wake word listening) after LLM options are generated
          _microphoneListening = false;
        });
        
        _maybeStartScanning();
      } else {
        throw Exception('Failed to generate options: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating initial options: $e');
      setState(() {
        _statusMessage = 'Error generating options: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Generate Thread Options from History ---
  Future<void> _generateThreadOptionsFromHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;
      final llmOptions = userSettings?.llmOptions ?? 10;
      final summaryOff = userSettings?.summaryOff ?? false;
      
      // Build context from recent messages with thread information
      String historyContext = '';
      if (_threadMessages.isNotEmpty) {
        final recentMessages = _threadMessages.take(10).toList();
        historyContext = recentMessages.map((msg) => 
          '${msg['sender_type'] == 'user' ? 'User' : 'Others'}: ${msg['content']}'
        ).join('\n');
      }
      
      // Include thread context similar to web app logic
      final contextPrompt = 'The user is in an ongoing conversation thread at ${_currentThread?['location'] ?? 'current location'} with ${_currentThread?['people'] ?? 'people present'} during ${_currentThread?['activity'] ?? 'current activity'}.\n\n'
          'Recent conversation history:\n$historyContext\n\n'
          'Generate $llmOptions response options that would be appropriate to continue or restart this conversation. Focus on creating engaging options that encourage continued communication and social interaction.';
      
      // Add summary instruction matching web app logic
      final summaryInstruction = summaryOff
          ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
          : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      
      final prompt = '$contextPrompt\n\nReturn ONLY a JSON list where each item has "option" and "summary" keys.\n$summaryInstruction\nThe "option" key should contain the FULL option text.\nExample: [{"option": "...", "summary": "..."}]';

      debugPrint('ThreadsPage: Sending LLM request for thread options');
      debugPrint('ThreadsPage: Thread context - Location: ${_currentThread?['location']}, People: ${_currentThread?['people']}, Activity: ${_currentThread?['activity']}');
      debugPrint('ThreadsPage: History context length: ${historyContext.length} characters');
      debugPrint('ThreadsPage: Full prompt length: ${prompt.length} characters');

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode({'prompt': prompt}),
        timeoutSeconds: 30,
      );

      debugPrint('ThreadsPage: LLM response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('ThreadsPage: LLM error response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        debugPrint('ThreadsPage: Successfully parsed LLM response, got ${data.length} options');
        
        List<Map<String, dynamic>> options = data.map((item) => {
          'text': item['summary'] ?? item['option'] ?? '',
          'speechPhrase': item['option'] ?? '',
          'isThreadOption': true,
        }).toList();

        debugPrint('ThreadsPage: Mapped options to internal format: ${options.map((o) => o['text']).toList()}');

        // Add standard thread control buttons
        _addStandardThreadButtons(options);
        
        debugPrint('ThreadsPage: After adding standard buttons, total options: ${options.length}');
        
        setState(() {
          _currentOptions = options;
          // Reset paused state when new options are available for scanning
          _waitingForUserInput = false;
          _isScanningPaused = false;
          // Ensure microphone icon shows green (wake word listening) after LLM options are generated
          _microphoneListening = false;
        });
        
        debugPrint('ThreadsPage: Set _currentOptions in state, calling _maybeStartScanning()');
        _maybeStartScanning();
      } else {
        debugPrint('ThreadsPage: Backend error generating options - Status: ${response.statusCode}');
        debugPrint('ThreadsPage: Backend error response: ${response.body}');
        String errorMessage = 'Backend returned status ${response.statusCode}';
        
        // Try to parse backend error message
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            errorMessage = errorData['error'];
          }
        } catch (e) {
          debugPrint('ThreadsPage: Could not parse error response as JSON');
        }
        
        throw Exception('Failed to generate options: $errorMessage');
      }
    } catch (e) {
      debugPrint('Error generating options from history: $e');
      setState(() {
        _statusMessage = 'Error generating options: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Generate New Topic Options (Enhanced Context) ---
  Future<void> _generateNewTopicOptions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;
      final llmOptions = userSettings?.llmOptions ?? 10;
      final summaryOff = userSettings?.summaryOff ?? false;
      
      // Build context from current thread and recent history - matching web app logic
      String contextInfo = '';
      if (_currentThread != null) {
        contextInfo = 'The user is currently in a conversation thread at "${_currentThread!['location']}" with "${_currentThread!['people']}" during "${_currentThread!['activity']}".';
        
        // Add recent conversation history for context
        if (_threadMessages.isNotEmpty) {
          final recentHistory = _threadMessages.take(5).map((msg) => 
            '${msg['sender_type'] == 'user' ? 'User' : 'Others'}: ${msg['content']}'
          ).join('\n');
          contextInfo += '\n\nRecent conversation history:\n$recentHistory\n\n';
        }
      }
      
      // Create a prompt for new topic suggestions with context - matching web app logic
      final basePrompt = '${contextInfo}The user wants to start a new conversation topic that would be relevant and engaging for this specific social setting. Generate $llmOptions conversation starter options that:\n\n'
          '- Are appropriate for the current location "${_currentThread?['location'] ?? 'current setting'}" and activity "${_currentThread?['activity'] ?? 'current activity'}"\n'
          '- Would work well when talking with "${_currentThread?['people'] ?? 'the people present'}"\n'
          '- Take into account the recent conversation flow and build naturally from it\n'
          '- Encourage sharing and deeper discussion\n'
          '- Include options that could lead to learning more about the people present\n'
          '- Suggest topics that are contextually relevant to the setting and activity\n'
          '- Provide ways to share relevant personal experiences that others can relate to\n'
          '- Offer conversation starters that could reveal common interests or experiences\n\n'
          'Focus on creating options that feel natural for this specific social context and encourage authentic connection and engagement between everyone present.';
      
      // Add summary instruction matching web app logic
      final summaryInstruction = summaryOff
          ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
          : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      
      final prompt = '$basePrompt\n\nReturn ONLY a JSON list where each item has "option" and "summary" keys.\n$summaryInstruction\nThe "option" key should contain the FULL option text.\nExample: [{"option": "...", "summary": "..."}]';

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/llm',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode({'prompt': prompt}),
        timeoutSeconds: 30,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<Map<String, dynamic>> options = data.map((item) => {
          'text': item['summary'] ?? item['option'] ?? '',
          'speechPhrase': item['option'] ?? '',
          'isThreadOption': true,
        }).toList();

        // Add standard thread control buttons
        _addStandardThreadButtons(options);
        
        setState(() {
          _currentOptions = options;
          // Reset paused state when new options are available for scanning (new topic options)
          _waitingForUserInput = false;
          _isScanningPaused = false;
          // Ensure microphone icon shows green (wake word listening) after LLM options are generated
          _microphoneListening = false;
        });
        
        _maybeStartScanning();
        await _announceViaBackend('Here are some new topic ideas to explore.');
      } else {
        throw Exception('Failed to generate new topic options: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating new topic options: $e');
      setState(() {
        _statusMessage = 'Error generating new topic options: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Add Standard Thread Buttons ---
  void _addStandardThreadButtons(List<Map<String, dynamic>> options) {
    options.addAll([
      {
        'text': 'Something Else',
        'speechPhrase': 'Something Else',
        'isThreadControl': true,
        'action': 'something_else',
      },
      {
        'text': 'Please Repeat',
        'speechPhrase': 'Please Repeat',
        'isThreadControl': true,
        'action': 'repeat',
      },
      {
        'text': 'New Topic',
        'speechPhrase': 'New Topic',
        'isThreadControl': true,
        'action': 'new_topic',
      },
      {
        'text': 'Exit Thread',
        'speechPhrase': 'Exit Thread',
        'isThreadControl': true,
        'action': 'exit',
      },
    ]);
  }

  // --- Handle Button Action ---
  Future<void> _handleButtonAction(Map<String, dynamic> buttonData) async {
    // Update activity time to show the app is responsive
    _lastActivityTime = DateTime.now();
    
    // Always stop scanning when any button is pressed
    _stopAuditoryScanning();
    
    if (buttonData['isThreadControl'] == true) {
      final action = buttonData['action'];
      
      // Handle "repeat" case separately since it doesn't resume scanning
      if (action == 'repeat') {
        // Stop auditory scanning and ask for repetition
        _stopAuditoryScanning();
        print('🟢 ThreadsPage - Please Repeat button: Asking for repetition');
        
        // Set listening state immediately
        setState(() {
          _highlightQuestionBox = true;
          _isListeningForQuestion = true;
          // Don't set _microphoneListening = true yet - wait until after announcement
        });
        print('🟢 ThreadsPage - Please Repeat button: Set listening state - _highlightQuestionBox: $_highlightQuestionBox, _isListeningForQuestion: $_isListeningForQuestion');
        
        // Start the announcement and wait for it to complete
        debugPrint('[TIMER] ThreadsPage: Before repeat announcement at ${DateTime.now().millisecondsSinceEpoch}');
        await _announceViaBackend('Sorry. Can you please repeat what you just said?');
        debugPrint('[TIMER] ThreadsPage: After repeat announcement at ${DateTime.now().millisecondsSinceEpoch}');
        
        // NOW set the microphone to red since we're actually about to start question listening
        setState(() {
          _microphoneListening = true; // Show red microphone icon with spinner
        });
        
        // Brief delay to ensure audio routing has switched back to microphone
        debugPrint('[TIMER] ThreadsPage: Before repeat delay at ${DateTime.now().millisecondsSinceEpoch}');
        await Future.delayed(const Duration(milliseconds: 200));
        debugPrint('[TIMER] ThreadsPage: After repeat delay at ${DateTime.now().millisecondsSinceEpoch}');
        
        // Start question listening after announcement completes
        print('🟢 ThreadsPage - Please Repeat button: Starting question listening for repeat');
        try {
          debugPrint('[TIMER] ThreadsPage: Before startQuestionListeningForRepeat at ${DateTime.now().millisecondsSinceEpoch}');
          await WakeWordService.startQuestionListeningForRepeat();
          debugPrint('[TIMER] ThreadsPage: After startQuestionListeningForRepeat at ${DateTime.now().millisecondsSinceEpoch}');
          print('🟢 ThreadsPage - Please Repeat button: Question listening started successfully');
        } catch (e) {
          print('🔴 ThreadsPage - Please Repeat button: Error starting question listening: $e');
          // Don't restart wake word service to avoid session conflicts
          print('🔴 ThreadsPage - Skipping wake word service restart to avoid session conflicts');
        }
        return; // Exit early, don't resume scanning
      }
      
      // Resume scanning since a control button was clicked (except repeat)
      _resumeScanningAfterUserAction();
      
      switch (action) {
        case 'something_else':
          await _generateInitialThreadOptions();
          break;
        case 'new_topic':
          await _generateNewTopicOptions();
          break;
        case 'exit':
          // Don't wait for announcement - navigate immediately to prevent freezing
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => GridPage(
                  idToken: widget.idToken,
                  aacUserId: widget.aacUserId,
                  displayName: 'User',
                ),
              ),
              (route) => false,
            );
          }
          return;
      }
    } else if (buttonData['isThreadOption'] == true) {
      // Handle thread conversation option
      final speechPhrase = buttonData['speechPhrase'];
      final threadSpecial = buttonData['threadSpecial'];
      
      if (threadSpecial != null) {
        // Handle special thread actions (matching main.dart pattern)
        _resumeScanningAfterUserAction();
        
        switch (threadSpecial) {
          case 'freeStyle':
            // Navigate to main page for free style input immediately to prevent freezing
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => GridPage(
                    idToken: widget.idToken,
                    aacUserId: widget.aacUserId,
                    displayName: 'User',
                  ),
                ),
                (route) => false,
              );
            }
            return;
          case 'askAgain':
            // Set listening state and restart question listening
            setState(() {
              _highlightQuestionBox = true;
              _isListeningForQuestion = true;
              // Don't set _microphoneListening = true yet - wait until after announcement
            });
            
            await _announceViaBackend('Please ask me again.');
            await Future.delayed(const Duration(milliseconds: 200));
            
            // NOW set the microphone to red since we're actually about to start question listening
            setState(() {
              _microphoneListening = true; // Show red microphone icon with spinner
            });
            
            try {
              await WakeWordService.startQuestionListeningForRepeat();
            } catch (e) {
              debugPrint('Error starting question listening: $e');
              // The shared service will handle recovery automatically
            }
            return;
        }
      } else if (speechPhrase != null) {
        // Handle normal thread conversation option
        // Stop scanning immediately when user makes a selection
        _stopAuditoryScanning();
        
        // Set waiting for user input BEFORE any announcements to prevent scanning restart
        setState(() {
          _waitingForUserInput = true;
          _isScanningPaused = true;
        });
        
        // Add message to thread first
        await _addMessageToThread(speechPhrase, 'user', userSelection: speechPhrase);
        
        // Announce the FULL option text via backend (built-in speaker)
        await _announceWithTimeout(speechPhrase, routing: 'system');
        
        // Clear LLM options and show only essential control buttons
        await _clearLLMOptionsAndShowControlButtons();
        
        // Announce scanning is paused via personal device (same as button scanning)
        await _speakSystemVoice('Scanning paused. Use your switch to resume scanning.');
        
        // CRITICAL: Start wake word listening after user selection for voice input
        print('🟢 ThreadsPage - Starting wake word listening for paused state voice input');
        try {
          // Simply ensure the shared service is listening (no restart needed)
          final service = WakeWordService.getCurrentInstance();
          await service?.startWakeWordListening();
          print('🟢 ThreadsPage - Wake word listening started successfully in paused state');
        } catch (e) {
          print('🔴 ThreadsPage - Error starting wake word listening in paused state: $e');
        }
        
        // Don't restart scanning automatically - user must manually resume
        return;
      }
    }
    
    // Only restart scanning for control button actions, not thread options
    if (buttonData['isThreadControl'] == true) {
      _resumeScanningAfterUserAction();
    }
  }

  // --- Add Message to Thread ---
  Future<void> _addMessageToThread(String content, String senderType, {String? userSelection}) async {
    print('🟢 ThreadsPage - _addMessageToThread called with: "$content", sender: $senderType, userSelection: $userSelection');
    
    if (_currentThread == null) {
      print('🔴 ThreadsPage - Cannot add message: _currentThread is null');
      return;
    }
    
    print('🟢 ThreadsPage - Current thread ID: ${_currentThread!['thread_id'] ?? _currentThread!['id']}');
    
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/threads/${_currentThread!['thread_id'] ?? _currentThread!['id']}/messages'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'thread_id': _currentThread!['thread_id'] ?? _currentThread!['id'],
          'content': content,
          'sender_type': senderType,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      print('🟢 ThreadsPage - Message API response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('🟢 ThreadsPage - Message API response: $result');
        
        if (result['success'] == true) {
          print('🟢 ThreadsPage - Message API success: true, adding to local thread');
          setState(() {
            final messageData = {
              'content': content,
              'sender_type': senderType,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'created_at': DateTime.now().toUtc().toIso8601String(),
            };
            
            // Add user selection if provided
            if (userSelection != null) {
              messageData['user_selection'] = userSelection;
            }
            
            _threadMessages.add(messageData);
            
            // Auto-scroll to bottom to show latest message
            _scrollToBottom();
          });
          print('🟢 ThreadsPage - Message added to thread successfully. Total messages: ${_threadMessages.length}');
        } else {
          print('🔴 ThreadsPage - Message API success: false');
        }
      } else {
        print('🔴 ThreadsPage - Message API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('🔴 ThreadsPage - Error adding message to thread: $e');
      debugPrint('Error adding message to thread: $e');
    }
  }

  /// Timeout wrapper for _announceViaBackend to prevent app freezing
  Future<void> _announceWithTimeout(
    String text, {
    String routing = 'system',
    int? speechRate,
    Duration timeout = const Duration(seconds: 15), // Match main.dart timeout
  }) async {
    try {
      debugPrint('ThreadsPage _announceWithTimeout: Starting announcement with ${timeout.inSeconds}s timeout: "$text"');
      
      await _announceViaBackend(text, routing: routing, speechRate: speechRate).timeout(
        timeout,
        onTimeout: () {
          debugPrint('🚨 THREADS PAGE TIMEOUT: _announceViaBackend timed out after ${timeout.inSeconds} seconds for: "$text"');
          debugPrint('🚨 TIMEOUT RECOVERY: Attempting graceful recovery in ThreadsPage');
          
          // Clear any announcement flags or states
          _isAnnouncementPlaying = false;
          
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
          
          throw TimeoutException('ThreadsPage announcement timed out after ${timeout.inSeconds} seconds', timeout);
        },
      );
      
      debugPrint('ThreadsPage _announceWithTimeout: Announcement completed successfully within timeout');
      
    } catch (e) {
      if (e is TimeoutException) {
        debugPrint('🚨 ThreadsPage _announceWithTimeout: Announcement timed out - showing user notification');
        
        // Show user-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Thread communication timed out. The app is still working normally.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        debugPrint('🚨 ThreadsPage _announceWithTimeout: Error during announcement: $e');
        rethrow; // Re-throw non-timeout exceptions
      }
    }
  }

  // --- Announce using backend TTS (selected voice, built-in speaker routing) ---
  Future<void> _announceViaBackend(String text, {String routing = 'system', int? speechRate, bool preserveMicrophoneSession = false}) async {
    print('🟢 ThreadsPage - Announcement: $text');
    
    // Stop scanning during announcement
    bool wasScanning = _isScanning;
    if (wasScanning) {
      _stopAuditoryScanning();
    }
    
    String idToken = widget.idToken;
    final aacUserId = widget.aacUserId;
    
    try {
      // Set announcement playing flag to suppress other audio
      _isAnnouncementPlaying = true;
      
      // Initialize audio session on first use
      if (!_audioSessionInitialized) {
        await _initializeAudioSession();
        _audioSessionInitialized = true;
      }

      // Always refresh the token before backend call
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          String? refreshedToken;
          try {
            refreshedToken = await user
                .getIdToken(true)
                .timeout(const Duration(seconds: 6));
          } catch (_) {
            refreshedToken = await user
                .getIdToken()
                .timeout(const Duration(seconds: 4));
          }
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            idToken = refreshedToken;
          }
        }
      } catch (e) {
        debugPrint('ThreadsPage: Token refresh failed: $e, using original token');
      }
      
      bool backendAudioPlayed = false;
      final Map<String, dynamic> requestBody = {
        'text': text, 
        'routing_target': routing,
      };
      
      // Add speechRate if provided (matches main.dart pattern)
      if (speechRate != null) {
        requestBody['speech_rate'] = speechRate;
      }
      
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/play-audio'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final base64Audio = RegExp('"audio_data"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audioContent"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        
        if (base64Audio != null && base64Audio.isNotEmpty) {
          final platform = MethodChannel('audio_routing');
          final player = AudioPlayer();
          
          try {
            // Force built-in speaker for system announcements - use same logic as main.dart
            await _flutterTts.stop();
            await player.stop();
            
            if (!kIsWeb && Platform.isIOS) {
              // ROBUST AUDIO ROUTING: Ensure consistent speaker routing
              debugPrint('ThreadsPage iOS: Setting speaker routing for announcement');
              try {
                await platform.invokeMethod('forceSpeaker');
                debugPrint('ThreadsPage iOS: forceSpeaker completed successfully');
              } catch (e) {
                debugPrint('ThreadsPage iOS: forceSpeaker failed: $e');
              }
              
              // Show speech bubble overlay RIGHT BEFORE the stabilization delay
              _showSpeechBubbleOverlay(text);
              
              // Wait for audio routing to fully stabilize to prevent audio cutoff
              debugPrint('ThreadsPage iOS: Waiting for audio routing to stabilize (600ms)...');
              await Future.delayed(const Duration(milliseconds: 600));
              debugPrint('ThreadsPage iOS: Audio routing stabilization complete');
            } else {
              // For non-iOS or web, still show speech bubble
              _showSpeechBubbleOverlay(text);
            }
            
            // Play the actual announcement
            final bytes = base64Decode(base64Audio);
            final tempDir = Directory.systemTemp;
            final tempFile = await File('${tempDir.path}/threads_backend_tts.mp3').create();
            await tempFile.writeAsBytes(bytes, flush: true);
            await player.setFilePath(tempFile.path);
            
            final completer2 = Completer<void>();
            final sub2 = player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                if (!completer2.isCompleted) completer2.complete();
              }
            });
            await player.play();
            await completer2.future;
            await sub2.cancel();
            
            // Reset audio routing after announcement - but only if not preserving microphone session
            await Future.delayed(const Duration(milliseconds: 100));
            if (!preserveMicrophoneSession) {
              await platform.invokeMethod('resetToDefault');
              debugPrint('ThreadsPage: Audio routing reset to default');
            } else {
              debugPrint('ThreadsPage: Preserving microphone session - skipping resetToDefault');
            }
            backendAudioPlayed = true;
          } catch (e) {
            debugPrint('ThreadsPage: Backend audio playback failed: $e');
          } finally {
            player.dispose();
          }
        }
      }
      
      // Fallback to local TTS if backend failed
      if (!backendAudioPlayed) {
        if (routing == 'system' && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
          try {
            const platform = MethodChannel('audio_routing');
            await platform.invokeMethod('forceSpeaker');
          } catch (e) {
            debugPrint('ThreadsPage: forceSpeaker failed for fallback TTS: $e');
          }
        }
        
        await _flutterTts.stop();
        final ttsCompleter = Completer<void>();
        _flutterTts.setCompletionHandler(() {
          debugPrint('ThreadsPage: Fallback TTS completion handler triggered for "$text"');
          if (!ttsCompleter.isCompleted) {
            debugPrint('ThreadsPage: Fallback TTS completion confirmed');
            ttsCompleter.complete();
          }
        });
        debugPrint('ThreadsPage: Starting fallback local TTS: "$text"');
        await _flutterTts.speak(text);

        final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final estimatedDurationMs = (wordCount * 700) + 3000;
        final timeout = Duration(milliseconds: estimatedDurationMs.clamp(5000, 120000));

        debugPrint('ThreadsPage: Waiting for fallback TTS completion (timeout: ${timeout.inMilliseconds}ms)');
        try {
          await ttsCompleter.future.timeout(timeout);
          debugPrint('ThreadsPage: Fallback TTS completed within timeout');
        } on TimeoutException {
          debugPrint('⚠️ ThreadsPage: Fallback TTS timeout after ${timeout.inMilliseconds}ms - forcing completion');
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        }

        debugPrint('ThreadsPage: Clearing fallback TTS completion handler');
        _flutterTts.setCompletionHandler(() {});
        
        if (routing == 'system' && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
          try {
            const platform = MethodChannel('audio_routing');
            await platform.invokeMethod('resetToDefault');
          } catch (e) {
            debugPrint('ThreadsPage: resetToDefault failed for fallback TTS: $e');
          }
        }
      }
      
    } catch (e) {
      print('🔴 ThreadsPage - Announcement error: $e');
      try {
        await _flutterTts.stop();
        await Future.delayed(const Duration(milliseconds: 100));

        final ttsCompleter = Completer<void>();
        _flutterTts.setCompletionHandler(() {
          debugPrint('ThreadsPage: Exception fallback TTS completion handler triggered for "$text"');
          if (!ttsCompleter.isCompleted) {
            debugPrint('ThreadsPage: Exception fallback TTS completion confirmed');
            ttsCompleter.complete();
          }
        });

        debugPrint('ThreadsPage: Starting exception fallback local TTS: "$text"');
        await _flutterTts.speak(text);

        final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final estimatedDurationMs = (wordCount * 700) + 3000;
        final timeout = Duration(milliseconds: estimatedDurationMs.clamp(5000, 120000));

        debugPrint('ThreadsPage: Waiting for exception fallback TTS completion (timeout: ${timeout.inMilliseconds}ms)');
        try {
          await ttsCompleter.future.timeout(timeout);
          debugPrint('ThreadsPage: Exception fallback TTS completed within timeout');
        } on TimeoutException {
          debugPrint('⚠️ ThreadsPage: Exception fallback TTS timeout after ${timeout.inMilliseconds}ms - forcing completion');
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        }

        debugPrint('ThreadsPage: Clearing exception fallback TTS completion handler');
        _flutterTts.setCompletionHandler(() {});
      } catch (fallbackError) {
        debugPrint('ThreadsPage: Exception fallback TTS failed: $fallbackError');
      }
    } finally {
      _isAnnouncementPlaying = false;
      
      // SHARED SERVICE: Don't constantly restart - let service manage itself
      debugPrint('🔄 ThreadsPage - Announcement completed, shared service will auto-restart as needed');
      
      if (mounted) {
        setState(() {
          _microphoneListening = false; // Show green microphone icon
        });
      }
    }
    
    // Resume scanning if it was running before and we're not waiting for user input
    if (wasScanning && !_waitingForUserInput && _currentOptions.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_waitingForUserInput) {
          debugPrint('🔄 ThreadsPage - Resuming scanning after announcement');
          _startAuditoryScanning();
          
          // SHARED SERVICE: Let service handle its own restart timing
          debugPrint('🔄 ThreadsPage - Scanning resumed, shared service active');
        }
      });
    } else {
      // SHARED SERVICE: No additional restart needed
      debugPrint('🔄 ThreadsPage - Announcement complete, no scanning to resume');
    }
  }

  // --- Clear LLM Options and Show Only Essential Control Buttons ---
  Future<void> _clearLLMOptionsAndShowControlButtons() async {
    print('🟢 ThreadsPage - Clearing LLM options and showing only essential control buttons for paused state');
    
    setState(() {
      _currentOptions.clear();
      
      // Add only the three essential control buttons after user selection
      _currentOptions.addAll([
        {
          'text': 'Free Style',
          'speechPhrase': 'Free Style',
          'isThreadOption': true,
          'threadSpecial': 'freeStyle',
        },
        {
          'text': 'New Topic',
          'speechPhrase': 'New Topic',
          'isThreadControl': true,
          'action': 'new_topic',
        },
        {
          'text': 'Exit Thread',
          'speechPhrase': 'Exit Thread',
          'isThreadControl': true,
          'action': 'exit',
        },
      ]);
    });
  }

  // --- Load All Thread Messages ---
  Future<void> _loadAllThreadMessages() async {
    if (_currentThread == null) return;
    
    try {
      final threadId = _currentThread!['thread_id'];
      print('🟡 ThreadsPage: Loading all messages for thread ID: $threadId');
      
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/threads/$threadId/messages'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );

      print('🟡 ThreadsPage: All messages response status: ${response.statusCode}');
      print('🟡 ThreadsPage: All messages response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final allMessages = List<Map<String, dynamic>>.from(result['messages'] ?? []);
        
        print('🟢 ThreadsPage: Loaded ${allMessages.length} total messages');
        
        setState(() {
          _threadMessages = allMessages;
        });
      } else {
        print('🔴 ThreadsPage: Failed to load all messages: ${response.statusCode}');
      }
    } catch (e) {
      print('🔴 ThreadsPage: Error loading all messages: $e');
    }
  }

  // --- Auto-scroll to Bottom ---
  void _scrollToBottom() {
    if (_historyScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_historyScrollController.hasClients) {
          _historyScrollController.animateTo(
            _historyScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // --- Resume Scanning After User Action ---
  void _resumeScanningAfterUserAction() {
    if (_waitingForUserInput) {
      print('🟢 ThreadsPage - Resuming scanning after user action');
      setState(() {
        _waitingForUserInput = false;
      });
      
      // Small delay to ensure UI is updated before starting scan
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_currentOptions.isNotEmpty) {
          _startAuditoryScanning();
        }
      });
    }
  }

  // --- Scanning Methods ---
  void _maybeStartScanning() {
    print('🟢 ThreadsPage _maybeStartScanning: _suppressScanning=$_suppressScanning, _currentOptions.length=${_currentOptions.length}, _waitingForUserInput=$_waitingForUserInput, _isAnnouncementPlaying=$_isAnnouncementPlaying');
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final enableScanning = settingsProvider.settings?.enableAuditoryScanning ?? false;
    final waitForSwitch = settingsProvider.settings?.waitForSwitchToScan ?? false;
    
    if (!enableScanning) {
      print('🔴 ThreadsPage _maybeStartScanning: Scanning disabled');
      _stopAuditoryScanning();
      return;
    }
    
    if (_suppressScanning || _currentOptions.isEmpty || _waitingForUserInput || _isAnnouncementPlaying) {
      print('🔴 ThreadsPage _maybeStartScanning: Scanning blocked');
      if (_isAnnouncementPlaying) {
        print('🔴 ThreadsPage _maybeStartScanning: Announcement in progress, will resume scanning after completion');
        // Don't start a timer - the announcement completion handler will restart scanning
      }
      return;
    }
    
    // Check if we should wait for switch press before starting
    if (waitForSwitch && !_isScanning && _currentOptions.isNotEmpty && !_waitingForInitialSwitch) {
      print('🟡 ThreadsPage _maybeStartScanning: Waiting for switch press to begin scanning...');
      setState(() {
        _waitingForInitialSwitch = true;
        _switchStartRequested = false;
      });
      // Don't play prompt - only mood selection and first grid page should play it
      
      return; // IMPORTANT: Don't start scanning yet, wait for switch press
    }
    
    print('🟢 ThreadsPage _maybeStartScanning: Starting auditory scanning');
    _startAuditoryScanning();
    
    // CRITICAL: Start wake word service when scanning begins so user can interrupt with voice
    print('🔄 ThreadsPage - Scanning started, ensuring wake word service is active');
    final service = WakeWordService.getCurrentInstance();
    if (service != null) {
      service.startWakeWordListening().then((_) {
        print('🔄 ThreadsPage - Wake word service confirmed active for scanning');
        // Ensure microphone icon shows green (wake word listening) 
        if (mounted) {
          setState(() {
            _microphoneListening = false;
          });
        }
      }).catchError((e) {
        print('🔴 ThreadsPage - Error ensuring wake word service for scanning: $e');
        // Don't let wake word errors prevent scanning from working
      });
    }
    
    // Add periodic health check to prevent freezes
    _startHealthCheck();
  }

  void _startAuditoryScanning() {
    // CRITICAL: Don't start scanning if we're waiting for the user to press switch
    if (_waitingForInitialSwitch) {
      print('🔴 ThreadsPage _startAuditoryScanning: Waiting for switch press, blocking scanning');
      return;
    }
    
    _stopAuditoryScanning();
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final userSettings = settingsProvider.settings;
    final waitForSwitch = userSettings?.waitForSwitchToScan ?? false;
    final scanningOff = userSettings?.scanningOff ?? false;

    if (waitForSwitch && !_switchStartRequested) {
      print('🔴 ThreadsPage _startAuditoryScanning: Switch not pressed, blocking scanning');
      return;
    }
    
    if (scanningOff) return;
    
    setState(() {
      _isScanning = true;
      _scanningIndex = -1; // Start at -1 so first _scanNextButton() goes to 0
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _currentScanCycle = 0; // Reset cycle counter when starting
      _switchStartRequested = false;
    });
    
    final scanDelay = userSettings?.scanDelay ?? 3500;
    
    final scanMode = userSettings?.scanMode ?? 'auto';
    debugPrint('ThreadsPage _startAuditoryScanning: Scan mode: $scanMode');
    
    if (scanMode == 'auto') {
      _scanNextButton(); // Auto mode announces first option immediately
      debugPrint('ThreadsPage _startAuditoryScanning: Setting up periodic timer for auto mode...');
      _scanningTimer = Timer.periodic(Duration(milliseconds: scanDelay), (timer) {
        _scanNextButton();
      });
    } else {
      debugPrint('ThreadsPage _startAuditoryScanning: Step mode - waiting for first Tab, timer not started');
    }
  }

  void _scanNextButton() {
    if (!_isScanning || _currentOptions.isEmpty) return;
    
    // Check if we're paused and waiting for user input
    if (_isScanningPaused && _waitingForUserInput) {
      print('🟢 ThreadsPage - _scanNextButton: Scanning is paused, waiting for user input');
      return;
    }
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanLoopLimit = settingsProvider.settings?.scanLoopLimit ?? 3;
    
    bool shouldPause = false;
    
    setState(() {
      _scanningIndex = (_scanningIndex! + 1) % _currentOptions.length;
      
      // Check if we've completed a full cycle (back to index 0)
      if (_scanningIndex == 0) {
        _currentScanCycle++;
        print('🟢 ThreadsPage - _scanNextButton: Completed scan cycle $_currentScanCycle');
        
        // Check if we should pause AFTER completing a cycle (scanLoopLimit > 0 and we've reached the limit)
        if (scanLoopLimit > 0 && _currentScanCycle >= scanLoopLimit) {
          print('🟢 ThreadsPage - _scanNextButton: Reached scan loop limit ($scanLoopLimit), will pause');
          shouldPause = true;
        }
      }
    });
    
    // Handle pause outside of setState
    if (shouldPause) {
      _pauseScanning();
      return;
    }
    
    final currentButton = _currentOptions[_scanningIndex!];
    final buttonText = currentButton['text'] ?? '';
    
    print('🟢 ThreadsPage - _scanNextButton: Speaking button text: $buttonText');
    
    // Only speak if no announcement is currently playing to prevent interruption
    if (!_isAnnouncementPlaying) {
      _speakSystemVoice(buttonText);
    }
  }

  void _stopAuditoryScanning() {
    debugPrint('ThreadsPage stopAuditoryScanning: called, _isScanning=' + _isScanning.toString());
    setState(() {
      _isScanning = false;
      _scanningTimer?.cancel();
      _scanningIndex = null;
      _currentScanCycle = 0; // Reset cycle counter
      _isScanningPaused = false; // Reset pause state
      _waitingForUserInput = false; // Reset waiting state
    });
  }

  Future<int> _getEffectivePersonalVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        'ThreadsPage: Using LOCAL personal volume override: $overrideValue/10',
      );
      return overrideValue;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final settingsValue = settingsProvider.settings?.personalVolume ?? 10;
    debugPrint(
      'ThreadsPage: Using SETTINGS personal volume: $settingsValue/10',
    );
    return settingsValue;
  }

  Future<void> _speakSystemVoice(String text) async {
    debugPrint('ThreadsPage: _speakSystemVoice - Starting TTS for: $text');
    
    // Wait for any ongoing announcements to complete before starting personal voice
    if (_isAnnouncementPlaying) {
      debugPrint('ThreadsPage: _speakSystemVoice - Waiting for ongoing announcement to complete...');
      int waitCount = 0;
      while (_isAnnouncementPlaying && waitCount < 30) { // Max 3 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      debugPrint('ThreadsPage: _speakSystemVoice - Wait completed after ${waitCount * 100}ms');
    }
    
    try {
      // Route audio to personal device (Bluetooth headphones) for scanning - same as grid page
      final audioDeviceProvider = Provider.of<AudioDeviceProvider>(context, listen: false);
      if (!kIsWeb && Platform.isWindows) {
        debugPrint('ThreadsPage: _speakSystemVoice - Routing to personal device: ${audioDeviceProvider.personalDeviceId}');
        await AudioDeviceService().playAudioToDevice(
          audioDeviceProvider.personalDeviceId ?? 'default',
          isPersonal: true,
        );
      } else if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        // CRITICAL FIX: Explicitly reset audio routing to default/headphones for scanning TTS
        try {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
          debugPrint('ThreadsPage: _speakSystemVoice - Audio routing reset to default for scanning');
        } catch (e) {
          debugPrint('ThreadsPage: _speakSystemVoice - Failed to reset audio routing: $e');
        }
      }
      // For iOS/Android, rely on the audio routing restored by announceViaBackend's resetToDefault
      // The system should automatically route to Bluetooth if available after the reset
      
      // For scanning audio, use simple local TTS to personal audio device (Bluetooth)
      // Don't use announceViaBackend for scanning - only for button selections
      await _flutterTts.stop();
      await _flutterTts.setSpeechRate(0.5); // Slower speech for clarity
      
      // Get personalVolume from global settings (scanning uses personal volume, not system)
      final personalVolume = await _getEffectivePersonalVolume();
      final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
      debugPrint('ThreadsPage: Using personalVolume: $personalVolume/10 → TTS volume: $ttsVolume (scanning)');
      await _flutterTts.setVolume(ttsVolume);
      
      await _flutterTts.setPitch(1.0); // Normal pitch
      
      setState(() {
        _isAnnouncingScanningPrompt = true;
      });
      await _flutterTts.speak(text);
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
      debugPrint('ThreadsPage: _speakSystemVoice - Local TTS completed successfully for scanning');
    } catch (e) {
      debugPrint('ThreadsPage: _speakSystemVoice - Local TTS failed: $e');
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
    }
  }

  Future<void> _pauseScanning() async {
    print('🟢 ThreadsPage - _pauseScanning: called');
    setState(() {
      _isScanningPaused = true;
      _waitingForUserInput = true;
      _scanningTimer?.cancel(); // Stop the timer
      // Keep current _scanningIndex - don't change it
    });
    
    // Play "Scanning paused. Use your switch to resume" using the same voice as button scanning
    await _speakSystemVoice("Scanning paused. Use your switch to resume");
  }

  // --- Health Check Methods ---
  void _startHealthCheck() {
    _lastActivityTime = DateTime.now();
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _performHealthCheck();
    });
  }

  void _performHealthCheck() {
    if (!mounted) {
      _healthCheckTimer?.cancel();
      return;
    }

    final now = DateTime.now();
    
    // Update activity time when there's normal activity
    if (_isScanning || _isAnnouncementPlaying || _waitingForUserInput) {
      _lastActivityTime = now;
      return;
    }

    // Check if we've been inactive for too long (30 seconds)
    if (_lastActivityTime != null && 
        now.difference(_lastActivityTime!).inSeconds > 30 &&
        _currentOptions.isNotEmpty &&
        !_isLoading) {
      
      print('🔴 ThreadsPage - Health check detected potential freeze, attempting recovery');
      
      // Restart scanning - the wake word service handles its own recovery
      try {
        if (mounted && _currentOptions.isNotEmpty) {
          _maybeStartScanning();
          print('� ThreadsPage - Health check recovery: scanning restarted');
        }
      } catch (e) {
        print('🔴 ThreadsPage - Health check recovery error: $e');
      }
      
      _lastActivityTime = now; // Reset timer
    }
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _resumeScanning() async {
    print('🟢 ThreadsPage - _resumeScanning: called');
    print('🟢 ThreadsPage - _resumeScanning: _isScanningPaused=$_isScanningPaused, _waitingForUserInput=$_waitingForUserInput, _isScanning=$_isScanning');
    
    // If we're not in a paused state and not waiting for input, just start scanning
    if (!_isScanningPaused && !_waitingForUserInput) {
      print('🟢 ThreadsPage - _resumeScanning: Not in paused state, just starting scanning');
      if (_currentOptions.isNotEmpty && !_isScanning) {
        _startAuditoryScanning();
      }
      return;
    }
    
    setState(() {
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _currentScanCycle = 0; // Reset cycle counter when resuming
    });
    
    // Play "Scanning resumed" using the same voice as button scanning
    await _speakSystemVoice("Scanning resumed");
    
    // Now start scanning properly using the established method
    if (_currentOptions.isNotEmpty) {
      print('🟢 ThreadsPage - _resumeScanning: Starting scanning with ${_currentOptions.length} options');
      _startAuditoryScanning();
    } else {
      print('🔴 ThreadsPage - _resumeScanning: No options available to scan');
    }
  }

  // --- Handle Scan Key Press ---
  void _handleScanKeyPress() {
    // If we're waiting for user input (paused state), resume scanning
    if (_waitingForUserInput) {
      print('🟢 ThreadsPage - Switch pressed while paused, resuming scanning');
      _resumeScanning();
      return;
    }
    
    // Normal scanning behavior - select current option
    if (!_isScanning || _scanningIndex == null) return;
    
    if (_scanningIndex! < _currentOptions.length) {
      final selectedOption = _currentOptions[_scanningIndex!];
      _handleButtonAction(selectedOption);
    }
  }

  // --- Admin PIN Dialog ---
  void _showPinDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String pin = '';
        return AlertDialog(
          title: const Text('Enter Admin PIN'),
          content: TextField(
            onChanged: (value) => pin = value,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Enter PIN'),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (pin == _currentPIN) {
                  setState(() {
                    _isAdminToolbarLocked = false;
                  });
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _threadFocusNode!,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent && event.logicalKey.keyLabel == ' ') {
          print('🟢 ThreadsPage - Spacebar pressed: _waitingForUserInput=$_waitingForUserInput, _isScanningPaused=$_isScanningPaused, _isScanning=$_isScanning, _scanningIndex=$_scanningIndex, _waitingForInitialSwitch=$_waitingForInitialSwitch');
          
          // Handle initial switch press to start scanning
          if (_waitingForInitialSwitch) {
            print('🟡 ThreadsPage - Initial switch detected, starting scanning');
            setState(() {
              _waitingForInitialSwitch = false;
              _switchStartRequested = true;
            });
            _startAuditoryScanning();
            return;
          }
          
          if (_waitingForUserInput) {
            // If we're waiting for user input (paused state), resume scanning
            print('🟢 ThreadsPage - Spacebar: Resuming scanning from paused state');
            _resumeScanning();
          } else if (_isScanning && _scanningIndex != null && _scanningIndex! >= 0) {
            // Normal scanning behavior - select current option
            print('🟢 ThreadsPage - Spacebar: Selecting button at index $_scanningIndex');
            _handleScanKeyPress();
          }
        } else if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
          // Tab key for step-mode scanning advancement
          final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
          final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
          
          debugPrint('ThreadsPage: Tab pressed: scanMode=$scanMode, isScanning=$_isScanning, _isAnnouncingScanningPrompt=$_isAnnouncingScanningPrompt');
          
          if (scanMode == 'step' && _isScanning && _isAnnouncingScanningPrompt) {
            debugPrint('ThreadsPage: Tab: Interrupting scanning announcement');
            // Interrupt the current scanning prompt announcement
            _flutterTts.stop();
            if (mounted) {
              setState(() {
                _isAnnouncingScanningPrompt = false;
              });
            }
          }
          
          if (scanMode == 'step' && _isScanning && _scanningIndex != null) {
            debugPrint('ThreadsPage: Tab: Advancing in step mode from index $_scanningIndex');
            // Advance to next option
            _scanNextButton();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_currentThread != null 
              ? 'Thread: ${_currentThread!['favorite_name']}' 
              : 'Thread Communication'),
          backgroundColor: const Color(0xFF002244),
          foregroundColor: const Color(0xFFFB4F14),
          automaticallyImplyLeading: false, // Remove back button
          actions: [
            // Floating-style admin toolbar in AppBar
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Lock/Unlock button
                  IconButton(
                    icon: Icon(
                      _isAdminToolbarLocked ? Icons.lock : Icons.lock_open,
                      size: 18,
                      color: const Color(0xFF002244),
                    ),
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
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  
                  // Admin buttons - Only show when unlocked
                  if (!_isAdminToolbarLocked) ...[
                    IconButton(
                      icon: const Icon(Icons.settings, size: 18, color: Color(0xFF002244)),
                      tooltip: 'Admin Settings',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AdminSettingsPage(),
                          ),
                        );
                      },
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      icon: const Icon(Icons.grid_on, size: 18, color: Color(0xFF002244)),
                      tooltip: 'Admin Pages & Buttons',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AdminPagesButtonsPage(),
                          ),
                        );
                      },
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      icon: const Icon(Icons.location_on, size: 18, color: Color(0xFF002244)),
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
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 18, color: Color(0xFF002244)),
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
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      icon: const Icon(Icons.book, size: 18, color: Color(0xFF002244)),
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
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    IconButton(
                      icon: const Icon(Icons.volume_up, size: 18, color: Color(0xFF002244)),
                      tooltip: 'Audio Device Admin',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AudioDeviceAdminPage(),
                          ),
                        );
                      },
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Thread History Section (iMessage-style)
                Container(
                  height: 200,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildThreadHistory(),
                ),
                
                const SizedBox(height: 16),
                
                // Options Grid
                Expanded(
                  child: _buildOptionsGrid(),
                ),
                
                // Status Message - Match main page styling for consistency
                if (_statusMessage?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _microphoneEnabled
                                  ? (_microphoneListening
                                        ? Icons.mic
                                        : Icons.keyboard_voice)
                                  : Icons.mic_none,
                              color: _microphoneEnabled
                                  ? (_microphoneListening
                                        ? Colors.red
                                        : Colors.green)
                                  : Colors.grey,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: const TextStyle(color: Colors.blueGrey),
                              ),
                            ),
                          ],
                        ),
                        // Show last heard words for debugging
                        if (_lastHeardWords.isNotEmpty)
                          Text(
                            'Last heard: "$_lastHeardWords"',
                            style: const TextStyle(
                              color: Colors.grey, 
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
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
                            color: Colors.black.withOpacity(0.3),
                            offset: Offset(0, 4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Speech bubble icon
                          Image.asset(
                            'assets/whitespeechbubble.jpg',
                            width: 60,
                            height: 60,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Icon(
                                  Icons.chat_bubble_outline,
                                  size: 30,
                                  color: Colors.grey[600],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 20),
                          // Speech bubble text
                          Flexible(
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
                        ],
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

  // --- Build Thread History (iMessage-style) ---
  Widget _buildThreadHistory() {
    if (_threadMessages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet. Start the conversation!',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _historyScrollController,
      itemCount: _threadMessages.length,
      itemBuilder: (context, index) {
        final message = _threadMessages[index];
        final content = message['content'] ?? '';
        final timestamp = message['timestamp'];
        final senderType = message['sender_type'] ?? 'incoming'; // Default to incoming
        final userSelection = message['user_selection'];
        
        // Parse timestamp for display
        String timeDisplay = '';
        if (timestamp != null) {
          try {
            final DateTime parsedTime = DateTime.parse(timestamp);
            final now = DateTime.now();
            final difference = now.difference(parsedTime);
            
            if (difference.inDays > 0) {
              timeDisplay = '${parsedTime.month}/${parsedTime.day}/${parsedTime.year} ${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}';
            } else if (difference.inHours > 0) {
              timeDisplay = '${difference.inHours}h ago';
            } else if (difference.inMinutes > 0) {
              timeDisplay = '${difference.inMinutes}m ago';
            } else {
              timeDisplay = 'Just now';
            }
          } catch (e) {
            timeDisplay = '';
          }
        }
        
        // Determine alignment and colors based on sender_type
        final isUser = senderType == 'user';
        final alignment = isUser ? MainAxisAlignment.end : MainAxisAlignment.start;
        final bubbleColor = isUser ? const Color(0xFF007AFF) : const Color(0xFFE5E5EA); // Blue for user, gray for incoming
        final textColor = isUser ? Colors.white : Colors.black;
        final timestampColor = isUser ? Colors.white70 : Colors.grey;
        
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: alignment,
            children: [
              if (!isUser) ...[
                // For incoming messages, no space on left
              ] else ...[
                // For user messages, add space on left
                const SizedBox(width: 60),
              ],
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show main content
                      Text(
                        userSelection ?? content,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                        ),
                      ),
                      if (timeDisplay.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          timeDisplay,
                          style: TextStyle(
                            color: timestampColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isUser) ...[
                // For user messages, no space on right
              ] else ...[
                // For incoming messages, add space on right
                const SizedBox(width: 60),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- Build Options Grid ---
  Widget _buildOptionsGrid() {
    debugPrint('ThreadsPage: _buildOptionsGrid() called with ${_currentOptions.length} options');
    
    if (_currentOptions.isEmpty) {
      debugPrint('ThreadsPage: No options available, showing placeholder');
      return const Center(
        child: Text('No options available'),
      );
    }

    debugPrint('ThreadsPage: Building grid with options: ${_currentOptions.map((o) => o['text']).toList()}');

    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        
        // Use same button sizing logic as main grid
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
        
        final Color darkColor = userSettings?.darkColor ?? const Color(0xFF002244);
        final Color lightColor = userSettings?.lightColor ?? const Color(0xFFFB4F14);
        
        return Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCols,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            itemCount: _currentOptions.length,
            itemBuilder: (context, index) {
              final option = _currentOptions[index];
              final isHighlighted = _isScanning && _scanningIndex == index;
              final fontSize = ((buttonSizePx / 10) * 1.44).clamp(14.4, 25.9);
              
              return Padding(
                padding: const EdgeInsets.all(2.0),
                child: SizedBox(
                  width: buttonSizePx,
                  height: buttonSizePx,
                  child: SpeechBubbleButton(
                    label: option['text'] ?? '',
                    onPressed: () => _handleButtonAction(option),
                    isActive: true,
                    isHighlighted: isHighlighted,
                    darkColor: darkColor,
                    lightColor: lightColor,
                    fontSize: fontSize,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
