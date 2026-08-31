import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:permission_handler/permission_handler.dart';

class WakeWordService {
  List<String> wakeWords;

  static String _wakeWordLocale = 'en-US';

  /// The group wake word shared across all devices in a room.
  /// Defaults to 'hey friends'. Set this at app init via [setGroupWakeWord].
  /// When backend support is added, load the value from UserSettings and call [setGroupWakeWord].
  static String _groupWakeWord = 'hey friends';

  /// Update the group wake word from settings. Call this after loading UserSettings.
  static void setGroupWakeWord(String phrase) {
    final normalized = phrase.trim().toLowerCase();
    _groupWakeWord = normalized.isEmpty ? 'hey friends' : normalized;
    debugPrint('[WakeWordService] Group wake word set to: "$_groupWakeWord"');
  }

  /// Update the wake words on the current instance. Call this when a user
  /// with different wake word settings reuses an already-running instance.
  static void updateWakeWords(List<String> words) {
    if (_currentInstance == null) return;
    _currentInstance!.wakeWords = List<String>.from(words);
    debugPrint('[WakeWordService] Wake words updated to: $words');
  }

  /// Update the locale used during wake-word listening.
  /// Example values: 'en-US', 'es-US', 'es-ES'.
  static void setWakeWordLocale(String locale) {
    final normalized = locale.trim();
    _wakeWordLocale = normalized.isEmpty ? 'en-US' : normalized;
    debugPrint('[WakeWordService] Wake-word locale set to: "$_wakeWordLocale"');
  }

  static bool wakeWordShouldBeActive = true;
  static WakeWordService?
  _currentInstance; // Static reference to current instance

  // Static flag to completely disable all WakeWordService callbacks during interviews
  static bool _callbacksDisabled = false;

  // Getter for current instance
  static WakeWordService? getCurrentInstance() => _currentInstance;

  // Static flag to handle wake word detected on freestyle page
  static String? pendingWakeWordFromFreestyle;

  // Future enhancement: Flag to use native iOS speech recognition for better accuracy
  // static bool useNativeiOSSpeech = false; // Disabled for now - would require extensive changes

  // Callback hooks
  void Function(String transcript)? onWakeWord;
  void Function(String question)? onQuestion;
  bool Function()? shouldAllowWakeWordRestart;

  /// Callback for announcing messages to the user (e.g., via TTS or backend)
  void Function(String message)? onAnnounce;

  /// Callback for simple TTS announcements (like "Listening") that should bypass complex audio routing
  void Function(String message)? onSimpleTTS;

  /// Optional callback to control question box highlighting in the UI
  void Function(bool highlight)? onQuestionHighlight;

  /// Callback for timeout events (when question listening times out)
  void Function()? onTimeout;

  /// Callback for updating the status bar with what the app is hearing during WAKE WORD detection
  void Function(String heardText)? onStatusBarUpdate;

  /// Callback for updating the status bar during QUESTION listening (separate from wake word)
  void Function(String questionText)? onQuestionStatusUpdate;

  /// Callback for when first speech is detected during question listening
  void Function()? onFirstSpeechDetected;

  void setWakeWordDetected(bool detected) {
    _wakeWordDetected = detected;
    debugPrint('[WakeWordService] setWakeWordDetected: $_wakeWordDetected');
  }

  void setProcessingWakeWord(bool processing) {
    _processingWakeWord = processing;
    debugPrint('[WakeWordService] setProcessingWakeWord: $_processingWakeWord');
  }

  // POC-STYLE: Single speech recognizer to avoid dual-recognizer interference
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _isWakeWordListening = false;
  bool _isQuestionListening = false;

  bool _wakeWordDetected = false;
  bool _processingWakeWord =
      false; // Flag to prevent interference during wake word processing
  bool _hasDetectedFirstSpeech =
      false; // Track if we've detected first speech in current question session
  bool _hasProcessedResult =
      false; // Track if we've already processed a result to prevent duplicates

  int _globalSessionId = 0;
  int _currentSessionId = 0;

  Timer? _questionTimeoutTimer;
  Timer? _initialTimeoutTimer; // Initial no-speech timeout
  Timer? _silenceTimer; // Post-speech silence detection
  String _lastPartialQuestion = '';

  // Question-capture timing tuned for Bluetooth/iOS stability.
  static const Duration _questionStartHandoffDelay = Duration(milliseconds: 50);
  // Timer 1 (pre-speech): if no words are heard at all, timeout after 10s.
  static const Duration _questionInitialTimeoutDuration = Duration(seconds: 10);
  static const Duration _questionHardTimeoutDuration = Duration(seconds: 30);
  // Timer 2 (post-speech): once speech has started, 3s of consecutive silence means done.
  static const Duration _questionSilenceTimeoutDuration = Duration(seconds: 3);
  static const Duration _questionListenForDuration = Duration(seconds: 45);
  // Keep recognizer pauseFor longer than the post-speech silence timer so our
  // explicit silence timer controls completion behavior.
  static const Duration _questionPauseForDuration = Duration(seconds: 10);

  Completer<void>? _stopCompleter;

  bool _shouldRestartWakeWordListening = true;
  Timer? _restartDebounceTimer; // Prevent multiple rapid restarts
  DateTime? _lastPermissionCheckAt;
  bool _lastPermissionCheckResult = false;

  WakeWordService({required this.wakeWords}) {
    _currentInstance = this; // Set the static reference to this instance
  }

  String _normalizeWakeText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _containsWakeWord(String transcript) {
    final normalizedTranscript = _normalizeWakeText(transcript);
    if (normalizedTranscript.isEmpty) return false;

    final configuredWakeWords = wakeWords
        .map((word) => _normalizeWakeText(word))
        .where((word) => word.isNotEmpty)
        .toSet();

    // Build group wake word variants (e.g. 'hey friends' and 'hey friend')
    final groupWord = _normalizeWakeText(_groupWakeWord);
    final groupVariants = <String>{
      if (groupWord.isNotEmpty) groupWord,
      // Singular variant: strip trailing 's' if it ends with 'friends'
      if (groupWord.endsWith('friends'))
        groupWord.substring(0, groupWord.length - 1),
    };

    final allWakeWords = <String>{...configuredWakeWords, ...groupVariants};

    return allWakeWords.any(
      (wakeWord) => normalizedTranscript.contains(wakeWord),
    );
  }

