import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'config/environment_config.dart';
import 'services/user_settings_provider.dart';

class SpellingScanPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final Future<void> Function(
    String text, {
    String routing,
    int? speechRate,
    bool showSpeechBubble,
  })
  announceFunction;
  final Future<void> Function(String text)? scanPromptFunction;
  final void Function(String text)? onComposeAppend;

  const SpellingScanPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.announceFunction,
    this.scanPromptFunction,
    this.onComposeAppend,
  });

  @override
  State<SpellingScanPage> createState() => _SpellingScanPageState();
}

class _SpellingScanPageState extends State<SpellingScanPage> {
  final FocusNode _focusNode = FocusNode();
  int _lastSwitchActivationMs = 0;

  int _scanDelayMs = 3500;
  String _scanMode = 'auto';
  bool _waitForSwitchToScan = false;
  bool _waitingForInitialSwitch = false;
  int _llmOptions = 10;
  String _spellLetterOrder = 'alphabetical';

  String _currentSpellingWord = '';
  String _currentBuildSpaceText = '';
  List<String> _currentPredictions = <String>[];
  bool _loadingPredictions = false;

  Timer? _scanTimer;
  Timer? _pendingPromptTimer;
  Timer? _speechBubbleTimer;
  bool _isAutoTickRunning = false;
  int _promptToken = 0;
  String _lastPromptText = '';
  DateTime _lastPromptAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isAnnouncingPrompt = false;
  String? _queuedPromptText;
  bool _showSpeechBubble = false;
  String _speechBubbleText = '';

  String _scanPhase = 'sections'; // sections | items
  int _sectionIndex = -1;
  int _itemIndex = -1;
  String _lettersScanPhase = 'rows'; // rows | items
  int? _activeLetterRowIndex;

  /// Returns letters split into 3 rows.
  /// QWERTY: real keyboard rows. Others: even 9/9/8 split.
  List<List<String>> _letterRows() {
    if (_spellLetterOrder == 'qwerty') {
      return [
        ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
        ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
        ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
      ];
    }
    final all = _allLettersByOrder();
    return [all.sublist(0, 9), all.sublist(9, 18), all.sublist(18)];
  }

