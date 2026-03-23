import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'dart:convert';
import '../config/environment_config.dart';
import 'wake_word_service.dart';
import '../data/interview_questions.dart';
import 'authenticated_http_client.dart';

class InterviewQuestion {
  final String id;
  final String text;
  final String type;
  final bool required;
  final bool followUp;

  InterviewQuestion({
    required this.id,
    required this.text,
    required this.type,
    this.required = false,
    this.followUp = false,
  });
}

class InterviewResponse {
  final String questionId;
  final String question;
  final String answer;
  final DateTime timestamp;
  final String type;

  InterviewResponse({
    required this.questionId,
    required this.question,
    required this.answer,
    required this.timestamp,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'questionId': questionId,
    'question': question,
    'answer': answer,
    'timestamp': timestamp.toIso8601String(),
    'type': type,
  };

  factory InterviewResponse.fromJson(Map<String, dynamic> json) => InterviewResponse(
    questionId: json['questionId'] ?? '',
    question: json['question'] ?? '',
    answer: json['answer'] ?? '',
    timestamp: DateTime.parse(json['timestamp']),
    type: json['type'] ?? '',
  );
}

class InterviewFriendFamily {
  final String name;
  final String relationship;
  final String birthday;
  final String about;

  InterviewFriendFamily({
    required this.name,
    required this.relationship,
    this.birthday = '',
    this.about = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'relationship': relationship,
    'birthday': birthday,
    'about': about,
  };
}

class InterviewData {
  String userName = '';
  List<InterviewResponse> responses = [];
  List<InterviewFriendFamily> friendsFamily = [];
  DateTime? startTime;
  DateTime? lastSaveTime;

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'responses': responses.map((r) => r.toJson()).toList(),
    'friendsFamily': friendsFamily.map((f) => f.toJson()).toList(),
    'startTime': startTime?.toIso8601String(),
    'lastSaveTime': lastSaveTime?.toIso8601String(),
  };
}

class AudioInterviewService extends ChangeNotifier {
  // Core state
  bool _isActive = false;
  bool _isPaused = false;
  int _currentQuestionIndex = 0;
  InterviewData _interviewData = InterviewData();

  // Speech services - Independent instance to avoid WakeWordService interference
  final FlutterTts _tts = FlutterTts();
  late final SpeechToText _speech;
  bool _isListening = false;
  String _currentRecognizedText = '';
  String _committedText = ''; // Text committed from previous sessions
  bool _speechInitialized = false;
  bool _isSpeaking = false;
  
  // Speech settings
  double _speechRate = 0.5;

  // Authentication
  String _idToken = '';
  String _aacUserId = '';

  // Questions
  late List<InterviewQuestion> _baseQuestions;
  late List<InterviewQuestion> _currentQuestions;
  List<InterviewQuestion> _additionalQuestions = [];

  // Status
  String _status = '';
  String _statusType = 'info'; // info, success, error, warning, listening
  
  // Silence detection (wake word service pattern)
  Timer? _initialTimeoutTimer;
  Timer? _silenceTimer;
  bool _hasDetectedFirstSpeech = false;
  bool _hasProcessedResult = false;
  bool _isConfirming = false; // Separate flag for confirmation state
  bool _isRestarting = false; // Flag to prevent recursive restarts

  // Delayed restart system to prevent cutting off speech
  Timer? _delayedRestartTimer;
  DateTime? _lastSpeechEndTime;

  // Getters
  bool get isActive => _isActive;
  bool get isPaused => _isPaused;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  int get currentQuestionIndex => _currentQuestionIndex;
  InterviewData get interviewData => _interviewData;
  String get currentRecognizedText => _currentRecognizedText;
  String get status => _status;
  String get statusType => _statusType;
  int get totalQuestions => _currentQuestions.length;
  double get progress => totalQuestions > 0 ? _currentQuestionIndex / totalQuestions : 0.0;
  double get speechRate => _speechRate;

  AudioInterviewService() {
    // Create a completely independent SpeechToText instance
    _speech = SpeechToText();
    _initializeQuestions();
    _initializeTts();
  }

  void _initializeQuestions() {
    // Load comprehensive questions from the new interview questions data
    final comprehensiveQuestionData = InterviewQuestions.getAllQuestions();
    
    _baseQuestions = comprehensiveQuestionData.map((questionData) {
      return InterviewQuestion(
        id: questionData['id'] ?? '',
        text: questionData['question'] ?? '',
        type: questionData['category'] ?? 'general',
        required: questionData['required'] ?? false,
        followUp: questionData['followUp'] != null && questionData['followUp'].toString().isNotEmpty,
      );
    }).toList();
    
    _currentQuestions = List.from(_baseQuestions);
    
    // Log the loaded questions for debugging
    print('AudioInterviewService: Loaded ${_baseQuestions.length} questions');
    final requiredCount = _baseQuestions.where((q) => q.required).length;
    print('AudioInterviewService: $requiredCount required questions');
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5); // Moderate speed - clear but not too slow
    await _tts.setPitch(1.0);
    await _tts.setVolume(0.8); // Slightly lower volume to reduce microphone pickup
    
