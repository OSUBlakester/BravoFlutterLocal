import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';
import '../data/family_friends_interview_questions.dart';
import 'wake_word_service.dart';

class FamilyFriendsQuestion {
  final String id;
  final String text;
  final String category;
  final bool required;
  final String? followUp;

  FamilyFriendsQuestion({
    required this.id,
    required this.text,
    required this.category,
    this.required = false,
    this.followUp,
  });
}

class FamilyFriendsResponse {
  final String questionId;
  final String question;
  final String answer;
  final DateTime timestamp;
  final String category;

  FamilyFriendsResponse({
    required this.questionId,
    required this.question,
    required this.answer,
    required this.timestamp,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'questionId': questionId,
    'question': question,
    'answer': answer,
    'timestamp': timestamp.toIso8601String(),
    'category': category,
  };
}

class ExtractedPerson {
  String name;
  String relationship;
  String about;
  String birthday;

  ExtractedPerson({
    this.name = '',
    this.relationship = '',
    this.about = '',
    this.birthday = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'relationship': relationship,
    'about': about,
    'birthday': birthday,
  };

  factory ExtractedPerson.fromJson(Map<String, dynamic> json) => ExtractedPerson(
    name: json['name'] ?? '',
    relationship: json['relationship'] ?? '',
    about: json['about'] ?? '',
    birthday: json['birthday'] ?? '',
  );

  bool get isComplete => name.isNotEmpty && relationship.isNotEmpty;
}

class FamilyFriendsInterviewData {
  String sessionId;
  DateTime startTime;
  List<FamilyFriendsResponse> responses;
  ExtractedPerson? extractedPerson;

  FamilyFriendsInterviewData({
    required this.sessionId,
    required this.startTime,
    List<FamilyFriendsResponse>? responses,
    this.extractedPerson,
  }) : responses = responses ?? <FamilyFriendsResponse>[];

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'startTime': startTime.toIso8601String(),
    'responses': responses.map((r) => r.toJson()).toList(),
    'extractedPerson': extractedPerson?.toJson(),
  };
}

class FamilyFriendsInterviewService extends ChangeNotifier {
  // Core state
  bool _isActive = false;
  bool _isPaused = false;
  int _currentQuestionIndex = 0;
  FamilyFriendsInterviewData _interviewData = FamilyFriendsInterviewData(
    sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
    startTime: DateTime.now(),
  );

  // Speech services
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _currentRecognizedText = '';
  bool _speechInitialized = false;
  bool _isSpeaking = false;

  // Speech settings
  double _speechRate = 0.5;

  // Authentication
  String _idToken = '';
  String _aacUserId = '';

  // Questions
  late List<FamilyFriendsQuestion> _questions;

  // Status
  String _status = '';
  String _statusType = 'info'; // info, success, error, warning, listening

  // Silence detection
  Timer? _silenceTimer;
  bool _hasDetectedFirstSpeech = false;
  bool _isConfirming = false;

  // Getters
  bool get isActive => _isActive;
  bool get isPaused => _isPaused;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  int get currentQuestionIndex => _currentQuestionIndex;
  int get totalQuestions => _questions.length;
  double get progress => totalQuestions > 0 ? _currentQuestionIndex / totalQuestions : 0.0;
  String get status => _status;
  String get statusType => _statusType;
  String get currentRecognizedText => _currentRecognizedText;
  bool get isConfirming => _isConfirming;
  FamilyFriendsInterviewData get interviewData => _interviewData;
  ExtractedPerson? get extractedPerson => _interviewData.extractedPerson;

  FamilyFriendsInterviewService() {
    _initializeQuestions();
    _initializeTts();
  }

  void _initializeQuestions() {
    final questionData = FamilyFriendsInterviewQuestions.getAllQuestions();
    
    _questions = questionData.map((q) {
      return FamilyFriendsQuestion(
        id: q['id'] ?? '',
        text: q['question'] ?? '',
        category: q['category'] ?? 'general',
        required: q['required'] ?? false,
        followUp: q['followUp'],
      );
    }).toList();

    print('FamilyFriendsInterviewService: Loaded ${_questions.length} questions');
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_speechRate);
  }

  void setAuthenticationDetails(String idToken, String aacUserId) {
    _idToken = idToken;
    _aacUserId = aacUserId;
  }

