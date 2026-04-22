import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/user_settings_provider.dart';
import 'services/pictogram_service.dart';
import 'services/sight_word_service.dart';

import 'services/audio_device_service.dart';
import 'services/wake_word_service.dart';
import 'config/environment_config.dart';
import 'services/tap_interface_service.dart';
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
import 'numbers_scan_page.dart';
import 'services/authenticated_http_client.dart';
import 'services/compose_document_service.dart';
import 'services/compose_session_service.dart';

// Font helper - using default system font to avoid AssetManifest.json errors on Android
String? _safeRobotoCondensed() {
  return null; // Use default system font (GoogleFonts causes unhandled async exceptions)
}

class _FreestyleNumberRange {
  final int start;
  final int end;
  final String label;

  const _FreestyleNumberRange({
    required this.start,
    required this.end,
    required this.label,
  });
}

class _FreestyleSpellingGridButton {
  const _FreestyleSpellingGridButton({
    required this.text,
    required this.rowIndex,
    required this.isEnabled,
    this.letter,
    this.isStandardOption = false,
    this.isChooseWordOption = false,
  });

  final String text;
  final int rowIndex;
  final bool isEnabled;
  final String? letter;
  final bool isStandardOption;
  final bool isChooseWordOption;
}

class _FreestyleCategoryNode {
  const _FreestyleCategoryNode({
    required this.label,
    required this.promptCategory,
    this.llmPrompt = '',
    this.wordsPrompt = '',
    this.children = const <_FreestyleCategoryNode>[],
  });

  final String label;
  final String promptCategory;
  final String llmPrompt;
  final String wordsPrompt;
  final List<_FreestyleCategoryNode> children;
}

class _FreestyleCategoryPanelEntry {
  const _FreestyleCategoryPanelEntry({
    required this.text,
    required this.action,
    this.node,
  });

  final String text;
  final String action;
  final _FreestyleCategoryNode? node;
}

class FreestylePage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;
  final String?
  sourceContext; // The context/topic from the originating page (LLM query)
  final String? sourcePage; // The page name that led to freestyle
  final bool isLLMGenerated; // Whether the source was LLM-generated
  final String?
  originatingButtonText; // The text of the button that started the LLM query
  final void Function(String text)? onComposeAppend;
  final bool composeMode;
  final ComposeSessionData? initialComposeSession;
  final String initialDocumentType;

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
    this.composeMode = false,
    this.initialComposeSession,
    this.initialDocumentType = 'story',
  });

  @override
  State<FreestylePage> createState() => _FreestylePageState();
}

class _FreestylePageState extends State<FreestylePage> {
  // --- Audio session initialization tracking ---
  static bool _audioSessionInitialized = false;
  static Set<String>? _commonSpellingWordsCache;
  static List<String>? _spellingFallbackWordsCache;
  static Set<String>? _spellingFallbackWordSetCache;
  static const Set<String> _spellingCommonWordBoosts = {
    'champ',
    'champion',
    'change',
    'chance',
    'chair',
    'chat',
    'check',
    'cheese',
    'child',
    'children',
    'chicken',
    'choice',
    'choose',
    'school',
    'friend',
    'family',
    'people',
    'water',
    'where',
    'what',
    'when',
    'want',
    'need',
    'play',
    'help',
    'happy',
    'because',
  };

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
  int _spellingPredictionOffset = 0;
  List<String> _validLetters = [];
  String _lastAnnouncedSpellingWord = '';
  String _availableCompletedSpellingWord = '';
  int _spellingPredictionRequestId = 0;

  // --- Choose Word Modal ---
  bool _isChooseWordModalOpen = false;
  String _currentChooseWordCategory = "";
  List<String> _currentCategoryWords = [];
  bool _isLoadingCategoryWords = false;
  _FreestyleCategoryNode? _selectedWordCategory;
  final List<_FreestyleCategoryNode> _categoryNavigationStack = [];
  String _activeToolPanel = 'categories';
  bool _isToolPanelVisible = false;
  _FreestyleNumberRange? _currentNumberRange;
  _FreestyleNumberRange? _selectedTopNumberRange;
  int _currentNumberPageOffset = 0;
  int _currentNumberBase = 0;

  // --- Context-Aware Features ---
  String _currentContext = ""; // Current context for word generation
  bool _isFirstRound =
      true; // Track if this is the first round (single words only)
  String _initialContext = ""; // Initial context (simplified for LLM pages)
  bool _initialIsFirstRound =
      true; // Initial first-round setting (false for LLM pages)

  // --- Compose Mode ---
  String? _composeDocumentId;
  String _composeDocumentType = 'story';
  String _composeTitle = '';
  String? _composeStartedAt;

  // Word categories for Choose Word feature
  static const List<_FreestyleCategoryNode> _fallbackWordCategories = [
    _FreestyleCategoryNode(label: 'Greetings', promptCategory: 'greetings'),
    _FreestyleCategoryNode(
      label: 'Ask',
      promptCategory: 'ask',
      llmPrompt:
          'Generate AAC-friendly starters, words, and short phrases for asking questions or making requests. When starting a sentence, strongly prefer natural openings like Can, Could, May, Will, Would, Please, What, Where, Why, How, Do, and Is.',
      wordsPrompt:
          'Generate AAC-friendly starters, words, and short phrases for asking questions or making requests. When starting a sentence, strongly prefer natural openings like Can, Could, May, Will, Would, Please, What, Where, Why, How, Do, and Is.',
      children: [
        _FreestyleCategoryNode(
          label: 'Question',
          promptCategory: 'questions',
          llmPrompt:
              'Generate question words and short AAC-friendly question phrases for asking about people, things, places, needs, choices, feelings, and preferences',
          wordsPrompt:
              'Generate question words and short AAC-friendly question phrases for asking about people, things, places, needs, choices, feelings, and preferences',
        ),
        _FreestyleCategoryNode(
          label: 'Request',
          promptCategory: 'requests',
          llmPrompt:
              'Generate AAC-friendly request starters, request words, and short request phrases for asking for help, objects, actions, comfort, food, drinks, and assistance. When starting a sentence, strongly prefer natural request openings like Can, Could, May, Will, Would, Please, I need, and I want.',
          wordsPrompt:
              'Generate AAC-friendly request starters, request words, and short request phrases for asking for help, objects, actions, comfort, food, drinks, and assistance. When starting a sentence, strongly prefer natural request openings like Can, Could, May, Will, Would, Please, I need, and I want.',
        ),
      ],
    ),
    _FreestyleCategoryNode(
      label: 'Respond',
      promptCategory: 'respond',
      llmPrompt:
          'Generate AAC-friendly response starters, words, and short phrases for responding to a question or request. When starting a sentence, strongly prefer natural response openings like Yes, No, Okay, Sure, Maybe, I can, I cannot, Please, Thank you, and Not right now.',
      wordsPrompt:
          'Generate AAC-friendly response starters, words, and short phrases for responding to a question or request. When starting a sentence, strongly prefer natural response openings like Yes, No, Okay, Sure, Maybe, I can, I cannot, Please, Thank you, and Not right now.',
    ),
    _FreestyleCategoryNode(label: 'People', promptCategory: 'people'),
    _FreestyleCategoryNode(label: 'Places', promptCategory: 'places'),
    _FreestyleCategoryNode(label: 'Things', promptCategory: 'things'),
    _FreestyleCategoryNode(label: 'Actions', promptCategory: 'actions'),
    _FreestyleCategoryNode(label: 'Describe', promptCategory: 'describe'),
    _FreestyleCategoryNode(label: 'Animals', promptCategory: 'animals'),
  ];
  List<_FreestyleCategoryNode> _wordCategories = _fallbackWordCategories;
  static const int _numberRangeSize = 100;
  static const int _numberPageSize = 20;
  static const List<int> _numberToolExpansions = [1000, 10000, 100000, 1000000];

  // --- Scanning ---
  Timer? _scanningTimer;
  int? _scanningIndex;
  bool _isScanning = false;
  FocusNode? _gridFocusNode;
  String _currentScanningContext =
      "main"; // "main", "spelling-letters", "spelling-predictions"
  int _currentScanCycle = 0;
  String _lastScanScopeKey = '';
  int _lastScannedIndex = -1;
  String _currentScanLevel = 'sections';
  String? _activeScanSection;
  String _lettersScanPhase = 'rows';
  int? _activeLetterRowIndex;
  bool _isScanningPaused = false;
  bool _waitingForUserInput = false;
  bool _isPausedFromScanLimit = false;
  bool _isAnnouncingScanningPrompt =
      false; // Track if announcing during scanning prompts (for Tab interrupt)

  // Wait-for-switch feature tracking
  bool _waitingForInitialSwitch = false;
  bool _switchStartRequested = false;
  DateTime? _lastWaitForSwitchNotificationAt;
  bool _isSpacebarDown = false;
  bool _isSpacebarDisabled = false;
  Timer? _spacebarHoldTimer;

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
  final List<AudioPlayer> _activeAudioPlayers = [];

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
  String? _scheduledStatusMessageText;

  // --- DISPOSAL TRACKING ---
  bool _disposeCalled = false; // Track if dispose has been called

  // --- WAKE WORD HEALTH CHECK ---
  Timer?
  _wakeWordHealthCheckTimer; // Periodic check to ensure wake word service is running

  // Fix the initState method - remove the blocking delay
  @override
  void initState() {
    super.initState();
    _flutterTts = FlutterTts();
    _gridFocusNode = FocusNode();
    _composeDocumentType = widget.initialDocumentType;

    // Initialize spelling word with valid letters
    _validLetters = _getAllLetters();

    // Initialize context-aware features
    _initializeContext();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.composeMode) {
        await _restoreComposeDraftIfNeeded();
      }