    // Set additional settings for better speech quality and isolation
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      // Try to route audio to specific output to reduce microphone pickup
    }
  }

  void setAuthenticationDetails(String idToken, String aacUserId) {
    _idToken = idToken;
    _aacUserId = aacUserId;
  }

  Future<bool> initializeSpeech() async {
    if (_speechInitialized) return true;
    
    // Completely stop WakeWordService to avoid any microphone conflicts
    debugPrint('[Interview] Completely stopping WakeWordService to prevent microphone conflicts');
    await WakeWordService.forceStopAndReset();
    WakeWordService.pauseWakeWordService();
    
    // Wait longer to ensure complete isolation
    await Future.delayed(const Duration(milliseconds: 1000));
    
    // Force stop any existing speech recognition on our instance
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 500));
    
    debugPrint('[Interview] Initializing completely independent speech recognizer');
    _speechInitialized = await _speech.initialize(
      onError: (error) {
        debugPrint('[Interview] ISOLATED Speech error: ${error.errorMsg}');
        _updateStatus('Speech recognition error: ${error.errorMsg}', 'error');
        _isListening = false;
        notifyListeners();
      },
      onStatus: (status) {
        debugPrint('[Interview] ISOLATED Speech status: $status (active: $_isActive, listening: $_isListening, hasProcessed: $_hasProcessedResult)');
        // Only process our own status updates when we're actively interviewing
        if (!_isActive) {
          debugPrint('[Interview] ISOLATED Ignoring status - interview not active');
          return;
        }
        
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          
          // If we haven't processed a result yet and have some text, restart listening
          if (!_hasProcessedResult && _currentRecognizedText.isNotEmpty) {
            debugPrint('[Interview] *** Speech session ended with text "$_currentRecognizedText" - auto-restarting to continue listening ***');
            Future.delayed(const Duration(milliseconds: 50), () {
              if (!_hasProcessedResult && _isActive) {
                _restartListening();
              }
            });
          } else if (!_hasProcessedResult && _currentRecognizedText.isEmpty) {
            debugPrint('[Interview] *** Speech session ended with no text - auto-restarting to continue listening ***');
            Future.delayed(const Duration(milliseconds: 50), () {
              if (!_hasProcessedResult && _isActive) {
                _restartListening();
              }
            });
          }
          
          notifyListeners();
        }
      },
    );
    
    if (!_speechInitialized) {
      _updateStatus('Speech recognition not available on this device', 'error');
    } else {
      debugPrint('[Interview] ISOLATED Speech recognizer initialized successfully');
    }
    
    return _speechInitialized;
  }

  Future<void> startInterview() async {
    // Completely shut down wake word service AND disable all callbacks
    debugPrint('[Interview] Completely shutting down wake word service and disabling callbacks for full isolation');
    await WakeWordService.forceStopAndReset();
    WakeWordService.pauseWakeWordService();
    WakeWordService.disableCallbacks(); // NEW: Disable all callbacks during interview
    
    // Longer delay to ensure complete isolation
    await Future.delayed(const Duration(milliseconds: 1000));
    
    if (!await initializeSpeech()) {
      _updateStatus('Cannot start interview: Speech recognition not available', 'error');
      return;
    }

    _isActive = true;
    _isPaused = false;
    _interviewData.startTime = DateTime.now();
    _currentQuestionIndex = 0;
    _updateStatus('Interview started', 'success');
    notifyListeners();

    await _askCurrentQuestion();
  }

  Future<void> _askCurrentQuestion() async {
    if (_isPaused || !_isActive) return;

    final question = _getCurrentQuestion();
    if (question == null) {
      await _completeInterview();
      return;
    }

    // Ensure clean state before starting
    await _speech.stop();
    _isListening = false;
    _hasDetectedFirstSpeech = false;
    _hasProcessedResult = false;
    
    final questionText = _processQuestionText(question.text);
    _updateStatus('Speaking question... Please wait', 'info');
    notifyListeners();

    // Speak the question with proper isolation
    await _speakText(questionText);

    // Extended pause to ensure TTS audio is completely finished
    await Future.delayed(const Duration(milliseconds: 1000));

    // Automatically start listening with continuous restart approach
    await _startListening();
  }

  InterviewQuestion? _getCurrentQuestion() {
    if (_currentQuestionIndex < _currentQuestions.length) {
      return _currentQuestions[_currentQuestionIndex];
    }
    return null;
  }

  // Public method for UI access
  InterviewQuestion? getCurrentQuestion() {
    return _getCurrentQuestion();
  }

  String _processQuestionText(String text) {
    final userName = _interviewData.userName.isNotEmpty ? _interviewData.userName : 'the user';
    return text.replaceAll('{userName}', userName);
  }

  Future<void> _speakText(String text) async {
    await _tts.stop();
    
    _isSpeaking = true;
    notifyListeners();
    
    // Use same TTS pattern as wake word service
    final ttsCompleter = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!ttsCompleter.isCompleted) {
        ttsCompleter.complete();
      }
    });
    
    await _tts.speak(text);
    await ttsCompleter.future;
    
    _tts.setCompletionHandler(() {});
    _isSpeaking = false;
    
    notifyListeners();
  }

  Future<void> _startListening() async {
    if (!_speechInitialized || _isPaused || !_isActive) return;

    // Completely stop all audio services and ensure isolation
    await _tts.stop();
    await _speech.stop();
    await WakeWordService.forceStopAndReset();
    WakeWordService.pauseWakeWordService();
    
    // CRITICAL: Complete shutdown and re-initialization (WakeWordService pattern)
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 50)); // Ensure complete shutdown
    
    // CRITICAL: Full re-initialization to properly acquire microphone
    debugPrint('[Interview] 🎤 Initializing speech recognizer with microphone resource management');
    final initialized = await _speech.initialize(
      onStatus: (status) {
        debugPrint('[Interview] 🎯 INTERVIEW SERVICE STATUS: $status, _isListening=$_isListening, _hasProcessedResult=$_hasProcessedResult');
        
        // IMMEDIATE RESTART on speech session end (bypass WakeWordService callback blocking)
        if ((status == 'done' || status == 'notListening') && _isActive && !_hasProcessedResult && _isListening && !_isRestarting) {
          debugPrint('[Interview] 🚀 IMMEDIATE RESTART: Speech session ended, restarting immediately (bypassing WakeWordService)');
          // Very short delay to avoid race conditions, much faster than timer
          Timer(const Duration(milliseconds: 50), () {
            if (_isActive && !_hasProcessedResult && _isListening && !_isRestarting) {
              debugPrint('[Interview] 🚀 Executing immediate restart after speech session end');
              _restartListening();
            }
          });
        }
      },
      onError: (error) {
        debugPrint('[Interview] ❌ INTERVIEW SERVICE ERROR: $error');
        
        // IMMEDIATE RESTART on error (bypass WakeWordService callback blocking)
        if (_isActive && !_hasProcessedResult && _isListening && !_isRestarting) {
          debugPrint('[Interview] 🚀 IMMEDIATE RESTART: Error occurred, restarting immediately (bypassing WakeWordService)');
          Timer(const Duration(milliseconds: 100), () {
            if (_isActive && !_hasProcessedResult && _isListening && !_isRestarting) {
              debugPrint('[Interview] 🚀 Executing immediate restart after error');
              _restartListening();
            }
          });
        }
      },
    );
    
    if (!initialized) {
      debugPrint('[Interview] ❌ Failed to initialize speech recognizer');
      _updateStatus('Microphone unavailable', 'error');
      return;
    }
    
    _currentRecognizedText = '';
    _committedText = '';
    _isListening = true;
    _hasDetectedFirstSpeech = false;
    _hasProcessedResult = false;
    _isConfirming = false;
    _speechWasListening = false; // Initialize monitoring state
    
    // Cancel any existing timers
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    
    // Extended delay to ensure complete audio isolation
    await Future.delayed(const Duration(milliseconds: 1000));
    
    _updateStatus('Listening for your response...', 'listening');
    notifyListeners();

    debugPrint('[Interview] 🎤 STARTING CONTINUOUS SPEECH RECOGNITION WITH TIMER-BASED AUTO-RESTART');
    
    // Start the timer-based auto-restart system
    _startAutoRestartTimer();
    
    await _speech.listen(
      onResult: (result) {
        if (_hasProcessedResult) {
          debugPrint('[Interview] *** IGNORING RESULT - already processed ***');
          return;
        }
        if (!_isListening || !_isActive) {
          debugPrint('[Interview] *** IGNORING RESULT - not actively listening ***');
          return;
        }
        
        final response = result.recognizedWords.trim();
        debugPrint('[Interview] 📝 SPEECH RESULT: "$response" (final: ${result.finalResult})');
        
        // Check if this is first valid speech detected
        final isValidResponse = response.length >= 2;
        if (!_hasDetectedFirstSpeech && response.isNotEmpty && isValidResponse) {
          debugPrint('[Interview] 🎤 FIRST SPEECH DETECTED: "$response"');
          _hasDetectedFirstSpeech = true;
          _initialTimeoutTimer?.cancel(); // Cancel initial timeout
          _updateStatus('Speech detected, listening...', 'listening');
        }
        
        // Update speech activity time and cancel any pending delayed restart
        if (response.isNotEmpty) {
          _lastSpeechEndTime = null; // Clear end time since speech is active
          _delayedRestartTimer?.cancel(); // Cancel any pending restart
        }
        
        // For the initial session, committed text is empty, so just use response
        _currentRecognizedText = response;
        
        // Show real-time transcription
        if (response.isNotEmpty && isValidResponse) {
          _updateStatus('Hearing: "$response"', 'listening');
        }
        
        notifyListeners();
        
        // Continuous listening approach - keep updating current text but don't auto-process
        if (result.finalResult && response.isNotEmpty && isValidResponse && !_hasProcessedResult) {
          debugPrint('[Interview] 📝 FINAL RESULT: "$response" - continuing to listen for more speech with timer restarts');
          // Continue listening with timer-based restarts to maintain microphone connection
        }
      },
      listenFor: const Duration(minutes: 10), // Longer duration - similar to WakeWordService
      pauseFor: const Duration(seconds: 30),  // Extended pause to prevent premature stopping
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
      localeId: 'en_US',
    );
  }

  // Timer-based auto-restart system (independent of status callbacks)
  Timer? _autoRestartTimer;
  Timer? _immediateMonitorTimer;
  bool _speechWasListening = false;
  
  void _startAutoRestartTimer() {
    _autoRestartTimer?.cancel();
    debugPrint('[Interview] ⏰ TIMER: Starting backup auto-restart timer with 60-second intervals');
    
    // Primary timer for backup restarts
    _autoRestartTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      debugPrint('[Interview] ⏰ BACKUP TIMER FIRED: _isActive=$_isActive, _isListening=$_isListening, _hasProcessedResult=$_hasProcessedResult, _isRestarting=$_isRestarting');
      
      if (_isActive && _isListening && !_hasProcessedResult && !_isRestarting) {
        debugPrint('[Interview] 🔄 BACKUP TIMER: Auto-restarting speech recognition to prevent timeout');
        _restartListening();
      } else {
        debugPrint('[Interview] ⏰ BACKUP TIMER: Skipping restart - conditions not met');
        if (!_isActive || _hasProcessedResult) {
          debugPrint('[Interview] ⏰ BACKUP TIMER: Canceling timer - interview completed or inactive');
          timer.cancel();
        }
      }
    });
    
    // Fast monitoring timer for immediate restarts
    _startImmediateMonitorTimer();
  }

  DateTime? _lastRestartTime;
  
  void _startDelayedRestart() {
    _delayedRestartTimer?.cancel();
    
    debugPrint('[Interview] 🔄⏰ Starting IMMEDIATE restart to prevent speech interruption');
    
    // Restart immediately (very short delay) to capture longer answers
    _delayedRestartTimer = Timer(const Duration(milliseconds: 50), () {
      if (_isActive && _isListening && !_isRestarting) {
        debugPrint('[Interview] ⏰ IMMEDIATE RESTART: Proceeding to restart listening');
        _lastRestartTime = DateTime.now();
        _restartListening();
      } else {
        debugPrint('[Interview] ⏰ IMMEDIATE RESTART CANCELLED: Service state changed (_isActive=$_isActive, _isListening=$_isListening, _isRestarting=$_isRestarting)');
      }
    });
  }
  
  void _startImmediateMonitorTimer() {
    _immediateMonitorTimer?.cancel();
    debugPrint('[Interview] 🚀 Starting speech monitoring timer for delayed restarts');
    
    // Monitor every 100ms for speech recognition state changes (High frequency for immediate detection)
    _immediateMonitorTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isActive || _hasProcessedResult) {
        debugPrint('[Interview] 🚀 MONITOR: Stopping monitoring - interview completed');
        timer.cancel();
        return;
      }
      
      final isCurrentlyListening = _speech.isListening;
      
      // Log state changes for debugging
      if (_speechWasListening != isCurrentlyListening) {
        debugPrint('[Interview] 🚀 MONITOR STATE CHANGE: was_listening=$_speechWasListening → now_listening=$isCurrentlyListening, _isListening=$_isListening, _isRestarting=$_isRestarting');
      }
      
      // Detect when speech recognition stops - start delayed restart to allow continued speech
      if (_speechWasListening && !isCurrentlyListening && _isListening && !_isRestarting) {
        final now = DateTime.now();
        _lastSpeechEndTime = now;
        
        final timeSinceLastRestart = _lastRestartTime != null ? now.difference(_lastRestartTime!) : const Duration(seconds: 10);
        
        // Reduced throttle to 500ms to allow recovery from immediate failures
        if (timeSinceLastRestart.inMilliseconds >= 500) { 
          debugPrint('[Interview] 🚀 MONITOR: Speech stopped - starting IMMEDIATE restart to allow continued speech');
          _startDelayedRestart();
        } else {
          debugPrint('[Interview] 🚀 MONITOR: Speech stopped but throttling restart (last restart ${timeSinceLastRestart.inMilliseconds}ms ago) - forcing retry in 500ms');
          // Force a retry if we were throttled, in case the previous restart failed immediately
          Timer(const Duration(milliseconds: 500), () {
             if (_isActive && _isListening && !_isRestarting && !_speech.isListening) {
                debugPrint('[Interview] 🚀 MONITOR: Executing forced retry after throttle');
                _startDelayedRestart();
             }
          });
        }
      }
      
      _speechWasListening = isCurrentlyListening;
    });
  }
  
  void _handleRestartSpeechResult(SpeechRecognitionResult result) {
    if (_hasProcessedResult) {
      debugPrint('[Interview] *** IGNORING RESULT - already processed ***');
      return;
    }
    if (!_isListening || !_isActive) {
      debugPrint('[Interview] *** IGNORING RESULT - not actively listening ***');
      return;
    }
    
    final response = result.recognizedWords.trim();
    debugPrint('[Interview] 📝 RESTART RESULT: "$response" (final: ${result.finalResult})');
    
    if (response.isNotEmpty) {
      // INTELLIGENT MERGE LOGIC
      // We merge the committed text (from previous sessions) with the new text (from current session)
      // handling any overlap where the restart captured words we already have.
      
      final mergedText = _mergeText(_committedText, response);
      
      if (mergedText != _currentRecognizedText) {
        _currentRecognizedText = mergedText;
        debugPrint('[Interview] 📝 MERGED TEXT: "$_currentRecognizedText"');
        
        if (!_hasDetectedFirstSpeech) {
          _hasDetectedFirstSpeech = true;
          _updateStatus('Speech detected, listening...', 'listening');
        }
        
        _updateStatus('Hearing: "$_currentRecognizedText"', 'listening');
        notifyListeners();
      }
    }
  }

  // Helper to merge two strings by finding the overlap
  String _mergeText(String current, String newText) {
    if (current.isEmpty) return newText;
    if (newText.isEmpty) return current;
    
    final currentWords = current.trim().split(' ');
    final newWords = newText.trim().split(' ');
    
    // Optimization: only check last N words of current to avoid scanning entire history
    // We assume overlap won't be more than 10 words
    int startCheck = (currentWords.length - 10).clamp(0, currentWords.length);
    
    int bestOverlap = 0;
    
    for (int i = startCheck; i < currentWords.length; i++) {
       // Check if currentWords[i..end] matches newWords[0..len]
       bool match = true;
       int currentIdx = i;
       int newIdx = 0;
       
       while (currentIdx < currentWords.length && newIdx < newWords.length) {
         if (currentWords[currentIdx].toLowerCase() != newWords[newIdx].toLowerCase()) {
           match = false;
           break;
         }
         currentIdx++;
         newIdx++;
       }
       
       if (match) {
         // We found a potential overlap. 
         // The overlap length is (currentWords.length - i)
         // But we must ensure that the match continued to the end of currentWords
         // (i.e. the suffix of current matches the prefix of new)
         if (currentIdx == currentWords.length) {
            bestOverlap = currentWords.length - i;
            break; // Found the longest overlap (since we started from left)
         }
       }
    }
    
    if (bestOverlap > 0) {
      debugPrint('[Interview] 🔗 Found overlap of $bestOverlap words: "${newWords.sublist(0, bestOverlap).join(' ')}"');
      // Append only the non-overlapping part of newWords
      List<String> toAppend = newWords.sublist(bestOverlap);
      if (toAppend.isEmpty) return current; // newText is fully contained at end of current
      return "$current ${toAppend.join(' ')}";
    }
    
    return "$current $newText";
  }
  
  // Auto-restart listening with proper microphone resource management (WakeWordService pattern)
  Future<void> _restartListening() async {
    if (_hasProcessedResult || !_isActive || _isRestarting) return;
    
    _isRestarting = true; // Prevent recursive restarts
    debugPrint('[Interview] 🔄 Auto-restarting speech recognition with full microphone reset');
    
    // Commit the current text before restarting so we can merge correctly
    _committedText = _currentRecognizedText;
    debugPrint('[Interview] 💾 Committed text before restart: "$_committedText"');
    
    // Cancel any existing timers - we'll restart them after successful restart
    _autoRestartTimer?.cancel();
    _immediateMonitorTimer?.cancel();
    _delayedRestartTimer?.cancel();
    
    // CRITICAL: Complete shutdown to release microphone resource (like WakeWordService)
    _isListening = false;
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 50)); // Minimized shutdown delay
    
    // Clear any accumulated speech recognition state by calling stop again
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 50)); // Minimized pause to ensure clean state
    
    // Try to listen directly first to save initialization time
    try {
      debugPrint('[Interview] 🎤 Attempting fast restart (listen without re-init)');
      _isListening = true;
      await _speech.listen(
        onResult: (result) {
          if (_hasProcessedResult) return;
          if (!_isListening || !_isActive) return;
          
          final response = result.recognizedWords.trim();
          debugPrint('[Interview] 📝 RESTART RESULT: "$response" (final: ${result.finalResult})');
          
          // Logic to merge with existing text
          if (response.isNotEmpty) {
             _handleRestartSpeechResult(result);
          }
        },
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 30),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        localeId: 'en_US',
      );
      debugPrint('[Interview] 🎤 Fast restart successful');
      
      // Restart timers
      _startAutoRestartTimer();
      _isRestarting = false;
      return;
    } catch (e) {
      debugPrint('[Interview] ⚠️ Fast restart failed, falling back to full re-initialization: $e');
    }

    // CRITICAL: Full re-initialization to reacquire microphone (like WakeWordService)
    debugPrint('[Interview] 🎤 Reinitializing speech recognizer to reacquire microphone');
    final initialized = await _speech.initialize(
      onStatus: (status) {
        debugPrint('[Interview] 🎯 INTERVIEW RESTART STATUS: $status, _isListening=$_isListening, _hasProcessedResult=$_hasProcessedResult');
        
        // IMMEDIATE RESTART on speech session end (like WakeWordService)
        if ((status == 'done' || status == 'notListening') && _isActive && !_hasProcessedResult && _isListening) {
          debugPrint('[Interview] 🚀 RESTART IMMEDIATE: Speech session ended during restart, restarting again');
          Timer(const Duration(milliseconds: 50), () {
            if (_isActive && !_hasProcessedResult && _isListening) {
              debugPrint('[Interview] 🚀 Executing immediate restart after restart session end');
              _restartListening();
            }
          });
        }
      },
      onError: (error) {
        debugPrint('[Interview] ❌ INTERVIEW RESTART ERROR: $error');
        
        // IMMEDIATE RESTART on error during restart (like WakeWordService)
        if (_isActive && !_hasProcessedResult && _isListening) {
          debugPrint('[Interview] 🚀 RESTART IMMEDIATE: Error during restart, restarting again');
          Timer(const Duration(milliseconds: 100), () {
            if (_isActive && !_hasProcessedResult && _isListening) {
              debugPrint('[Interview] 🚀 Executing immediate restart after restart error');
              _restartListening();
            }
          });
        }
      },
    );
    
    if (!initialized) {
      debugPrint('[Interview] ❌ Failed to reinitialize speech recognizer');
      _isRestarting = false; // Clear restart flag on failure
      return;
    }
    
    // Now start listening with fresh microphone resource
    _isListening = true;
    _hasDetectedFirstSpeech = _currentRecognizedText.isNotEmpty; // Keep first speech detection if we have text
    
    debugPrint('[Interview] 🎤 Starting fresh listening session with reacquired microphone');
    await _speech.listen(
      onResult: (result) {
        if (_hasProcessedResult) {
          debugPrint('[Interview] *** IGNORING RESULT - already processed ***');
          return;
        }
        if (!_isListening || !_isActive) {
          debugPrint('[Interview] *** IGNORING RESULT - not actively listening ***');
          return;
        }
        
        _handleRestartSpeechResult(result);
      },
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(seconds: 30),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
      localeId: 'en_US',
    );
    
    // CRITICAL: Restart the timers after successful restart
    debugPrint('[Interview] ⏰ TIMER: Restarting monitoring timers after successful microphone restart');
    _startAutoRestartTimer();
    
    _isRestarting = false; // Clear restart flag
  }

  // Wake word service pattern: Stop question listening and wait for manual confirmation
  Future<void> _stopQuestionListening() async {
    if (_hasProcessedResult) return; // Prevent duplicate processing
    
    _silenceTimer?.cancel();
    _initialTimeoutTimer?.cancel();
    await _speech.stop();
    _isListening = false;
    
    debugPrint('[Interview] Stopping question listening. Current text: "$_currentRecognizedText"');
    
    if (_currentRecognizedText.trim().isNotEmpty && !_hasProcessedResult) {
      // Show the captured response and wait for manual confirmation (like wake word service)
      debugPrint('[Interview] Captured response: "$_currentRecognizedText" - waiting for manual confirmation');
      _hasProcessedResult = true; // Set flag to prevent duplicates
      _updateStatus('Response captured. Please review and confirm.', 'success');
      // UI will show confirm/retry buttons, don't auto-confirm
    } else {
      // If no response was captured, DON'T auto-skip - wait for user action
      debugPrint('[Interview] No response captured - waiting for user to retry or skip manually');
      _hasProcessedResult = true;
      _updateStatus('No response heard. Please try again or skip this question.', 'warning');
      // Don't auto-skip - let user decide with buttons
    }
  }

  void stopListening() {
    if (_isListening) {
      _speech.stop();
      _initialTimeoutTimer?.cancel();
      _silenceTimer?.cancel();
      _isListening = false;
      notifyListeners();
    }
  }

  // Manual start listening - gives admin full control over when to begin recording
  Future<void> startListeningManually() async {
    if (_isListening) {
      _updateStatus('Already listening for response...', 'warning');
      return;
    }
    
    if (_hasProcessedResult) {
      _updateStatus('Response already captured. Please confirm or retry.', 'warning');
      return;
    }
    
    debugPrint('[Interview] Manual start listening requested');
    await _startListening();
  }

  // Manual stop listening - allows admin to stop recording and confirm response
  Future<void> stopListeningManually() async {
    if (!_isListening) {
      _updateStatus('Not currently listening.', 'warning');
      return;
    }
    
    debugPrint('[Interview] Manual stop listening requested');
    await _stopQuestionListening();
  }

  Future<void> confirmCurrentResponse() async {
    if (_currentRecognizedText.trim().isEmpty) {
      _updateStatus('No response to confirm. Please try speaking again.', 'warning');
      return;
    }
    
    // Prevent multiple confirmations
    if (_isConfirming) {
      debugPrint('[Interview] confirmCurrentResponse: Already confirming, ignoring duplicate call');
      return;
    }
    
    _isConfirming = true;

    final question = _getCurrentQuestion();
    if (question == null) return;

    // Save the response
    final response = InterviewResponse(
      questionId: question.id,
      question: _processQuestionText(question.text),
      answer: _currentRecognizedText,
      timestamp: DateTime.now(),
      type: question.type,
    );

    _interviewData.responses.add(response);

    // Handle special cases
    if (question.id == 'user_name' && _interviewData.userName.isEmpty) {
      _interviewData.userName = _currentRecognizedText;
    }

    // Generate follow-up questions if applicable
    if (question.followUp) {
      await _generateFollowUpQuestions(question, _currentRecognizedText);
    }

    _currentQuestionIndex++;
    _currentRecognizedText = '';
    
    // Reset silence detection flags and confirmation state
    _hasDetectedFirstSpeech = false;
    _hasProcessedResult = false;
    _isConfirming = false;
    
    stopListening();

    _updateStatus('Response saved. Moving to next question...', 'success');
    notifyListeners();

    // Brief pause before next question
    await Future.delayed(const Duration(milliseconds: 1500));
    await _askCurrentQuestion();
  }

  Future<void> _generateFollowUpQuestions(InterviewQuestion originalQuestion, String response) async {
    // Get follow-up question from comprehensive questions data
    final comprehensiveQuestions = InterviewQuestions.getAllQuestions();
    final originalQuestionData = comprehensiveQuestions.firstWhere(
      (q) => q['id'] == originalQuestion.id,
      orElse: () => <String, dynamic>{},
    );
    
    final config = InterviewQuestions.getConfig();
    final maxFollowUps = config['maxFollowUpQuestions'] ?? 2;
    final enableDynamic = config['enableDynamicFollowUps'] ?? true;
    
    // Count existing follow-ups for this question to avoid too many
    final existingFollowUps = _additionalQuestions.where((q) => 
      q.id.startsWith('${originalQuestion.id}_followup')).length;
    
    if (existingFollowUps >= maxFollowUps) {
      return;
    }
    
    // If there's a specific follow-up defined, use it
    if (originalQuestionData['followUp'] != null && 
        originalQuestionData['followUp'].toString().isNotEmpty) {
      final followUpText = originalQuestionData['followUp'].toString();
      
      _additionalQuestions.add(InterviewQuestion(
        id: '${originalQuestion.id}_followup_${DateTime.now().millisecondsSinceEpoch}',
        text: followUpText,
        type: originalQuestion.type,
      ));
      
      // If this question supports dynamic follow-ups and response is detailed, add one more
      if (enableDynamic && originalQuestionData['dynamicFollowUp'] == true && 
          response.trim().split(' ').length > 3) {
        await _generateDynamicFollowUp(originalQuestion, response);
      }
      return;
    }
    
    // Generate smart context-based follow-ups based on response content
    await _generateContextualFollowUp(originalQuestion, response);
  }
  
  Future<void> _generateDynamicFollowUp(InterviewQuestion originalQuestion, String response) async {
    final responseLower = response.toLowerCase();
    String? dynamicQuestion;
    
    // Generate contextual follow-ups based on response content
    if (responseLower.contains('love') || responseLower.contains('favorite')) {
      dynamicQuestion = "What is it about that that makes {userName} love it so much?";
    } else if (responseLower.contains('sometimes') || responseLower.contains('usually')) {
      dynamicQuestion = "Can you tell me more about when that happens?";
    } else if (responseLower.contains('help') || responseLower.contains('support')) {
      dynamicQuestion = "What kind of help works best for {userName}?";
    } else if (responseLower.contains('difficult') || responseLower.contains('hard')) {
      dynamicQuestion = "How does {userName} handle those difficult situations?";
    } else if (responseLower.contains('friends') || responseLower.contains('people')) {
      dynamicQuestion = "What does {userName} enjoy most about spending time with them?";
    } else if (response.trim().split(' ').length > 5) {
      // For detailed responses, ask for examples or more specific details
      dynamicQuestion = "Can you give me a specific example of that?";
    }
    
    if (dynamicQuestion != null) {
      _additionalQuestions.add(InterviewQuestion(
        id: '${originalQuestion.id}_dynamic_${DateTime.now().millisecondsSinceEpoch}',
        text: dynamicQuestion,
        type: originalQuestion.type,
      ));
    }
  }
  
  Future<void> _generateContextualFollowUp(InterviewQuestion originalQuestion, String response) async {
    final responseLower = response.toLowerCase();
    
    // Enhanced context-based follow-up generation with better detection
    if ((responseLower.contains('eat') || responseLower.contains('food') || 
         responseLower.contains('restaurant') || responseLower.contains('meal')) && 
        !_hasQuestionAbout('food_detail')) {
      _additionalQuestions.add(InterviewQuestion(
        id: 'food_detail_${DateTime.now().millisecondsSinceEpoch}',
        text: "What are some of {userName}'s favorite foods or meals?",
        type: originalQuestion.type,
      ));
    } else if ((responseLower.contains('watch') || responseLower.contains('tv') || 
               responseLower.contains('movie') || responseLower.contains('show')) && 
               !_hasQuestionAbout('entertainment_detail')) {
      _additionalQuestions.add(InterviewQuestion(
        id: 'entertainment_detail_${DateTime.now().millisecondsSinceEpoch}',
        text: "What types of shows or movies does {userName} enjoy watching?",
        type: originalQuestion.type,
      ));
    } else if ((responseLower.contains('music') || responseLower.contains('sing') || 
               responseLower.contains('dance') || responseLower.contains('song')) && 
               !_hasQuestionAbout('music_detail')) {
      _additionalQuestions.add(InterviewQuestion(
        id: 'music_detail_${DateTime.now().millisecondsSinceEpoch}',
        text: "What kind of music or songs does {userName} enjoy most?",
        type: originalQuestion.type,
      ));
    } else if ((responseLower.contains('sport') || responseLower.contains('team') || 
               responseLower.contains('game') || responseLower.contains('play')) && 
               !_hasQuestionAbout('sports_detail')) {
      _additionalQuestions.add(InterviewQuestion(
        id: 'sports_detail_${DateTime.now().millisecondsSinceEpoch}',
        text: "What sports or games does {userName} like to watch or play?",
        type: originalQuestion.type,
      ));
    } else if ((responseLower.contains('friend') || responseLower.contains('family') || 
               responseLower.contains('people') || responseLower.contains('visit')) && 
               !_hasQuestionAbout('social_detail')) {
      _additionalQuestions.add(InterviewQuestion(
        id: 'social_detail_${DateTime.now().millisecondsSinceEpoch}',
        text: "What does {userName} like to do when spending time with others?",
        type: originalQuestion.type,
      ));
    }

    // Add the follow-up questions to current questions
    if (_additionalQuestions.isNotEmpty) {
      _currentQuestions.addAll(_additionalQuestions);
      debugPrint('[Interview] Added ${_additionalQuestions.length} follow-up questions');
      _additionalQuestions.clear();
    }
  }

  bool _hasQuestionAbout(String topic) {
    return _currentQuestions.any((q) => q.id.contains(topic)) ||
           _interviewData.responses.any((r) => r.questionId.contains(topic));
  }

  Future<void> retryCurrentQuestion() async {
    // Ensure complete audio isolation when retrying
    await _tts.stop();
    await _speech.stop();
    
    _currentRecognizedText = '';
    _isConfirming = false;
    _isListening = false;
    _hasDetectedFirstSpeech = false;
    _hasProcessedResult = false;
    
    // Longer delay to prevent audio feedback
    await Future.delayed(const Duration(milliseconds: 500));
    
    await _askCurrentQuestion();
  }

  Future<void> skipCurrentQuestion() async {
    _currentQuestionIndex++;
    _currentRecognizedText = '';
    _isConfirming = false; // Reset confirmation flag
    _hasDetectedFirstSpeech = false;
    _hasProcessedResult = false;
    
    stopListening();
    
    // Cancel any active timers
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    
    _updateStatus('Question skipped', 'info');
    notifyListeners();

    // Add delay to ensure clean state transition
    await Future.delayed(const Duration(milliseconds: 500));
    await _askCurrentQuestion();
  }

  void togglePauseResume() {
    _isPaused = !_isPaused;
    
    if (_isPaused) {
      stopListening();
      _tts.stop();
      // Resume wake word service when pausing interview
      debugPrint('[Interview] Resuming wake word service during interview pause');
      WakeWordService.resumeWakeWordService();
      _updateStatus('Interview paused', 'warning');
    } else {
      // Pause wake word service when resuming interview
      debugPrint('[Interview] Pausing wake word service when resuming interview');
      WakeWordService.pauseWakeWordService();
      _updateStatus('Interview resumed', 'success');
      _askCurrentQuestion();
    }
    
    notifyListeners();
  }

  Future<void> _completeInterview() async {
    _isActive = false;
    
    // Clean up all timers and tracking
    _autoRestartTimer?.cancel();
    _immediateMonitorTimer?.cancel();
    _delayedRestartTimer?.cancel();
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    _lastRestartTime = null;
    _lastSpeechEndTime = null;
    
    stopListening();
    await _tts.stop();
    
    // Re-enable callbacks and resume wake word service
    debugPrint('[Interview] Re-enabling WakeWordService callbacks and resuming service after interview completion');
    WakeWordService.enableCallbacks();
    await WakeWordService.resumeWakeWordService();
    
    _updateStatus('Interview completed! You can now generate the user profile.', 'success');
    notifyListeners();
  }

  void restartInterview() {
    _isActive = false;
    
    // Clean up all timers
    _autoRestartTimer?.cancel();
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    
    _isPaused = false;
    _currentQuestionIndex = 0;
    _interviewData = InterviewData();
    _currentQuestions = List.from(_baseQuestions);
    _additionalQuestions.clear();
    _currentRecognizedText = '';
    
    stopListening();
    _tts.stop();
    
    // Re-enable callbacks and resume wake word service when resetting interview
    debugPrint('[Interview] Re-enabling WakeWordService callbacks and resuming service after interview reset');
    WakeWordService.enableCallbacks();
    WakeWordService.resumeWakeWordService();
    
    _updateStatus('Interview reset. Ready to start fresh.', 'info');
    notifyListeners();
  }

  Future<Map<String, dynamic>> generateAndProcessNarrative() async {
    if (_interviewData.responses.isEmpty) {
      throw Exception('No interview responses to process. Please complete the interview first.');
    }

    _updateStatus('Generating user profile narrative...', 'info');
    notifyListeners();

    try {
      final narrative = await _generateNarrative();
      final result = await _processNarrativeForUserInfo(narrative);
      
      // Create a detailed success message
      String successMessage = 'User profile generated successfully!';
      if (_interviewData.userName.isNotEmpty) {
        successMessage += ' Name automatically updated to "${_interviewData.userName}".';
      }
      if (result['userBirthday'] != null) {
        successMessage += ' Birthday automatically updated to ${result['userBirthday']}.';
      }
      
      _updateStatus(successMessage, 'success');
      notifyListeners();
      
      return result;
    } catch (e) {
      _updateStatus('Error generating user profile: $e', 'error');
      notifyListeners();
      rethrow;
    }
  }

  Future<String> _generateNarrative() async {
    // Check authentication before proceeding
    if (_idToken.isEmpty || _aacUserId.isEmpty) {
      throw Exception('Authentication not set up. Please ensure user is logged in.');
    }
    
    debugPrint('[Interview] Generating comprehensive narrative using dedicated endpoint');
    debugPrint('[Interview] Auth token available: ${_idToken.isNotEmpty}');
    debugPrint('[Interview] AAC User ID: $_aacUserId');
    debugPrint('[Interview] Total responses: ${_interviewData.responses.length}');

    // Enhanced prompt for generating a comprehensive narrative story about the user
    const comprehensivePrompt = '''Generate a detailed user profile narrative from this comprehensive interview. This information will be used by an AAC (Augmentative and Alternative Communication) system to provide personalized communication options.

Focus on creating a narrative that helps the communication system understand:
- The user's personality, preferences, and communication style
- Their relationships, interests, and daily life context  
- Their support needs and challenges
- Environmental factors that affect their communication
- Values and motivations that drive their choices

Write in third person as a cohesive, professional profile that caregivers and the AAC system can reference to provide better, more personalized communication support.''';

    // Prepare the interview responses in the format expected by the API
    final responses = _interviewData.responses.map((r) => {
      'questionId': r.questionId,
      'question': r.question,
      'answer': r.answer,
      'timestamp': r.timestamp.toIso8601String(),
      'type': r.type,
    }).toList();
    
    final requestBody = json.encode({
      'prompt': comprehensivePrompt,
      'responses': responses,
    });
    
    debugPrint('[Interview] Using /api/interview/generate-narrative endpoint');
    debugPrint('[Interview] Request contains ${responses.length} responses');
    
    // Use the dedicated interview narrative generation endpoint
    final narrativeResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/api/interview/generate-narrative',
      baseHeaders: {
        'X-User-ID': _aacUserId,
      },
      body: requestBody,
    );

    debugPrint('[Interview] Narrative response status: ${narrativeResponse.statusCode}');
    debugPrint('[Interview] Narrative response body length: ${narrativeResponse.body.length} chars');
    
    if (narrativeResponse.statusCode == 200) {
      final data = json.decode(narrativeResponse.body);
      final narrative = data['narrative'] ?? '';
      
      debugPrint('[Interview] ✅ API SUCCESS: Generated narrative length: ${narrative.length} characters');
      debugPrint('[Interview] Narrative preview (first 200 chars): ${narrative.length > 200 ? narrative.substring(0, 200) + "..." : narrative}');
      
      // Validate that we got a meaningful narrative
      if (narrative.trim().isEmpty) {
        debugPrint('[Interview] ⚠️ WARNING: Empty narrative returned from API, using fallback');
        return _createBasicNarrativeFromResponses();
      }
      
      if (narrative.length < 50) {
        debugPrint('[Interview] ⚠️ WARNING: Very short narrative (${narrative.length} chars), might want to use fallback');
        debugPrint('[Interview] Short narrative content: "$narrative"');
      }
      
      return narrative;
    } else {
      // Log the error details for debugging
      debugPrint('[Interview] ❌ API ERROR: Status ${narrativeResponse.statusCode}');
      debugPrint('[Interview] Error response body: ${narrativeResponse.body}');
      
      // Try to parse error message from response
      String errorMessage = 'Unknown error';
      try {
        final errorData = json.decode(narrativeResponse.body);
        errorMessage = errorData['error'] ?? 'Failed to generate narrative';
      } catch (e) {
        errorMessage = 'HTTP ${narrativeResponse.statusCode}: Failed to generate narrative';
      }
      
      debugPrint('[Interview] Parsed error: $errorMessage');
      
      // Fallback to basic narrative creation
      debugPrint('[Interview] 🔄 Falling back to basic narrative generation');
      final fallbackNarrative = _createBasicNarrativeFromResponses();
      debugPrint('[Interview] 📝 Fallback narrative length: ${fallbackNarrative.length} characters');
      
      return fallbackNarrative;
    }
  }

  String _createBasicNarrativeFromResponses() {
    final responses = _interviewData.responses;
    
    // Extract key information
    final nameResponses = responses.where((r) => r.questionId.contains('name')).toList();
    final nameResponse = nameResponses.isNotEmpty ? nameResponses.first : null;
    final userName = nameResponse?.answer.trim() ?? 'The user';
    
    var narrative = 'This profile is for $userName.\n\n';
    
    // Group responses by category for better organization
    final categories = <String, List<InterviewResponse>>{
      'identity': [],
      'communication': [],
      'interests': [],
      'relationships': [],
      'daily_life': [],
      'values': [],
      'challenges': [],
      'technology': []
    };
    
    for (final response in responses) {
      final questionId = response.questionId.toLowerCase();
      if (questionId.contains('name') || questionId.contains('identity')) {
        categories['identity']!.add(response);
      } else if (questionId.contains('communication') || questionId.contains('talk') || questionId.contains('express')) {
        categories['communication']!.add(response);
      } else if (questionId.contains('interest') || questionId.contains('hobby') || questionId.contains('like') || questionId.contains('enjoy')) {
        categories['interests']!.add(response);
      } else if (questionId.contains('family') || questionId.contains('friend') || questionId.contains('relationship')) {
        categories['relationships']!.add(response);
      } else if (questionId.contains('daily') || questionId.contains('routine') || questionId.contains('day')) {
        categories['daily_life']!.add(response);
      } else if (questionId.contains('value') || questionId.contains('important') || questionId.contains('goal')) {
        categories['values']!.add(response);
      } else if (questionId.contains('challenge') || questionId.contains('difficult') || questionId.contains('help')) {
        categories['challenges']!.add(response);
      } else {
        categories['interests']!.add(response); // Default to interests
      }
    }
    
    // Build narrative sections
    categories.forEach((category, categoryResponses) {
      if (categoryResponses.isNotEmpty) {
        final categoryText = categoryResponses.map((r) => r.answer.trim()).where((a) => a.isNotEmpty).join(' ');
        if (categoryText.isNotEmpty) {
          narrative += '$categoryText\n\n';
        }
      }
    });
    
    return narrative.trim();
  }

  Future<Map<String, dynamic>> _processNarrativeForUserInfo(String narrative) async {
    // Extract birthday from responses
    String? userBirthday;
    final birthdayResponse = _interviewData.responses.firstWhere(
      (r) => r.questionId == 'user_birthday',
      orElse: () => InterviewResponse(
        questionId: '', question: '', answer: '', timestamp: DateTime.now(), type: '',
      ),
    );
    
    if (birthdayResponse.questionId.isNotEmpty) {
      userBirthday = await _parseBirthdayFromResponse(birthdayResponse.answer);
    }

    // Save the generated narrative with user name using the existing API
    final saveResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/api/user-info',
      baseHeaders: {
        'X-User-ID': _aacUserId,
      },
      body: json.encode({
        'userInfo': narrative,
        'name': _interviewData.userName.isNotEmpty ? _interviewData.userName : null,
      }),
    );

    if (saveResponse.statusCode != 200) {
      throw Exception('Failed to save user narrative: ${saveResponse.statusCode}');
    }

    // Save birthday if we extracted one
    if (userBirthday != null && userBirthday.isNotEmpty) {
      final birthdayResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/birthdays',
        baseHeaders: {
          'X-User-ID': _aacUserId,
        },
        body: json.encode({
          'userBirthdate': userBirthday,
          'friendsFamily': [], // Keep existing friends/family data
        }),
      );

      if (birthdayResponse.statusCode != 200) {
        // Don't throw error for birthday save failure, just log it
        debugPrint('Warning: Failed to save birthday from interview: ${birthdayResponse.statusCode}');
      }
    }

    // Extract friends and family information
    final friendsFamily = <InterviewFriendFamily>[];
    // This would need more sophisticated parsing or additional questions

    return {
      'narrative': narrative,
      'userName': _interviewData.userName.isNotEmpty ? _interviewData.userName : null,
      'userBirthday': userBirthday,
      'friendsFamily': friendsFamily,
    };
  }

  Future<String?> _parseBirthdayFromResponse(String birthdayText) async {
    // Enhanced parsing to handle natural speech patterns
    final lowerText = birthdayText.toLowerCase();
    
    // First try exact date patterns
    final regexPatterns = [
      RegExp(r'(\d{4})-(\d{2})-(\d{2})'), // YYYY-MM-DD
      RegExp(r'(\d{2})/(\d{2})/(\d{4})'), // MM/DD/YYYY
      RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})'), // M/D/YYYY
      RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})'), // M-D-YYYY
      RegExp(r'(\d{1,2})\s+(\d{1,2})\s+(\d{4})'), // M D YYYY (spoken)
    ];

    for (final pattern in regexPatterns) {
      final match = pattern.firstMatch(birthdayText);
      if (match != null) {
        if (pattern.pattern.startsWith('(\\d{4})')) {
          return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
        } else {
          final month = match.group(1)!.padLeft(2, '0');
          final day = match.group(2)!.padLeft(2, '0');
          final year = match.group(3)!;
          return '$year-$month-$day';
        }
      }
    }

    // Try to parse month names (January 15, 1990)
    final monthNames = {
      'january': '01', 'jan': '01',
      'february': '02', 'feb': '02',
      'march': '03', 'mar': '03',
      'april': '04', 'apr': '04',
      'may': '05',
      'june': '06', 'jun': '06',
      'july': '07', 'jul': '07',
      'august': '08', 'aug': '08',
      'september': '09', 'sep': '09', 'sept': '09',
      'october': '10', 'oct': '10',
      'november': '11', 'nov': '11',
      'december': '12', 'dec': '12',
    };

    for (final entry in monthNames.entries) {
      final monthPattern = RegExp(r'${entry.key}\s+(\d{1,2})[,\s]+(\d{4})', caseSensitive: false);
      final match = monthPattern.firstMatch(lowerText);
      if (match != null) {
        final day = match.group(1)!.padLeft(2, '0');
        final year = match.group(2)!;
        return '$year-${entry.value}-$day';
      }
    }

    return null;
  }

  void _updateStatus(String message, String type) {
    _status = message;
    _statusType = type;
    debugPrint('Interview Status: $message');
  }

  String getCurrentQuestionText() {
    final question = _getCurrentQuestion();
    return question != null ? _processQuestionText(question.text) : '';
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    
    // Clean up timers
    _autoRestartTimer?.cancel();
    _immediateMonitorTimer?.cancel();
    _delayedRestartTimer?.cancel();
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    _lastRestartTime = null;
    _lastSpeechEndTime = null;
    
    // Re-enable WakeWordService callbacks when interview service is disposed
    WakeWordService.enableCallbacks();
    super.dispose();
  }
}