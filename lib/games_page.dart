import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/environment_config.dart';
import 'services/user_settings_provider.dart';
import 'services/pictogram_service.dart';
import 'services/wake_word_service.dart';
import 'services/audio_device_provider.dart';
import 'services/audio_device_service.dart';
import 'tap_interface_page.dart';

class GamesPage extends StatefulWidget {
  final String? fromInterface; // 'auditory' or 'tap'
  final String idToken;
  final String aacUserId;
  final Future<void> Function(
    String text, {
    String routing,
    int? speechRate,
    bool showSpeechBubble,
  })?
  announceFunction;
  final String? initialGame; // Auto-start a specific game (e.g., 'guess_who')

  const GamesPage({
    Key? key,
    this.fromInterface,
    required this.idToken,
    required this.aacUserId,
    this.announceFunction,
    this.initialGame,
  }) : super(key: key);

  @override
  _GamesPageState createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  bool _skipTtsStopOnDispose = false;
  // Game state
  String _currentView =
      'menu'; // 'menu', 'role_selection', 'category_selection', 'ready', 'playing', 'action_selection', 'guessing', 'response_selection'
  String? _selectedGame;
  bool _isExiting = false;
  bool _isWaitPromptActive = false;
  String? _lastSelectionViewForScan;
  bool _deferSelectionScanning = false;
  String? _role; // 'ask' or 'answer'
  String? _category;
  String? _selectedItem;
  String? _currentQuestion;
  String? _currentGuess;
  String _currentResponseType = ''; // 'question_response' or 'guess_response'
  List<Map<String, dynamic>> _responseOptions = [];
  List<Map<String, String>> _askedQuestions = [];
  List<String> _previousGuesses = [];
  int _questionCount = 0;
  int _guessCount = 0;
  List<String> _currentOptions = [];
  Map<String, String> _questionData =
      {}; // Maps summary -> full question for 'question' type
  String _currentOptionType =
      ''; // 'question', 'guess', 'select', 'response', 'finished'
  String _statusText = '';
  bool _isLoading = false;

  // Question history for display
  List<Map<String, String>> _questionHistory =
      []; // [{question: "...", answer: "..."}]

  // Settings from backend
  int _maxQuestions = 20;
  int _maxGuesses = 5;
  int _scanDelay = 3500;
  // ignore: unused_field
  String _wakeWord = 'Hey Bravo';
  bool _enableScanning = false;
  bool _waitForSwitchToScan = false; // Wait for switch before starting scan

  // Keyboard/Switch handling
  final FocusNode _focusNode = FocusNode();
  final ScrollController _menuScrollController = ScrollController();
  final ScrollController _optionsScrollController = ScrollController();
  final ScrollController _historyScrollController = ScrollController();
  bool _isSpacebarDown = false;

  // Speech recognition
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _listeningFor =
      ''; // 'ready', 'yes_no', 'yes_no_guess', 'wake_word', 'intent', 'player_question', 'player_guess', 'story_wake_word', 'story_partner_question'
  String _realtimeTranscript = ''; // Real-time transcription display
  bool _isProcessingSpeechResult = false; // Guard against duplicate callbacks
  String _lastProcessedTranscript =
      ''; // Track last processed to avoid duplicates
  int _ignoreSpeechInputUntilMs =
      0; // Ignore recognizer callbacks during TTS bleed-through windows
  bool _isAnnouncementActive = false;
  Timer? _listeningRestartTimer;
  bool _isReadyTransitionInProgress =
      false; // Prevent duplicate ready transitions
  bool _isWakeWordTransitionInProgress =
      false; // Prevent duplicate wake-word transitions
  bool _isIntentTransitionInProgress =
      false; // Prevent duplicate intent transitions
  bool _isQuestionTransitionInProgress =
      false; // Prevent duplicate question transitions
  bool _isGuessTransitionInProgress =
      false; // Prevent duplicate guess transitions
  int _lastGuessResultAtMs = 0; // Deduplicate rapid guess result handling
  Timer? _guessNoInputTimer;
  int _guessNoInputDeadlineMs = 0;
  Timer? _playerGuessCommitTimer;
  String _pendingPlayerGuessTranscript = '';
  Timer? _guessClueSilenceTimer;
  String _lastPartialGuessClueTranscript = '';
  bool _guessClueDetectedFirstSpeech = false;
  Timer? _storyQuestionCommitTimer;
  String _pendingStoryQuestionTranscript = '';

  // Flutter TTS for scanning audio
  late FlutterTts _flutterTts;

  // Scanning
  int _currentScanIndex = 0;
  Timer? _scanTimer;
  bool _isScanning = false;
  bool _scanningWaitingForSwitch =
      false; // Flag for when waiting for switch to start scanning
  bool _isAnnouncingScanningPrompt =
      false; // Track if announcing during scanning prompts (for Tab interrupt)

  // Speech bubble overlay
  bool _showSpeechBubble = false;
  String _speechBubbleText = '';
  Timer? _speechBubbleTimer;

  // Guess Game state (Guess Who / Guess Where / Guess What)
  static const Map<String, Map<String, String>> _guessGameConfigs = {
    'who': {
      'title': 'Guess Who',
      'itemType': 'person',
      'itemTypePlural': 'people',
      'apiEndpoint': 'guess-who',
    },
    'where': {
      'title': 'Guess Where',
      'itemType': 'place',
      'itemTypePlural': 'places',
      'apiEndpoint': 'guess-where',
    },
    'what': {
      'title': 'Guess What',
      'itemType': 'thing',
      'itemTypePlural': 'things',
      'apiEndpoint': 'guess-what',
    },
  };
  String? _guessGameType; // 'who', 'where', 'what'
  String? _guessMode; // 'mode-a' or 'mode-b'
  String? _guessCategory;
  String? _guessSelectedPerson;
  List<String> _guessCluesGiven = [];
  List<dynamic> _guessCluesAvailable = [];
  int _guessGuessesRemaining = 3;
  List<String> _guessGuessesAttempted = [];
  String? _guessCurrentGuess;
  List<String> _guessPeopleOptions = [];
  List<String> _guessGuessOptionsAll = [];
  List<String> _guessGuessOptionsShown = [];
  List<Map<String, dynamic>> _guessResponseOptions = [];
  Map<String, String> _guessClueTextMap = {};
  Map<String, dynamic> _guessGameResult = {};
  bool _guessModeBListeningForClue = false;
  bool _isGuessConfirmationInProgress =
      false; // Guard against duplicate yes/no confirmation

  bool get _isGuessGame => _selectedGame?.startsWith('guess_') == true;
  Map<String, String> get _guessConfig =>
      _guessGameConfigs[_guessGameType] ?? _guessGameConfigs['who']!;
  String _getGuessApiUrl(String endpoint) =>
      '${EnvironmentConfig.apiBaseUrl}/api/${_guessConfig['apiEndpoint']}/$endpoint';

  // Tic-Tac-Toe state
  List<String> _tttBoard = List.filled(9, ''); // 9 cells, '' = empty
  String _tttPlayer1Symbol = 'X';
  String _tttPlayer2Symbol = 'O';
  bool _tttIsPlayer1Turn = true;
  bool _tttGameOver = false;
  String? _tttWinner; // 'player1', 'player2', or 'tie'
  int _tttScanIndex = 0; // scanning index for available cells only
  Timer? _tttScanTimer;
  bool _tttIsScanning = false;
  static const List<String> _tttPositionNames = [
    'top-left',
    'top-center',
    'top-right',
    'center-left',
    'center',
    'center-right',
    'bottom-left',
    'bottom-center',
    'bottom-right',
  ];

  // Hangman state
  String? _hmMode; // 'mode-a' (I guess) or 'mode-b' (You guess)
  String? _hmCategory;
  String? _hmWord; // The secret word (known in Mode B, null in Mode A)
  int _hmWordLength = 0; // Number of letters
  List<dynamic> _hmRevealedLetters =
      []; // Mode A: false or letter char; Mode B: bool per position
  List<String> _hmGuessedLetters = []; // Letters guessed so far
  int _hmWrongGuesses = 0;
  static const int _hmMaxWrong = 6;
  List<String> _hmWordOptions = []; // LLM-generated word options for Mode B
  List<String> _hmPreviousWords =
      []; // Track previously shown words for "Something Else"
  String? _hmCurrentGuessedLetter; // Mode A: letter awaiting yes/no
  String _hmModeAPhase =
      ''; // 'waitingReady', 'waitingLetterCount', 'playing', 'waitingYesNo', 'waitingPositions'
  String?
  _hmProcessedYesNoForLetter; // Track which letter we've processed yes/no for
  Set<int> _hmSelectedPositions =
      {}; // Mode A: positions selected for current letter
  bool _hmGameOver = false;
  bool _hmPlayerWon = false;

  // Hangman scanning
  int _hmAlphabetScanIndex = 0;
  Timer? _hmAlphabetScanTimer;
  bool _hmIsAlphabetScanning = false;
  int? _hmLastProcessedLetterCount; // Track to prevent double-processing

  // Hangman custom categories
  bool _showHmCategoriesDialog = false;
  bool _showHmPinDialog = false;
  final TextEditingController _hmPinController = TextEditingController();
  final TextEditingController _hmCategoriesController = TextEditingController();
  String _hmPinError = '';
  List<String> _hmDefaultCategories = [];
  List<String> _hmCustomCategories = [];