  Future<void> initializeSpeech() async {
    if (!_speechInitialized) {
      _speechInitialized = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            notifyListeners();
          }
        },
        onError: (error) {
          print('Speech recognition error: $error');
          _updateStatus('Speech recognition error', 'error');
          _isListening = false;
          notifyListeners();
        },
      );
    }
  }

  Future<void> startInterview() async {
    // Force stop wake word service completely to prevent interference
    debugPrint('[FamilyFriendsInterview] Force stopping wake word service to prevent microphone conflicts');
    WakeWordService.pauseWakeWordService();
    await WakeWordService.forceStopAndReset();
    
    // Small delay to ensure wake word service is fully stopped
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (_speechInitialized) {
      _isActive = true;
      _isPaused = false;
      _currentQuestionIndex = 0;
      _interviewData = FamilyFriendsInterviewData(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        startTime: DateTime.now(),
      );
      
      _updateStatus('Starting interview...', 'info');
      notifyListeners();
      
      await _askCurrentQuestion();
    } else {
      _updateStatus('Please wait for speech recognition to initialize', 'warning');
    }
  }

  Future<void> _askCurrentQuestion() async {
    if (_currentQuestionIndex >= _questions.length) {
      await _completeInterview();
      return;
    }

    final question = _questions[_currentQuestionIndex];
    final questionText = question.text;

    _updateStatus('Asking question ${_currentQuestionIndex + 1} of ${_questions.length}', 'info');
    
    // Speak the question and wait for completion
    await _speakText(questionText);
    
    // The _speakText method already includes proper timing, so minimal additional delay
    await Future.delayed(const Duration(milliseconds: 200));

    // Start listening for response
    await _startListening();
  }

  FamilyFriendsQuestion? getCurrentQuestion() {
    if (_currentQuestionIndex < _questions.length) {
      return _questions[_currentQuestionIndex];
    }
    return null;
  }

  String getCurrentQuestionText() {
    final question = getCurrentQuestion();
    return question?.text ?? '';
  }

  Future<void> _speakText(String text) async {
    debugPrint('🔊 FamilyFriendsInterview: Starting TTS for: "$text"');
    // Stop any ongoing speech recognition during TTS to prevent pickup
    if (_isListening) {
      debugPrint('🔊 FamilyFriendsInterview: Stopping speech recognition during TTS');
      await _speech.stop();
      _isListening = false;
    }
    
    await _tts.stop();
    
    _isSpeaking = true;
    notifyListeners();
    
    final ttsCompleter = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!ttsCompleter.isCompleted) {
        ttsCompleter.complete();
      }
    });
    
    await _tts.speak(text);
    await ttsCompleter.future;
    
    debugPrint('🔊 FamilyFriendsInterview: TTS completed, waiting 500ms buffer...');
    _isSpeaking = false;
    _tts.setCompletionHandler(() {});
    
    // Add extra delay to ensure TTS audio has fully finished and microphone is clear
    await Future.delayed(const Duration(milliseconds: 500));
    
    debugPrint('🔊 FamilyFriendsInterview: Buffer complete, TTS method finished');
    notifyListeners();
  }

  Future<void> _startListening() async {
    if (!_speechInitialized || _isListening) return;

    debugPrint('🎤 FamilyFriendsInterview: Clearing recognized text before listening');
    debugPrint('🎤 FamilyFriendsInterview: Previous text was: "$_currentRecognizedText"');
    _currentRecognizedText = '';
    debugPrint('🎤 FamilyFriendsInterview: Text cleared, starting to listen...');
    _hasDetectedFirstSpeech = false;
    _isConfirming = false;
    _isListening = true;
    _updateStatus('Listening for your answer...', 'listening');
    notifyListeners();

    try {
      await _speech.listen(
        onResult: (result) {
          debugPrint('🎤 FamilyFriendsInterview: Speech result - Final: ${result.finalResult}, Words: "${result.recognizedWords}"');
          
          // Update recognized text with any non-empty result
          if (result.recognizedWords.trim().isNotEmpty) {
            _currentRecognizedText = result.recognizedWords.trim();
            
            if (result.finalResult) {
              debugPrint('🎤 FamilyFriendsInterview: Final result set: "$_currentRecognizedText"');
            } else {
              debugPrint('🎤 FamilyFriendsInterview: Partial result set: "$_currentRecognizedText"');
            }
            
            // Show confirmation immediately when we detect any speech
            if (!_hasDetectedFirstSpeech) {
              _hasDetectedFirstSpeech = true;
              debugPrint('🔴 FamilyFriendsInterview: First speech detected, showing confirmation buttons');
              _showConfirmation();
            } else {
              // Just update the UI if confirmation is already showing
              notifyListeners();
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );

      // Set up silence detection
      _silenceTimer = Timer(const Duration(seconds: 5), () {
        if (!_hasDetectedFirstSpeech && _isListening) {
          _handleNoSpeechDetected();
        }
      });

    } catch (e) {
      _updateStatus('Error starting speech recognition: $e', 'error');
      _isListening = false;
      notifyListeners();
    }
  }

  void _showConfirmation() {
    debugPrint('🔄 FamilyFriendsInterview: _showConfirmation() called');
    _silenceTimer?.cancel();
    // Stop listening but show confirmation buttons
    _isListening = false;
    _isConfirming = true;
    debugPrint('🔄 FamilyFriendsInterview: _isConfirming set to true, _currentRecognizedText = "$_currentRecognizedText"');
    _updateStatus('Please confirm, try again, or keep speaking to add more', 'info');
    notifyListeners();
  }

  void _handleNoSpeechDetected() {
    _updateStatus('No speech detected. Please try speaking again.', 'warning');
    _isListening = false;
    notifyListeners();
  }

  Future<void> confirmResponse() async {
    debugPrint('✅ FamilyFriendsInterview: confirmResponse() called');
    debugPrint('✅ FamilyFriendsInterview: _currentRecognizedText = "$_currentRecognizedText"');
    debugPrint('✅ FamilyFriendsInterview: _isConfirming = $_isConfirming');
    
    if (_currentRecognizedText.isEmpty || !_isConfirming) {
      debugPrint('❌ FamilyFriendsInterview: confirmResponse() early return - text empty or not confirming');
      return;
    }

    // CRITICAL: Stop speech listening immediately and cleanup
    debugPrint('🛑 FamilyFriendsInterview: Stopping speech listener before confirming response');
    _silenceTimer?.cancel();
    _isListening = false;
    _isConfirming = false;
    
    try {
      await _speech.stop();
      debugPrint('🛑 FamilyFriendsInterview: Speech listener stopped successfully');
    } catch (e) {
      debugPrint('⚠️ FamilyFriendsInterview: Error stopping speech listener: $e');
    }
    final question = getCurrentQuestion();
    if (question == null) {
      debugPrint('❌ FamilyFriendsInterview: confirmResponse() - no current question');
      return;
    }

    debugPrint('✅ FamilyFriendsInterview: Creating response for question: ${question.id}');

    // Create response
    final response = FamilyFriendsResponse(
      questionId: question.id,
      question: question.text,
      answer: _currentRecognizedText,
      timestamp: DateTime.now(),
      category: question.category,
    );

    // Initialize responses list if it's unmodifiable or null
    if (_interviewData.responses.isEmpty) {
      _interviewData.responses = <FamilyFriendsResponse>[];
    }
    
    try {
      _interviewData.responses.add(response);
      debugPrint('✅ FamilyFriendsInterview: Response added to list successfully');
    } catch (e) {
      debugPrint('❌ FamilyFriendsInterview: Error adding response: $e');
      // Create a new mutable list if the current one is unmodifiable
      final newResponses = <FamilyFriendsResponse>[];
      newResponses.addAll(_interviewData.responses);
      newResponses.add(response);
      _interviewData.responses = newResponses;
      debugPrint('✅ FamilyFriendsInterview: Response added to new mutable list');
    }
    
    debugPrint('✅ FamilyFriendsInterview: Response saved, moving to next question (${_currentQuestionIndex + 1})');
    _updateStatus('Response saved', 'success');
    _currentQuestionIndex++;

    // Brief pause before next question
    await Future.delayed(const Duration(milliseconds: 1500));
    await _askCurrentQuestion();
  }

  Future<void> retryResponse() async {
    _isConfirming = false;
    _currentRecognizedText = '';
    _hasDetectedFirstSpeech = false;
    _updateStatus('Let\'s try that again...', 'info');
    notifyListeners();
    
    await Future.delayed(const Duration(milliseconds: 500));
    await _startListening();
  }

  Future<void> skipQuestion() async {
    _isConfirming = false;
    _isListening = false;
    _silenceTimer?.cancel();
    
    _updateStatus('Skipping question...', 'info');
    _currentQuestionIndex++;
    
    await Future.delayed(const Duration(milliseconds: 500));
    await _askCurrentQuestion();
  }

  Future<void> togglePauseResume() async {
    _isPaused = !_isPaused;
    
    if (_isPaused) {
      await _tts.stop();
      _isListening = false;
      _silenceTimer?.cancel();
      _updateStatus('Interview paused', 'warning');
    } else {
      _updateStatus('Interview resumed', 'info');
      await _askCurrentQuestion();
    }
    
    notifyListeners();
  }

  Future<void> _completeInterview() async {
    _isActive = false;
    _isListening = false;
    _silenceTimer?.cancel();
    
    _updateStatus('Processing your responses...', 'info');
    
    // Extract person data from responses
    await _extractPersonData();
    
    // Resume wake word service now that interview is complete
    debugPrint('[FamilyFriendsInterview] Resuming wake word service after interview completion');
    await WakeWordService.resumeWakeWordService();
    
    _updateStatus('Interview completed! All ${_questions.length} questions answered.', 'success');
    notifyListeners();
  }

  Future<void> _extractPersonData() async {
    final person = ExtractedPerson();
    
    // Extract information from responses
    for (final response in _interviewData.responses) {
      switch (response.questionId) {
        case 'person_name':
          person.name = response.answer;
          break;
        case 'relationship':
          person.relationship = response.answer;
          break;
        case 'about_person':
          person.about = response.answer;
          break;
        case 'birthday':
          person.birthday = _parseBirthday(response.answer);
          break;
      }
    }
    
    _interviewData.extractedPerson = person;
    
    // Try to enhance with AI if we have API access
    if (_idToken.isNotEmpty && _aacUserId.isNotEmpty) {
      await _enhancePersonDataWithAI(person);
    }
  }

  String _parseBirthday(String birthdayText) {
    final cleaned = birthdayText.toLowerCase().trim();
    
    if (cleaned.contains('don\'t know') || cleaned.contains('unknown') || cleaned.isEmpty) {
      return '';
    }
    
    // Try to parse various date formats to MM-DD
    final text = birthdayText.trim();
    
    // Check if already in MM-DD format
    if (RegExp(r'^\d{1,2}-\d{1,2}$').hasMatch(text)) {
      final parts = text.split('-');
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      if (month != null && day != null && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }
    }
    
    // Try to extract month and day from natural language
    final monthNames = {
      'january': '01', 'jan': '01', 'february': '02', 'feb': '02', 'march': '03', 'mar': '03',
      'april': '04', 'apr': '04', 'may': '05', 'june': '06', 'jun': '06', 'july': '07', 'jul': '07',
      'august': '08', 'aug': '08', 'september': '09', 'sep': '09', 'october': '10', 'oct': '10',
      'november': '11', 'nov': '11', 'december': '12', 'dec': '12'
    };
    
    for (final entry in monthNames.entries) {
      if (cleaned.contains(entry.key)) {
        // Look for a day number near the month
        final dayMatch = RegExp(r'\b(\d{1,2})\b').firstMatch(text);
        if (dayMatch != null) {
          final day = int.tryParse(dayMatch.group(1)!);
          if (day != null && day >= 1 && day <= 31) {
            return '${entry.value}-${day.toString().padLeft(2, '0')}';
          }
        }
      }
    }
    
    // If we can't parse it, return empty string
    debugPrint('Could not parse birthday: "$birthdayText"');
    return '';
  }

  Future<void> _enhancePersonDataWithAI(ExtractedPerson person) async {
    try {
      final requestBody = {
        'responses': _interviewData.responses.map((r) => r.toJson()).toList(),
        'task': 'extract_family_friend_data',
      };

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/process-interview-responses'),
        headers: {
          'Authorization': 'Bearer $_idToken',
          'X-User-ID': _aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['extracted_person'] != null) {
          final enhanced = ExtractedPerson.fromJson(data['extracted_person']);
          // Merge AI enhancements with existing data
          if (enhanced.name.isNotEmpty) person.name = enhanced.name;
          if (enhanced.relationship.isNotEmpty) person.relationship = enhanced.relationship;
          if (enhanced.about.isNotEmpty) person.about = enhanced.about;
          if (enhanced.birthday.isNotEmpty) person.birthday = enhanced.birthday;
        }
      }
    } catch (e) {
      print('AI enhancement failed: $e');
      // Continue with manual extraction
    }
  }

  Future<void> stopInterview() async {
    _isActive = false;
    _isPaused = false;
    _isListening = false;
    _isConfirming = false;
    _silenceTimer?.cancel();
    await _tts.stop();
    
    // Resume wake word service when stopping interview
    debugPrint('[FamilyFriendsInterview] Resuming wake word service after interview stop');
    await WakeWordService.resumeWakeWordService();
    
    _updateStatus('Interview stopped', 'info');
    notifyListeners();
  }

  void _updateStatus(String message, String type) {
    _status = message;
    _statusType = type;
    notifyListeners();
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _tts.stop();
    
    // Resume wake word service as safety fallback
    debugPrint('[FamilyFriendsInterview] Resuming wake word service in dispose (safety fallback)');
    WakeWordService.resumeWakeWordService();
    
    super.dispose();
  }
}