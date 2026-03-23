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
import 'services/user_settings_provider.dart';
import 'services/wake_word_service.dart';
import 'admin_settings_scaffold.dart';
import 'admin_pages_buttons.dart';
import 'user_current_admin_page.dart';
import 'user_info_admin_page.dart';
import 'user_diary_admin_page.dart';
import 'audio_device_admin_page.dart';
import 'main.dart'; // Import to access routeObserver

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
  
  // --- Scanning State (matching main.dart exactly) ---
  bool _isScanning = false;
  bool _isScanningPaused = false;
  bool _waitingForUserInput = false;
  int? _scanningIndex;
  Timer? _scanningTimer;
  bool _suppressScanning = false;
  
  // Scan loop limit tracking (matching main.dart)
  int _currentScanCycle = 0; // Track how many complete cycles we've done
  
  // --- Audio & TTS ---
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
  bool _isListeningForQuestion = false;
  
  // --- Microphone Status Tracking (main page manages actual WakeWordService) ---
  bool _microphoneEnabled = false;
  bool _microphoneListening = false;

  @override
  void initState() {
    super.initState();
    print('🟢 ThreadsPage initState called - starting initialization');
    print('🟢 ThreadsPage - idToken: ${widget.idToken.isNotEmpty ? "Present" : "Missing"}');
    print('🟢 ThreadsPage - aacUserId: ${widget.aacUserId}');
    
    _threadFocusNode = FocusNode();
    
    print('🟢 ThreadsPage - setting up TTS');
    _setupTTS();
    
    // Add a small delay to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🟢 ThreadsPage post-frame callback - starting favorite location check');
      try {
        _checkFavoriteLocationAndOpenThread();
      } catch (e) {
        print('🔴 ThreadsPage ERROR in post-frame callback: $e');
        print('🔴 ThreadsPage ERROR stack trace: ${StackTrace.current}');
      }
    });
    
    print('🟢 ThreadsPage initState completed successfully');
  }

  @override
  void dispose() {
    _threadFocusNode?.dispose();
    _questionController.dispose();
    
    // Stop scanning before dispose (manual cleanup without setState to avoid dispose errors)
    print('🟡 ThreadsPage - dispose: Manually stopping scanning without setState');
    _isScanning = false;
    _scanningTimer?.cancel();
    _scanningIndex = null;
    _currentScanCycle = 0;
    _isScanningPaused = false;
    _waitingForUserInput = false;
    
    _flutterTts.stop();
    
    // CRITICAL: Do NOT stop the wake word service in dispose - this causes system microphone indicator to disappear
    // Since we're not creating our own WakeWordService instance, there's nothing to stop
    print('🟡 ThreadsPage - dispose: NOT stopping wake word service to maintain system microphone indicator');
    // _wakeWordService?.stop(); // REMOVED - this was causing the system microphone indicator to disappear
    
    // CRITICAL: Do NOT disable wake word service global flag when leaving ThreadsPage
    // This prevents the system microphone indicator from disappearing
    print('� ThreadsPage - Keeping wake word service global flag enabled to maintain system microphone indicator');
    // WakeWordService.wakeWordShouldBeActive = false; // REMOVED - this was causing the indicator to disappear
    
    // Reset microphone status when leaving ThreadsPage (no setState needed in dispose)
    _microphoneEnabled = false;
    _microphoneListening = false;
    
    // Unregister route observer
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() {
    // Navigated away from threads page (e.g., to admin page)
    print('🟡 ThreadsPage - didPushNext: Stopping auditory scanning');
    _stopAuditoryScanning();
    // Do NOT interfere with wake word service - let main page handle it
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // Returned to threads page
    print('🟡 ThreadsPage - didPopNext: Restarting scanning');
    _maybeStartScanning();
    // Do NOT interfere with wake word service - main page manages it
    super.didPopNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
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

  // --- Wake Word Service Setup ---
  Future<void> _setupWakeWordService() async {
    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final settings = settingsProvider.settings;
      
      // Get wake word settings
      final wakeWordInterjection = (settings?.wakeWordInterjection ?? 'hey').toLowerCase();
      final wakeWordName = (settings?.wakeWordName ?? 'bravo').toLowerCase();
      
      // Create wake words list (matching threads.js logic)
      final wakeWords = [
        '$wakeWordInterjection $wakeWordName',
        '$wakeWordInterjection, $wakeWordName',
        '$wakeWordInterjection,$wakeWordName'
      ];
      
      print('🟢 ThreadsPage - Wake words: $wakeWords');
      
      // CRITICAL: DO NOT create a new WakeWordService instance - this causes microphone conflicts
      // Instead, ensure the global flag stays active and restart the existing wake word service
      print('🟢 ThreadsPage - Re-enabling wake word service global flag');
      WakeWordService.wakeWordShouldBeActive = true;
      
      // CRITICAL: Actually restart the wake word service that was paused during navigation
      // This is needed because main page pauses the service when navigating to ThreadsPage
      print('🟢 ThreadsPage - Restarting wake word service to maintain system microphone indicator');
      await WakeWordService.restartWakeWordService();
      print('🟢 ThreadsPage - Wake word service restarted');
      
      // CRITICAL: Override wake word service callbacks to handle questions on ThreadsPage
      print('🟢 ThreadsPage - Setting up wake word service callbacks for ThreadsPage');
      await _setupWakeWordCallbacks();
      
      // Update microphone status to show green indicator
      setState(() {
        _microphoneEnabled = true;
        _microphoneListening = false; // Initially not listening for question
      });
      print('🟢 ThreadsPage - Microphone status updated: enabled=true, listening=false');
    } catch (e) {
      print('🔴 ThreadsPage - Error setting up wake word service: $e');
      print('🔴 ThreadsPage - Error stack trace: ${StackTrace.current}');
    }
  }

  // --- Setup Wake Word Service Callbacks for ThreadsPage ---
  Future<void> _setupWakeWordCallbacks() async {
    print('🟢 ThreadsPage - Setting up wake word callbacks');
    
    // Set the callbacks to handle wake word and questions on ThreadsPage
    WakeWordService.setCallbacks(
      onWakeWord: (transcript) async {
        print('🟢 ThreadsPage - Wake word detected: $transcript');
        print('🟢 ThreadsPage - Highlighting question box for input');
        setState(() {
          _highlightQuestionBox = true;
          _isListeningForQuestion = true;
          _microphoneListening = true;
        });
        
        // Start question listening on ThreadsPage
        await WakeWordService.startQuestionListeningStatic();
      },
      
      onQuestion: (question) async {
        print('🟢 ThreadsPage - Question received: $question');
        setState(() {
          _highlightQuestionBox = false;
          _isListeningForQuestion = false;
          _microphoneListening = false;
        });
        
        // Handle the question on ThreadsPage by generating response options
        await _handleQuestionOnThreadsPage(question);
      },
      
      onAnnounce: (message) async {
        // Use ThreadsPage's announcement method
        await _announceViaBackend(message);
      },
      
      onQuestionHighlight: (highlight) {
        setState(() {
          _highlightQuestionBox = highlight;
          _isListeningForQuestion = highlight;
          _microphoneListening = highlight;
        });
      },
      
      onTimeout: () {
        setState(() {
          _highlightQuestionBox = false;
          _isListeningForQuestion = false;
          _microphoneListening = false;
        });
      },
      
      onStatusBarUpdate: (heardText) {
        // Could update a status bar if needed
        print('🟢 ThreadsPage - Heard: $heardText');
      },
      
      shouldAllowWakeWordRestart: () {
        // Allow wake word restart on ThreadsPage unless we're loading
        return !_isLoading;
      },
    );
    
    print('🟢 ThreadsPage - Wake word callbacks setup complete');
  }

  // --- Handle Questions on ThreadsPage ---
  Future<void> _handleQuestionOnThreadsPage(String question) async {
    print('🟢 ThreadsPage - Processing question: $question');
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Announce that we're processing the question
      await _announceViaBackend('Okay, processing: $question. Give me a moment.');
      
      // Add a small delay before processing
      await Future.delayed(const Duration(seconds: 1));
      
      // For now, let's add the question to the current thread messages
      final newMessage = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'content': question,
        'isUser': true,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      setState(() {
        _threadMessages.add(newMessage);
        _isLoading = false;
      });
      
      // For now, just acknowledge the question was received
      // In the future, you could integrate with LLM processing similar to main page
      await _announceViaBackend('Question received: $question');
      
      print('🟢 ThreadsPage - Question processed and added to thread messages');
      
    } catch (e) {
      print('🔴 ThreadsPage - Error processing question: $e');
      setState(() {
        _isLoading = false;
      });
      await _announceViaBackend('Sorry, there was an error processing your question.');
    }
  }

  // --- Audio Session Initialization ---
  Future<void> _initializeAudioSession() async {
    if (_audioSessionInitialized) return;
    
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final platform = MethodChannel('audio_routing');
        await platform.invokeMethod('initializeAudioSession');
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
      print('🟡 ThreadsPage: URL: https://talkwithbravo.com/get-user-current');
      print('🟡 ThreadsPage: Headers - Authorization: Bearer ${widget.idToken.substring(0, 20)}...');
      print('🟡 ThreadsPage: Headers - X-User-ID: ${widget.aacUserId}');
      
      // Check if favorite location was loaded within 4 hours
      final response = await http.get(
        Uri.parse('https://talkwithbravo.com/get-user-current'),
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
        await _announceViaBackend('A favorite location has not been loaded recently. Returning to previous page.');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          print('🟠 ThreadsPage: Navigating back to GridPage');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => GridPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: 'User', // Default displayName
              ),
            ),
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
        await _announceViaBackend('Error opening thread: ${e.toString()}. Returning to previous page.');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          print('🔴 ThreadsPage: Popping navigation after error');
          Navigator.of(context).pop();
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
      print('🟡 ThreadsPage: URL: https://talkwithbravo.com/api/threads/open');
      print('🟡 ThreadsPage: Request body: {"favorite_name": "$favoriteName"}');
      
      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/api/threads/open'),
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

          if (result['is_new'] == true) {
            print('🟢 ThreadsPage: New thread created, generating initial options');
            await _announceViaBackend('New thread started for $favoriteName. What would you like to talk about?');
            await _generateInitialThreadOptions();
          } else {
            print('🟢 ThreadsPage: Existing thread opened, generating options from history');
            await _announceViaBackend('Thread opened for $favoriteName. Here are some conversation options.');
            await _generateThreadOptionsFromHistory();
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
        await _announceViaBackend('Error opening thread: ${e.toString()}. Returning to previous page.');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          print('🔴 ThreadsPage: Popping navigation after thread error');
          Navigator.of(context).pop();
        }
      } catch (announceError) {
        print('🔴 ThreadsPage: Error in thread error announcement: $announceError');
        if (mounted) {
          print('🔴 ThreadsPage: Emergency navigation pop from thread error');
          Navigator.of(context).pop();
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

      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/llm'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        debugPrint('ThreadsPage: Raw LLM response: ${response.body}');
        
        try {
          // Try to parse JSON response
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
          });
          
          _maybeStartScanning();
        } catch (jsonError) {
          debugPrint('ThreadsPage: JSON parsing error in _generateInitialThreadOptions: $jsonError');
          debugPrint('ThreadsPage: Raw response causing error: ${response.body}');
          
          // Try to extract JSON from response if it's wrapped in other text
          String cleanedResponse = response.body.trim();
          
          // Look for JSON array pattern
          final jsonArrayMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(cleanedResponse);
          if (jsonArrayMatch != null) {
            try {
              final List<dynamic> data = json.decode(jsonArrayMatch.group(0)!);
              List<Map<String, dynamic>> options = data.map((item) => {
                'text': item['summary'] ?? item['option'] ?? '',
                'speechPhrase': item['option'] ?? '',
                'isThreadOption': true,
              }).toList();

              // Add standard thread control buttons
              _addStandardThreadButtons(options);
              
              setState(() {
                _currentOptions = options;
              });
              
              _maybeStartScanning();
              return;
            } catch (extractError) {
              debugPrint('ThreadsPage: Failed to extract JSON from initial options: $extractError');
            }
          }
          
          // Fallback: create generic options
          debugPrint('ThreadsPage: Using fallback generic options for initial thread due to JSON error');
          List<Map<String, dynamic>> fallbackOptions = [
            {'text': 'How are you?', 'speechPhrase': 'How are you doing today?', 'isThreadOption': true},
            {'text': 'Tell me more', 'speechPhrase': 'Can you tell me more about that?', 'isThreadOption': true},
            {'text': 'That\'s interesting', 'speechPhrase': 'That\'s really interesting!', 'isThreadOption': true},
            {'text': 'I agree', 'speechPhrase': 'I completely agree with you.', 'isThreadOption': true},
            {'text': 'What do you think?', 'speechPhrase': 'What do you think about that?', 'isThreadOption': true},
          ];
          
          // Add standard thread control buttons
          _addStandardThreadButtons(fallbackOptions);
          
          setState(() {
            _currentOptions = fallbackOptions;
          });
          
          _maybeStartScanning();
        }
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

      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/llm'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        debugPrint('ThreadsPage: Raw LLM response (history): ${response.body}');
        
        try {
          // Try to parse JSON response
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
          });
          
          _maybeStartScanning();
        } catch (jsonError) {
          debugPrint('ThreadsPage: JSON parsing error in _generateThreadOptionsFromHistory: $jsonError');
          debugPrint('ThreadsPage: Raw response causing error: ${response.body}');
          
          // Try to extract JSON from response if it's wrapped in other text
          String cleanedResponse = response.body.trim();
          
          // Look for JSON array pattern
          final jsonArrayMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(cleanedResponse);
          if (jsonArrayMatch != null) {
            try {
              final List<dynamic> data = json.decode(jsonArrayMatch.group(0)!);
              List<Map<String, dynamic>> options = data.map((item) => {
                'text': item['summary'] ?? item['option'] ?? '',
                'speechPhrase': item['option'] ?? '',
                'isThreadOption': true,
              }).toList();

              // Add standard thread control buttons
              _addStandardThreadButtons(options);
              
              setState(() {
                _currentOptions = options;
              });
              
              _maybeStartScanning();
              return;
            } catch (extractError) {
              debugPrint('ThreadsPage: Failed to extract JSON from history options: $extractError');
            }
          }
          
          // Fallback: create contextual options based on recent history
          debugPrint('ThreadsPage: Using fallback contextual options for history due to JSON error');
          List<Map<String, dynamic>> fallbackOptions = [
            {'text': 'Continue topic', 'speechPhrase': 'Let\'s continue talking about that.', 'isThreadOption': true},
            {'text': 'Good point', 'speechPhrase': 'That\'s a really good point.', 'isThreadOption': true},
            {'text': 'Tell me more', 'speechPhrase': 'Can you tell me more about that?', 'isThreadOption': true},
            {'text': 'I see', 'speechPhrase': 'I see what you mean.', 'isThreadOption': true},
            {'text': 'What else?', 'speechPhrase': 'What else would you like to discuss?', 'isThreadOption': true},
          ];
          
          // Add standard thread control buttons
          _addStandardThreadButtons(fallbackOptions);
          
          setState(() {
            _currentOptions = fallbackOptions;
          });
          
          _maybeStartScanning();
        }
      } else {
        throw Exception('Failed to generate options: ${response.statusCode}');
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

      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/llm'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        debugPrint('ThreadsPage: Raw LLM response (new topic): ${response.body}');
        
        try {
          // Try to parse JSON response
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
          });
          
          _maybeStartScanning();
          await _announceViaBackend('Here are some new topic ideas to explore.');
        } catch (jsonError) {
          debugPrint('ThreadsPage: JSON parsing error in _generateNewTopicOptions: $jsonError');
          debugPrint('ThreadsPage: Raw response causing error: ${response.body}');
          
          // Try to extract JSON from response if it's wrapped in other text
          String cleanedResponse = response.body.trim();
          
          // Look for JSON array pattern
          final jsonArrayMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(cleanedResponse);
          if (jsonArrayMatch != null) {
            try {
              final List<dynamic> data = json.decode(jsonArrayMatch.group(0)!);
              List<Map<String, dynamic>> options = data.map((item) => {
                'text': item['summary'] ?? item['option'] ?? '',
                'speechPhrase': item['option'] ?? '',
                'isThreadOption': true,
              }).toList();

              // Add standard thread control buttons
              _addStandardThreadButtons(options);
              
              setState(() {
                _currentOptions = options;
              });
              
              _maybeStartScanning();
              await _announceViaBackend('Here are some new topic ideas to explore.');
              return;
            } catch (extractError) {
              debugPrint('ThreadsPage: Failed to extract JSON from new topic options: $extractError');
            }
          }
          
          // Fallback: create topic starter options
          debugPrint('ThreadsPage: Using fallback topic options due to JSON error');
          List<Map<String, dynamic>> fallbackOptions = [
            {'text': 'Weather today', 'speechPhrase': 'What do you think about the weather today?', 'isThreadOption': true},
            {'text': 'Weekend plans', 'speechPhrase': 'Do you have any fun plans for the weekend?', 'isThreadOption': true},
            {'text': 'Favorite hobby', 'speechPhrase': 'What\'s your favorite hobby or activity?', 'isThreadOption': true},
            {'text': 'Recent news', 'speechPhrase': 'Have you heard any interesting news lately?', 'isThreadOption': true},
            {'text': 'Travel stories', 'speechPhrase': 'Do you have any interesting travel stories?', 'isThreadOption': true},
          ];
          
          // Add standard thread control buttons
          _addStandardThreadButtons(fallbackOptions);
          
          setState(() {
            _currentOptions = fallbackOptions;
          });
          
          _maybeStartScanning();
          await _announceViaBackend('Here are some new topic ideas to explore.');
        }
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
    _stopAuditoryScanning();
    
    if (buttonData['isThreadControl'] == true) {
      final action = buttonData['action'];
      switch (action) {
        case 'something_else':
          await _generateInitialThreadOptions();
          break;
        case 'repeat':
          if (_threadMessages.isNotEmpty) {
            final lastMessage = _threadMessages.last;
            await _announceViaBackend(lastMessage['content']);
          }
          break;
        case 'new_topic':
          await _generateNewTopicOptions();
          break;
        case 'exit':
          Navigator.of(context).pop();
          return;
      }
    } else if (buttonData['isThreadOption'] == true) {
      // Handle thread conversation option
      final speechPhrase = buttonData['speechPhrase'];
      if (speechPhrase != null) {
        await _addMessageToThread(speechPhrase, 'user');
        await _announceViaBackend(speechPhrase);
        await _generateResponseOptions(speechPhrase);
      }
    }
    
    _maybeStartScanning();
  }

  // --- Add Message to Thread ---
  Future<void> _addMessageToThread(String content, String senderType) async {
    if (_currentThread == null) return;
    
    try {
      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/api/threads/message'),
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

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success'] == true) {
          setState(() {
            _threadMessages.add({
              'content': content,
              'sender_type': senderType,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          });
          print('🟢 ThreadsPage - Message added to thread: $content');
        }
      }
    } catch (e) {
      print('🔴 ThreadsPage - Error adding message to thread: $e');
      debugPrint('Error adding message to thread: $e');
    }
  }

  // --- Generate Response Options ---
  Future<void> _generateResponseOptions(String userMessage) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      final userSettings = settingsProvider.settings;
      final llmOptions = userSettings?.llmOptions ?? 10;
      final summaryOff = userSettings?.summaryOff ?? false;
      
      // Build context including thread history and current question - matching web app logic
      final recentHistory = _threadMessages.take(10).map((msg) => 
        '${msg['sender_type'] == 'user' ? 'User' : 'Others'}: ${msg['content']}'
      ).join('\n');
      
      final contextPrompt = 'The user is in a conversation thread at ${_currentThread?['location'] ?? 'current location'} with ${_currentThread?['people'] ?? 'people present'} during ${_currentThread?['activity'] ?? 'current activity'}.\n\n'
          'Recent conversation history:\n$recentHistory\n\n'
          'Someone just asked or commented: "$userMessage"\n\n'
          'Generate $llmOptions appropriate response options for the AAC user. The options should include:\n'
          '- Direct responses to the question/comment\n'
          '- Follow-up questions to keep the conversation going\n'
          '- Related comments that could lead to more discussion\n'
          '- Ways to share relevant personal experiences or thoughts\n\n'
          'Focus on creating engaging options that encourage continued communication and social interaction.';
      
      // Add summary instruction matching web app logic
      final summaryInstruction = summaryOff
          ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
          : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      
      final prompt = '$contextPrompt\n\nReturn ONLY a JSON list where each item has "option" and "summary" keys.\n$summaryInstruction\nThe "option" key should contain the FULL response text.\nExample: [{"option": "...", "summary": "..."}]';

      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/llm'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        debugPrint('ThreadsPage: Raw LLM response (response options): ${response.body}');
        
        try {
          // Try to parse JSON response
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
          });
          
          // DON'T restart scanning here - will be handled after question processing completes
        } catch (jsonError) {
          debugPrint('ThreadsPage: JSON parsing error in _generateResponseOptions: $jsonError');
          debugPrint('ThreadsPage: Raw response causing error: ${response.body}');
          
          // Try to extract JSON from response if it's wrapped in other text
          String cleanedResponse = response.body.trim();
          
          // Look for JSON array pattern
          final jsonArrayMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(cleanedResponse);
          if (jsonArrayMatch != null) {
            try {
              final List<dynamic> data = json.decode(jsonArrayMatch.group(0)!);
              List<Map<String, dynamic>> options = data.map((item) => {
                'text': item['summary'] ?? item['option'] ?? '',
                'speechPhrase': item['option'] ?? '',
                'isThreadOption': true,
              }).toList();

              // Add standard thread control buttons
              _addStandardThreadButtons(options);
              
              setState(() {
                _currentOptions = options;
              });
              
              // DON'T restart scanning here - will be handled after question processing completes
              return;
            } catch (extractError) {
              debugPrint('ThreadsPage: Failed to extract JSON from response options: $extractError');
            }
          }
          
          // Fallback: create response options based on the user message
          debugPrint('ThreadsPage: Using fallback response options due to JSON error');
          List<Map<String, dynamic>> fallbackOptions = [
            {'text': 'Yes, exactly', 'speechPhrase': 'Yes, that\'s exactly right.', 'isThreadOption': true},
            {'text': 'Tell me more', 'speechPhrase': 'Can you tell me more about that?', 'isThreadOption': true},
            {'text': 'That\'s cool', 'speechPhrase': 'That\'s really cool!', 'isThreadOption': true},
            {'text': 'I think so too', 'speechPhrase': 'I think so too.', 'isThreadOption': true},
            {'text': 'Interesting', 'speechPhrase': 'That\'s very interesting.', 'isThreadOption': true},
          ];
          
          // Add standard thread control buttons
          _addStandardThreadButtons(fallbackOptions);
          
          setState(() {
            _currentOptions = fallbackOptions;
          });
          
          // DON'T restart scanning here - will be handled after question processing completes
        }
      } else {
        throw Exception('Failed to generate response options: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating response options: $e');
      setState(() {
        _statusMessage = 'Error generating response options: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Announcement Method ---
  Future<void> _announceViaBackend(String text, {String routing = 'system'}) async {
    String idToken = widget.idToken;
    final aacUserId = widget.aacUserId;
    
    try {
      if (!_audioSessionInitialized) {
        await _initializeAudioSession();
        _audioSessionInitialized = true;
      }

      final response = await http.post(
        Uri.parse('https://talkwithbravo.com/play-audio'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'text': text, 'routing_target': routing}),
      );

      if (response.statusCode == 200) {
        // Handle audio playback similar to main.dart
        final jsonStr = response.body;
        final base64Audio = RegExp('"audio_data"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        
        if (base64Audio != null && base64Audio.isNotEmpty) {
          final player = AudioPlayer();
          final bytes = base64Decode(base64Audio);
          final tempDir = Directory.systemTemp;
          final tempFile = await File('${tempDir.path}/thread_tts.mp3').create();
          await tempFile.writeAsBytes(bytes, flush: true);
          await player.setFilePath(tempFile.path);
          await player.play();
        }
      } else {
        // Fallback to local TTS
        await _flutterTts.speak(text);
      }
    } catch (e) {
      debugPrint('Announcement error: $e');
      await _flutterTts.speak(text);
    }
  }

  // --- Scanning Methods ---
  void _maybeStartScanning() {
    if (_suppressScanning) {
      print('🟡 ThreadsPage - maybeStartScanning: scanning suppressed');
      return;
    }
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    print('🟡 ThreadsPage - maybeStartScanning: enableAuditoryScanning = ${settingsProvider.settings?.enableAuditoryScanning}');
    
    if (settingsProvider.settings?.enableAuditoryScanning ?? false) {
      _startAuditoryScanning();
    } else {
      _stopAuditoryScanning();
    }
  }

  Future<void> _startAuditoryScanning() async {
    print('🟡 ThreadsPage - startAuditoryScanning: called, _isScanning=${_isScanning.toString()}');
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _scanningIndex = -1;
      _currentScanCycle = 0; // Reset cycle counter
      _isScanningPaused = false; // Reset pause state
      _waitingForUserInput = false; // Reset waiting state
    });
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    int delay = settingsProvider.settings?.scanDelay ?? 3500;
    _scanningTimer?.cancel();
    
    // No force speaker for iOS/Android (matching main.dart)
    _scanStep();
    _scanningTimer = Timer.periodic(
      Duration(milliseconds: delay),
      (_) => _scanStep(),
    );
    print('🟡 ThreadsPage - startAuditoryScanning: Started with delay ${delay}ms');
  }

  void _stopAuditoryScanning() {
    print('🟡 ThreadsPage - stopAuditoryScanning: called, _isScanning=${_isScanning.toString()}');
    setState(() {
      _isScanning = false;
      _scanningTimer?.cancel();
      _scanningIndex = null;
      _currentScanCycle = 0; // Reset cycle counter
      _isScanningPaused = false; // Reset pause state
      _waitingForUserInput = false; // Reset waiting state
    });
    
    // DO NOT pause wake word service when scanning stops - this can interfere with system microphone indicator
    // The wake word service should remain active to maintain system microphone indicator visibility
    print('🟡 ThreadsPage - stopAuditoryScanning: Keeping wake word service active to maintain system microphone indicator');
    // if (_wakeWordService != null) {
    //   _wakeWordService!.pauseWakeWordAutoRestart();
    // }
  }

  Future<void> _pauseScanning() async {
    print('🟡 ThreadsPage - pauseScanning: called');
    setState(() {
      _isScanningPaused = true;
      _waitingForUserInput = true;
      _scanningTimer?.cancel(); // Stop the timer
      // Keep current _scanningIndex - don't change it
    });
    
    // Play "Scanning paused. Use your switch to resume" using the same voice as button scanning
    await _speakSystemVoice("Scanning paused. Use your switch to resume");
  }

  void _scanStep() async {
    print('🟡 ThreadsPage - scanStep: called');
    
    // Check if we're paused and waiting for user input
    if (_isScanningPaused && _waitingForUserInput) {
      print('🟡 ThreadsPage - scanStep: Scanning is paused, waiting for user input');
      return;
    }
    
    final definedButtons = _currentOptions.where((btn) => (btn['hidden'] != true) && ((btn['text'] ?? '').toString().trim().isNotEmpty)).toList();
    if (definedButtons.isEmpty) {
      print('🟡 ThreadsPage - scanStep: No defined buttons');
      return;
    }
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanLoopLimit = settingsProvider.settings?.scanLoopLimit ?? 3;
    
    setState(() {
      _scanningIndex = _scanningIndex == null ? 0 : (_scanningIndex! + 1) % definedButtons.length;
      
      // Check if we've completed a full cycle (back to index 0)
      if (_scanningIndex == 0 && _currentScanCycle > 0) {
        _currentScanCycle++;
        print('🟡 ThreadsPage - scanStep: Completed scan cycle $_currentScanCycle');
      } else if (_scanningIndex == 0) {
        // First time reaching index 0, start counting cycles
        _currentScanCycle = 1;
        print('🟡 ThreadsPage - scanStep: Starting scan cycle 1');
      }
    });
    
    // Check if we should pause BEFORE speaking the button (scanLoopLimit > 0 and we've reached the limit)
    if (scanLoopLimit > 0 && _currentScanCycle > scanLoopLimit) {
      print('🟡 ThreadsPage - scanStep: Reached scan loop limit ($scanLoopLimit), pausing');
      _pauseScanning();
      return;
    }
    
    final btn = definedButtons[_scanningIndex!];
    print('🟡 ThreadsPage - scanStep: Speaking button text: ${btn['text'] ?? btn['summary'] ?? btn['option'] ?? ''}');
    await _speakSystemVoice(btn['text'] ?? btn['summary'] ?? btn['option'] ?? '');
  }

  Future<void> _speakSystemVoice(String text) async {
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  // --- Handle Scan Key Press ---
  void _handleScanKeyPress() {
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
          if (_isScanningPaused && _waitingForUserInput) {
            // Resume scanning
            setState(() {
              _isScanningPaused = false;
              _waitingForUserInput = false;
            });
            _maybeStartScanning();
          } else if (_isScanning && _scanningIndex != null) {
            _handleScanKeyPress();
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Navigate back to GridPage using pushReplacement since we replaced it coming here
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => GridPage(
                    idToken: widget.idToken,
                    aacUserId: widget.aacUserId,
                    displayName: 'User', // Default displayName - could be improved later
                  ),
                ),
              );
            },
          ),
          actions: [
            // Microphone status indicator (matching main.dart implementation)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      _microphoneEnabled 
                        ? (_microphoneListening ? Icons.mic : Icons.keyboard_voice)
                        : Icons.mic_off,
                      color: _microphoneEnabled 
                        ? (_microphoneListening ? Colors.red : Colors.green)
                        : Colors.grey,
                    ),
                    onPressed: () {}, // No action needed for indicator
                  ),
                  if (_microphoneListening)
                    Positioned.fill(child: Icon(Icons.circle, color: Colors.red, size: 8)),
                  if (_microphoneListening)
                    Positioned.fill(child: Icon(Icons.circle, color: Colors.white, size: 4)),
                ],
              ),
            ),
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
                
                // Question Display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Question or Comment:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _highlightQuestionBox 
                                ? const Color(0xFFFB4F14) 
                                : const Color(0xFF002244), 
                            width: 2
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: _highlightQuestionBox 
                              ? const Color(0xFFFFF7F0) 
                              : Colors.white,
                        ),
                        child: TextField(
                          controller: _questionController,
                          readOnly: true,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF002244),
                          ),
                          decoration: InputDecoration(
                            hintText: _isListeningForQuestion 
                                ? 'Listening...' 
                                : 'Say "Hey Bravo" then your question or comment',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Options Grid
                Expanded(
                  child: _buildOptionsGrid(),
                ),
                
                // Status Message
                if (_statusMessage?.isNotEmpty == true)
                  Container(
                    padding: const EdgeInsets.all(12),
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
      itemCount: _threadMessages.length,
      itemBuilder: (context, index) {
        final message = _threadMessages[index];
        final isUser = message['sender_type'] == 'user';
        
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: isUser 
                ? MainAxisAlignment.end 
                : MainAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isUser 
                      ? const Color(0xFF007AFF) 
                      : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  message['content'] ?? '',
                  style: TextStyle(
                    color: isUser ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Build Options Grid ---
  Widget _buildOptionsGrid() {
    if (_currentOptions.isEmpty) {
      return const Center(
        child: Text('No options available'),
      );
    }

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
              
              return Container(
                decoration: BoxDecoration(
                  color: isHighlighted ? lightColor : Colors.white,
                  border: Border.all(
                    color: isHighlighted ? lightColor : darkColor,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isHighlighted ? [
                    BoxShadow(
                      color: lightColor.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ] : [
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
                    onTap: () => _handleButtonAction(option),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Center(
                        child: Text(
                          option['text'] ?? '',
                          style: TextStyle(
                            color: isHighlighted ? Colors.white : darkColor,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
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