  // Story Builder state
  List<Map<String, String>> _storyTranscript = [];
  String _storyPendingQuestion = '';
  List<Map<String, dynamic>> _storyCurrentOptions = [];
  List<Map<String, dynamic>> _storyLibrary = [];
  String? _storySelectedStoryId;
  String _storyCurrentTitle = '';
  String _storyCurrentText = '';
  bool _storyEditMode = false;
  bool _storyVerifiedAdminPin = false;
  final TextEditingController _storyPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    debugPrint(
      'Games page: initState called - initializing speech and loading settings',
    );
    _flutterTts = FlutterTts();
    _initializeSpeech();
    _loadSettings();
    // Request focus immediately on a fresh frame
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        debugPrint('Games: initState post-frame - requesting focus again');
        _focusNode.requestFocus();
        FocusScope.of(context).requestFocus(_focusNode);
        // Auto-start a specific game if requested (e.g., from !jokes special page)
        if (widget.initialGame != null) {
          _handleInitialGame(widget.initialGame!);
        }
      }
    });
  }

  void _handleInitialGame(String game) {
    final gameLower = game.toLowerCase();
    debugPrint('Games page: Auto-starting initial game: $gameLower');
    if (gameLower == 'guess_who' || gameLower == 'guess-who') {
      _startGuessGame('who');
    } else if (gameLower == 'guess_where' || gameLower == 'guess-where') {
      _startGuessGame('where');
    } else if (gameLower == 'guess_what' || gameLower == 'guess-what') {
      _startGuessGame('what');
    } else if (gameLower == '20_questions' || gameLower == '20questions') {
      _startTwentyQuestions();
    } else if (gameLower == 'story_builder' || gameLower == 'story-builder') {
      _startStoryBuilder();
    } else {
      debugPrint('Games page: Unknown initial game: $game');
    }
  }

  @override
  void didUpdateWidget(GamesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restore focus whenever widget is updated (e.g., from parent rebuild)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        debugPrint('Games: didUpdateWidget post-frame - restoring focus');
        _focusNode.requestFocus();
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void dispose() {
    _stopScanning();
    _tttStopScanning();
    _hmStopAlphabetScanning();
    _stopListening(resumeWakeWordService: true);
    _focusNode.dispose();
    _menuScrollController.dispose();
    _optionsScrollController.dispose();
    _historyScrollController.dispose();
    _storyPinController.dispose();
    _speech.stop();
    if (!_skipTtsStopOnDispose) {
      _flutterTts.stop();
    }
    _speechBubbleTimer?.cancel();
    _listeningRestartTimer?.cancel();
    _guessNoInputTimer?.cancel();
    _playerGuessCommitTimer?.cancel();
    _guessClueSilenceTimer?.cancel();
    _storyQuestionCommitTimer?.cancel();
    super.dispose();
  }

  void _scheduleFastListeningRestart(String source) {
    if (!mounted || _isExiting) return;
    final isGuessModeAPlayerGuess =
        _isGuessGame &&
        _listeningFor == 'player_guess' &&
        !_guessModeBListeningForClue;
    if (!isGuessModeAPlayerGuess && (!_isListening || _listeningFor.isEmpty))
      return;
    if (_listeningFor.isEmpty) return;
    if (_isAnnouncementActive) return;

    _listeningRestartTimer?.cancel();
    _listeningRestartTimer = Timer(const Duration(seconds: 1), () async {
      if (!mounted || _isExiting) return;
      final isGuessModeAPlayerGuessTimer =
          _isGuessGame &&
          _listeningFor == 'player_guess' &&
          !_guessModeBListeningForClue;
      if (!isGuessModeAPlayerGuessTimer &&
          (!_isListening || _listeningFor.isEmpty))
        return;
      if (_listeningFor.isEmpty) return;
      if (_isAnnouncementActive) return;

      if (_isGuessGame &&
          !_guessModeBListeningForClue &&
          _listeningFor == 'player_guess' &&
          _guessNoInputDeadlineMs > 0 &&
          DateTime.now().millisecondsSinceEpoch >= _guessNoInputDeadlineMs) {
        debugPrint(
          'Games page: [GUESS_TIMEOUT] No input window expired during restart scheduler',
        );
        await _handleGuessNoInputTimeout();
        return;
      }

      debugPrint(
        'Games page: [FAST_RESTART] Restarting listener from $source for $_listeningFor (speech.isListening=${_speech.isListening})',
      );
      await _startListening(_listeningFor);
    });
  }

  void _startGuessNoInputTimeoutWindow() {
    _guessNoInputTimer?.cancel();
    _guessNoInputDeadlineMs =
        DateTime.now().millisecondsSinceEpoch +
        const Duration(seconds: 60).inMilliseconds;
    _guessNoInputTimer = Timer(const Duration(seconds: 60), () async {
      await _handleGuessNoInputTimeout();
    });
  }

  void _clearGuessNoInputTimeoutWindow() {
    _guessNoInputTimer?.cancel();
    _guessNoInputTimer = null;
    _guessNoInputDeadlineMs = 0;
  }

  void _schedulePlayerGuessCommit(String transcript) {
    if (!_isGuessGame || _guessModeBListeningForClue) return;

    final cleanedTranscript = transcript.trim();
    if (cleanedTranscript.isEmpty) return;

    _pendingPlayerGuessTranscript = cleanedTranscript;
    _playerGuessCommitTimer?.cancel();
    _playerGuessCommitTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || _isExiting) return;
      if (!_isListening || _listeningFor != 'player_guess') return;
      if (_isGuessTransitionInProgress) return;

      final committedTranscript = _pendingPlayerGuessTranscript.trim();
      if (committedTranscript.isEmpty) return;

      debugPrint(
        'Games page: [PLAYER_GUESS_COMMIT] Committing partial transcript: "$committedTranscript"',
      );
      _isGuessTransitionInProgress = true;
      _isProcessingSpeechResult = true;
      _lastProcessedTranscript = committedTranscript;
      _speech.stop();
      _handleSpeechResult(committedTranscript, 'player_guess');
    });
  }

  void _clearPlayerGuessCommitTimer() {
    _playerGuessCommitTimer?.cancel();
    _playerGuessCommitTimer = null;
    _pendingPlayerGuessTranscript = '';
  }

  void _resetGuessClueSilenceTimer() {
    if (!_isGuessGame || !_guessModeBListeningForClue) return;

    _guessClueSilenceTimer?.cancel();
    _guessClueSilenceTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isExiting) return;
      if (!_isListening || _listeningFor != 'player_guess') return;
      if (!_guessModeBListeningForClue || _isGuessTransitionInProgress) return;

      final clueTranscript = _lastPartialGuessClueTranscript.trim();
      if (clueTranscript.isEmpty) return;

      debugPrint(
        'Games page: [GUESS_CLUE_COMMIT] Committing clue after silence: "$clueTranscript"',
      );
      _isGuessTransitionInProgress = true;
      _isProcessingSpeechResult = true;
      _lastProcessedTranscript = clueTranscript;
      _speech.stop();
      _handleSpeechResult(clueTranscript, 'player_guess');
    });
  }

  void _clearGuessClueSilenceTimer() {
    _guessClueSilenceTimer?.cancel();
    _guessClueSilenceTimer = null;
    _lastPartialGuessClueTranscript = '';
    _guessClueDetectedFirstSpeech = false;
  }

  void _scheduleStoryQuestionCommit(String transcript) {
    final cleanedTranscript = transcript.trim();
    if (cleanedTranscript.isEmpty) return;

    _pendingStoryQuestionTranscript = cleanedTranscript;
    _storyQuestionCommitTimer?.cancel();
    _storyQuestionCommitTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || _isExiting) return;
      if (!_isListening || _listeningFor != 'story_partner_question') return;
      if (_isQuestionTransitionInProgress) return;

      final committedTranscript = _pendingStoryQuestionTranscript.trim();
      if (committedTranscript.isEmpty) return;

      debugPrint(
        'Games page: [STORY_QUESTION_COMMIT] Committing partial transcript: "$committedTranscript"',
      );
      _isQuestionTransitionInProgress = true;
      _isProcessingSpeechResult = true;
      _lastProcessedTranscript = committedTranscript;
      _speech.stop();
      _handleSpeechResult(committedTranscript, 'story_partner_question');
    });
  }

  void _clearStoryQuestionCommitTimer() {
    _storyQuestionCommitTimer?.cancel();
    _storyQuestionCommitTimer = null;
    _pendingStoryQuestionTranscript = '';
  }

  Future<void> _handleGuessNoInputTimeout() async {
    if (!mounted || _isExiting) return;
    if (!_isGuessGame || _guessModeBListeningForClue) return;
    if (_guessNoInputDeadlineMs == 0) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _guessNoInputDeadlineMs) return;

    debugPrint(
      'Games page: [GUESS_TIMEOUT] No input for 60 seconds, returning to wake word mode',
    );
    _clearGuessNoInputTimeoutWindow();
    _isGuessTransitionInProgress = false;
    _stopListening();
    await _speak(
      "I didn't hear anything, please say $_wakeWord again to make a guess",
    );

    if (!mounted || _isExiting) return;
    _guessModeBListeningForClue = false;
    setState(() {
      _statusText = 'Say "$_wakeWord" to make a guess.';
    });

    await _startListeningWithGuard(
      'wake_word',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
  }

  bool _usesDictationListenMode(String listeningFor) {
    return listeningFor == 'player_question' ||
        listeningFor == 'player_guess' ||
        listeningFor == 'story_partner_question' ||
        listeningFor == 'hm_letter_count';
  }

  Future<void> _initializeSpeech() async {
    try {
      _speech = stt.SpeechToText();
      bool available = await _speech.initialize(
        onError: (error) {
          debugPrint('Speech recognition error: $error');
          // Auto-retry for hangman letter listening on error_no_match
          // Single letters are hard for speech recognition, so retry automatically
          if (_listeningFor == 'hm_letter' &&
              error.errorMsg == 'error_no_match' &&
              mounted) {
            debugPrint(
              'Games page: [HM_LETTER] error_no_match, prompting retry',
            );
            _speak("I didn't catch that. Say the letter again.").then((_) {
              if (mounted && _listeningFor == 'hm_letter') {
                Future.delayed(Duration(milliseconds: 300), () {
                  if (mounted) _startListening('hm_letter');
                });
              }
            });
            return;
          }

          if (_isGuessGame &&
              _listeningFor == 'player_guess' &&
              !_guessModeBListeningForClue) {
            _scheduleFastListeningRestart('guess_error:${error.errorMsg}');
            return;
          }

          if (_isListening && _listeningFor.isNotEmpty) {
            _scheduleFastListeningRestart('error:${error.errorMsg}');
          }
        },
        onStatus: (status) {
          debugPrint('Speech recognition status: $status');
          if ((status == 'done' || status == 'notListening') &&
              _isGuessGame &&
              _listeningFor == 'player_guess' &&
              !_guessModeBListeningForClue) {
            _scheduleFastListeningRestart('guess_status:$status');
            return;
          }

          if ((status == 'done' || status == 'notListening') &&
              _isListening &&
              _listeningFor.isNotEmpty) {
            _scheduleFastListeningRestart('status:$status');
          }
        },
      );
      debugPrint('Games page: Speech recognition available: $available');
      if (!available) {
        debugPrint('Games page: WARNING - Speech recognition not available!');
      }
    } catch (e) {
      debugPrint('Games page: Error initializing speech recognition: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      // Get settings from provider
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );

      setState(() {
        _scanDelay = settingsProvider.settings?.scanDelay ?? 3500;
        _wakeWord =
            '${settingsProvider.settings?.wakeWordInterjection ?? 'Hey'} ${settingsProvider.settings?.wakeWordName ?? 'Bravo'}';
        _maxQuestions = 20; // Will be loaded from backend later
        _maxGuesses = 5; // Will be loaded from backend later
        _enableScanning =
            (settingsProvider.settings?.enableAuditoryScanning ?? false) &&
            widget.fromInterface == 'auditory';
        _waitForSwitchToScan =
            settingsProvider.settings?.waitForSwitchToScan ?? false;
      });

      debugPrint(
        'Games page settings: enableScanning=$_enableScanning, waitForSwitch=$_waitForSwitchToScan, scanDelay=$_scanDelay',
      );
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _startListening(String listeningFor) async {
    debugPrint(
      'Games page: [LISTEN_START] Attempting to start listening for: $listeningFor',
    );

    // CRITICAL: Completely stop and reset WakeWordService to release the speech recognizer
    debugPrint(
      'Games page: [LISTEN_START] Stopping WakeWordService completely to avoid speech recognizer conflict...',
    );
    await WakeWordService.forceStopAndReset();

    // CRITICAL: After stopping, prevent auto-restart (set AFTER forceStopAndReset to override any flags it sets)
    WakeWordService.wakeWordShouldBeActive = false; // Prevent auto-restart
    debugPrint(
      'Games page: [LISTEN_START] WakeWordService stopped and disabled successfully',
    );

    // Check if speech is available
    if (!_speech.isAvailable) {
      debugPrint(
        'Games page: [LISTEN_ERROR] Speech recognition not available!',
      );
      setState(() {
        _isListening = false;
        _statusText = 'Speech recognition not available';
      });
      return;
    }

    debugPrint(
      'Games page: [LISTEN_OK] Speech is available, checking if already listening...',
    );

    // Stop any existing listening
    if (_isListening) {
      debugPrint('Games page: [LISTEN] Already listening, stopping first...');
      _speech.stop();
    }

    // Set listening state BEFORE calling listen()
    setState(() {
      _isListening = true;
      _listeningFor = listeningFor;
      // Only clear transcript when starting fresh (not when auto-restarting for 'ready')
      if (_realtimeTranscript.isEmpty || listeningFor != 'ready') {
        _realtimeTranscript = '';
      }
    });

    // Reset processing flags for new listening session
    _isProcessingSpeechResult = false;
    _lastProcessedTranscript = '';
    if (listeningFor == 'ready') {
      _isReadyTransitionInProgress = false;
    } else if (listeningFor == 'wake_word') {
      _isWakeWordTransitionInProgress = false;
    } else if (listeningFor == 'intent') {
      _isIntentTransitionInProgress = false;
    } else if (listeningFor == 'player_question' ||
        listeningFor == 'story_partner_question') {
      _isQuestionTransitionInProgress = false;
    } else if (listeningFor == 'player_guess') {
      _isGuessTransitionInProgress = false;
      if (_guessModeBListeningForClue) {
        _guessClueDetectedFirstSpeech = false;
        _lastPartialGuessClueTranscript = '';
        _guessClueSilenceTimer?.cancel();
      }
    }

    debugPrint(
      'Games page: [LISTEN] UI state updated: _isListening=true, _realtimeTranscript=""',
    );
    debugPrint('Games page: [LISTEN] Now calling _speech.listen()...');

    final useDictationMode = _usesDictationListenMode(listeningFor);

    // Set pause duration based on what we're listening for
    final pauseDuration = (listeningFor == 'story_partner_question')
        ? Duration(seconds: 3)
        : (listeningFor == 'player_question' ||
              listeningFor == 'yes_no' ||
              listeningFor == 'yes_no_guess' ||
              listeningFor == 'hm_letter_count' ||
              listeningFor == 'hm_yes_no')
        ? Duration(seconds: 8)
        : (listeningFor == 'hm_letter')
        ? Duration(seconds: 5)
        : Duration(seconds: 60);

    debugPrint(
      'Games page: [LISTEN] Using pauseFor: ${pauseDuration.inSeconds}s for mode: $listeningFor',
    );

    try {
      _speech.listen(
        onResult: (result) {
          if (_isAnnouncementActive) {
            debugPrint(
              'Games page: [RESULT_IGNORED] Ignoring transcript during active announcement',
            );
            return;
          }

          if (DateTime.now().millisecondsSinceEpoch <
              _ignoreSpeechInputUntilMs) {
            debugPrint(
              'Games page: [RESULT_IGNORED] Ignoring transcript during TTS guard window',
            );
            return;
          }

          debugPrint(
            'Games page: [RESULT] Speech callback fired! final=${result.finalResult}, words="${result.recognizedWords.toLowerCase()}"',
          );

          final transcript = result.recognizedWords.toLowerCase();

          // Update real-time transcript for display
          debugPrint(
            'Games page: [UPDATE_TRANSCRIPT] New speech: "$transcript" (final=${result.finalResult})',
          );
          setState(() {
            if (result.finalResult && listeningFor == 'ready') {
              // For 'ready' mode, accumulate final results to show listening progress
              if (_realtimeTranscript.isNotEmpty &&
                  !_realtimeTranscript.endsWith(' ')) {
                _realtimeTranscript += ' ... ';
              }
              _realtimeTranscript += transcript;
            } else {
              // For other modes or partial results, just show current utterance
              _realtimeTranscript = transcript;
            }
          });
          debugPrint(
            'Games page: [UPDATE_TRANSCRIPT] Full transcript: "$_realtimeTranscript"',
          );

          // Check for match on BOTH partial and final results for faster response
          // Guard against duplicate callbacks (partial + final) using both flag and transcript check
          if (_isProcessingSpeechResult ||
              _lastProcessedTranscript == transcript) {
            debugPrint(
              'Games page: [DUPLICATE] Already processing or processed this transcript, ignoring',
            );
            return;
          }

          if (listeningFor == 'story_wake_word' &&
              _matchesWakeWord(transcript)) {
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED story wake word in transcript!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'story_partner_question') {
            if (transcript.isNotEmpty) {
              if (result.finalResult) {
                debugPrint(
                  'Games page: [MATCH_FOUND] DETECTED story partner question (final)',
                );
                _isQuestionTransitionInProgress = true;
                _isProcessingSpeechResult = true;
                _lastProcessedTranscript = transcript;
                _speech.stop();
                _handleSpeechResult(transcript, listeningFor);
              } else {
                _scheduleStoryQuestionCommit(transcript);
              }
            }
          } else if (listeningFor == 'wake_word' &&
              _matchesWakeWord(transcript)) {
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED wake word in transcript!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'intent' &&
              (transcript.contains('question') ||
                  transcript.contains('guess'))) {
            if (_isIntentTransitionInProgress) {
              debugPrint(
                'Games page: [INTENT] Transition already in progress, ignoring transcript',
              );
              return;
            }
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED intent in transcript!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'player_question') {
            if (!_isQuestionTransitionInProgress &&
                result.finalResult &&
                transcript.isNotEmpty) {
              debugPrint('Games page: [MATCH_FOUND] DETECTED player question');
              _isQuestionTransitionInProgress = true;
              _isProcessingSpeechResult = true;
              _lastProcessedTranscript = transcript;
              _speech.stop();
              _handleSpeechResult(transcript, listeningFor);
            }
          } else if (listeningFor == 'player_guess') {
            if (!_isGuessTransitionInProgress && transcript.isNotEmpty) {
              if (_guessModeBListeningForClue) {
                final clueTranscript = transcript.trim();
                if (clueTranscript.isNotEmpty) {
                  if (!_guessClueDetectedFirstSpeech) {
                    _guessClueDetectedFirstSpeech = true;
                  }
                  _lastPartialGuessClueTranscript = clueTranscript;
                  _resetGuessClueSilenceTimer();
                }
              } else if (result.finalResult) {
                debugPrint(
                  'Games page: [MATCH_FOUND] DETECTED player guess (final)',
                );
                _isGuessTransitionInProgress = true;
                _isProcessingSpeechResult = true;
                _lastProcessedTranscript = transcript;
                _speech.stop();
                _handleSpeechResult(transcript, listeningFor);
              } else {
                _schedulePlayerGuessCommit(transcript);
              }
            }
          } else if (listeningFor == 'ready' && transcript.contains('ready')) {
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED "ready" in transcript!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'yes_no' &&
              (transcript.contains('yes') || transcript.contains('no'))) {
            // Immediate response for yes/no answers
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED "yes" or "no" in transcript!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'yes_no_guess' &&
              (transcript.contains('yes') || transcript.contains('no'))) {
            // Immediate response for yes/no guess verification
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED "yes" or "no" for guess in transcript!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'hm_letter_count') {
            // Hangman Mode A: listen for letter count (process immediately on partial results)
            final count = _hmParseLetterCount(transcript);
            if (count != null && count > 0 && count <= 30) {
              debugPrint(
                'Games page: [MATCH_FOUND] DETECTED letter count: $count',
              );
              _isProcessingSpeechResult = true;
              _lastProcessedTranscript = transcript;
              _speech.stop();
              _handleSpeechResult(transcript, listeningFor);
            }
          } else if (listeningFor == 'hm_yes_no' &&
              (transcript.contains('yes') || transcript.contains('no'))) {
            // Hangman Mode A: yes/no for letter guess
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED yes/no for hangman letter!',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (listeningFor == 'hm_letter' &&
              result.finalResult &&
              transcript.isNotEmpty) {
            // Hangman Mode B: capture a letter from voice
            debugPrint(
              'Games page: [MATCH_FOUND] DETECTED hangman letter guess: "$transcript"',
            );
            _isProcessingSpeechResult = true;
            _lastProcessedTranscript = transcript;
            _speech.stop();
            _handleSpeechResult(transcript, listeningFor);
          } else if (result.finalResult && listeningFor == 'ready') {
            // For 'ready' mode, don't restart - the listener will keep running
            debugPrint(
              'Games page: [FINAL_NO_MATCH] Final result without "ready": "$transcript", listener continues...',
            );
          } else {
            // For 'ready' mode, ignore all non-matching partial results and keep listening
            debugPrint(
              'Games page: [NO_MATCH] Heard "$transcript", continuing to listen for match...',
            );
          }
        },
        listenFor: Duration(seconds: 60), // Listen for up to 1 minute
        pauseFor: pauseDuration,
        partialResults: true, // Show partial results in real-time
        cancelOnError:
            listeningFor !=
            'hm_letter', // Don't cancel on error for letter mode (single letters often get error_no_match)
        listenMode: useDictationMode
            ? stt.ListenMode.dictation
            : stt.ListenMode.confirmation,
        localeId: useDictationMode ? 'en_US' : null,
        onSoundLevelChange: (level) {
          debugPrint('Games page: [SOUND] Sound level: $level');
        },
      );
      debugPrint('Games page: [LISTEN] _speech.listen() call completed');
    } catch (e) {
      debugPrint('Games page: [EXCEPTION] Exception in _speech.listen(): $e');
      setState(() {
        _isListening = false;
        _statusText = 'Error starting speech recognition: $e';
      });
      return;
    }

    // Restarts are handled via onStatus/onError fast-restart scheduler.
  }

  void _suppressSpeechInputFor(Duration duration) {
    _ignoreSpeechInputUntilMs =
        DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
  }

  Future<void> _startListeningWithGuard(
    String listeningFor, {
    Duration preListenDelay = const Duration(milliseconds: 1400),
    Duration ignoreWindow = const Duration(milliseconds: 3500),
  }) async {
    if (preListenDelay.inMilliseconds > 0) {
      await Future.delayed(preListenDelay);
    }
    if (!mounted || _isExiting) return;
    _suppressSpeechInputFor(ignoreWindow);
    await _startListening(listeningFor);
  }

  void _stopListening({bool resumeWakeWordService = false}) {
    _listeningRestartTimer?.cancel();
    if (_listeningFor == 'player_guess') {
      _clearGuessNoInputTimeoutWindow();
      _clearPlayerGuessCommitTimer();
      _clearGuessClueSilenceTimer();
    } else if (_listeningFor == 'story_partner_question') {
      _clearStoryQuestionCommitTimer();
    }
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
        _listeningFor = '';
      });
    }
    // Reset processing flags when stopping
    _isProcessingSpeechResult = false;
    _lastProcessedTranscript = '';
    if (resumeWakeWordService) {
      debugPrint('Games page: [LISTEN_STOP] Resuming WakeWordService...');
      WakeWordService.resumeWakeWordService();
    }
  }

  Future<void> _handleSpeechResult(
    String transcript, [
    String? listeningForOverride,
  ]) async {
    final listeningMode = listeningForOverride ?? _listeningFor;
    debugPrint(
      'Games page: Speech result: "$transcript" (listening for: $listeningMode)',
    );

    if (listeningMode == 'ready' && _isReadyTransitionInProgress) {
      debugPrint(
        'Games page: [READY] Transition already in progress, ignoring duplicate ready result',
      );
      return;
    }

    if (listeningMode == 'wake_word') {
      if (_matchesWakeWord(transcript)) {
        debugPrint('Games page: MATCHED wake word');
        if (_selectedGame == 'hangman' && _hmMode == 'mode-b') {
          await _hmHandleWakeWordForModeB();
        } else if (_isGuessGame) {
          await _handleGuessWakeWordDetected();
        } else {
          await _handleWakeWordDetected();
        }
      }
      return;
    }

    if (listeningMode == 'story_wake_word') {
      if (_matchesWakeWord(transcript)) {
        await _handleStoryWakeWordDetected();
      }
      return;
    }

    if (listeningMode == 'story_partner_question') {
      await _handleStoryPartnerQuestion(transcript);
      return;
    }

    if (listeningMode == 'intent') {
      if (transcript.contains('question')) {
        await _handlePlayerIntent('question');
      } else if (transcript.contains('guess')) {
        await _handlePlayerIntent('guess');
      } else {
        await _speak('Do you have a question or guess?');
        Future.delayed(Duration(seconds: 2), () async {
          if (_listeningFor == 'intent') await _startListening('intent');
        });
      }
      return;
    }

    if (listeningMode == 'player_question') {
      await _handlePlayerQuestion(transcript);
      return;
    }

    if (listeningMode == 'player_guess') {
      if (_isGuessGame) {
        if (_guessModeBListeningForClue) {
          await _handleGuessClueHeard(transcript);
        } else {
          await _handleGuessPlayerGuess(transcript);
        }
      } else {
        await _handlePlayerGuess(transcript);
      }
      return;
    }

    if (listeningMode == 'ready' && transcript.contains('ready')) {
      debugPrint('Games page: MATCHED "ready", proceeding...');
      _isReadyTransitionInProgress = true;
      _stopListening();
      if (_selectedGame == 'hangman') {
        await _hmHandleReady();
      } else if (_isGuessGame) {
        await _handleGuessReadyHeard();
      } else {
        _speak('Excellent! Give me a moment to pick a question');
        await _proceedAfterReady();
      }
    } else if (listeningMode == 'ready') {
      // No match for "ready" - keep listening
      debugPrint('Games page: No match for "ready" in: "$transcript"');
      _speak("I didn't hear 'ready'. Please try again.");
      Future.delayed(Duration(seconds: 2), () async {
        if (_listeningFor == 'ready') await _startListening('ready');
      });
    } else if (listeningMode == 'yes_no') {
      if (transcript.contains('yes')) {
        debugPrint('Games page: MATCHED "yes"');
        _stopListening();
        _recordAnswer('yes');
      } else if (transcript.contains('no')) {
        debugPrint('Games page: MATCHED "no"');
        _stopListening();
        _recordAnswer('no');
      } else {
        debugPrint('Games page: No match for yes/no in: "$transcript"');
        _speak("I didn't catch that. Please say yes or no.");
        Future.delayed(Duration(seconds: 2), () async {
          if (_listeningFor == 'yes_no') await _startListening('yes_no');
        });
      }
    } else if (listeningMode == 'yes_no_guess') {
      // Handle guess verification with yes/no
      if (transcript.contains('yes')) {
        debugPrint('Games page: MATCHED "yes" for guess');
        _stopListening();
        if (_isGuessGame) {
          _handleGuessModeBConfirmation(true);
        } else {
          _handleGuessResult(true);
        }
      } else if (transcript.contains('no')) {
        debugPrint('Games page: MATCHED "no" for guess');
        _stopListening();
        if (_isGuessGame) {
          _handleGuessModeBConfirmation(false);
        } else {
          _handleGuessResult(false);
        }
      } else {
        debugPrint('Games page: No match for yes/no in guess: "$transcript"');
        _speak("I didn't catch that. Please say yes or no.");
        Future.delayed(Duration(seconds: 2), () async {
          if (_listeningFor == 'yes_no_guess')
            await _startListening('yes_no_guess');
        });
      }
    } else if (listeningMode == 'hm_letter_count') {
      final count = _hmParseLetterCount(transcript);
      if (count != null &&
          count > 0 &&
          count <= 30 &&
          _hmLastProcessedLetterCount != count) {
        debugPrint('Games page: [HANGMAN] MATCHED letter count: $count');
        _hmLastProcessedLetterCount = count;
        _stopListening();
        _hmHandleLetterCount(count);
      } else if (_hmLastProcessedLetterCount == null) {
        // Only announce error if we haven't successfully processed a count yet
        debugPrint(
          'Games page: [HANGMAN] No valid letter count in: "$transcript"',
        );
        _speak("I didn't catch a number. How many letters?");
        Future.delayed(Duration(seconds: 2), () async {
          if (_listeningFor == 'hm_letter_count')
            await _startListening('hm_letter_count');
        });
      }
    } else if (listeningMode == 'hm_yes_no') {
      if (transcript.contains('yes')) {
        debugPrint('Games page: [HANGMAN] MATCHED "yes" for letter');
        if (_hmProcessedYesNoForLetter != _hmCurrentGuessedLetter) {
          _hmProcessedYesNoForLetter = _hmCurrentGuessedLetter;
          _stopListening();
          _hmHandleModeAYes();
        }
      } else if (transcript.contains('no')) {
        debugPrint('Games page: [HANGMAN] MATCHED "no" for letter');
        if (_hmProcessedYesNoForLetter != _hmCurrentGuessedLetter) {
          _hmProcessedYesNoForLetter = _hmCurrentGuessedLetter;
          _stopListening();
          _hmHandleModeANo();
        }
      } else if (_hmProcessedYesNoForLetter == null) {
        // Only announce error if we haven't already processed a response for this letter
        debugPrint(
          'Games page: [HANGMAN] No match for yes/no in: "$transcript"',
        );
        _speak("I didn't catch that. Please say yes or no.");
        Future.delayed(Duration(seconds: 2), () async {
          if (_listeningFor == 'hm_yes_no' &&
              _hmProcessedYesNoForLetter == null)
            await _startListening('hm_yes_no');
        });
      }
    } else if (listeningMode == 'hm_letter') {
      // Mode B letter capture: parse the letter from the transcript
      final upper = transcript.toUpperCase().trim();
      String? detectedLetter;

      // Try single character
      if (upper.length == 1 && RegExp(r'[A-Z]').hasMatch(upper)) {
        detectedLetter = upper;
      }

      // Try extracting a single letter word from the transcript
      if (detectedLetter == null) {
        final match = RegExp(r'\b([A-Z])\b').firstMatch(upper);
        if (match != null) {
          detectedLetter = match.group(1);
        }
      }

      // Try "the letter X" or "X as in" patterns
      if (detectedLetter == null) {
        final letterPattern = RegExp(
          r'(?:THE\s+)?LETTER\s+([A-Z])\b',
        ).firstMatch(upper);
        if (letterPattern != null) {
          detectedLetter = letterPattern.group(1);
        }
      }
      if (detectedLetter == null) {
        final asInPattern = RegExp(r'\b([A-Z])\s+AS\s+IN\b').firstMatch(upper);
        if (asInPattern != null) {
          detectedLetter = asInPattern.group(1);
        }
      }

      // Phonetic/homophone mapping — speech recognizers often hear letters as words
      if (detectedLetter == null) {
        final lower = transcript.toLowerCase().trim();
        const phoneticMap = {
          // A
          'hey': 'A', 'ay': 'A', 'eh': 'A', 'a.': 'A', 'aye': 'A', 'eight': 'A',
          // B
          'bee': 'B', 'be': 'B', 'b.': 'B', 'bea': 'B',
          // C
          'see': 'C', 'sea': 'C', 'c.': 'C', 'si': 'C',
          // D
          'dee': 'D', 'de': 'D', 'd.': 'D',
          // E
          'ee': 'E', 'e.': 'E',
          // F
          'ef': 'F', 'eff': 'F', 'f.': 'F', 'half': 'F',
          // G
          'gee': 'G', 'g.': 'G', 'ji': 'G', 'jee': 'G',
          // H
          'aitch': 'H', 'h.': 'H', 'age': 'H', 'ach': 'H', 'each': 'H',
          // I
          'eye': 'I', 'i.': 'I',
          // J
          'jay': 'J', 'j.': 'J', 'je': 'J',
          // K
          'kay': 'K',
          'k.': 'K',
          'ok': 'K',
          'okay': 'K',
          'kei': 'K',
          'cake': 'K',
          // L
          'el': 'L', 'elle': 'L', 'l.': 'L', 'ale': 'L', 'ell': 'L',
          // M
          'em': 'M', 'm.': 'M',
          // N
          'en': 'N', 'n.': 'N', 'and': 'N',
          // O
          'oh': 'O', 'o.': 'O', 'owe': 'O',
          // P
          'pee': 'P', 'pe': 'P', 'p.': 'P',
          // Q
          'queue': 'Q',
          'cue': 'Q',
          'q.': 'Q',
          'cute': 'Q',
          'kew': 'Q',
          'que': 'Q',
          // R
          'are': 'R', 'ar': 'R', 'r.': 'R', 'our': 'R',
          // S
          'es': 'S', 'ass': 'S', 's.': 'S',
          // T
          'tee': 'T', 'tea': 'T', 'te': 'T', 't.': 'T',
          // U
          'you': 'U', 'u.': 'U', 'ewe': 'U', 'yu': 'U',
          // V
          'vee': 'V', 've': 'V', 'v.': 'V', 'we': 'V',
          // W
          'double you': 'W', 'w.': 'W', 'double u': 'W', 'dubya': 'W',
          // X
          'ex': 'X', 'x.': 'X', 'axe': 'X', 'eggs': 'X',
          // Y
          'why': 'Y', 'y.': 'Y', 'wie': 'Y', 'wye': 'Y',
          // Z
          'zee': 'Z', 'zed': 'Z', 'z.': 'Z',
        };

        // Check exact match first
        if (phoneticMap.containsKey(lower)) {
          detectedLetter = phoneticMap[lower];
        }

        // Check if transcript contains a phonetic match (for "the letter bee" etc.)
        if (detectedLetter == null) {
          for (final entry in phoneticMap.entries) {
            if (lower.endsWith(entry.key) || lower.contains(' ${entry.key}')) {
              detectedLetter = entry.value;
              break;
            }
          }
        }
      }

      debugPrint(
        'Games page: [HM_LETTER] transcript="$transcript", detected=$detectedLetter',
      );

      _stopListening();

      if (detectedLetter != null) {
        if (_hmGuessedLetters.contains(detectedLetter)) {
          await _speak(
            'You already guessed $detectedLetter. Try another letter. Say $_wakeWord first.',
          );
          await Future.delayed(Duration(milliseconds: 500));
          await _startListening('wake_word');
        } else {
          await _hmHandleLetterSelected(detectedLetter);
        }
      } else {
        await _speak("I didn't catch a letter. Say $_wakeWord and try again.");
        await Future.delayed(Duration(milliseconds: 500));
        await _startListening('wake_word');
      }
    }
  }

  void _startScanning({bool announceWaitPrompt = true}) {
    if (!_enableScanning || _isScanning || _currentOptions.isEmpty) return;

    debugPrint(
      'Games: Starting scanning with ${_currentOptions.length} options, waitForSwitch=$_waitForSwitchToScan',
    );
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    _focusNode.requestFocus();
    FocusScope.of(context).requestFocus(_focusNode);
    _isSpacebarDown = false;

    // Wait for switch whenever the setting is enabled
    bool shouldWaitForSwitch = _waitForSwitchToScan;

    // If waiting for switch, don't start scanning or announce yet
    if (shouldWaitForSwitch) {
      _scanTimer?.cancel();
      _scanTimer = null;
      setState(() {
        _scanningWaitingForSwitch = true;
        _currentScanIndex = scanMode == 'step' ? -1 : 0;
      });
      debugPrint('Games: Waiting for switch to start scanning timer');
      _debugFocusState('waiting_for_switch');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scanningWaitingForSwitch) {
          _focusNode.requestFocus();
          FocusScope.of(context).requestFocus(_focusNode);
          _debugFocusState('post_frame_focus');
        }
      });
      // Don't play prompt - only mood selection and first grid page should play it
      return;
    }

    setState(() {
      _isScanning = true;
      _currentScanIndex = scanMode == 'step' ? -1 : 0;
    });

    if (scanMode == 'auto') {
      _announceCurrentOption();
    }
    _startScanningTimer();
  }

  void _restartScanningForSelectionStep({bool announceWaitPrompt = true}) {
    if (!_enableScanning || !mounted) return;
    _focusNode.requestFocus();
    FocusScope.of(context).requestFocus(_focusNode);
    _stopScanning();
    _startScanning(announceWaitPrompt: announceWaitPrompt);
  }

  // Simple TTS for scanning announcements (like grid page's _speakPersonalVoice)
  Future<void> _speakScanningOption(String text) async {
    if (_isExiting || !mounted) return;
    debugPrint('Games scanning: $text');

    setState(() {
      _isAnnouncingScanningPrompt = true;
    });

    // Match grid page routing: use personal volume for scanning prompts
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final finalVolume = await _getEffectivePersonalVolume(settingsProvider);
    final ttsVolume = (finalVolume / 10.0).clamp(0.0, 0.7);

    // Reset audio routing to default before speaking (for Bluetooth/personal device)
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final platform = MethodChannel('audio_routing');
        await platform.invokeMethod('resetToDefault');
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('Games scanning: Audio routing reset failed: $e');
      }
    }

    // Route to personal device on Windows (same as grid page)
    if (!kIsWeb && Platform.isWindows) {
      final audioDeviceProvider = Provider.of<AudioDeviceProvider>(
        context,
        listen: false,
      );
      debugPrint(
        'Games scanning: Routing to personal device: ${audioDeviceProvider.personalDeviceId}',
      );
      await AudioDeviceService().playAudioToDevice(
        audioDeviceProvider.personalDeviceId ?? 'default',
        isPersonal: true,
      );
    }

    try {
      await _flutterTts.stop();
      await _flutterTts.setSpeechRate(0.5); // Slower speech for clarity
      await _flutterTts.setVolume(ttsVolume);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Games scanning: TTS failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
    }
  }

  Future<int> _getEffectivePersonalVolume(
    UserSettingsProvider settingsProvider,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        'Games scanning: Using LOCAL personal volume override: $overrideValue/10',
      );
      return overrideValue;
    }
    final settingsValue = settingsProvider.settings?.personalVolume ?? 10;
    debugPrint(
      'Games scanning: Using SETTINGS personal volume: $settingsValue/10',
    );
    return settingsValue;
  }

  void _stopScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    // Stop any in-progress scanning TTS so it doesn't hold the audio route
    // (e.g., personal device) when a system announcement needs to play
    _flutterTts.stop();
    setState(() {
      _isScanning = false;
      _scanningWaitingForSwitch = false;
      _currentScanIndex = 0;
    });
    _isWaitPromptActive = false;
  }

  void _handleSelection() {
    if (!_isScanning) return;

    debugPrint('Games: Selection at index $_currentScanIndex');
    final allOptions = _getScanningOptions();

    if (_currentScanIndex < allOptions.length) {
      final selected = allOptions[_currentScanIndex];
      _handleOptionSelection(selected);
    }
  }

  void _handleKeyPress(RawKeyEvent event) {
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? false;
    debugPrint(
      'Games: [KEY EVENT ARRIVED] logicalKey=${event.logicalKey.keyLabel} isDown=${event is RawKeyDownEvent} isCurrentRoute=$isCurrentRoute',
    );

    if (!isCurrentRoute) {
      debugPrint('Games: [KEY REJECTED] Not current route, ignoring event');
      return;
    }

    if (event.logicalKey.keyLabel == ' ') {
      if (event is RawKeyDownEvent) {
        _debugFocusState('switch_down');
        debugPrint(
          'Games: Switch down (view=$_currentView, isScanning=$_isScanning, waiting=$_scanningWaitingForSwitch, timer=${_scanTimer != null})',
        );
        if (_isSpacebarDown) return; // Ignore repeats
        _isSpacebarDown = true;

        // If waiting for switch to start scanning, start it now
        if (_scanningWaitingForSwitch && _scanTimer == null) {
          final settingsProvider = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
          debugPrint('Games: Switch pressed - starting scanning timer');
          setState(() {
            _scanningWaitingForSwitch = false;
            _isScanning = true;
            _currentScanIndex = scanMode == 'step' ? -1 : 0;
          });
          _isWaitPromptActive = false;
          if (scanMode == 'auto') {
            _announceCurrentOption();
          }
          _startScanningTimer();
          return;
        }

        // TTT has its own scanning
        if (_tttIsScanning && _tttIsPlayer1Turn && !_tttGameOver) {
          _tttHandleScanSelection();
          return;
        }

        // Hangman has its own alphabet scanning
        if (_hmIsAlphabetScanning && !_hmGameOver) {
          _hmHandleAlphabetScanSelection();
          return;
        }

        if (_isScanning && _currentScanIndex >= 0) {
          _handleSelection();
        }
      } else if (event is RawKeyUpEvent) {
        _isSpacebarDown = false;
      }
    } else if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      // Tab key for step-mode scanning advancement
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

      debugPrint(
        'Games: Tab pressed: scanMode=$scanMode, isScanning=$_isScanning, _isAnnouncingScanningPrompt=$_isAnnouncingScanningPrompt',
      );

      if (scanMode == 'step' && _isScanning && _isAnnouncingScanningPrompt) {
        debugPrint('Games: Tab: Interrupting scanning announcement');
        // Interrupt the current scanning prompt announcement
        _flutterTts.stop();
        if (mounted) {
          setState(() {
            _isAnnouncingScanningPrompt = false;
          });
        }
      }

      if (scanMode == 'step' && _isScanning) {
        debugPrint(
          'Games: Tab: Advancing in step mode from index $_currentScanIndex',
        );
        // Advance to next option
        _advanceStepModeScan();
      }
    }
  }

  void _advanceStepModeScan() {
    final allOptions = _getScanningOptions();
    if (allOptions.isEmpty) return;

    setState(() {
      _currentScanIndex = (_currentScanIndex + 1) % allOptions.length;
    });

    _announceCurrentOption();
  }

  void _debugFocusState(String source) {
    final focused = FocusManager.instance.primaryFocus;
    debugPrint(
      'Games: [FOCUS] $source primaryFocus=$focused hasFocus=${_focusNode.hasFocus}',
    );
  }

  void _startScanningTimer() {
    final allOptions = _getScanningOptions();
    _scanTimer?.cancel();

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    debugPrint('Games: _startScanningTimer: scanMode=$scanMode');

    if (scanMode == 'auto') {
      debugPrint('Games: Starting periodic timer for auto mode');
      _scanTimer = Timer.periodic(Duration(milliseconds: _scanDelay), (timer) {
        if (!_isScanning || _currentOptions.isEmpty) {
          timer.cancel();
          return;
        }

        // Move to next option
        setState(() {
          _currentScanIndex = (_currentScanIndex + 1) % allOptions.length;
        });

        // Announce the new current option
        if (_currentScanIndex < allOptions.length) {
          _speakScanningOption(allOptions[_currentScanIndex]);
        }
      });
    } else {
      debugPrint('Games: Step mode - timer not started, Tab key will advance');
      _scanTimer = null;
    }
  }

  List<String> _getScanningOptions() {
    return [
      ..._currentOptions,
      if (_currentOptionType == 'question' ||
          _currentOptionType == 'guess' ||
          _currentOptionType == 'guess_person' ||
          _currentOptionType == 'guess_clue' ||
          _currentOptionType == 'guess_guess' ||
          _currentOptionType == 'hm_word')
        'Something Else',
      if (_currentOptionType == 'guess_category' ||
          _currentOptionType == 'guess_mode' ||
          _currentOptionType == 'guess_person' ||
          _currentOptionType == 'guess_clue' ||
          _currentOptionType == 'guess_guess' ||
          _currentOptionType == 'hm_category' ||
          _currentOptionType == 'hm_mode' ||
          _currentOptionType == 'hm_word')
        'Go Back',
      if (_currentOptionType != 'game' &&
          _currentOptionType != 'finished' &&
          _currentOptionType != 'response' &&
          _currentOptionType != 'guess_finished' &&
          _currentOptionType != 'guess_response' &&
          _currentOptionType != 'ttt_board' &&
          _currentOptionType != 'ttt_finished' &&
          _currentOptionType != 'hm_alphabet' &&
          _currentOptionType != 'hm_playing' &&
          _currentOptionType != 'hm_finished')
        'Exit Game',
    ];
  }

  void _announceCurrentOption() {
    final allOptions = _getScanningOptions();
    if (allOptions.isNotEmpty && _currentScanIndex < allOptions.length) {
      _speakScanningOption(allOptions[_currentScanIndex]);
    }
  }

  void _handleOptionClick(String option) {
    _stopScanning();

    if (_currentOptionType == 'game') {
      // Route to selected game from game menu
      if (option == 'Home') {
        _exitGame();
      } else if (option == '20 Questions') {
        _startTwentyQuestions();
      } else if (option == 'Tic-Tac-Toe') {
        _startTicTacToe();
      } else if (option == 'Hangman') {
        _startHangman();
      } else if (option == 'Guess Who') {
        _startGuessGame('who');
      } else if (option == 'Guess Where') {
        _startGuessGame('where');
      } else if (option == 'Guess What') {
        _startGuessGame('what');
      } else if (option == 'Story Builder') {
        _startStoryBuilder();
      }
    } else if (_currentOptionType.startsWith('story_')) {
      _handleStoryOptionSelection(option);
    } else if (_currentOptionType == 'role') {
      // _selectRole is now async, so we need to call it without awaiting in this sync context
      // It will handle its own async operations internally
      _selectRole(option);
    } else if (_currentOptionType == 'category') {
      _selectCategory(option);
    } else if (_currentOptionType == 'action' ||
        _currentOptionType == 'action_guess') {
      _handleActionSelection(option);
    } else if (_currentOptionType == 'question') {
      _askQuestion(option);
    } else if (_currentOptionType == 'guess') {
      _makeGuess(option);
    } else if (_currentOptionType == 'select') {
      setState(() {
        _selectedItem = option;
        _currentView = 'ready';
      });
      _enterWakeWordPhase();
    } else if (_currentOptionType == 'guess_category') {
      _selectGuessCategory(option);
    } else if (_currentOptionType == 'guess_mode') {
      _selectGuessMode(option);
    } else if (_currentOptionType == 'guess_person') {
      _selectGuessPerson(option);
    } else if (_currentOptionType == 'guess_clue') {
      _selectGuessClue(option);
    } else if (_currentOptionType == 'guess_guess') {
      _selectGuessModeBGuess(option);
    } else if (_currentOptionType == 'ttt_symbol') {
      _tttSelectSymbol(option);
    } else if (_currentOptionType == 'hm_category') {
      _hmSelectCategory(option);
    } else if (_currentOptionType == 'hm_mode') {
      _hmSelectMode(option);
    } else if (_currentOptionType == 'hm_word') {
      _hmSelectWord(option);
    }
  }

  void _handleSomethingElse() {
    _stopScanning();

    if (_currentOptionType == 'question') {
      _loadQuestions();
    } else if (_currentOptionType == 'guess') {
      _loadGuesses();
    } else if (_currentOptionType == 'select') {
      _loadGameOptions(requestDifferent: true);
    } else if (_currentOptionType == 'guess_person') {
      _refreshGuessPeopleOptions();
    } else if (_currentOptionType == 'guess_clue') {
      _refreshGuessClueOptions();
    } else if (_currentOptionType == 'guess_guess') {
      _refreshGuessModeBGuessOptions();
    } else if (_currentOptionType == 'hm_word') {
      _hmRefreshWordOptions();
    }
  }

  Future<void> _enterWakeWordPhase() async {
    if (!mounted) return;
    setState(() {
      _currentView = 'ready';
      _statusText =
          'I\'m ready. To ask a question or make a guess, start with "$_wakeWord".';
      _currentOptions.clear();
      _currentOptionType = '';
    });
    await _speak(
      'I\'m ready. To ask a question or make a guess, start with $_wakeWord.',
    );
    await _startListeningWithGuard(
      'wake_word',
      preListenDelay: const Duration(milliseconds: 1800),
      ignoreWindow: const Duration(milliseconds: 4000),
    );
  }

  bool _matchesWakeWord(String transcript) {
    String normalize(String value) {
      return value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final normalizedTranscript = normalize(transcript);
    final normalizedWake = normalize(_wakeWord);

    if (normalizedTranscript.isEmpty || normalizedWake.isEmpty) {
      return false;
    }

    if (normalizedTranscript.contains(normalizedWake)) {
      return true;
    }

    final compactTranscript = normalizedTranscript.replaceAll(' ', '');
    final compactWake = normalizedWake.replaceAll(' ', '');
    if (compactTranscript.contains(compactWake)) {
      return true;
    }

    final wakeTokens = normalizedWake
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    if (wakeTokens.length <= 1) {
      return normalizedTranscript.contains(normalizedWake);
    }

    int searchStart = 0;
    for (final token in wakeTokens) {
      final index = normalizedTranscript.indexOf(token, searchStart);
      if (index == -1) {
        return false;
      }
      searchStart = index + token.length;
    }

    return true;
  }

  Future<void> _handleWakeWordDetected() async {
    if (_isWakeWordTransitionInProgress) {
      debugPrint(
        'Games page: [WAKE_WORD] Transition already in progress, ignoring duplicate wake word',
      );
      return;
    }
    _isWakeWordTransitionInProgress = true;
    _stopListening();
    setState(() {
      _currentView = 'ready';
      _statusText = 'Listening for your question or guess...';
    });
    await _speak('I\'m listening. Do you have a question or guess?');
    await _startListeningWithGuard(
      'intent',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
    _isWakeWordTransitionInProgress = false;
  }

  Future<void> _handlePlayerIntent(String intent) async {
    if (_isIntentTransitionInProgress) {
      debugPrint(
        'Games page: [INTENT] Transition already in progress, ignoring duplicate intent',
      );
      return;
    }
    _isIntentTransitionInProgress = true;
    _stopListening();
    if (intent == 'question') {
      await _speak('Ready for your question');
      await _startListeningWithGuard(
        'player_question',
        preListenDelay: const Duration(milliseconds: 1200),
        ignoreWindow: const Duration(milliseconds: 3000),
      );
      _isIntentTransitionInProgress = false;
    } else if (intent == 'guess') {
      await _speak('Ready for your guess');
      await _startListeningWithGuard(
        'player_guess',
        preListenDelay: const Duration(milliseconds: 1200),
        ignoreWindow: const Duration(milliseconds: 3000),
      );
      _isIntentTransitionInProgress = false;
    }
    _isIntentTransitionInProgress = false;
  }

  Future<void> _handlePlayerQuestion(String question) async {
    if (_role != 'answer') return;
    _stopListening();
    setState(() {
      _questionCount++;
      _currentQuestion = question;
      _statusText = 'Processing your question...';
    });
    await _speak('Ok. Your question is $question. Give me a moment to respond');
    await _loadResponseOptions('question_response', question);
  }

  Future<void> _handlePlayerGuess(String guess) async {
    if (_role != 'answer') return;
    _stopListening();
    setState(() {
      _guessCount++;
      _currentGuess = guess;
      _statusText = 'Processing your guess...';
    });
    await _speak('Ok. They guessed $guess. Give me a moment to respond');
    await _loadResponseOptions('guess_response', guess);
  }

  Future<void> _loadResponseOptions(
    String responseType,
    String promptText,
  ) async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Generating responses...';
    });

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/response-options'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'game_type': '20_questions',
          'response_type': responseType,
          'category': _category,
          'selected_item': _selectedItem,
          'player_question_or_guess': promptText,
          'questions_remaining': _maxQuestions - _questionCount,
          'guesses_remaining': _maxGuesses - _guessCount,
          'questions_asked': _questionCount,
          'guesses_made': _guessCount,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Error response status: ${response.statusCode}');
        debugPrint('Error response body: ${response.body}');
        throw Exception(
          'Failed to load response options: ${response.statusCode} - ${response.body}',
        );
      }

      final data = jsonDecode(response.body);
      final dynamic options = data['response_options'] ?? data['options'] ?? [];
      final List<Map<String, dynamic>> parsed = [];
      for (final opt in options) {
        if (opt is Map<String, dynamic>) {
          parsed.add(opt);
        } else if (opt is String) {
          parsed.add({'text': opt});
        }
      }

      setState(() {
        _isLoading = false;
        _currentResponseType = responseType;
        _responseOptions = parsed;
        _currentOptions = parsed
            .map((e) => (e['text'] ?? '').toString())
            .where((e) => e.isNotEmpty)
            .toList();
        _currentOptionType = 'response';
        _currentView = 'response_selection';
        _statusText = 'Choose a response';
      });

      if (_enableScanning) {
        _restartScanningForSelectionStep();
      }
    } catch (e) {
      debugPrint('Games page: Error loading response options: $e');
      setState(() {
        _isLoading = false;
        _currentView = 'ready';
        _statusText = 'Failed to load responses. Please try again.';
      });
      await _speak('Failed to load responses. Please try again.');
      Future.delayed(Duration(seconds: 2), () async {
        await _startListening('wake_word');
      });
    }
  }

  Future<void> _handleResponseOptionSelection(String option) async {
    _stopScanning();
    final selected = _responseOptions.firstWhere(
      (element) => (element['text'] ?? '').toString() == option,
      orElse: () => {'text': option},
    );
    final responseText = (selected['text'] ?? option).toString();
    final answerType = (selected['answer_type'] ?? '').toString();

    if (_currentResponseType == 'question_response') {
      setState(() {
        _questionHistory.add({
          'question': _currentQuestion ?? '',
          'answer': responseText,
        });
        _currentOptions.clear();
        _currentOptionType = '';
      });
      final remaining = _maxQuestions - _questionCount;
      await _speak(
        '$responseText. You have $remaining question${remaining == 1 ? '' : 's'} left.',
      );
      setState(() {
        _currentView = 'ready';
        _statusText = 'Listening for next question or guess...';
      });
      await _speak(
        'To ask another question or make a guess, start with $_wakeWord.',
      );
      Future.delayed(Duration(seconds: 3), () async {
        await _startListening('wake_word');
      });
    } else if (_currentResponseType == 'guess_response') {
      if (answerType == 'correct') {
        await _speak(responseText);
        await _speak('You successfully guessed it! It was $_selectedItem!');
        setState(() {
          _currentView = 'menu';
          _selectedGame = null;
          _role = null;
          _category = null;
          _selectedItem = null;
          _askedQuestions.clear();
          _previousGuesses.clear();
          _questionCount = 0;
          _guessCount = 0;
          _statusText = 'Select a game to play';
          _currentOptions.clear();
          _currentOptionType = 'game';
          _currentResponseType = '';
          _responseOptions.clear();
        });
      } else {
        if (_currentGuess != null && _currentGuess!.isNotEmpty) {
          if (!_previousGuesses.contains(_currentGuess)) {
            _previousGuesses.add(_currentGuess!);
          }
        }
        final remaining = _maxGuesses - _guessCount;
        if (remaining <= 0) {
          await _speak(responseText);
          await _speak(
            'You ran out of guesses. The answer was $_selectedItem. Great game!',
          );
          setState(() {
            _currentView = 'menu';
            _selectedGame = null;
            _role = null;
            _category = null;
            _selectedItem = null;
            _askedQuestions.clear();
            _previousGuesses.clear();
            _questionCount = 0;
            _guessCount = 0;
            _statusText = 'Select a game to play';
            _currentOptions.clear();
            _currentOptionType = 'game';
            _currentResponseType = '';
            _responseOptions.clear();
          });
        } else {
          await _speak(
            '$responseText. ${remaining} guess${remaining == 1 ? '' : 'es'} left.',
          );
          setState(() {
            _currentView = 'ready';
            _statusText = 'Listening for next question or guess...';
            _currentOptions.clear();
            _currentOptionType = '';
          });
          await _speak(
            'To ask another question or make a guess, start with $_wakeWord.',
          );
          Future.delayed(Duration(seconds: 3), () async {
            await _startListening('wake_word');
          });
        }
      }
    }
  }

  Future<void> _speak(String text) async {
    if (_isExiting || !mounted) return;

    _isAnnouncementActive = true;
    _suppressSpeechInputFor(const Duration(milliseconds: 2500));
    _stopListening();
    await WakeWordService.forceStopAndReset();
    WakeWordService.wakeWordShouldBeActive = false;

    // CRITICAL: Stop local scanning TTS before system announcement
    // On iOS, if the local _flutterTts is still holding the audio session
    // on the personal/Bluetooth device, forceSpeaker in announceViaBackend
    // may fail to route to the built-in speaker.
    await _flutterTts.stop();

    // Show speech bubble on games page first
    _showSpeechBubbleOverlay(text);

    // Use the announcement function passed from main.dart for audio playback
    // Use 'system' routing so other players can hear the announcements
    // Pass showSpeechBubble: false to prevent grid page from showing its own bubble
    if (widget.announceFunction != null) {
      try {
        await widget.announceFunction!(
          text,
          routing: 'system',
          showSpeechBubble: false,
        );
      } catch (e) {
        debugPrint('Games page: Announcement error: $e');
      } finally {
        _isAnnouncementActive = false;
        final wordCount = text.trim().isEmpty
            ? 0
            : text.trim().split(RegExp(r'\s+')).length;
        final cooldownMs = (2200 + (wordCount * 120)).clamp(2200, 7000).toInt();
        _suppressSpeechInputFor(Duration(milliseconds: cooldownMs));
      }
    } else {
      debugPrint('Games page: Speaking (no announce function): $text');
      _isAnnouncementActive = false;
      _suppressSpeechInputFor(const Duration(milliseconds: 2500));
    }
  }

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
      'Games page: Speech bubble displayed for ${duration}ms: "$text"',
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

    debugPrint('Games page: Speech bubble hidden');
  }

  void _resetStoryBuilderState() {
    _storyTranscript = [];
    _storyPendingQuestion = '';
    _storyCurrentOptions = [];
    _storyLibrary = [];
    _storySelectedStoryId = null;
    _storyCurrentTitle = '';
    _storyCurrentText = '';
    _storyEditMode = false;
  }

  void _setStoryOptions({
    required List<Map<String, dynamic>> options,
    required String optionType,
    required String view,
    required String status,
  }) {
    setState(() {
      _storyCurrentOptions = options;
      _currentOptions = options
          .map(
            (item) =>
                (item['summary'] ?? item['option'] ?? '').toString().trim(),
          )
          .where((text) => text.isNotEmpty)
          .toList();
      _currentOptionType = optionType;
      _currentView = view;
      _statusText = status;
    });

    if (_enableScanning && mounted && _currentOptions.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _restartScanningForSelectionStep(announceWaitPrompt: false);
        }
      });
    }
  }

  void _startStoryBuilder() async {
    _stopListening();
    _stopScanning();
    _deferSelectionScanning = true;

    setState(() {
      _selectedGame = 'story_builder';
      _isLoading = false;
    });

    _resetStoryBuilderState();
    await _storyShowEntryMenu();
  }

  Future<void> _storyShowEntryMenu() async {
    final options = [
      {'option': 'Go Back', 'summary': 'Go Back', 'action': 'story_entry_back'},
      {
        'option': 'Create a New Story',
        'summary': 'Create New Story',
        'action': 'story_entry_create',
      },
      {
        'option': 'Read an Existing Story',
        'summary': 'Read Existing Story',
        'action': 'story_entry_read',
      },
    ];

    _setStoryOptions(
      options: options,
      optionType: 'story_entry',
      view: 'story_entry_menu',
      status: 'Choose an option to begin Story Builder.',
    );
  }

  Future<void> _storyStartCreateFlow() async {
    _stopScanning();
    _stopListening();

    setState(() {
      _storyTranscript = [];
      _storyPendingQuestion = '';
      _storyCurrentOptions = [];
      _currentOptions = [];
      _currentOptionType = '';
      _currentView = 'ready';
      _storyEditMode = false;
      _statusText =
          "Let's create a story! Say $_wakeWord to ask me a question about the story.";
    });

    await _speak(
      "Let's create a story! Say $_wakeWord to ask me a question about the story.",
    );
    await _startListeningWithGuard(
      'story_wake_word',
      preListenDelay: const Duration(milliseconds: 800),
      ignoreWindow: const Duration(milliseconds: 1800),
    );
  }

  Future<void> _storyShowReadMenu() async {
    _stopScanning();
    _stopListening();

    await _storyLoadLibrary();

    final options = <Map<String, dynamic>>[
      {'option': 'Go Back', 'summary': 'Go Back', 'action': 'story_read_back'},
    ];

    if (_storyLibrary.isNotEmpty) {
      options.add({
        'option': 'Delete Stories',
        'summary': 'Delete Stories',
        'action': 'story_read_delete',
      });
      options.addAll(
        _storyLibrary.map((story) {
          final title = (story['title'] ?? 'Untitled Story').toString();
          return {
            'option': title,
            'summary': title,
            'action': 'story_read_story',
            'storyId': (story['id'] ?? '').toString(),
            'storyTitle': title,
          };
        }),
      );
    } else {
      options.add({
        'option': 'No saved stories found',
        'summary': 'No Saved Stories',
        'action': 'story_noop',
      });
    }

    _setStoryOptions(
      options: options,
      optionType: 'story_read',
      view: 'story_read_list',
      status: 'Choose a story to read.',
    );
  }

  Future<void> _storyLoadLibrary() async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/story/list'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final stories = List<Map<String, dynamic>>.from(data['stories'] ?? []);
        setState(() {
          _storyLibrary = stories;
        });
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Games page: Story Builder load library error: $e');
      setState(() {
        _storyLibrary = [];
      });
    }
  }

  Future<void> _storyReadById(
    String storyId, {
    String fallbackTitle = 'Untitled Story',
  }) async {
    if (storyId.trim().isEmpty) {
      await _storyShowReadMenu();
      return;
    }

    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Loading story...';
    });

    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/story/$storyId'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final story = Map<String, dynamic>.from(data['story'] ?? {});
      final title = (story['title'] ?? fallbackTitle).toString();
      final text = (story['story_text'] ?? '').toString();

      setState(() {
        _isLoading = false;
        _storySelectedStoryId = (story['id'] ?? storyId).toString();
        _storyCurrentTitle = title;
        _storyCurrentText = text;
        _storyTranscript = List<Map<String, String>>.from(
          ((story['transcript'] as List?) ?? []).map((item) {
            final entry = Map<String, dynamic>.from(item as Map);
            return {
              'question': (entry['question'] ?? '').toString(),
              'answer': (entry['answer'] ?? '').toString(),
            };
          }),
        );
        _statusText = 'Reading "$title"';
      });

      await _speak("Let's read $title");
      if (text.trim().isNotEmpty) {
        await _speak(text);
      } else {
        await _speak('This story is empty.');
      }

      await _storyPresentPostStoryActions(
        statusMessage: 'Choose what to do next with your story.',
      );
    } catch (e) {
      debugPrint('Games page: Story Builder read story error: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Unable to read that story.';
      });
      await _storyShowReadMenu();
    }
  }

  Future<void> _storyEnterAwaitWakeWord({
    String? status,
    String? spokenPrompt,
  }) async {
    setState(() {
      _currentView = 'ready';
      _currentOptions = [];
      _currentOptionType = '';
      _statusText =
          status ??
          'Say $_wakeWord to ask the next question or complete the story.';
    });

    if (spokenPrompt != null && spokenPrompt.trim().isNotEmpty) {
      await _speak(spokenPrompt);
    }

    await _startListeningWithGuard(
      'story_wake_word',
      preListenDelay: const Duration(milliseconds: 800),
      ignoreWindow: const Duration(milliseconds: 1800),
    );
  }

  Future<void> _handleStoryWakeWordDetected() async {
    _stopListening();
    setState(() {
      _currentView = 'ready';
      _statusText = "I'm listening. Say 'The End' to finish the story.";
    });
    await _speak("I'm listening. Say The End to finish the story.");
    await _startListeningWithGuard(
      'story_partner_question',
      preListenDelay: const Duration(milliseconds: 500),
      ignoreWindow: const Duration(milliseconds: 1200),
    );
  }

  Future<void> _handleStoryPartnerQuestion(String transcript) async {
    _stopListening();

    var partnerQuestion = transcript.trim();
    final escapedWakeWord = RegExp.escape(_wakeWord.trim());
    final wakePrefix = RegExp(
      '^$escapedWakeWord[\\s,.:;!?-]*',
      caseSensitive: false,
    );
    partnerQuestion = partnerQuestion.replaceFirst(wakePrefix, '').trim();

    if (partnerQuestion.isEmpty) {
      await _storyEnterAwaitWakeWord(
        status: 'Please ask a question for Story Builder.',
        spokenPrompt: 'Please ask a question for Story Builder.',
      );
      return;
    }

    setState(() {
      _storyPendingQuestion = partnerQuestion;
      _statusText = 'Question captured: $partnerQuestion';
    });
    await _speak("I heard $partnerQuestion. Give me a moment to respond.");

    if (RegExp(
      r'^the end\\??$',
      caseSensitive: false,
    ).hasMatch(partnerQuestion)) {
      _setStoryOptions(
        options: const [
          {'option': 'Yes', 'summary': 'Yes'},
          {'option': 'No', 'summary': 'No'},
        ],
        optionType: 'story_confirm_end',
        view: 'story_selecting_answer',
        status: 'Story completion requested. Select Yes or No.',
      );
      return;
    }

    await _storyRequestOptionsForQuestion(partnerQuestion);
  }

  List<Map<String, dynamic>> _storyStandardActionOptions() {
    return const [
      {
        'option': 'Something else',
        'summary': 'Something Else',
        'action': 'story_something_else',
      },
      {
        'option': 'Ask again',
        'summary': 'Ask Again',
        'action': 'story_ask_again',
      },
      {'option': 'Quit story', 'summary': 'Quit Story', 'action': 'story_quit'},
    ];
  }

  List<String> _storyExcludableOptions() {
    return _storyCurrentOptions
        .where((item) => item['action'] == null)
        .map(
          (item) =>
              ((item['option'] ?? item['summary']) ?? '').toString().trim(),
        )
        .where((text) => text.isNotEmpty)
        .toList();
  }

  Future<void> _storyRequestOptionsForQuestion(
    String partnerQuestion, {
    List<String> excluded = const [],
  }) async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Generating story options...';
    });

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/story/options'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'partner_question': partnerQuestion,
          'transcript': _storyTranscript,
          'exclude_existing_options': excluded,
          'include_partner_suggestions': false,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final rawUserOptions = List<Map<String, dynamic>>.from(
        data['user_options'] ?? [],
      );
      var normalized = rawUserOptions
          .map((item) {
            final option = (item['option'] ?? '').toString().trim();
            final summary = (item['summary'] ?? option).toString().trim();
            return {
              'option': option,
              'summary': summary.isEmpty ? option : summary,
            };
          })
          .where((item) => (item['option'] ?? '').toString().isNotEmpty)
          .toList();

      if (normalized.isEmpty) {
        normalized = [
          {
            'option': 'Let\'s add a surprise to the story',
            'summary': 'Add Surprise',
          },
          {
            'option': 'The character learns a lesson',
            'summary': 'Learn Lesson',
          },
          {'option': 'Something funny happens next', 'summary': 'Funny Moment'},
        ];
      }

      final optionsWithActions = <Map<String, dynamic>>[
        ...normalized,
        ..._storyStandardActionOptions(),
      ];

      setState(() {
        _isLoading = false;
      });

      _setStoryOptions(
        options: optionsWithActions,
        optionType: 'story_answer',
        view: 'story_selecting_answer',
        status: 'Choose an answer option for the user.',
      );
    } catch (e) {
      debugPrint('Games page: Story Builder request options error: $e');
      setState(() {
        _isLoading = false;
      });
      await _storyEnterAwaitWakeWord(
        status: 'Failed to generate story options. Try again.',
        spokenPrompt: 'Failed to generate story options. Try again.',
      );
    }
  }

  Future<void> _storyRequestTitleOptions() async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Generating title options...';
    });

    try {
      final response = await http.post(
        Uri.parse(
          '${EnvironmentConfig.apiBaseUrl}/api/games/story/title-options',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({'transcript': _storyTranscript}),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final titles = List<String>.from(data['title_options'] ?? []);
      final options = titles
          .where((title) => title.trim().isNotEmpty)
          .map((title) => {'option': title.trim(), 'summary': title.trim()})
          .toList();

      setState(() {
        _isLoading = false;
      });

      _setStoryOptions(
        options: options,
        optionType: 'story_title',
        view: 'story_selecting_title',
        status: 'Choose a title for your story.',
      );
    } catch (e) {
      debugPrint('Games page: Story Builder request title options error: $e');
      setState(() {
        _isLoading = false;
      });
      await _storyEnterAwaitWakeWord(
        status: 'Failed to generate title options.',
        spokenPrompt: 'Failed to generate title options.',
      );
    }
  }

  Future<void> _storyFinalize(String selectedTitle) async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Finalizing story...';
    });

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/story/finalize'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'title': selectedTitle,
          'transcript': _storyTranscript,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final story = Map<String, dynamic>.from(data['story'] ?? {});

      setState(() {
        _isLoading = false;
        _storySelectedStoryId = (story['id'] ?? '').toString();
        _storyCurrentTitle = (story['title'] ?? selectedTitle).toString();
        _storyCurrentText = (story['story_text'] ?? '').toString();
        _storyEditMode = false;
      });

      await _speak(
        _storyCurrentText.isNotEmpty
            ? _storyCurrentText
            : 'Your story is ready.',
      );
      await _storyPresentPostStoryActions(
        statusMessage: 'Story complete. Choose what to do next.',
      );
    } catch (e) {
      debugPrint('Games page: Story Builder finalize error: $e');
      setState(() {
        _isLoading = false;
      });
      await _storyEnterAwaitWakeWord(
        status: 'Failed to finish story. Please try again.',
        spokenPrompt: 'Failed to finish story. Please try again.',
      );
    }
  }

  Future<void> _storyRegenerateAndSaveEdits() async {
    if ((_storySelectedStoryId ?? '').isEmpty) {
      await _storyEnterAwaitWakeWord(
        status: 'No story selected for updates.',
        spokenPrompt: 'No story selected for updates.',
      );
      return;
    }

    final selectedTitle = _storyCurrentTitle.trim().isEmpty
        ? 'Untitled Story'
        : _storyCurrentTitle.trim();

    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Updating story...';
    });

    try {
      final regenerateResponse = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/story/finalize'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'title': selectedTitle,
          'transcript': _storyTranscript,
        }),
      );

      if (regenerateResponse.statusCode != 200) {
        throw Exception('HTTP ${regenerateResponse.statusCode}');
      }

      final regenerateData = jsonDecode(regenerateResponse.body);
      final regeneratedText =
          (Map<String, dynamic>.from(
                    regenerateData['story'] ?? {},
                  )['story_text'] ??
                  '')
              .toString();

      final updateResponse = await http.put(
        Uri.parse(
          '${EnvironmentConfig.apiBaseUrl}/api/games/story/${_storySelectedStoryId!}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'title': selectedTitle,
          'story_text': regeneratedText,
          'transcript': _storyTranscript,
        }),
      );

      if (updateResponse.statusCode != 200) {
        throw Exception('HTTP ${updateResponse.statusCode}');
      }

      setState(() {
        _isLoading = false;
        _storyCurrentTitle = selectedTitle;
        _storyCurrentText = regeneratedText;
        _storyEditMode = false;
      });

      await _speak(
        _storyCurrentText.isNotEmpty ? _storyCurrentText : 'Story updated.',
      );
      await _storyPresentPostStoryActions(
        statusMessage: 'Story updated. Choose what to do next.',
      );
    } catch (e) {
      debugPrint('Games page: Story Builder regenerate error: $e');
      setState(() {
        _isLoading = false;
      });
      await _storyEnterAwaitWakeWord(
        status: 'Failed to regenerate story. Please try again.',
        spokenPrompt: 'Failed to regenerate story. Please try again.',
      );
    }
  }

  Future<void> _storyPresentPostStoryActions({
    String statusMessage = 'Choose what to do next with your story.',
  }) async {
    final options = [
      {
        'option': 'Exit Story Builder',
        'summary': 'Exit Story Builder',
        'action': 'story_post_exit',
      },
      {
        'option': 'Read Story Again',
        'summary': 'Read Story Again',
        'action': 'story_post_read_again',
      },
      {
        'option': 'Make changes to story',
        'summary': 'Make Changes to Story',
        'action': 'story_post_make_changes',
      },
    ];

    _setStoryOptions(
      options: options,
      optionType: 'story_post',
      view: 'story_post_actions',
      status: statusMessage,
    );
  }

  Future<void> _storyBeginEditMode() async {
    setState(() {
      _storyEditMode = true;
    });

    await _storyEnterAwaitWakeWord(
      status:
          'I want to make some changes. Say $_wakeWord to ask me about the changes.',
      spokenPrompt:
          'I want to make some changes. Say $_wakeWord to ask me about the changes.',
    );
  }

  Future<bool> _storyValidateAdminPin(String pin) async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/account/toolbar-pin'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
      );

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body);
      return (data['pin'] ?? '').toString() == pin;
    } catch (_) {
      return false;
    }
  }

  Future<void> _storyPromptDeleteStories() async {
    if (_storyLibrary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no saved stories to delete.')),
      );
      return;
    }

    if (!_storyVerifiedAdminPin) {
      _storyPinController.clear();
      final pin = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Enter Admin PIN'),
            content: TextField(
              controller: _storyPinController,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'PIN'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_storyPinController.text.trim()),
                child: const Text('Verify'),
              ),
            ],
          );
        },
      );

      if (pin == null) {
        return;
      }

      final isValid = await _storyValidateAdminPin(pin);
      if (!isValid) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Incorrect Admin PIN.')));
        return;
      }

      setState(() {
        _storyVerifiedAdminPin = true;
      });
    }

    final selectedIds = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final localSelection = <String>{};
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Delete Stories'),
              content: SizedBox(
                width: 420,
                height: 320,
                child: ListView(
                  children: _storyLibrary.map((story) {
                    final id = (story['id'] ?? '').toString();
                    final title = (story['title'] ?? 'Untitled Story')
                        .toString();
                    return CheckboxListTile(
                      value: localSelection.contains(id),
                      title: Text(title),
                      onChanged: id.isEmpty
                          ? null
                          : (checked) {
                              setModalState(() {
                                if (checked == true) {
                                  localSelection.add(id);
                                } else {
                                  localSelection.remove(id);
                                }
                              });
                            },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: localSelection.isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(localSelection),
                  child: const Text('Delete Selected'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedIds == null || selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Deleting selected stories...';
    });

    try {
      for (final storyId in selectedIds) {
        final response = await http.delete(
          Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/story/$storyId'),
          headers: {
            'Authorization': 'Bearer ${widget.idToken}',
            'X-User-ID': widget.aacUserId,
          },
        );
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
      }

      setState(() {
        _isLoading = false;
      });
      await _storyShowReadMenu();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${selectedIds.length} stor${selectedIds.length == 1 ? 'y' : 'ies'}',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Games page: Story Builder delete error: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete selected stories.')),
      );
      await _storyShowReadMenu();
    }
  }

  void _storyBackToMenu() {
    _stopScanning();
    _stopListening();
    setState(() {
      _selectedGame = null;
      _currentView = 'menu';
      _currentOptions.clear();
      _currentOptionType = '';
      _statusText = 'Select a game';
    });
  }

  Future<void> _handleStoryOptionSelection(String selectedLabel) async {
    Map<String, dynamic>? selectedOption;
    for (final item in _storyCurrentOptions) {
      final summary = (item['summary'] ?? item['option'] ?? '')
          .toString()
          .trim();
      if (summary == selectedLabel) {
        selectedOption = item;
        break;
      }
    }

    selectedOption ??= {'option': selectedLabel, 'summary': selectedLabel};
    final optionText = (selectedOption['option'] ?? selectedLabel)
        .toString()
        .trim();
    final selectedAction = selectedOption['action']?.toString();

    if (selectedAction == 'story_entry_back') {
      _storyBackToMenu();
      return;
    }
    if (selectedAction == 'story_entry_create') {
      await _storyStartCreateFlow();
      return;
    }
    if (selectedAction == 'story_entry_read') {
      await _storyShowReadMenu();
      return;
    }
    if (selectedAction == 'story_read_back') {
      await _storyShowEntryMenu();
      return;
    }
    if (selectedAction == 'story_read_story') {
      final storyId = (selectedOption['storyId'] ?? '').toString();
      await _storyReadById(
        storyId,
        fallbackTitle: (selectedOption['storyTitle'] ?? optionText).toString(),
      );
      return;
    }
    if (selectedAction == 'story_read_delete') {
      await _storyPromptDeleteStories();
      return;
    }
    if (selectedAction == 'story_noop') {
      await _storyShowReadMenu();
      return;
    }
    if (selectedAction == 'story_something_else') {
      final excluded = _storyExcludableOptions();
      await _storyRequestOptionsForQuestion(
        _storyPendingQuestion,
        excluded: excluded,
      );
      return;
    }
    if (selectedAction == 'story_ask_again') {
      _storyPendingQuestion = '';
      await _storyEnterAwaitWakeWord(
        status: 'Please use $_wakeWord and ask again.',
        spokenPrompt: 'Please use $_wakeWord and ask again.',
      );
      return;
    }
    if (selectedAction == 'story_quit' || selectedAction == 'story_post_exit') {
      _storyBackToMenu();
      return;
    }
    if (selectedAction == 'story_post_read_again') {
      if (_storyCurrentText.trim().isNotEmpty) {
        await _speak(_storyCurrentText);
      }
      await _storyPresentPostStoryActions(
        statusMessage: 'Choose what to do next with your story.',
      );
      return;
    }
    if (selectedAction == 'story_post_make_changes') {
      await _storyBeginEditMode();
      return;
    }

    if (_currentOptionType == 'story_confirm_end') {
      _storyTranscript.add({'question': 'The End?', 'answer': optionText});
      if (optionText.toLowerCase() == 'yes') {
        if (_storyEditMode) {
          await _speak("I'm updating your story now.");
          await _storyRegenerateAndSaveEdits();
        } else {
          await _speak("I'm picking a title for the story.");
          await _storyRequestTitleOptions();
        }
        return;
      }

      await _storyEnterAwaitWakeWord(
        status:
            'Say $_wakeWord to ask the next question or complete the story.',
        spokenPrompt: 'Say $_wakeWord to ask another question.',
      );
      return;
    }

    if (_currentOptionType == 'story_title') {
      await _speak("Let's listen to our story $optionText.");
      await _storyFinalize(optionText);
      return;
    }

    if (_currentOptionType == 'story_answer') {
      await _speak(optionText);
      _storyTranscript.add({
        'question': _storyPendingQuestion,
        'answer': optionText,
      });
      _storyPendingQuestion = '';
      await _storyEnterAwaitWakeWord(
        status:
            'Say $_wakeWord to ask the next question or complete the story.',
        spokenPrompt: 'Say $_wakeWord to ask another question.',
      );
    }
  }

  void _startTwentyQuestions() async {
    _deferSelectionScanning = true;
    setState(() {
      _selectedGame = '20_questions';
      _currentView = 'role_selection';
      _statusText = 'Who will ask the questions?';
      _currentOptions = ['I ask the questions', 'You ask the questions'];
      _currentOptionType = 'role';
    });

    // Wait for announcement to finish before starting scanning
    await _speak("Let's play 20 questions!");

    if (_enableScanning && mounted) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep(announceWaitPrompt: false);
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  void _startTicTacToe() async {
    _tttBoard = List.filled(9, '');
    _tttPlayer1Symbol = 'X';
    _tttPlayer2Symbol = 'O';
    _tttIsPlayer1Turn = true;
    _tttGameOver = false;
    _tttWinner = null;
    _tttStopScanning();

    _deferSelectionScanning = true;
    setState(() {
      _selectedGame = 'tic_tac_toe';
      _currentView = 'ttt_symbol_selection';
      _statusText = "I'm choosing my symbol";
      _currentOptions = ['X', 'O'];
      _currentOptionType = 'ttt_symbol';
    });

    await _speak("Let's play Tic-Tac-Toe! I'm choosing my symbol.");

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep(announceWaitPrompt: false);
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  void _tttSelectSymbol(String symbol) {
    _stopScanning();
    _tttPlayer1Symbol = symbol;
    _tttPlayer2Symbol = symbol == 'X' ? 'O' : 'X';

    // Randomly decide who goes first
    final random = DateTime.now().millisecondsSinceEpoch % 2 == 0;
    _tttIsPlayer1Turn = random;

    final firstLabel = _tttIsPlayer1Turn ? 'I' : 'You';

    setState(() {
      _currentView = 'ttt_board';
      _statusText = '$firstLabel go${_tttIsPlayer1Turn ? '' : ''} first!';
      _currentOptions.clear();
      _currentOptionType = 'ttt_board';
    });

    _speak(
      'I am $_tttPlayer1Symbol. You are $_tttPlayer2Symbol. $firstLabel go first!${_tttIsPlayer1Turn ? ' Give me a moment to pick my space.' : ''}',
    ).then((_) {
      if (mounted && !_tttGameOver) {
        if (_tttIsPlayer1Turn) {
          _tttStartPlayer1Turn();
        } else {
          setState(() {
            _statusText = "Your turn. Tap a space.";
          });
        }
      }
    });
  }

  void _tttStartPlayer1Turn() {
    if (_tttGameOver || !mounted) return;
    setState(() {
      _statusText = "My turn ($_tttPlayer1Symbol)";
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_tttGameOver && _tttIsPlayer1Turn) {
          _tttStartScanning();
        }
      });
    }
  }

  // --- TTT Scanning (scans only available cells) ---

  List<int> _tttGetAvailableCells() {
    final available = <int>[];
    for (int i = 0; i < 9; i++) {
      if (_tttBoard[i].isEmpty) available.add(i);
    }
    return available;
  }

  void _tttStartScanning() {
    if (!_enableScanning || _tttGameOver || !_tttIsPlayer1Turn) return;

    final available = _tttGetAvailableCells();
    if (available.isEmpty) return;

    _tttScanIndex = 0;
    _tttIsScanning = true;
    _focusNode.requestFocus();

    // Announce and highlight the first available cell
    setState(() {});
    _speakScanningOption(_tttPositionNames[available[_tttScanIndex]]);

    _tttScanTimer?.cancel();
    _tttScanTimer = Timer.periodic(Duration(milliseconds: _scanDelay), (timer) {
      if (!mounted || _tttGameOver || !_tttIsPlayer1Turn) {
        timer.cancel();
        _tttIsScanning = false;
        return;
      }

      final avail = _tttGetAvailableCells();
      if (avail.isEmpty) {
        timer.cancel();
        _tttIsScanning = false;
        return;
      }

      // Cycle through available cells + 1 extra for Exit Game
      _tttScanIndex = (_tttScanIndex + 1) % (avail.length + 1);
      setState(() {});
      if (_tttScanIndex < avail.length) {
        _speakScanningOption(_tttPositionNames[avail[_tttScanIndex]]);
      } else {
        _speakScanningOption('Exit Game');
      }
    });
  }

  void _tttStopScanning() {
    _tttScanTimer?.cancel();
    _tttScanTimer = null;
    _tttIsScanning = false;
  }

  void _tttHandleScanSelection() {
    if (!_tttIsScanning || !_tttIsPlayer1Turn || _tttGameOver) return;

    final available = _tttGetAvailableCells();
    if (available.isEmpty) return;

    // If scanning is on Exit Game (index == avail.length), trigger exit
    if (_tttScanIndex >= available.length) {
      _tttStopScanning();
      _stopScanning();
      setState(() {
        _selectedGame = null;
        _currentView = 'menu';
        _currentOptions.clear();
        _currentOptionType = '';
        _statusText = 'Select a game';
      });
      return;
    }

    final cellIndex = available[_tttScanIndex];
    _tttStopScanning();
    _tttPlaceSymbol(cellIndex, isPlayer1: true);
  }

  // --- TTT Core Game Logic ---

  void _tttPlaceSymbol(int cellIndex, {required bool isPlayer1}) async {
    if (_tttBoard[cellIndex].isNotEmpty || _tttGameOver) return;

    // Verify it's the right player's turn
    if (isPlayer1 && !_tttIsPlayer1Turn) return;
    if (!isPlayer1 && _tttIsPlayer1Turn) return;

    final symbol = isPlayer1 ? _tttPlayer1Symbol : _tttPlayer2Symbol;
    final posName = _tttPositionNames[cellIndex];

    _tttStopScanning();

    setState(() {
      _tttBoard[cellIndex] = symbol;
    });

    // Check for winner or tie before announcing (so we don't promise a next turn if game is over)
    final winner = _tttCheckWinner();

    if (winner != null) {
      // Game over - announce the move, wait for it to finish, then end game
      final moveAnnounce = isPlayer1
          ? 'I selected $posName.'
          : 'You selected $posName.';
      _tttGameOver = true;
      await _speak(moveAnnounce);
      if (winner == 'tie') {
        _tttWinner = 'tie';
        _tttEndGame("It's a tie! Great game!");
      } else {
        final isMyWin = winner == _tttPlayer1Symbol;
        _tttWinner = isMyWin ? 'player1' : 'player2';
        _tttEndGame(isMyWin ? 'I win! Great game!' : 'You win! Great game!');
      }
    } else {
      // Game continues - conversational announcement
      if (isPlayer1) {
        _speak('I selected $posName. Your turn to tap an open space.');
      } else {
        _speak('You selected $posName. Give me a moment to pick my space.');
      }

      // Switch turns
      setState(() {
        _tttIsPlayer1Turn = !_tttIsPlayer1Turn;
        if (_tttIsPlayer1Turn) {
          _statusText = "My turn ($_tttPlayer1Symbol)";
        } else {
          _statusText = "Your turn ($_tttPlayer2Symbol). Tap a space.";
        }
      });

      if (_tttIsPlayer1Turn) {
        _tttStartPlayer1Turn();
      }
    }
  }

  String? _tttCheckWinner() {
    // All winning combinations
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
      [0, 4, 8], [2, 4, 6], // diagonals
    ];

    for (final line in lines) {
      final a = _tttBoard[line[0]];
      final b = _tttBoard[line[1]];
      final c = _tttBoard[line[2]];
      if (a.isNotEmpty && a == b && b == c) {
        return a; // Return the winning symbol
      }
    }

    // Check for tie (all cells filled)
    if (_tttBoard.every((cell) => cell.isNotEmpty)) {
      return 'tie';
    }

    return null; // Game continues
  }

  void _tttEndGame(String message) async {
    _tttStopScanning();

    await _speak(message);

    setState(() {
      _currentView = 'ttt_game_over';
      _statusText = message;
      _currentOptions = ['Play Again', 'Go Back'];
      _currentOptionType = 'ttt_finished';
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 1000), () {
        if (mounted) _restartScanningForSelectionStep();
      });
    }
  }

  void _tttHandleFinished(String option) {
    _tttStopScanning();
    _stopScanning();
    if (option == 'Play Again') {
      _startTicTacToe();
    } else if (option == 'Go Back') {
      setState(() {
        _selectedGame = null;
        _currentView = 'menu';
        _currentOptions.clear();
        _currentOptionType = '';
        _statusText = 'Select a game';
      });
    }
  }

  // ===== HANGMAN GAME METHODS =====

  void _hmResetState() {
    _hmMode = null;
    _hmCategory = null;
    _hmWord = null;
    _hmWordLength = 0;
    _hmRevealedLetters = [];
    _hmGuessedLetters = [];
    _hmWrongGuesses = 0;
    _hmWordOptions = [];
    _hmPreviousWords = [];
    _hmCurrentGuessedLetter = null;
    _hmModeAPhase = '';
    _hmSelectedPositions = {};
    _hmGameOver = false;
    _hmPlayerWon = false;
    _hmStopAlphabetScanning();
  }

  void _startHangman() async {
    _hmResetState();

    _deferSelectionScanning = true;
    setState(() {
      _selectedGame = 'hangman';
      _currentView = 'loading';
      _isLoading = true;
      _statusText = 'Loading categories...';
    });

    await _speak("Let's play Hangman!");

    await _hmLoadCategories();
  }

  Future<void> _hmLoadCategories() async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
    });

    try {
      // Use the hangman-specific categories endpoint
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/hangman/categories'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final categories = List<String>.from(data['all_categories'] ?? []);

        // Store default and custom categories for the management UI
        _hmDefaultCategories = List<String>.from(
          data['default_categories'] ?? [],
        );
        _hmCustomCategories = List<String>.from(
          data['custom_categories'] ?? [],
        );

        _deferSelectionScanning = true;
        setState(() {
          _currentOptions = categories;
          _currentOptionType = 'hm_category';
          _currentView = 'hm_category_selection';
          _statusText = 'Select a category';
          _isLoading = false;
        });

        if (_enableScanning && mounted) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _deferSelectionScanning = false;
              _restartScanningForSelectionStep(announceWaitPrompt: false);
            }
          });
        } else {
          _deferSelectionScanning = false;
        }
      } else {
        debugPrint(
          'Games page: [HANGMAN] Error loading categories: ${response.statusCode}',
        );
        setState(() {
          _isLoading = false;
          _statusText = 'Error loading categories. Try again.';
        });
      }
    } catch (e) {
      debugPrint('Games page: [HANGMAN] Exception loading categories: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error loading categories. Try again.';
      });
    }
  }

  void _hmSelectCategory(String category) async {
    _hmCategory = category;
    _stopScanning();

    await _speak('The Category is $category.');

    // Show mode selection
    _deferSelectionScanning = true;
    setState(() {
      _currentOptions = ['I guess', 'You guess'];
      _currentOptionType = 'hm_mode';
      _currentView = 'hm_mode_selection';
      _statusText = 'Who is guessing?';
    });

    if (_enableScanning && mounted) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep(announceWaitPrompt: false);
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  void _hmSelectMode(String mode) {
    _stopScanning();

    if (mode == 'I guess') {
      _hmMode = 'mode-a';
      _hmStartModeA();
    } else {
      _hmMode = 'mode-b';
      _hmStartModeB();
    }
  }

  // ===== MODE A: I guess (partner picks word secretly) =====

  void _hmStartModeA() async {
    _hmModeAPhase = 'waitingReady';
    _hmWord = null; // Word is secret
    _hmLastProcessedLetterCount = null; // Reset tracking
    _hmProcessedYesNoForLetter = null; // Reset tracking

    setState(() {
      _currentView = 'hm_listening';
      _statusText =
          'Think of a ${_hmCategory ?? "word"}. Say "ready" when you have your word.';
      _currentOptions = [];
    });

    await _speak(
      'Think of a ${_hmCategory ?? "word"}. Say ready when you have your word.',
    );
    await _startListeningWithGuard(
      'ready',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
  }

  Future<void> _hmHandleReady() async {
    _hmModeAPhase = 'waitingLetterCount';
    _hmLastProcessedLetterCount = null; // Reset tracking

    setState(() {
      _currentView = 'hm_listening';
      _statusText = 'How many letters are in your word? Say the number.';
    });

    await _speak('How many letters are in your word? Say the number.');
    await _startListeningWithGuard(
      'hm_letter_count',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
  }

  int? _hmParseLetterCount(String transcript) {
    final wordToNum = {
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19,
      'twenty': 20,
      'twenty one': 21,
      'twenty two': 22,
      'twenty three': 23,
      'twenty four': 24,
      'twenty five': 25,
    };

    final lower = transcript.toLowerCase().trim();

    // Check word numbers first
    for (final entry in wordToNum.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    // Try numeric extraction
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match != null) return int.tryParse(match.group(1)!);

    return null;
  }

  void _hmHandleLetterCount(int count) async {
    _hmWordLength = count;
    _hmRevealedLetters = List.filled(count, false);
    _hmGuessedLetters = [];
    _hmWrongGuesses = 0;
    _hmModeAPhase = 'playing';

    await _speak(
      '$count letters. Give me a moment to select a letter to guess.',
    );

    setState(() {
      _currentView = 'hm_playing';
      _statusText = 'Guess a letter!';
      _currentOptionType = 'hm_alphabet';
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_hmGameOver) {
          _hmStartAlphabetScanning();
        }
      });
    }
  }

  // Mode A: alphabet scanning
  List<String> _hmGetAvailableLetters() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return alphabet
        .split('')
        .where((l) => !_hmGuessedLetters.contains(l))
        .toList();
  }

  void _hmStartAlphabetScanning() {
    if (!_enableScanning || _hmGameOver) return;

    final available = _hmGetAvailableLetters();
    if (available.isEmpty) return;

    _hmAlphabetScanIndex = 0;
    _hmIsAlphabetScanning = true;
    _focusNode.requestFocus();

    setState(() {});

    // Announce first letter after a short delay
    Future.delayed(Duration(milliseconds: 300), () {
      if (_hmIsAlphabetScanning && mounted) {
        _speakScanningOption(available[_hmAlphabetScanIndex].toLowerCase());
      }
    });

    _hmAlphabetScanTimer?.cancel();
    _hmAlphabetScanTimer = Timer.periodic(Duration(milliseconds: _scanDelay), (
      timer,
    ) {
      if (!mounted || _hmGameOver) {
        timer.cancel();
        _hmIsAlphabetScanning = false;
        return;
      }

      final avail = _hmGetAvailableLetters();
      if (avail.isEmpty) {
        timer.cancel();
        _hmIsAlphabetScanning = false;
        return;
      }

      // Cycle through available letters + 1 for Exit Game
      _hmAlphabetScanIndex = (_hmAlphabetScanIndex + 1) % (avail.length + 1);
      setState(() {});
      if (_hmAlphabetScanIndex < avail.length) {
        _speakScanningOption(avail[_hmAlphabetScanIndex].toLowerCase());
      } else {
        _speakScanningOption('Exit Game');
      }
    });
  }

  void _hmStopAlphabetScanning() {
    _hmAlphabetScanTimer?.cancel();
    _hmAlphabetScanTimer = null;
    _hmIsAlphabetScanning = false;
  }

  void _hmHandleAlphabetScanSelection() {
    if (!_hmIsAlphabetScanning || _hmGameOver) return;

    final available = _hmGetAvailableLetters();
    if (available.isEmpty) return;

    // Exit Game option
    if (_hmAlphabetScanIndex >= available.length) {
      _hmStopAlphabetScanning();
      _hmExitToMenu();
      return;
    }

    final letter = available[_hmAlphabetScanIndex];
    _hmStopAlphabetScanning();
    _hmHandleLetterSelected(letter);
  }

  // Mode A: letter guess flow
  Future<void> _hmHandleLetterSelected(String letter) async {
    if (_hmGuessedLetters.contains(letter)) return;
    _hmGuessedLetters.add(letter);
    _hmStopAlphabetScanning();
    _stopScanning();

    if (_hmMode == 'mode-a') {
      await _hmHandleModeALetterGuess(letter);
    } else {
      await _hmHandleModeBLetterGuess(letter);
    }
  }

  Future<void> _hmHandleModeALetterGuess(String letter) async {
    _hmCurrentGuessedLetter = letter;
    _hmProcessedYesNoForLetter = null; // Reset tracking for new letter
    _hmModeAPhase = 'waitingYesNo';

    setState(() {
      _currentView = 'hm_playing';
      _statusText = 'Is the letter $letter in your word? Say yes or no.';
    });

    await _speak('Is the letter $letter in your word? Say yes or no.');
    await _startListeningWithGuard(
      'hm_yes_no',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
  }

  void _hmHandleModeAYes() async {
    final letter = _hmCurrentGuessedLetter;
    if (letter == null) return;

    _hmModeAPhase = 'waitingPositions';
    _hmSelectedPositions = {};

    setState(() {
      _currentView = 'hm_position_selection';
      _statusText = 'Tap the blanks where $letter goes, then tap Done.';
    });

    await Future.delayed(Duration(milliseconds: 500));
    await _speak('Tap the blanks where $letter goes, then tap Done.');
  }

  void _hmTogglePosition(int index) {
    setState(() {
      if (_hmSelectedPositions.contains(index)) {
        _hmSelectedPositions.remove(index);
      } else {
        _hmSelectedPositions.add(index);
      }
    });
  }

  void _hmConfirmPositions() async {
    _hmStopAlphabetScanning();

    final letter = _hmCurrentGuessedLetter;
    if (letter == null) return;

    if (_hmSelectedPositions.isEmpty) {
      await _speak('You need to tap at least one blank. Try again.');
      return;
    }

    // Reveal the selected positions
    for (final pos in _hmSelectedPositions) {
      if (pos >= 0 && pos < _hmRevealedLetters.length) {
        _hmRevealedLetters[pos] = letter;
      }
    }

    _hmSelectedPositions = {};

    setState(() {
      _currentView = 'hm_playing';
    });

    // Check win
    if (_hmCheckModeAWin()) {
      final word = _hmRevealedLetters.map((l) => l == false ? '_' : l).join('');
      _hmGameOver = true;
      _hmPlayerWon = true;
      await _speak('I figured it out! The word is $word! I win!');
      _hmEndGame(true);
      return;
    }

    // Continue playing
    _hmModeAPhase = 'playing';
    setState(() {
      _statusText = 'What letter next?';
    });

    await _speak('Give me a moment to select a letter to guess.');

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_hmGameOver) {
          _hmStartAlphabetScanning();
        }
      });
    }
  }

  bool _hmCheckModeAWin() {
    for (int i = 0; i < _hmWordLength; i++) {
      if (_hmRevealedLetters[i] == false) return false;
    }
    return true;
  }

  void _hmHandleModeANo() async {
    final letter = _hmCurrentGuessedLetter;
    if (letter == null) return;

    _hmWrongGuesses++;

    setState(() {
      _currentView = 'hm_playing';
    });

    if (_hmWrongGuesses >= _hmMaxWrong) {
      _hmGameOver = true;
      _hmPlayerWon = false;
      await _speak('Oh no! I\'m out of guesses. You win!');
      _hmEndGame(false);
      return;
    }

    final remaining = _hmMaxWrong - _hmWrongGuesses;
    _hmModeAPhase = 'playing';
    setState(() {
      _statusText =
          '$remaining wrong ${remaining == 1 ? 'guess' : 'guesses'} left.';
    });

    await _speak(
      'Nope! $remaining wrong ${remaining == 1 ? 'guess' : 'guesses'} left.',
    );

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_hmGameOver) {
          _hmStartAlphabetScanning();
        }
      });
    }
  }

  // ===== MODE B: You guess (I pick word from LLM options) =====

  // Local fallback word lists matching the backend's fallback
  static const Map<String, List<String>> _hmFallbackWords = {
    'Animals': [
      'elephant',
      'dolphin',
      'penguin',
      'giraffe',
      'octopus',
      'butterfly',
      'kangaroo',
      'cheetah',
      'gorilla',
      'flamingo',
    ],
    'Sports': [
      'basketball',
      'tennis',
      'soccer',
      'swimming',
      'baseball',
      'football',
      'volleyball',
      'gymnastics',
      'hockey',
      'surfing',
    ],
    'Food': [
      'pizza',
      'hamburger',
      'spaghetti',
      'chocolate',
      'sandwich',
      'pancake',
      'burrito',
      'popcorn',
      'pineapple',
      'broccoli',
    ],
    'Movies': [
      'frozen',
      'batman',
      'titanic',
      'avengers',
      'shrek',
      'moana',
      'coco',
      'brave',
      'ratatouille',
      'jaws',
    ],
    'Music': [
      'guitar',
      'piano',
      'drums',
      'trumpet',
      'violin',
      'microphone',
      'concert',
      'melody',
      'rhythm',
      'harmony',
    ],
    'Science': [
      'volcano',
      'dinosaur',
      'gravity',
      'molecule',
      'telescope',
      'magnet',
      'crystal',
      'planet',
      'tornado',
      'fossil',
    ],
    'Geography': [
      'mountain',
      'island',
      'desert',
      'canyon',
      'glacier',
      'volcano',
      'peninsula',
      'archipelago',
      'plateau',
      'tundra',
    ],
    'Holidays': [
      'christmas',
      'halloween',
      'thanksgiving',
      'valentine',
      'fireworks',
      'pumpkin',
      'snowman',
      'costume',
      'turkey',
      'present',
    ],
  };

  List<String> _hmGetFallbackWords() {
    final category = _hmCategory ?? '';
    // Try exact match first, then case-insensitive
    List<String> words =
        _hmFallbackWords[category] ??
        _hmFallbackWords.entries
            .where((e) => e.key.toLowerCase() == category.toLowerCase())
            .map((e) => e.value)
            .firstOrNull ??
        [
          'puzzle',
          'challenge',
          'mystery',
          'adventure',
          'treasure',
          'mountain',
          'rainbow',
          'diamond',
          'shelter',
          'kingdom',
        ];

    // Filter out previously used words
    words = words
        .where(
          (w) => !_hmPreviousWords
              .map((p) => p.toLowerCase())
              .contains(w.toLowerCase()),
        )
        .toList();
    if (words.isEmpty) {
      words = ['puzzle', 'challenge', 'mystery', 'adventure', 'treasure'];
    }
    // Shuffle to add variety
    words.shuffle();
    return words.take(5).toList();
  }

  void _hmShowWordOptions(List<String> words) {
    _hmWordOptions = words;
    _hmPreviousWords.addAll(words);

    _deferSelectionScanning = true;
    setState(() {
      _currentOptions = _hmWordOptions;
      _currentOptionType = 'hm_word';
      _currentView = 'hm_word_selection';
      _statusText = 'Pick a word';
      _isLoading = false;
    });

    if (_enableScanning && mounted) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep(announceWaitPrompt: false);
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  void _hmStartModeB() async {
    setState(() {
      _currentView = 'loading';
      _isLoading = true;
      _statusText = 'Choosing words...';
    });

    await _speak('Give me a moment to choose a ${_hmCategory ?? "word"} word.');

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/hangman/generate-words'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'category': _hmCategory ?? '',
          'previous_words': _hmPreviousWords,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final words = List<String>.from(data['words'] ?? []);
        if (words.isNotEmpty) {
          _hmShowWordOptions(words);
        } else {
          debugPrint(
            'Games page: [HANGMAN] Server returned empty words, using fallback',
          );
          _hmShowWordOptions(_hmGetFallbackWords());
        }
      } else {
        debugPrint(
          'Games page: [HANGMAN] Error generating words: ${response.statusCode} - ${response.body}',
        );
        debugPrint('Games page: [HANGMAN] Using local fallback words');
        _hmShowWordOptions(_hmGetFallbackWords());
      }
    } catch (e) {
      debugPrint('Games page: [HANGMAN] Exception generating words: $e');
      debugPrint('Games page: [HANGMAN] Using local fallback words');
      _hmShowWordOptions(_hmGetFallbackWords());
    }
  }

  void _hmRefreshWordOptions() async {
    _stopScanning();
    setState(() {
      _currentView = 'loading';
      _isLoading = true;
      _statusText = 'Finding more words...';
    });

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/hangman/generate-words'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'category': _hmCategory ?? '',
          'previous_words': _hmPreviousWords,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final words = List<String>.from(data['words'] ?? []);
        if (words.isNotEmpty) {
          _hmShowWordOptions(words);
        } else {
          _hmShowWordOptions(_hmGetFallbackWords());
        }
      } else {
        debugPrint(
          'Games page: [HANGMAN] Refresh error: ${response.statusCode}, using fallback',
        );
        _hmShowWordOptions(_hmGetFallbackWords());
      }
    } catch (e) {
      debugPrint('Games page: [HANGMAN] Refresh exception: $e, using fallback');
      _hmShowWordOptions(_hmGetFallbackWords());
    }
  }

  void _hmSelectWord(String word) async {
    _stopScanning();

    _hmWord = word.toUpperCase();
    _hmWordLength = _hmWord!.replaceAll(RegExp(r'[^A-Z]'), '').length;
    _hmRevealedLetters = List.generate(_hmWord!.length, (i) {
      // Non-letter characters (spaces, hyphens) are pre-revealed
      return RegExp(r'[A-Z]').hasMatch(_hmWord![i]) ? false : true;
    });
    _hmGuessedLetters = [];
    _hmWrongGuesses = 0;

    await _speak(
      'I picked my word! It has $_hmWordLength letters. Say $_wakeWord then guess a letter!',
    );

    setState(() {
      _currentView = 'hm_playing';
      _statusText = 'Say $_wakeWord then guess a letter!';
      _currentOptionType = 'hm_playing';
    });

    // Start listening for wake word (Mode B)
    _startListening('wake_word');
  }

  // Mode B: handle letter guess (app auto-checks)
  Future<void> _hmHandleModeBLetterGuess(String letter) async {
    if (_hmWord == null) return;

    if (_hmWord!.contains(letter)) {
      // Correct — reveal all matching positions
      for (int i = 0; i < _hmWord!.length; i++) {
        if (_hmWord![i] == letter) {
          _hmRevealedLetters[i] = true;
        }
      }

      setState(() {});

      // Check win
      if (_hmRevealedLetters.every((r) => r == true)) {
        _hmGameOver = true;
        _hmPlayerWon = true;
        await _speak(
          'Yes! $letter is in the word! The word is ${_hmWord!}. You win!',
        );
        _hmEndGame(true);
        return;
      }

      final count = _hmWord!.split('').where((c) => c == letter).length;
      await _speak(
        'Yes! $letter appears $count ${count == 1 ? 'time' : 'times'}! Say $_wakeWord to guess another letter.',
      );

      setState(() {
        _statusText = 'Say $_wakeWord then guess a letter!';
      });

      // Delay to let the iOS audio session settle after system speaker announcement
      await Future.delayed(Duration(milliseconds: 500));
      await _startListening('wake_word');
    } else {
      // Wrong
      _hmWrongGuesses++;

      setState(() {});

      if (_hmWrongGuesses >= _hmMaxWrong) {
        _hmGameOver = true;
        _hmPlayerWon = false;
        await _speak(
          'No, $letter is not in the word. The word was ${_hmWord!}. I win!',
        );
        _hmEndGame(false);
        return;
      }

      final remaining = _hmMaxWrong - _hmWrongGuesses;
      await _speak(
        'No, $letter is not in the word. $remaining wrong ${remaining == 1 ? 'guess' : 'guesses'} left. Say $_wakeWord to guess another letter.',
      );

      setState(() {
        _statusText = 'Say $_wakeWord then guess a letter!';
      });

      // Delay to let the iOS audio session settle after system speaker announcement
      await Future.delayed(Duration(milliseconds: 500));
      await _startListening('wake_word');
    }
  }

  // Mode B: wake word detected, now listen for a letter
  Future<void> _hmHandleWakeWordForModeB() async {
    _stopListening();
    await _speak('What letter do you want to guess?');

    setState(() {
      _statusText = 'Listening for a letter...';
    });

    // Delay to let the audio session settle after the system announcement
    // On iOS, the audio routing change (forceSpeaker → routeToPersonal) needs time
    await Future.delayed(Duration(milliseconds: 500));

    // Use short pause for letter capture
    _startListening('hm_letter');
  }

  // ===== HANGMAN GAME OVER =====

  void _hmEndGame(bool playerWon) {
    _hmStopAlphabetScanning();
    _stopScanning();
    _stopListening();
    _hmGameOver = true;
    _hmPlayerWon = playerWon;

    String message;
    if (_hmMode == 'mode-a') {
      if (playerWon) {
        final word = _hmRevealedLetters
            .map((l) => l == false ? '_' : l)
            .join('');
        message =
            'I figured it out! The word is "$word". I made $_hmWrongGuesses wrong ${_hmWrongGuesses != 1 ? 'guesses' : 'guess'}.';
      } else {
        message =
            'Game Over! The hangman is complete. I used all $_hmMaxWrong wrong guesses.';
      }
    } else {
      if (playerWon) {
        message =
            'You got it! The word was "${_hmWord ?? ""}". $_hmWrongGuesses wrong ${_hmWrongGuesses != 1 ? 'guesses' : 'guess'} out of $_hmMaxWrong allowed.';
      } else {
        message =
            'Game Over! The word was "${_hmWord ?? ""}". You used all $_hmMaxWrong wrong guesses.';
      }
    }

    setState(() {
      _currentView = 'hm_game_over';
      _statusText = message;
      _currentOptions = ['Play Again', 'Go Back'];
      _currentOptionType = 'hm_finished';
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 1000), () {
        if (mounted) _restartScanningForSelectionStep();
      });
    }
  }

  void _hmHandleFinished(String option) {
    _hmStopAlphabetScanning();
    _stopScanning();
    _stopListening();
    if (option == 'Play Again') {
      _startHangman();
    } else if (option == 'Go Back') {
      _hmExitToMenu();
    }
  }

  void _hmExitToMenu() {
    _hmStopAlphabetScanning();
    _stopScanning();
    _stopListening();
    setState(() {
      _selectedGame = null;
      _currentView = 'menu';
      _currentOptions.clear();
      _currentOptionType = '';
      _statusText = 'Select a game';
    });
  }

  void _hmGoBack() {
    _hmStopAlphabetScanning();
    _stopScanning();
    _stopListening();

    if (_currentView == 'hm_mode_selection') {
      // Go back to category selection
      _hmLoadCategories();
    } else if (_currentView == 'hm_word_selection') {
      // Go back to mode selection
      _deferSelectionScanning = true;
      setState(() {
        _currentOptions = ['I guess', 'You guess'];
        _currentOptionType = 'hm_mode';
        _currentView = 'hm_mode_selection';
        _statusText = 'Who is guessing?';
      });
      if (_enableScanning && mounted) {
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _deferSelectionScanning = false;
            _restartScanningForSelectionStep(announceWaitPrompt: false);
          }
        });
      } else {
        _deferSelectionScanning = false;
      }
    } else if (_currentView == 'hm_category_selection') {
      _hmExitToMenu();
    } else {
      _hmExitToMenu();
    }
  }

  // ===== HANGMAN CUSTOM CATEGORIES MANAGEMENT =====

  // ===== HANGMAN CUSTOM CATEGORIES MANAGEMENT =====

  Future<void> _validateHangmanPin() async {
    final enteredPin = _hmPinController.text.trim();

    if (enteredPin.length < 3 || enteredPin.length > 10) {
      setState(() {
        _hmPinError = 'PIN must be 3-10 characters';
      });
      return;
    }

    try {
      // Get the PIN from settings provider
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final correctPin = settingsProvider.settings?.toolbarPIN ?? '1234';

      if (enteredPin == correctPin) {
        // PIN is correct - load current categories and show management dialog
        final categoriesToEdit = _hmCustomCategories.isNotEmpty
            ? _hmCustomCategories
            : _hmDefaultCategories;

        setState(() {
          _showHmPinDialog = false;
          _hmPinController.clear();
          _hmPinError = '';
          _hmCategoriesController.text = categoriesToEdit.join('\n');
          _showHmCategoriesDialog = true;
        });
      } else {
        setState(() {
          _hmPinError = 'Invalid PIN. Please try again.';
          _hmPinController.clear();
        });
      }
    } catch (e) {
      debugPrint('Error validating PIN: $e');
      setState(() {
        _hmPinError = 'Error validating PIN';
      });
    }
  }

  Future<void> _saveHangmanCategories() async {
    final categories = _hmCategoriesController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter at least one category')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse(
          '${EnvironmentConfig.apiBaseUrl}/api/hangman/custom-categories',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({'categories': categories}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _showHmCategoriesDialog = false;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully saved ${categories.length} custom categories!',
            ),
          ),
        );

        // Reload categories to show the updated list
        if (_currentView == 'hm_category_selection') {
          await _hmLoadCategories();
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save categories. Please try again.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving categories: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving categories: $e')));
    }
  }

  Future<void> _resetHangmanCategoriesToDefaults() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset to Default Categories?'),
        content: Text(
          'Are you sure you want to reset to default categories? This will remove all custom categories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.delete(
        Uri.parse(
          '${EnvironmentConfig.apiBaseUrl}/api/hangman/custom-categories',
        ),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _showHmCategoriesDialog = false;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully reset to default categories!')),
        );

        // Reload categories to show the defaults
        if (_currentView == 'hm_category_selection') {
          await _hmLoadCategories();
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset categories. Please try again.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error resetting categories: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error resetting categories: $e')));
    }
  }

  // ===== GUESS GAME METHODS (Guess Who / Guess Where / Guess What) =====

  void _resetGuessGameState() {
    _guessMode = null;
    _guessCategory = null;
    _guessSelectedPerson = null;
    _guessCluesGiven = [];
    _guessCluesAvailable = [];
    _guessGuessesRemaining = 3;
    _guessGuessesAttempted = [];
    _guessCurrentGuess = null;
    _guessPeopleOptions = [];
    _guessGuessOptionsAll = [];
    _guessGuessOptionsShown = [];
    _guessResponseOptions = [];
    _guessClueTextMap = {};
    _guessGameResult = {};
    _guessModeBListeningForClue = false;
    _isGuessConfirmationInProgress = false;
  }

  void _startGuessGame(String gameType) async {
    _guessGameType = gameType;
    _resetGuessGameState();

    _deferSelectionScanning = true;
    setState(() {
      _selectedGame = 'guess_$gameType';
      _currentView = 'loading';
      _isLoading = true;
      _statusText = 'Loading categories...';
    });

    // Wait for announcement to finish before loading categories
    await _speak("Let's play ${_guessConfig['title']}!");

    await _loadGuessCategories();
  }

  Future<void> _loadGuessCategories() async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
    });

    try {
      final response = await http.post(
        Uri.parse(_getGuessApiUrl('categories')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final categories = List<String>.from(data['all_categories'] ?? []);

        _deferSelectionScanning = true;
        setState(() {
          _currentOptions = categories;
          _currentOptionType = 'guess_category';
          _currentView = 'guess_category_selection';
          _statusText = 'Select a category';
          _isLoading = false;
        });

        if (_enableScanning && mounted) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _deferSelectionScanning = false;
              _restartScanningForSelectionStep(announceWaitPrompt: false);
            }
          });
        } else {
          _deferSelectionScanning = false;
        }
      } else {
        debugPrint('Error loading guess categories: ${response.statusCode}');
        debugPrint('Error response body: ${response.body}');
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading guess categories: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error loading categories. Please try again.';
        _currentView = 'guess_category_selection';
      });
    }
  }

  void _selectGuessCategory(String category) {
    _stopScanning();
    _guessCategory = category;
    // Show immediate visual feedback
    setState(() {
      _currentView = 'loading';
      _statusText = '$category selected';
    });
    _speak('$category.').then((_) => _showGuessModeSelection());
  }

  void _showGuessModeSelection() {
    _deferSelectionScanning = true;
    setState(() {
      _currentView = 'guess_mode_selection';
      _currentOptions = ['I pick', 'You pick'];
      _currentOptionType = 'guess_mode';
      _statusText = 'Who will pick the ${_guessConfig['itemType']}?';
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep();
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  void _selectGuessMode(String mode) {
    _stopScanning();
    if (mode == 'I pick') {
      _startGuessGameModeA();
    } else {
      _startGuessGameModeB();
    }
  }

  // --- Mode A: Player picks an item, other player guesses verbally ---

  Future<void> _startGuessGameModeA() async {
    _guessMode = 'mode-a';

    setState(() {
      _currentView = 'loading';
      _isLoading = true;
      _statusText = 'Loading ${_guessConfig['itemTypePlural']}...';
    });

    // Wait for announcement to finish before loading items
    await _speak(
      'See if you can guess the ${_guessCategory} ${_guessConfig['itemType']} I am thinking of. Give me a moment to select.',
    );

    try {
      final response = await http.post(
        Uri.parse(_getGuessApiUrl('generate-people')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({'category': _guessCategory, 'previous_people': []}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _guessPeopleOptions = List<String>.from(data['people'] ?? []);

        _deferSelectionScanning = true;
        setState(() {
          _currentOptions = _guessPeopleOptions;
          _currentOptionType = 'guess_person';
          _currentView = 'guess_person_selection';
          _statusText = 'Choose your ${_guessConfig['itemType']}:';
          _isLoading = false;
        });

        if (_enableScanning) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _deferSelectionScanning = false;
              _restartScanningForSelectionStep();
            }
          });
        } else {
          _deferSelectionScanning = false;
        }
      } else {
        debugPrint('Error response: ${response.statusCode} - ${response.body}');
        throw Exception(
          'Failed to generate ${_guessConfig['itemTypePlural']}: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error generating ${_guessConfig['itemTypePlural']}: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error loading options. Please try again.';
      });
    }
  }

  Future<void> _refreshGuessPeopleOptions() async {
    _stopScanning();
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
    });

    try {
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

      final response = await http.post(
        Uri.parse(_getGuessApiUrl('generate-people')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'category': _guessCategory,
          'previous_people': _guessPeopleOptions,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _guessPeopleOptions = List<String>.from(data['people'] ?? []);

        _deferSelectionScanning = true;
        setState(() {
          _currentOptions = _guessPeopleOptions;
          _currentOptionType = 'guess_person';
          _currentView = 'guess_person_selection';
          _statusText = 'Choose your ${_guessConfig['itemType']}:';
          _isLoading = false;
        });

        if (_enableScanning) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _deferSelectionScanning = false;
              _restartScanningForSelectionStep();
            }
          });
        } else {
          _deferSelectionScanning = false;
        }
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error refreshing people options: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error refreshing options.';
      });
    }
  }

  Future<void> _selectGuessPerson(String person) async {
    _stopScanning();
    _guessSelectedPerson = person;

    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Generating clues...';
    });

    // Fire announcement in parallel with API call to reduce perceived delay
    _speak("I've made my selection. Give me a moment to pick my clues.");

    try {
      final response = await http.post(
        Uri.parse(_getGuessApiUrl('generate-clues')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'category': _guessCategory,
          'selected_person': person,
          'previous_clues': [],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _guessCluesAvailable = List<dynamic>.from(data['clues'] ?? []);
        _guessCluesGiven = [];
        _guessGuessesRemaining = 3;
        _guessGuessesAttempted = [];

        _showGuessClueScreen();
      } else {
        debugPrint('Error response: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to generate clues: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating clues: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error generating clues. Please try again.';
      });
    }
  }

  void _showGuessClueScreen() {
    // Check if max clues reached
    if (_guessCluesGiven.length >= 3) {
      if (_guessGuessesRemaining <= 0) {
        _guessGameResult = {
          'won': false,
          'actualPerson': _guessSelectedPerson,
          'guessesAttempted': _guessGuessesAttempted,
          'guessesTotal': 3,
        };
        _endGuessGame();
      }
      return;
    }

    // Filter out already given clues
    final availableClues = _guessCluesAvailable.where((clueObj) {
      String clueText;
      if (clueObj is String) {
        clueText = clueObj;
      } else if (clueObj is Map) {
        clueText = (clueObj['text'] ?? clueObj['full'] ?? '').toString().trim();
      } else {
        clueText = clueObj.toString();
      }
      return !_guessCluesGiven.contains(clueText);
    }).toList();

    if (availableClues.isEmpty) {
      _refreshGuessClueOptions();
      return;
    }

    // Parse clues into display-friendly format
    List<String> clueDisplayOptions = [];
    Map<String, String> clueTextMap = {};

    for (var clueObj in availableClues) {
      String clueText;
      String clueSummary;

      if (clueObj is String) {
        clueText = clueObj;
        clueSummary = clueObj.length > 50
            ? '${clueObj.substring(0, 47)}...'
            : clueObj;
      } else if (clueObj is Map) {
        clueText = (clueObj['text'] ?? clueObj['full'] ?? '').toString().trim();
        clueSummary = (clueObj['summary'] ?? clueText).toString().trim();
      } else {
        clueText = clueObj.toString();
        clueSummary = clueText;
      }

      if (clueText.isNotEmpty) {
        clueDisplayOptions.add(clueSummary);
        clueTextMap[clueSummary] = clueText;
      }
    }

    _guessClueTextMap = clueTextMap;

    _deferSelectionScanning = true;
    setState(() {
      _currentOptions = clueDisplayOptions;
      _currentOptionType = 'guess_clue';
      _currentView = 'guess_clue_selection';
      _statusText =
          'Pick a clue to give | Clues given: ${_guessCluesGiven.length} | Guesses left: $_guessGuessesRemaining';
      _isLoading = false;
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep();
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  Future<void> _refreshGuessClueOptions() async {
    _stopScanning();
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
    });

    try {
      List<String> allShownClues = [
        ..._guessCluesGiven,
        ..._guessCluesAvailable.map(
          (c) =>
              c is Map ? (c['text'] ?? c.toString()).toString() : c.toString(),
        ),
      ];

      final response = await http.post(
        Uri.parse(_getGuessApiUrl('generate-clues')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'category': _guessCategory,
          'selected_person': _guessSelectedPerson,
          'previous_clues': allShownClues,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _guessCluesAvailable = List<dynamic>.from(data['clues'] ?? []);
        _showGuessClueScreen();
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error refreshing clues: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error refreshing clues.';
      });
    }
  }

  Future<void> _selectGuessClue(String clueSummary) async {
    _stopScanning();
    _stopListening();

    String fullClue = _guessClueTextMap[clueSummary] ?? clueSummary;
    _guessCluesGiven.add(fullClue);

    int clueIndex = _guessCluesGiven.length;

    // Disable WakeWordService for speech recognition
    await WakeWordService.forceStopAndReset();
    WakeWordService.wakeWordShouldBeActive = false;

    setState(() {
      _currentView = 'guess_listening';
      _statusText =
          'Clue $clueIndex: $fullClue\n\nSay "$_wakeWord" when ready to guess.';
      _currentOptions.clear();
      _currentOptionType = '';
    });

    await _speak(
      'Clue $clueIndex: $fullClue. Say $_wakeWord when you are ready to guess.',
    );

    await _startListeningWithGuard(
      'wake_word',
      preListenDelay: const Duration(milliseconds: 1800),
      ignoreWindow: const Duration(milliseconds: 4000),
    );
  }

  // Mode A: Wake word detected - start listening for verbal guess
  Future<void> _handleGuessWakeWordDetected() async {
    if (_isWakeWordTransitionInProgress) {
      debugPrint('Guess game: [WAKE_WORD] Transition already in progress');
      return;
    }
    _isWakeWordTransitionInProgress = true;
    _stopListening();

    if (_guessMode == 'mode-b') {
      // Mode B: wake word means they're about to give a clue
      await _handleGuessWakeWordForClue();
    } else {
      // Mode A: wake word means they're about to guess
      setState(() {
        _statusText = 'Listening for your guess...';
      });
      await _speak('Listening for your guess.');
      _guessModeBListeningForClue = false;
      _startGuessNoInputTimeoutWindow();
      await _startListeningWithGuard(
        'player_guess',
        preListenDelay: const Duration(milliseconds: 1200),
        ignoreWindow: const Duration(milliseconds: 3000),
      );
    }
    _isWakeWordTransitionInProgress = false;
  }

  // Mode A: Verbal guess captured
  Future<void> _handleGuessPlayerGuess(String guessText) async {
    _clearGuessNoInputTimeoutWindow();
    _stopListening();
    _guessGuessesAttempted.add(guessText);
    _guessGuessesRemaining--;

    setState(() {
      _statusText = 'Processing guess: "$guessText"';
    });

    await _speak(
      'Ok. I hear your guess $guessText. Give me a moment to respond.',
    );

    // Determine if guess is correct (client-side, same as web app)
    final selectedLower = (_guessSelectedPerson ?? '').toLowerCase();
    final guessLower = guessText.toLowerCase();
    final isCorrect =
        guessLower.contains(selectedLower) ||
        selectedLower.contains(guessLower.split(' ').first);

    _showGuessResponseOptions(guessText, isCorrect);
  }

  void _showGuessResponseOptions(String guessText, bool isCorrect) {
    List<Map<String, dynamic>> responseOptions;

    if (isCorrect) {
      responseOptions = [
        {'text': "Yes! That's right!", 'is_correct': true},
        {'text': 'Correct! You got it!', 'is_correct': true},
        {'text': 'Nice job! You guessed it!', 'is_correct': true},
        {'text': "That's the one!", 'is_correct': true},
        {'text': 'You nailed it!', 'is_correct': true},
        {'text': 'Great guess! Correct!', 'is_correct': true},
      ];
    } else {
      responseOptions = [
        {'text': "No, that's not it.", 'is_correct': false},
        {'text': 'Not quite. Try again.', 'is_correct': false},
        {'text': 'Wrong guess!', 'is_correct': false},
        {'text': "Nope, that's not right.", 'is_correct': false},
        {'text': 'Sorry, incorrect.', 'is_correct': false},
        {'text': "That's not who I'm thinking of.", 'is_correct': false},
      ];
    }

    _guessResponseOptions = responseOptions;

    _deferSelectionScanning = true;
    setState(() {
      _currentOptions = responseOptions
          .map((r) => r['text'] as String)
          .toList();
      _currentOptionType = 'guess_response';
      _currentView = 'guess_response_selection';
      _statusText =
          'Player guessed: "$guessText" | Guesses left: $_guessGuessesRemaining';
      _isLoading = false;
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep();
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  Future<void> _handleGuessResponseSelection(String option) async {
    _stopScanning();

    final selected = _guessResponseOptions.firstWhere(
      (r) => r['text'] == option,
      orElse: () => {'text': option, 'is_correct': false},
    );
    final isCorrect = selected['is_correct'] == true;

    // Show immediate visual feedback
    setState(() {
      _statusText = option;
      _currentOptions.clear();
      _currentOptionType = '';
    });

    if (isCorrect) {
      // Combine into single announcement to reduce delay
      await _speak('$option You win!');
      _guessGameResult = {
        'won': true,
        'guess': _guessGuessesAttempted.last,
        'guessesUsed': 3 - _guessGuessesRemaining,
        'guessesTotal': 3,
      };
      _endGuessGame();
    } else if (_guessGuessesRemaining <= 0) {
      // Combine into single announcement and include the selected item
      final itemType = _guessConfig['itemType'] ?? 'answer';
      await _speak('$option I win! The $itemType was ${_guessSelectedPerson}.');
      _guessGameResult = {
        'won': false,
        'actualPerson': _guessSelectedPerson,
        'guessesAttempted': _guessGuessesAttempted,
        'guessesTotal': 3,
      };
      _endGuessGame();
    } else {
      // Combine response with next instruction
      await _speak('$option Give me a moment to select another clue.');
      _showGuessClueScreen();
    }
  }

  // --- Mode B: Player picks secretly, app tries to guess ---

  Future<void> _startGuessGameModeB() async {
    _guessMode = 'mode-b';
    _guessCluesGiven = [];
    _guessGuessesAttempted = [];
    _guessGuessesRemaining = 3;
    _guessGuessOptionsAll = [];
    _guessGuessOptionsShown = [];

    // Disable WakeWordService for speech recognition
    await WakeWordService.forceStopAndReset();
    WakeWordService.wakeWordShouldBeActive = false;

    setState(() {
      _currentView = 'guess_listening';
      _statusText =
          'Think of a ${_guessConfig['itemType']} in the category "$_guessCategory".\n\nSay "ready" when you have one in mind.';
      _currentOptions.clear();
      _currentOptionType = '';
    });

    await _speak(
      'Think of a ${_guessCategory} ${_guessConfig['itemType']}. Say ready when you have one in mind.',
    );
    await _startListeningWithGuard(
      'ready',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
  }

  // Mode B: "ready" heard
  Future<void> _handleGuessReadyHeard() async {
    _isReadyTransitionInProgress = true;

    setState(() {
      _statusText = 'Great! Say $_wakeWord when you have a clue.';
    });

    await _speak('Great! Say $_wakeWord when you have thought of a clue.');
    await _startListeningWithGuard(
      'wake_word',
      preListenDelay: const Duration(milliseconds: 1800),
      ignoreWindow: const Duration(milliseconds: 4000),
    );
    _isReadyTransitionInProgress = false;
  }

  // Mode B: Wake word detected, start listening for clue
  Future<void> _handleGuessWakeWordForClue() async {
    setState(() {
      _statusText = 'Listening for your clue...';
    });

    await _speak('Listening for your clue now.');
    _clearGuessClueSilenceTimer();
    _guessModeBListeningForClue = true;
    await _startListening('player_guess');
  }

  // Mode B: Clue captured from speech
  Future<void> _handleGuessClueHeard(String clueText) async {
    _clearGuessClueSilenceTimer();
    _stopListening();
    _guessModeBListeningForClue = false;
    _guessCluesGiven.add(clueText);

    setState(() {
      _statusText = 'Ok. "$clueText". Give me a moment to make a guess.';
      _isLoading = true;
      _currentView = 'loading';
    });

    await _speak('Ok. $clueText. Give me a moment to make a guess.');

    await _generateGuessModeBGuesses();
  }

  Future<void> _generateGuessModeBGuesses() async {
    try {
      final response = await http.post(
        Uri.parse(_getGuessApiUrl('generate-guesses')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'category': _guessCategory,
          'clues': _guessCluesGiven,
          'previous_guesses': _guessGuessesAttempted,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _guessGuessOptionsAll = List<String>.from(data['guesses'] ?? []);
        _guessGuessOptionsShown = [];

        _displayGuessModeBOptions();
      } else {
        debugPrint('Error response: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to generate guesses: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating guesses: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error generating guesses. Please try again.';
      });
    }
  }

  void _displayGuessModeBOptions() {
    final availableGuesses = _guessGuessOptionsAll
        .where((g) => !_guessGuessOptionsShown.contains(g))
        .toList();

    final guessesToShow = availableGuesses.take(5).toList();
    _guessGuessOptionsShown.addAll(guessesToShow);

    _deferSelectionScanning = true;
    setState(() {
      _currentOptions = guessesToShow;
      _currentOptionType = 'guess_guess';
      _currentView = 'guess_guess_selection';
      _statusText =
          'Select a guess | Guesses remaining: $_guessGuessesRemaining';
      _isLoading = false;
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _deferSelectionScanning = false;
          _restartScanningForSelectionStep();
        }
      });
    } else {
      _deferSelectionScanning = false;
    }
  }

  void _refreshGuessModeBGuessOptions() {
    _stopScanning();
    _displayGuessModeBOptions();
  }

  Future<void> _selectGuessModeBGuess(String guess) async {
    _stopScanning();
    _stopListening();
    _guessCurrentGuess = guess;

    setState(() {
      _currentView = 'guess_listening';
      _statusText = 'Is it $guess?\n\nPlease say "yes" or "no".';
      _currentOptions.clear();
      _currentOptionType = '';
    });

    await _speak('Is it $guess? Please say yes or no.');
    await _startListeningWithGuard(
      'yes_no_guess',
      preListenDelay: const Duration(milliseconds: 1200),
      ignoreWindow: const Duration(milliseconds: 3000),
    );
  }

  // Mode B: Handle yes/no confirmation of guess
  Future<void> _handleGuessModeBConfirmation(bool isCorrect) async {
    if (_isGuessConfirmationInProgress) {
      debugPrint(
        'Guess game: [CONFIRM] Confirmation already in progress, ignoring duplicate',
      );
      return;
    }
    _isGuessConfirmationInProgress = true;
    _stopListening();

    if (isCorrect) {
      _guessGameResult = {
        'won': true,
        'guess': _guessCurrentGuess,
        'cluesUsed': _guessCluesGiven.length,
        'guessesUsed': _guessGuessesAttempted.length + 1,
        'guessesTotal': 3,
      };
      await _speak('I win! Great game!');
      _isGuessConfirmationInProgress = false;
      _endGuessGame();
    } else {
      _guessGuessesAttempted.add(_guessCurrentGuess ?? '');
      _guessGuessesRemaining--;

      if (_guessGuessesRemaining <= 0) {
        _guessGameResult = {
          'won': false,
          'cluesGiven': _guessCluesGiven,
          'guessesUsed': 3,
          'guessesTotal': 3,
        };
        final itemType = _guessConfig['itemType'] ?? 'answer';
        await _speak('Darn! You win! Great game! What was the $itemType?');
        _isGuessConfirmationInProgress = false;
        _endGuessGame();
      } else {
        await _speak(
          "That's not it. Say $_wakeWord when you have another clue.",
        );

        setState(() {
          _currentView = 'guess_listening';
          _statusText =
              "That's not it.\n\nSay $_wakeWord when you have another clue.";
          _currentOptions.clear();
          _currentOptionType = '';
        });

        _isGuessConfirmationInProgress = false;
        await _startListening('wake_word');
      }
    }
  }

  // --- Guess Game End ---

  void _endGuessGame() {
    _stopListening();
    _stopScanning();

    String gameOverMessage = '';
    String gameOverDetails = '';

    if (_guessMode == 'mode-a') {
      if (_guessGameResult['won'] == true) {
        gameOverMessage = 'Correct! The guess was right!';
        gameOverDetails =
            'Used ${_guessGameResult['guessesUsed']} out of ${_guessGameResult['guessesTotal']} guesses.';
      } else {
        gameOverMessage = "Game Over! They didn't guess it.";
        gameOverDetails =
            'The ${_guessConfig['itemType']} was: ${_guessGameResult['actualPerson']}';
      }
    } else {
      if (_guessGameResult['won'] == true) {
        gameOverMessage = 'I win! I guessed "${_guessGameResult['guess']}"!';
        gameOverDetails =
            'I used ${_guessGameResult['cluesUsed']} clue${(_guessGameResult['cluesUsed'] as int?) == 1 ? '' : 's'} and ${_guessGameResult['guessesUsed']} guess${(_guessGameResult['guessesUsed'] as int?) == 1 ? '' : 'es'}.';
      } else {
        gameOverMessage = "You win! I couldn't guess it.";
        final cluesList =
            (_guessGameResult['cluesGiven'] as List?)?.join(', ') ?? '';
        gameOverDetails =
            'I used all ${_guessGameResult['guessesTotal']} guesses. Clues: $cluesList';
      }
    }

    setState(() {
      _currentView = 'guess_game_over';
      _statusText = '$gameOverMessage\n$gameOverDetails';
      _currentOptions = ['Play Again', 'Go Back'];
      _currentOptionType = 'guess_finished';
    });

    if (_enableScanning) {
      Future.delayed(Duration(milliseconds: 1000), () {
        if (mounted) _restartScanningForSelectionStep();
      });
    }
  }

  void _handleGuessGoBack() {
    _stopScanning();
    _stopListening();

    if (_currentOptionType == 'guess_category') {
      // Go back to game menu
      setState(() {
        _currentView = 'menu';
        _selectedGame = null;
        _currentOptions.clear();
        _currentOptionType = '';
        _statusText = 'Select a game';
      });
      // Re-enable WakeWordService
      WakeWordService.wakeWordShouldBeActive = true;
      WakeWordService.resumeWakeWordService();
    } else if (_currentOptionType == 'guess_mode') {
      // Go back to category selection
      _loadGuessCategories();
    } else if (_currentOptionType == 'guess_person') {
      // Go back to mode selection
      _showGuessModeSelection();
    } else if (_currentOptionType == 'guess_clue') {
      // Go back to person selection (re-fetch people)
      _startGuessGameModeA();
    } else if (_currentOptionType == 'guess_guess') {
      // Go back - Mode B, return to category selection since we can't undo clues
      _loadGuessCategories();
    }
  }

  void _handleGuessFinishedClick(String option) {
    _stopScanning();
    _stopListening();

    // Re-enable WakeWordService on exit
    WakeWordService.wakeWordShouldBeActive = true;
    WakeWordService.resumeWakeWordService();

    if (option == 'Play Again') {
      _startGuessGame(_guessGameType ?? 'who');
    } else if (option == 'Go Back') {
      setState(() {
        _currentView = 'menu';
        _selectedGame = null;
        _currentOptions.clear();
        _currentOptionType = '';
        _statusText = 'Select a game';
      });
    }
  }

  // ===== END GUESS GAME METHODS =====

  Future<void> _selectRole(String role) async {
    _stopScanning();

    setState(() {
      _role = role == 'I ask the questions' ? 'ask' : 'answer';
    });

    if (_role == 'ask') {
      // CRITICAL: Disable WakeWordService completely BEFORE announcement - this prevents auto-restart
      debugPrint(
        'Games page: [SELECT_ROLE] Disabling WakeWordService auto-restart permanently for this game...',
      );
      await WakeWordService.forceStopAndReset(); // Stop it completely
      WakeWordService.wakeWordShouldBeActive =
          false; // Prevent auto-restart (set AFTER forceStopAndReset to override any flags it sets)
      debugPrint(
        'Games page: [SELECT_ROLE] WakeWordService disabled successfully',
      );

      // Skip category selection and go straight to ready phase
      setState(() {
        _currentView = 'ready';
        _statusText = 'Waiting for you to say "ready"...';
      });
      await _speak(
        "I ask the questions. Say 'ready' when you have thought of something for me to guess",
      );
      await _startListeningWithGuard(
        'ready',
        preListenDelay: const Duration(milliseconds: 1200),
        ignoreWindow: const Duration(milliseconds: 3000),
      );
    } else {
      await _speak(
        'You ask the questions.  Give me a moment to pick something for you to guess',
      );

      // Show category selection
      setState(() {
        _currentView = 'category_selection';
        _statusText = 'What category?';
        _currentOptions = ['Person', 'Place', 'Thing'];
        _currentOptionType = 'category';
      });

      if (_enableScanning) {
        _restartScanningForSelectionStep();
      }
    }
  }

  void _selectCategory(String category) {
    _stopScanning();

    setState(() {
      _category = category.toLowerCase();
      _currentView = 'loading';
    });

    _loadGameOptions();
  }

  Future<void> _loadGameOptions({bool requestDifferent = false}) async {
    setState(() {
      _isLoading = true;
      _statusText = 'Loading options...';
    });

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/options'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'game_type': '20_questions',
          'category': _category,
          'request_different': requestDifferent,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _currentOptions = List<String>.from(data['options']);
          _currentOptionType = 'select';
          _currentView = 'playing';
          _statusText = 'Choose your $_category:';
          _isLoading = false;
        });

        if (_enableScanning) {
          Future.delayed(
            Duration(milliseconds: 500),
            () => _restartScanningForSelectionStep(),
          );
        }
      } else {
        debugPrint('Error response status: ${response.statusCode}');
        debugPrint('Error response body: ${response.body}');
        throw Exception(
          'Failed to load options: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error loading options: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error loading options. Please try again.';
      });
    }
  }

  Future<void> _proceedAfterReady() async {
    debugPrint(
      'Games page: Proceeding after ready - stopping listening and scanning',
    );
    _stopListening();
    _stopScanning();

    setState(() {
      _currentView = 'loading';
      _statusText = 'Let me think of some questions...';
    });

    // Announcement is now combined in _handleSpeechResult to avoid duplicate announcements
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    await Future.delayed(
      Duration(
        milliseconds: settingsProvider.settings?.displaySplashtime ?? 3000,
      ),
    );

    await _loadQuestions();
    _isReadyTransitionInProgress = false;
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/questions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
        },
        body: jsonEncode({
          'game_type': '20_questions',
          'category': _category ?? 'unknown',
          'asked_questions': _askedQuestions,
          'question_count': _questionCount,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final questions = data['questions'] as List;

        // Parse questions - handle both old format (question/summary) and new format (text/summary)
        _questionData.clear();
        List<String> summaries = [];

        for (var q in questions) {
          if (q is Map) {
            // New format: {"text": "...", "summary": "..."}
            // Old format: {"question": "...", "summary": "..."}
            String fullQuestion = q['text'] ?? q['question'] ?? '';
            String summary = q['summary'] ?? fullQuestion;

            if (fullQuestion.isNotEmpty) {
              _questionData[summary] = fullQuestion;
              summaries.add(summary);
            }
          } else if (q is String) {
            // Fallback for old string format
            _questionData[q] = q;
            summaries.add(q);
          }
        }

        setState(() {
          _currentOptions = summaries;
          _currentOptionType = 'question';
          _currentView = 'playing';
          _statusText =
              'Questions remaining: ${_maxQuestions - _questionCount}';
          _isLoading = false;
        });

        // Restore focus immediately after state update
        _focusNode.requestFocus();

        if (_enableScanning) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _focusNode.requestFocus();
              FocusScope.of(context).requestFocus(_focusNode);
              _restartScanningForSelectionStep();
            }
          });
        }
      } else {
        debugPrint('Error response status: ${response.statusCode}');
        debugPrint('Error response body: ${response.body}');
        throw Exception(
          'Failed to load questions: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error loading questions: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error loading questions. Please try again.';
      });
    }
  }

  Future<void> _askQuestion(String summary) async {
    _stopScanning();
    _stopListening();

    // Get the full question from the summary
    String fullQuestion = _questionData[summary] ?? summary;

    setState(() {
      _currentView = 'awaiting_answer';
      _statusText = fullQuestion;
      _questionCount++;
    });

    // Combine question and yes/no prompt into one announcement
    await _speak('$fullQuestion. Please answer yes or no');

    // Start listening for yes/no answer immediately after announcement completes
    if (_currentView == 'awaiting_answer') {
      debugPrint('Starting to listen for yes/no answer');
      await _startListening('yes_no');
    }
  }

  void _recordAnswer(String answer) {
    _stopListening();

    // Get the last asked question (the current status text)
    _askedQuestions.add({'question': _statusText, 'answer': answer});

    // Add to question history for display
    setState(() {
      _questionHistory.add({'question': _statusText, 'answer': answer});
    });

    // Don't announce the player's answer - just record it silently

    // Show action selection after a delay
    Future.delayed(Duration(seconds: 2), () {
      _showActionSelection();
    });
  }

  void _showActionSelection() {
    setState(() {
      _currentView = 'action_selection';
      _currentOptions = ['Ask another question', 'Make a guess'];
      _currentOptionType = 'action';
      _statusText = 'What would you like to do?';
    });

    if (_enableScanning) {
      _restartScanningForSelectionStep();
    }
  }

  void _handleActionSelection(String action) {
    _stopScanning();
    _focusNode.requestFocus();

    if (action == 'Ask another question' || action == 'Ask more questions') {
      if (_questionCount >= _maxQuestions) {
        _speak('No more questions left. You must make a guess.');
        Future.delayed(Duration(seconds: 2), () => _loadGuesses());
      } else {
        _speak('I want to ask another question. Give me a moment');
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        Future.delayed(
          Duration(
            milliseconds: settingsProvider.settings?.displaySplashtime ?? 3000,
          ),
          () => _loadQuestions(),
        );
      }
    } else {
      _speak('I want to make a guess, give me a moment');
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      Future.delayed(
        Duration(
          milliseconds: settingsProvider.settings?.displaySplashtime ?? 3000,
        ),
        () => _loadGuesses(),
      );
    }
  }

  Future<void> _loadGuesses() async {
    setState(() {
      _isLoading = true;
      _currentView = 'loading';
      _statusText = 'Thinking of possible answers...';
    });

    try {
      for (var attempt = 1; attempt <= 3; attempt++) {
        final response = await http.post(
          Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/games/guesses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${widget.idToken}',
            'X-User-ID': widget.aacUserId,
          },
          body: jsonEncode({
            'game_type': '20_questions',
            'category': _category ?? 'unknown',
            'asked_questions': _askedQuestions,
            'guess_count': _guessCount,
            'previous_guesses': _previousGuesses,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final guesses = _normalizeGuesses(data['guesses']);
          final hasGuessError =
              guesses.length == 1 && _looksLikeGuessError(guesses.first);

          if (hasGuessError && attempt < 3) {
            await Future.delayed(Duration(milliseconds: 250));
            continue;
          }

          if (hasGuessError) {
            debugPrint('Error response body: ${response.body}');
            setState(() {
              _isLoading = false;
              _currentView = 'action_selection';
              _currentOptions = ['Make a guess', 'Ask more questions'];
              _currentOptionType = 'action';
              _statusText = 'Trouble generating guesses. Try again.';
            });
            if (_enableScanning) {
              _restartScanningForSelectionStep();
            }
            return;
          }

          setState(() {
            _currentOptions = guesses;
            _currentOptionType = 'guess';
            _currentView = 'guessing';
            _statusText = 'Guesses remaining: ${_maxGuesses - _guessCount}';
            _isLoading = false;
          });

          if (_enableScanning) {
            Future.delayed(Duration(milliseconds: 500), () {
              _focusNode.requestFocus();
              _restartScanningForSelectionStep();
            });
          }
          return;
        } else {
          debugPrint('Error response status: ${response.statusCode}');
          debugPrint('Error response body: ${response.body}');
          throw Exception(
            'Failed to load guesses: ${response.statusCode} - ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading guesses: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'Error loading guesses. Please try again.';
      });
    }
  }

  List<String> _normalizeGuesses(dynamic rawGuesses) {
    if (rawGuesses is List) {
      return rawGuesses.map((g) => g.toString()).toList();
    }
    if (rawGuesses is String) {
      try {
        final decoded = jsonDecode(rawGuesses);
        if (decoded is List) {
          return decoded.map((g) => g.toString()).toList();
        }
      } catch (_) {
        // Fall through to return a single string entry.
      }
      return [rawGuesses];
    }
    if (rawGuesses == null) {
      return [];
    }
    return [rawGuesses.toString()];
  }

  bool _looksLikeGuessError(String guess) {
    final lower = guess.toLowerCase();
    return lower.contains('cannot') &&
        (lower.contains('json') || lower.contains('array'));
  }

  void _makeGuess(String guess) async {
    setState(() {
      _currentView = 'awaiting_verification';
      _statusText = 'Is it $guess?';
      _guessCount++;
    });

    _previousGuesses.add(guess);
    // Use yes/no for consistency
    await _speak('Is it $guess? Please say yes or no');

    // Start listening for yes/no answer immediately after announcement completes
    if (_currentView == 'awaiting_verification') {
      debugPrint('Starting to listen for yes/no answer on guess');
      await _startListening('yes_no_guess');
    }
  }

  void _handleGuessResult(bool isCorrect) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastGuessResultAtMs < 500) {
      debugPrint(
        'Games page: [DUPLICATE] Ignoring rapid duplicate guess result',
      );
      return;
    }
    _lastGuessResultAtMs = nowMs;
    _stopListening();

    if (isCorrect) {
      setState(() {
        _currentView = 'finished';
        _statusText = 'I win! Great game!';
        _currentOptions = ['Play Again', 'Return Home'];
        _currentOptionType = 'finished';
      });
      _speak('I win! Great game!');

      // Start scanning for end game options
      if (_enableScanning) {
        Future.delayed(Duration(milliseconds: 1000), () {
          _restartScanningForSelectionStep();
        });
      }
    } else {
      if (_guessCount >= _maxGuesses) {
        setState(() {
          _currentView = 'finished';
          _statusText = 'You win! I ran out of guesses. What was it?';
          _currentOptions = ['Play Again', 'Return Home'];
          _currentOptionType = 'finished';
        });
        _speak('You win! I ran out of guesses. What was it?');

        // Start scanning for end game options
        if (_enableScanning) {
          Future.delayed(Duration(milliseconds: 1000), () {
            _restartScanningForSelectionStep();
          });
        }
      } else {
        _speak('Hmm, that\'s not it.');
        Future.delayed(Duration(seconds: 2), () {
          setState(() {
            _currentView = 'action_selection';
            _currentOptions = ['Make another guess', 'Ask more questions'];
            _currentOptionType = 'action_guess';
            _statusText = 'What would you like to do?';
          });

          if (_enableScanning) {
            _restartScanningForSelectionStep();
          }
        });
      }
    }
  }

  Future<void> _exitGame() async {
    _stopScanning();
    _isExiting = true;
    _skipTtsStopOnDispose = true;
    await _flutterTts.stop();
    _stopListening();
    // Extra safety: ensure WakeWordService is resumed on exit
    debugPrint(
      'Games page: [EXIT_GAME] Exiting game, re-enabling WakeWordService...',
    );
    WakeWordService.wakeWordShouldBeActive = true; // Re-enable auto-restart
    WakeWordService.resumeWakeWordService();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Use Denver Broncos colors from main.dart
    final Color darkColor = Color(0xFF002244); // Navy blue
    final Color lightColor = Color(0xFFFB4F14); // Orange

    // Ensure focus is restored on every build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      }
    });

    return FocusScope(
      child: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKey: _handleKeyPress,
        child: Scaffold(
          body: Stack(
            children: [
              // Main content
              Column(
                children: [
                  // Custom Header matching main.dart style
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: darkColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            // Back button
                            IconButton(
                              icon: Icon(
                                Icons.arrow_back,
                                color: lightColor,
                                size: 28,
                              ),
                              onPressed: _exitGame,
                              padding: EdgeInsets.zero,
                            ),
                            // Page Title
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Games',
                                    style: TextStyle(
                                      color: lightColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (_selectedGame != null)
                                    Text(
                                      _isGuessGame
                                          ? (_guessConfig['title'] ??
                                                'Guess Game')
                                          : _selectedGame == '20_questions'
                                          ? '20 Questions'
                                          : _selectedGame == 'tic_tac_toe'
                                          ? 'Tic-Tac-Toe'
                                          : _selectedGame == 'hangman'
                                          ? 'Hangman'
                                          : _selectedGame == 'story_builder'
                                          ? 'Story Builder'
                                          : '',
                                      style: TextStyle(
                                        color: lightColor.withOpacity(0.8),
                                        fontSize: 12,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Lock icon for Hangman custom categories
                            if (_selectedGame == 'hangman' &&
                                _currentView == 'hm_category_selection')
                              IconButton(
                                icon: Icon(
                                  Icons.lock,
                                  color: lightColor,
                                  size: 24,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showHmPinDialog = true;
                                    _hmPinError = '';
                                    _hmPinController.clear();
                                  });
                                },
                                padding: EdgeInsets.zero,
                                tooltip: 'Manage Custom Categories',
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Status text area matching main.dart question box style
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        // Real-time transcript display while listening - PROMINENT
                        if (_isListening)
                          Column(
                            children: [
                              // Listening indicator with mic icon
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.mic,
                                      color: Colors.red,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Listening...',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Real-time transcript display
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.shade400,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'I hear:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _realtimeTranscript.isEmpty
                                          ? '(waiting...)'
                                          : '"$_realtimeTranscript"',
                                      style: TextStyle(
                                        fontSize: 20,
                                        color: Colors.blue.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        // Only show status text when NOT listening (to avoid redundancy)
                        if (!_isListening)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              _statusText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Loading indicator
                  if (_isLoading)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: lightColor,
                              strokeWidth: 4,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading...',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Content area
                  if (!_isLoading)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: _buildContent(darkColor, lightColor),
                      ),
                    ),

                  // Question / Story History Log
                  if ((_selectedGame == 'story_builder' &&
                          _storyTranscript.isNotEmpty) ||
                      _questionHistory.isNotEmpty)
                    Container(
                      height: 180,
                      margin: EdgeInsets.all(12),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: darkColor.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedGame == 'story_builder'
                                ? 'Story Q&A:'
                                : 'Questions Asked:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: darkColor,
                            ),
                          ),
                          SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              controller: _historyScrollController,
                              primary: false,
                              reverse: true, // Most recent at bottom
                              itemCount: _selectedGame == 'story_builder'
                                  ? _storyTranscript.length
                                  : _questionHistory.length,
                              itemBuilder: (context, index) {
                                final historySource =
                                    _selectedGame == 'story_builder'
                                    ? _storyTranscript
                                    : _questionHistory;
                                final qa =
                                    historySource[historySource.length -
                                        1 -
                                        index];
                                return Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Q: ${qa['question'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        'A: ${qa['answer'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: lightColor,
                                        ),
                                      ),
                                      if (index < historySource.length - 1)
                                        Divider(height: 8, thickness: 1),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              // Speech Bubble Overlay
              if (_showSpeechBubble)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(60),
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.grey[400]!,
                            width: 2,
                          ),
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
                              width: 90,
                              height: 90,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(45),
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline,
                                    size: 45,
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 30),
                            // Speech bubble text
                            Flexible(
                              child: Text(
                                _speechBubbleText,
                                style: const TextStyle(
                                  fontSize: 36,
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
              // Hangman PIN Dialog
              if (_showHmPinDialog) _buildHangmanPinDialog(lightColor),

              // Hangman Categories Management Dialog
              if (_showHmCategoriesDialog)
                _buildHangmanCategoriesDialog(darkColor, lightColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHangmanPinDialog(Color lightColor) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showHmPinDialog = false;
          _hmPinController.clear();
          _hmPinError = '';
        });
      },
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent taps from closing dialog
            child: Container(
              width: 350,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter Admin PIN',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 20),
                  TextField(
                    controller: _hmPinController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Enter PIN',
                      border: OutlineInputBorder(),
                      errorText: _hmPinError.isNotEmpty ? _hmPinError : null,
                    ),
                    onSubmitted: (_) => _validateHangmanPin(),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showHmPinDialog = false;
                            _hmPinController.clear();
                            _hmPinError = '';
                          });
                        },
                        child: Text('Cancel'),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _validateHangmanPin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: lightColor,
                        ),
                        child: Text('Submit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHangmanCategoriesDialog(Color darkColor, Color lightColor) {
    final categories = _hmCategoriesController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    return GestureDetector(
      onTap: () {
        setState(() {
          _showHmCategoriesDialog = false;
        });
      },
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent taps from closing dialog
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 650,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Manage Hangman Categories',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[900],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _showHmCategoriesDialog = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enter Categories (one per line):',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 10),
                            TextField(
                              controller: _hmCategoriesController,
                              maxLines: 10,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                hintText:
                                    'Animals\nFood\nSports\nMovies\nTV Shows\nColors\nCountries',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Tip: Enter one category per line. Empty lines are ignored.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 20),
                            Text(
                              'Preview (${categories.length} categories):',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 10),
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: categories.isEmpty
                                  ? Text(
                                      'Start typing to see preview...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey[400],
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: categories.asMap().entries.map((
                                        entry,
                                      ) {
                                        return Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[100],
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            '${entry.key + 1}. ${entry.value}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue[900],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Footer
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border(
                          top: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: _resetHangmanCategoriesToDefaults,
                            icon: Icon(Icons.restore),
                            label: Text('Reset to Defaults'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[600],
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _showHmCategoriesDialog = false;
                                  });
                                },
                                child: Text('Cancel'),
                              ),
                              SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _saveHangmanCategories,
                                icon: Icon(Icons.save),
                                label: Text('Save Categories'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: lightColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color darkColor, Color lightColor) {
    if (_currentView == 'menu') {
      return _buildGameMenu(darkColor, lightColor);
    } else if (_currentView == 'role_selection' ||
        _currentView == 'category_selection' ||
        _currentView == 'playing' ||
        _currentView == 'action_selection' ||
        _currentView == 'guessing' ||
        _currentView == 'response_selection' ||
        _currentView == 'guess_category_selection' ||
        _currentView == 'guess_mode_selection' ||
        _currentView == 'guess_person_selection' ||
        _currentView == 'guess_clue_selection' ||
        _currentView == 'guess_response_selection' ||
        _currentView == 'guess_guess_selection' ||
        _currentView == 'story_entry_menu' ||
        _currentView == 'story_selecting_answer' ||
        _currentView == 'story_selecting_title' ||
        _currentView == 'story_read_list' ||
        _currentView == 'story_post_actions') {
      return _buildOptionsGrid(darkColor, lightColor);
    } else if (_currentView == 'ready' ||
        _currentView == 'awaiting_answer' ||
        _currentView == 'awaiting_verification' ||
        _currentView == 'guess_listening') {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            _statusText,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_currentView == 'finished') {
      return _buildFinishedScreen(darkColor, lightColor);
    } else if (_currentView == 'guess_game_over') {
      return _buildFinishedScreen(darkColor, lightColor);
    } else if (_currentView == 'ttt_symbol_selection') {
      return _buildOptionsGrid(darkColor, lightColor);
    } else if (_currentView == 'ttt_board') {
      return _buildTicTacToeBoard(darkColor, lightColor);
    } else if (_currentView == 'ttt_game_over') {
      return _buildFinishedScreen(darkColor, lightColor);
    } else if (_currentView == 'hm_category_selection' ||
        _currentView == 'hm_mode_selection' ||
        _currentView == 'hm_word_selection') {
      return _buildOptionsGrid(darkColor, lightColor);
    } else if (_currentView == 'hm_playing') {
      return _buildHangmanPlayingScreen(darkColor, lightColor);
    } else if (_currentView == 'hm_position_selection') {
      return _buildHangmanPositionSelection(darkColor, lightColor);
    } else if (_currentView == 'hm_listening') {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            _statusText,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_currentView == 'hm_game_over') {
      return _buildFinishedScreen(darkColor, lightColor);
    }

    return Container();
  }

  Widget _buildGameMenu(Color darkColor, Color lightColor) {
    // Set up game options and scanning on first build of menu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentOptions.isEmpty && _currentView == 'menu') {
        setState(() {
          _currentOptions = [
            'Home',
            'Guess Who',
            'Guess Where',
            'Guess What',
            '20 Questions',
            'Tic-Tac-Toe',
            'Hangman',
            'Story Builder',
          ];
          _currentOptionType = 'game';
          _statusText = 'Select a game';
        });

        // Start scanning if enabled (respects waitForSwitchToScan internally)
        if (_enableScanning) {
          _startScanning();
        }
      }
    });

    // Build the game menu grid using the same sizing and styling as grid page
    return LayoutBuilder(
      builder: (context, constraints) {
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: true,
        );
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;

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

        final double gridPadding = 12;
        final double spacing = 10;
        final double availableWidth =
            constraints.maxWidth - gridPadding * 2 - spacing * (gridCols - 1);
        double effectiveButtonSize = buttonSizePx;
        if (availableWidth / gridCols < buttonSizePx) {
          effectiveButtonSize = (availableWidth / gridCols).clamp(
            40.0,
            buttonSizePx,
          );
        }
        final double fontSize = ((effectiveButtonSize / 10) * 1.5).clamp(
          8.0,
          12.0,
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            image: DecorationImage(
              image: AssetImage('assets/subtle_pattern.png'),
              fit: BoxFit.cover,
              opacity: 0.05,
              onError: (exception, stackTrace) {},
            ),
          ),
          padding: EdgeInsets.all(gridPadding),
          child: Scrollbar(
            controller: _menuScrollController,
            thumbVisibility: false,
            child: GridView.builder(
              controller: _menuScrollController,
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCols,
                childAspectRatio: 1.33,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: _currentOptions.length,
              itemBuilder: (context, index) {
                final option = _currentOptions[index];
                final isHighlighted = _isScanning && _currentScanIndex == index;

                return Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: SizedBox(
                    width: effectiveButtonSize,
                    height: effectiveButtonSize,
                    child: _buildGameMenuButton(
                      label: option,
                      isHighlighted: isHighlighted,
                      fontSize: fontSize,
                      lightColor: lightColor,
                      onTap: () => _handleOptionClick(option),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildGameMenuButton({
    required String label,
    required bool isHighlighted,
    required double fontSize,
    required Color lightColor,
    required VoidCallback onTap,
  }) {
    // Use TapInterfaceButton for Tap Interface mode (has pictogram support)
    if (widget.fromInterface == 'tap') {
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      return TapInterfaceButton(
        label: label,
        onPressed: onTap,
        backgroundColor: isHighlighted ? lightColor : Colors.white,
        foregroundColor: isHighlighted ? Colors.white : Colors.black87,
        borderColor: isHighlighted ? lightColor : Colors.grey.shade300,
        fontSize: fontSize,
        enablePictograms:
            true, // Always enable pictograms in Tap Interface mode
        sightWordGradeLevel: settingsProvider.settings?.sightWordGradeLevel,
        enableSightWords: settingsProvider.settings?.enableSightWords ?? true,
      );
    }

    // Original button styling for auditory scanning mode
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: _buildAutoSizingText(
                label,
                fontSize,
                Colors.black,
                FontWeight.w300,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutoSizingText(
    String label,
    double baseFontSize,
    Color textColor,
    FontWeight fontWeight,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final optimalFontSize = _calculateOptimalFontSize(
          label,
          baseFontSize,
          constraints.maxWidth,
          fontWeight,
        );

        return Text(
          label,
          textAlign: TextAlign.center,
          textScaleFactor: 1.0,
          softWrap: true,
          style: TextStyle(
            color: textColor,
            fontWeight: fontWeight,
            fontSize: optimalFontSize,
            fontFamily: _safeRobotoCondensed(),
          ),
        );
      },
    );
  }

  double _calculateOptimalFontSize(
    String text,
    double baseFontSize,
    double maxWidth,
    FontWeight fontWeight,
  ) {
    if (text.trim().isEmpty) return baseFontSize;

    final words = text.trim().split(RegExp(r'\s+'));

    bool fitsWithoutSplitting(double fontSize) {
      final double safeMaxWidth = maxWidth * 0.80;

      for (final word in words) {
        final wordPainter = TextPainter(
          textDirection: TextDirection.ltr,
          textScaleFactor: 1.0,
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

    double low = baseFontSize * 0.4;
    double high = baseFontSize * 1.5;
    double bestSize = low;

    for (int i = 0; i < 8; i++) {
      final mid = (low + high) / 2;
      if (fitsWithoutSplitting(mid)) {
        bestSize = mid;
        low = mid;
      } else {
        high = mid;
      }
    }

    return bestSize;
  }

  String? _safeRobotoCondensed() {
    return null;
  }

  Widget _buildOptionsGrid(Color darkColor, Color lightColor) {
    final allOptions = _getScanningOptions();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_currentView != _lastSelectionViewForScan) {
        _lastSelectionViewForScan = _currentView;
        if (_enableScanning &&
            allOptions.isNotEmpty &&
            !_deferSelectionScanning) {
          debugPrint('Games: Initializing scanning for view=$_currentView');
          _restartScanningForSelectionStep();
        }
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: true,
        );
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;

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

        final double gridPadding = 12;
        final double spacing = 10;
        final double availableWidth =
            constraints.maxWidth - gridPadding * 2 - spacing * (gridCols - 1);
        double effectiveButtonSize = buttonSizePx;
        if (availableWidth / gridCols < buttonSizePx) {
          effectiveButtonSize = (availableWidth / gridCols).clamp(
            40.0,
            buttonSizePx,
          );
        }
        final double fontSize = ((effectiveButtonSize / 10) * 1.5).clamp(
          8.0,
          12.0,
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            image: DecorationImage(
              image: AssetImage('assets/subtle_pattern.png'),
              fit: BoxFit.cover,
              opacity: 0.05,
              onError: (exception, stackTrace) {},
            ),
          ),
          padding: EdgeInsets.all(gridPadding),
          child: Scrollbar(
            controller: _optionsScrollController,
            thumbVisibility: false,
            child: GridView.builder(
              controller: _optionsScrollController,
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCols,
                childAspectRatio: 1.33,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: allOptions.length,
              itemBuilder: (context, index) {
                final option = allOptions[index];
                final isHighlighted = _isScanning && _currentScanIndex == index;

                return Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: SizedBox(
                    width: effectiveButtonSize,
                    height: effectiveButtonSize,
                    child: _buildGameMenuButton(
                      label: option,
                      isHighlighted: isHighlighted,
                      fontSize: fontSize,
                      lightColor: lightColor,
                      onTap: () => _handleOptionSelection(option),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionButton({
    required String option,
    required int index,
    required bool isScanned,
    required Color darkColor,
    required Color lightColor,
  }) {
    return GameOptionButton(
      option: option,
      isScanned: isScanned,
      darkColor: darkColor,
      lightColor: lightColor,
      fontSize: widget.fromInterface == 'tap' ? 18 : 22,
      onTap: () => _handleOptionSelection(option),
    );
  }

  Widget _buildTicTacToeBoard(Color darkColor, Color lightColor) {
    final available = _tttGetAvailableCells();
    // _tttScanIndex can be 0..avail.length where avail.length = Exit Game
    final isExitScanned = _tttIsScanning && _tttScanIndex == available.length;
    final scannedCellIndex =
        (_tttIsScanning &&
            available.isNotEmpty &&
            _tttScanIndex < available.length)
        ? available[_tttScanIndex]
        : -1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use available height for grid + exit button below
        // Grid takes ~80%, exit button takes the rest
        final gridSize = (constraints.maxHeight * 0.80).clamp(200.0, 380.0);
        final cellSize = (gridSize - 8) / 3; // each cell size (minus spacing)
        final fontSize = (gridSize / 7).clamp(24.0, 48.0);

        return Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The 3x3 grid
              SizedBox(
                width: gridSize,
                height: gridSize,
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: 9,
                  itemBuilder: (context, index) {
                    final cellValue = _tttBoard[index];
                    final isOccupied = cellValue.isNotEmpty;
                    final isScannedCell = (index == scannedCellIndex);

                    Color bgColor;
                    if (isScannedCell) {
                      bgColor = Colors.yellow.shade300;
                    } else if (isOccupied) {
                      bgColor = cellValue == _tttPlayer1Symbol
                          ? Colors.blue.shade100
                          : Colors.red.shade100;
                    } else {
                      bgColor = Colors.grey.shade200;
                    }

                    return GestureDetector(
                      onTap: () {
                        if (_tttGameOver) return;
                        if (isOccupied) return;

                        if (_tttIsPlayer1Turn) {
                          _tttPlaceSymbol(index, isPlayer1: true);
                        } else {
                          _tttPlaceSymbol(index, isPlayer1: false);
                        }
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isScannedCell
                                ? Colors.orange
                                : Colors.grey.shade400,
                            width: isScannedCell ? 3 : 1.5,
                          ),
                          boxShadow: isScannedCell
                              ? [
                                  BoxShadow(
                                    color: Colors.orange.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 2,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: Text(
                            cellValue,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              color: cellValue == _tttPlayer1Symbol
                                  ? Colors.blue.shade800
                                  : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Exit Game button below grid, styled like a grid cell
              SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  _tttStopScanning();
                  _stopScanning();
                  setState(() {
                    _selectedGame = null;
                    _currentView = 'menu';
                    _currentOptions.clear();
                    _currentOptionType = '';
                    _statusText = 'Select a game';
                  });
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: gridSize,
                  height: cellSize,
                  decoration: BoxDecoration(
                    color: isExitScanned
                        ? Colors.yellow.shade300
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isExitScanned
                          ? Colors.orange
                          : Colors.grey.shade400,
                      width: isExitScanned ? 3 : 1.5,
                    ),
                    boxShadow: isExitScanned
                        ? [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 2,
                              offset: Offset(1, 1),
                            ),
                          ],
                  ),
                  child: Center(
                    child: Text(
                      'Exit Game',
                      style: TextStyle(
                        fontSize: fontSize * 0.7,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===== HANGMAN UI WIDGETS =====

  Widget _buildHangmanPlayingScreen(Color darkColor, Color lightColor) {
    final available = _hmGetAvailableLetters();
    final isExitScanned =
        _hmIsAlphabetScanning && _hmAlphabetScanIndex == available.length;
    final scannedLetterIndex =
        (_hmIsAlphabetScanning &&
            available.isNotEmpty &&
            _hmAlphabetScanIndex < available.length)
        ? _hmAlphabetScanIndex
        : -1;
    final scannedLetter = scannedLetterIndex >= 0
        ? available[scannedLetterIndex]
        : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate sizes based on available space
        final maxHeight = constraints.maxHeight;
        final hangmanSize = (maxHeight * 0.28).clamp(120.0, 200.0);
        final blanksHeight = (maxHeight * 0.10).clamp(40.0, 70.0);

        return Column(
          children: [
            // Status / wrong count
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade400,
                    size: 20,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Wrong: $_hmWrongGuesses / $_hmMaxWrong',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),

            // Hangman figure
            SizedBox(
              height: hangmanSize,
              child: Center(
                child: CustomPaint(
                  size: Size(hangmanSize * 0.82, hangmanSize),
                  painter: _HangmanPainter(wrongGuesses: _hmWrongGuesses),
                ),
              ),
            ),

            SizedBox(height: 8),

            // Word blanks
            SizedBox(height: blanksHeight, child: _buildWordBlanks()),

            SizedBox(height: 8),

            // Alphabet grid (Mode A only shows tappable alphabet; Mode B shows as reference)
            Expanded(
              child: _buildAlphabetGrid(
                scannedLetter,
                isExitScanned,
                darkColor,
                lightColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWordBlanks() {
    if (_hmMode == 'mode-a') {
      // Mode A: We only know wordLength, not the actual word
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_hmWordLength, (i) {
            final revealed = _hmRevealedLetters[i];
            final letter = (revealed != false && revealed != true)
                ? revealed.toString()
                : '';
            return Container(
              width: 36,
              height: 48,
              margin: EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: letter.isNotEmpty ? Colors.green.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: letter.isNotEmpty
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            );
          }),
        ),
      );
    } else {
      // Mode B: We know the word
      if (_hmWord == null) return SizedBox.shrink();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_hmWord!.length, (i) {
            final char = _hmWord![i];
            final isLetter = RegExp(r'[A-Z]').hasMatch(char);
            final isRevealed = _hmRevealedLetters[i] == true;

            if (!isLetter) {
              // Space/hyphen
              return Container(
                width: 20,
                height: 48,
                margin: EdgeInsets.symmetric(horizontal: 2),
                child: Center(
                  child: Text(
                    char == ' ' ? '' : char,
                    style: TextStyle(fontSize: 20, color: Colors.grey),
                  ),
                ),
              );
            }

            return Container(
              width: 36,
              height: 48,
              margin: EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isRevealed ? Colors.green.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isRevealed
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  isRevealed ? char : '',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            );
          }),
        ),
      );
    }
  }

  Widget _buildAlphabetGrid(
    String scannedLetter,
    bool isExitScanned,
    Color darkColor,
    Color lightColor,
  ) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final letters = alphabet.split('');

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth;
        // 13 columns for better tablet landscape layout (2 rows: A-M, N-Z)
        final cols = 13;
        final cellSize = ((gridWidth - 32) / cols).clamp(30.0, 50.0);
        final fontSize = (cellSize * 0.5).clamp(12.0, 22.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Expanded(
                child: GridView.builder(
                  physics: NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: letters.length,
                  itemBuilder: (context, index) {
                    final letter = letters[index];
                    final isGuessed = _hmGuessedLetters.contains(letter);
                    final isScanned = (letter == scannedLetter);

                    // Determine color based on guess state
                    Color bgColor;
                    Color textColor;
                    if (isScanned) {
                      bgColor = Colors.yellow.shade300;
                      textColor = Colors.black87;
                    } else if (isGuessed) {
                      // Check if correct or wrong
                      if (_hmMode == 'mode-b' && _hmWord != null) {
                        bgColor = _hmWord!.contains(letter)
                            ? Colors.green.shade200
                            : Colors.red.shade200;
                        textColor = _hmWord!.contains(letter)
                            ? Colors.green.shade900
                            : Colors.red.shade900;
                      } else {
                        // Mode A: check if any revealed position has this letter
                        final wasCorrect = _hmRevealedLetters.any(
                          (l) => l.toString() == letter,
                        );
                        bgColor = wasCorrect
                            ? Colors.green.shade200
                            : Colors.red.shade200;
                        textColor = wasCorrect
                            ? Colors.green.shade900
                            : Colors.red.shade900;
                      }
                    } else {
                      bgColor = Colors.grey.shade100;
                      textColor = Colors.black87;
                    }

                    return GestureDetector(
                      onTap: () {
                        if (_hmGameOver || isGuessed) return;
                        // Mode A: Only allow taps during 'playing' phase
                        // Mode B: Allow taps anytime (tap interface support)
                        if ((_hmMode == 'mode-a' &&
                                _hmModeAPhase == 'playing') ||
                            _hmMode == 'mode-b') {
                          _hmHandleLetterSelected(letter);
                        }
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isScanned
                                ? Colors.orange
                                : (isGuessed
                                      ? Colors.transparent
                                      : Colors.grey.shade300),
                            width: isScanned ? 3 : 1,
                          ),
                          boxShadow: isScanned
                              ? [
                                  BoxShadow(
                                    color: Colors.orange.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Exit Game button
              SizedBox(height: 4),
              GestureDetector(
                onTap: () => _hmExitToMenu(),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: double.infinity,
                  height: cellSize,
                  decoration: BoxDecoration(
                    color: isExitScanned
                        ? Colors.yellow.shade300
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isExitScanned
                          ? Colors.orange
                          : Colors.grey.shade400,
                      width: isExitScanned ? 3 : 1.5,
                    ),
                    boxShadow: isExitScanned
                        ? [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      'Exit Game',
                      style: TextStyle(
                        fontSize: fontSize * 0.9,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  // Hangman position selection screen (Mode A: tap blanks where letter goes)
  Widget _buildHangmanPositionSelection(Color darkColor, Color lightColor) {
    final letter = _hmCurrentGuessedLetter ?? '';

    return Column(
      children: [
        // Hangman figure (smaller)
        SizedBox(
          height: 120,
          child: Center(
            child: CustomPaint(
              size: Size(100, 120),
              painter: _HangmanPainter(wrongGuesses: _hmWrongGuesses),
            ),
          ),
        ),

        SizedBox(height: 8),

        // Instruction
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Tap the blanks where "$letter" goes:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        SizedBox(height: 12),

        // Word blanks (tappable for position selection)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_hmWordLength, (i) {
              final revealed = _hmRevealedLetters[i];
              final alreadyRevealed = revealed != false;
              final isSelected = _hmSelectedPositions.contains(i);

              if (alreadyRevealed) {
                // Already revealed — show the letter, not selectable
                return Container(
                  width: 42,
                  height: 56,
                  margin: EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade400, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      revealed.toString(),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
              }

              // Unrevealed — tappable
              return GestureDetector(
                onTap: () => _hmTogglePosition(i),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: 42,
                  height: 56,
                  margin: EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade100 : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade600
                          : Colors.grey.shade400,
                      width: isSelected ? 3 : 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      isSelected ? letter : '',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        SizedBox(height: 16),

        // Done button
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: ElevatedButton(
            onPressed: _hmConfirmPositions,
            style: ElevatedButton.styleFrom(
              backgroundColor: darkColor,
              foregroundColor: Colors.white,
              minimumSize: Size(200, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Done',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFinishedScreen(Color darkColor, Color lightColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: true,
        );
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;

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

        final double gridPadding = 12;
        final double spacing = 10;
        final double availableWidth =
            constraints.maxWidth - gridPadding * 2 - spacing * (gridCols - 1);
        double effectiveButtonSize = buttonSizePx;
        if (availableWidth / gridCols < buttonSizePx) {
          effectiveButtonSize = (availableWidth / gridCols).clamp(
            40.0,
            buttonSizePx,
          );
        }
        final double fontSize = ((effectiveButtonSize / 10) * 1.5).clamp(
          8.0,
          12.0,
        );

        return Column(
          children: [
            // Buttons section at top using same style as other game buttons
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  image: DecorationImage(
                    image: AssetImage('assets/subtle_pattern.png'),
                    fit: BoxFit.cover,
                    opacity: 0.05,
                    onError: (exception, stackTrace) {},
                  ),
                ),
                padding: EdgeInsets.all(gridPadding),
                child: Scrollbar(
                  controller: _optionsScrollController,
                  thumbVisibility: false,
                  child: GridView.builder(
                    controller: _optionsScrollController,
                    primary: false,
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCols,
                      childAspectRatio: 1.33,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                    ),
                    itemCount: _currentOptions.length,
                    itemBuilder: (context, index) {
                      final option = _currentOptions[index];
                      final isScanned =
                          (_enableScanning && _currentScanIndex == index);

                      return Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: SizedBox(
                          width: effectiveButtonSize,
                          height: effectiveButtonSize,
                          child: GameOptionButton(
                            option: option,
                            isScanned: isScanned,
                            darkColor: darkColor,
                            lightColor: lightColor,
                            fontSize: fontSize,
                            onTap: () => _handleOptionSelection(option),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Status section with icon and text at bottom
            Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    _statusText.contains('win') && _statusText.contains('I win')
                        ? Icons.emoji_events
                        : Icons.celebration,
                    size: 80,
                    color: lightColor,
                  ),
                  SizedBox(height: 16),
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: darkColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleFinishedOptionClick(String option) {
    _stopScanning();

    if (option == 'Play Again') {
      setState(() {
        _currentView = 'menu';
        _selectedGame = null;
        _role = null;
        _category = null;
        _selectedItem = null;
        _currentQuestion = null;
        _currentGuess = null;
        _currentResponseType = '';
        _responseOptions.clear();
        _askedQuestions.clear();
        _previousGuesses.clear();
        _questionHistory.clear();
        _questionCount = 0;
        _guessCount = 0;
        _statusText = 'Select a game to play';
        _currentOptions.clear();
      });
    } else if (option == 'Return Home') {
      _exitGame();
    }
  }

  void _handleOptionSelection(String option) {
    if (_currentOptionType == 'guess_finished') {
      _handleGuessFinishedClick(option);
    } else if (_currentOptionType == 'guess_response') {
      _handleGuessResponseSelection(option);
    } else if (_currentOptionType == 'finished') {
      // Route to finished screen handler
      _handleFinishedOptionClick(option);
    } else if (_currentOptionType == 'response') {
      _handleResponseOptionSelection(option);
    } else if (_currentOptionType == 'ttt_finished') {
      _tttHandleFinished(option);
    } else if (_currentOptionType == 'hm_finished') {
      _hmHandleFinished(option);
    } else if (_currentOptions.contains(option)) {
      _handleOptionClick(option);
    } else if (option == 'Something Else') {
      _handleSomethingElse();
    } else if (option == 'Go Back') {
      if (_currentOptionType.startsWith('hm_')) {
        _hmGoBack();
      } else {
        _handleGuessGoBack();
      }
    } else if (option == 'Exit Game') {
      if (_selectedGame == 'hangman') {
        _hmExitToMenu();
      } else {
        _exitGame();
      }
    }
  }
}

// --- GameOptionButton Widget with Image Support ---
class GameOptionButton extends StatefulWidget {
  final String option;
  final bool isScanned;
  final Color darkColor;
  final Color lightColor;
  final double fontSize;
  final VoidCallback onTap;

  const GameOptionButton({
    Key? key,
    required this.option,
    required this.isScanned,
    required this.darkColor,
    required this.lightColor,
    required this.fontSize,
    required this.onTap,
  }) : super(key: key);

  @override
  _GameOptionButtonState createState() => _GameOptionButtonState();
}

class _GameOptionButtonState extends State<GameOptionButton> {
  String? _pictogramUrl;
  // ignore: unused_field
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPictogram();
  }

  @override
  void didUpdateWidget(GameOptionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.option != widget.option) {
      _loadPictogram();
    }
  }

  Future<void> _loadPictogram() async {
    // Skip image loading for special options
    if (widget.option == 'Something Else' ||
        widget.option == 'Exit Game' ||
        widget.option == 'Play Again' ||
        widget.option == 'Return Home') {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final pictogramService = PictogramService();
      // Use actual user settings for pictograms instead of hardcoding
      // pictogramService will read from settings automatically

      final result = await pictogramService.getPictogramResult(
        widget.option,
        shouldLogMissing: false,
      ); // Don't log missing images for game options

      if (mounted) {
        setState(() {
          _pictogramUrl = result?.imageUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(
        'Games page: Error loading pictogram for "${widget.option}": $e',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 1.0],
              colors: widget.isScanned
                  ? [Colors.white, widget.lightColor.withOpacity(0.5)]
                  : [Colors.white, Colors.white],
            ),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: widget.isScanned
                  ? widget.lightColor
                  : Colors.grey.shade300,
              width: widget.isScanned ? 3.0 : 1.0,
            ),
            boxShadow: widget.isScanned
                ? [
                    BoxShadow(
                      color: widget.lightColor.withOpacity(0.6),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.0),
            child: (_pictogramUrl != null && _pictogramUrl!.isNotEmpty)
                ? _buildWithImage()
                : _buildTextOnly(),
          ),
        ),
      ),
    );
  }

  Widget _buildWithImage() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Image layer - padded to make room for text at bottom
        Padding(
          padding: const EdgeInsets.only(
            top: 4.0,
            left: 4.0,
            right: 4.0,
            bottom: 30.0,
          ),
          child: Image.network(
            _pictogramUrl!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return SizedBox.shrink();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.lightColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Text layer - pinned to bottom with dark background strip
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(
              widget.option,
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w300,
                fontSize: widget.fontSize,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextOnly() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Text(
          widget.option,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w300,
            fontSize: widget.fontSize,
          ),
        ),
      ),
    );
  }
}

// ===== HANGMAN CUSTOM PAINTER =====
// Draws the gallows and body parts (shown bottom-up: legs, torso, arms, head)

class _HangmanPainter extends CustomPainter {
  final int wrongGuesses;

  _HangmanPainter({required this.wrongGuesses});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1e293b)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final gallowsPaint = Paint()
      ..color = const Color(0xFF1e293b)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Scale to fit size (designed for 180x220)
    final sx = size.width / 180;
    final sy = size.height / 220;

    // Gallows (always visible)
    // Base
    canvas.drawLine(
      Offset(20 * sx, 200 * sy),
      Offset(160 * sx, 200 * sy),
      gallowsPaint,
    );
    // Vertical pole
    canvas.drawLine(
      Offset(60 * sx, 200 * sy),
      Offset(60 * sx, 20 * sy),
      gallowsPaint,
    );
    // Horizontal beam
    canvas.drawLine(
      Offset(60 * sx, 20 * sy),
      Offset(120 * sx, 20 * sy),
      gallowsPaint,
    );
    // Rope
    canvas.drawLine(
      Offset(120 * sx, 20 * sy),
      Offset(120 * sx, 40 * sy),
      gallowsPaint,
    );

    // Body parts shown bottom-up based on wrong guesses
    // 1: Left leg
    if (wrongGuesses >= 1) {
      canvas.drawLine(
        Offset(120 * sx, 130 * sy),
        Offset(100 * sx, 170 * sy),
        paint,
      );
    }
    // 2: Right leg
    if (wrongGuesses >= 2) {
      canvas.drawLine(
        Offset(120 * sx, 130 * sy),
        Offset(140 * sx, 170 * sy),
        paint,
      );
    }
    // 3: Torso
    if (wrongGuesses >= 3) {
      canvas.drawLine(
        Offset(120 * sx, 80 * sy),
        Offset(120 * sx, 130 * sy),
        paint,
      );
    }
    // 4: Left arm
    if (wrongGuesses >= 4) {
      canvas.drawLine(
        Offset(120 * sx, 95 * sy),
        Offset(95 * sx, 115 * sy),
        paint,
      );
    }
    // 5: Right arm
    if (wrongGuesses >= 5) {
      canvas.drawLine(
        Offset(120 * sx, 95 * sy),
        Offset(145 * sx, 115 * sy),
        paint,
      );
    }
    // 6: Head
    if (wrongGuesses >= 6) {
      canvas.drawCircle(Offset(120 * sx, 58 * sy), 18 * sx, paint);
    }
  }

  @override
  bool shouldRepaint(_HangmanPainter oldDelegate) =>
      oldDelegate.wrongGuesses != wrongGuesses;
}
