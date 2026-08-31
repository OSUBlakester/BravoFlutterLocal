import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'config/environment_config.dart';
import 'services/user_settings_provider.dart';
import 'services/wake_word_service.dart';
import 'services/authenticated_http_client.dart';
import 'main.dart';

enum _TextScreen {
  contactPicker,
  modeMenu,
  recentTextVoice,
  llmOptions,
  postSelection,
  afterSend,
}

class TextingPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final Future<void> Function(
    String text, {
    String routing,
    int? speechRate,
    bool showSpeechBubble,
  })? announceFunction;

  const TextingPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    this.announceFunction,
  });

  @override
  TextingPageState createState() => TextingPageState();
}

class TextingPageState extends State<TextingPage> {
  // ─── Screen state ───────────────────────────────────────────────────────────
  _TextScreen _screen = _TextScreen.contactPicker;

  // ─── Texting data ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _contacts = [];
  String? _selectedContact;
  String _recentTextContent = '';
  List<String> _conversationLines = [];
  List<Map<String, dynamic>> _currentOptions = [];
  List<Map<String, dynamic>> _lastLLMOptions = [];
  bool _hadRecentText = false;

  // ─── UI state ───────────────────────────────────────────────────────────────
  bool _isLoading = false;
  // ─── Scanning ───────────────────────────────────────────────────────────────
  bool _isScanning = false;
  bool _waitingForUserInput = false;
  bool _isAnnouncingScanningPrompt = false;
  int? _scanningIndex;
  Timer? _scanningTimer;
  bool _suppressScanning = false;
  int _currentScanCycle = 0;
  bool _waitingForInitialSwitch = false;

  // ─── Wake word / partner speech ─────────────────────────────────────────────
  String _wakeWordInterjection = 'hey';
  String _wakeWordName = 'bravo';
  late stt.SpeechToText _speech;
  bool _speechInitialized = false;
  bool _ownListening = false;
  String _ownListeningMode = ''; // 'wake_word' | 'partner_speech'
  bool _partnerFirstSpeechDetected = false;
  String _lastPartnerTranscript = '';
  Timer? _partnerSilenceTimer;
  Timer? _partnerNoSpeechTimer;
  Timer? _partnerHardTimer;
  Timer? _partnerRestartTimer;
  bool _processingPartnerSpeech = false;
  int _ignoreSpeechInputUntilMs = 0;
  String _recentTextStatusMessage = '';

  // ─── TTS ────────────────────────────────────────────────────────────────────
  final FlutterTts _flutterTts = FlutterTts();