  /// Static method to restart the current instance's wake word service
  static Future<void> restartWakeWordService() async {
    if (_currentInstance != null) {
      debugPrint('[WakeWordService] Static restart called');
      _currentInstance!.resumeWakeWordAutoRestart();
      await _currentInstance!.startWakeWordListening();
    } else {
      debugPrint(
        '[WakeWordService] Static restart called but no current instance',
      );
    }
  }

  /// Static method to pause the current instance's wake word auto restart
  static void pauseWakeWordService() {
    if (_currentInstance != null) {
      debugPrint('[WakeWordService] Static pause called');
      _currentInstance!.pauseWakeWordAutoRestart();
    } else {
      debugPrint(
        '[WakeWordService] Static pause called but no current instance',
      );
    }
  }

  /// Static method to disable all callbacks during interviews
  static void disableCallbacks() {
    debugPrint(
      '[WakeWordService] DISABLING ALL CALLBACKS for interview isolation',
    );
    _callbacksDisabled = true;
  }

  /// Static method to re-enable callbacks after interviews
  static void enableCallbacks() {
    debugPrint('[WakeWordService] ENABLING CALLBACKS after interview');
    _callbacksDisabled = false;
  }

  /// Static method to resume the current instance's wake word auto restart
  static Future<void> resumeWakeWordService() async {
    if (_currentInstance != null) {
      debugPrint(
        '[WakeWordService] Static resume called - re-enabling auto-restart',
      );
      _currentInstance!.resumeWakeWordAutoRestart();
      // Don't force start—let auto-restart mechanism handle it naturally
      // to avoid conflict with scanning state checks
    } else {
      debugPrint(
        '[WakeWordService] Static resume called but no current instance',
      );
    }
  }

  /// Static method to force complete reset of the wake word service session
  /// This breaks out of any corrupted session state and resets all flags
  static Future<void> forceStopAndReset() async {
    if (_currentInstance != null) {
      debugPrint('[WakeWordService] Static force reset called');
      try {
        // Stop the single recognizer
        await _currentInstance!.stopAllRecognizers();

        // Reset all session state flags
        _currentInstance!._processingWakeWord = false;
        _currentInstance!._shouldRestartWakeWordListening = true;
        _currentInstance!._wakeWordDetected = false;
        _currentInstance!._isListening = false;
        _currentInstance!._isWakeWordListening = false;
        _currentInstance!._isQuestionListening = false;

        // Increment session ID to break any old session references
        _currentInstance!._globalSessionId += 10;
        _currentInstance!._currentSessionId =
            _currentInstance!._globalSessionId;

        // Reset global flag
        wakeWordShouldBeActive = true;

        debugPrint(
          '[WakeWordService] Force reset completed - session state cleared',
        );
      } catch (e) {
        debugPrint('[WakeWordService] Error during force reset: $e');
      }
    } else {
      debugPrint(
        '[WakeWordService] Static force reset called but no current instance',
      );
    }
  }

  /// Static method to gently stop speech recognition without resetting wake word state
  /// This is for preventing interference during TTS announcements
  static Future<void> pauseSpeechRecognition() async {
    if (_currentInstance != null) {
      debugPrint(
        '[WakeWordService] Pausing speech recognition to prevent TTS interference',
      );
      try {
        await _currentInstance!._speech.stop();
        debugPrint('[WakeWordService] Speech recognition paused successfully');
      } catch (e) {
        debugPrint('[WakeWordService] Error pausing speech recognition: $e');
      }
    } else {
      debugPrint(
        '[WakeWordService] Pause speech recognition called but no current instance',
      );
    }
  }

  // Static method to set callbacks on the current instance
  static void setCallbacks({
    required Function(String) onWakeWord,
    required Function(String) onQuestion,
    required Function(String) onAnnounce,
    Function(String)?
    onSimpleTTS, // Optional simple TTS for "Listening" announcements
    required Function(bool) onQuestionHighlight,
    required Function() onTimeout,
    required Function(String) onStatusBarUpdate,
    required bool Function() shouldAllowWakeWordRestart,
  }) {
    print('🟢 WakeWordService - Setting callbacks on current instance');

    if (_currentInstance != null) {
      _currentInstance!.onWakeWord = onWakeWord;
      _currentInstance!.onQuestion = onQuestion;
      _currentInstance!.onAnnounce = onAnnounce;
      _currentInstance!.onSimpleTTS = onSimpleTTS;
      _currentInstance!.onQuestionHighlight = onQuestionHighlight;
      _currentInstance!.onTimeout = onTimeout;
      _currentInstance!.onStatusBarUpdate = onStatusBarUpdate;
      _currentInstance!.shouldAllowWakeWordRestart = shouldAllowWakeWordRestart;

      print('🟢 WakeWordService - Callbacks updated successfully');
    } else {
      print(
        '🔴 WakeWordService - No current instance available to set callbacks',
      );
    }
  }

  // Static method to start question listening on current instance
  static Future<void> startQuestionListeningStatic() async {
    if (_currentInstance != null) {
      await _currentInstance!.startQuestionListening();
    }
  }