      await _loadComposeCategoryConfig();

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
      debugPrint(
        '🎤 Freestyle: Starting wake word service initialization in background',
      );
      _initializeWakeWordService()
          .then((_) {
            debugPrint(
              '🎤 Freestyle: Wake word service initialization completed',
            );
            // Start health check after wake word service is ready
            _startWakeWordHealthCheck();
          })
          .catchError((error) {
            debugPrint(
              '🎤 Freestyle: Wake word service initialization failed: $error',
            );
          });
    });
  }

  // Fix the initialization to completely stop any existing wake word service first
  Future<void> _initializeWakeWordService() async {
    try {
      debugPrint('🎤 Freestyle: _initializeWakeWordService - START');

      // CRITICAL FIX: Stop any existing wake word service completely before creating new one
      debugPrint(
        '🎤 Freestyle: Checking for existing WakeWordService instances and stopping them',
      );

      // If there's already a service running from main page, stop it completely
      if (_wakeWordService != null) {
        debugPrint(
          '🎤 Freestyle: Found existing WakeWordService, stopping it completely',
        );
        await _wakeWordService!.stopAllRecognizers();
        await _wakeWordService!.stopWakeWordListening();
        _wakeWordService = null;
      }

      // EXTRA SAFETY: Add delay to ensure old sessions are completely terminated
      debugPrint(
        '🎤 Freestyle: Waiting for old wake word sessions to terminate completely',
      );
      await Future.delayed(const Duration(milliseconds: 1000));

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );

      _wakeWordInterjection =
          (settingsProvider.settings?.wakeWordInterjection ?? 'hey')
              .trim()
              .toLowerCase();
      _wakeWordName = (settingsProvider.settings?.wakeWordName ?? 'bravo')
          .trim()
          .toLowerCase();
      _wakeWordVariants = [
        '${_wakeWordInterjection} ${_wakeWordName}',
        '${_wakeWordInterjection}, ${_wakeWordName}',
        '${_wakeWordInterjection},${_wakeWordName}',
      ];
      debugPrint(
        '🎤 Freestyle: Wake word variants configured: \'${_wakeWordVariants.join("' | '")}\'',
      );

      // CRITICAL: Create completely fresh WakeWordService instance
      debugPrint(
        '🎤 Freestyle: Creating completely fresh WakeWordService instance',
      );
      _wakeWordService = WakeWordService(wakeWords: _wakeWordVariants);

      // CRITICAL: Set global flag and IMMEDIATELY reset the _shouldRestartWakeWordListening flag
      debugPrint(
        '🎤 Freestyle: Setting WakeWordService.wakeWordShouldBeActive = true',
      );
      WakeWordService.wakeWordShouldBeActive = true;

      // CRITICAL FIX: IMMEDIATELY call resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true
      // This ensures the NEW service has the correct restart flag, regardless of old sessions
      debugPrint(
        '🎤 Freestyle: IMMEDIATELY calling resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true on NEW service',
      );
      _wakeWordService?.resumeWakeWordAutoRestart();

      // Set up callbacks AFTER resetting the flag
      debugPrint('🎤 Freestyle: Setting up callbacks');
      _initializeWakeWordCallbacks();

      setState(() {
        _microphoneEnabled = true;
      });

      debugPrint(
        '🎤 Freestyle: Wake word service initialization complete with fresh session',
      );
    } catch (e) {
      debugPrint('❌ Freestyle: Error initializing WakeWordService: $e');
    }
  }

  Future<void> _restoreComposeDraftIfNeeded() async {
    final initialSession = widget.initialComposeSession;
    if (initialSession != null && initialSession.active) {
      _applyComposeSession(initialSession);
      return;
    }

    final savedSession = await ComposeSessionService.load(widget.aacUserId);
    if (!mounted || !savedSession.active) {
      return;
    }

    _applyComposeSession(savedSession);
  }

  void _applyComposeSession(ComposeSessionData session) {
    setState(() {
      _composeDocumentId = session.documentId;
      _composeDocumentType = session.documentType.trim().isEmpty
          ? widget.initialDocumentType
          : session.documentType;
      _composeTitle = session.title;
      _composeStartedAt = session.startedAt;
      _buildSpaceText = session.text;
      _buildSpaceController.text = session.text;
      _currentContext = session.text.trim().isNotEmpty
          ? session.text
          : _currentContext;
      _isFirstRound = session.text.trim().isEmpty;
      _statusMessage = session.text.trim().isEmpty
          ? 'Ready to compose.'
          : 'Draft restored.';
    });
  }

  bool _shouldIncludeComposeCategory(TapInterfaceCategory node) {
    if (node.hidden) {
      return false;
    }

    final label = node.label.trim().toLowerCase();
    if (label.isEmpty) {
      return false;
    }

    if (label == 'entertainment' || label == 'numbers') {
      return false;
    }

    const skippedSpecialFunctions = {
      'spell',
      'games',
      'goto-home',
      'goto_home',
      'navigate',
    };
    final specialPage = (node.specialPage ?? '').trim().toLowerCase();
    if (skippedSpecialFunctions.contains(specialPage)) {
      return false;
    }

    return true;
  }

  _FreestyleCategoryNode _mapTapCategoryNode(TapInterfaceCategory node) {
    final visibleChildren = node.children
        .where(_shouldIncludeComposeCategory)
        .map(_mapTapCategoryNode)
        .toList(growable: false);

    final label = node.label.trim();
    final promptCategory =
        (node.promptCategory ?? '').trim().isNotEmpty
            ? node.promptCategory!.trim()
            : label.toLowerCase();
    return _FreestyleCategoryNode(
      label: label,
      promptCategory: promptCategory,
      llmPrompt: (node.llmPrompt ?? '').trim(),
      wordsPrompt: (node.wordsPrompt ?? '').trim(),
      children: visibleChildren,
    );
  }

  Future<void> _loadComposeCategoryConfig() async {
    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final tapService = TapInterfaceService(
        userSettingsProvider: settingsProvider,
      );
      final config = await tapService.fetchTapInterfaceConfig();
      if (!mounted || config == null) {
        return;
      }

      final categories = config.buttons
          .where(_shouldIncludeComposeCategory)
          .map(_mapTapCategoryNode)
          .toList(growable: false);
      if (categories.isEmpty) {
        return;
      }

      setState(() {
        _wordCategories = categories;
      });
    } catch (e) {
      debugPrint('FreestylePage: Failed to load compose category config: $e');
    }
  }

  Future<void> _persistComposeSession() async {
    if (!widget.composeMode) {
      return;
    }

    final session = ComposeSessionData(
      active: true,
      documentType: _composeDocumentType,
      documentId: _composeDocumentId,
      title: _composeTitle,
      text: _buildSpaceText,
      startedAt: _composeStartedAt ?? DateTime.now().toUtc().toIso8601String(),
      sourceFrom: widget.sourcePage ?? 'compose',
    );

    _composeStartedAt = session.startedAt;
    await ComposeSessionService.save(widget.aacUserId, session);
  }

  bool _isStartingNewSentenceForCategoryPrompt() {
    final text = _buildSpaceText.trimRight();
    if (text.isEmpty) {
      return true;
    }

    return text.endsWith('.') ||
        text.endsWith('!') ||
        text.endsWith('?') ||
        text.endsWith('\n');
  }

  String _ensureTerminalPunctuation(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    if (trimmed.endsWith('.') ||
        trimmed.endsWith('!') ||
        trimmed.endsWith('?') ||
        trimmed.endsWith('."') ||
        trimmed.endsWith('!"') ||
        trimmed.endsWith('?"') ||
        trimmed.endsWith(".'") ||
        trimmed.endsWith("!'") ||
        trimmed.endsWith("?'") ||
        trimmed.endsWith('.)') ||
        trimmed.endsWith('!)') ||
        trimmed.endsWith('?)') ||
        trimmed.endsWith('.]') ||
        trimmed.endsWith('!]') ||
        trimmed.endsWith('?]')) {
      return trimmed;
    }

    return '$trimmed.';
  }

  String _getContextFreeGeneralPrompt() {
    if (!widget.composeMode) {
      if (_isStartingNewSentenceForCategoryPrompt()) {
        return 'The user has finished one sentence and is starting a NEW sentence or row.\nGenerate broadly useful AAC words or short phrases that are appropriate for the BEGINNING of the next sentence.\n\nCRITICAL REQUIREMENTS:\n- Treat the existing build space as prior context only, not as a sentence fragment to continue.\n- Prioritize sentence starters, discourse starters, pronouns, articles, helper verbs, and common opening phrases.\n- Good examples of the kind of options to prefer: "I", "It", "The", "We", "Then", "Also", "After that", "Next", "Later", "They".\n- Avoid options that sound like they belong in the middle or end of the previous sentence.\n- The new sentence can stay on the same topic, but it must read like the START of a sentence.\n- Use current communication context when relevant, including current location, people present, activity, and the page or button the user came from.\n- Keep the suggestions useful for current AAC communication.\n- Return words or short phrases only.';
      }

      return 'Generate broadly useful AAC words or short phrases that naturally continue the current message being built.\nUse current communication context when relevant, including current location, people present, activity, and the page or button the user came from.\nKeep the suggestions useful for current AAC communication.\nReturn words or short phrases only.';
    }

    if (_isStartingNewSentenceForCategoryPrompt()) {
      return 'The user has finished one sentence and is starting a NEW sentence or row.\nGenerate broadly useful AAC words or short phrases that are appropriate for the BEGINNING of the next sentence.\n\nCRITICAL REQUIREMENTS:\n- Treat the existing build space as prior context only, not as a sentence fragment to continue.\n- Prioritize sentence starters, discourse starters, pronouns, articles, helper verbs, and common opening phrases.\n- Good examples of the kind of options to prefer: "I", "It", "The", "We", "Then", "Also", "After that", "Next", "Later", "They".\n- Avoid options that sound like they belong in the middle or end of the previous sentence.\n- The new sentence can stay on the same topic, but it must read like the START of a sentence.\n- The user is composing a message for someone who is not currently in the room.\n- Do not use the user\'s current location, people present, current activity, personal narrative, or any other live context.\n- Do not mention nearby people, the current room, or what is happening around the user unless it already appears in the message being composed.\n- Keep the suggestions general, everyday, and reusable across settings.\n- Avoid proper nouns unless they already appear in the current message.';
    }

    return 'Generate broadly useful AAC words or short phrases that naturally continue the current message being built.\nThe user is composing a message for someone who is not currently in the room.\nDo not use the user\'s current location, people present, current activity, personal narrative, or any other live context.\nDo not mention nearby people, the current room, or what is happening around the user unless it already appears in the message being composed.\nKeep the suggestions general, everyday, and reusable across settings.\nAvoid proper nouns unless they already appear in the current message.';
  }

  List<String> _getGeneralFallbackWords([int? maxOptions]) {
    final limit = maxOptions ?? _getSuggestedWordLimit();
    if (!widget.composeMode) {
      final fallbackWords = _isStartingNewSentenceForCategoryPrompt()
          ? const [
              'I',
              'It',
              'The',
              'We',
              'Then',
              'Also',
              'After that',
              'Next',
              'Later',
              'They',
            ]
          : const [
              'I',
              'want',
              'need',
              'can',
              'please',
              'help',
              'yes',
              'no',
            ];

      return fallbackWords.take(limit).toList();
    }

    final fallbackWords = _isStartingNewSentenceForCategoryPrompt()
        ? const [
            'I',
            'It',
            'The',
            'We',
            'Then',
            'Also',
            'After that',
            'Next',
            'Later',
            'They',
          ]
        : const [
            'I',
            'want',
            'to',
            'go',
            'more',
            'help',
            'with',
            'and',
            'the',
            'it',
          ];

    return fallbackWords.take(limit).toList();
  }

  String _getContextFreeCategoryPrompt(String categoryLabel) {
    if (!widget.composeMode) {
      if (_isStartingNewSentenceForCategoryPrompt()) {
        return "The user has finished one sentence and is starting a NEW sentence or row.\nGenerate AAC-friendly words or short phrases for the category '$categoryLabel' that are appropriate near the BEGINNING of a new sentence.\n\nCRITICAL REQUIREMENTS:\n- Treat the existing build space as prior context only, not as a sentence fragment to continue.\n- Prefer category words or short phrases that can sensibly appear at the start of a sentence.\n- Keep the new sentence connected to the overall topic, but make the options feel like sentence starters rather than mid-sentence continuations.\n- Avoid options that read like they belong after several words have already been spoken in the new sentence.\n- Use current communication context when relevant, including current location, people present, activity, and the page or button the user came from.\n- Keep the suggestions category-appropriate and useful for current AAC communication.";
      }

      return "Generate AAC-friendly words or short phrases for the category '$categoryLabel'.\nUse the current build space to help decide what could naturally come next.\nUse current communication context when relevant, including current location, people present, activity, and the page or button the user came from.\nKeep the suggestions category-appropriate and useful for current AAC communication.";
    }

    if (_isStartingNewSentenceForCategoryPrompt()) {
      return "The user has finished one sentence and is starting a NEW sentence or row.\nGenerate AAC-friendly words or short phrases for the category '$categoryLabel' that are appropriate near the BEGINNING of a new sentence.\n\nCRITICAL REQUIREMENTS:\n- Treat the existing build space as prior context only, not as a sentence fragment to continue.\n- Prefer category words or short phrases that can sensibly appear at the start of a sentence.\n- Keep the new sentence connected to the overall topic, but make the options feel like sentence starters rather than mid-sentence continuations.\n- Avoid options that read like they belong after several words have already been spoken in the new sentence.\n- The user is composing a message for someone who is not currently in the room.\n- Do not use the user's current location, people present, current activity, personal narrative, or any other live context.\n- Do not mention nearby people, the current room, or what is happening around the user unless it already appears in the message being composed.\n- For the People category, prefer general relationships, roles, or recipients rather than people physically present nearby.\n- Keep the suggestions category-appropriate, general, and useful across settings.";
    }

    return "Generate AAC-friendly words or short phrases for the category '$categoryLabel'.\nUse only the current message being built to help decide what could naturally come next.\nThe user is composing a message for someone who is not currently in the room.\nDo not use the user's current location, people present, current activity, personal narrative, or any other live context.\nDo not mention nearby people, the current room, or what is happening around the user unless it already appears in the message being composed.\nFor the People category, prefer general relationships, roles, or recipients rather than people physically present nearby.\nKeep the suggestions category-appropriate, general, and useful across settings.";
  }

  String _buildCategorySpecificPrompt(_FreestyleCategoryNode category) {
    final basePrompt = category.wordsPrompt.trim().isNotEmpty
        ? category.wordsPrompt.trim()
        : category.llmPrompt.trim();

    if (basePrompt.isEmpty) {
      return _getContextFreeCategoryPrompt(category.label);
    }

    String sentenceStartInstruction = _isStartingNewSentenceForCategoryPrompt()
        ? 'The user is starting a new sentence or row. Prefer options that can sensibly begin the next sentence while staying within the category intent.'
      : 'Use the current build space to decide what could naturally come next within this category.';

    final promptCategory = category.promptCategory.trim().toLowerCase();
    if (promptCategory == 'ask' && _isStartingNewSentenceForCategoryPrompt()) {
      sentenceStartInstruction =
          'The user is starting a new sentence or row. Prefer natural question and request openings such as Can, Could, May, Will, Would, Please, What, Where, Why, How, Do, and Is. Avoid mid-sentence fragments.';
    } else if (promptCategory == 'respond' &&
        _isStartingNewSentenceForCategoryPrompt()) {
      sentenceStartInstruction =
          'The user is starting a new sentence or row. Prefer natural response openings such as Yes, No, Okay, Sure, Maybe, I can, I cannot, Please, Thank you, and Not right now. Avoid mid-sentence response fragments.';
    } else if (promptCategory == 'requests' &&
        _isStartingNewSentenceForCategoryPrompt()) {
      sentenceStartInstruction =
          'The user is starting a new sentence or row. Prefer natural request openings and request starters such as Can, Could, May, Will, Would, Please, I need, and I want. Avoid mid-sentence request fragments.';
    }

    if (!widget.composeMode) {
      return '$basePrompt\n\nADDITIONAL FREESTYLE REQUIREMENTS:\n- $sentenceStartInstruction\n- Use current communication context when relevant, including current location, people present, activity, and the page or button the user came from.\n- Keep the options useful for current AAC communication.\n- Return words or short phrases only.';
    }

    return '$basePrompt\n\nADDITIONAL COMPOSE REQUIREMENTS:\n- $sentenceStartInstruction\n- The user is composing a message for someone who is not currently in the room.\n- Do not use the user\'s current location, people present, current activity, personal narrative, or any other live context unless the prompt above explicitly requires it.\n- Do not mention nearby people, the current room, or what is happening around the user unless it already appears in the message being composed.\n- For the People category, prefer general relationships, roles, or recipients rather than people physically present nearby.\n- Keep the options useful for composition and AAC communication.\n- Return words or short phrases only.';
  }

  Map<String, dynamic> _buildFreestyleRequestPayloadBase() {
    return {
      'context': _currentContext,
      'source_page': widget.sourcePage,
      'is_llm_generated': widget.isLLMGenerated,
      'originating_button_text': widget.originatingButtonText,
    };
  }

  List<Map<String, dynamic>> _buildLeadingMainButtons() {
    final buttons = <Map<String, dynamic>>[
      {
        'text': 'Speak Display',
        'icon': Icons.volume_up,
        'color': const Color(0xFF10B981),
        'action': _speakDisplayText,
      },
      {
        'text': 'Exit Page',
        'icon': Icons.logout,
        'color': const Color(0xFF0F766E),
        'action': () async {
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      },
      {
        'text': 'Backspace',
        'icon': Icons.backspace_outlined,
        'color': const Color(0xFFF59E0B),
        'action': _removeLastBuildSpaceUnit,
      },
      {
        'text': 'Clear',
        'icon': Icons.delete_outline,
        'color': const Color(0xFFEF4444),
        'action': _clearDisplayTextAsync,
      },
      {
        'text': 'Clean Up',
        'icon': Icons.auto_fix_high,
        'color': const Color(0xFF7C3AED),
        'action': _cleanUpBuildSpace,
      },
      {
        'text': 'New Row',
        'icon': Icons.keyboard_return,
        'color': const Color(0xFF3B82F6),
        'action': _insertBuildSpaceNewLine,
      },
      {
        'text': 'Go Back',
        'icon': Icons.arrow_back,
        'color': const Color(0xFF6B7280),
        'action': _resetActiveToolPanel,
      },
    ];

    return buttons;
  }

  Future<void> _clearDisplayTextAsync() async {
    _clearDisplayText();
  }

  Future<void> _startNewComposeDraft() async {
    setState(() {
      _composeDocumentId = null;
      _composeTitle = '';
      _composeDocumentType = widget.initialDocumentType;
      _composeStartedAt = DateTime.now().toUtc().toIso8601String();
      _buildSpaceText = '';
      _buildSpaceController.text = '';
      _currentContext = _initialContext;
      _isFirstRound = _initialIsFirstRound;
      _statusMessage = 'Started a new draft.';
    });
    await _persistComposeSession();
    await _loadWordOptions();
  }

  Future<void> _saveComposeDraft() async {
    final body = _buildSpaceText.trim();
    if (body.isEmpty) {
      setState(() {
        _statusMessage = 'Draft is empty. Add words before saving.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Saving draft...';
    });

    try {
      var title = _composeTitle.trim();
      if (title.isEmpty) {
        title = await ComposeDocumentService.generateTitle(
          widget.aacUserId,
          body,
        );
      }

      final saved = await ComposeDocumentService.saveDocument(
        widget.aacUserId,
        documentId: _composeDocumentId,
        documentType: _composeDocumentType,
        title: title,
        body: body,
      );

      setState(() {
        _composeDocumentId = saved.id;
        _composeTitle = saved.title;
        _composeDocumentType = saved.documentType;
        _statusMessage = 'Saved "${saved.title}".';
      });
      await _persistComposeSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Save failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _aiEditComposeDraft() async {
    final body = _buildSpaceText.trim();
    if (body.isEmpty) {
      setState(() {
        _statusMessage = 'Draft is empty. Add words before AI edit.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'AI editing draft...';
    });

    try {
      final edited = await ComposeDocumentService.aiEdit(
        widget.aacUserId,
        body,
      );
      setState(() {
        _buildSpaceText = edited;
        _buildSpaceController.text = edited;
        _currentContext = edited;
        _isFirstRound = false;
        _statusMessage = 'AI edit complete.';
      });
      await _persistComposeSession();
      await _loadWordOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'AI edit failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openComposeDocumentsSheet() async {
    setState(() {
      _statusMessage = 'Loading saved drafts...';
    });

    try {
      final documents = await ComposeDocumentService.listDocuments(
        widget.aacUserId,
      );
      if (!mounted) return;

      if (documents.isEmpty) {
        setState(() {
          _statusMessage = 'No saved drafts yet.';
        });
        return;
      }

      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Saved Drafts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: documents.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = documents[index];
                        final subtitle = [
                          doc.documentType,
                          doc.updatedAt.isNotEmpty
                              ? doc.updatedAt.substring(
                                  0,
                                  doc.updatedAt.length >= 10
                                      ? 10
                                      : doc.updatedAt.length,
                                )
                              : '',
                          doc.preview.trim(),
                        ].where((part) => part.trim().isNotEmpty).join('  |  ');
                        return ListTile(
                          title: Text(
                            doc.title.trim().isEmpty
                                ? 'Untitled Draft'
                                : doc.title,
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(
                            context,
                          ).pop({'action': 'open', 'doc': doc}),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => Navigator.of(
                              context,
                            ).pop({'action': 'delete', 'doc': doc}),
                          ),
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

      if (!mounted || result == null) {
        return;
      }

      final action = (result['action'] ?? '').toString();
      final doc = result['doc'] as ComposeDocument?;
      if (doc == null) {
        return;
      }

      if (action == 'delete') {
        await _deleteComposeDocument(doc);
        return;
      }

      setState(() {
        _composeDocumentId = doc.id;
        _composeDocumentType = doc.documentType;
        _composeTitle = doc.title;
        _buildSpaceText = doc.body;
        _buildSpaceController.text = doc.body;
        _currentContext = doc.body.trim().isNotEmpty
            ? doc.body
            : _initialContext;
        _isFirstRound = doc.body.trim().isEmpty;
        _statusMessage =
            'Loaded "${doc.title.trim().isEmpty ? 'Untitled Draft' : doc.title}".';
      });
      await _persistComposeSession();
      await _loadWordOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed to load drafts: $e';
      });
    }
  }

  Future<void> _deleteComposeDocument(ComposeDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Draft'),
          content: Text(
            'Delete "${doc.title.trim().isEmpty ? 'Untitled Draft' : doc.title}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Deleting draft...';
    });

    try {
      await ComposeDocumentService.deleteDocument(widget.aacUserId, doc.id);
      if (_composeDocumentId == doc.id) {
        setState(() {
          _composeDocumentId = null;
          _composeTitle = '';
          _buildSpaceText = '';
          _buildSpaceController.text = '';
          _currentContext = _initialContext;
          _isFirstRound = _initialIsFirstRound;
        });
        await _persistComposeSession();
      }
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Draft deleted.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Delete failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openNumbersTool() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NumbersScanPage(
          idToken: widget.idToken,
          aacUserId: widget.aacUserId,
          announceFunction:
              (
                String text, {
                String routing = 'system',
                int? speechRate,
                bool showSpeechBubble = true,
              }) {
                return _announceViaBackend(
                  text,
                  routing: routing,
                  speechRate: speechRate,
                  showSpeechBubble: showSpeechBubble,
                );
              },
          scanPromptFunction: (text) => _speakSystemVoice(text),
          onComposeAppend: (text) async {
            await _addWordToBuildSpace(text);
          },
        ),
      ),
    );
  }

  // Add a dedicated method to explicitly reset the _shouldRestartWakeWordListening flag
  void _ensureWakeWordAutoRestartEnabled() {
    debugPrint('🎤 Freestyle: _ensureWakeWordAutoRestartEnabled called');

    if (_wakeWordService == null) {
      debugPrint(
        '🎤 Freestyle: Wake word service is null, cannot reset restart flag',
      );
      return;
    }

    // Set global flag
    WakeWordService.wakeWordShouldBeActive = true;

    // CRITICAL: Reset the internal _shouldRestartWakeWordListening flag
    debugPrint(
      '🎤 Freestyle: Explicitly calling resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true',
    );
    _wakeWordService?.resumeWakeWordAutoRestart();

    debugPrint('🎤 Freestyle: Wake word auto-restart should now be enabled');
  }

  // Fix the _initializeWakeWordCallbacks method - remove the non-existent onError callback
  void _initializeWakeWordCallbacks() {
    if (_wakeWordService == null) return;

    debugPrint(
      '🎤 Freestyle: Setting up callbacks with exact main.dart pattern',
    );

    // EXACT SAME shouldAllowWakeWordRestart logic as main.dart
    _wakeWordService!.shouldAllowWakeWordRestart = () {
      final shouldAllow = mounted && !_disposeCalled;
      debugPrint(
        '🎤 Freestyle: shouldAllowWakeWordRestart called - returning: $shouldAllow (mounted: $mounted, disposeCalled: $_disposeCalled)',
      );
      return shouldAllow;
    };

    // Find the onWakeWord callback in _initializeWakeWordCallbacks() and replace it with this:
    _wakeWordService!.onWakeWord = (transcript) async {
      debugPrint(
        '🎤 Freestyle: Wake word detected - navigating back to main page and triggering wake word process: "$transcript"',
      );

      if (!mounted) {
        debugPrint('🎤 Freestyle: Widget not mounted, skipping navigation');
        return;
      }

      // Stop scanning on freestyle page immediately
      _stopAuditoryScanning();

      // Store the wake word detection for the main page to pick up
      debugPrint(
        '🎤 Freestyle: Setting global flag for main page wake word trigger',
      );
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
        debugPrint(
          '🎤 Freestyle: Detected timeout announcement - IMMEDIATELY restarting wake word service',
        );

        // CRITICAL: Immediately call resumeWakeWordAutoRestart to reset _shouldRestartWakeWordListening=true
        _wakeWordService?.resumeWakeWordAutoRestart();

        debugPrint(
          '🎤 Freestyle: Wake word service restarted after timeout announcement',
        );
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
      debugPrint(
        '🎤 Freestyle: Ensuring wake word auto-restart is enabled before restart',
      );
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
        debugPrint(
          '🎤 Freestyle: SUCCESS - service is now listening and _shouldRestartWakeWordListening should be TRUE',
        );
      } else {
        debugPrint(
          '🎤 Freestyle: WARNING - service may not be listening properly, trying one more reset',
        );

        // One more attempt
        _ensureWakeWordAutoRestartEnabled();
        await Future.delayed(const Duration(milliseconds: 300));
        await _wakeWordService!.startWakeWordListening();

        final finalListening = _wakeWordService!.isListening;
        debugPrint(
          '🎤 Freestyle: Final attempt result - isListening: $finalListening',
        );
      }
    } catch (e) {
      debugPrint('🎤 Freestyle: Error in _forceRestartWakeWordService: $e');
    }
  }

  // Remove the _startWakeWordHealthCheck method and replace with simple version
  void _startWakeWordHealthCheck() {
    // Since we're now using the exact main.dart pattern, we don't need aggressive restarts
    // Just keep a simple health check that logs the service status
    debugPrint(
      '🔍 FreestylePage: Wake word service initialized with main.dart pattern',
    );

    // Optional: Keep a very light health check every 60 seconds just for logging
    _wakeWordHealthCheckTimer = Timer.periodic(Duration(seconds: 60), (timer) {
      if (_disposeCalled || !mounted) {
        timer.cancel();
        return;
      }

      if (_wakeWordService != null) {
        final isListening = _wakeWordService!.isListening;
        debugPrint(
          '🔍 FreestylePage: Wake word service health check - isListening: $isListening',
        );
      }
    });
  }

  // Update dispose method
  @override
  void dispose() {
    _disposeCalled = true;

    _scanningTimer
        ?.cancel(); // Fixed: was scanningTimer, should be _scanningTimer
    _spacebarHoldTimer?.cancel();
    _speechBubbleTimer?.cancel();
    _wakeWordHealthCheckTimer?.cancel();
    _statusMessageTimer
        ?.cancel(); // This was also missing from the current dispose
    _buildSpaceDebounceTimer?.cancel(); // This was also missing

    // Clean up wake word service
    debugPrint('🎤 Freestyle: dispose - Cleaning up wake word service');
    if (_wakeWordService != null) {
      _wakeWordService!.stopWakeWordListening();
      _wakeWordService!.stopAllRecognizers();
    }

    _gridFocusNode
        ?.dispose(); // Fixed: was gridFocusNode, should be _gridFocusNode
    _buildSpaceController.dispose(); // This was also missing
    _spellingWordController.dispose(); // This was also missing

    super.dispose();
  }

  // --- Audio session initialization helper ---
  Future<void> _initializeAudioSession() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        debugPrint(
          '_initializeAudioSession: Starting audio session initialization...',
        );
        final platform = MethodChannel('audio_routing');
        final player = AudioPlayer();

        // Read volume settings for proper initialization (matches main page behavior)
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final userSettings = settingsProvider.settings;
        final personalVolume =
            userSettings?.personalVolume ?? userSettings?.applicationVolume ?? 10;
        final systemVolume =
            userSettings?.systemVolume ?? userSettings?.applicationVolume ?? 10;

        if (Platform.isIOS) {
          // Use setupOptimalAudioSession to preserve Bluetooth routing (matches main page)
          try {
            debugPrint(
              '_initializeAudioSession: Setting up optimal audio session with BT A2DP support...',
            );
            await platform.invokeMethod('setupOptimalAudioSession');
            debugPrint(
              '_initializeAudioSession: Optimal audio session setup completed',
            );
          } catch (e) {
            debugPrint(
              '_initializeAudioSession: Failed to setup optimal audio session: $e',
            );
          }

          // Warm up at personalVolumeLevel so Bluetooth pipeline initializes at the right level
          final personalVolumeLevel = personalVolume / 10.0;
          await player.setVolume(personalVolumeLevel);
          await player.setAsset('assets/silence.mp3');
          debugPrint(
            '_initializeAudioSession: Playing silence.mp3 to warm up audio session (volume=$personalVolumeLevel)...',
          );

          final completer = Completer<void>();
          final sub = player.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed) {
              if (!completer.isCompleted) completer.complete();
            }
          });
          await player.play();
          await completer.future;
          await sub.cancel();

          // Do NOT call resetToDefault — keep Bluetooth session active
          debugPrint(
            '_initializeAudioSession: iOS audio session initialized successfully (BT-aware)',
          );
        } else {
          // For Android: store both volumes (for forceSpeaker to use later)...
          await platform.invokeMethod('initializeAudioWithVolume', {
            'personalVolume': personalVolume,
            'systemVolume': systemVolume,
          });
          // ...then ALSO actually set the hardware audio stream to personalVolume,
          // matching what main.dart's _setApplicationVolume(isSystemSpeaker:false) does.
          // Without this, the hardware stream stays at whatever the last announcement
          // left it at, which can be louder than the intended personal-speaker level.
          await platform.invokeMethod('setApplicationVolume', {
            'applicationVolume': personalVolume,
            'isPersonal': true,
          });
          debugPrint(
            '_initializeAudioSession: Android hardware stream set to personalVolume: $personalVolume/10 (system stored: $systemVolume/10)',
          );

          // Play silence to warm up the audio pipeline
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

          debugPrint(
            '_initializeAudioSession: Android audio session initialized successfully',
          );
        }

        await player.dispose();
      } catch (e) {
        debugPrint(
          '_initializeAudioSession: Error initializing audio session: $e',
        );
      }
    }
  }

  // --- Context initialization ---
  void _initializeContext() {
    if (widget.composeMode) {
      _currentContext = 'compose a message';
      _initialContext = _currentContext;
      debugPrint(
        '🎯 FreestylePage: Compose mode initialized with neutral context: "$_currentContext"',
      );
      return;
    }

    // Initialize context based on source information
    String? rawContext = widget.sourceContext ?? 'general communication';

    // For LLM-generated pages, extract simple context from the prompt or use page name
    if (widget.isLLMGenerated == true && rawContext.length > 100) {
      // The context is likely an LLM generation prompt (contains formatting instructions)
      // Extract a simpler context for word option generation

      String simplifiedContext = widget.sourcePage ?? "general communication";

      // Strategy 1: Use originating button text if available (most reliable)
      if (widget.originatingButtonText != null &&
          widget.originatingButtonText!.isNotEmpty) {
        simplifiedContext = widget.originatingButtonText!;
        debugPrint(
          '🎯 FreestylePage: Using button text as context: "$simplifiedContext"',
        );
      } else {
        // Strategy 2: Extract meaningful keywords from the prompt
        // Look for topic descriptions like "activity suggestions", "greetings", "questions about"
        final keywordPatterns = [
          RegExp(r'(activity|action)\s+suggestions?', caseSensitive: false),
          RegExp(r'(greeting|hello|goodbye|farewell)s?', caseSensitive: false),
          RegExp(
            r'(question|inquiry|queries)s?\s+(?:about\s+)?(.+?)(?:\.|,|based)',
            caseSensitive: false,
          ),
          RegExp(r'(conversation\s+starters?|topics?)', caseSensitive: false),
          RegExp(r'(express|expressive)\s+(.+?)(?:\.|,)', caseSensitive: false),
        ];

        for (final pattern in keywordPatterns) {
          final match = pattern.firstMatch(rawContext);
          if (match != null) {
            // Use the matched phrase as context
            simplifiedContext = match.group(0)!.trim();
            // Clean up "based on..." trailing text
            simplifiedContext = simplifiedContext.replaceAll(
              RegExp(r'\s+based\s*$'),
              '',
            );
            debugPrint(
              '🎯 FreestylePage: Extracted context from prompt: "$simplifiedContext"',
            );
            break;
          }
        }
      }

      _currentContext = simplifiedContext;
      debugPrint(
        '🎯 FreestylePage: Simplified LLM context from "${rawContext.substring(0, 50)}..." to "$_currentContext"',
      );

      // For LLM-generated contexts, start with full phrases instead of single words
      // This ensures options match the LLM topic (e.g., full greetings, not just "hello")
      _isFirstRound = false;
      debugPrint(
        '🎯 FreestylePage: Starting with full phrases for LLM-generated content',
      );
    } else {
      _currentContext = rawContext;
      // For non-LLM pages (home, general), start with single words
      _isFirstRound = true;
    }

    // Store initial values for reset
    _initialContext = _currentContext;
    _initialIsFirstRound = _isFirstRound;

    debugPrint(
      '🎯 FreestylePage: Initialized with context: "$_currentContext" (LLM generated: ${widget.isLLMGenerated})',
    );
    debugPrint(
      '🎯 FreestylePage: Originating button: "${widget.originatingButtonText}"',
    );
    debugPrint('🎯 FreestylePage: Source page: "${widget.sourcePage}"');
    debugPrint('🎯 FreestylePage: First round (single words): $_isFirstRound');
  }

  // --- Auditory scanning methods ---
  void _maybeStartScanning() {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final isAuditoryEnabled =
        settingsProvider.settings?.enableAuditoryScanning ?? false;
    final waitForSwitch =
        settingsProvider.settings?.waitForSwitchToScan ?? false;

    debugPrint(
      'FreestylePage _maybeStartScanning: called, enableAuditoryScanning = $isAuditoryEnabled, waitForSwitch = $waitForSwitch, current _isScanning = $_isScanning',
    );

    if (!isAuditoryEnabled) {
      debugPrint(
        'FreestylePage _maybeStartScanning: Auditory scanning disabled, stopping any existing scanning',
      );
      _stopAuditoryScanning();
      return;
    }

    // Check if we should wait for switch press before starting
    if (waitForSwitch &&
        !_isScanning &&
        _currentWordOptions.isNotEmpty &&
        !_waitingForInitialSwitch) {
      debugPrint(
        'FreestylePage _maybeStartScanning: Waiting for switch press to begin scanning...',
      );
      setState(() {
        _waitingForInitialSwitch = true;
        _switchStartRequested = false;
      });
      unawaited(_playWaitForSwitchNotification());

      return; // IMPORTANT: Don't start scanning yet, wait for switch press
    }

    debugPrint('FreestylePage: Starting scanning');

    debugPrint(
      'FreestylePage _maybeStartScanning: Auditory scanning enabled, calling _startAuditoryScanning()',
    );
    _startAuditoryScanning();
    debugPrint('FreestylePage _maybeStartScanning: Method completed');
  }

  int _getEffectiveScanLoopLimit() {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final rawLimit = settingsProvider.settings?.scanLoopLimit;
    if (rawLimit == null) {
      return 0;
    }
    return rawLimit.clamp(0, 10).toInt();
  }

  String _getCurrentScanScopeKey() {
    if (_currentScanLevel == 'sections') {
      return 'sections:${_getSectionIdsInOrder().join('|')}';
    }

    switch (_activeScanSection) {
      case 'action':
        return 'action:${_buildLeadingMainButtons().map((button) => (button['text'] ?? 'Button').toString()).join('|')}';
      case 'choose-word':
        final visibleWords = _getVisibleSuggestedWords();
        return 'choose-word:${visibleWords.join('|')}|number:${_currentNumberRange?.label ?? ''}|spelling:${_currentSpellingWord.trim()}';
      case 'tool-toggle':
        return 'tool-toggle:Go Back|Word Categories|Spell|Numbers';
      case 'tool-panel':
        if (_activeToolPanel == 'numbers') {
          return 'tool-panel:numbers:${_buildNumberToolButtons().map((button) => (button['text'] ?? 'Button').toString()).join('|')}';
        }
        if (_activeToolPanel == 'spelling') {
          if (_lettersScanPhase == 'rows') {
            return 'tool-panel:spelling:rows:${_getVisibleLetterRowIndexes().join('|')}';
          }
          return 'tool-panel:spelling:items:${_activeLetterRowIndex ?? -1}:${_getSpellingButtonsForActiveRow().map((button) => button.text).join('|')}';
        }
        if (_currentScanningContext == 'choose-word-categories') {
          return 'tool-panel:categories:${_getCategoryPanelEntries().map((entry) => entry.text).join('|')}';
        }
        if (_currentScanningContext == 'choose-word-options') {
          return 'tool-panel:options:${_currentCategoryWords.join('|')}';
        }
        return 'tool-panel:${_activeToolPanel}:${_currentScanningContext}';
      default:
        return 'unknown:${_currentScanLevel}:${_activeScanSection ?? 'none'}:${_currentScanningContext}';
    }
  }

  Future<void> _startAuditoryScanning() async {
    debugPrint(
      'FreestylePage _startAuditoryScanning: called, current _isScanning=$_isScanning',
    );

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final waitForSwitch =
        settingsProvider.settings?.waitForSwitchToScan ?? false;

    if (waitForSwitch && !_switchStartRequested) {
      debugPrint(
        'FreestylePage _startAuditoryScanning: Switch not pressed, blocking scanning',
      );
      return;
    }

    // CRITICAL: Don't start scanning if we're waiting for the user to press switch
    if (_waitingForInitialSwitch) {
      debugPrint(
        'FreestylePage _startAuditoryScanning: Waiting for switch press, blocking scanning',
      );
      return;
    }

    if (_isScanning) {
      debugPrint(
        'FreestylePage _startAuditoryScanning: Already scanning, returning early',
      );
      return;
    }

    debugPrint(
      'FreestylePage _startAuditoryScanning: Setting scanning state variables',
    );
    final scanScopeKey = _getCurrentScanScopeKey();
    final shouldResetScanCycle = scanScopeKey != _lastScanScopeKey;
    setState(() {
      _isScanning = true;
      _scanningIndex = -1;
      if (shouldResetScanCycle) {
        _currentScanCycle = 0;
        _lastScannedIndex = -1;
      }
      _lastScanScopeKey = scanScopeKey;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _isPausedFromScanLimit = false;
      _switchStartRequested = false;
    });

    int delay = settingsProvider.settings?.scanDelay ?? 3500;
    debugPrint(
      'FreestylePage _startAuditoryScanning: Using scan delay of ${delay}ms',
    );
    _scanningTimer?.cancel();

    // Only setup immediate prompt + periodic timer for auto mode
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    debugPrint('FreestylePage _startAuditoryScanning: Scan mode: $scanMode');

    if (scanMode == 'auto') {
      debugPrint(
        'FreestylePage _startAuditoryScanning: Starting first scan step for auto mode...',
      );
      _performScanStep();
      debugPrint(
        'FreestylePage _startAuditoryScanning: Setting up periodic timer for auto mode...',
      );
      _scanningTimer = Timer.periodic(
        Duration(milliseconds: delay),
        (_) => _performScanStep(),
      );
    } else {
      debugPrint(
        'FreestylePage _startAuditoryScanning: Step mode - waiting for first Tab, timer not started',
      );
    }

    debugPrint('FreestylePage _startAuditoryScanning: Requesting focus');
    _gridFocusNode?.requestFocus();
    debugPrint(
      'FreestylePage _startAuditoryScanning: Setup complete, scanning should now be active',
    );
  }

  Future<void> _restartScanning({
    int delayMs = 0,
    bool resetToSections = false,
  }) async {
    _stopAuditoryScanning();
    if (delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    if (!mounted) {
      return;
    }
    if (resetToSections) {
      _returnToSectionScan();
    }
    await _startScanningOrArmWaitForSwitch();
  }

  Future<void> _startScanningOrArmWaitForSwitch() async {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final waitForSwitch =
        settingsProvider.settings?.waitForSwitchToScan ?? false;

    if (waitForSwitch) {
      if (mounted) {
        setState(() {
          _waitingForInitialSwitch = true;
          _switchStartRequested = false;
        });
      }
      await _playWaitForSwitchNotification();
      return;
    }

    await _startAuditoryScanning();
  }

  void _stopAuditoryScanning() {
    debugPrint(
      'FreestylePage stopAuditoryScanning: called, isScanning=$_isScanning',
    );
    setState(() {
      _isScanning = false;
      _scanningTimer?.cancel();
      _scanningIndex = null;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _isPausedFromScanLimit = false;
    });
    // Stop any ongoing TTS to prevent audio overlap
    _flutterTts.stop();
  }

  Future<void> _playWaitForSwitchNotification() async {
    final now = DateTime.now();
    if (_lastWaitForSwitchNotificationAt != null &&
        now.difference(_lastWaitForSwitchNotificationAt!).inMilliseconds <
            1200) {
      debugPrint(
        'FreestylePage waitForSwitchNotification: Skipping duplicate notification playback',
      );
      return;
    }
    _lastWaitForSwitchNotificationAt = now;

    final player = AudioPlayer();
    try {
      await player.setAsset('assets/notification_v2.mp3');
      await player.play();
      await player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
    } catch (e) {
      debugPrint(
        'FreestylePage waitForSwitchNotification: Playback failed: $e',
      );
    } finally {
      await player.dispose();
    }
  }

  void _performScanStep() async {
    debugPrint('FreestylePage performScanStep: called');

    if (_isAnnouncingScanningPrompt) {
      debugPrint(
        'FreestylePage performScanStep: Skipping tick while prompt announcement is starting',
      );
      return;
    }

    // Check if we're paused and waiting for user input
    if (_isScanningPaused && _waitingForUserInput) {
      debugPrint(
        'FreestylePage performScanStep: Scanning is paused, waiting for user input',
      );
      return;
    }

    List<Widget> scannableButtons = _getScannableButtons();
    if (scannableButtons.isEmpty && _currentScanLevel != 'sections') {
      _returnToSectionScan();
      scannableButtons = _getScannableButtons();
    }
    if (scannableButtons.isEmpty) {
      debugPrint('FreestylePage performScanStep: No scannable buttons');
      return;
    }

    final int buttonCount = scannableButtons.length;
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final scanLoopLimit = _getEffectiveScanLoopLimit();
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    final int baselineIndex = _scanningIndex ?? _lastScannedIndex;
    final nextIndex = baselineIndex + 1;
    if (nextIndex >= buttonCount) {
      final nextCycleCount = _currentScanCycle + 1;
      if (scanMode != 'step' &&
          scanLoopLimit > 0 &&
          nextCycleCount >= scanLoopLimit) {
        setState(() {
          _currentScanCycle = nextCycleCount;
          _scanningIndex = 0;
          _lastScannedIndex = 0;
        });
        debugPrint(
          'FreestylePage performScanStep: Reached scan loop limit ($scanLoopLimit), pausing',
        );
        await _pauseScanning(fromScanLoopLimit: true);
        return;
      }
      setState(() {
        _currentScanCycle = nextCycleCount;
      });
    }

    final int newIndex = nextIndex % buttonCount;
    String buttonText = _getButtonTextForIndex(newIndex);

    debugPrint(
      '🎯 FP performScanStep: OLD index=$_scanningIndex, NEW index=$newIndex (buttonCount=$buttonCount)',
    );
    debugPrint('🎯 FP performScanStep: Will announce: "$buttonText"');

    setState(() {
      _scanningIndex = newIndex;
      _lastScannedIndex = newIndex;
      _isAnnouncingScanningPrompt = true;
    });

    // Let the new highlight paint before the spoken prompt starts.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_isScanning || _scanningIndex != newIndex) {
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
      return;
    }

    await _speakSystemVoice(buttonText);
    if (mounted) {
      setState(() {
        _isAnnouncingScanningPrompt = false;
      });
    }
  }

  Future<void> _pauseScanning({bool fromScanLoopLimit = false}) async {
    debugPrint('FreestylePage pauseScanning: called');
    setState(() {
      _isScanningPaused = true;
      _waitingForUserInput = true;
      _isPausedFromScanLimit = fromScanLoopLimit;
      _scanningTimer?.cancel();
    });

    await _speakSystemVoice("Scanning paused. Use your switch to resume");
  }

  Future<void> _resumeAuditoryScanning() async {
    if (!_isPausedFromScanLimit) {
      if (mounted) {
        setState(() {
          _waitingForInitialSwitch = false;
          _switchStartRequested = true;
          _isScanning = false;
        });
      }
      await _startAuditoryScanning();
      return;
    }

    setState(() {
      _isPausedFromScanLimit = false;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _waitingForInitialSwitch = false;
      _switchStartRequested = true;
      _currentScanCycle = 0;
      _scanningIndex = -1;
      _isScanning = false;
    });

    await _speakSystemVoice("Scanning resumed");
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) {
      return;
    }
    await _startAuditoryScanning();
  }

  List<String> _getSectionIdsInOrder() {
    return <String>[
      'action',
      'choose-word',
      if (_isToolPanelVisible) 'tool-panel' else 'tool-toggle',
    ];
  }

  String _getSectionPromptText(String sectionId) {
    switch (sectionId) {
      case 'action':
        return 'Actions';
      case 'choose-word':
        return 'Choose word';
      case 'tool-toggle':
        return 'Tools';
      case 'tool-panel':
        if (_activeToolPanel == 'spelling') {
          return 'Spelling';
        }
        if (_activeToolPanel == 'numbers') {
          return 'Numbers';
        }
        return 'Word Categories';
      default:
        return 'Section';
    }
  }

  bool _isSectionHighlighted(String sectionId) {
    if (!_isScanning ||
        _currentScanLevel != 'sections' ||
        _scanningIndex == null) {
      return false;
    }
    final sections = _getSectionIdsInOrder();
    if (_scanningIndex! < 0 || _scanningIndex! >= sections.length) {
      return false;
    }
    return sections[_scanningIndex!] == sectionId;
  }

  Future<void> _enterSectionScan(String sectionId) async {
    setState(() {
      _activeScanSection = sectionId;
      _currentScanLevel = 'items';
      _scanningIndex = -1;
      _lastScannedIndex = -1;
      _currentScanCycle = 0;
      if (sectionId == 'tool-panel' && _activeToolPanel == 'spelling') {
        _lettersScanPhase = 'rows';
        _activeLetterRowIndex = null;
      }
    });
  }

  Future<void> _selectSectionAndContinueScanning(String sectionId) async {
    await _enterSectionScan(sectionId);

    if (!_isScanning) {
      return;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    if (scanMode != 'auto') {
      return;
    }

    final delay = settingsProvider.settings?.scanDelay ?? 3500;
    _scanningTimer?.cancel();
    _performScanStep();
    _scanningTimer = Timer.periodic(
      Duration(milliseconds: delay),
      (_) => _performScanStep(),
    );
  }

  void _returnToSectionScan() {
    setState(() {
      _activeScanSection = null;
      _currentScanLevel = 'sections';
      _lettersScanPhase = 'rows';
      _activeLetterRowIndex = null;
      _scanningIndex = -1;
      _lastScannedIndex = -1;
      _currentScanCycle = 0;
    });
  }

  int _getSuggestedWordLimit() {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final llmOptions = settingsProvider.settings?.llmOptions ?? 10;
    return llmOptions <= 0 ? 1 : llmOptions;
  }

  int _getSpellingSuggestedWordLimit() {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final llmOptions = settingsProvider.settings?.llmOptions ?? 10;
    return llmOptions <= 0 ? 1 : llmOptions;
  }

  List<String> _getVisibleSuggestedWords() {
    if (_currentSpellingWord.trim().isNotEmpty) {
      final limit = _getSpellingSuggestedWordLimit();
      final start = _spellingPredictionOffset.clamp(
        0,
        _currentPredictions.length,
      );
      final end = (start + limit).clamp(start, _currentPredictions.length);
      return _currentPredictions.sublist(start, end);
    }
    if (_currentNumberRange != null) {
      return _getCurrentNumberPageValues();
    }
    return _currentWordOptions.take(_getSuggestedWordLimit()).toList();
  }

  bool _hasMoreSpellingSuggestions() {
    if (_currentSpellingWord.trim().isEmpty) {
      return false;
    }

    return _spellingPredictionOffset + _getSpellingSuggestedWordLimit() <
        _currentPredictions.length;
  }

  String _formatNumberLabelValue(int value) {
    final raw = value.toString();
    return raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  List<_FreestyleNumberRange> _buildNumberRanges([int maxNumber = 1000]) {
    final ranges = <_FreestyleNumberRange>[];
    int start = _currentNumberBase;
    final int finalEnd = _currentNumberBase + maxNumber;

    while (start <= finalEnd) {
      final int end = start == _currentNumberBase
          ? (_currentNumberBase + _numberRangeSize).clamp(start, finalEnd)
          : (start + (_numberRangeSize - 1)).clamp(start, finalEnd);
      ranges.add(
        _FreestyleNumberRange(
          start: start,
          end: end,
          label:
              '${_formatNumberLabelValue(start)}-${_formatNumberLabelValue(end)}',
        ),
      );
      start = end + 1;
    }

    return ranges;
  }

  List<_FreestyleNumberRange> _buildNumberSubRanges(
    _FreestyleNumberRange parent,
  ) {
    final subRanges = <_FreestyleNumberRange>[];
    int start = parent.start;

    while (start <= parent.end) {
      final int end = (start + 9).clamp(start, parent.end);
      subRanges.add(
        _FreestyleNumberRange(
          start: start,
          end: end,
          label: start == end
              ? _formatNumberLabelValue(start)
              : '${_formatNumberLabelValue(start)}-${_formatNumberLabelValue(end)}',
        ),
      );
      start = end + 1;
    }

    return subRanges;
  }

  List<_FreestyleNumberRange> _getActiveNumberToolRanges() {
    if (_selectedTopNumberRange == null) {
      return _buildNumberRanges();
    }
    return _buildNumberSubRanges(_selectedTopNumberRange!);
  }

  List<Map<String, dynamic>> _buildNumberToolButtons() {
    final buttons = <Map<String, dynamic>>[
      {'text': 'Go Back', 'action': _resetActiveToolPanel},
      ..._getActiveNumberToolRanges().map(
        (range) => {
          'text': range.label,
          'action': () => _handleNumberToolRangeSelection(range),
        },
      ),
    ];

    if (_selectedTopNumberRange == null) {
      for (final increment in _numberToolExpansions) {
        buttons.add({
          'text': 'Add ${_formatNumberLabelValue(increment)}',
          'action': () => _incrementNumberBase(increment),
        });
      }
      buttons.add({'text': 'Reset to 0', 'action': _resetNumberBase});
    }

    return buttons;
  }

  List<String> _getCurrentNumberPageValues() {
    if (_currentNumberRange == null) {
      return const [];
    }

    final int start =
        _currentNumberRange!.start +
        (_currentNumberPageOffset * _numberPageSize);
    if (start > _currentNumberRange!.end) {
      return const [];
    }

    final int end = (start + _numberPageSize - 1).clamp(
      start,
      _currentNumberRange!.end,
    );

    return [for (int value = start; value <= end; value++) value.toString()];
  }

  bool _hasMoreNumberPageValues() {
    if (_currentNumberRange == null) {
      return false;
    }

    return _currentNumberRange!.start +
            ((_currentNumberPageOffset + 1) * _numberPageSize) <=
        _currentNumberRange!.end;
  }

  Future<void> _selectNumberRange(_FreestyleNumberRange range) async {
    setState(() {
      _currentNumberRange = range;
      _selectedTopNumberRange = null;
      _activeToolPanel = 'categories';
      _isToolPanelVisible = false;
      _currentNumberPageOffset = 0;
      _statusMessage = 'Numbers ${range.label} ready.';
    });

    if (_isScanning) {
      await _restartScanningInSection('choose-word');
    }
  }

  Future<void> _handleNumberToolRangeSelection(
    _FreestyleNumberRange range,
  ) async {
    if (_selectedTopNumberRange == null) {
      setState(() {
        _selectedTopNumberRange = range;
        _currentNumberRange = null;
        _currentNumberPageOffset = 0;
        _statusMessage =
            'Numbers ${range.label} selected. Choose a smaller range.';
      });

      if (_isScanning) {
        await _restartScanningInSection('tool-panel');
      }
      return;
    }

    await _selectNumberRange(range);
  }

  Future<void> _incrementNumberBase(int increment) async {
    setState(() {
      _currentNumberBase += increment;
      _selectedTopNumberRange = null;
      _currentNumberRange = null;
      _currentNumberPageOffset = 0;
      _statusMessage =
          'Numbers starting at ${_formatNumberLabelValue(_currentNumberBase)} ready.';
    });

    if (_isScanning) {
      await _restartScanningInSection('tool-panel');
    }
  }

  Future<void> _resetNumberBase() async {
    setState(() {
      _currentNumberBase = 0;
      _selectedTopNumberRange = null;
      _currentNumberRange = null;
      _currentNumberPageOffset = 0;
      _statusMessage = 'Numbers reset to 0.';
    });

    if (_isScanning) {
      await _restartScanningInSection('tool-panel');
    }
  }

  Future<void> _showMoreSuggestedOptions() async {
    if (_currentSpellingWord.trim().isNotEmpty) {
      if (_hasMoreSpellingSuggestions()) {
        setState(() {
          _spellingPredictionOffset += _getSpellingSuggestedWordLimit();
          _statusMessage = 'Loaded more spelling suggestions.';
        });
      } else {
        await _announceWithTimeout(
          'No more spelling suggestions.',
          routing: 'system',
        );
      }

      if (_isScanning) {
        await _restartScanningInSection('choose-word');
      }
      return;
    }

    if (_currentNumberRange != null) {
      if (_hasMoreNumberPageValues()) {
        setState(() {
          _currentNumberPageOffset += 1;
          _statusMessage = 'Loaded more numbers.';
        });
      } else {
        await _announceWithTimeout(
          'No more numbers in this range.',
          routing: 'system',
        );
      }

      if (_isScanning) {
        await _restartScanningInSection('choose-word');
      }
      return;
    }

    if (_selectedWordCategory != null) {
      await _loadCategoryWordOptions(
        _selectedWordCategory!,
        requestDifferent: true,
        excludeWords: List<String>.from(_currentWordOptions),
        fallbackOptions: List<String>.from(_currentWordOptions),
      );
      return;
    }

    await _loadMoreWordOptions();
  }

  void _scheduleStatusMessageAutoHide() {
    final message = _statusMessage?.trim() ?? '';
    if (message.isEmpty) {
      _statusMessageTimer?.cancel();
      _scheduledStatusMessageText = null;
      return;
    }
    if (_scheduledStatusMessageText == message) {
      return;
    }

    _statusMessageTimer?.cancel();
    _scheduledStatusMessageText = message;
    _statusMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      if ((_statusMessage?.trim() ?? '') == message) {
        setState(() {
          _statusMessage = '';
        });
      }
      _scheduledStatusMessageText = null;
    });
  }

  Future<void> _restartScanningInSection(String sectionId) async {
    _stopAuditoryScanning();
    if (!mounted) {
      return;
    }
    await _enterSectionScan(sectionId);
    await _startScanningOrArmWaitForSwitch();
  }

  int _getSpellingGridColumns() {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;
    final letterOrder = settings?.spellLetterOrder ?? 'alphabetical';
    return letterOrder == 'qwerty' ? 10 : 9;
  }

  List<_FreestyleSpellingGridButton> _getSpellingGridButtons() {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;
    final letterOrder = settings?.spellLetterOrder ?? 'alphabetical';
    final buttons = <_FreestyleSpellingGridButton>[];

    if (letterOrder == 'qwerty') {
      const rows = [
        ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
        ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
        ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
      ];
      for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        for (final letter in rows[rowIndex]) {
          buttons.add(
            _FreestyleSpellingGridButton(
              text: letter,
              rowIndex: rowIndex,
              letter: letter,
              isEnabled: _validLetters.contains(letter),
            ),
          );
        }
      }
    } else {
      final letters = _getAllLetters();
      final columns = _getSpellingGridColumns();
      for (int index = 0; index < letters.length; index++) {
        final letter = letters[index];
        buttons.add(
          _FreestyleSpellingGridButton(
            text: letter,
            rowIndex: index ~/ columns,
            letter: letter,
            isEnabled: _validLetters.contains(letter),
          ),
        );
      }
    }

    int maxRowIndex = -1;
    for (final button in buttons) {
      if (button.rowIndex > maxRowIndex) {
        maxRowIndex = button.rowIndex;
      }
    }
    final actionRowIndex = maxRowIndex;

    buttons.add(
      _FreestyleSpellingGridButton(
        text: 'Go Back',
        rowIndex: actionRowIndex,
        isEnabled: true,
        isStandardOption: true,
      ),
    );

    if (_availableCompletedSpellingWord.trim().isNotEmpty) {
      buttons.add(
        _FreestyleSpellingGridButton(
          text: 'Choose Word',
          rowIndex: actionRowIndex,
          isEnabled: true,
          isStandardOption: true,
          isChooseWordOption: true,
        ),
      );
    }

    return buttons;
  }

  List<_FreestyleSpellingGridButton> _getVisibleEnabledSpellingButtons() {
    return _getSpellingGridButtons()
        .where((button) => button.isEnabled)
        .toList(growable: false);
  }

  List<_FreestyleSpellingGridButton> _getSpellingButtonsForActiveRow() {
    if (_activeLetterRowIndex == null) {
      return const [];
    }
    return _getVisibleEnabledSpellingButtons()
        .where((button) => button.rowIndex == _activeLetterRowIndex)
        .toList(growable: false);
  }

  List<Widget> _getToolPanelScannableButtons() {
    if (_activeToolPanel == 'numbers') {
      return List<Widget>.filled(_buildNumberToolButtons().length, Container());
    }

    if (_activeToolPanel == 'spelling') {
      final List<Widget> buttons = [];

      if (_lettersScanPhase == 'rows') {
        final rowIndexesWithGoBack = _getVisibleLetterRowIndexesWithGoBack();
        for (int i = 0; i < rowIndexesWithGoBack.length; i++) {
          buttons.add(Container());
        }
      } else {
        for (final _ in _getSpellingButtonsForActiveRow()) {
          buttons.add(Container());
        }
      }

      return buttons;
    }

    if (_currentScanningContext == 'choose-word-options') {
      return List<Widget>.filled(_currentCategoryWords.length + 3, Container());
    }

    return List<Widget>.filled(_getCategoryPanelEntries().length, Container());
  }

  bool _canDrillIntoCategory(_FreestyleCategoryNode node) {
    if (node.label.toLowerCase() == 'greetings') {
      return false;
    }

    return node.children.isNotEmpty;
  }

  List<_FreestyleCategoryNode> _getCurrentCategoryNodes() {
    if (_categoryNavigationStack.isEmpty) {
      return _wordCategories;
    }

    return _categoryNavigationStack.last.children;
  }

  String _getCategoryPanelPathLabel() {
    if (_categoryNavigationStack.isEmpty) {
      return '';
    }

    return _categoryNavigationStack.map((node) => node.label).join(' / ');
  }

  List<_FreestyleCategoryPanelEntry> _getCategoryPanelEntries() {
    final parentNode = _categoryNavigationStack.isNotEmpty
        ? _categoryNavigationStack.last
        : null;
    final entries = <_FreestyleCategoryPanelEntry>[];

    // Add Go Back/Back button first
    entries.add(
      _FreestyleCategoryPanelEntry(
        text: parentNode != null ? 'Back' : 'Go Back',
        action: parentNode != null ? 'back' : 'close',
      ),
    );

    if (parentNode == null) {
      entries.add(
        const _FreestyleCategoryPanelEntry(text: 'General', action: 'general'),
      );
    } else {
      entries.add(
        _FreestyleCategoryPanelEntry(
          text: 'All ${parentNode.label}',
          action: 'select-parent',
          node: parentNode,
        ),
      );
    }

    for (final category in _getCurrentCategoryNodes()) {
      entries.add(
        _FreestyleCategoryPanelEntry(
          text: category.label,
          action: _canDrillIntoCategory(category) ? 'drill' : 'select',
          node: category,
        ),
      );
    }

    return entries;
  }

  Future<void> _handleCategoryPanelEntry(
    _FreestyleCategoryPanelEntry entry,
  ) async {
    switch (entry.action) {
      case 'general':
        await _selectSuggestedWordCategory(null);
        return;
      case 'select-parent':
      case 'select':
        await _selectSuggestedWordCategory(entry.node);
        return;
      case 'drill':
        if (entry.node == null) {
          return;
        }
        setState(() {
          _categoryNavigationStack.add(entry.node!);
          _currentScanningContext = 'choose-word-categories';
          _statusMessage = 'Showing ${entry.node!.label} categories.';
        });
        if (_isScanning) {
          await _restartScanningInSection('tool-panel');
        }
        return;
      case 'back':
        if (_categoryNavigationStack.isEmpty) {
          return;
        }
        setState(() {
          _categoryNavigationStack.removeLast();
          _currentScanningContext = 'choose-word-categories';
        });
        if (_isScanning) {
          await _restartScanningInSection('tool-panel');
        }
        return;
      case 'close':
        _closeChooseWordModal();
        return;
    }
  }

  Future<void> _selectSuggestedWordCategory(
    _FreestyleCategoryNode? category, {
    bool requestDifferent = false,
  }) async {
    setState(() {
      _selectedWordCategory = category;
      _currentChooseWordCategory = category?.label ?? '';
      _currentScanningContext = 'choose-word-categories';
      _currentNumberRange = null;
      _currentNumberPageOffset = 0;
      _statusMessage = category == null
          ? 'General word suggestions ready.'
          : '${category.label} suggestions ready.';
    });

    if (category == null) {
      await _loadWordOptions(
        requestDifferent: requestDifferent,
        excludeWords: requestDifferent
            ? List<String>.from(_currentWordOptions)
            : const <String>[],
      );
    } else {
      await _loadCategoryWordOptions(
        category,
        requestDifferent: requestDifferent,
        excludeWords: requestDifferent
            ? List<String>.from(_currentWordOptions)
            : const <String>[],
      );
    }

    if (_isScanning && mounted) {
      await _restartScanningInSection('choose-word');
    }
  }

  List<int> _getVisibleLetterRowIndexes() {
    final rows = _getVisibleEnabledSpellingButtons()
        .map((button) => button.rowIndex)
        .toSet();
    final sorted = rows.toList()..sort();
    return sorted;
  }

  /// Returns row indexes with a special -1 marker for "Go Back" at the beginning
  List<int> _getVisibleLetterRowIndexesWithGoBack() {
    return [-1, ..._getVisibleLetterRowIndexes()];
  }

  List<String> _getLettersForActiveRow() {
    return _getSpellingButtonsForActiveRow()
        .map((button) => button.text)
        .toList(growable: false);
  }

  Widget _buildSpellingHeaderCurrentWordField() {
    return SizedBox(
      width: 300,
      child: TextField(
        controller: _spellingWordController,
        readOnly: true,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF002244),
        ),
        decoration: InputDecoration(
          labelText: 'Current Word',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF002244), width: 2),
          ),
        ),
      ),
    );
  }

  /// Returns personalVolume honoring local SharedPreferences overrides,
  /// matching main.dart _getEffectivePersonalVolume exactly.
  Future<int> _getEffectivePersonalVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        '[FreestylePage] VOLUME: Using LOCAL personal volume override: $overrideValue/10',
      );
      return overrideValue;
    }
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final settingsValue =
        settingsProvider.settings?.personalVolume ??
        settingsProvider.settings?.applicationVolume ??
        10;
    debugPrint(
      '[FreestylePage] VOLUME: Using SETTINGS personal volume: $settingsValue/10',
    );
    return settingsValue;
  }

  Future<void> _speakSystemVoice(String text) async {
    try {
      // CRITICAL: Reset audio routing to personal/Bluetooth BEFORE speaking.
      // Mirrors main.dart _speakPersonalVoice which does this before every utterance.
      // On Android, resetToDefault → restoreAudio() sets STREAM_MUSIC to savedPersonalVolume.
      // On iOS, routeToPersonal removes the speaker override so audio goes to Bluetooth.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final platform = MethodChannel('audio_routing');
          if (Platform.isIOS) {
            await platform.invokeMethod('routeToPersonal');
          } else {
            await platform.invokeMethod('resetToDefault');
          }
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint(
            'FreestylePage: _speakSystemVoice routing reset failed: $e',
          );
        }
      }

      await _flutterTts.stop();
      // Use shared audio session, matching the grid page's _speakText behavior
      await _flutterTts.setSharedInstance(true);
      final userSettings = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      ).settings;
      final selectedVoiceName = userSettings?.selectedTtsVoiceName.trim() ?? '';
      final configuredSpeechRate = userSettings?.speechRate ?? 180;
      // Use _getEffectivePersonalVolume to honor local overrides (matches main.dart)
      final personalVolume = await _getEffectivePersonalVolume();
      final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
      debugPrint(
        '[FreestylePage] _speakSystemVoice: volume=$ttsVolume (personalVolume: $personalVolume/10)',
      );
      await _flutterTts.setVolume(ttsVolume);
      await _flutterTts.setSpeechRate(
        (configuredSpeechRate / 360.0).clamp(0.2, 1.0),
      );
      if (selectedVoiceName.isNotEmpty) {
        try {
          await _flutterTts.setVoice({'name': selectedVoiceName});
        } catch (e) {
          debugPrint('FreestylePage: _speakSystemVoice setVoice failed: $e');
        }
      }
      await _flutterTts.speak(text);
      debugPrint('FreestylePage: Scanning prompt spoken: $text');
    } catch (e) {
      debugPrint('FreestylePage: _speakSystemVoice failed: $e');
    }
  }

  List<Widget> _getScannableButtons() {
    if (_currentScanLevel == 'sections') {
      return List<Widget>.filled(_getSectionIdsInOrder().length, Container());
    }

    switch (_activeScanSection) {
      case 'action':
        return List<Widget>.filled(
          _buildLeadingMainButtons().length,
          Container(),
        );
      case 'choose-word':
        return List<Widget>.filled(
          _getVisibleSuggestedWords().length + 2,
          Container(),
        );
      case 'tool-toggle':
        return List<Widget>.filled(4, Container());
      case 'tool-panel':
        return _getToolPanelScannableButtons();
      default:
        return [];
    }
  }

  List<Widget> _getMainScannableButtons() {
    List<Widget> buttons = [];
    final leadingButtons = _buildLeadingMainButtons();

    for (int i = 0; i < leadingButtons.length; i++) {
      buttons.add(Container());
    }

    for (int i = 0; i < _currentWordOptions.length; i++) {
      buttons.add(Container());
    }

    buttons.add(Container());
    buttons.add(Container());
    buttons.add(Container());
    buttons.add(Container());

    return buttons;
  }

  int _getButtonIndexForWordOption(String word) {
    final currentIndex = _buildLeadingMainButtons().length;
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
    return List<Widget>.filled(_getCategoryPanelEntries().length, Container());
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
    if (_currentScanLevel == 'sections') {
      final sections = _getSectionIdsInOrder();
      if (index >= 0 && index < sections.length) {
        return _getSectionPromptText(sections[index]);
      }
      return 'Section';
    }

    if (_activeScanSection == 'action') {
      final buttons = _buildLeadingMainButtons();
      if (index >= 0 && index < buttons.length) {
        final text = (buttons[index]['text'] ?? 'Button').toString();
        if (index == 0 && _buildSpaceText.trim().isNotEmpty) {
          return _buildSpaceText;
        }
        return text;
      }
    } else if (_activeScanSection == 'choose-word') {
      final visibleWords = _getVisibleSuggestedWords();
      if (index == 0) {
        return 'Go Back';
      }

      if (index > 0 && index <= visibleWords.length) {
        return visibleWords[index - 1];
      }

      if (index == visibleWords.length + 1) {
        return 'Something Else';
      }
    } else if (_activeScanSection == 'tool-toggle') {
      const toolButtons = ['Go Back', 'Word Categories', 'Spell', 'Numbers'];
      if (index >= 0 && index < toolButtons.length) {
        return toolButtons[index];
      }
    } else if (_activeScanSection == 'tool-panel' &&
        _activeToolPanel == 'numbers') {
      final buttons = _buildNumberToolButtons();
      if (index >= 0 && index < buttons.length) {
        return (buttons[index]['text'] ?? 'Button').toString();
      }
    } else if (_currentScanningContext == "choose-word-categories") {
      final entries = _getCategoryPanelEntries();
      if (index >= 0 && index < entries.length) {
        return entries[index].text;
      }
    } else if (_currentScanningContext == "choose-word-options") {
      // Handle word options within a category
      if (index < _currentCategoryWords.length) {
        return _currentCategoryWords[index];
      } else {
        int controlIndex = index - _currentCategoryWords.length;
        const controlButtons = [
          "Back to Categories",
          "Something Else",
          "Go Back",
        ];
        if (controlIndex < controlButtons.length) {
          return controlButtons[controlIndex];
        }
      }
    } else if (_currentScanningContext == "spelling-letters") {
      if (_lettersScanPhase == 'rows') {
        final rowIndexesWithGoBack = _getVisibleLetterRowIndexesWithGoBack();
        if (index >= 0 && index < rowIndexesWithGoBack.length) {
          final rowIndex = rowIndexesWithGoBack[index];
          if (rowIndex == -1) {
            return 'Go Back';
          }
          return 'Row ${rowIndex + 1}';
        }
      } else {
        final rowButtons = _getSpellingButtonsForActiveRow();
        if (index >= 0 && index < rowButtons.length) {
          final button = rowButtons[index];
          return button.letter != null
              ? button.text.toLowerCase()
              : button.text;
        }
      }
    }
    return "Button";
  }

  // --- Build Space Management ---
  void _onBuildSpaceChange() {
    _buildSpaceText = _buildSpaceController.text;
    _currentContext = _buildSpaceText.trim().isNotEmpty
        ? _buildSpaceText
        : (widget.sourceContext ?? 'general communication');

    if (widget.composeMode) {
      unawaited(_persistComposeSession());
    }

    // Debounced reload of word options when build space changes
    _buildSpaceDebounceTimer?.cancel();
    _buildSpaceDebounceTimer = Timer(Duration(seconds: 1), () {
      _loadWordOptions();
    });
  }

  Future<void> _addWordToBuildSpace(
    String word, {
    String? restartSectionId,
  }) async {
    final wasScanning = _isScanning;
    final resolvedRestartSectionId =
        restartSectionId ??
        ((_activeScanSection == 'choose-word' ||
                _currentScanningContext == 'choose-word-options' ||
                _currentScanningContext == 'spelling-letters')
            ? 'choose-word'
            : null);

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
      debugPrint(
        '🎯 FreestylePage: First word selected - subsequent rounds can include phrases',
      );
    }

    // Reload word options with new context
    if (widget.composeMode) {
      await _persistComposeSession();
    }
    if (_currentNumberRange == null) {
      await _loadWordOptions();
    }

    // Use WidgetsBinding to ensure proper sequencing (matching main.dart pattern)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add delay to ensure audio system has settled after announcement
      Future.delayed(const Duration(milliseconds: 300), () async {
        debugPrint(
          'FreestylePage: Restarting wake word service and scanning after button announcement',
        );

        // Restart wake word service after announcement completes (like main page)
        _forceRestartWakeWordService();

        if (!wasScanning || !mounted) {
          return;
        }

        if (resolvedRestartSectionId != null) {
          await _restartScanningInSection(resolvedRestartSectionId);
          return;
        }

        await _restartScanning(resetToSections: true);
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
        debugPrint(
          '_speakDisplayText: "Nothing to speak" announced, restarting scanning',
        );

        // Add delay to allow audio routing to reset before starting scanning
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('_speakDisplayText: Audio routing reset delay completed');

        // Check if widget is still mounted before proceeding
        if (!mounted) {
          debugPrint(
            '_speakDisplayText: Widget not mounted, cannot restart scanning',
          );
          return;
        }

        // Use direct approach instead of addPostFrameCallback
        debugPrint(
          '_speakDisplayText: Directly resetting scanning state for "Nothing to speak"',
        );
        // Reset scanning state properly (same pattern as main page)
        setState(() {
          _isScanning = false; // Reset scanning state
          _scanningIndex = null; // Clear any existing highlighting
          _isScanningPaused = false; // Reset paused state
          _waitingForUserInput = false; // Reset waiting state
        });
        _returnToSectionScan();
        debugPrint(
          '_speakDisplayText: Calling _maybeStartScanning() to restart scanning after "Nothing to speak"',
        );
        _maybeStartScanning(); // Use the proper scanning restart method

        // Restart wake word service after announcement (like main page)
        _forceRestartWakeWordService();
      }
      return;
    }

    final String textToSpeak = _buildSpaceText;
    debugPrint(
      'FreestylePage: _speakDisplayText speaking exact Build Space text="$_buildSpaceText"',
    );

    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('forceSpeaker');

        if (Platform.isAndroid) {
          final settings = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          ).settings;
          final systemVolume =
              settings?.systemVolume ?? settings?.applicationVolume ?? 10;
          await platform.invokeMethod('setApplicationVolume', {
            'applicationVolume': systemVolume,
            'isPersonal': false,
          });
        }

        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint(
          'FreestylePage: _speakDisplayText forceSpeaker/system volume setup failed: $e',
        );
      }
    }

    // Use system routing for speech display (same as main page for consistency)
    await _announceWithTimeout(textToSpeak, routing: "system");

    if (widget.composeMode) {
      await _persistComposeSession();
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
        debugPrint(
          '_speakDisplayText: Widget not mounted, cannot restart scanning',
        );
        return;
      }

      // Use WidgetsBinding for proper sequencing (matching main.dart pattern)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Add delay to ensure audio system has settled
        Future.delayed(const Duration(milliseconds: 300), () {
          debugPrint(
            '_speakDisplayText: Resetting scanning state and restarting after delay',
          );

          // Reset scanning state properly (same pattern as main page)
          setState(() {
            _isScanning = false; // Reset scanning state
            _scanningIndex = null; // Clear any existing highlighting
            _isScanningPaused = false; // Reset paused state
            _waitingForUserInput = false; // Reset waiting state
          });

          _returnToSectionScan();

          debugPrint(
            '_speakDisplayText: Calling _maybeStartScanning() to restart scanning',
          );
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
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
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

      final body = json.encode({'text_to_cleanup': textToClean});

      debugPrint('FreestylePage: Cleanup body: $body');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      debugPrint(
        'FreestylePage: Cleanup response status: ${response.statusCode}',
      );
      debugPrint('FreestylePage: Cleanup response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final cleanedText = data['cleaned_text'] ?? textToClean;
        debugPrint('FreestylePage: Original text: "$textToClean"');
        debugPrint('FreestylePage: Cleaned text: "$cleanedText"');
        return cleanedText;
      } else {
        debugPrint(
          'FreestylePage: Cleanup failed with status ${response.statusCode}: ${response.body}',
        );
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
    debugPrint(
      '🎯 FreestylePage: Display cleared - reset to initial state (single words: $_isFirstRound)',
    );
    if (widget.composeMode) {
      unawaited(_persistComposeSession());
    }
    _loadWordOptions();
  }

  Future<void> _removeLastBuildSpaceUnit() async {
    if (_buildSpaceText.trim().isEmpty) {
      return;
    }

    final trimmedRight = _buildSpaceText.replaceFirst(RegExp(r'\s+$'), '');
    final updated = trimmedRight.replaceFirst(RegExp(r'(\n|\s*\S+)\s*$'), '');

    setState(() {
      _buildSpaceText = updated.trimRight();
      _buildSpaceController.text = _buildSpaceText;
      _currentContext = _buildSpaceText.trim().isNotEmpty
          ? _buildSpaceText
          : (_initialContext.isNotEmpty
                ? _initialContext
                : (widget.sourceContext ?? 'general communication'));
      _isFirstRound = _buildSpaceText.trim().isEmpty
          ? _initialIsFirstRound
          : false;
      _statusMessage = 'Removed the last entry.';
    });

    if (widget.composeMode) {
      await _persistComposeSession();
    }

    await _loadWordOptions();
    _returnToSectionScan();
  }

  Future<void> _insertBuildSpaceNewLine() async {
    final wasScanning = _isScanning;
    final text = _buildSpaceText.trimRight();
    if (text.isEmpty) {
      await _announceWithTimeout('Creation is empty.', routing: 'system');
      return;
    }

    await _flutterTts.stop();
    if (_isScanning) {
      _stopAuditoryScanning();
    }

    try {
      final lines = text.split('\n');
      final lastLine = lines.isNotEmpty ? lines.removeLast() : '';
      final finalizedLine = _ensureTerminalPunctuation(lastLine);
      final rebuiltText = lines.isNotEmpty
          ? '${lines.join('\n')}\n$finalizedLine\n'
          : '$finalizedLine\n';

      setState(() {
        _currentSpellingWord = '';
        _spellingWordController.text = '';
        _currentPredictions = [];
        _spellingPredictionOffset = 0;
        _availableCompletedSpellingWord = '';
        _lastAnnouncedSpellingWord = '';
        _isSpellingModalOpen = false;
        _isChooseWordModalOpen = false;
        _selectedWordCategory = null;
        _currentChooseWordCategory = '';
        _currentCategoryWords = [];
        _categoryNavigationStack.clear();
        _currentNumberRange = null;
        _currentNumberPageOffset = 0;
        _activeToolPanel = 'categories';
        _currentScanningContext = 'main';
        _buildSpaceText = rebuiltText;
        _buildSpaceController.text = rebuiltText;
        _currentContext = rebuiltText;
        _isFirstRound = false;
        _statusMessage = 'Started new row.';
      });

      if (widget.composeMode) {
        await _persistComposeSession();
      }

      await _loadWordOptions(
        requestDifferent: false,
        excludeWords: const <String>[],
      );
      await _announceWithTimeout('Started new row.', routing: 'system');
    } catch (e) {
      debugPrint('FreestylePage: New row failed: $e');
      await _announceWithTimeout(
        'Unable to start a new row right now.',
        routing: 'system',
      );
    }

    _returnToSectionScan();
    if (wasScanning && mounted) {
      await _restartScanning(delayMs: 250, resetToSections: true);
    }
  }

  Future<void> _cleanUpBuildSpace() async {
    if (_buildSpaceText.trim().isEmpty) {
      return;
    }

    final normalizedText = _buildSpaceText.replaceAll('\r\n', '\n');
    final lastLineBreakIndex = normalizedText.lastIndexOf('\n');
    final preservedPrefix = lastLineBreakIndex >= 0
        ? normalizedText.substring(0, lastLineBreakIndex + 1)
        : '';
    final currentRowText = lastLineBreakIndex >= 0
        ? normalizedText.substring(lastLineBreakIndex + 1)
        : normalizedText;

    if (currentRowText.trim().isEmpty) {
      await _announceWithTimeout('Current row is empty.', routing: 'system');
      return;
    }

    final wasScanning = _isScanning;

    await _flutterTts.stop();
    if (_isScanning) {
      _stopAuditoryScanning();
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Cleaning up text...';
    });

    try {
      final cleanedCurrentRow = await _cleanupText(currentRowText.trimRight());
      final rebuiltText = '$preservedPrefix$cleanedCurrentRow';
      if (!mounted) {
        return;
      }

      setState(() {
        _buildSpaceText = rebuiltText;
        _buildSpaceController.text = rebuiltText;
        _currentContext = rebuiltText.trim().isNotEmpty
            ? rebuiltText
            : _currentContext;
        _isFirstRound = rebuiltText.trim().isEmpty
            ? _initialIsFirstRound
            : false;
        _statusMessage = 'Current row cleaned up.';
      });

      if (widget.composeMode) {
        await _persistComposeSession();
      }

      if (cleanedCurrentRow.trim().isNotEmpty) {
        await _announceWithTimeout(cleanedCurrentRow, routing: 'system');
      }

      await _loadWordOptions();

      if (wasScanning && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 300), () async {
            _forceRestartWakeWordService();

            if (!mounted) {
              return;
            }

            await _restartScanning(resetToSections: true);
          });
        });
      } else {
        _returnToSectionScan();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetActiveToolPanel() async {
    setState(() {
      _isSpellingModalOpen = false;
      _isChooseWordModalOpen = false;
      _activeToolPanel = 'categories';
      _isToolPanelVisible = false;
      _currentNumberBase = 0;
      _currentNumberRange = null;
      _selectedTopNumberRange = null;
      _currentNumberPageOffset = 0;
      _selectedWordCategory = null;
      _categoryNavigationStack.clear();
      _currentChooseWordCategory = '';
      _currentCategoryWords = [];
      _currentScanningContext = 'main';
      _scanningIndex = _getFirstButtonIndex();
      _statusMessage = 'Returned to the main builder tools.';
    });

    _returnToSectionScan();
    _stopAuditoryScanning();
    _maybeStartScanning();
  }

  void _showNumbersToolPanel() {
    setState(() {
      _isSpellingModalOpen = false;
      _isChooseWordModalOpen = false;
      _activeToolPanel = 'numbers';
      _isToolPanelVisible = true;
      _currentNumberBase = 0;
      _currentNumberRange = null;
      _selectedTopNumberRange = null;
      _currentNumberPageOffset = 0;
      _currentScanningContext = 'main';
      _activeScanSection = 'tool-panel';
      _currentScanLevel = 'items';
      _scanningIndex = -1;
      _statusMessage = 'Numbers tool ready.';
    });
  }

  // --- Word Options Management ---
  Future<void> _loadWordOptions({
    bool? requestDifferent,
    List<String>? excludeWords,
    List<String>? fallbackOptions,
  }) async {
    if (_isLoadingWordOptions) return;

    if (_selectedWordCategory != null) {
      await _loadCategoryWordOptions(
        _selectedWordCategory!,
        requestDifferent: requestDifferent ?? false,
        excludeWords: excludeWords ?? const <String>[],
        fallbackOptions: fallbackOptions,
      );
      return;
    }

    final maxOptions = _getSuggestedWordLimit();

    setState(() {
      _isLoadingWordOptions = true;
      _statusMessage = 'Loading word options...';
    });

    final effectiveFallbackOptions =
        (fallbackOptions != null && fallbackOptions.isNotEmpty)
        ? fallbackOptions.take(maxOptions).toList()
        : _getGeneralFallbackWords(maxOptions);

    try {
      final exclusions =
          excludeWords ??
          (_currentWordOptions.isNotEmpty
              ? List<String>.from(_currentWordOptions)
              : <String>[]);
      final shouldRequestDifferent =
          requestDifferent ?? exclusions.isNotEmpty;

      debugPrint(
        '🎯 FreestylePage _loadWordOptions build space: "${_buildSpaceText.trim()}"',
      );
      debugPrint(
        '🎯 FreestylePage _loadWordOptions exclusions: ${exclusions.length}',
      );

      final response = widget.composeMode
          ? await AuthenticatedHttpClient.makeAuthenticatedRequest(
              'POST',
              '${EnvironmentConfig.apiBaseUrl}/api/freestyle/category-words',
              baseHeaders: {
                'Content-Type': 'application/json',
                'X-User-ID': widget.aacUserId,
              },
              body: json.encode({
                'category': 'general',
                'build_space_content': _buildSpaceText,
                'custom_prompt': _getContextFreeGeneralPrompt(),
                'exclude_words': exclusions,
              }),
            )
          : await AuthenticatedHttpClient.makeAuthenticatedRequest(
              'POST',
              '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options',
              baseHeaders: {
                'Content-Type': 'application/json',
                'X-User-ID': widget.aacUserId,
              },
              body: json.encode({
                ..._buildFreestyleRequestPayloadBase(),
                'build_space_text': _buildSpaceText.trim(),
                'single_words_only': true,
                'request_different_options': shouldRequestDifferent,
                'max_options': maxOptions,
              }),
            );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('FreestylePage: Raw API response: ${response.body}');
        setState(() {
          final rawOptions = widget.composeMode
              ? (data['words'] ?? [])
              : (data['word_options'] ?? []);
          debugPrint('FreestylePage: Parsed rawOptions: $rawOptions');
          _currentWordOptions = rawOptions
              .map<String>((option) {
                String raw;
                if (option is String) {
                  raw = option;
                } else if (option is Map<String, dynamic>) {
                  raw =
                      option['text']?.toString() ??
                      option['word']?.toString() ??
                      option.toString();
                } else {
                  raw = option.toString();
                }
                return _normalizeOptionText(raw);
              })
              .where((text) {
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
                    trimmedText.length == 1 &&
                        RegExp(r'[^\w]').hasMatch(trimmedText)) {
                  debugPrint(
                    'FreestylePage: Filtering out invalid option: "$trimmedText"',
                  );
                  return false;
                }

                return !(lowerText.contains('here are') ||
                    lowerText.contains('varied and diverse') ||
                    lowerText.contains('useful words') ||
                    lowerText.contains('communication for') ||
                    lowerText.contains('with related keywords') ||
                    lowerText.length > 50); // Skip very long descriptive text
              })
              .take(maxOptions)
              .toList();

          if (_currentWordOptions.isNotEmpty &&
              _currentWordOptions.length < maxOptions) {
            final usedLower = _currentWordOptions
                .map((word) => word.toLowerCase())
                .toSet();
            for (final fallback in effectiveFallbackOptions) {
              if (_currentWordOptions.length >= maxOptions) {
                break;
              }
              final normalized = _normalizeOptionText(fallback);
              if (normalized.isEmpty) {
                continue;
              }
              if (usedLower.add(normalized.toLowerCase())) {
                _currentWordOptions.add(normalized);
              }
            }
          }

          if (_currentWordOptions.isEmpty) {
            _currentWordOptions = effectiveFallbackOptions;
            _statusMessage = 'Using fallback word options.';
          } else {
            _statusMessage = 'Loaded ${_currentWordOptions.length} word options';
          }
          debugPrint(
            'FreestylePage: Final processed options: $_currentWordOptions',
          );
        });
      } else {
        // Fallback options
        debugPrint(
          'FreestylePage: API returned ${response.statusCode}: ${response.body}',
        );
        setState(() {
          _currentWordOptions = effectiveFallbackOptions;
          _statusMessage =
              'Using fallback word options (API ${response.statusCode})';
        });
      }
    } catch (e) {
      // Fallback options
      debugPrint('FreestylePage: Error loading word options: $e');
      setState(() {
        _currentWordOptions = effectiveFallbackOptions;
        _statusMessage = 'Error loading options, using fallback ($e)';
      });
    } finally {
      setState(() {
        _isLoadingWordOptions = false;
      });
    }
  }

  Future<void> _loadCategoryWordOptions(
    _FreestyleCategoryNode category, {
    bool requestDifferent = false,
    List<String> excludeWords = const <String>[],
    List<String>? fallbackOptions,
  }) async {
    if (_isLoadingWordOptions) {
      return;
    }

    setState(() {
      _isLoadingWordOptions = true;
      _isLoadingCategoryWords = true;
      _statusMessage = 'Loading ${category.label} word options...';
    });

    try {
      final response = await _getCategoryWords(
        category,
        excludeWords: requestDifferent ? excludeWords : const <String>[],
      );
      final effectiveFallbackOptions =
          (fallbackOptions != null && fallbackOptions.isNotEmpty)
          ? fallbackOptions.take(_getSuggestedWordLimit()).toList()
          : _getDefaultCategoryWords(
              category.promptCategory,
            ).take(_getSuggestedWordLimit()).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _currentWordOptions = response.take(_getSuggestedWordLimit()).toList();
        if (_currentWordOptions.isEmpty) {
          _currentWordOptions = effectiveFallbackOptions;
        }
        _currentCategoryWords = List<String>.from(_currentWordOptions);
        _statusMessage =
            'Loaded ${_currentWordOptions.length} ${category.label.toLowerCase()} options';
      });
    } catch (e) {
      debugPrint('Error loading category word options: $e');
      if (!mounted) {
        return;
      }

      setState(() {
        _currentWordOptions =
            (fallbackOptions != null && fallbackOptions.isNotEmpty)
            ? fallbackOptions.take(_getSuggestedWordLimit()).toList()
            : _getDefaultCategoryWords(
                category.promptCategory,
              ).take(_getSuggestedWordLimit()).toList();
        _currentCategoryWords = List<String>.from(_currentWordOptions);
        _statusMessage =
            'Using fallback ${category.label.toLowerCase()} options';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWordOptions = false;
          _isLoadingCategoryWords = false;
        });
      }
    }
  }

  Future<void> _loadMoreWordOptions() async {
    if (_currentNumberRange != null) {
      await _showMoreSuggestedOptions();
      return;
    }

    if (_isLoadingWordOptions) return;

    // Store previous options for comparison
    final List<String> previousOptions = List.from(_currentWordOptions);

    if (widget.composeMode) {
      await _loadWordOptions(
        requestDifferent: true,
        excludeWords: previousOptions,
        fallbackOptions: previousOptions,
      );
      return;
    }

    setState(() {
      _isLoadingWordOptions = true;
      _statusMessage = 'Loading more word options...';
    });

    try {
      final targetCount = _getSuggestedWordLimit();
      final effectiveContext = _buildSpaceText.trim().isNotEmpty
          ? _buildSpaceText
          : _currentContext;

      // AGGRESSIVE APPROACH: Try multiple API strategies to get truly different words
      List<String> finalNewOptions = [];
      int attemptCount = 0;
      const maxAttempts = 3;

      while (finalNewOptions.length < targetCount &&
          attemptCount < maxAttempts) {
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
            'alternative_word_types': [
              'descriptive',
              'action',
              'creative',
            ], // New parameter
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
            'force_category': [
              'objects',
              'places',
              'activities',
            ], // Force different categories
            'exclude_previous_options': [
              ...previousOptions,
              ...finalNewOptions,
            ],
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
            'exclude_previous_options': [
              ...previousOptions,
              ...finalNewOptions,
            ],
            'force_unique': true,
            'timestamp':
                DateTime.now().millisecondsSinceEpoch + attemptCount * 100,
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
          final attemptOptions = rawOptions
              .map<String>((option) {
                String raw;
                if (option is String) {
                  raw = option;
                } else if (option is Map<String, dynamic>) {
                  raw =
                      option['text']?.toString() ??
                      option['word']?.toString() ??
                      option.toString();
                } else {
                  raw = option.toString();
                }
                return _normalizeOptionText(raw);
              })
              .where((text) {
                final lowerText = text.toLowerCase();
                final trimmedText = text.trim();
                final previousLower = previousOptions
                    .map((e) => e.toLowerCase())
                    .toList();
                final finalLower = finalNewOptions
                    .map((e) => e.toLowerCase())
                    .toList();

                // STRICT filtering: exclude if it matches ANY previous word (case-insensitive)
                return trimmedText.isNotEmpty &&
                    !previousLower.contains(
                      lowerText,
                    ) && // Case-insensitive comparison
                    !finalLower.contains(lowerText) &&
                    !(lowerText.contains('here are') ||
                        lowerText.contains('varied and diverse') ||
                        lowerText.contains('useful words') ||
                        lowerText.contains('communication for') ||
                        lowerText.contains('with related keywords') ||
                        lowerText.length > 50);
              })
              .toList();

          // Add unique options to our collection
          for (String option in attemptOptions) {
            final optionLower = option.toLowerCase();
            final existingLower = finalNewOptions
                .map((e) => e.toLowerCase())
                .toList();
            if (!existingLower.contains(optionLower) &&
                finalNewOptions.length < targetCount) {
              finalNewOptions.add(option);
            }
          }

          debugPrint(
            '   Attempt $attemptCount added ${attemptOptions.length} options, total now: ${finalNewOptions.length}',
          );
        }

        // Small delay between attempts
        if (attemptCount < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }

      // If we still don't have enough unique options, add fallback creative words
      if (finalNewOptions.length < targetCount) {
        final fallbackWords = [
          'awesome',
          'amazing',
          'wonderful',
          'fantastic',
          'brilliant',
          'create',
          'build',
          'make',
          'fix',
          'solve',
          'adventure',
          'journey',
          'explore',
          'discover',
          'find',
          'music',
          'art',
          'color',
          'draw',
          'paint',
          'family',
          'friend',
          'together',
          'share',
          'care',
          'outside',
          'inside',
          'around',
          'between',
          'through',
          'morning',
          'afternoon',
          'evening',
          'night',
          'day',
          'cold',
          'warm',
          'hot',
          'cool',
          'fresh',
        ];

        for (String fallback in fallbackWords) {
          final fallbackLower = fallback.toLowerCase();
          final previousLower = previousOptions
              .map((e) => e.toLowerCase())
              .toList();
          final finalLower = finalNewOptions
              .map((e) => e.toLowerCase())
              .toList();

          if (!previousLower.contains(fallbackLower) &&
              !finalLower.contains(fallbackLower) &&
              finalNewOptions.length < targetCount) {
            finalNewOptions.add(fallback);
          }
        }
      }

      // Calculate overlap for debugging
      final previousLower = previousOptions
          .map((e) => e.toLowerCase())
          .toList();
      final overlap = finalNewOptions
          .where((option) => previousLower.contains(option.toLowerCase()))
          .toList();

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
        _currentWordOptions = finalNewOptions.take(targetCount).toList();
        _statusMessage =
            'Loaded ${_currentWordOptions.length} additional word options.';
      });

      setState(() {
        _scanningIndex = 0;
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
      _activeToolPanel = 'spelling';
      _isToolPanelVisible = true;
      _activeScanSection = 'tool-panel';
      _currentScanLevel = 'items';
      _lettersScanPhase = 'rows';
      _activeLetterRowIndex = null;
      _currentSpellingWord = "";
      _spellingWordController.text = "";
      _currentPredictions = [];
      _spellingPredictionOffset = 0;
      _lastAnnouncedSpellingWord = '';
      _availableCompletedSpellingWord = '';
      _currentScanningContext = "spelling-letters";
      _validLetters = _getAllLetters();
      // Reset scanning back to first button in spelling context
      _scanningIndex = _getFirstButtonIndex();
    });

    // Stop main scanning and start spelling scanning
    _stopAuditoryScanning();
    _maybeStartScanning();
    unawaited(_getSpellingFallbackWords());
    unawaited(_getCommonSpellingWords());

    // Get initial word predictions even with empty current word
    _getWordPredictions();

    // Small delay to ensure the audio prompt is heard for the reset position
    if (_isScanning) {
      Future.delayed(Duration(milliseconds: 300), () {
        _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
      });
    }
  }

  void _closeSpellingModal({bool restartScanning = true}) {
    setState(() {
      _isSpellingModalOpen = false;
      _activeToolPanel = 'categories';
      _currentScanningContext = "main";
      _activeScanSection = null;
      _currentScanLevel = 'sections';
      _lettersScanPhase = 'rows';
      _activeLetterRowIndex = null;
      // Reset scanning back to first button when returning to main context
      _scanningIndex = _getFirstButtonIndex();
    });

    if (!restartScanning) {
      return;
    }

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
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;
    final letterOrder = settings?.spellLetterOrder ?? 'alphabetical';

    if (letterOrder == 'qwerty') {
      // QWERTY keyboard layout - flatten the rows
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

    if (currentWord.length >= 2) {
      final matchingLetterOptions = _getNextLettersFromMatchingWords(
        currentWord,
      );
      if (matchingLetterOptions.isNotEmpty) {
        print(
          'DEBUG: Using matching-word next letters for "$currentWord": $matchingLetterOptions',
        );
        return matchingLetterOptions;
      }
    }

    final lastChar = currentWord.toUpperCase().substring(
      currentWord.length - 1,
    );
    final lastTwoChars = currentWord.length >= 2
        ? currentWord.toUpperCase().substring(currentWord.length - 2)
        : '';
    final wordSoFar = currentWord.toUpperCase();

    print(
      'DEBUG: Last char: "$lastChar", Last two chars: "$lastTwoChars", Word so far: "$wordSoFar"',
    );

    // Define likely letter combinations based on common English patterns
    const likelyAfter = {
      'A': [
        'B',
        'C',
        'D',
        'F',
        'G',
        'L',
        'M',
        'N',
        'P',
        'R',
        'S',
        'T',
        'V',
        'W',
        'Y',
      ],
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
      'O': [
        'B',
        'C',
        'D',
        'F',
        'G',
        'K',
        'L',
        'M',
        'N',
        'P',
        'R',
        'S',
        'T',
        'V',
        'W',
      ],
      'P': ['A', 'E', 'I', 'L', 'O', 'R', 'U'],
      'Q': ['U'],
      'R': ['A', 'E', 'I', 'O', 'U', 'Y'],
      'S': [
        'A',
        'C',
        'E',
        'H',
        'I',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'T',
        'U',
        'W',
      ],
      'T': ['A', 'E', 'H', 'I', 'O', 'R', 'U', 'W'],
      'U': ['B', 'C', 'G', 'L', 'M', 'N', 'P', 'R', 'S', 'T'],
      'V': ['A', 'E', 'I', 'O'],
      'W': ['A', 'E', 'H', 'I', 'O'],
      'X': ['A', 'E', 'I'],
      'Y': ['A', 'E', 'O', 'U'],
      'Z': ['A', 'E', 'I', 'O'],
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
    if (currentWord.length >= 2 &&
        likelyAfterTwoLetters[lastTwoChars] != null) {
      validLetters = likelyAfterTwoLetters[lastTwoChars]!;
      print(
        'DEBUG: Using two-letter pattern for "$lastTwoChars": $validLetters',
      );
    } else if (likelyAfter[lastChar] != null) {
      validLetters = likelyAfter[lastChar]!;
      print(
        'DEBUG: Using single-letter pattern for "$lastChar": $validLetters',
      );
    } else {
      validLetters = _getAllLetters();
      print('DEBUG: No pattern found, using all letters');
    }

    print('DEBUG: Final valid letters for "$currentWord": $validLetters');
    return validLetters;
  }

  List<String> _getNextLettersFromMatchingWords(String currentWord) {
    final normalizedWord = currentWord.trim().toLowerCase();
    if (normalizedWord.isEmpty) {
      return const [];
    }

    final nextLetters = <String>{};

    void addCandidate(String candidate) {
      final normalizedCandidate = candidate.trim().toLowerCase();
      if (!_isVocabularyCompatibleCandidate(normalizedCandidate) ||
          !normalizedCandidate.startsWith(normalizedWord) ||
          normalizedCandidate.length <= normalizedWord.length) {
        return;
      }

      nextLetters.add(normalizedCandidate[normalizedWord.length].toUpperCase());
    }

    for (final candidate in _currentPredictions) {
      addCandidate(candidate);
    }

    final fallbackWords = _spellingFallbackWordsCache;
    if (fallbackWords != null && nextLetters.length < 10) {
      final startIndex = _findWordPrefixStartIndex(
        fallbackWords,
        normalizedWord,
      );
      for (int index = startIndex; index < fallbackWords.length; index++) {
        final candidate = fallbackWords[index];
        if (!candidate.startsWith(normalizedWord)) {
          break;
        }

        addCandidate(candidate);
        if (nextLetters.length >= 12) {
          break;
        }
      }
    }

    final orderedLetters = _getAllLetters()
        .where((letter) => nextLetters.contains(letter))
        .toList(growable: false);
    return orderedLetters;
  }

  void _handleLetterClick(String letter) {
    Future<void>(() async {
      final wasScanning = _isScanning;
      if (wasScanning) {
        _stopAuditoryScanning();
      }

      setState(() {
        _currentSpellingWord += letter.toLowerCase();
        _spellingWordController.text = _currentSpellingWord;
        _spellingPredictionOffset = 0;
        _validLetters = _getValidLetters(_currentSpellingWord);
        _lettersScanPhase = 'rows';
        _activeLetterRowIndex = null;
        _scanningIndex = -1;
        _currentScanCycle = 0;
      });

      final completedWordFuture = _getWordPredictions();
      await _announceWithTimeout(letter, routing: 'system');
      final completedWord = await completedWordFuture;
      if (!mounted) {
        return;
      }

      if (completedWord != null && completedWord.trim().isNotEmpty) {
        final normalizedWord = completedWord.trim().toLowerCase();
        setState(() {
          _availableCompletedSpellingWord = completedWord.trim();
        });
        if (normalizedWord != _lastAnnouncedSpellingWord) {
          _lastAnnouncedSpellingWord = normalizedWord;
          await _announceWithTimeout(completedWord, routing: 'system');
        }
        if (wasScanning) {
          await _restartSpellingWithActionPriority();
          return;
        }
      } else {
        setState(() {
          _availableCompletedSpellingWord = '';
          _lastAnnouncedSpellingWord = '';
        });
      }

      if (wasScanning) {
        await _restartScanningInSection('tool-panel');
      }
    });
  }

  void _selectLetterRow(int rowIndex) {
    setState(() {
      _lettersScanPhase = 'items';
      _activeLetterRowIndex = rowIndex;
      _scanningIndex = -1;
      _currentScanCycle = 0;
    });
  }

  Future<bool> _isLocallyRecognizedSpellingWord(String word) async {
    final normalizedWord = word.trim().toLowerCase();
    if (normalizedWord.isEmpty) {
      return false;
    }

    final sightWordService = SightWordService();
    if (!sightWordService.isInitialized) {
      await sightWordService.initialize();
    }
    if (!sightWordService.isInitialized) {
      return false;
    }

    final previousGradeLevel = sightWordService.currentGradeLevel;
    try {
      await sightWordService.setGradeLevel('third_grade_with_nouns');
      if (sightWordService.isSightWordText(normalizedWord)) {
        return true;
      }

      return _spellingCommonWordBoosts.contains(normalizedWord);
    } finally {
      if (sightWordService.currentGradeLevel != previousGradeLevel) {
        await sightWordService.setGradeLevel(previousGradeLevel);
      }
    }
  }

  String _getVocabularyLevel() {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;
    return settings?.vocabularyLevel ?? 'functional';
  }

  bool _isPreferredFunctionalWord(String candidate) {
    if (_spellingCommonWordBoosts.contains(candidate)) {
      return true;
    }

    return const {
      'can',
      'cat',
      'dog',
      'car',
      'chat',
      'chair',
      'change',
      'champ',
      'champion',
      'day',
      'drink',
      'eat',
      'friend',
      'go',
      'good',
      'happy',
      'help',
      'home',
      'house',
      'like',
      'look',
      'need',
      'play',
      'school',
      'stop',
      'thank',
      'water',
      'want',
      'where',
      'yes',
      'you',
    }.contains(candidate);
  }

  bool _isCommonSpellingWord(String candidate) {
    return _spellingCommonWordBoosts.contains(candidate) ||
        (_commonSpellingWordsCache?.contains(candidate) ?? false);
  }

  bool _isVocabularyCompatibleCandidate(String candidate) {
    final vocabularyLevel = _getVocabularyLevel();

    if (candidate.length <= 2) {
      return false;
    }

    final hasRareSuffix =
        candidate.endsWith('less') ||
        candidate.endsWith('like') ||
        candidate.endsWith('ize') ||
        candidate.endsWith('ous') ||
        candidate.endsWith('acol') ||
        candidate.endsWith('aca');

    switch (vocabularyLevel) {
      case 'emergent':
        return _isPreferredFunctionalWord(candidate) &&
            !hasRareSuffix &&
            candidate.length <= 6;
      case 'functional':
        return (_isPreferredFunctionalWord(candidate) ||
                _isCommonSpellingWord(candidate)) &&
            !hasRareSuffix &&
            candidate.length <= 10;
      case 'developing':
        return !candidate.endsWith('acol') &&
            !candidate.endsWith('aca') &&
            candidate.length <= 14;
      case 'proficient':
      default:
        return true;
    }
  }

  Future<Set<String>> _getCommonSpellingWords() async {
    if (_commonSpellingWordsCache != null) {
      return _commonSpellingWordsCache!;
    }

    final sightWordService = SightWordService();
    if (!sightWordService.isInitialized) {
      await sightWordService.initialize();
    }
    if (!sightWordService.isInitialized) {
      _commonSpellingWordsCache = Set<String>.from(_spellingCommonWordBoosts);
      return _commonSpellingWordsCache!;
    }

    final previousGradeLevel = sightWordService.currentGradeLevel;
    try {
      await sightWordService.setGradeLevel('third_grade_with_nouns');
      _commonSpellingWordsCache = {
        ...sightWordService.getAllSightWords(),
        ..._spellingCommonWordBoosts,
      };
      return _commonSpellingWordsCache!;
    } finally {
      if (sightWordService.currentGradeLevel != previousGradeLevel) {
        await sightWordService.setGradeLevel(previousGradeLevel);
      }
    }
  }

  Future<List<String>> _getSpellingFallbackWords() async {
    if (_spellingFallbackWordsCache != null) {
      return _spellingFallbackWordsCache!;
    }

    final wordList = await rootBundle.loadString(
      'assets/spelling_fallback_words.txt',
    );
    final words = wordList
        .split('\n')
        .map((word) => word.trim().toLowerCase())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);

    _spellingFallbackWordsCache = words;
    _spellingFallbackWordSetCache = words.toSet();
    return words;
  }

  Future<Set<String>> _getSpellingFallbackWordSet() async {
    if (_spellingFallbackWordSetCache != null) {
      return _spellingFallbackWordSetCache!;
    }

    await _getSpellingFallbackWords();
    return _spellingFallbackWordSetCache ?? <String>{};
  }

  int _findWordPrefixStartIndex(List<String> words, String prefix) {
    int low = 0;
    int high = words.length;

    while (low < high) {
      final mid = (low + high) >> 1;
      if (words[mid].compareTo(prefix) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return low;
  }

  int _scoreLocalSpellingPrediction(String prefix, String candidate) {
    if (!_isVocabularyCompatibleCandidate(candidate)) {
      return -10000;
    }

    int score = 0;
    if (candidate == prefix) {
      score += 2000;
    }
    if (_spellingCommonWordBoosts.contains(candidate)) {
      score += 1000;
    }

    switch (_getVocabularyLevel()) {
      case 'emergent':
        if (_isPreferredFunctionalWord(candidate)) {
          score += 1200;
        }
        if (candidate.length <= 5) {
          score += 120;
        }
        break;
      case 'functional':
        if (_isPreferredFunctionalWord(candidate)) {
          score += 900;
        }
        if (candidate.length <= 8) {
          score += 80;
        }
        break;
      case 'developing':
        if (candidate.length >= 5 && candidate.length <= 10) {
          score += 40;
        }
        break;
      case 'proficient':
        if (candidate.length >= 7) {
          score += 20;
        }
        break;
    }

    final extraLength = candidate.length - prefix.length;
    if (extraLength >= 0) {
      score += (120 - (extraLength * 8)).clamp(0, 120);
    }

    if (candidate.endsWith('ion') ||
        candidate.endsWith('ing') ||
        candidate.endsWith('ed') ||
        candidate.endsWith('er')) {
      score += 20;
    }

    if (candidate.endsWith('less') ||
        candidate.endsWith('like') ||
        candidate.endsWith('ize') ||
        candidate.endsWith('ous') ||
        candidate.endsWith('acol') ||
        candidate.endsWith('aca')) {
      score -= 40;
    }

    return score;
  }

  Future<List<String>> _getLocalSpellingPredictions(
    String word, {
    int maxResults = 60,
  }) async {
    final normalizedWord = word.trim().toLowerCase();
    if (normalizedWord.isEmpty) {
      return const [];
    }

    final fallbackWords = await _getSpellingFallbackWords();
    final startIndex = _findWordPrefixStartIndex(fallbackWords, normalizedWord);
    final matchingWords = <String>[];

    for (int index = startIndex; index < fallbackWords.length; index++) {
      final candidate = fallbackWords[index];
      if (!candidate.startsWith(normalizedWord)) {
        break;
      }
      if (!_isVocabularyCompatibleCandidate(candidate)) {
        continue;
      }
      matchingWords.add(candidate);
      if (matchingWords.length >= maxResults * 4) {
        break;
      }
    }

    matchingWords.sort((left, right) {
      final scoreComparison = _scoreLocalSpellingPrediction(
        normalizedWord,
        right,
      ).compareTo(_scoreLocalSpellingPrediction(normalizedWord, left));
      if (scoreComparison != 0) {
        return scoreComparison;
      }

      final lengthComparison = left.length.compareTo(right.length);
      if (lengthComparison != 0) {
        return lengthComparison;
      }
      return left.compareTo(right);
    });

    return matchingWords.take(maxResults).toList();
  }

  Future<String?> _getWordPredictions() async {
    print(
      'DEBUG: _getWordPredictions called with current word: "$_currentSpellingWord"',
    ); // Debug output
    final requestedWord = _currentSpellingWord.trim();
    final normalizedRequestedWord = requestedWord.toLowerCase();
    final requestId = ++_spellingPredictionRequestId;
    List<String> predictions = [];
    String? completedWord;

    if (normalizedRequestedWord.isNotEmpty &&
        await _isLocallyRecognizedSpellingWord(requestedWord)) {
      completedWord = requestedWord;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Debug the authentication tokens
      print('DEBUG: idToken length: ${widget.idToken.length}');
      print('DEBUG: aacUserId: "${widget.aacUserId}"');
      print('DEBUG: Build space text: "${_buildSpaceText}"');
      print('DEBUG: Current spelling word: "${_currentSpellingWord}"');

      final url =
          '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-prediction';
      final body = json.encode({
        'text': _buildSpaceText.trim().isEmpty
            ? ""
            : _buildSpaceText, // Context from build space
        'spelling_word':
            _currentSpellingWord, // Current partial word being spelled
        'predict_full_words':
            true, // Flag to ensure complete words are returned
      });

      print('DEBUG: API URL: $url');
      print('DEBUG: API Body: $body');

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        url,
        baseHeaders: {'X-User-ID': widget.aacUserId},
        body: body,
      );

      print('DEBUG: Response status code: ${response.statusCode}');
      print('DEBUG: Response headers: ${response.headers}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('DEBUG: Full API response: $data'); // Debug output
        predictions = List<String>.from(data['predictions'] ?? [])
          ..retainWhere((prediction) => prediction.trim().isNotEmpty);
        print('DEBUG: Raw predictions from API: $predictions'); // Debug output

        // Convert completions to full words
        if (requestedWord.isNotEmpty) {
          predictions = predictions.map((prediction) {
            // If prediction doesn't start with our current word, it's likely a completion
            // so prepend the current word to make it a full word
            String currentWord = requestedWord.toLowerCase();
            String predictionLower = prediction.toLowerCase();

            if (predictionLower.startsWith(currentWord)) {
              // Already a full word
              return prediction;
            } else {
              // It's a completion, combine with current word
              return requestedWord + prediction;
            }
          }).toList();
        }

        if (normalizedRequestedWord.isNotEmpty) {
          final exactMatch = predictions.cast<String?>().firstWhere(
            (prediction) =>
                (prediction ?? '').trim().toLowerCase() ==
                normalizedRequestedWord,
            orElse: () => null,
          );

          if (exactMatch?.trim().isNotEmpty == true) {
            completedWord = exactMatch!.trim();
          }
        }
      } else {
        print(
          'DEBUG: Word prediction API failed with status: ${response.statusCode}',
        ); // Debug output
        print('DEBUG: Response body: ${response.body}'); // Debug output
      }
    } catch (e) {
      print('DEBUG: Word prediction error: $e'); // Debug output
      debugPrint('FreestylePage: Error getting word predictions: $e');
    } finally {
      if (normalizedRequestedWord.isNotEmpty) {
        final localPredictions = await _getLocalSpellingPredictions(
          requestedWord,
        );
        if (localPredictions.isNotEmpty) {
          predictions = [...predictions, ...localPredictions];
        }
      }

      final isLatestRequest =
          requestId == _spellingPredictionRequestId &&
          requestedWord == _currentSpellingWord.trim();

      if (completedWord != null && completedWord.isNotEmpty) {
        final alreadyPresent = predictions.any(
          (prediction) =>
              prediction.trim().toLowerCase() == completedWord!.toLowerCase(),
        );
        if (!alreadyPresent) {
          predictions = [completedWord, ...predictions];
        }
      }

      final uniquePredictions = <String>[];
      final seenPredictions = <String>{};
      for (final prediction in predictions) {
        final normalizedPrediction = prediction.trim().toLowerCase();
        if (normalizedPrediction.isEmpty ||
            !_isVocabularyCompatibleCandidate(normalizedPrediction) ||
            seenPredictions.contains(normalizedPrediction)) {
          continue;
        }
        seenPredictions.add(normalizedPrediction);
        uniquePredictions.add(prediction.trim());
      }

      if (mounted && isLatestRequest) {
        setState(() {
          _currentPredictions = uniquePredictions;
          _spellingPredictionOffset = 0;
          _validLetters = _getValidLetters(_currentSpellingWord);
          _isLoading = false;
        });
      } else if (mounted && requestId == _spellingPredictionRequestId) {
        setState(() {
          _isLoading = false;
        });
      }

      print(
        'DEBUG: Word predictions loaded: $_currentPredictions; completedWord=$completedWord',
      ); // Debug output

      if (!isLatestRequest) {
        return null;
      }
    }

    return completedWord;
  }

  void _handlePredictionClick(String word) async {
    await _addWordToBuildSpace(word, restartSectionId: 'choose-word');
    _clearCurrentWord();
  }

  Future<void> _chooseCurrentSpellingWord() async {
    final chosenWord =
        (_availableCompletedSpellingWord.trim().isNotEmpty
                ? _availableCompletedSpellingWord
                : _currentSpellingWord)
            .trim();
    if (chosenWord.isEmpty) {
      if (_isScanning) {
        await _restartScanningInSection('tool-panel');
      }
      return;
    }

    await _addWordToBuildSpace(chosenWord);
    _clearCurrentWord();
    if (_isScanning) {
      await _restartScanning(delayMs: 250, resetToSections: true);
    }
  }

  Future<void> _addCurrentWordToBuildSpace() async {
    await _chooseCurrentSpellingWord();
  }

  Future<void> _closeSpellingToolAndReturnToSections() async {
    await _resetActiveToolPanel();
    if (_isScanning) {
      await _restartScanning(resetToSections: true);
    }
  }

  Future<void> _restartSpellingWithActionPriority() async {
    int actionRowIndex = -1;
    for (final button in _getSpellingGridButtons()) {
      if (button.isChooseWordOption || button.isStandardOption) {
        actionRowIndex = button.rowIndex;
        break;
      }
    }

    if (actionRowIndex < 0) {
      await _restartScanningInSection('tool-panel');
      return;
    }

    _stopAuditoryScanning();
    if (!mounted) {
      return;
    }

    setState(() {
      _activeScanSection = 'tool-panel';
      _currentScanLevel = 'items';
      _lettersScanPhase = 'items';
      _activeLetterRowIndex = actionRowIndex;
      _scanningIndex = -1;
      _currentScanCycle = 0;
    });

    await _startAuditoryScanning();
  }

  void _clearCurrentWord() {
    setState(() {
      _currentSpellingWord = "";
      _spellingWordController.text = "";
      _currentPredictions = [];
      _spellingPredictionOffset = 0;
      _lastAnnouncedSpellingWord = '';
      _availableCompletedSpellingWord = '';
      _validLetters = _getAllLetters();
      _lettersScanPhase = 'rows';
      _activeLetterRowIndex = null;
      _scanningIndex = -1;
      _currentScanCycle = 0;
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
        _currentSpellingWord = _currentSpellingWord.substring(
          0,
          _currentSpellingWord.length - 1,
        );
        _spellingWordController.text = _currentSpellingWord;
        _spellingPredictionOffset = 0;
        _validLetters = _getValidLetters(_currentSpellingWord);
        _availableCompletedSpellingWord = '';
        _lettersScanPhase = 'rows';
        _activeLetterRowIndex = null;
        _scanningIndex = -1;
        _currentScanCycle = 0;
      });

      // Small delay to ensure the audio prompt is heard for the reset position
      if (_isScanning) {
        Future.delayed(Duration(milliseconds: 200), () {
          _speakSystemVoice(_getButtonTextForIndex(_scanningIndex!));
        });
      }

      unawaited(_getWordPredictions());
    }
  }

  // --- CHOOSE WORD MODAL METHODS ---
  void _openChooseWordModal() {
    setState(() {
      _isSpellingModalOpen = false;
      _isChooseWordModalOpen = true;
      _activeToolPanel = 'categories';
      _isToolPanelVisible = true;
      _currentNumberRange = null;
      _currentNumberPageOffset = 0;
      _activeScanSection = 'tool-panel';
      _currentScanLevel = 'items';
      _currentScanningContext = "choose-word-categories";
      _currentCategoryWords = [];
    });

    // Stop main scanning
    _stopAuditoryScanning();

    // Start category scanning after UI settles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartScanning();
    });
  }

  void _closeChooseWordModal({bool restartScanning = true}) {
    setState(() {
      _isChooseWordModalOpen = false;
      _activeToolPanel = 'categories';
      _isToolPanelVisible = false;
      _currentScanningContext = "main";
      _activeScanSection = null;
      _currentScanLevel = 'sections';
      _currentCategoryWords = [];
      // Reset scanning back to first button when returning to main context
      _scanningIndex = _getFirstButtonIndex();
    });

    if (!restartScanning) {
      return;
    }

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
    final normalizedCategory = category.trim().toLowerCase();
    final categoryNode = _wordCategories.firstWhere(
      (node) => node.label.toLowerCase() == normalizedCategory,
      orElse: () => _FreestyleCategoryNode(
        label: category,
        promptCategory: normalizedCategory,
      ),
    );

    await _selectSuggestedWordCategory(categoryNode);
  }

  Future<List<String>> _getCategoryWords(
    _FreestyleCategoryNode category, {
    List<String> excludeWords = const <String>[],
  }) async {
    try {
      final requestBody = {
        if (!widget.composeMode) ..._buildFreestyleRequestPayloadBase(),
        'category': category.promptCategory,
        'custom_prompt': _buildCategorySpecificPrompt(category),
        'build_space_content': _buildSpaceText,
        'exclude_words': excludeWords,
      };

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/freestyle/category-words',
        baseHeaders: {
          'Content-Type': 'application/json',
          'X-User-ID': widget.aacUserId,
        },
        body: json.encode(requestBody),
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
        }
        throw Exception('Invalid response format');
      }

      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('Error getting category words: $e');
      final fallbackByPrompt = _getDefaultCategoryWords(category.promptCategory);
      if (!_isGenericCategoryFallback(fallbackByPrompt)) {
        return fallbackByPrompt;
      }

      return _getDefaultCategoryWords(category.label);
    }
  }

  bool _isGenericCategoryFallback(List<String> words) {
    const genericFallback = ['help', 'yes', 'no', 'more', 'done', 'like', 'want', 'go'];
    if (words.length != genericFallback.length) {
      return false;
    }

    for (int index = 0; index < words.length; index++) {
      if (words[index] != genericFallback[index]) {
        return false;
      }
    }

    return true;
  }

  List<String> _getDefaultCategoryWords(String category) {
    switch (category.toLowerCase()) {
      case 'greetings':
        return [
          'hello',
          'hi',
          'good morning',
          'good afternoon',
          'goodbye',
          'see you later',
          'thank you',
          'nice to see you',
        ];
      case 'ask':
        return [
          'can',
          'could',
          'may',
          'will',
          'would',
          'please',
          'i need',
          'i want',
        ];
      case 'question':
      case 'questions':
        return [
          'what',
          'where',
          'why',
          'how',
          'when',
          'who',
          'is it',
          'do you',
        ];
      case 'request':
      case 'requests':
        return [
          'can',
          'could',
          'please',
          'i need',
          'i want',
          'help me',
          'get',
          'bring',
        ];
      case 'respond':
        return [
          'yes',
          'no',
          'okay',
          'sure',
          'maybe',
          'not right now',
          'thank you',
          'i can',
        ];
      case 'people':
        return [
          'mom',
          'dad',
          'teacher',
          'friend',
          'doctor',
          'nurse',
          'family',
          'classmate',
        ];
      case 'places':
        return [
          'home',
          'school',
          'park',
          'store',
          'hospital',
          'library',
          'restaurant',
          'playground',
        ];
      case 'things':
        return [
          'book',
          'toy',
          'phone',
          'computer',
          'car',
          'bike',
          'keys',
          'bag',
        ];
      case 'actions':
        return ['eat', 'drink', 'sleep', 'walk', 'run', 'sit', 'stand', 'play'];
      case 'describe':
        return ['happy', 'sad', 'big', 'small', 'fast', 'slow', 'hot', 'cold'];
      case 'animals':
        return ['dog', 'cat', 'bird', 'fish', 'horse', 'cow', 'pig', 'rabbit'];
      default:
        return ['help', 'yes', 'no', 'more', 'done', 'like', 'want', 'go'];
    }
  }

  // --- SPEECH BUBBLE OVERLAY METHODS ---

  void _showSpeechBubbleOverlay(String text) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );

    if (settingsProvider.settings?.displaySplash != true) {
      return;
    }

    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = true;
        _speechBubbleText = text;
      });
    }

    final duration = settingsProvider.settings?.displaySplashtime ?? 3000;
    _speechBubbleTimer = Timer(Duration(milliseconds: duration), () {
      _hideSpeechBubbleOverlay();
    });
  }

  void _hideSpeechBubbleOverlay() {
    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = false;
        _speechBubbleText = '';
      });
    }
  }

  Future<void> _waitForAudioPlayerCompletion(
    AudioPlayer player, {
    bool verifyPlaybackPosition = false,
    Duration timeout = const Duration(seconds: 120),
    String debugLabel = 'announcement',
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<PlayerState> sub;

    sub = player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) {
        return;
      }

      if (verifyPlaybackPosition) {
        final duration = await player.duration;
        final position = await player.position;
        final remainingMs =
            (duration?.inMilliseconds ?? 0) - position.inMilliseconds;
        if (duration != null && remainingMs > 200) {
          debugPrint(
            'FreestylePage: False completion detected for $debugLabel - ${remainingMs}ms remaining',
          );
          return;
        }
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint(
            'FreestylePage: Timed out waiting for $debugLabel playback completion',
          );
        },
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _speakLocalFallbackTts(
    String text, {
    required String selectedVoiceName,
    required double ttsVolume,
    required double fallbackSpeechRate,
    required String routing,
  }) async {
    if (routing == 'system' &&
        !kIsWeb &&
        (Platform.isIOS || Platform.isAndroid)) {
      try {
        final platform = MethodChannel('audio_routing');
        await platform.invokeMethod('forceSpeaker');
      } catch (e) {
        debugPrint('FreestylePage: forceSpeaker failed for fallback TTS: $e');
      }
    }

    await _flutterTts.stop();
    await Future.delayed(const Duration(milliseconds: 100));
    await _flutterTts.setVolume(ttsVolume);
    await _flutterTts.setSpeechRate(fallbackSpeechRate);
    if (selectedVoiceName.isNotEmpty) {
      try {
        await _flutterTts.setVoice({'name': selectedVoiceName});
      } catch (e) {
        debugPrint('FreestylePage: fallback setVoice failed: $e');
      }
    }

    final ttsCompleter = Completer<void>();
    _flutterTts.setCompletionHandler(() {
      if (!ttsCompleter.isCompleted) {
        ttsCompleter.complete();
      }
    });

    await _flutterTts.speak(text);

    final wordCount = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    final estimatedDurationMs = (wordCount * 700) + 3000;
    await ttsCompleter.future.timeout(
      Duration(milliseconds: estimatedDurationMs.clamp(5000, 120000)),
      onTimeout: () {
        debugPrint('FreestylePage: Local fallback TTS timed out for "$text"');
      },
    );

    _flutterTts.setCompletionHandler(() {});
  }

  Future<void> _resetAudioSystem({String reason = 'error'}) async {
    try {
      debugPrint(
        'FreestylePage AUDIO RESET: Starting comprehensive audio system reset (reason: $reason)...',
      );

      _isAnnouncementPlaying = false;
      _audioSessionInitialized = false;

      try {
        await _flutterTts.stop();
      } catch (e) {
        debugPrint('FreestylePage AUDIO RESET: Error stopping TTS: $e');
      }

      if (_activeAudioPlayers.isNotEmpty) {
        for (final player in List<AudioPlayer>.from(_activeAudioPlayers)) {
          try {
            await player.stop();
            await player.dispose();
          } catch (e) {
            debugPrint('FreestylePage AUDIO RESET: Error disposing player: $e');
          }
        }
        _activeAudioPlayers.clear();
      }

      try {
        if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        debugPrint(
          'FreestylePage AUDIO RESET: Error resetting audio routing: $e',
        );
      }

      if (!kIsWeb && Platform.isAndroid) {
        try {
          const platform = MethodChannel('audio_routing');
          platform.invokeMethod('restoreNotificationSounds');
        } catch (e) {
          debugPrint(
            'FreestylePage AUDIO RESET: Error restoring notifications: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('FreestylePage AUDIO RESET: Error during reset: $e');
    }
  }

  AudioPlayer _createTrackedAudioPlayer(String purpose) {
    final player = AudioPlayer();
    _activeAudioPlayers.add(player);
    debugPrint(
      'FreestylePage: Created AudioPlayer for $purpose (active: ${_activeAudioPlayers.length})',
    );
    return player;
  }

  Future<void> _disposeAudioPlayer(AudioPlayer player, String purpose) async {
    try {
      await player.stop();
      await player.dispose();
    } catch (e) {
      debugPrint('FreestylePage: Error disposing $purpose player: $e');
    } finally {
      _activeAudioPlayers.remove(player);
    }
  }

  Future<void> _performTimeoutRecovery() async {
    try {
      await _resetAudioSystem(reason: 'timeout');

      if (!mounted) {
        return;
      }

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final enableScanning =
          settingsProvider.settings?.enableAuditoryScanning ?? false;

      if (enableScanning && !_isScanning) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !_isScanning) {
          _startAuditoryScanning();
        }
      }
    } catch (e) {
      debugPrint('FreestylePage TIMEOUT RECOVERY: Error during recovery: $e');
    }
  }

  /// Timeout wrapper for _announceViaBackend to prevent app freezing
  Future<void> _announceWithTimeout(
    String text, {
    String routing = 'system',
    int? speechRate,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      debugPrint(
        'FreestylePage _announceWithTimeout: Starting announcement with ${timeout.inSeconds}s timeout: "$text"',
      );

      await _announceViaBackend(
        text,
        routing: routing,
        speechRate: speechRate,
      ).timeout(
        timeout,
        onTimeout: () {
          debugPrint(
            '🚨 FREESTYLE PAGE TIMEOUT: _announceViaBackend timed out after ${timeout.inSeconds} seconds for: "$text"',
          );
          debugPrint(
            '🚨 TIMEOUT RECOVERY: Starting comprehensive audio system reset...',
          );

          _audioSessionInitialized = false;
          _isAnnouncementPlaying = false;

          try {
            _flutterTts.stop();
          } catch (e) {
            debugPrint('🚨 TIMEOUT RECOVERY: Error stopping TTS: $e');
          }

          try {
            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              const platform = MethodChannel('audio_routing');
              platform.invokeMethod('resetToDefault');
            }
          } catch (e) {
            debugPrint(
              '🚨 TIMEOUT RECOVERY: Error resetting audio routing: $e',
            );
          }

          _gridFocusNode?.requestFocus();

          Future.delayed(const Duration(milliseconds: 100), () async {
            await _performTimeoutRecovery();
          });

          throw TimeoutException(
            'FreestylePage announcement timed out after ${timeout.inSeconds} seconds',
            timeout,
          );
        },
      );

      debugPrint(
        'FreestylePage _announceWithTimeout: Announcement completed successfully within timeout',
      );
    } catch (e) {
      if (e is TimeoutException) {
        debugPrint(
          '🚨 FreestylePage _announceWithTimeout: Announcement timed out - showing user notification',
        );

        // Show user-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Audio announcement timed out. The app is still working normally.',
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        debugPrint(
          '🚨 FreestylePage _announceWithTimeout: Error during announcement: $e',
        );
        rethrow; // Re-throw non-timeout exceptions
      }
    }
  }

  // --- Announcement method (identical to main page for consistency) ---
  Future<void> _announceViaBackend(
    String text, {
    String routing = 'system',
    int? speechRate,
    bool showSpeechBubble = true,
  }) async {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final userSettings = settingsProvider.settings;
    final aacUserId = widget.aacUserId;
    String idToken = widget.idToken;
    final systemVolume =
        userSettings?.systemVolume ?? userSettings?.applicationVolume ?? 10;
    final volumeLevel = systemVolume / 10.0;

    if (text.trim().isEmpty) {
      return;
    }

    final announceStart = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
      '[TIMER] ANNOUNCE START: Freestyle _announceViaBackend("$text") at $announceStart',
    );

    _gridFocusNode?.unfocus();

    try {
      if (text.contains('[PAUSE]')) {
        final parts = text
            .split('[PAUSE]')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
        for (int index = 0; index < parts.length; index++) {
          await _announceViaBackend(
            parts[index],
            routing: routing,
            speechRate: speechRate,
            showSpeechBubble: showSpeechBubble,
          );
          if (index < parts.length - 1) {
            await Future.delayed(const Duration(milliseconds: 800));
          }
        }
        return;
      }

      final jokePattern = RegExp(r'^(.+\?)\s*(.+[!.])$');
      final jokeMatch = jokePattern.firstMatch(text);
      if (jokeMatch != null) {
        final question = jokeMatch.group(1)?.trim() ?? '';
        final punchline = jokeMatch.group(2)?.trim() ?? '';
        await _announceViaBackend(
          question,
          routing: routing,
          speechRate: speechRate,
          showSpeechBubble: showSpeechBubble,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await _announceViaBackend(
          punchline,
          routing: routing,
          speechRate: speechRate,
          showSpeechBubble: showSpeechBubble,
        );
        return;
      }

      if (_isAnnouncementPlaying) {
        debugPrint(
          'FreestylePage: Clearing stuck announcement state before new playback',
        );
        _isAnnouncementPlaying = false;
        _audioSessionInitialized = false;
        try {
          await _flutterTts.stop();
        } catch (e) {
          debugPrint('FreestylePage: Failed to stop stuck TTS: $e');
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _isAnnouncementPlaying = true;

      if (!kIsWeb && Platform.isAndroid) {
        try {
          final platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint(
            'FreestylePage: Pre-announcement resetToDefault failed: $e',
          );
        }
      }

      if (!_audioSessionInitialized) {
        debugPrint(
          'announceViaBackend: First call, initializing audio session...',
        );
        await _initializeAudioSession();
        _audioSessionInitialized = true;
      }

      final startTotal = DateTime.now();

      debugPrint(
        '[TIMER] announceViaBackend: START for "$text" at ${startTotal.millisecondsSinceEpoch}',
      );

      bool backendAudioPlayed = false;
      final startRequest = DateTime.now();
      debugPrint(
        '[TIMER] announceViaBackend: Requesting backend audio for "$text" at ${startRequest.millisecondsSinceEpoch}',
      );
      try {
        final token = await AuthenticatedHttpClient.getRefreshedIdToken();
        if (token != null && token.isNotEmpty) {
          idToken = token;
        }
      } catch (e) {
        debugPrint(
          'FreestylePage: Could not get fresh token: $e, using original token',
        );
      }

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/play-audio'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': text,
          'routing_target': routing,
          if (speechRate != null) 'speech_rate': speechRate,
        }),
      );
      final endRequest = DateTime.now();
      debugPrint(
        '[TIMER] announceViaBackend: Backend response received at ${endRequest.millisecondsSinceEpoch} (delta: ${endRequest.difference(startRequest).inMilliseconds} ms)',
      );
      debugPrint('announceViaBackend: Response status: ${response.statusCode}');

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

        try {
          if (!kIsWeb && Platform.isIOS) {
            final platform = MethodChannel('audio_routing');
            final player = _createTrackedAudioPlayer('iOS announcement');
            await _flutterTts.stop();
            await player.stop();
            await platform.invokeMethod('forceSpeaker');
            await player.setVolume(volumeLevel);

            if (showSpeechBubble) {
              _showSpeechBubbleOverlay(text);
            }

            await Future.delayed(const Duration(milliseconds: 600));

            if (routing == 'system') {
              _stopAuditoryScanning();
            }

            if (base64Audio != null && base64Audio.isNotEmpty) {
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File(
                '${tempDir.path}/backend_tts.mp3',
              ).create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              await player.play();
              await _waitForAudioPlayerCompletion(
                player,
                debugLabel: 'iOS base64 announcement',
              );
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              await player.setUrl(audioUrl);
              await player.play();
              await _waitForAudioPlayerCompletion(
                player,
                debugLabel: 'iOS audioUrl announcement',
              );
              backendAudioPlayed = true;
            }

            await platform.invokeMethod('routeToPersonal');
            await _disposeAudioPlayer(player, 'iOS announcement');
          } else if (!kIsWeb && Platform.isWindows) {
            if (showSpeechBubble) {
              _showSpeechBubbleOverlay(text);
            }

            debugPrint('FreestylePage: Windows priming audio with silence.mp3');
            try {
              final primingPlayer = AudioPlayer();
              await primingPlayer.setAsset('assets/silence.mp3');
              await primingPlayer.play().timeout(
                const Duration(milliseconds: 2000),
                onTimeout: () {
                  debugPrint(
                    'FreestylePage: Windows silence priming timed out, continuing',
                  );
                },
              );
              final completer = Completer<void>();
              StreamSubscription? sub;
              sub = primingPlayer.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) {
                    completer.complete();
                    sub?.cancel();
                  }
                }
              });
              await completer.future.timeout(
                const Duration(milliseconds: 1000),
                onTimeout: () {
                  sub?.cancel();
                },
              );
              await primingPlayer.dispose();
            } catch (e) {
              debugPrint('FreestylePage: Windows silence priming failed: $e');
            }

            final audioDeviceService = AudioDeviceService();
            await audioDeviceService.initialize();
            debugPrint(
              'announceViaBackend: Using AudioDeviceService for TTS playback with system device routing',
            );
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              await audioDeviceService.playTTSAudio(
                base64Audio,
                isPersonal: false,
              );
              final base64End = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: Windows base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms',
              );
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              final player = _createTrackedAudioPlayer('Windows audioUrl');
              await player.setUrl(audioUrl);
              await player.play();
              await _waitForAudioPlayerCompletion(
                player,
                debugLabel: 'Windows audioUrl announcement',
              );
              backendAudioPlayed = true;
              await _disposeAudioPlayer(player, 'Windows audioUrl');
            }
          } else if (!kIsWeb && Platform.isAndroid) {
            final platform = MethodChannel('audio_routing');
            final player = _createTrackedAudioPlayer('Android announcement');
            try {
              await _flutterTts.stop();
              await player.stop();
              await platform.invokeMethod('forceSpeaker');

              if (showSpeechBubble) {
                _showSpeechBubbleOverlay(text);
              }

              await Future.delayed(const Duration(milliseconds: 1200));

              try {
                final quickPrimingPlayer = AudioPlayer();
                await quickPrimingPlayer.setAsset('assets/silence.mp3');
                await quickPrimingPlayer.play();
                await quickPrimingPlayer.dispose();

                final earlyPrimingPlayer = AudioPlayer();
                await earlyPrimingPlayer.setAsset('assets/silence_1000MS.mp3');
                await earlyPrimingPlayer.play().timeout(
                  const Duration(milliseconds: 3000),
                  onTimeout: () {
                    debugPrint(
                      'FreestylePage: Android 1-second priming timed out, continuing',
                    );
                  },
                );
                final completer = Completer<void>();
                StreamSubscription? sub;
                sub = earlyPrimingPlayer.playerStateStream.listen((state) {
                  if (state.processingState == ProcessingState.completed) {
                    if (!completer.isCompleted) {
                      completer.complete();
                      sub?.cancel();
                    }
                  }
                });
                await completer.future.timeout(
                  const Duration(milliseconds: 2000),
                  onTimeout: () {
                    sub?.cancel();
                  },
                );
                await earlyPrimingPlayer.dispose();

                final finalPrimingPlayer = AudioPlayer();
                await finalPrimingPlayer.setAsset('assets/silence.mp3');
                await finalPrimingPlayer.play();
                await finalPrimingPlayer.dispose();
              } catch (e) {
                debugPrint(
                  'FreestylePage: Android aggressive audio priming failed: $e',
                );
              }

              if (routing == 'system') {
                _stopAuditoryScanning();
              }

              if (base64Audio != null && base64Audio.isNotEmpty) {
                final bytes = base64Decode(base64Audio);
                final tempDir = Directory.systemTemp;
                final tempFile = await File(
                  '${tempDir.path}/backend_tts.mp3',
                ).create();
                await tempFile.writeAsBytes(bytes, flush: true);
                await player.setFilePath(tempFile.path);
                await player.setVolume(volumeLevel);
                await Future.delayed(const Duration(milliseconds: 200));
                await player.play();
                await _waitForAudioPlayerCompletion(
                  player,
                  verifyPlaybackPosition: true,
                  debugLabel: 'Android base64 announcement',
                );
                backendAudioPlayed = true;
              } else if (audioUrl != null && audioUrl.isNotEmpty) {
                await player.setUrl(audioUrl);
                await player.setVolume(volumeLevel);
                await Future.delayed(const Duration(milliseconds: 200));
                await player.play();
                await _waitForAudioPlayerCompletion(
                  player,
                  verifyPlaybackPosition: true,
                  debugLabel: 'Android audioUrl announcement',
                );
                backendAudioPlayed = true;
              }

              await platform.invokeMethod('resetToDefault');
            } catch (e) {
              debugPrint('Android announceViaBackend failed: $e');
              backendAudioPlayed = false;
              try {
                await platform.invokeMethod('resetToDefault');
              } catch (_) {}
            } finally {
              await _disposeAudioPlayer(player, 'Android announcement');
            }
          } else {
            if (showSpeechBubble) {
              _showSpeechBubbleOverlay(text);
            }

            try {
              final primingPlayer = AudioPlayer();
              await primingPlayer.setAsset('assets/silence.mp3');
              await primingPlayer.play().timeout(
                const Duration(milliseconds: 2000),
                onTimeout: () {
                  debugPrint(
                    'FreestylePage: fallback silence priming timed out, continuing',
                  );
                },
              );
              final completer = Completer<void>();
              StreamSubscription? sub;
              sub = primingPlayer.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) {
                    completer.complete();
                    sub?.cancel();
                  }
                }
              });
              await completer.future.timeout(
                const Duration(milliseconds: 1000),
                onTimeout: () {
                  sub?.cancel();
                },
              );
              await primingPlayer.dispose();
            } catch (e) {
              debugPrint('FreestylePage: fallback silence priming failed: $e');
            }

            final player = _createTrackedAudioPlayer('Fallback platform');
            await player.setVolume(volumeLevel);
            await Future.delayed(const Duration(milliseconds: 100));

            if (audioUrl != null && audioUrl.isNotEmpty) {
              await player.setUrl(audioUrl);
              await player.play();
              await _waitForAudioPlayerCompletion(
                player,
                debugLabel: 'fallback audioUrl announcement',
              );
              backendAudioPlayed = true;
            } else if (base64Audio != null && base64Audio.isNotEmpty) {
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File(
                '${tempDir.path}/backend_tts.mp3',
              ).create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              await player.play();
              await _waitForAudioPlayerCompletion(
                player,
                debugLabel: 'fallback base64 announcement',
              );
              backendAudioPlayed = true;
            }

            await _disposeAudioPlayer(player, 'Fallback platform');
          }
        } catch (e) {
          debugPrint('FreestylePage: Audio playback failed: $e');
          backendAudioPlayed = false;
          await _resetAudioSystem(reason: 'playback error');
        }
      } else {
        debugPrint(
          'announceViaBackend: Backend error ${response.statusCode}: ${response.body}',
        );
      }

      if (!backendAudioPlayed) {
        debugPrint('announceViaBackend: Fallback to local TTS for "$text"');

        try {
          if (routing == 'system' &&
              !kIsWeb &&
              (Platform.isIOS || Platform.isAndroid)) {
            try {
              const platform = MethodChannel('audio_routing');
              await platform.invokeMethod('forceSpeaker');
            } catch (e) {
              debugPrint(
                'FreestylePage: forceSpeaker failed for local TTS fallback: $e',
              );
            }
          }

          await _flutterTts.stop();
          await Future.delayed(const Duration(milliseconds: 100));

          final ttsCompleter = Completer<void>();
          _flutterTts.setCompletionHandler(() {
            if (!ttsCompleter.isCompleted) {
              ttsCompleter.complete();
            }
          });

          await _flutterTts.speak(text);

          final wordCount = text
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
          final estimatedDurationMs = (wordCount * 700) + 3000;
          final timeout = Duration(
            milliseconds: estimatedDurationMs.clamp(5000, 120000),
          );

          try {
            await ttsCompleter.future.timeout(timeout);
          } on TimeoutException {
            if (!ttsCompleter.isCompleted) {
              ttsCompleter.complete();
            }
          }

          _flutterTts.setCompletionHandler(() {});
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (ttsError) {
          debugPrint('FreestylePage: TTS fallback failed: $ttsError');
          await _resetAudioSystem(reason: 'TTS fallback error in try block');
        }
      }

      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        try {
          final platform = MethodChannel('audio_routing');
          if (Platform.isIOS) {
            await platform.invokeMethod('routeToPersonal');
            await Future.delayed(const Duration(milliseconds: 200));
          } else {
            await platform.invokeMethod('resetToDefault');
          }
        } catch (e) {
          debugPrint('resetToDefault not implemented or failed: $e');
        }
      }
      final endTotal = DateTime.now();
      debugPrint(
        '[TIMER] announceViaBackend: END at ${endTotal.millisecondsSinceEpoch} (total delta: ${endTotal.difference(startTotal).inMilliseconds} ms)',
      );
    } catch (e) {
      debugPrint('announceViaBackend: Exception: $e');

      await _resetAudioSystem(reason: 'exception');

      try {
        if (routing == 'system' &&
            !kIsWeb &&
            (Platform.isIOS || Platform.isAndroid)) {
          try {
            const platform = MethodChannel('audio_routing');
            await platform.invokeMethod('forceSpeaker');
          } catch (speakerError) {
            debugPrint(
              'FreestylePage: forceSpeaker failed for exception fallback: $speakerError',
            );
          }
        }

        await _flutterTts.stop();
        await Future.delayed(const Duration(milliseconds: 100));

        final ttsCompleter = Completer<void>();
        _flutterTts.setCompletionHandler(() {
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        });

        await _flutterTts.speak(text);

        final wordCount = text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        final estimatedDurationMs = (wordCount * 700) + 3000;
        final timeout = Duration(
          milliseconds: estimatedDurationMs.clamp(5000, 120000),
        );

        try {
          await ttsCompleter.future.timeout(timeout);
        } on TimeoutException {
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        }

        _flutterTts.setCompletionHandler(() {});
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (ttsError) {
        debugPrint('FreestylePage: Exception fallback TTS failed: $ttsError');
        await _resetAudioSystem(reason: 'TTS fallback error');
      }
    } finally {
      _isAnnouncementPlaying = false;

      if (!kIsWeb && Platform.isAndroid) {
        try {
          const platform = MethodChannel('audio_routing');
          platform.invokeMethod('restoreNotificationSounds');
        } catch (e) {
          debugPrint(
            'FreestylePage: Failed to restore notification sounds: $e',
          );
        }
      }

      _gridFocusNode?.requestFocus();

      final announceEnd = DateTime.now().millisecondsSinceEpoch;
      debugPrint(
        '[TIMER] ANNOUNCE END: Freestyle _announceViaBackend("$text") at $announceEnd (total delta: ${announceEnd - announceStart}ms)',
      );
    }
  }

  // --- Handle scanning key press ---
  void _handleScanKeyPress() async {
    if (_isPausedFromScanLimit) {
      await _resumeAuditoryScanning();
      return;
    }

    if (!_isScanning || _scanningIndex == null) return;

    if (_currentScanLevel == 'sections') {
      final sections = _getSectionIdsInOrder();
      if (_scanningIndex! >= 0 && _scanningIndex! < sections.length) {
        await _selectSectionAndContinueScanning(sections[_scanningIndex!]);
      }
      return;
    }

    if (_activeScanSection == 'action') {
      final leadingButtons = _buildLeadingMainButtons();
      if (_scanningIndex! >= 0 && _scanningIndex! < leadingButtons.length) {
        final selectedActionText =
            (leadingButtons[_scanningIndex!]['text'] ?? '').toString();
        final action =
            leadingButtons[_scanningIndex!]['action']
                as Future<void> Function();
        await action();

        if (selectedActionText == 'Backspace' ||
            selectedActionText == 'Clear') {
          await _restartScanning(resetToSections: true);
        }
      }
      return;
    }

    if (_activeScanSection == 'choose-word') {
      final visibleWords = _getVisibleSuggestedWords();
      if (_scanningIndex == 0) {
        await _restartScanning(resetToSections: true);
        return;
      }

      if (_scanningIndex! > 0 && _scanningIndex! <= visibleWords.length) {
        await _addWordToBuildSpace(
          visibleWords[_scanningIndex! - 1],
          restartSectionId: 'choose-word',
        );
        return;
      }

      final somethingElseIndex = visibleWords.length + 1;
      if (_scanningIndex == somethingElseIndex) {
        _stopAuditoryScanning();
        await _showMoreSuggestedOptions();
        await _restartScanningInSection('choose-word');
      }
      return;
    }

    if (_activeScanSection == 'tool-toggle') {
      switch (_scanningIndex!) {
        case 0:
          await _restartScanning(resetToSections: true);
          return;
        case 1:
          _openChooseWordModal();
          await _enterSectionScan('tool-panel');
          return;
        case 2:
          _openSpellingModal();
          await _enterSectionScan('tool-panel');
          return;
        case 3:
          _showNumbersToolPanel();
          await _enterSectionScan('tool-panel');
          return;
      }
    }

    if (_activeScanSection == 'tool-panel' && _activeToolPanel == 'numbers') {
      final buttons = _buildNumberToolButtons();
      if (_scanningIndex! >= 0 && _scanningIndex! < buttons.length) {
        await (buttons[_scanningIndex!]['action'] as Future<void> Function())();
        return;
      }
    }

    if (_currentScanningContext == "choose-word-categories") {
      // Handle category selection
      final entries = _getCategoryPanelEntries();
      if (_scanningIndex! >= 0 && _scanningIndex! < entries.length) {
        await _handleCategoryPanelEntry(entries[_scanningIndex!]);
      }
    } else if (_currentScanningContext == "choose-word-options") {
      // Handle word selection within a category
      if (_scanningIndex! < _currentCategoryWords.length) {
        String selectedWord = _currentCategoryWords[_scanningIndex!];
        await _addWordToBuildSpace(
          selectedWord,
          restartSectionId: 'choose-word',
        );
        _closeChooseWordModal(restartScanning: false);
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
      if (_lettersScanPhase == 'rows') {
        final rowIndexesWithGoBack = _getVisibleLetterRowIndexesWithGoBack();
        if (_scanningIndex! >= 0 && _scanningIndex! < rowIndexesWithGoBack.length) {
          final rowIndex = rowIndexesWithGoBack[_scanningIndex!];
          if (rowIndex == -1) {
            // Go Back selected
            await _closeSpellingToolAndReturnToSections();
          } else {
            _selectLetterRow(rowIndex);
          }
        }
      } else {
        final rowButtons = _getSpellingButtonsForActiveRow();
        if (_scanningIndex! >= 0 && _scanningIndex! < rowButtons.length) {
          final selectedButton = rowButtons[_scanningIndex!];
          if (selectedButton.isChooseWordOption) {
            await _chooseCurrentSpellingWord();
          } else if (selectedButton.isStandardOption) {
            await _closeSpellingToolAndReturnToSections();
          } else if (selectedButton.letter != null) {
            _handleLetterClick(selectedButton.letter!);
          }
        }
      }
    }
  }

  Widget _buildComposeCreateSection({
    required String title,
    String? subtitle,
    Widget? trailing,
    String? scanSectionId,
    double contentSpacing = 16,
    required Widget child,
  }) {
    final isSectionHighlighted =
        scanSectionId != null && _isSectionHighlighted(scanSectionId);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSectionHighlighted
              ? const Color(0xFFFB4F14)
              : const Color(0xFFD7E0EA),
          width: isSectionHighlighted ? 3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color:
                (isSectionHighlighted
                        ? const Color(0xFFFB4F14)
                        : const Color(0xFF002244))
                    .withOpacity(isSectionHighlighted ? 0.18 : 0.08),
            blurRadius: isSectionHighlighted ? 18 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF002244),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5B6B7F),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          SizedBox(height: contentSpacing),
          child,
        ],
      ),
    );
  }

  Widget _buildActionStripButton({
    required String text,
    required VoidCallback onPressed,
    required int buttonIndex,
  }) {
    final bool isHighlighted =
        _isScanning &&
        _scanningIndex != null &&
        _currentScanLevel == 'items' &&
        _activeScanSection == 'action' &&
        _scanningIndex == buttonIndex;

    return Material(
      color: isHighlighted ? const Color(0xFFFB4F14) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isHighlighted
                  ? const Color(0xFFFB4F14)
                  : const Color(0xFFD0D9E3),
              width: isHighlighted ? 3 : 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isHighlighted ? Colors.white : const Color(0xFF002244),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTextButton({
    required String text,
    required VoidCallback onPressed,
    required bool isHighlighted,
    Color borderColor = const Color(0xFFD0D9E3),
    Color textColor = const Color(0xFF002244),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 3,
    ),
    int maxLines = 2,
  }) {
    return Material(
      color: isHighlighted ? const Color(0xFFFB4F14) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () async {
          if (_isScanningPaused && _waitingForUserInput) {
            await _resumeAuditoryScanning();
            return;
          }
          onPressed();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted ? const Color(0xFFFB4F14) : borderColor,
              width: isHighlighted ? 3 : 1.25,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: padding,
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isHighlighted ? Colors.white : textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedActionButton({
    required String text,
    required VoidCallback onPressed,
    required bool isHighlighted,
  }) {
    return _buildCompactTextButton(
      text: text,
      onPressed: onPressed,
      isHighlighted: isHighlighted,
    );
  }

  Widget _buildInlinePanelButton({
    required String text,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return _buildCompactTextButton(
      text: text,
      onPressed: onPressed,
      isHighlighted: false,
      borderColor: color.withOpacity(0.45),
      textColor: const Color(0xFF002244),
    );
  }

  Widget _buildActionSection() {
    final leadingButtons = _buildLeadingMainButtons();
    return _buildComposeCreateSection(
      scanSectionId: 'action',
      title: 'Build Space',
      contentSpacing: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF002244), width: 2),
            ),
            child: TextField(
              controller: _buildSpaceController,
              onChanged: (_) => _onBuildSpaceChange(),
              readOnly: true,
              enableInteractiveSelection: false,
              canRequestFocus: false,
              showCursor: false,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Color(0xFF002244),
              ),
              decoration: const InputDecoration(
                hintText: 'Select words or tools to build your message here...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 3.9,
            ),
            itemCount: leadingButtons.length,
            itemBuilder: (context, index) {
              final button = leadingButtons[index];
              return _buildActionStripButton(
                text: button['text'] as String,
                onPressed: () async {
                  await (button['action'] as Future<void> Function())();
                },
                buttonIndex: index,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedWordsSection() {
    final String sectionTitle;
    final numberValues = _getCurrentNumberPageValues();
    if (_currentNumberRange != null && numberValues.isNotEmpty) {
      sectionTitle =
          'Suggested Words - ${numberValues.first}-${numberValues.last}';
    } else if (_currentNumberRange != null) {
      sectionTitle = 'Suggested Words - ${_currentNumberRange!.label}';
    } else if (_selectedWordCategory != null) {
      sectionTitle = 'Suggested Words - ${_selectedWordCategory!.label}';
    } else {
      sectionTitle = 'Suggested Words';
    }

    return _buildComposeCreateSection(
      scanSectionId: 'choose-word',
      title: sectionTitle,
      contentSpacing: 0,
      child: _isLoadingWordOptions
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final visibleWords = _getVisibleSuggestedWords();
                final width = constraints.maxWidth;
                final totalItems = visibleWords.length + 2;
                final crossAxisCount = width >= 1080
                    ? ((totalItems / 2).ceil()).clamp(6, 8)
                    : width >= 840
                    ? ((totalItems / 2).ceil()).clamp(5, 7)
                    : width >= 620
                    ? ((totalItems / 2).ceil()).clamp(4, 6)
                    : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 4.3,
                  ),
                  itemCount: totalItems,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildSuggestedActionButton(
                        text: 'Go Back',
                        onPressed: _returnToSectionScan,
                        isHighlighted:
                            _isScanning &&
                            _scanningIndex != null &&
                            _currentScanLevel == 'items' &&
                            _activeScanSection == 'choose-word' &&
                            _scanningIndex == 0,
                      );
                    }

                    if (index > 0 && index <= visibleWords.length) {
                      return _buildWordOptionButton(
                        visibleWords[index - 1],
                        buttonIndex: index,
                      );
                    }

                    final somethingElseIndex = visibleWords.length + 1;
                    return _buildSuggestedActionButton(
                      text: 'Something Else',
                      onPressed: _showMoreSuggestedOptions,
                      isHighlighted:
                          _isScanning &&
                          _scanningIndex != null &&
                          _currentScanLevel == 'items' &&
                          _activeScanSection == 'choose-word' &&
                          _scanningIndex == somethingElseIndex,
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildToolsSection() {
    return _buildComposeCreateSection(
      scanSectionId: 'tool-toggle',
      title: 'Tools',
      contentSpacing: 0,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 6,
        childAspectRatio: 7.0,
        children: [
          _buildSuggestedActionButton(
            text: 'Go Back',
            onPressed: () {
              unawaited(_restartScanning(resetToSections: true));
            },
            isHighlighted:
                _isScanning &&
                _scanningIndex != null &&
                _currentScanLevel == 'items' &&
                _activeScanSection == 'tool-toggle' &&
                _scanningIndex == 0,
          ),
          _buildSuggestedActionButton(
            text: 'Word Categories',
            onPressed: _openChooseWordModal,
            isHighlighted:
                _isScanning &&
                _scanningIndex != null &&
                _currentScanLevel == 'items' &&
                _activeScanSection == 'tool-toggle' &&
                _scanningIndex == 1,
          ),
          _buildSuggestedActionButton(
            text: 'Spell',
            onPressed: _openSpellingModal,
            isHighlighted:
                _isScanning &&
                _scanningIndex != null &&
                _currentScanLevel == 'items' &&
                _activeScanSection == 'tool-toggle' &&
                _scanningIndex == 2,
          ),
          _buildSuggestedActionButton(
            text: 'Numbers',
            onPressed: _showNumbersToolPanel,
            isHighlighted:
                _isScanning &&
                _scanningIndex != null &&
                _currentScanLevel == 'items' &&
                _activeScanSection == 'tool-toggle' &&
                _scanningIndex == 3,
          ),
        ],
      ),
    );
  }

  Widget _buildInlineChooseWordPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [SizedBox(height: 170, child: _buildCategoryGrid())],
    );
  }

  Widget _buildInlineAlphabetGrid() {
    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        final buttons = _getSpellingGridButtons();
        final rowIndexesWithGoBack = _getVisibleLetterRowIndexesWithGoBack();
        final rowIndexes =
            buttons.map((button) => button.rowIndex).toSet().toList()..sort();

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

        final double letterFontSize = (((buttonSizePx / 10) * 1.44) * 1.2)
            .clamp(16.0, 31.0);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final rowIndex in rowIndexes) ...[
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final button in buttons.where(
                      (candidate) => candidate.rowIndex == rowIndex,
                    ))
                      Builder(
                        builder: (context) {
                          bool isHighlighted = false;
                          if (_isScanning &&
                              _scanningIndex != null &&
                              _currentScanningContext == 'spelling-letters') {
                            if (_lettersScanPhase == 'rows') {
                              if (_scanningIndex! >= 0 &&
                                  _scanningIndex! <
                                      rowIndexesWithGoBack.length) {
                                final highlightedRowIndex =
                                    rowIndexesWithGoBack[_scanningIndex!];
                                if (highlightedRowIndex == -1) {
                                  isHighlighted =
                                      button.isStandardOption &&
                                      button.text == 'Go Back';
                                } else {
                                  isHighlighted =
                                      button.isEnabled &&
                                      highlightedRowIndex == button.rowIndex;
                                }
                              }
                            } else {
                              final activeRowButtons =
                                  _getSpellingButtonsForActiveRow();
                              if (_scanningIndex! >= 0 &&
                                  _scanningIndex! < activeRowButtons.length) {
                                final highlightedButton =
                                    activeRowButtons[_scanningIndex!];
                                isHighlighted =
                                    highlightedButton.rowIndex ==
                                        button.rowIndex &&
                                    highlightedButton.text == button.text &&
                                    highlightedButton.isChooseWordOption ==
                                        button.isChooseWordOption &&
                                    highlightedButton.isStandardOption ==
                                        button.isStandardOption;
                              }
                            }
                          }

                          final buttonWidth = button.isStandardOption
                              ? 132.0
                              : 44.0;

                          return SizedBox(
                            width: buttonWidth,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isHighlighted
                                    ? const Color(0xFFFB4F14)
                                    : (button.isEnabled
                                          ? Colors.white
                                          : Colors.grey[300]),
                                border: Border.all(
                                  color: isHighlighted
                                      ? const Color(0xFFFB4F14)
                                      : (button.isEnabled
                                            ? const Color(0xFF002244)
                                            : Colors.grey),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: !button.isEnabled
                                      ? null
                                      : () {
                                          if (button.isChooseWordOption) {
                                            unawaited(
                                              _chooseCurrentSpellingWord(),
                                            );
                                          } else if (button.isStandardOption) {
                                            unawaited(
                                              _closeSpellingToolAndReturnToSections(),
                                            );
                                          } else if (button.letter != null) {
                                            _handleLetterClick(button.letter!);
                                          }
                                        },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Center(
                                    child: Text(
                                      button.text,
                                      style: TextStyle(
                                        fontSize: button.isStandardOption
                                            ? 14
                                            : letterFontSize,
                                        fontWeight: FontWeight.w600,
                                        color: isHighlighted
                                            ? Colors.white
                                            : (button.isEnabled
                                                  ? const Color(0xFF002244)
                                                  : Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineSpellingPanel() {
    return SizedBox(height: 152, child: _buildInlineAlphabetGrid());
  }

  Widget _buildInlineNumbersPanel() {
    final buttons = _buildNumberToolButtons();
    final bool isTopLevelNumbersPanel = _selectedTopNumberRange == null;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTopLevelNumbersPanel ? 6 : 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: isTopLevelNumbersPanel ? 2.9 : 4.3,
      ),
      itemCount: buttons.length,
      itemBuilder: (context, index) {
        final button = buttons[index];
        final isHighlighted =
            _isScanning &&
            _scanningIndex != null &&
            _currentScanLevel == 'items' &&
            _activeScanSection == 'tool-panel' &&
            _activeToolPanel == 'numbers' &&
            _scanningIndex == index;

        return _buildSuggestedActionButton(
          text: button['text'] as String,
          onPressed: () async {
            await (button['action'] as Future<void> Function())();
          },
          isHighlighted: isHighlighted,
        );
      },
    );
  }

  Widget _buildActiveToolPanelSection() {
    final String panelTitle;
    if (_activeToolPanel == 'spelling' || _isSpellingModalOpen) {
      panelTitle = 'Active Tool Panel - Spelling';
    } else if (_activeToolPanel == 'numbers' && !_isChooseWordModalOpen) {
      panelTitle = 'Active Tool Panel - Numbers';
    } else if (_getCategoryPanelPathLabel().isNotEmpty) {
      panelTitle =
          'Active Tool Panel - Word Categories - ${_getCategoryPanelPathLabel()}';
    } else if (_selectedWordCategory != null) {
      panelTitle =
          'Active Tool Panel - Word Categories - ${_selectedWordCategory!.label}';
    } else {
      panelTitle = 'Active Tool Panel - Word Categories';
    }

    if (_activeToolPanel == 'spelling' || _isSpellingModalOpen) {
      return _buildComposeCreateSection(
        scanSectionId: 'tool-panel',
        title: panelTitle,
        trailing: _buildSpellingHeaderCurrentWordField(),
        contentSpacing: 0,
        child: _buildInlineSpellingPanel(),
      );
    }

    if (_activeToolPanel == 'numbers' && !_isChooseWordModalOpen) {
      return _buildComposeCreateSection(
        scanSectionId: 'tool-panel',
        title: panelTitle,
        contentSpacing: 0,
        child: _buildInlineNumbersPanel(),
      );
    }

    return _buildComposeCreateSection(
      scanSectionId: 'tool-panel',
      title: panelTitle,
      contentSpacing: 0,
      child: _buildInlineChooseWordPanel(),
    );
  }

  Widget _buildPageHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        decoration: const BoxDecoration(
          color: Color(0xFF002244),
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Freestyle',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              widget.displayName,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleStatusMessageAutoHide();

    return RawKeyboardListener(
      focusNode: _gridFocusNode!,
      autofocus: true,
      onKey: (event) {
        if (ModalRoute.of(context)?.isCurrent == false) return;

        if (event.logicalKey.keyLabel == ' ') {
          if (event is RawKeyDownEvent) {
            if (_isSpacebarDisabled) return;

            // Handle initial switch press to start scanning
            if (_waitingForInitialSwitch) {
              setState(() {
                _waitingForInitialSwitch = false;
                _switchStartRequested = true;
              });
              _startAuditoryScanning();
              return;
            }

            if (!_isScanning && !_waitingForUserInput && !_isPausedFromScanLimit) return;

            if (_isSpacebarDown) return; // repeat, ignore
            _isSpacebarDown = true;

            _spacebarHoldTimer?.cancel();
            _spacebarHoldTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted) {
                setState(() {
                  _isSpacebarDisabled = true;
                });
              }
            });

            _handleScanKeyPress();
          } else if (event is RawKeyUpEvent) {
            _isSpacebarDown = false;
            _spacebarHoldTimer?.cancel();
            if (_isSpacebarDisabled) {
              setState(() {
                _isSpacebarDisabled = false;
              });
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE8EDF2),
      body: Stack(
        children: [
          Column(
            children: [
              _buildPageHeader(),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7FA),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFD7E0EA)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildActionSection(),
                              const SizedBox(height: 12),
                              _buildSuggestedWordsSection(),
                              const SizedBox(height: 12),
                              if (_isToolPanelVisible)
                                _buildActiveToolPanelSection()
                              else
                                _buildToolsSection(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_statusMessage?.trim().isNotEmpty == true)
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: IgnorePointer(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF002244).withOpacity(0.94),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Loading Indicator
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),

          // Speech Bubble Overlay
          if (_showSpeechBubble)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(
                  0.3,
                ), // Semi-transparent background
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
  }  // end build()

  Widget _buildSpellingControlButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
    int buttonIndex,
  ) {
    bool isHighlighted = false;

    // Check if this button is currently being scanned
    if (_isScanning &&
        _scanningIndex != null &&
        _currentScanningContext == "spelling-letters") {
      isHighlighted = _scanningIndex == buttonIndex;
    }

    return _buildCompactTextButton(
      text: text,
      onPressed: onPressed,
      isHighlighted: isHighlighted,
      borderColor: color.withOpacity(0.45),
    );
  }

  Widget _buildWordOptionButton(String word, {int? buttonIndex}) {
    bool isHighlighted = false;
    final int resolvedButtonIndex =
        buttonIndex ?? _currentWordOptions.indexOf(word);
    if (_isScanning &&
        _scanningIndex != null &&
        _currentScanLevel == 'items' &&
        _activeScanSection == 'choose-word') {
      isHighlighted = _scanningIndex == resolvedButtonIndex;
      if (isHighlighted) {
        debugPrint(
          '🎯 FP _buildWordOptionButton: word="$word" highlighted at index=$resolvedButtonIndex (_scanningIndex=$_scanningIndex)',
        );
      }
    }

    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        return _buildSuggestedActionButton(
          text: word,
          onPressed: () async {
            await _addWordToBuildSpace(word, restartSectionId: 'choose-word');
          },
          isHighlighted: isHighlighted,
        );
      },
    );
  }

  // Build text-only content with sight word checking
  Widget _buildTextOnlyWithSightWordCheck(
    String word,
    double fontSize,
    String? sightWordGradeLevel,
  ) {
    return FutureBuilder<bool>(
      future: _checkIfSightWord(word, sightWordGradeLevel),
      builder: (context, snapshot) {
        final bool isSightWord = snapshot.data ?? false;
        return _buildTextOnlyButtonContent(
          word,
          fontSize,
          isSightWord: isSightWord,
        );
      },
    );
  }

  // Helper method to check if a word is a sight word
  Future<bool> _checkIfSightWord(
    String word,
    String? sightWordGradeLevel, {
    bool enableSightWords = true,
  }) async {
    if (!enableSightWords || sightWordGradeLevel == null) return false;

    final sightWordService = SightWordService();
    if (!sightWordService.isInitialized) return false;

    await sightWordService.setGradeLevel(sightWordGradeLevel);
    return sightWordService.isSightWordText(word);
  }

  // Build text-only button content (original layout) with optional sight word styling
  Widget _buildTextOnlyButtonContent(
    String word,
    double fontSize, {
    bool isSightWord = false,
  }) {
    // Apply special formatting for sight words
    final double adjustedFontSize = isSightWord
        ? fontSize * 1.3
        : fontSize; // 30% larger for sight words
    final FontWeight fontWeight = isSightWord
        ? FontWeight.w700
        : FontWeight.w500; // Bolder for sight words
    final Color textColor = isSightWord
        ? const Color(0xFF0066CC)
        : const Color(0xFF002244); // Blue for sight words

    return Container(
      decoration: isSightWord
          ? BoxDecoration(
              // Subtle background highlight for sight words
              color: const Color(0xFFF0F8FF), // Very light blue background
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF0066CC).withOpacity(0.3),
                width: 1,
              ),
            )
          : null,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(
            isSightWord ? 4.0 : 0.0,
          ), // Extra padding for sight words
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
                  shadows: isSightWord
                      ? [
                          const Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Color(0x30000000),
                          ),
                        ]
                      : null,
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
  Widget _buildPictogramButtonContent(
    String word,
    double fontSize, {
    String? sightWordGradeLevel,
    bool? enableSightWords,
  }) {
    // Create pictogram service instance with enablePictograms configuration
    final pictogramService = PictogramService();
    pictogramService.enablePictograms = true;

    return FutureBuilder<PictogramResult?>(
      future: pictogramService.getPictogramResult(
        word,
        sightWordGradeLevel: sightWordGradeLevel != null
            ? int.tryParse(sightWordGradeLevel)
            : null,
        enableSightWords: enableSightWords ?? true,
        shouldLogMissing:
            false, // Don't log missing images for dynamically generated freestyle words
      ),
      builder: (context, snapshot) {
        final PictogramResult? result = snapshot.data;
        final String? pictogramUrl = result?.imageUrl;
        final bool isSightWord = result?.isSightWord ?? false;

        if (pictogramUrl == null || pictogramUrl.isEmpty) {
          // No pictogram found - show text only with sight word styling
          return _buildTextOnlyButtonContent(
            word,
            fontSize,
            isSightWord: isSightWord,
          );
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
              padding: const EdgeInsets.symmetric(
                horizontal: 4.0,
                vertical: 2.0,
              ),
              decoration: BoxDecoration(
                color: const Color(
                  0xFF002244,
                ).withOpacity(0.1), // Subtle background
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10.0),
                  bottomRight: Radius.circular(10.0),
                ),
              ),
              child: Text(
                word,
                style: TextStyle(
                  color: const Color(0xFF002244),
                  fontSize: (fontSize * 0.65).clamp(
                    9.0,
                    14.0,
                  ), // Smaller footer text
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
    int currentIndex = 0;

    for (final button in _buildLeadingMainButtons()) {
      buttons.add(
        _buildMainControlButton(
          button['text'] as String,
          button['icon'] as IconData,
          button['color'] as Color,
          () async {
            await (button['action'] as Future<void> Function())();
          },
          currentIndex,
        ),
      );
      currentIndex++;
    }

    for (int i = 0; i < _currentWordOptions.length; i++) {
      buttons.add(_buildWordOptionButton(_currentWordOptions[i]));
      currentIndex++;
    }

    // Word Categories button
    buttons.add(
      _buildMainControlButton(
        'Word Categories',
        Icons.list,
        const Color(0xFF8B5CF6),
        _openChooseWordModal,
        currentIndex,
      ),
    );
    currentIndex++;

    // More Suggestions button
    buttons.add(_buildMoreOptionsButton(currentIndex));
    currentIndex++;

    // Spell button
    buttons.add(
      _buildMainControlButton(
        'Spell',
        Icons.keyboard,
        const Color(0xFF3B82F6),
        _openSpellingModal,
        currentIndex,
      ),
    );
    currentIndex++;

    // Numbers button
    buttons.add(
      _buildMainControlButton(
        'Numbers',
        Icons.pin,
        const Color(0xFFF59E0B),
        _showNumbersToolPanel,
        currentIndex,
      ),
    );

    return buttons;
  }

  // Calculate optimal font size to prevent word splitting
  double _calculateOptimalFontSize(
    String text,
    double baseFontSize,
    double maxWidth,
    FontWeight fontWeight,
  ) {
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

  Widget _buildMainControlButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
    int buttonIndex, {
    String scanSectionId = 'tool-toggle',
    bool compact = false,
  }) {
    bool isHighlighted = false;

    // Check if this button is currently being scanned
    if (_isScanning &&
        _scanningIndex != null &&
        _currentScanLevel == 'items' &&
        _activeScanSection == scanSectionId) {
      isHighlighted = _scanningIndex == buttonIndex;
      if (isHighlighted) {
        debugPrint(
          '🎯 FP _buildMainControlButton: text="$text" highlighted at index=$buttonIndex (_scanningIndex=$_scanningIndex)',
        );
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

        final compactFontSize = compact ? fontSize - 1 : fontSize;

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
                  onTap: () async {
                    if (_isScanningPaused && _waitingForUserInput) {
                      await _resumeAuditoryScanning();
                      return;
                    }
                    onPressed();
                  },
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    padding: EdgeInsets.all(compact ? 3 : 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        double optimalFontSize = _calculateOptimalFontSize(
                          text,
                          compactFontSize,
                          constraints.maxWidth,
                          FontWeight.w500,
                        );

                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                color: color,
                                size: compact
                                    ? optimalFontSize + 1
                                    : optimalFontSize + 4,
                              ),
                              SizedBox(height: compact ? 1 : 2),
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

  Widget _buildMoreOptionsButton(int buttonIndex, {bool compact = false}) {
    bool isHighlighted = false;

    // Check if this button is currently being scanned
    if (_isScanning &&
        _scanningIndex != null &&
        _currentScanLevel == 'items' &&
        _activeScanSection == 'tool-toggle') {
      isHighlighted = _scanningIndex == buttonIndex;
    }

    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
        final userSettings = settingsProvider.settings;
        final int gridCols = userSettings?.gridColumns ?? 10;
        final Color lightColor =
            userSettings?.lightColor ?? const Color(0xFFFB4F14);

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

        // Use larger font size for letter buttons (120% of main grid)
        final double letterFontSize = (((buttonSizePx / 10) * 1.44) * 1.2)
            .clamp(16.0, 31.0);

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
                    padding: EdgeInsets.all(compact ? 3 : 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        double optimalFontSize = _calculateOptimalFontSize(
                          'More Suggestions',
                          compact ? letterFontSize * 0.72 : letterFontSize,
                          constraints.maxWidth,
                          FontWeight.w500,
                        );

                        return Center(
                          child: Text(
                            'More Suggestions',
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
                  Text(
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
                    borderSide: const BorderSide(
                      color: Color(0xFF002244),
                      width: 2,
                    ),
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
                    _buildSpellingControlButton(
                      'Add Word',
                      Icons.add,
                      const Color(0xFF10B981),
                      _addCurrentWordToBuildSpace,
                      0,
                    ),
                    _buildSpellingControlButton(
                      'Clear',
                      Icons.backspace,
                      const Color(0xFFEF4444),
                      _clearCurrentWord,
                      1,
                    ),
                    _buildSpellingControlButton(
                      'Backspace',
                      Icons.arrow_back,
                      const Color(0xFFF59E0B),
                      _backspaceCurrentWord,
                      2,
                    ),
                  ],
                  // Always show Cancel button
                  _buildSpellingControlButton(
                    'Cancel',
                    Icons.close,
                    const Color(0xFF6B7280),
                    _closeSpellingModal,
                    _spellingWordController.text.trim().isEmpty
                        ? 0
                        : 3, // Dynamic index
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
                      if (_isScanning &&
                          _scanningIndex != null &&
                          _currentScanningContext == "spelling-letters") {
                        int controlButtonCount =
                            _spellingWordController.text.trim().isEmpty ? 1 : 4;
                        // Predictions come right after control buttons
                        int predictionIndex =
                            _scanningIndex! - controlButtonCount;
                        isHighlighted = predictionIndex == index;
                      }

                      return Container(
                        margin: const EdgeInsets.only(right: 10),
                        child: ElevatedButton(
                          onPressed: () => _handlePredictionClick(
                            _currentPredictions[index],
                          ),
                          child: Text(_currentPredictions[index]),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isHighlighted
                                ? const Color(0xFFFB4F14)
                                : const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shadowColor: isHighlighted
                                ? const Color(0xFFFB4F14).withOpacity(0.4)
                                : null,
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
                    final letterOrder =
                        userSettings?.spellLetterOrder ?? 'alphabetical';

                    // Get ordered letters
                    final allLetters = _getAllLetters();

                    // Calculate grid columns based on letter order
                    int letterGridCols =
                        10; // default for alphabetical and frequency
                    if (letterOrder == 'qwerty') {
                      letterGridCols =
                          10; // QWERTY layout uses 10 columns for top row
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
                    final double letterFontSize =
                        (((buttonSizePx / 10) * 1.44) * 1.2).clamp(16.0, 31.0);

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: letterGridCols,
                        crossAxisSpacing: 4, // Reduced spacing
                        mainAxisSpacing: 4, // Reduced spacing
                        childAspectRatio: 1.0,
                      ),
                      itemCount: allLetters.length,
                      itemBuilder: (context, index) {
                        final letter = allLetters[index];
                        final isEnabled = _validLetters.contains(letter);

                        bool isHighlighted = false;
                        if (_isScanning &&
                            _scanningIndex != null &&
                            _currentScanLevel == 'items' &&
                            _activeScanSection == 'tool-panel' &&
                            _currentScanningContext == "spelling-letters") {
                          // Calculate which valid letter is currently being scanned
                          int predictionCount = _currentPredictions.length;
                          int controlButtonCount =
                              _spellingWordController.text.trim().isEmpty
                              ? 1
                              : 4;

                          // Letters come after control buttons AND predictions
                          int letterStartIndex =
                              controlButtonCount + predictionCount;
                          if (_scanningIndex! >= letterStartIndex) {
                            final localIndex =
                                _scanningIndex! - letterStartIndex;
                            if (_lettersScanPhase == 'rows') {
                              final rowIndexes = _getVisibleLetterRowIndexes();
                              if (localIndex >= 0 &&
                                  localIndex < rowIndexes.length) {
                                isHighlighted =
                                    index ~/ 10 == rowIndexes[localIndex];
                              }
                            } else {
                              final rowLetters = _getLettersForActiveRow();
                              if (localIndex >= 0 &&
                                  localIndex < rowLetters.length) {
                                isHighlighted =
                                    letter == rowLetters[localIndex];
                              }
                            }
                          }
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? const Color(0xFFFB4F14)
                                : (isEnabled ? Colors.white : Colors.grey[300]),
                            border: Border.all(
                              color: isHighlighted
                                  ? const Color(0xFFFB4F14)
                                  : (isEnabled
                                        ? const Color(0xFF002244)
                                        : Colors.grey),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: isHighlighted
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFB4F14,
                                      ).withOpacity(0.4),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isEnabled
                                  ? () => _handleLetterClick(letter)
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Center(
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    fontSize: letterFontSize,
                                    fontWeight: FontWeight.w500,
                                    color: isHighlighted
                                        ? Colors.white
                                        : (isEnabled
                                              ? const Color(0xFF002244)
                                              : Colors.grey),
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
    final categoryPathLabel = _getCategoryPanelPathLabel();
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
                    categoryPathLabel.isEmpty
                        ? 'Choose Word Category'
                        : 'Choose Word Category - $categoryPathLabel',
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
              Expanded(child: _buildCategoryGrid()),
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
        final int gridCols = (userSettings?.gridColumns ?? 10).clamp(4, 7);
        final entries = _getCategoryPanelEntries();

        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 2.85,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final isHighlighted =
                _isScanning &&
                _scanningIndex != null &&
                _currentScanLevel == 'items' &&
                _activeScanSection == 'tool-panel' &&
                _currentScanningContext == "choose-word-categories" &&
                _scanningIndex == index;

            return _buildSuggestedActionButton(
              text: entry.text,
              onPressed: () async {
                await _handleCategoryPanelEntry(entry);
              },
              isHighlighted: isHighlighted,
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
        final int gridCols = (userSettings?.gridColumns ?? 10).clamp(4, 7);

        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 2.85,
          ),
          itemCount: _currentCategoryWords.length,
          itemBuilder: (context, index) {
            final word = _currentCategoryWords[index];
            final isHighlighted =
                _isScanning &&
                _scanningIndex != null &&
                _currentScanLevel == 'items' &&
                _activeScanSection == 'tool-panel' &&
                _currentScanningContext == "choose-word-options" &&
                _scanningIndex == index;

            return _buildSuggestedActionButton(
              text: word,
              onPressed: () async {
                await _addWordToBuildSpace(word);
                _closeChooseWordModal();
              },
              isHighlighted: isHighlighted,
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

  Widget _buildChooseWordControlButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
    int buttonIndex,
    String context,
  ) {
    bool isHighlighted = false;

    // Check if this button is currently being scanned
    if (_isScanning &&
        _scanningIndex != null &&
        _currentScanningContext == context) {
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
    final RRect rrect = RRect.fromRectAndRadius(
      buttonRect,
      Radius.circular(radius),
    );

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