  @override
  void initState() {
    super.initState();
    _loadSettingsAndInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _pendingPromptTimer?.cancel();
    _speechBubbleTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndInit() async {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;

    setState(() {
      _scanDelayMs = settings?.scanDelay ?? 3500;
      _scanMode = (settings?.scanMode == 'step') ? 'step' : 'auto';
      _waitForSwitchToScan = settings?.waitForSwitchToScan == true;
      _waitingForInitialSwitch = _waitForSwitchToScan;
      _llmOptions = settings?.llmOptions ?? 10;
      _spellLetterOrder = settings?.spellLetterOrder ?? 'alphabetical';
    });

    await _refreshSuggestedWords();

    if (!_waitingForInitialSwitch) {
      _resetToSectionsAndRestart(delayMs: 0);
    }
  }

  List<String> _allLettersByOrder() {
    if (_spellLetterOrder == 'qwerty') {
      return <String>[
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
    if (_spellLetterOrder == 'frequency') {
      return 'ETAOINSHRDLUCMFWGYPBVKXJZQ'.split('');
    }
    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
  }

  List<String> _getValidLetters(String currentWord) {
    if (currentWord.isEmpty) {
      return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }

    final upperWord = currentWord.toUpperCase();
    final lastChar = upperWord.substring(upperWord.length - 1);
    final lastTwoChars = upperWord.length >= 2
        ? upperWord.substring(upperWord.length - 2)
        : '';

    const likelyAfter = <String, List<String>>{
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
      'N': ['A', 'C', 'D', 'E', 'G', 'I', 'K', 'O', 'S', 'T', 'U', 'Y', 'Z'],
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

    const likelyAfterTwo = <String, List<String>>{
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
      'ON': ['A', 'C', 'D', 'E', 'G', 'K', 'S', 'T', 'Y', 'Z'],
      'RO': [
        'A',
        'B',
        'C',
        'D',
        'E',
        'G',
        'L',
        'M',
        'N',
        'O',
        'P',
        'S',
        'T',
        'U',
        'W',
      ],
      'RN': ['A', 'E', 'I', 'O'],
    };

    if (upperWord.length >= 4) {
      return 'ABCDEFGHIKLMNOPRSTUVWYZ'.split('');
    }
    if (upperWord.length >= 2 && likelyAfterTwo.containsKey(lastTwoChars)) {
      return likelyAfterTwo[lastTwoChars]!;
    }
    if (likelyAfter.containsKey(lastChar)) {
      return likelyAfter[lastChar]!;
    }
    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
  }

  String get _displayText {
    return [
      _currentBuildSpaceText,
      _currentSpellingWord,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
  }

  Future<void> _recordChatHistory(String responseText) async {
    try {
      await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/record_chat_history'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'question': '', 'response': responseText}),
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _getContextualSuggestedWords() async {
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-options'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'build_space_text': _currentBuildSpaceText,
          'max_options': _llmOptions < 1 ? 1 : _llmOptions,
        }),
      );

      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _currentPredictions = <String>[];
        });
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final rawOptions = (data['word_options'] as List<dynamic>? ?? <dynamic>[])
          .map((opt) {
            if (opt is Map<String, dynamic>) {
              return (opt['text'] ?? '').toString();
            }
            return opt.toString();
          })
          .where((opt) => opt.trim().isNotEmpty)
          .take(_llmOptions < 1 ? 1 : _llmOptions)
          .toList();

      setState(() {
        _currentPredictions = rawOptions;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentPredictions = <String>[];
      });
    }
  }

  Future<void> _getWordPredictionsForSpelling() async {
    try {
      final response = await http.post(
        Uri.parse(
          '${EnvironmentConfig.apiBaseUrl}/api/freestyle/word-prediction',
        ),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': _currentBuildSpaceText,
          'spelling_word': _currentSpellingWord,
          'predict_full_words': true,
        }),
      );

      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _currentPredictions = <String>[];
        });
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final predictions = (data['predictions'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .take(_llmOptions < 1 ? 1 : _llmOptions)
          .toList();

      setState(() {
        _currentPredictions = predictions;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentPredictions = <String>[];
      });
    }
  }

  Future<void> _refreshSuggestedWords() async {
    setState(() {
      _loadingPredictions = true;
    });

    if (_currentSpellingWord.isNotEmpty) {
      await _getWordPredictionsForSpelling();
    } else {
      await _getContextualSuggestedWords();
    }

    if (!mounted) return;
    setState(() {
      _loadingPredictions = false;
    });
  }

  void _appendWordToBuildSpace(String word) {
    final clean = word.trim();
    if (clean.isEmpty) return;
    final next = _currentBuildSpaceText.isEmpty
        ? clean
        : '$_currentBuildSpaceText $clean';
    setState(() {
      _currentBuildSpaceText = next;
    });
  }

  Future<void> _refreshSuggestedWordsInBackground() async {
    try {
      await _refreshSuggestedWords();
    } catch (_) {
      // Best-effort only.
    }
  }

  void _showSpeechBubbleOverlay(String text) {
    final settings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    ).settings;

    if (settings?.displaySplash != true) {
      return;
    }

    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = true;
        _speechBubbleText = text;
      });
    }

    final duration = settings?.displaySplashtime ?? 3000;
    _speechBubbleTimer = Timer(Duration(milliseconds: duration), () {
      _hideSpeechBubbleOverlay();
    });
  }

  void _hideSpeechBubbleOverlay() {
    _speechBubbleTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showSpeechBubble = false;
      _speechBubbleText = '';
    });
  }

  Future<void> _announceWithLocalSpeechBubble(
    String text, {
    String routing = 'system',
    int? speechRate,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    _showSpeechBubbleOverlay(cleaned);
    await widget.announceFunction(
      cleaned,
      routing: routing,
      speechRate: speechRate,
      showSpeechBubble: false,
    );
  }

  Future<void> _announceAndRecordWordInBackground(String word) async {
    try {
      await _announceWithLocalSpeechBubble(word, routing: 'system');
    } catch (_) {
      // Non-critical for selection responsiveness.
    }

    await _recordChatHistory(word);
  }

  Future<void> _handleLetterTap(String letter) async {
    setState(() {
      _currentSpellingWord += letter.toLowerCase();
    });
    _restartLettersRowsScan(delayMs: 120);
    unawaited(_refreshSuggestedWordsInBackground());
  }

  void _restartLettersRowsScan({int delayMs = 120}) {
    _stopScanning();

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_waitForSwitchToScan && _waitingForInitialSwitch) return;

      final sections = _sectionTargets();
      final lettersSectionIndex = sections.indexWhere((s) => s.id == 'letters');
      if (lettersSectionIndex < 0) {
        _resetToSectionsAndRestart(delayMs: 0);
        return;
      }

      setState(() {
        _scanPhase = 'items';
        _sectionIndex = lettersSectionIndex;
        _itemIndex = -1;
        _lettersScanPhase = 'rows';
        _activeLetterRowIndex = null;
      });

      _startScanning();
    });
  }

  Future<void> _handlePredictionTap(String word) async {
    _stopScanning();
    widget.onComposeAppend?.call(word);
    _appendWordToBuildSpace(word);
    setState(() {
      _currentSpellingWord = '';
    });
    _resetToSectionsAndRestart(delayMs: 120);
    unawaited(_announceAndRecordWordInBackground(word));
    unawaited(_refreshSuggestedWordsInBackground());
  }

  Future<void> _speakDisplay() async {
    final text = _displayText;
    if (text.isEmpty) return;
    _stopScanning();
    await _announceWithLocalSpeechBubble(text, routing: 'system');
    await _recordChatHistory(text);
    if (_currentSpellingWord.isNotEmpty) {
      _appendWordToBuildSpace(_currentSpellingWord);
      setState(() {
        _currentSpellingWord = '';
      });
      await _refreshSuggestedWords();
    }
    _resetToSectionsAndRestart(delayMs: 300);
  }

  Future<void> _backspaceCurrentWord() async {
    if (_currentSpellingWord.isNotEmpty) {
      setState(() {
        _currentSpellingWord = _currentSpellingWord.substring(
          0,
          _currentSpellingWord.length - 1,
        );
      });
      _resetToSectionsAndRestart(delayMs: 120);
      unawaited(_refreshSuggestedWordsInBackground());
      return;
    }

    if (_currentBuildSpaceText.isEmpty) return;
    setState(() {
      _currentBuildSpaceText = _currentBuildSpaceText.substring(
        0,
        _currentBuildSpaceText.length - 1,
      );
      _currentBuildSpaceText = _currentBuildSpaceText.trimRight();
    });
    _resetToSectionsAndRestart(delayMs: 120);
    unawaited(_refreshSuggestedWordsInBackground());
  }

  Future<void> _clearBuildSpace() async {
    setState(() {
      _currentBuildSpaceText = '';
      _currentSpellingWord = '';
      _currentPredictions = <String>[];
    });
    _resetToSectionsAndRestart(delayMs: 100);
    unawaited(_refreshSuggestedWordsInBackground());
  }

  Future<String> _cleanupText(String textToClean) async {
    if (textToClean.trim().isEmpty) return textToClean;

    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final userLanguage = settingsProvider.settings?.userLanguage ?? 'en-US';
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/freestyle/cleanup-text'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text_to_cleanup': textToClean,
          'target_locale': userLanguage,
        }),
      );

      if (response.statusCode != 200) return textToClean;

      final data = json.decode(response.body);
      if (data is Map<String, dynamic>) {
        final cleaned = (data['cleaned_text'] ?? '').toString().trim();
        return cleaned.isEmpty ? textToClean : cleaned;
      }
      return textToClean;
    } catch (_) {
      return textToClean;
    }
  }

  Future<void> _cleanDisplayText() async {
    final textToClean = _displayText.trim();
    if (textToClean.isEmpty) return;

    _resetToSectionsAndRestart(delayMs: 100);

    final cleaned = await _cleanupText(textToClean);
    if (!mounted) return;

    final normalized = cleaned.trim();
    if (normalized.isEmpty) return;

    setState(() {
      _currentBuildSpaceText = normalized;
      _currentSpellingWord = '';
    });

    try {
      await _announceWithLocalSpeechBubble(normalized, routing: 'system');
    } catch (_) {
      // Non-critical if announcement fails.
    }

    unawaited(_refreshSuggestedWordsInBackground());
  }

  List<_SectionTarget> _sectionTargets() {
    return const <_SectionTarget>[
      _SectionTarget(id: 'action', label: 'Actions'),
      _SectionTarget(id: 'letters', label: 'Letters'),
      _SectionTarget(id: 'choose-word', label: 'Choose word'),
    ];
  }

  List<_ItemTarget> _itemsForSection(String sectionId) {
    if (sectionId == 'action') {
      return const <_ItemTarget>[
        _ItemTarget(id: 'speak_display', label: 'Speak Display'),
        _ItemTarget(id: 'clean_text', label: 'Clean Text'),
        _ItemTarget(id: 'backspace', label: 'Backspace'),
        _ItemTarget(id: 'clear_word', label: 'Clear Word'),
        _ItemTarget(id: 'home', label: 'Home'),
      ];
    }

    if (sectionId == 'choose-word') {
      final predictionItems = _currentPredictions
          .map((word) => _ItemTarget(id: 'pred_$word', label: word))
          .toList();
      predictionItems.insert(
        0,
        const _ItemTarget(id: 'pred_go_back', label: 'Go Back'),
      );
      return predictionItems;
    }

    if (_lettersScanPhase == 'rows') {
      final rowIndexes = _letterRowTargets();
      final rowTargets = <_ItemTarget>[
        const _ItemTarget(id: 'letter_go_back', label: 'Go Back'),
      ];
      rowTargets.addAll(
        rowIndexes
          .map(
            (row) =>
                _ItemTarget(id: 'letter_row_$row', label: 'Row ${row + 1}'),
          )
          .toList(),
      );
      return rowTargets;
    }

    final valid = _getValidLetters(_currentSpellingWord);
    final rowIndex = _activeLetterRowIndex;
    final rows = _letterRows();

    List<String> source;
    if (rowIndex == null) {
      source = rows.expand((r) => r).toList();
    } else if (rowIndex < rows.length) {
      source = rows[rowIndex];
    } else {
      source = [];
    }

    final letters = source
        .where((letter) => valid.contains(letter))
        .map((letter) => _ItemTarget(id: 'letter_$letter', label: letter))
        .toList();
    letters.add(const _ItemTarget(id: 'letter_go_back', label: 'Go Back'));
    return letters;
  }

  void _clearPendingPrompt() {
    _pendingPromptTimer?.cancel();
    _pendingPromptTimer = null;
    _promptToken += 1;
  }

  Future<void> _announcePrompt(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    if (_isAnnouncingPrompt) {
      _queuedPromptText = cleaned;
      return;
    }

    final now = DateTime.now();
    if (cleaned == _lastPromptText &&
        now.difference(_lastPromptAt).inMilliseconds < 700) {
      return;
    }

    _isAnnouncingPrompt = true;
    try {
      if (widget.scanPromptFunction != null) {
        await widget.scanPromptFunction!(cleaned);
      } else {
        await widget.announceFunction(
          cleaned,
          routing: 'personal',
          showSpeechBubble: false,
        );
      }
      _lastPromptText = cleaned;
      _lastPromptAt = DateTime.now();
    } catch (_) {
      // Non-critical for scanning flow.
    } finally {
      _isAnnouncingPrompt = false;

      final queued = _queuedPromptText;
      _queuedPromptText = null;
      if (queued != null && queued.trim().isNotEmpty) {
        Future.microtask(() => _announcePrompt(queued));
      }
    }
  }

  Future<void> _schedulePromptForCurrentTarget() async {
    String prompt = '';

    if (_scanPhase == 'sections') {
      final sections = _sectionTargets();
      if (_sectionIndex < 0 || _sectionIndex >= sections.length) return;
      prompt = sections[_sectionIndex].label;
    } else {
      final sections = _sectionTargets();
      if (_sectionIndex < 0 || _sectionIndex >= sections.length) return;
      final sectionId = sections[_sectionIndex].id;
      final items = _itemsForSection(sectionId);
      if (_itemIndex < 0 || _itemIndex >= items.length) return;
      final selected = items[_itemIndex];
      if (sectionId == 'letters' &&
          _lettersScanPhase == 'rows' &&
          selected.id.startsWith('letter_row_')) {
        final row = int.tryParse(selected.id.substring('letter_row_'.length));
        prompt = row == null ? selected.label : 'Row ${row + 1}';
      } else if (sectionId == 'letters' &&
          _lettersScanPhase == 'items' &&
          selected.id.startsWith('letter_') &&
          selected.id != 'letter_go_back') {
        prompt = selected.label.toLowerCase();
      } else {
        prompt = selected.label;
      }
    }

    if (prompt.isEmpty) return;

    _clearPendingPrompt();
    final token = _promptToken;
    if (!mounted || token != _promptToken) return;
    _pendingPromptTimer = null;
    await _announcePrompt(prompt);
  }

  Future<void> _advanceScan() async {
    if (!mounted) return;
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_scanPhase == 'sections') {
      final sections = _sectionTargets();
      if (sections.isEmpty) return;
      setState(() {
        _sectionIndex = (_sectionIndex + 1) % sections.length;
      });
      unawaited(_schedulePromptForCurrentTarget());
      return;
    }

    final sections = _sectionTargets();
    if (_sectionIndex < 0 || _sectionIndex >= sections.length) {
      setState(() {
        _scanPhase = 'sections';
        _itemIndex = -1;
      });
      _advanceScanSync();
      unawaited(_schedulePromptForCurrentTarget());
      return;
    }

    final items = _itemsForSection(sections[_sectionIndex].id);
    if (items.isEmpty) {
      setState(() {
        _scanPhase = 'sections';
        _itemIndex = -1;
      });
      _advanceScanSync();
      unawaited(_schedulePromptForCurrentTarget());
      return;
    }

    setState(() {
      _itemIndex = (_itemIndex + 1) % items.length;
    });
    unawaited(_schedulePromptForCurrentTarget());
  }

  void _advanceScanSync() {
    // Synchronous state change only (no prompt). Used for immediate switch response.
    if (!mounted) return;
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_scanPhase == 'sections') {
      final sections = _sectionTargets();
      if (sections.isEmpty) return;
      setState(() {
        _sectionIndex = (_sectionIndex + 1) % sections.length;
      });
      return;
    }

    final sections = _sectionTargets();
    if (_sectionIndex < 0 || _sectionIndex >= sections.length) {
      setState(() {
        _scanPhase = 'sections';
        _itemIndex = -1;
      });
      _advanceScanSync();
      return;
    }

    final items = _itemsForSection(sections[_sectionIndex].id);
    if (items.isEmpty) {
      setState(() {
        _scanPhase = 'sections';
        _itemIndex = -1;
      });
      _advanceScanSync();
      return;
    }

    setState(() {
      _itemIndex = (_itemIndex + 1) % items.length;
    });
  }

  List<int> _letterRowTargets() {
    final rowCount = _letterRows().length;
    return List<int>.generate(rowCount, (index) => index);
  }

  void _startAutoScanTimer() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(Duration(milliseconds: _scanDelayMs), (_) {
      if (!mounted || _scanMode != 'auto' || _isAutoTickRunning) return;
      _isAutoTickRunning = true;
      unawaited(() async {
        try {
          await _advanceScan();
        } finally {
          _isAutoTickRunning = false;
        }
      }());
    });
  }

  void _enterSectionScan(String sectionId) {
    _stopScanning();
    setState(() {
      _scanPhase = 'items';
      _itemIndex = -1;
      if (sectionId == 'letters') {
        _lettersScanPhase = 'rows';
        _activeLetterRowIndex = null;
      }
    });

    if (_scanMode == 'auto') {
      _advanceScanSync();  // Immediate visual feedback
      unawaited(_schedulePromptForCurrentTarget());  // Schedule prompt async
      _startAutoScanTimer();
      return;
    }

    _advanceScanSync();  // Immediate visual feedback
  }

  void _startScanning() {
    if (!mounted) return;

    if (_scanMode == 'step') {
      if ((_scanPhase == 'sections' && _sectionIndex == -1) ||
          (_scanPhase == 'items' && _itemIndex == -1)) {
        _advanceScanSync();  // Immediate visual feedback
        unawaited(_schedulePromptForCurrentTarget());  // Schedule prompt async
      }
      return;
    }

    _scanTimer?.cancel();
    _advanceScanSync();  // Immediate visual feedback
    unawaited(_schedulePromptForCurrentTarget());  // Schedule prompt async
    _startAutoScanTimer();
  }

  void _stopScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isAutoTickRunning = false;
    _clearPendingPrompt();
  }

  void _resetToSectionsAndRestart({int delayMs = 0}) {
    _stopScanning();
    setState(() {
      _scanPhase = 'sections';
      _sectionIndex = -1;
      _itemIndex = -1;
    });

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_waitForSwitchToScan && _waitingForInitialSwitch) return;
      _startScanning();
    });
  }

  Future<void> _handleItemSelected() async {
    final sections = _sectionTargets();
    if (_sectionIndex < 0 || _sectionIndex >= sections.length) return;
    final items = _itemsForSection(sections[_sectionIndex].id);
    if (_itemIndex < 0 || _itemIndex >= items.length) return;

    final selected = items[_itemIndex];
    final id = selected.id;

    if (id == 'speak_display') {
      await _speakDisplay();
      return;
    }
    if (id == 'backspace') {
      await _backspaceCurrentWord();
      return;
    }
    if (id == 'clean_text') {
      await _cleanDisplayText();
      return;
    }
    if (id == 'clear_word') {
      await _clearBuildSpace();
      return;
    }
    if (id == 'home') {
      _stopScanning();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (id == 'pred_go_back' || id == 'letter_go_back') {
      _resetToSectionsAndRestart(delayMs: 120);
      return;
    }

    if (id.startsWith('pred_')) {
      final word = id.substring(5);
      await _handlePredictionTap(word);
      return;
    }

    if (id.startsWith('letter_')) {
      final letter = id.substring(7);
      await _handleLetterTap(letter);
      return;
    }
  }

  void _handleSpace() {
    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_waitForSwitchToScan && _waitingForInitialSwitch) {
      setState(() {
        _waitingForInitialSwitch = false;
      });
      _startScanning();
      return;
    }

    final hasTarget =
        (_scanPhase == 'sections' && _sectionIndex >= 0) ||
        (_scanPhase == 'items' && _itemIndex >= 0);

    if (!hasTarget) {
      _startScanning();
      return;
    }

    _clearPendingPrompt();

    if (_scanPhase == 'sections') {
      final sections = _sectionTargets();
      if (_sectionIndex < 0 || _sectionIndex >= sections.length) return;
      _enterSectionScan(sections[_sectionIndex].id);
      return;
    }

    final sections = _sectionTargets();
    if (_sectionIndex < 0 || _sectionIndex >= sections.length) return;
    final activeSectionId = sections[_sectionIndex].id;

    if (activeSectionId == 'letters' && _lettersScanPhase == 'rows') {
      final items = _itemsForSection(activeSectionId);
      if (_itemIndex < 0 || _itemIndex >= items.length) return;
      final selected = items[_itemIndex];
      if (selected.id == 'letter_go_back') {
        _resetToSectionsAndRestart(delayMs: 120);
        return;
      }
      if (!selected.id.startsWith('letter_row_')) return;
      final row = int.tryParse(selected.id.substring('letter_row_'.length));
      if (row == null) return;

      _stopScanning();
      setState(() {
        _lettersScanPhase = 'items';
        _activeLetterRowIndex = row;
        _itemIndex = -1;
      });

      if (_scanMode == 'auto') {
        _advanceScanSync();  // Immediate visual feedback
        unawaited(_schedulePromptForCurrentTarget());  // Schedule prompt async
        _startAutoScanTimer();
        return;
      }

      _advanceScanSync();  // Immediate visual feedback
      unawaited(_schedulePromptForCurrentTarget());  // Schedule prompt async
      return;
    }

    _handleItemSelected();
  }

  void _handleRawKey(RawKeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent == false) {
      return;
    }

    final isSwitchKey =
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey.keyLabel == ' ';

    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        _scanMode == 'step') {
      _advanceScanSync();  // Immediate visual feedback
      unawaited(_schedulePromptForCurrentTarget());  // Schedule prompt async
      return;
    }

    if (isSwitchKey && event is RawKeyDownEvent) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSwitchActivationMs < 180) {
        return;
      }
      _lastSwitchActivationMs = now;
      _handleSpace();
    }
  }

  bool _isSectionHighlighted(String sectionId) {
    if (_scanPhase != 'sections' || _sectionIndex < 0) return false;
    final sections = _sectionTargets();
    if (_sectionIndex >= sections.length) return false;
    return sections[_sectionIndex].id == sectionId;
  }

  bool _isItemHighlighted(String sectionId, String itemId) {
    if (_scanPhase != 'items') return false;
    final sections = _sectionTargets();
    if (_sectionIndex < 0 || _sectionIndex >= sections.length) return false;
    if (sections[_sectionIndex].id != sectionId) return false;
    final items = _itemsForSection(sectionId);
    if (_itemIndex < 0 || _itemIndex >= items.length) return false;
    return items[_itemIndex].id == itemId;
  }

  Widget _buildSectionCard({
    required String sectionId,
    required String title,
    required Widget child,
  }) {
    final highlighted = _isSectionHighlighted(sectionId);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlighted
            ? Colors.orange.withValues(alpha: 0.16)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? Colors.orange : Colors.blueGrey.shade100,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String id,
    String label,
    VoidCallback onPressed, {
    String sectionId = 'action',
    required Color highlightColor,
  }) {
    final highlighted = _isItemHighlighted(sectionId, id);
    return SizedBox(
      height: 34,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: highlighted
                    ? [Colors.white, highlightColor.withOpacity(0.5)]
                    : [Colors.white, Colors.white],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: highlighted ? highlightColor : Colors.grey.shade300,
                width: highlighted ? 3.0 : 1.0,
              ),
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: highlightColor.withOpacity(0.6),
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
            child: Center(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPredictionChip(String prediction, Color highlightColor) {
    final id = 'pred_$prediction';
    final highlighted = _isItemHighlighted('choose-word', id);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handlePredictionTap(prediction),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: highlighted
                    ? [Colors.white, highlightColor.withOpacity(0.5)]
                    : [Colors.white, Colors.white],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlighted ? highlightColor : Colors.grey.shade300,
                width: highlighted ? 3.0 : 1.0,
              ),
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: highlightColor.withOpacity(0.6),
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
            child: Text(
              prediction,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLetterButton(String letter) {
    final valid = _getValidLetters(_currentSpellingWord).contains(letter);
    final id = 'letter_$letter';
    final highlighted = _isItemHighlighted('letters', id);
    final rowHighlighted = _isLetterRowHighlighted(letter);
    return Opacity(
      opacity: valid ? 1.0 : 0.35,
      child: SizedBox(
        width: 90,
        height: 90,
        child: ElevatedButton(
          onPressed: valid ? () => _handleLetterTap(letter) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: highlighted || rowHighlighted
                ? Colors.orange
                : Colors.white,
            foregroundColor: Colors.black,
            padding: EdgeInsets.zero,
            minimumSize: const Size(90, 90),
            fixedSize: const Size(90, 90),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
              side: BorderSide(
                color: highlighted || rowHighlighted
                    ? Colors.deepOrange
                    : Colors.blueGrey.shade200,
              ),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              letter,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
            ),
          ),
        ),
      ),
    );
  }

  bool _isLetterRowHighlighted(String letter) {
    if (_scanPhase != 'items' || _lettersScanPhase != 'rows') return false;
    final sections = _sectionTargets();
    if (_sectionIndex < 0 || _sectionIndex >= sections.length) return false;
    if (sections[_sectionIndex].id != 'letters') return false;

    final items = _itemsForSection('letters');
    if (_itemIndex < 0 || _itemIndex >= items.length) return false;
    final selected = items[_itemIndex];
    if (!selected.id.startsWith('letter_row_')) return false;
    final selectedRow = int.tryParse(
      selected.id.substring('letter_row_'.length),
    );
    if (selectedRow == null) return false;

    final rows = _letterRows();
    final rowIndex = rows.indexWhere((row) => row.contains(letter));
    if (rowIndex < 0) return false;
    return rowIndex == selectedRow;
  }

  Widget _buildGridStyleHeader({
    required Color headerBackgroundColor,
    required Color headerTextColor,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: headerBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Spelling',
                      style: TextStyle(
                        color: headerTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'v1.0.2+18',
                      style: TextStyle(
                        color: headerTextColor.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: true,
    );
    final userSettings = settingsProvider.settings;
    final Color headerTextColor = userSettings != null
        ? Color(userSettings.lightColorValue)
        : Colors.white;
    final Color headerBackgroundColor = userSettings != null
        ? Color(userSettings.darkColorValue)
        : Colors.black;
    final Color scanHighlightColor = userSettings != null
      ? Color(userSettings.lightColorValue)
      : Colors.orange;

    final displayValue = _displayText.isEmpty ? ' ' : _displayText;

    return Scaffold(
      body: RawKeyboardListener(
        autofocus: true,
        focusNode: _focusNode,
        onKey: _handleRawKey,
        child: Stack(
          children: [
            Column(
              children: [
            _buildGridStyleHeader(
              headerBackgroundColor: headerBackgroundColor,
              headerTextColor: headerTextColor,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      displayValue,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isSectionHighlighted('action')
                          ? Colors.orange.withValues(alpha: 0.16)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSectionHighlighted('action')
                            ? Colors.orange
                            : Colors.blueGrey.shade100,
                        width: _isSectionHighlighted('action') ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            'speak_display',
                            'Speak',
                            _speakDisplay,
                            highlightColor: scanHighlightColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionButton(
                            'clean_text',
                            'Clean',
                            _cleanDisplayText,
                            highlightColor: scanHighlightColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionButton(
                            'backspace',
                            'Back',
                            _backspaceCurrentWord,
                            highlightColor: scanHighlightColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionButton(
                            'clear_word',
                            'Clear',
                            _clearBuildSpace,
                            highlightColor: scanHighlightColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionButton('home', 'Home', () {
                            _stopScanning();
                            Navigator.of(context).pop();
                          }, highlightColor: scanHighlightColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                children: [
                  _buildSectionCard(
                    sectionId: 'letters',
                    title: 'Letters',
                    child: Column(
                      children: [
                        _buildActionButton('letter_go_back', 'Go Back', () {
                          _resetToSectionsAndRestart(delayMs: 120);
                        },
                            sectionId: 'letters',
                            highlightColor: scanHighlightColor),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _letterRows().map((row) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Wrap(
                                spacing: 10,
                                children: row.map(_buildLetterButton).toList(),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  _buildSectionCard(
                    sectionId: 'choose-word',
                    title: 'Choose Word',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildActionButton('pred_go_back', 'Go Back', () {
                          _resetToSectionsAndRestart(delayMs: 120);
                        },
                            sectionId: 'choose-word',
                            highlightColor: scanHighlightColor),
                        const SizedBox(height: 8),
                        if (_loadingPredictions)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_currentPredictions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text('No suggestions yet'),
                          )
                        else
                          Wrap(
                            children: _currentPredictions
                                .map(
                                  (prediction) =>
                                      _buildPredictionChip(
                                        prediction,
                                        scanHighlightColor,
                                      ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
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
                            offset: const Offset(0, 4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                child: const Icon(
                                  Icons.chat_bubble_outline,
                                  size: 45,
                                  color: Colors.grey,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 30),
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
          ],
        ),
      ),
    );
  }
}

class _SectionTarget {
  final String id;
  final String label;

  const _SectionTarget({required this.id, required this.label});
}

class _ItemTarget {
  final String id;
  final String label;

  const _ItemTarget({required this.id, required this.label});
}