  // Static method to start question listening directly for "Please Repeat" button
  // This bypasses the wake word detection requirement
  static Future<void> startQuestionListeningForRepeat() async {
    if (_currentInstance != null) {
      print(
        '🟢 WakeWordService - Starting question listening for Please Repeat button',
      );

      // First, stop any existing wake word listening to prevent conflicts
      print(
        '🟢 WakeWordService - Stopping wake word listening before starting question listening',
      );
      _currentInstance!.pauseWakeWordAutoRestart();
      await _currentInstance!.stopWakeWordListening();

      // Very brief wait for the stop to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Set wake word detected state to allow question listening
      _currentInstance!._wakeWordDetected = true;
      _currentInstance!._processingWakeWord =
          false; // Ensure we're not blocking

      // Now start question listening
      await _currentInstance!.startQuestionListening();
      print(
        '🟢 WakeWordService - Question listening started for repeat button',
      );
    } else {
      print(
        '🔴 WakeWordService - No current instance available for repeat question listening',
      );
    }
  }

  /// Check and request microphone permission
  Future<bool> _checkMicrophonePermission() async {
    debugPrint('[WakeWordService] Checking microphone permission...');

    // On iOS, use native permission checking which is more reliable
    if (!kIsWeb && Platform.isIOS) {
      try {
        const platform = MethodChannel('audio_routing');
        final String? nativeStatus = await platform.invokeMethod(
          'checkMicrophonePermission',
        );
        debugPrint(
          '[WakeWordService] Native iOS microphone permission: $nativeStatus',
        );

        if (nativeStatus == 'granted') {
          debugPrint(
            '[WakeWordService] Native iOS microphone permission already granted',
          );
          return true;
        } else if (nativeStatus == 'undetermined') {
          debugPrint(
            '[WakeWordService] Requesting microphone permission through native iOS...',
          );
          final String? requestResult = await platform.invokeMethod(
            'requestMicrophonePermission',
          );
          debugPrint(
            '[WakeWordService] Native iOS permission request result: $requestResult',
          );

          if (requestResult == 'granted') {
            debugPrint(
              '[WakeWordService] Native iOS microphone permission granted after request',
            );
            return true;
          } else {
            debugPrint(
              '[WakeWordService] Native iOS microphone permission denied by user',
            );
            return false;
          }
        } else {
          debugPrint(
            '[WakeWordService] Native iOS microphone permission denied',
          );
          return false;
        }
      } catch (e) {
        debugPrint(
          '[WakeWordService] Error with native iOS permission check: $e',
        );
        // Fall back to Flutter permission handler
      }
    }

    // Fallback to Flutter permission handler for non-iOS or if native check failed
    final permission = Permission.microphone;
    final status = await permission.status;

    debugPrint(
      '[WakeWordService] Current microphone permission status (Flutter): $status',
    );

    if (status.isGranted) {
      debugPrint(
        '[WakeWordService] Microphone permission already granted (Flutter)',
      );
      return true;
    }

    if (status.isDenied) {
      debugPrint(
        '[WakeWordService] Requesting microphone permission (Flutter)...',
      );
      final result = await permission.request();
      debugPrint(
        '[WakeWordService] Microphone permission request result (Flutter): $result',
      );

      if (result.isGranted) {
        debugPrint(
          '[WakeWordService] Microphone permission granted after request (Flutter)',
        );
        return true;
      } else {
        debugPrint(
          '[WakeWordService] Microphone permission denied by user (Flutter)',
        );
        // Note: Permission announcement removed since iOS workaround handles permissions automatically
        return false;
      }
    }

    if (status.isPermanentlyDenied) {
      debugPrint(
        '[WakeWordService] Microphone permission permanently denied (Flutter)',
      );
      // Note: Permission announcement removed since iOS workaround handles permissions automatically
      return false;
    }

    debugPrint('[WakeWordService] Unexpected permission status: $status');
    return false;
  }