  // ─── Focus / admin ──────────────────────────────────────────────────────────
  FocusNode? _focusNode;
  bool _isAdminToolbarLocked = true;

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _speech = stt.SpeechToText();
    _setupTTS();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Stop WakeWordService immediately so it cannot fire while TextingPage is open.
      await WakeWordService.forceStopAndReset();
      WakeWordService.wakeWordShouldBeActive = false;
      await _readWakeWordSettings();
      await _initSpeech();
      await _loadContacts();
    });
  }

  @override
  void dispose() {
    _scanningTimer?.cancel();
    _partnerSilenceTimer?.cancel();
    _partnerNoSpeechTimer?.cancel();
    _partnerHardTimer?.cancel();
    _partnerRestartTimer?.cancel();
    _stopOwnListening(restoreWakeWord: true);
    _focusNode?.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // ─── TTS ────────────────────────────────────────────────────────────────────

  Future<void> _setupTTS() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
    } catch (e) {
      debugPrint('TextingPage TTS setup: $e');
    }
  }

  Future<void> _announce(String text, {String routing = 'system'}) async {
    if (widget.announceFunction != null) {
      await widget.announceFunction!(
        text,
        routing: routing,
        showSpeechBubble: true,
      );
    } else {
      await _speakLocal(text);
    }
  }

  Future<void> _speakLocal(String text) async {
    if (!mounted || text.isEmpty) return;
    final wasScanning = _isScanning;
    if (wasScanning) _stopAuditoryScanning();

    try {
      await _flutterTts.stop();
      final completer = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      await _flutterTts.speak(text);
      final wordCount =
          text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final timeoutMs = ((wordCount * 700) + 3000).clamp(3000, 60000);
      await completer.future.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('TextingPage _speakLocal error: $e');
    }

    if (wasScanning &&
        !_waitingForUserInput &&
        _currentOptions.isNotEmpty &&
        mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_waitingForUserInput) _startAuditoryScanning();
      });
    }
  }

  // ─── Contacts ───────────────────────────────────────────────────────────────

  Future<void> _loadContacts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/friends-family',
        baseHeaders: {'X-User-ID': widget.aacUserId},
        timeoutSeconds: 15,
      );

      List<Map<String, dynamic>> contacts = [];
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawList = (data['friends_family'] as List?) ?? [];
        contacts = rawList
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      if (mounted) {
        setState(() {
          _contacts = contacts;
          _isLoading = false;
        });
        _buildContactPickerOptions();
      }
    } catch (e) {
      debugPrint('TextingPage _loadContacts error: $e');
      if (mounted) {
        setState(() {
          _contacts = [];
          _isLoading = false;
        });
        _buildContactPickerOptions();
      }
    }
  }

  // ─── Screen builders ─────────────────────────────────────────────────────────

  void _buildContactPickerOptions() {
    _stopAuditoryScanning();
    final options = <Map<String, dynamic>>[];

    for (final c in _contacts) {
      final name = (c['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      options.add({'label': name, 'action': 'contact', 'name': name});
    }
    options.add({'label': 'Add New Contact', 'action': 'add_contact'});
    options.add({'label': 'Exit Text', 'action': 'exit'});

    setState(() {
      _screen = _TextScreen.contactPicker;
      _currentOptions = options;
      _scanningIndex = null;
    });
    _maybeStartScanning();
  }

  void _buildModeMenuOptions() {
    _stopAuditoryScanning();
    setState(() {
      _screen = _TextScreen.modeMenu;
      _currentOptions = [
        {'label': 'Reply to Recent Text', 'action': 'reply_recent'},
        {'label': 'New Topic', 'action': 'new_topic'},
        {'label': 'Go Back', 'action': 'go_back'},
        {'label': 'Exit Text', 'action': 'exit'},
      ];
      _scanningIndex = null;
    });
    _maybeStartScanning();
  }

  Future<void> _buildRecentTextVoiceScreen() async {
    _stopAuditoryScanning();
    _stopOwnListening();
    // Kill WakeWordService BEFORE the announcement so it cannot hear
    // the wake phrase spoken aloud in the TTS and fire prematurely.
    await WakeWordService.forceStopAndReset();
    WakeWordService.wakeWordShouldBeActive = false;
    if (!mounted) return;
    final contact = _selectedContact ?? 'your contact';
    final wakePhrase = '$_wakeWordInterjection $_wakeWordName';
    setState(() {
      _screen = _TextScreen.recentTextVoice;
      _currentOptions = [];
      _scanningIndex = null;
      _recentTextStatusMessage = 'Say "$wakePhrase" to begin';
    });
    await _announce(
      'Say $wakePhrase when you are ready to read the latest text from $contact.',
    );
    if (!mounted || _screen != _TextScreen.recentTextVoice) return;
    _startWakeWordListening();
  }

  void _buildAfterSendScreen() {
    _stopAuditoryScanning();
    setState(() {
      _screen = _TextScreen.afterSend;
      _currentOptions = [
        {'label': 'Send Another Text', 'action': 'send_another'},
        {'label': 'Done', 'action': 'done'},
      ];
      _scanningIndex = null;
    });
    _maybeStartScanning();
  }

  // ─── LLM ────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _callLLM(String basePrompt) async {
    final settingsProvider =
        Provider.of<UserSettingsProvider>(context, listen: false);
    final llmOptions = settingsProvider.settings?.llmOptions ?? 10;
    final summaryOff = settingsProvider.settings?.summaryOff ?? false;

    final summaryInstruction = summaryOff
        ? 'The "summary" key must contain the exact same FULL text as the "option" key.'
        : 'For the "summary" key: write a 3-5 word label capturing the main intent. '
            'If the option is 5 words or less, use the full text as the summary.';

    final fullPrompt = '$basePrompt\n'
        'Generate up to $llmOptions options.\n'
        'Format as a JSON list: [{"option": "full text", "summary": "short label"}, ...].\n'
        '$summaryInstruction';

    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/llm',
      baseHeaders: {'X-User-ID': widget.aacUserId},
      body: json.encode({'prompt': fullPrompt}),
      timeoutSeconds: 30,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data
          .map<Map<String, dynamic>>((item) => {
                'label': (item['summary'] ?? item['option'] ?? '') as String,
                'fullText': (item['option'] ?? item['summary'] ?? '') as String,
                'action': 'select_option',
              })
          .where((o) => (o['label'] as String).isNotEmpty)
          .toList();
    }
    return [];
  }

  String _buildReplyPrompt() {
    final contact = _selectedContact ?? 'your contact';
    final parts = <String>[
      'The user wants to reply to a text message from $contact.',
    ];
    if (_recentTextContent.isNotEmpty) {
      parts.add('Their recent message: "$_recentTextContent"');
    }
    if (_conversationLines.isNotEmpty) {
      parts.add('Conversation so far:\n${_conversationLines.join('\n')}');
    }
    parts.add(
        'Generate short, natural, complete text message reply options ready to send.');
    return parts.join('\n');
  }

  String _buildNewTopicPrompt() {
    final contact = _selectedContact ?? 'your contact';
    return 'The user wants to start a new text message conversation with $contact. '
        'Generate short, friendly opening text message options ready to send.';
  }

  String _buildFollowUpPrompt() {
    final contact = _selectedContact ?? 'your contact';
    final parts = <String>['The user is texting $contact.'];
    if (_conversationLines.isNotEmpty) {
      parts.add('Conversation so far:\n${_conversationLines.join('\n')}');
    }
    if (_lastLLMOptions.isNotEmpty) {
      final excluded = _lastLLMOptions
          .map((o) => o['fullText'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .join('; ');
      if (excluded.isNotEmpty) parts.add('Do not repeat: $excluded');
    }
    parts.add(
        'Generate short follow-up text message options to continue the conversation.');
    return parts.join('\n');
  }

  Future<void> _loadReplyOptions() async {
    if (!mounted) return;
    setState(() {
      _screen = _TextScreen.llmOptions;
      _isLoading = true;
    });
    _stopAuditoryScanning();

    try {
      final options = await _callLLM(_buildReplyPrompt());
      if (!mounted) return;

      if (options.isEmpty) {
        await _announce('Unable to generate reply options right now.');
        _buildModeMenuOptions();
        return;
      }

      _lastLLMOptions = List.from(options);
      final allOptions = [
        ...options,
        {'label': 'Ask Again', 'action': 'ask_again'},
        {'label': 'Go Back', 'action': 'go_back'},
        {'label': 'Exit Text', 'action': 'exit'},
      ];
      setState(() {
        _currentOptions = allOptions;
        _isLoading = false;
        _scanningIndex = null;
      });
      _maybeStartScanning();
    } catch (e) {
      debugPrint('TextingPage _loadReplyOptions error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _buildModeMenuOptions();
      }
    }
  }

  Future<void> _loadNewTopicOptions() async {
    if (!mounted) return;
    setState(() {
      _screen = _TextScreen.llmOptions;
      _isLoading = true;
    });
    _stopAuditoryScanning();

    try {
      final options = await _callLLM(_buildNewTopicPrompt());
      if (!mounted) return;

      if (options.isEmpty) {
        await _announce('Unable to generate topic options right now.');
        _buildModeMenuOptions();
        return;
      }

      _lastLLMOptions = List.from(options);
      final allOptions = [
        ...options,
        {'label': 'Ask Again', 'action': 'ask_again'},
        {'label': 'Go Back', 'action': 'go_back'},
        {'label': 'Exit Text', 'action': 'exit'},
      ];
      setState(() {
        _currentOptions = allOptions;
        _isLoading = false;
        _scanningIndex = null;
      });
      _maybeStartScanning();
    } catch (e) {
      debugPrint('TextingPage _loadNewTopicOptions error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _buildModeMenuOptions();
      }
    }
  }

  Future<void> _loadFollowUpOptions() async {
    if (!mounted) return;
    setState(() {
      _screen = _TextScreen.postSelection;
      _isLoading = true;
    });
    _stopAuditoryScanning();

    try {
      final options = await _callLLM(_buildFollowUpPrompt());
      if (!mounted) return;

      _lastLLMOptions = List.from(options);
      final allOptions = <Map<String, dynamic>>[
        {'label': 'Send Text', 'action': 'send_text'},
        ...options,
        {'label': 'Go Back', 'action': 'go_back'},
        {'label': 'Exit Text', 'action': 'exit'},
      ];
      setState(() {
        _currentOptions = allOptions;
        _isLoading = false;
        _scanningIndex = null;
      });
      _maybeStartScanning();
    } catch (e) {
      debugPrint('TextingPage _loadFollowUpOptions error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentOptions = [
            {'label': 'Send Text', 'action': 'send_text'},
            {'label': 'Go Back', 'action': 'go_back'},
            {'label': 'Exit Text', 'action': 'exit'},
          ];
          _scanningIndex = null;
        });
        _maybeStartScanning();
      }
    }
  }

  // ─── Option handling ─────────────────────────────────────────────────────────

  Future<void> _handleOptionSelected(Map<String, dynamic> option) async {
    final action = option['action'] as String? ?? '';

    if (action == 'contact') {
      _stopAuditoryScanning();
      final contactName = option['name'] as String? ?? 'your contact';
      setState(() {
        _selectedContact = contactName;
        _recentTextContent = '';
        _conversationLines = [];
        _hadRecentText = false;
      });
      await _announce('I want to text $contactName.');
      _buildModeMenuOptions();
    } else if (action == 'add_contact') {
      await _announce(
          'I need to add a new contact. Please ask me yes or no questions'
          ' about who I want to add.');
    } else if (action == 'reply_recent') {
      _stopAuditoryScanning();
      setState(() {
        _hadRecentText = true;
      });
      _buildRecentTextVoiceScreen();
    } else if (action == 'new_topic') {
      _stopAuditoryScanning();
      setState(() {
        _hadRecentText = false;
      });
      await _loadNewTopicOptions();
    } else if (action == 'select_option') {
      _stopAuditoryScanning();
      final fullText = (option['fullText'] as String?)?.trim() ?? '';
      if (fullText.isEmpty) return;
      setState(() {
        _conversationLines = [..._conversationLines, 'Me: $fullText'];
      });
      await _announce(fullText);
      await _loadFollowUpOptions();
    } else if (action == 'send_text') {
      _stopAuditoryScanning();
      await _handleSendText();
    } else if (action == 'ask_again') {
      _stopAuditoryScanning();
      if (_hadRecentText) {
        await _loadReplyOptions();
      } else {
        await _loadNewTopicOptions();
      }
    } else if (action == 'go_back') {
      _stopAuditoryScanning();
      _handleGoBack();
    } else if (action == 'send_another') {
      _stopAuditoryScanning();
      setState(() {
        _recentTextContent = '';
        _hadRecentText = false;
      });
      _buildModeMenuOptions();
    } else if (action == 'done' || action == 'exit') {
      _stopAuditoryScanning();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _handleGoBack() {
    if (_screen == _TextScreen.modeMenu) {
      _buildContactPickerOptions();
    } else if (_screen == _TextScreen.recentTextVoice) {
      _buildModeMenuOptions();
    } else if (_screen == _TextScreen.llmOptions) {
      _buildModeMenuOptions();
    } else if (_screen == _TextScreen.postSelection) {
      if (_hadRecentText) {
        _loadReplyOptions();
      } else {
        _loadNewTopicOptions();
      }
    } else if (_screen == _TextScreen.afterSend) {
      _buildModeMenuOptions();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _showTextCopyModal() {
    final lines = _conversationLines
        .map((l) => l.startsWith('Me: ') ? l.substring(4) : l)
        .toList();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final checked = <int>{};
        return StatefulBuilder(
          builder: (_, setInnerState) {
            return AlertDialog(
              title: const Text('Copy Text History'),
              content: SizedBox(
                width: double.maxFinite,
                child: lines.isEmpty
                    ? const Text(
                        'No messages to copy.',
                        style: TextStyle(color: Colors.grey),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: lines.length,
                        itemBuilder: (_, i) {
                          return CheckboxListTile(
                            value: checked.contains(i),
                            onChanged: (selected) {
                              setInnerState(() {
                                if (selected == true) {
                                  checked.add(i);
                                } else {
                                  checked.remove(i);
                                }
                              });
                            },
                            title: Text(
                              lines[i],
                              style: const TextStyle(fontSize: 15),
                            ),
                            activeColor: Colors.green.shade700,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: lines.isEmpty
                      ? null
                      : () async {
                          final selected = checked.isEmpty
                              ? lines
                              : checked.toList().map((i) => lines[i]).toList();
                          await Clipboard.setData(
                              ClipboardData(text: selected.join('\n')));
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Copy'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleSendText() async {
    final contact = _selectedContact ?? 'your contact';
    final messageText = _conversationLines
        .where((l) => l.startsWith('Me: '))
        .map((l) => l.substring(4))
        .join('\n');

    if (messageText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: messageText));
    }

    await _announce(
      'Please copy my message and paste it into the messaging app for $contact.',
    );

    _buildAfterSendScreen();
  }

  // ─── Wake word / partner speech ──────────────────────────────────────────────

  Future<void> _readWakeWordSettings() async {
    if (!mounted) return;
    final settingsProvider =
        Provider.of<UserSettingsProvider>(context, listen: false);
    _wakeWordInterjection =
        (settingsProvider.settings?.wakeWordInterjection ?? 'hey')
            .trim()
            .toLowerCase();
    _wakeWordName =
        (settingsProvider.settings?.wakeWordName ?? 'bravo')
            .trim()
            .toLowerCase();
  }

  Future<void> _initSpeech() async {
    try {
      _speech = stt.SpeechToText();
      _speechInitialized = await _speech.initialize(
        onError: (error) {
          debugPrint('TextingPage speech error: ${error.errorMsg}');
          if (_ownListening && _ownListeningMode.isNotEmpty) {
            _scheduleListeningRestart();
          }
        },
        onStatus: (status) {
          debugPrint('TextingPage speech status: $status');
          if ((status == 'done' || status == 'notListening') &&
              _ownListening &&
              !_processingPartnerSpeech) {
            _scheduleListeningRestart();
          }
        },
      );
    } catch (e) {
      debugPrint('TextingPage _initSpeech error: $e');
    }
  }

  bool _matchesWakeWord(String transcript) {
    String norm(String v) => v
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final t = norm(transcript);
    final w = norm('$_wakeWordInterjection $_wakeWordName');
    if (t.isEmpty || w.isEmpty) return false;
    if (t.contains(w)) return true;
    return t.replaceAll(' ', '').contains(w.replaceAll(' ', ''));
  }

  void _stopOwnListening({bool restoreWakeWord = false}) {
    _partnerSilenceTimer?.cancel();
    _partnerNoSpeechTimer?.cancel();
    _partnerHardTimer?.cancel();
    _partnerRestartTimer?.cancel();
    if (_ownListening) {
      _speech.stop();
      if (mounted) {
        setState(() {
          _ownListening = false;
          _ownListeningMode = '';
        });
      } else {
        _ownListening = false;
        _ownListeningMode = '';
      }
    }
    _processingPartnerSpeech = false;
    if (restoreWakeWord) {
      WakeWordService.resumeWakeWordService();
    }
  }

  void _scheduleListeningRestart({int delayMs = 300}) {
    _partnerRestartTimer?.cancel();
    _partnerRestartTimer =
        Timer(Duration(milliseconds: delayMs), () async {
      if (!mounted || !_ownListening || _processingPartnerSpeech) return;
      if (_screen != _TextScreen.recentTextVoice) return;
      final mode = _ownListeningMode;
      if (mode.isEmpty) return;
      debugPrint('TextingPage: restarting speech session for $mode');
      if (_speech.isListening) await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted && _ownListening) await _startOwnListening(mode);
    });
  }

  Future<void> _startOwnListening(String mode) async {
    if (!mounted) return;
    if (!_speechInitialized) {
      await _initSpeech();
      if (!_speechInitialized) return;
    }

    // Take over speech recognition from WakeWordService
    await WakeWordService.forceStopAndReset();
    WakeWordService.wakeWordShouldBeActive = false;

    if (_speech.isListening) await _speech.stop();

    if (mounted) {
      setState(() {
        _ownListening = true;
        _ownListeningMode = mode;
        _lastPartnerTranscript = '';
      });
    } else {
      _ownListening = true;
      _ownListeningMode = mode;
      _lastPartnerTranscript = '';
    }

    // Ignore window: discard results for 1.5 s after starting so acoustic echo
    // from the just-finished TTS announcement cannot trigger the wake word.
    _ignoreSpeechInputUntilMs =
        DateTime.now().millisecondsSinceEpoch + 1500;

    final pauseFor = mode == 'partner_speech'
        ? const Duration(seconds: 10)
        : const Duration(seconds: 30); // wake_word: long session so it doesn't cut out

    _speech.listen(
      onResult: (result) {
        if (!_ownListening || _ownListeningMode != mode) return;
        if (DateTime.now().millisecondsSinceEpoch < _ignoreSpeechInputUntilMs) {
          return; // still in post-TTS ignore window
        }
        final transcript = result.recognizedWords.toLowerCase();
        // Always update the real-time display (matches GamesPage behaviour)
        if (transcript.isNotEmpty && mounted) {
          setState(() { _lastPartnerTranscript = transcript; });
        }
        if (mode == 'wake_word') {
          if (_matchesWakeWord(transcript)) {
            if (mounted) {
              setState(() { _ownListening = false; });
            } else {
              _ownListening = false;
            }
            _speech.stop();
            _handleWakeWordDetected();
          }
        } else if (mode == 'partner_speech') {
          if (transcript.isNotEmpty) {
            if (!_partnerFirstSpeechDetected) {
              _partnerFirstSpeechDetected = true;
              _partnerNoSpeechTimer?.cancel();
            }
            // Reset 3-second silence timer on every new result
            _partnerSilenceTimer?.cancel();
            _partnerSilenceTimer = Timer(const Duration(seconds: 3), () {
              if (!mounted || !_ownListening) return;
              if (_processingPartnerSpeech) return;
              final t = _lastPartnerTranscript.trim();
              if (t.isEmpty) return;
              _processingPartnerSpeech = true;
              _speech.stop();
              if (mounted) {
                setState(() { _ownListening = false; });
              } else {
                _ownListening = false;
              }
              _processPartnerSpeech(t);
            });
            // iOS fires finalResult prematurely — restart quickly so silence
            // timer stays alive from continuous partials
            if (result.finalResult) {
              _partnerRestartTimer?.cancel();
              _partnerRestartTimer =
                  Timer(const Duration(milliseconds: 200), () async {
                if (!mounted || !_ownListening || _processingPartnerSpeech) {
                  return;
                }
                await _startOwnListening('partner_speech');
              });
            }
          }
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
      ),
      pauseFor: pauseFor,
      localeId: 'en-US',
    );
  }

  Future<void> _startWakeWordListening() async {
    if (!mounted) return;
    _stopOwnListening();
    if (!_speechInitialized) {
      await _initSpeech();
    }
    if (mounted) setState(() { _lastPartnerTranscript = ''; });
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && _screen == _TextScreen.recentTextVoice) {
      await _startOwnListening('wake_word');
    }
  }

  Future<void> _handleWakeWordDetected() async {
    if (!mounted) return;
    _stopAuditoryScanning();
    _partnerSilenceTimer?.cancel();
    _partnerNoSpeechTimer?.cancel();
    _partnerHardTimer?.cancel();
    _partnerFirstSpeechDetected = false;
    _lastPartnerTranscript = '';
    _processingPartnerSpeech = false;
    if (mounted) setState(() { _recentTextStatusMessage = 'Read most recent text message'; });
    await _announce("I'm listening. Please read the text message aloud.");
    if (!mounted || _screen != _TextScreen.recentTextVoice) return;
    await _startOwnListening('partner_speech');

    // 10-second no-speech timeout
    _partnerNoSpeechTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_ownListening || _partnerFirstSpeechDetected) return;
      _stopOwnListening();
      _buildRecentTextVoiceScreen();
    });
    // 30-second hard cap
    _partnerHardTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || !_ownListening) return;
      _stopOwnListening();
      _buildRecentTextVoiceScreen();
    });
  }

  Future<void> _processPartnerSpeech(String transcript) async {
    if (!mounted) return;
    _partnerSilenceTimer?.cancel();
    _partnerNoSpeechTimer?.cancel();
    _partnerHardTimer?.cancel();
    setState(() {
      _recentTextContent = transcript;
      _recentTextStatusMessage = 'Generating response options';
    });
    await _announce('Got it. Give me a moment to respond.');
    await _loadReplyOptions();
  }

  // ─── Scanning ────────────────────────────────────────────────────────────────

  void _maybeStartScanning() {
    if (!mounted) return;
    final settingsProvider =
        Provider.of<UserSettingsProvider>(context, listen: false);
    if (settingsProvider.settings?.scanningOff == true ||
        _suppressScanning ||
        _isLoading) {
      return;
    }
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    if (scanMode == 'wait-for-switch') {
      if (mounted) {
        setState(() {
          _waitingForInitialSwitch = true;
        });
      }
      return;
    }
    _startAuditoryScanning();
  }

  void _startAuditoryScanning() {
    if (_currentOptions.isEmpty || _suppressScanning || !mounted) return;
    _scanningTimer?.cancel();

    final settingsProvider =
        Provider.of<UserSettingsProvider>(context, listen: false);
    final scanDelay = settingsProvider.settings?.scanDelay ?? 3000;
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    setState(() {
      _isScanning = true;
      _scanningIndex = 0;
      _currentScanCycle = 0;
      _waitingForUserInput = false;
    });

    if (scanMode == 'auto') {
      _scanningTimer =
          Timer.periodic(Duration(milliseconds: scanDelay), (_) {
        if (mounted) _scanNextButton();
      });
    }

    _announceCurrentButton();
  }

  void _scanNextButton() {
    if (!_isScanning || _currentOptions.isEmpty || !mounted) return;
    final next = ((_scanningIndex ?? -1) + 1) % _currentOptions.length;
    if (next == 0) _currentScanCycle++;

    final settingsProvider =
        Provider.of<UserSettingsProvider>(context, listen: false);
    final scanLoopLimit = settingsProvider.settings?.scanLoopLimit ?? 3;

    if (_currentScanCycle >= scanLoopLimit) {
      _stopAuditoryScanning();
      if (mounted) {
        setState(() {
          _waitingForUserInput = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _scanningIndex = next;
      });
    }
    _announceCurrentButton();
  }

  void _stopAuditoryScanning() {
    _scanningTimer?.cancel();
    if (mounted) {
      setState(() {
        _isScanning = false;
        _scanningIndex = null;
        _waitingForUserInput = false;
        _currentScanCycle = 0;
        _waitingForInitialSwitch = false;
      });
    }
  }

  Future<void> _announceCurrentButton() async {
    if (_scanningIndex == null || _currentOptions.isEmpty || !mounted) return;
    if (_scanningIndex! >= _currentOptions.length) return;
    final label =
        _currentOptions[_scanningIndex!]['label'] as String? ?? '';
    if (label.isEmpty) return;

    if (mounted) {
      setState(() {
        _isAnnouncingScanningPrompt = true;
      });
    }
    try {
      await _flutterTts.stop();
      final completer = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      await _flutterTts.speak(label);
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('TextingPage _announceCurrentButton error: $e');
    }
    if (mounted) {
      setState(() {
        _isAnnouncingScanningPrompt = false;
      });
    }
  }

  void _handleScanKeyPress() {
    if (_scanningIndex == null || _currentOptions.isEmpty) return;
    if (_scanningIndex! >= _currentOptions.length) return;
    _handleOptionSelected(_currentOptions[_scanningIndex!]);
  }

  Future<void> _resumeScanning() async {
    if (!mounted) return;
    setState(() {
      _waitingForUserInput = false;
      _currentScanCycle = 0;
      _suppressScanning = false;
    });
    _startAuditoryScanning();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  String _getHeaderText() {
    final contact = _selectedContact ?? '';
    if (_screen == _TextScreen.contactPicker) return 'Text: Choose a contact';
    if (_screen == _TextScreen.modeMenu) return 'Text $contact: Choose topic';
    if (_screen == _TextScreen.recentTextVoice) {
      return 'Text $contact: Read incoming text';
    }
    if (_screen == _TextScreen.llmOptions) {
      return 'Text $contact: Choose your message';
    }
    if (_screen == _TextScreen.postSelection) {
      return "Text $contact: What's next?";
    }
    return 'Text $contact: Message sent';
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode!,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          if (_waitingForInitialSwitch) {
            setState(() {
              _waitingForInitialSwitch = false;
            });
            _startAuditoryScanning();
            return;
          }
          if (_waitingForUserInput) {
            _resumeScanning();
          } else if (_isScanning && _scanningIndex != null) {
            _handleScanKeyPress();
          }
        } else if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          final settingsProvider =
              Provider.of<UserSettingsProvider>(context, listen: false);
          final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
          if (scanMode == 'step' &&
              _isScanning &&
              _isAnnouncingScanningPrompt) {
            _flutterTts.stop();
            if (mounted) {
              setState(() {
                _isAnnouncingScanningPrompt = false;
              });
            }
          }
          if (scanMode == 'step' && _isScanning && _scanningIndex != null) {
            _scanNextButton();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _getHeaderText(),
            style: const TextStyle(fontSize: 16),
          ),
          backgroundColor: const Color(0xFF002244),
          foregroundColor: const Color(0xFFFB4F14),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: Icon(
                _isAdminToolbarLocked ? Icons.lock : Icons.lock_open,
                size: 18,
                color: Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  _isAdminToolbarLocked = !_isAdminToolbarLocked;
                });
              },
              tooltip: _isAdminToolbarLocked
                  ? 'Unlock Admin Toolbar'
                  : 'Lock Admin Toolbar',
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Conversation history
                if (_conversationLines.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Text History:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _conversationLines = [];
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red.shade700,
                                elevation: 2,
                                shadowColor:
                                    Colors.red.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                      color: Colors.red.shade100),
                                ),
                              ),
                              child: const Text('Clear'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _showTextCopyModal,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.green.shade700,
                                elevation: 2,
                                shadowColor:
                                    Colors.green.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                      color: Colors.green.shade100),
                                ),
                              ),
                              child: const Text('Copy'),
                            ),
                          ],
                        ),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 130),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _conversationLines.length,
                            itemBuilder: (ctx, i) {
                              final raw = _conversationLines[i];
                              final text = raw.startsWith('Me: ')
                                  ? raw.substring(4)
                                  : raw;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    const SizedBox(width: 60),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF007AFF),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          text,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // Listening indicator section (matches GamesPage layout exactly)
                if (_screen == _TextScreen.recentTextVoice)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        if (_ownListening)
                          Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.mic,
                                        color: Colors.red, size: 24),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
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
                                          Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.blue.shade400, width: 2),
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
                                      _lastPartnerTranscript.isEmpty
                                          ? '(waiting...)'
                                          : '"$_lastPartnerTranscript"',
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
                        if (!_ownListening)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              _recentTextVoiceStatusText(),
                              style: const TextStyle(
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

                // Options grid
                Expanded(
                  child: _screen == _TextScreen.recentTextVoice
                      ? _buildRecentTextVoiceGoBack()
                      : _buildOptionsGrid(),
                ),

              ],
            ),

            // Loading overlay
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.54),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  String _recentTextVoiceStatusText() => _recentTextStatusMessage;

  Widget _buildRecentTextVoiceGoBack() {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          _stopOwnListening(restoreWakeWord: false);
          _handleGoBack();
        },
        child: const Text('Go Back'),
      ),
    );
  }

  Widget _buildOptionsGrid() {
    if (_currentOptions.isEmpty) {
      return const Center(
        child: Text('Loading...', style: TextStyle(color: Colors.grey)),
      );
    }

    return Consumer<UserSettingsProvider>(
      builder: (context, settingsProvider, child) {
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

        final darkColor =
            userSettings?.darkColor ?? const Color(0xFF002244);
        final lightColor =
            userSettings?.lightColor ?? const Color(0xFFFB4F14);

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
              final isHighlighted =
                  _isScanning && _scanningIndex == index;
              final fontSize =
                  ((buttonSizePx / 10) * 1.44).clamp(14.4, 25.9);

              return Padding(
                padding: const EdgeInsets.all(2.0),
                child: SizedBox(
                  width: buttonSizePx,
                  height: buttonSizePx,
                  child: SpeechBubbleButton(
                    label: option['label'] as String? ?? '',
                    onPressed: () => _handleOptionSelected(option),
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