  /// Robust stop: returns when recognizer is fully stopped.
  Future<void> stopWakeWordListening() async {
    debugPrint('[WakeWordService] stopWakeWordListening called');
    debugPrint(
      "[WakeWordService] Before _isListening: $_isListening, _isWakeWordListening: $_isWakeWordListening",
    );
    if (!_isListening && !_isWakeWordListening) return;
    _isListening = false;
    _isWakeWordListening = false;
    _stopCompleter = Completer<void>();
    await _speech.stop();
    await _stopCompleter!
        .future; // Only completes in onStatus when status == 'done'
    debugPrint(
      "[WakeWordService] After _isListening: $_isListening, _isWakeWordListening: $_isWakeWordListening",
    );
    // Wait for onStatus: done or timeout
    return _stopCompleter!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        debugPrint('[WakeWordService] stopWakeWordListening: timeout');
        if (!_stopCompleter!.isCompleted) _stopCompleter!.complete();
      },
    );
  }

  /// Start listening for the wake word, only after previous session is stopped.
  Future<void> startWakeWordListening() async {
    await _startWakeWordListeningInternal(fastRestart: false);
  }

  /// Fast restart path used after session end/errors to minimize downtime.
  Future<void> startWakeWordListeningFast() async {
    await _startWakeWordListeningInternal(fastRestart: true);
  }

  Future<void> _startWakeWordListeningInternal({
    required bool fastRestart,
  }) async {
    debugPrint(
      '[WakeWordService] startWakeWordListening called (fastRestart=$fastRestart)',
    );
    if (!wakeWordShouldBeActive) {
      debugPrint(
        '[WakeWordService] startWakeWordListening: ABORTED (shouldBeActive is false)',
      );
      return;
    }

    // Check if restart is allowed before proceeding (prevents conflict during scanning)
    if (shouldAllowWakeWordRestart != null &&
        !(shouldAllowWakeWordRestart!.call())) {
      debugPrint(
        '[WakeWordService] startWakeWordListening: ABORTED (shouldAllowWakeWordRestart returned false - likely scanning)',
      );
      return;
    }

    // On iOS, try to start speech recognition even if permission_handler reports denied
    // because iOS Settings permission might be granted but Flutter plugin detection is unreliable
    // Cache permission checks to avoid expensive checks on every auto-restart.
    final now = DateTime.now();
    final shouldRefreshPermission =
        _lastPermissionCheckAt == null ||
        now.difference(_lastPermissionCheckAt!) > const Duration(seconds: 60);
    bool hasPermission;
    if (shouldRefreshPermission) {
      hasPermission = await _checkMicrophonePermission();
      _lastPermissionCheckResult = hasPermission;
      _lastPermissionCheckAt = now;
      debugPrint(
        '[WakeWordService] Refreshed microphone permission cache: $hasPermission',
      );
    } else {
      hasPermission = _lastPermissionCheckResult;
      debugPrint(
        '[WakeWordService] Using cached microphone permission: $hasPermission',
      );
    }
    if (!hasPermission) {
      debugPrint(
        '[WakeWordService] startWakeWordListening: permission_handler reports denied, but trying speech recognition anyway (iOS bug workaround)',
      );
      // Continue anyway - let speech recognition itself fail if permission truly not granted
    }

    // Wait for any previous stop to finish. Keep auto-restart path lean.
    if (_isListening || _isWakeWordListening) {
      if (fastRestart) {
        debugPrint(
          '[WakeWordService] Fast restart skipped because listener is already active',
        );
        return;
      }
      await stopWakeWordListening();
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // Clear any accumulated speech recognition state only on full starts.
    if (!fastRestart) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 80));
    }

    _globalSessionId++;
    _currentSessionId = _globalSessionId;
    _isListening = true;
    _isWakeWordListening = true;
    _isQuestionListening = false;

    // Clear the status bar display when starting a new session
    if (onStatusBarUpdate != null) {
      onStatusBarUpdate!(''); // Clear the previous text
    }

    debugPrint(
      'Starting wake word listening. sessionId=$_currentSessionId.  Processing: $_processingWakeWord',
    );
    // Only reset _wakeWordDetected if we're not currently processing a wake word
    if (!_processingWakeWord) {
      _wakeWordDetected = false;
      debugPrint(
        'Starting wake word listening. sessionId=$_currentSessionId.  wakeWordDetected set to false',
      );
    } else {
      debugPrint(
        'Starting wake word listening. sessionId=$_currentSessionId.  PRESERVING wakeWordDetected=true during processing',
      );
    }

    try {
      // Capture return value — false means speech recognition is unavailable
      // (e.g., permission denied, audio session conflict, or device limitation).
      final available = await _speech.initialize(
        onStatus: (status) => _onStatus(status, _currentSessionId),
        onError: (error) => _onError(error, _currentSessionId),
      );

      if (!available) {
        debugPrint(
          '[WakeWordService] _speech.initialize() returned false — speech recognition unavailable. Scheduling retry in 3s.',
        );
        _isListening = false;
        _isWakeWordListening = false;
        if (_shouldRestartWakeWordListening && wakeWordShouldBeActive) {
          _restartDebounceTimer?.cancel();
          _restartDebounceTimer = Timer(const Duration(seconds: 3), () {
            _restartDebounceTimer = null;
            if (_shouldRestartWakeWordListening &&
                wakeWordShouldBeActive &&
                !_isListening) {
              debugPrint(
                '[WakeWordService] Retrying after initialize() failure',
              );
              startWakeWordListeningFast();
            }
          });
        }
        return;
      }

      // Listen using configured locale so non-English users can still trigger wake words.
      const pauseForDuration = Duration(seconds: 60);
      debugPrint(
        '[WakeWordService] Starting listen with pauseFor=60s, localeId=$_wakeWordLocale',
      );

      await _speech.listen(
        onResult: (result) => _onResult(result, _currentSessionId),
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: false,
        listenFor: const Duration(minutes: 10),
        pauseFor: pauseForDuration,
        localeId: _wakeWordLocale,
      );
      debugPrint(
        '[WakeWordService] Wake word listening started. sessionId=$_currentSessionId',
      );
    } catch (e) {
      debugPrint(
        '[WakeWordService] startWakeWordListening failed (fastRestart=$fastRestart): $e',
      );
      if (fastRestart) {
        debugPrint(
          '[WakeWordService] Fast restart failed, retrying with full restart path',
        );
        await _startWakeWordListeningInternal(fastRestart: false);
      }
    }
  }

  Future<void> stopAllRecognizers() async {
    await stopWakeWordListening();
    debugPrint(
      '[WakeWordService] stopAllRecognizers called. Stopping single speech recognizer.',
    );
    _questionTimeoutTimer?.cancel();
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    _lastPartialQuestion = '';
    _isQuestionListening = false;
    _stopCompleter = Completer<void>();
    debugPrint('[WakeWordService] Before _speech.stop()');
    await _speech.stop();
    debugPrint('[WakeWordService] After _speech.stop()');
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();
      debugPrint(
        '[WakeWordService] stopAllRecognizers: _stopCompleter completed',
      );
    } else {
      debugPrint(
        '[WakeWordService] stopAllRecognizers: _stopCompleter was already completed',
      );
    }
    debugPrint('[WakeWordService] All recognizers stopped.');
  }

  void _onStatus(String status, int sessionId) {
    debugPrint(
      '[WakeWordService] onStatus callback. sessionId=$sessionId, currentSessionId=$_currentSessionId, status=$status, isWakeWordListening=$_isWakeWordListening, isQuestionListening=$_isQuestionListening',
    );

    // Check if callbacks are disabled (during interviews)
    if (_callbacksDisabled) {
      debugPrint(
        '[WakeWordService] onStatus callback: IGNORING - callbacks disabled during interview',
      );
      return;
    }

    if (sessionId != _currentSessionId) {
      debugPrint(
        '[WakeWordService] onStatus callback: ignoring stale sessionId=$sessionId',
      );
      return;
    }
    if (status == 'done' || status == 'notListening') {
      _isListening = false;

      if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
        _stopCompleter!.complete();
      }

      // Clear the status bar when the session ends
      if (onStatusBarUpdate != null) {
        onStatusBarUpdate!(''); // Clear the display
      }

      // Handle wake word listening completion
      if (_isWakeWordListening) {
        _isWakeWordListening = false;
        debugPrint(
          '[WakeWordService] Wake word session ended. wakeWordShouldBeActive=$wakeWordShouldBeActive, _shouldRestartWakeWordListening=$_shouldRestartWakeWordListening, _processingWakeWord=$_processingWakeWord',
        );

        // Check if restart is actually allowed before attempting
        final restartAllowed =
            wakeWordShouldBeActive &&
            _shouldRestartWakeWordListening &&
            !_processingWakeWord &&
            (shouldAllowWakeWordRestart?.call() ?? true);
        debugPrint(
          '[WakeWordService] Auto-restart check: allowed=$restartAllowed',
        );

        if (restartAllowed) {
          debugPrint(
            '[WakeWordService] Auto-restarting wake word listening after session end',
          );
          // Cancel any existing restart timer to prevent multiple restarts
          _restartDebounceTimer?.cancel();

          final debounceMs = 250;
          debugPrint(
            '[WakeWordService] Auto-restart debounce delay: ${debounceMs}ms',
          );

          _restartDebounceTimer = Timer(Duration(milliseconds: debounceMs), () {
            // Double-check conditions before restarting
            final stillAllowed =
                wakeWordShouldBeActive &&
                _shouldRestartWakeWordListening &&
                !_processingWakeWord &&
                (shouldAllowWakeWordRestart?.call() ?? true);
            if (!_isListening &&
                !_isWakeWordListening &&
                !_isQuestionListening &&
                stillAllowed) {
              debugPrint(
                '[WakeWordService] Executing delayed auto-restart after session end (debounce=$debounceMs ms)',
              );
              startWakeWordListeningFast();
            } else {
              debugPrint(
                '[WakeWordService] Delayed auto-restart cancelled: _isListening=$_isListening, _isWakeWordListening=$_isWakeWordListening, _isQuestionListening=$_isQuestionListening, stillAllowed=$stillAllowed',
              );
            }
            _restartDebounceTimer = null; // Clear the timer reference
          });
        } else {
          debugPrint(
            '[WakeWordService] Auto-restart not allowed: wakeWordShouldBeActive=$wakeWordShouldBeActive, _shouldRestartWakeWordListening=$_shouldRestartWakeWordListening, _processingWakeWord=$_processingWakeWord, callback=${shouldAllowWakeWordRestart?.call()}',
          );
        }
      }

      // Handle question listening completion
      if (_isQuestionListening) {
        _isQuestionListening = false;
        debugPrint(
          '[WakeWordService] Question listening session ended. Resetting wakeWordDetected to false.',
        );
        _wakeWordDetected = false;
        _questionTimeoutTimer?.cancel();
        _initialTimeoutTimer?.cancel();
        _silenceTimer?.cancel();

        // Remove highlight from question box if UI callback is provided
        onQuestionHighlight?.call(false);

        // If no result was processed during question listening, announce timeout
        if (_lastPartialQuestion.isEmpty && !_hasProcessedResult) {
          debugPrint(
            '[WakeWordService] Question session ended with no input, announcing timeout',
          );
          _hasProcessedResult = true;
          onAnnounce?.call("I didn't hear anything. Try again?");
          onTimeout?.call();
        }

        // Restart wake word listening
        resumeWakeWordAutoRestart();
      }
    }
  }

  // Add stack trace debugging to pauseWakeWordAutoRestart to see what's calling it
  void pauseWakeWordAutoRestart() {
    _shouldRestartWakeWordListening = false;
    debugPrint(
      '[WakeWordService] pauseWakeWordAutoRestart: _shouldRestartWakeWordListening=$_shouldRestartWakeWordListening',
    );

    // DEBUGGING: Print stack trace to see what called this method
    debugPrint('[WakeWordService] pauseWakeWordAutoRestart CALLED FROM:');
    debugPrint(StackTrace.current.toString());
  }

  // Add stack trace debugging to resumeWakeWordAutoRestart to see when it's called
  void resumeWakeWordAutoRestart() {
    _shouldRestartWakeWordListening = true;
    debugPrint(
      '[WakeWordService] resumeWakeWordAutoRestart: _shouldRestartWakeWordListening=$_shouldRestartWakeWordListening',
    );

    // DEBUGGING: Print stack trace to see what called this method
    debugPrint('[WakeWordService] resumeWakeWordAutoRestart CALLED FROM:');
    debugPrint(StackTrace.current.toString());

    // Do not force an immediate restart here.
    // Callers that need a restart should explicitly invoke startWakeWordListening().
  }

  // FIX: Use dynamic for error type to avoid build errors
  void _onError(dynamic error, int sessionId) {
    debugPrint(
      '[WakeWordService] onError callback. sessionId=$sessionId, currentSessionId=$_currentSessionId, error=$error',
    );

    // Check if callbacks are disabled (during interviews)
    if (_callbacksDisabled) {
      debugPrint(
        '[WakeWordService] onError callback: IGNORING - callbacks disabled during interview',
      );
      return;
    }

    if (sessionId != _currentSessionId) {
      debugPrint(
        '[WakeWordService] onError callback: ignoring stale sessionId=$sessionId',
      );
      return;
    }
    _isListening = false;
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();
    }

    // Clear the status bar when there's an error
    if (onStatusBarUpdate != null) {
      onStatusBarUpdate!(''); // Clear the display
    }

    // Check if restart is actually allowed before attempting
    final restartAllowed =
        wakeWordShouldBeActive &&
        _shouldRestartWakeWordListening &&
        !_processingWakeWord &&
        (shouldAllowWakeWordRestart?.call() ?? true);
    debugPrint(
      '[WakeWordService] Error auto-restart check: allowed=$restartAllowed, error=${error.errorMsg}',
    );

    if (restartAllowed) {
      debugPrint(
        '[WakeWordService] Auto-restarting wake word listening after error',
      );
      // Cancel any existing restart timer to prevent multiple restarts
      _restartDebounceTimer?.cancel();

      final debounceMs = 250;
      debugPrint(
        '[WakeWordService] Error auto-restart debounce delay: ${debounceMs}ms',
      );

      _restartDebounceTimer = Timer(Duration(milliseconds: debounceMs), () {
        // Double-check conditions before restarting
        final stillAllowed =
            wakeWordShouldBeActive &&
            _shouldRestartWakeWordListening &&
            !_processingWakeWord &&
            (shouldAllowWakeWordRestart?.call() ?? true);
        if (!_isListening && stillAllowed) {
          debugPrint(
            '[WakeWordService] Executing delayed auto-restart after error (debounce=$debounceMs ms)',
          );
          startWakeWordListeningFast();
        } else {
          debugPrint(
            '[WakeWordService] Delayed auto-restart after error cancelled: _isListening=$_isListening, stillAllowed=$stillAllowed',
          );
        }
        _restartDebounceTimer = null; // Clear the timer reference
      });
    } else {
      debugPrint(
        '[WakeWordService] Auto-restart after error not allowed: wakeWordShouldBeActive=$wakeWordShouldBeActive, _shouldRestartWakeWordListening=$_shouldRestartWakeWordListening, _processingWakeWord=$_processingWakeWord, callback=${shouldAllowWakeWordRestart?.call()}',
      );
    }
  }

  void _onResult(SpeechRecognitionResult result, int sessionId) {
    if (sessionId != _currentSessionId) return;
    debugPrint(
      '[WakeWordService] onResult callback. sessionId=$sessionId, currentSessionId=$_currentSessionId, _wakeWordDetected=$_wakeWordDetected  result=$result ',
    );
    if (_wakeWordDetected) return;
    final transcript = result.recognizedWords.toLowerCase();

    // Update status bar with what we're hearing during wake word detection
    if (onStatusBarUpdate != null && transcript.isNotEmpty) {
      onStatusBarUpdate!(transcript);
    }

    if (!_wakeWordDetected && _containsWakeWord(transcript)) {
      debugPrint('Setting _wakeWordDetected to true for sessionId=$sessionId');
      _wakeWordDetected = true;
      _processingWakeWord = true; // Protect this state during processing
      debugPrint('[WakeWordService] Wake word detected: $transcript');
      // Stop listening immediately to prevent further wake word detection
      _isListening = false;
      _questionTimeoutTimer?.cancel(); // Cancel any pending question timeout
      //_stopCompleter?.complete(); // Complete the stop completer if waiting
      debugPrint(
        '[WakeWordService] Stopping wake word listening after detection.',
      );
      pauseWakeWordAutoRestart(); // Prevent auto-restart until we handle the question
      stopWakeWordListening(); // <-- await if possible, or just call it
      debugPrint(
        '[WakeWordService] Wake word listening stopped. Firing onWakeWord callback',
      );
      onWakeWord?.call(transcript);
    }
  }

  Future<void> startQuestionListening({
    int retryCount = 0,
    String localeId = 'en-US',
  }) async {
    debugPrint(
      '[QuestionService] Starting POC-STYLE question listening. _wakeWordDetected: $_wakeWordDetected, _processingWakeWord: $_processingWakeWord, retryCount: $retryCount',
    );

    if (!_wakeWordDetected) {
      debugPrint(
        '[QuestionService] ERROR: Attempted to start question listening when _wakeWordDetected is false! Stopping here.',
      );
      debugPrint(
        '[QuestionService] This is likely a race condition. The wake word session may have ended before this method was called.',
      );
      // Don't proceed if wake word wasn't detected
      return;
    }

    // Add a small delay to allow previous wake word session to fully complete
    debugPrint(
      '[QuestionService] Adding delay to prevent race condition with previous session...',
    );
    await Future.delayed(_questionStartHandoffDelay);

    // Double-check the flag after delay in case it was reset by a race condition
    if (!_wakeWordDetected) {
      debugPrint(
        '[QuestionService] ERROR: _wakeWordDetected was reset during delay! Race condition detected, aborting.',
      );
      return;
    }

    // Set a flag to indicate we're starting question listening to prevent race conditions
    final questionSessionId =
        _globalSessionId + 1000; // Use a different range for question sessions
    debugPrint(
      '[QuestionService] Starting question session with ID: $questionSessionId',
    );

    // Clear the processing flag since we're now starting question listening
    _processingWakeWord = false;
    // Reset session state flags for new question session
    _hasDetectedFirstSpeech = false;
    _hasProcessedResult = false; // Reset to prevent duplicate processing

    // Set states for question listening mode
    _isListening = true;
    _isWakeWordListening = false;
    _isQuestionListening = true;
    _lastPartialQuestion = '';

    // POC-STYLE: Skip permission check for faster setup - we already checked during wake word
    debugPrint(
      '[QuestionService] POC-STYLE: Skipping permission check for faster setup...',
    );

    // POC-STYLE: Ultra-minimal stop delay like POC
    debugPrint(
      '[QuestionService] POC-STYLE: Ultra-minimal stop before question listening...',
    );
    final stopStart = DateTime.now().millisecondsSinceEpoch;
    await _speech.stop();

    // POC uses ultra-minimal delay for fastest setup
    await Future.delayed(
      const Duration(milliseconds: 25),
    ); // Reduced from 50ms to 25ms for speed
    final stopEnd = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[TIMER] POC-style stop completed in ${stopEnd - stopStart}ms');

    debugPrint(
      '[QuestionService] POC-STYLE: Initializing speech-to-text for question listening... (retryCount: $retryCount)',
    );

    bool _hasRetried = false;

    final initStart = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[TIMER] Question speech initialize START at $initStart');

    // POC-STYLE: Ultra-fast initialization matching POC exactly
    bool available = await _speech.initialize(
      onStatus: (status) {
        debugPrint(
          '[QuestionService] Speech status (question) sessionId=$questionSessionId: $status',
        );
        if (status == 'done') {
          debugPrint(
            '[QuestionService] Question recognizer done (sessionId=$questionSessionId). Checking if this is our active session...',
          );

          // Only handle this callback if it's from our question session
          // Ignore status callbacks from previous wake word sessions
          if (_isQuestionListening &&
              questionSessionId == (_globalSessionId + 1000)) {
            debugPrint(
              '[QuestionService] This is our active question session. Resetting wakeWordDetected to false.',
            );
            _wakeWordDetected = false;
            _isQuestionListening = false;
            _questionTimeoutTimer?.cancel();
            _initialTimeoutTimer?.cancel();
            _silenceTimer?.cancel();
            if (!_hasProcessedResult) {
              debugPrint(
                '[QuestionService] onStatus (sessionId=$questionSessionId): No result processed, calling timeout callback and restarting wake word listening.',
              );
              // Remove highlight from question box if UI callback is provided
              this.onQuestionHighlight?.call(false);
              onAnnounce?.call("I didn't hear anything. Try again?");
              resumeWakeWordAutoRestart();
              // Call timeout callback to handle proper restart
              onTimeout?.call();
            }
          } else {
            debugPrint(
              '[QuestionService] Ignoring status=done from inactive session (sessionId=$questionSessionId, _isQuestionListening=$_isQuestionListening)',
            );
          }
        }
      },
      onError: (error) async {
        debugPrint('[QuestionService] Speech error (question): $error');
        final msg = error.errorMsg.toLowerCase();
        debugPrint('[QuestionService] Error message lowercased: "$msg"');
        debugPrint(
          '[QuestionService] _hasProcessedResult: $_hasProcessedResult, retryCount: $retryCount',
        );

        _questionTimeoutTimer?.cancel();
        _initialTimeoutTimer?.cancel();
        _silenceTimer?.cancel();

        if (!_hasProcessedResult &&
            (msg.contains('no speech detected') ||
                msg.contains('error_no_match') ||
                msg.contains('no_match'))) {
          if (!_hasRetried && retryCount < 1) {
            debugPrint(
              '[QuestionService] No speech detected, retrying question listening (attempt ${retryCount + 1})...',
            );
            _hasRetried = true;
            await Future.delayed(const Duration(milliseconds: 400));
            startQuestionListening(retryCount: retryCount + 1);
          } else {
            debugPrint(
              '[QuestionService] No speech detected after retry or max attempts. Announcing timeout and restarting wake word listening.',
            );
            // Stop the question recognizer before announcing, to avoid it hearing the prompt
            await _speech.stop();
            _wakeWordDetected = false;
            _isQuestionListening = false;
            _hasProcessedResult = true;
            // Remove highlight from question box if UI callback is provided
            onQuestionHighlight?.call(false);
            debugPrint(
              '[QuestionService] About to call onAnnounce with timeout message',
            );
            onAnnounce?.call("I didn't hear anything. Try again?");
            debugPrint(
              '[QuestionService] About to call resumeWakeWordAutoRestart',
            );
            resumeWakeWordAutoRestart();
            // Call timeout callback to handle proper restart
            debugPrint('[QuestionService] About to call onTimeout callback');
            onTimeout?.call();
          }
        } else {
          debugPrint(
            '[QuestionService] Max retries reached or other error. Announcing error and restarting wake word listening.',
          );
          await _speech.stop();
          _wakeWordDetected = false;
          _isQuestionListening = false;
          _hasProcessedResult = true;
          onQuestionHighlight?.call(false);
          onAnnounce?.call("Speech recognition error. Try again?");
          resumeWakeWordAutoRestart();
          onTimeout?.call();
        }
      },
    );

    final initEnd = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
      '[TIMER] Question speech initialize END at $initEnd (delta: ${initEnd - initStart}ms)',
    );

    if (!available) {
      debugPrint(
        '[QuestionService] ERROR: Speech-to-text initialization failed. Question listening not started. Setting wakeWordDetected to false.',
      );
      _wakeWordDetected = false;
      _isQuestionListening = false;
      resumeWakeWordAutoRestart();
      return;
    }
    debugPrint(
      '[QuestionService] Speech-to-text initialized. Listening for question...',
    );

    // Initial no-speech timeout after entering question mode.
    _initialTimeoutTimer = Timer(_questionInitialTimeoutDuration, () {
      if (!_hasProcessedResult && !_hasDetectedFirstSpeech) {
        debugPrint(
          '[QuestionService] Initial timeout elapsed with no speech. Announcing and restarting wake word listening.',
        );
        _hasProcessedResult = true;
        _speech.stop();
        _wakeWordDetected = false;
        _isQuestionListening = false;
        // Remove highlight from question box if UI callback is provided
        onQuestionHighlight?.call(false);
        onAnnounce?.call("I didn't hear anything. Try again?");
        resumeWakeWordAutoRestart();
        onTimeout?.call();
      }
    });

    // Hard cap timeout for the whole question capture session.
    _questionTimeoutTimer?.cancel();
    _questionTimeoutTimer = Timer(_questionHardTimeoutDuration, () {
      if (!_hasProcessedResult) {
        debugPrint(
          '[QuestionService] Hard timeout (${_questionHardTimeoutDuration.inSeconds}s) reached. Stopping question listening.',
        );
        _hasProcessedResult = true;
        _silenceTimer?.cancel();
        _initialTimeoutTimer?.cancel();
        _speech.stop();
        _wakeWordDetected = false;
        _isQuestionListening = false;
        onQuestionHighlight?.call(false);
        onAnnounce?.call("I didn't hear anything. Try again?");
        resumeWakeWordAutoRestart();
        onTimeout?.call();
      }
    });

    final listenStart = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[TIMER] Question speech listen START at $listenStart');

    // POC-STYLE: Use dictation mode for questions like POC with longer timeouts.
    // localeId is set to the partner's language so the recognizer properly transcribes
    // what the partner says (e.g., English even when device locale is Spanish).
    debugPrint('[QuestionService] Starting listen with localeId=$localeId');
    await _speech.listen(
      localeId: localeId,
      onResult: (result) async {
        if (_hasProcessedResult) return; // Prevent duplicate processing
        final question = result.recognizedWords.trim();
        debugPrint(
          '[QuestionService] Question result: "$question" (final: ${result.finalResult})',
        );

        // POC-STYLE: More lenient filtering - POC didn't filter as aggressively
        final isValidQuestion =
            question.length >= 2; // Simplified validation like POC
        if (!isValidQuestion && result.finalResult) {
          debugPrint(
            '[QuestionService] Rejected too-short result: "$question"',
          );
          return; // Ignore this result and keep listening
        }

        // POC-STYLE: Check if this is the first valid speech detected in this session
        if (!_hasDetectedFirstSpeech &&
            question.isNotEmpty &&
            isValidQuestion) {
          debugPrint(
            '[QuestionService] POC-style: First speech detected: "$question" - triggering audio reset callback',
          );
          _hasDetectedFirstSpeech = true;
          onFirstSpeechDetected?.call();
          _initialTimeoutTimer
              ?.cancel(); // Cancel 20-second initial timeout since we detected speech

          // POC-STYLE: Start 4-second silence detection after first speech (increased from 2s)
          _resetSilenceTimer();
        }

        _lastPartialQuestion = question;
        // Update status bar with what the app is hearing during question processing (separate callback)
        if (onQuestionStatusUpdate != null &&
            question.isNotEmpty &&
            isValidQuestion) {
          onQuestionStatusUpdate!(question);
        }

        // Reset silence timer on each result (POC behavior) - but only if not already processed
        if (_hasDetectedFirstSpeech && !_hasProcessedResult) {
          _resetSilenceTimer();
        }

        // POC-STYLE: Process final results immediately when they come in
        if (result.finalResult) {
          debugPrint('[QuestionService] FINAL RESULT DEBUG:');
          debugPrint('[QuestionService]   - question: "$question"');
          debugPrint(
            '[QuestionService]   - question.isNotEmpty: ${question.isNotEmpty}',
          );
          debugPrint('[QuestionService]   - isValidQuestion: $isValidQuestion');
          debugPrint(
            '[QuestionService]   - onQuestion != null: ${onQuestion != null}',
          );
          debugPrint(
            '[QuestionService]   - !_hasProcessedResult: ${!_hasProcessedResult}',
          );
          debugPrint(
            '[QuestionService]   - _hasProcessedResult: $_hasProcessedResult',
          );

          if (question.isNotEmpty &&
              isValidQuestion &&
              onQuestion != null &&
              !_hasProcessedResult) {
            debugPrint(
              '[QuestionService] Final question recognized, firing onQuestion callback. Setting wakeWordDetected to false.',
            );
            _hasProcessedResult =
                true; // Set flag immediately to prevent duplicates
            _questionTimeoutTimer?.cancel();
            _silenceTimer?.cancel();
            _initialTimeoutTimer?.cancel();
            onQuestion!(question);
            _wakeWordDetected = false;
            _isQuestionListening = false;
            resumeWakeWordAutoRestart();
          } else {
            debugPrint(
              '[QuestionService] Final result NOT processed - one or more conditions failed',
            );
          }
        }
      },
      listenFor: _questionListenForDuration,
      pauseFor: _questionPauseForDuration,
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation, // POC uses dictation mode for questions
      // ENHANCED: Add sound level monitoring for better microphone detection
      onSoundLevelChange: (level) {
        // Print sound level occasionally to verify microphone is working during question listening
        if (DateTime.now().millisecondsSinceEpoch % 2000 < 100) {
          debugPrint('Question listening - Sound level: $level');
        }
      },
    );

    final listenEnd = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
      '[TIMER] Question speech listen END at $listenEnd (delta: ${listenEnd - listenStart}ms)',
    );
    debugPrint(
      '[TIMER] TOTAL POC-style question listening setup time: ${listenEnd - stopStart}ms',
    );
  }

  // POC-STYLE: Reset silence timer (like POC's _resetSilenceTimer)
  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    // Only start silence detection if we've detected speech and haven't already processed a result
    if (_hasDetectedFirstSpeech && !_hasProcessedResult) {
      _silenceTimer = Timer(_questionSilenceTimeoutDuration, () {
        if (!_hasProcessedResult) {
          // Double-check to prevent duplicate processing
          debugPrint(
            '[QuestionService] Silence timeout (${_questionSilenceTimeoutDuration.inSeconds}s) detected after speech, stopping listening',
          );
          _stopQuestionListening();
        }
      });
    }
  }

  // POC-STYLE: Stop question listening method
  Future<void> _stopQuestionListening() async {
    if (_hasProcessedResult) return; // Prevent duplicate processing

    _silenceTimer?.cancel();
    _initialTimeoutTimer?.cancel();
    _questionTimeoutTimer?.cancel();
    await _speech.stop();
    _isQuestionListening = false;

    if (_lastPartialQuestion.isNotEmpty && !_hasProcessedResult) {
      // Process the question we captured
      debugPrint(
        '[QuestionService] POC-style: Processing captured question: "$_lastPartialQuestion"',
      );
      _hasProcessedResult = true; // Set flag to prevent duplicates
      onQuestion?.call(_lastPartialQuestion);
      _wakeWordDetected = false;
      resumeWakeWordAutoRestart();
    } else {
      // If no question was captured, restart wake word listening
      debugPrint(
        '[QuestionService] POC-style: No question captured, restarting wake word listening',
      );
      _hasProcessedResult = true;
      _wakeWordDetected = false;
      resumeWakeWordAutoRestart();
      onTimeout?.call();
    }
  }

  void stop() {
    wakeWordShouldBeActive = false;
    _isListening = false;
    _isWakeWordListening = false;
    _isQuestionListening = false;
    debugPrint('Stop() Setting wakeWordShouldBeActive to false');
    _wakeWordDetected = false;
    _currentSessionId = -1; // Invalidate all previous sessions
    _initialTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    _questionTimeoutTimer?.cancel();
    _speech.stop();
  }

  bool get isListening => _isListening;
  bool get wakeWordDetected => _wakeWordDetected;
}
