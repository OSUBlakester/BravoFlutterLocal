import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/music_playback_service.dart';
import 'services/user_settings_provider.dart';
import 'main.dart'; // Import for SpeechBubbleButton

Future<void> _playWithFeedback(
  BuildContext context,
  MusicPlaybackService music,
  SpotifyPlaylist playlist,
) async {
  await music.playPlaylist(playlist);
  if (!context.mounted) return;

  final message = (music.lastError ?? '').trim().isNotEmpty
      ? music.lastError!.trim()
      : 'Requested playback for ${playlist.name}.';

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
}

class MusicPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;
  final Future<void> Function(String musicContext)? onTalkAboutMusic;
  final Future<void> Function()? onTalkAboutSomethingElse;

  const MusicPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
    this.onTalkAboutMusic,
    this.onTalkAboutSomethingElse,
  });

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> with WidgetsBindingObserver {
  // Add platform channel for audio routing (like main.dart)
  static const platform = MethodChannel('audio_routing');

  // Focus node for keyboard handling
  late FocusNode _keyboardFocusNode;

  // --- Scanning State ---
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _isScanning = false;
  bool _isScanningPaused = false;
  bool _waitingForUserInput = false;
  bool _isAnnouncingScanningPrompt = false;  // Track if announcing during scanning prompts (for Tab interrupt)
  Timer? _scanningTimer;
  int _scanningIndex = -1;
  int _scanCycleCount = 0;
  int _scanLoopLimit = 0;
  bool _waitingForInitialSwitch = false;
  bool _switchStartRequested = false;
  DateTime? _lastWaitForSwitchNotificationAt;
  int _lastSwitchActivationMs = 0;
  String _scanningPhase = 'playlists'; // 'playlists' | 'controls'
  bool _musicIsPlayingState = false;

  // --- Audio State ---
  FlutterTts? _flutterTts;
  bool _isAnnouncing = false;
  AudioPlayer? _audioPlayer;
  int _currentSpeechId = 0;
  String _currentAudioRoute = 'personal';

  // --- Settings ---
  Map<String, dynamic> _userSettings = {};
  int _gridColumns = 10;
  double _buttonSize = 80.0;
  bool _scanningOff = false;
  int _scanDelay = 3500;
  Color _darkColor = const Color(0xFF002244);
  Color _lightColor = const Color(0xFFFB4F14);

  MusicPlaybackService? _musicService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardFocusNode = FocusNode();
    _keyboardFocusNode.addListener(_onFocusChanged);
    _initializePage();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _musicService = Provider.of<MusicPlaybackService>(context, listen: false);
      _musicService?.addListener(_onMusicServiceChanged);

      // Await initialization to prevent race conditions on startup configuration checks
      unawaited(() async {
        await _musicService!.ensureInitialized();
        if (mounted && _musicService!.isConfigured) {
          await _musicService!.refreshPlaylists();
        }
      }());

      // Always start scanning and request keyboard focus immediately on page load
      _startScanningAfterDelay();
      _keyboardFocusNode.requestFocus();

      // Always schedule delayed focus requests to survive route transitions
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
          debugPrint('MusicPage: Post-init 100ms requested keyboard focus');
        }
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
          debugPrint('MusicPage: Post-init 500ms re-requested keyboard focus');
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocusNode.removeListener(_onFocusChanged);
    _musicService?.removeListener(_onMusicServiceChanged);
    _cleanupResources();
    _keyboardFocusNode.dispose();

    // Restore default/personal routing (Bluetooth) for the main page
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(() async {
        try {
          const platform = MethodChannel('audio_routing');
          if (Platform.isIOS) {
            await platform.invokeMethod('routeToPersonal');
          } else {
            await platform.invokeMethod('resetToDefault');
          }
          debugPrint('MusicPage dispose: Restored audio routing to personal');
        } catch (e) {
          debugPrint('MusicPage dispose: Failed to restore audio routing: $e');
        }
      }());
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    debugPrint('MusicPage: didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Stop scanning and active TTS scanning prompts immediately when backgrounded
      _currentSpeechId++;
      _flutterTts?.stop();
      _pauseScanning();
      // Do NOT pause the silence loop here. The silence loop must run persistently to
      // keep the AVAudioSession active. Pausing it causes just_audio to deactivate the
      // audio session, and the subsequent reactivation on resume interrupts Spotify playback.
    } else if (state == AppLifecycleState.resumed) {
      // Re-request focus when returning to the app
      _keyboardFocusNode.requestFocus();
      // Do NOT call _audioPlayer!.play() here. The silence loop is already running
      // continuously from initialization. Re-calling play() after a lifecycle pause would
      // reactivate the AVAudioSession and interrupt Spotify playback.

      // Resume scanning if appropriate
      if (!_scanningOff && _scanningPhase == 'playlists' && !_musicIsPlayingState) {
        _maybeStartScanning();
      }
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (!_keyboardFocusNode.hasFocus && ModalRoute.of(context)?.isCurrent == true) {
      debugPrint('MusicPage: Focus lost, reclaiming focus...');
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_keyboardFocusNode.hasFocus && ModalRoute.of(context)?.isCurrent == true) {
          _keyboardFocusNode.requestFocus();
        }
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_keyboardFocusNode.hasFocus && ModalRoute.of(context)?.isCurrent == true) {
          _keyboardFocusNode.requestFocus();
        }
      });
    }
  }

  void _onMusicServiceChanged() {
    if (!mounted) return;
    if (_isScanning) {
      debugPrint('MusicPage: Ignoring _onMusicServiceChanged because we are actively scanning.');
      return;
    }
    final music = _musicService;
    if (music == null) return;

    debugPrint('MusicPage: _onMusicServiceChanged - music.isPlaying=${music.isPlaying}, _musicIsPlayingState=$_musicIsPlayingState, _scanningPhase=$_scanningPhase, _isScanning=$_isScanning');

    // Synchronize play state if music is active/playing and we are in controls phase
    if (music.isPlaying && !_musicIsPlayingState && _scanningPhase == 'controls' && !_isScanning) {
      setState(() {
        _musicIsPlayingState = true;
        _scanningPhase = 'controls';
        _isScanning = false;
        _isScanningPaused = true;
        _waitingForUserInput = true;
        // Reset index so the next switch press starts a fresh scan cycle (pause +
        // announce buttons) rather than re-selecting whichever button was last
        // highlighted. Without this, pressing switch after resume would hit
        // _handleControlBarSelection(0) → SpotifySdk.pause() (App Remote), which
        // hangs. Fresh-start uses pauseForScanning() (Web API, reliable).
        _scanningIndex = -1;
      });
      _scanningTimer?.cancel();
      _scanningTimer = null;

      _startSilenceLoop();
      // Delay audio routing change so Spotify's App Remote audio session fully
      // establishes before forceSpeaker() calls setActive(true). An immediate
      // AVAudioSession change interrupts Spotify and pauses playback.
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) _resetAudioRouteToSpeaker();
      });

      _keyboardFocusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
        }
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
        }
      });
    } else if (!music.isPlaying && _musicIsPlayingState) {
      // Music was playing, but now it is paused or stopped natively
      setState(() {
        _musicIsPlayingState = false;
      });
      _stopSilenceLoop();
    }
  }

  void _cleanupResources() {
    _scanningTimer?.cancel();
    _scanningTimer = null;
    _flutterTts?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }

  Future<void> _initializePage() async {
    debugPrint('MusicPage: Initializing...');
    try {
      // Load user settings
      await _loadUserSettings();

      // Initialize audio services
      await _initializeAudioServices();
    } catch (e) {
      debugPrint('Error initializing music page: $e');
    }
  }

  Future<void> _loadUserSettings() async {
    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      if (settingsProvider.settings == null) {
        settingsProvider.idToken = widget.idToken;
        settingsProvider.userId = widget.aacUserId;
        await settingsProvider.fetchSettings();
      }

      setState(() {
        _userSettings = settingsProvider.settings?.toJson() ?? {};
        _gridColumns = _userSettings['gridColumns'] ?? 10;
        _scanningOff = _userSettings['ScanningOff'] ?? false;
        _scanDelay = _userSettings['scanDelay'] ?? 3500;
        _scanLoopLimit = _userSettings['scanLoopLimit'] ?? 0;
        _darkColor = Color(_userSettings['darkColorValue'] ?? 0xFF002244);
        _lightColor = Color(_userSettings['lightColorValue'] ?? 0xFFFB4F14);
      });

      debugPrint('MusicPage: Settings loaded - scanning: ${!_scanningOff}, delay: $_scanDelay');
    } catch (e) {
      debugPrint('Error loading user settings: $e');
    }
  }

  Future<void> _initializeAudioServices() async {
    try {
      // Configure audio session for the app to play and record, mix with others, allow Bluetooth, etc.
      // This matches AppDelegate.swift and ensures just_audio mixes with Spotify instead of blocking it.
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));

      // Initialize TTS
      _flutterTts = FlutterTts();
      if (_flutterTts != null) {
        await _flutterTts!.setLanguage("en-US");
        await _flutterTts!.setSpeechRate(0.5);

        if (Platform.isIOS) {
          await _flutterTts!.setSharedInstance(true);
          await _flutterTts!.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playAndRecord,
            [
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
              IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            ],
            IosTextToSpeechAudioMode.defaultMode,
          );
        }

        final personalVolume = await _getEffectivePersonalVolume();
        final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
        debugPrint('MusicPage: Using personalVolume: $personalVolume/10 → TTS volume: $ttsVolume (scanning)');
        await _flutterTts!.setVolume(ttsVolume);
        await _flutterTts!.setPitch(1.0);
      }

      // Initialize audio player and start silence loop persistently to keep the audio session active.
      // Playing it continuously from page entry to disposal prevents iOS from pausing Spotify
      // during playback transitions/TTS stops, and avoids audio category change interruptions.
      _audioPlayer = AudioPlayer();
      if (!kIsWeb && Platform.isIOS) {
        try {
          debugPrint('MusicPage: Starting persistent background silence loop on initialization');
          await _audioPlayer!.setAsset('assets/silence.mp3');
          await _audioPlayer!.setLoopMode(LoopMode.one);
          await _audioPlayer!.setVolume(0.0);
          await _audioPlayer!.play();
        } catch (e) {
          debugPrint('MusicPage: Failed to start persistent silence loop: $e');
        }
      }

      debugPrint('MusicPage: Audio services initialized');
    } catch (e) {
      debugPrint('Error initializing audio services: $e');
    }
  }

  Future<int> _getEffectivePersonalVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint('MusicPage: Using LOCAL personal volume override: $overrideValue/10');
      return overrideValue;
    }

    if (!mounted) return 10;
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final settingsValue = settingsProvider.settings?.personalVolume ?? 10;
    debugPrint('MusicPage: Using SETTINGS personal volume: $settingsValue/10');
    return settingsValue;
  }

  Future<void> _resetAudioRouteToSpeaker() async {
    if (_lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive) {
      debugPrint('MusicPage: Skipping _resetAudioRouteToSpeaker because app is in background.');
      return;
    }
    if (_currentAudioRoute == 'speaker') {
      debugPrint('MusicPage: Audio routing is already speaker, skipping redundant override');
      return;
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        _currentAudioRoute = 'speaker';
        await platform.invokeMethod('forceSpeaker');
        debugPrint('MusicPage: Reset audio routing to built-in speaker');
        if (Platform.isIOS) {
          await Future.delayed(const Duration(milliseconds: 600));
        }
      } catch (e) {
        debugPrint('MusicPage: Failed to reset audio routing to speaker: $e');
      }
    }
  }

  Future<void> _startSilenceLoop() async {
    // Silence loop runs persistently from initialization to disposal.
    // Dynamic starting/stopping is disabled to prevent AVAudioSession category/play interrupts on Spotify.
  }

  Future<void> _stopSilenceLoop() async {
    // Silence loop runs persistently from initialization to disposal.
    // Dynamic starting/stopping is disabled to prevent AVAudioSession category/play interrupts on Spotify.
  }

  Future<void> _speakScanningPrompt(String text) async {
    debugPrint('MusicPage: _speakScanningPrompt called with text="$text"');
    if (_lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive) {
      debugPrint('MusicPage: _speakScanningPrompt ignored because app is in background.');
      return;
    }
    if (text.isEmpty || _flutterTts == null || _isAnnouncing) {
      debugPrint('MusicPage: _speakScanningPrompt early return: text.isEmpty=${text.isEmpty}, _flutterTts == null=${_flutterTts == null}, _isAnnouncing=$_isAnnouncing');
      return;
    }

    final speechId = ++_currentSpeechId;

    try {
      setState(() {
        _isAnnouncingScanningPrompt = true;
      });

      // Route to personal device (Bluetooth) before speaking scanning prompt
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          if (_currentAudioRoute != 'personal') {
            _currentAudioRoute = 'personal';
            if (Platform.isIOS) {
              await platform.invokeMethod('routeToPersonal');
            } else {
              await platform.invokeMethod('resetToDefault');
            }
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (e) {
          debugPrint('MusicPage TTS routing error: $e');
        }
      }

      await _flutterTts!.stop();

      // Set completion/cancel handlers to route back to speaker if music is active
      _flutterTts!.setCompletionHandler(() {
        if (!mounted || _currentSpeechId != speechId) return;
        if (_musicIsPlayingState) {
          _resetAudioRouteToSpeaker();
        }
      });

      _flutterTts!.setCancelHandler(() {
        if (!mounted || _currentSpeechId != speechId) return;
        if (_musicIsPlayingState) {
          _resetAudioRouteToSpeaker();
        }
      });

      _flutterTts!.setErrorHandler((msg) {
        if (!mounted || _currentSpeechId != speechId) return;
        if (_musicIsPlayingState) {
          _resetAudioRouteToSpeaker();
        }
      });

      await _flutterTts!.setSpeechRate(0.5);
      final personalVolume = await _getEffectivePersonalVolume();
      final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
      await _flutterTts!.setVolume(ttsVolume);
      await _flutterTts!.setPitch(1.0);
      await _flutterTts!.speak(text);
    } catch (e) {
      debugPrint('MusicPage: Error speaking scanning prompt: $e');
      if (_musicIsPlayingState) {
        _resetAudioRouteToSpeaker();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
    }
  }

  void _startScanningAfterDelay() {
    if (_scanningOff) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && !_isAnnouncing) {
          _maybeStartScanning();
        }
      });
    });
  }

  void _maybeStartScanning() {
    if (_lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive) {
      debugPrint('MusicPage: _maybeStartScanning ignored because app is in background.');
      return;
    }
    if (_scanningOff || _isScanning || _isAnnouncing) return;

    if (!_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
      debugPrint('MusicPage: Re-requesting focus during _maybeStartScanning');
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final waitForSwitch =
        settingsProvider.settings?.waitForSwitchToScan ?? false;

    if (waitForSwitch && !_waitingForInitialSwitch) {
      setState(() {
        _waitingForInitialSwitch = true;
        _switchStartRequested = false;
        _scanningIndex = -1;
      });

      unawaited(_playWaitForSwitchNotification());
      return;
    }

    _startScanning();
  }

  void _startScanning({bool force = false}) {
    if (_lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive) {
      debugPrint('MusicPage: _startScanning ignored because app is in background.');
      return;
    }
    if (_scanningOff || _isScanning || _isAnnouncing) return;

    if (!_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
      debugPrint('MusicPage: Re-requesting focus during _startScanning');
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    if (!force) {
      if ((settingsProvider.settings?.waitForSwitchToScan ?? false) &&
          !_switchStartRequested && _scanningPhase == 'playlists') {
        debugPrint('MusicPage: Waiting for switch before starting scanning');
        return;
      }

      if (_waitingForInitialSwitch && _scanningPhase == 'playlists') {
        debugPrint('MusicPage: _startScanning blocked while waiting for initial switch');
        return;
      }
    }

    setState(() {
      _isScanning = true;
      _scanningIndex = _scanningPhase == 'playlists' ? -1 : 0;
      _scanCycleCount = 0;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _switchStartRequested = false;
    });

    if (_musicIsPlayingState && _scanningPhase == 'controls') {
      _startSilenceLoop();
    }

    if (scanMode == 'auto') {
      _announceCurrentButton();
    }

    debugPrint('MusicPage: Scan mode: $scanMode');

    if (scanMode == 'auto') {
      _scanningTimer = Timer(Duration(milliseconds: _scanDelay), () {
        _scanNext();
      });
    }
  }

  void _scanNext() {
    debugPrint('MusicPage: _scanNext called - _isScanning=$_isScanning, _scanningOff=$_scanningOff, _isAnnouncing=$_isAnnouncing, _scanningPhase=$_scanningPhase, _scanningIndex=$_scanningIndex');
    if (_lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive) {
      debugPrint('MusicPage: _scanNext ignored because app is in background.');
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == false) {
      debugPrint('MusicPage: Page is not current, ignoring scan step');
      return;
    }
    if (!_isScanning || _scanningOff || _isAnnouncing) {
      debugPrint('MusicPage: _scanNext early return - !_isScanning=${!_isScanning}, _scanningOff=$_scanningOff, _isAnnouncing=$_isAnnouncing');
      return;
    }
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    bool shouldPauseAfterScan = false;

    if (_scanningPhase == 'playlists') {
      final music = Provider.of<MusicPlaybackService>(context, listen: false);
      final playlistsList = music.playlists.isNotEmpty ? music.playlists : music.fallbackPlaylists;

      setState(() {
        _scanningIndex++;
        if (_scanningIndex >= playlistsList.length) {
          _scanningIndex = -1; // Reset to Go Back button
          _scanCycleCount++;

          if (_scanLoopLimit > 0 && _scanCycleCount >= _scanLoopLimit) {
            shouldPauseAfterScan = true;
          }
        }
      });
    } else {
      // _scanningPhase == 'controls'
      setState(() {
        _scanningIndex++;
        if (_scanningIndex > 5) {
          _scanningIndex = 0; // Wrap around to index 0 (Pause/Resume)
          _scanCycleCount++;

          if (_scanLoopLimit > 0 && _scanCycleCount >= _scanLoopLimit) {
            shouldPauseAfterScan = true;
          }
        }
      });
    }

    // Auto-pause when the scan loop limit is reached. Calling _pauseScanning()
    // here (outside setState) avoids a nested setState call and ensures the
    // return properly skips the announcement and timer below.
    if (shouldPauseAfterScan) {
      _pauseScanning();
      return;
    }

    _announceCurrentButton();

    if (scanMode == 'auto') {
      _scanningTimer = Timer(Duration(milliseconds: _scanDelay), () {
        _scanNext();
      });
    }
  }

  void _announceCurrentButton() async {
    try {
      String text = '';
      if (_scanningPhase == 'playlists') {
        if (_scanningIndex == -1) {
          text = 'Go Back';
        } else {
          final music = Provider.of<MusicPlaybackService>(context, listen: false);
          final playlistsList = music.playlists.isNotEmpty ? music.playlists : music.fallbackPlaylists;
          if (_scanningIndex >= 0 && _scanningIndex < playlistsList.length) {
            text = playlistsList[_scanningIndex].name;
          } else {
            return;
          }
        }
      } else {
        // _scanningPhase == 'controls'
        if (_scanningIndex == 0) {
          text = 'Resume';
        } else if (_scanningIndex == 1) {
          text = 'Skip Song';
        } else if (_scanningIndex == 2) {
          text = 'Change Music';
        } else if (_scanningIndex == 3) {
          text = 'Stop Playing';
        } else if (_scanningIndex == 4) {
          text = 'Talk About Music';
        } else if (_scanningIndex == 5) {
          text = 'Talk About Something Else';
        }
      }

      if (text.isNotEmpty) {
        await _speakScanningPrompt(text);
      }
    } catch (e) {
      debugPrint('Error announcing current button: $e');
    }
  }

  void _stopScanning() {
    _scanningTimer?.cancel();
    _scanningTimer = null;
    setState(() {
      _isScanning = false;
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _scanningIndex = -1;
      _waitingForInitialSwitch = false;
      _switchStartRequested = false;
    });
    _stopSilenceLoop();
  }

  void _pauseScanning() {
    _scanningTimer?.cancel();
    _scanningTimer = null;
    setState(() {
      _isScanning = false;
      _isScanningPaused = true;
      _waitingForUserInput = true;
    });
    _stopSilenceLoop();
  }

  void _resumeScanning() {
    if (_lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive) {
      debugPrint('MusicPage: _resumeScanning ignored because app is in background.');
      return;
    }
    if (_isScanningPaused) {
      setState(() {
        _isScanningPaused = false;
        _waitingForUserInput = false;
        _isScanning = true;
      });
      _scanNext();
    }
  }

  Future<void> _selectPlaylistAndStartPlayback(SpotifyPlaylist playlist) async {
    _currentSpeechId++; // Cancel any active TTS callbacks
    _flutterTts?.stop(); // Stop any currently speaking TTS

    _pauseScanning();
    setState(() {
      _scanningPhase = 'controls';
      _musicIsPlayingState = true; // Mark as playing immediately to transition phase and stop scanning
      _scanningIndex = -1; // Reset highlight
    });

    final music = Provider.of<MusicPlaybackService>(context, listen: false);

    await _resetAudioRouteToSpeaker();

    if (!mounted) return;

    _keyboardFocusNode.requestFocus();
    await _playWithFeedback(context, music, playlist);

    if (mounted) {
      final isInBackground = _lifecycleState == AppLifecycleState.paused ||
          _lifecycleState == AppLifecycleState.inactive;
      if (!music.isPlaying && !isInBackground) {
        // Play failed, reset to playlists phase and restart scanning
        setState(() {
          _scanningPhase = 'playlists';
          _musicIsPlayingState = false;
        });
        _startScanning(force: true);
      } else {
        // Play succeeded: start silence loop
        await _startSilenceLoop();
      }
    }

    // Re-request focus to survive any focus loss from media connection or snackbar
    if (mounted) {
      _keyboardFocusNode.requestFocus();
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  void _handlePauseResume() async {
    final music = Provider.of<MusicPlaybackService>(context, listen: false);
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    if (music.isPlaying) {
      await music.pause();
    } else {
      // Resume FIRST, then wait before routing audio. forceSpeaker() calls
      // AVAudioSession.setActive(true) which interrupts Spotify's audio session
      // if triggered within the first ~2 seconds of App Remote playback.
      await music.resume();
      await Future.delayed(const Duration(milliseconds: 1500));
      await _resetAudioRouteToSpeaker();
      if (music.isConnected) {
        await _startSilenceLoop();
      }
    }
  }

  void _handleSkipNext() async {
    final music = Provider.of<MusicPlaybackService>(context, listen: false);
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    await _resetAudioRouteToSpeaker();
    await music.skipNext();
  }

  void _handleStopPlayback() async {
    final music = Provider.of<MusicPlaybackService>(context, listen: false);
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    await music.stopPlayback();
    setState(() {
      _scanningPhase = 'playlists';
      _musicIsPlayingState = false;
      _scanningIndex = -1;
    });
    await _stopSilenceLoop();
    _handleBackButton(); // Return to the prior page
  }

  void _handleChangeMusic() async {
    final music = Provider.of<MusicPlaybackService>(context, listen: false);
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    await music.stopPlayback();
    setState(() {
      _scanningPhase = 'playlists';
      _musicIsPlayingState = false;
      _scanningIndex = -1;
    });
    await _stopSilenceLoop();
    _startScanning(force: true); // Start scanning playlists immediately!
  }

  void _handleControlBarSelection(int index) async {
    _currentSpeechId++; // Cancel active TTS scanning cues
    _flutterTts?.stop();

    _pauseScanning(); // Stop scanning control options
    _keyboardFocusNode.requestFocus();
    if (index == 0) {
      _handlePauseResume();
    } else if (index == 1) {
      _handleSkipNext();
    } else if (index == 2) {
      _handleChangeMusic();
    } else if (index == 3) {
      _handleStopPlayback();
    } else if (index == 4) {
      final music = Provider.of<MusicPlaybackService>(context, listen: false);
      if (widget.onTalkAboutMusic != null) {
        await widget.onTalkAboutMusic!(music.musicContextSummary);
      }
    } else if (index == 5) {
      if (widget.onTalkAboutSomethingElse != null) {
        await widget.onTalkAboutSomethingElse!();
      }
    }
  }

  Future<void> _handleSpacebarPress() async {
    debugPrint('MusicPage: Spacebar pressed - _waitingForUserInput=$_waitingForUserInput, _isScanningPaused=$_isScanningPaused, _isScanning=$_isScanning, _scanningIndex=$_scanningIndex, _scanningPhase=$_scanningPhase');
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    if (_isAnnouncing) {
      debugPrint('MusicPage: Spacebar ignored while announcement is in progress');
      return;
    }

    if (_scanningPhase == 'controls') {
      if (_isScanning) {
        // Scanning is active — select whatever button is currently highlighted.
        debugPrint('MusicPage: Spacebar - Selecting control option at index $_scanningIndex');
        _handleControlBarSelection(_scanningIndex);
      } else if (_isScanningPaused && _scanningIndex >= 0) {
        // Scanning was auto-paused at a valid button index. The user pressed
        // switch intending to select that button — treat it as a selection rather
        // than restarting the scan from index 0.
        debugPrint('MusicPage: Spacebar - Selecting paused control at index $_scanningIndex');
        _handleControlBarSelection(_scanningIndex);
      } else {
        // No scanning is active yet (e.g. music just started playing and the
        // user hit switch for the first time). Start scanning from index 0.
        debugPrint('MusicPage: Spacebar - Starting control scanning phase');

        // Pause music playback first so scanning and music do not overlap.
        // Uses Web API (not App Remote) to keep the App Remote write pipeline
        // clean for the subsequent resume/skip command the user will select.
        final music = Provider.of<MusicPlaybackService>(context, listen: false);
        if (music.isPlaying) {
          unawaited(music.pauseForScanning());
        }

        // Route audio prompts to Bluetooth speaker (personal)
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          try {
            if (_currentAudioRoute != 'personal') {
              _currentAudioRoute = 'personal';
              if (Platform.isIOS) {
                unawaited(platform.invokeMethod('routeToPersonal'));
              } else {
                unawaited(platform.invokeMethod('resetToDefault'));
              }
            }
          } catch (e) {
            debugPrint('MusicPage: routeToPersonal error: $e');
          }
        }

        _scanningTimer?.cancel();
        _scanningTimer = null;

        setState(() {
          _musicIsPlayingState = false;
          _isScanning = true;
          _scanningIndex = 0;
          _scanCycleCount = 0;
          _isScanningPaused = false;
          _waitingForUserInput = false;
        });
        debugPrint('MusicPage: _handleSpacebarPress starting silence loop');
        unawaited(_startSilenceLoop());
        debugPrint('MusicPage: _handleSpacebarPress silence loop done, announcing current button');
        _announceCurrentButton();
        if (scanMode == 'auto') {
          debugPrint('MusicPage: _handleSpacebarPress starting scanning timer with delay=$_scanDelay');
          _scanningTimer = Timer(Duration(milliseconds: _scanDelay), () {
            debugPrint('MusicPage: Scanning timer fired, calling _scanNext');
            _scanNext();
          });
        }
      }
      return;
    }

    if (_waitingForInitialSwitch) {
      debugPrint('MusicPage: Initial switch detected, starting scanning');
      setState(() {
        _waitingForInitialSwitch = false;
        _switchStartRequested = true;
      });
      _startScanning();
      return;
    }

    if (scanMode == 'step' && _isScanning && _scanningIndex < -1) {
      return;
    }

    if (_waitingForUserInput || _isScanningPaused) {
      debugPrint('MusicPage: Spacebar - Resuming scanning from paused state');
      _resumeScanning();
    } else if (_isScanning) {
      debugPrint('MusicPage: Spacebar - Selecting button at index $_scanningIndex');
      if (_scanningIndex == -1) {
        _handleBackButton();
      } else {
        final music = Provider.of<MusicPlaybackService>(context, listen: false);
        final playlistsList = music.playlists.isNotEmpty ? music.playlists : music.fallbackPlaylists;
        if (_scanningIndex >= 0 && _scanningIndex < playlistsList.length) {
          final playlist = playlistsList[_scanningIndex];
          _selectPlaylistAndStartPlayback(playlist);
        }
      }
    }
  }

  void _handleBackButton() {
    _cleanupResources();
    Navigator.of(context).pop();
  }

  Future<void> _playWaitForSwitchNotification() async {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final playChime =
        settingsProvider.settings?.playWaitForSwitchChime ?? false;
    if (!playChime) {
      debugPrint(
        'MusicPage waitForSwitchNotification: Chime disabled in settings',
      );
      return;
    }

    final now = DateTime.now();
    if (_lastWaitForSwitchNotificationAt != null &&
        now.difference(_lastWaitForSwitchNotificationAt!).inMilliseconds <
            1200) {
      debugPrint(
        'MusicPage waitForSwitchNotification: Skipping duplicate notification playback',
      );
      return;
    }
    _lastWaitForSwitchNotificationAt = now;

    final player = AudioPlayer();
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          if (_currentAudioRoute != 'personal') {
            _currentAudioRoute = 'personal';
            if (Platform.isIOS) {
              await platform.invokeMethod('routeToPersonal');
            } else {
              await platform.invokeMethod('resetToDefault');
            }
          }
        } catch (e) {
          debugPrint(
            'MusicPage waitForSwitchNotification: Personal routing setup failed (non-critical): $e',
          );
        }
      }

      final personalVolume = await _getEffectivePersonalVolume();
      const chimeCompensation = 0.18;
      const chimeMaxCap = 0.16;
      final chimeVolume = ((personalVolume / 10.0) * chimeCompensation)
          .clamp(0.0, chimeMaxCap);

      await player.setAsset('assets/notification.mp3');
      await player.setVolume(chimeVolume);
      await player.play();
      await player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
    } catch (e) {
      debugPrint(
        'MusicPage waitForSwitchNotification: Playback failed: $e',
      );
    } finally {
      await player.dispose();
      if (_musicIsPlayingState) {
        _resetAudioRouteToSpeaker();
      }
    }
  }

  void _showSpotifySettingsDialog(BuildContext context, MusicPlaybackService music) {
    final clientIdController = TextEditingController(text: music.clientId);
    final redirectUriController = TextEditingController(text: music.redirectUri);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFF0369A1)),
              const SizedBox(width: 8),
              const Text('Spotify API Settings'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To access your playlists, you can configure your own Spotify Client ID & Redirect URI. '
                  'Make sure your test Spotify user is added to your app\'s "Users and Access" list in the Spotify Developer Dashboard.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: clientIdController,
                  decoration: const InputDecoration(
                    labelText: 'Client ID',
                    hintText: '32-character Client ID',
                    border: OutlineInputBorder(),
                    helperText: 'From Spotify Developer Dashboard',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: redirectUriController,
                  decoration: const InputDecoration(
                    labelText: 'Redirect URI',
                    hintText: 'e.g. bravo://spotify-auth-callback',
                    border: OutlineInputBorder(),
                    helperText: 'Must match Spotify Dashboard Redirect URIs',
                  ),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset Credentials?'),
                    content: const Text('This will restore the default developer Client ID and Redirect URI.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await music.clearCredentials();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Credentials reset to defaults.')),
                    );
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Reset Default'),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newClientId = clientIdController.text.trim();
                    final newRedirectUri = redirectUriController.text.trim();
                    if (newClientId.isEmpty || newRedirectUri.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Both Client ID and Redirect URI are required.')),
                      );
                      return;
                    }
                    await music.saveCredentials(
                      clientId: newClientId,
                      redirectUri: newRedirectUri,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Spotify API credentials saved.')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        );
      },
    );
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

    // Retrieve scanMode from UserSettingsProvider
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        scanMode == 'step') {
      debugPrint('MusicPage: Tab pressed in step mode: advancing scan');

      if (_isScanning && _isAnnouncingScanningPrompt) {
        _flutterTts?.stop();
        if (mounted) {
          setState(() {
            _isAnnouncingScanningPrompt = false;
          });
        }
      }

      if (_isScanning && _scanningIndex >= -1) {
        _scanNext();
      }
      _keyboardFocusNode.requestFocus();
      return;
    }

    if (isSwitchKey && event is RawKeyDownEvent) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSwitchActivationMs < 180) {
        return;
      }
      _lastSwitchActivationMs = now;

      debugPrint('MusicPage: Switch key detected, calling _handleSpacebarPress');
      _handleSpacebarPress();
      _keyboardFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicPlaybackService>();

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        _cleanupResources();
      },
      child: RawKeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKey: _handleRawKey,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Music'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBackButton,
            ),
            actions: [
              IconButton(
                tooltip: 'Spotify Settings',
                onPressed: () => _showSpotifySettingsDialog(context, music),
                icon: const Icon(Icons.settings),
              ),
              IconButton(
                tooltip: 'Home',
                onPressed: _handleBackButton,
                icon: const Icon(Icons.home),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StatusBanner(
                  errorText: music.lastError,
                  isInfo: music.webApiForbidden,
                ),
                _NowPlayingCard(music: music),
                Expanded(
                  child: _MusicContent(
                    music: music,
                    isScanning: _isScanning,
                    isScanningPaused: _isScanningPaused,
                    scanningIndex: _scanningIndex,
                    scanningPhase: _scanningPhase,
                    darkColor: _darkColor,
                    lightColor: _lightColor,
                    gridColumns: _gridColumns,
                    buttonSize: _buttonSize,
                    resumeScanning: _resumeScanning,
                    pauseScanning: _pauseScanning,
                    stopScanning: _stopScanning,
                    handleBackButton: _handleBackButton,
                    onPlaylistSelected: _selectPlaylistAndStartPlayback,
                  ),
                ),
                _ControlBar(
                  music: music,
                  isScanning: _isScanning,
                  scanningIndex: _scanningIndex,
                  scanningPhase: _scanningPhase,
                  lightColor: _lightColor,
                  darkColor: _darkColor,
                  onPauseResume: _handlePauseResume,
                  onSkipNext: _handleSkipNext,
                  onStopPlayback: _handleStopPlayback,
                  onChangeMusic: _handleChangeMusic,
                  onTalkAboutMusic: () async {
                    if (widget.onTalkAboutMusic != null) {
                      await widget.onTalkAboutMusic!(music.musicContextSummary);
                    }
                  },
                  onTalkAboutSomethingElse: () async {
                    if (widget.onTalkAboutSomethingElse != null) {
                      await widget.onTalkAboutSomethingElse!();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String? errorText;
  final bool isInfo;

  const _StatusBanner({
    required this.errorText,
    this.isInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    if (errorText == null || errorText!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isInfo ? const Color(0xFFEFF6FF) : const Color(0xFFFFF2EE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isInfo ? const Color(0xFFBFDBFE) : const Color(0xFFFFB49F),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isInfo ? Icons.info_outline : Icons.warning_amber_rounded,
            color: isInfo ? const Color(0xFF1E40AF) : const Color(0xFFB54708),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorText!,
              style: TextStyle(
                color:
                    isInfo ? const Color(0xFF1E3A8A) : const Color(0xFF7A2E0E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final MusicPlaybackService music;

  const _NowPlayingCard({required this.music});

  @override
  Widget build(BuildContext context) {
    final title = music.currentTrack?.trim().isNotEmpty == true
        ? music.currentTrack!
        : 'Nothing playing';

    final subtitleParts = <String>[];
    if (music.currentArtist?.trim().isNotEmpty == true) {
      subtitleParts.add(music.currentArtist!);
    }
    if (music.currentPlaylistName?.trim().isNotEmpty == true) {
      subtitleParts.add('Playlist: ${music.currentPlaylistName}');
    }
    final subtitle = subtitleParts.join(' • ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C4A6E), Color(0xFF0369A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class _MusicContent extends StatelessWidget {
  final MusicPlaybackService music;
  final bool isScanning;
  final bool isScanningPaused;
  final int scanningIndex;
  final String scanningPhase;
  final Color darkColor;
  final Color lightColor;
  final int gridColumns;
  final double buttonSize;
  final VoidCallback resumeScanning;
  final VoidCallback pauseScanning;
  final VoidCallback stopScanning;
  final VoidCallback handleBackButton;
  final Function(SpotifyPlaylist) onPlaylistSelected;

  const _MusicContent({
    required this.music,
    required this.isScanning,
    required this.isScanningPaused,
    required this.scanningIndex,
    required this.scanningPhase,
    required this.darkColor,
    required this.lightColor,
    required this.gridColumns,
    required this.buttonSize,
    required this.resumeScanning,
    required this.pauseScanning,
    required this.stopScanning,
    required this.handleBackButton,
    required this.onPlaylistSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (music.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final playlistsList = music.playlists.isNotEmpty ? music.playlists : music.fallbackPlaylists;

    // Build list of all items in grid:
    // First item is Go Back
    final allButtons = [
      {'name': 'Go Back', 'isBackButton': true},
      ...playlistsList.map((p) => {'name': p.name, 'isBackButton': false, 'playlist': p}),
    ];

    final availableWidth = MediaQuery.of(context).size.width - 40; // Account for padding
    final spacing = 10.0;
    final gridPadding = 20.0;

    double effectiveButtonSize = (availableWidth / gridColumns).clamp(40.0, buttonSize);
    final double fontSize = ((effectiveButtonSize / 10) * 1.44).clamp(14.4, 25.9);

    final showFallbackBanner = music.playlists.isEmpty;
    final title = music.webApiForbidden
        ? 'Spotify account playlists are blocked by API permissions.'
        : 'No account playlists loaded yet.';
    final subtitle = music.webApiForbidden
        ? 'Account playlist access is unavailable in this Spotify mode/network. You can still start music with these preset playlists.'
        : 'Try refresh, or start with a preset Spotify playlist below.';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              if (!music.webApiForbidden) ...[
                ElevatedButton.icon(
                  onPressed: music.refreshPlaylists,
                  icon: const Icon(Icons.queue_music),
                  label: const Text('Refresh Playlists'),
                ),
                const SizedBox(width: 8),
              ] else ...[
                const Expanded(
                  child: Text(
                    'Using preset Spotify playlists',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (music.isConnected || music.isPlaying) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    stopScanning();
                    music.disconnect();
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () => music.connect(autoPause: true),
                  icon: const Icon(Icons.link),
                  label: const Text('Connect Spotify'),
                ),
              ],
            ],
          ),
        ),
        if (showFallbackBanner)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF1E40AF), fontSize: 13),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: Colors.grey[100],
            padding: EdgeInsets.all(gridPadding),
            child: Scrollbar(
              thumbVisibility: true,
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridColumns,
                  childAspectRatio: 1.0,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: allButtons.length,
                itemBuilder: (context, index) {
                  final button = allButtons[index];
                  final isBackButton = button['isBackButton'] == true;
                  final label = button['name'] as String;

                  // Calculate scanning index (-1 for Go Back, then 0-based for other buttons)
                  final buttonScanIndex = isBackButton ? -1 : index - 1;
                  final isHighlighted = scanningPhase == 'playlists' && buttonScanIndex == scanningIndex && (isScanning || isScanningPaused);

                  return Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: SizedBox(
                      width: effectiveButtonSize,
                      height: effectiveButtonSize,
                      child: SpeechBubbleButton(
                        label: label,
                        onPressed: () async {
                          if (isScanningPaused && !isScanning && scanningPhase == 'playlists') {
                            resumeScanning();
                          } else {
                            if (isBackButton) {
                              handleBackButton();
                            } else {
                              final playlist = button['playlist'] as SpotifyPlaylist;
                              onPlaylistSelected(playlist);
                            }
                          }
                        },
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
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  final MusicPlaybackService music;
  final bool isScanning;
  final int scanningIndex;
  final String scanningPhase;
  final Color lightColor;
  final Color darkColor;
  final VoidCallback onPauseResume;
  final VoidCallback onSkipNext;
  final VoidCallback onStopPlayback;
  final VoidCallback onChangeMusic;
  final Future<void> Function() onTalkAboutMusic;
  final Future<void> Function() onTalkAboutSomethingElse;

  const _ControlBar({
    required this.music,
    required this.isScanning,
    required this.scanningIndex,
    required this.scanningPhase,
    required this.lightColor,
    required this.darkColor,
    required this.onPauseResume,
    required this.onSkipNext,
    required this.onStopPlayback,
    required this.onChangeMusic,
    required this.onTalkAboutMusic,
    required this.onTalkAboutSomethingElse,
  });

  @override
  Widget build(BuildContext context) {
    final bool isControlsPhase = scanningPhase == 'controls';
    final bool showHighlight0 = isControlsPhase && isScanning && scanningIndex == 0;
    final bool showHighlight1 = isControlsPhase && isScanning && scanningIndex == 1;
    final bool showHighlight2 = isControlsPhase && isScanning && scanningIndex == 2;
    final bool showHighlight3 = isControlsPhase && isScanning && scanningIndex == 3;
    final bool showHighlight4 = isControlsPhase && isScanning && scanningIndex == 4;
    final bool showHighlight5 = isControlsPhase && isScanning && scanningIndex == 5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ElevatedButton.icon(
            onPressed: onPauseResume,
            style: ElevatedButton.styleFrom(
              side: showHighlight0
                  ? BorderSide(color: lightColor, width: 3.0)
                  : null,
              elevation: showHighlight0 ? 8.0 : null,
            ),
            icon: Icon((music.isPlaying && !isScanning) ? Icons.pause : Icons.play_arrow),
            label: Text((music.isPlaying && !isScanning) ? 'Pause' : 'Resume'),
          ),
          ElevatedButton.icon(
            onPressed: onSkipNext,
            style: ElevatedButton.styleFrom(
              side: showHighlight1
                  ? BorderSide(color: lightColor, width: 3.0)
                  : null,
              elevation: showHighlight1 ? 8.0 : null,
            ),
            icon: const Icon(Icons.skip_next),
            label: const Text('Skip Song'),
          ),
          ElevatedButton.icon(
            onPressed: onChangeMusic,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0369A1),
              foregroundColor: Colors.white,
              side: showHighlight2
                  ? BorderSide(color: lightColor, width: 3.0)
                  : null,
              elevation: showHighlight2 ? 8.0 : null,
            ),
            icon: const Icon(Icons.music_note),
            label: const Text('Change Music'),
          ),
          ElevatedButton.icon(
            onPressed: onStopPlayback,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
              side: showHighlight3
                  ? BorderSide(color: lightColor, width: 3.0)
                  : null,
              elevation: showHighlight3 ? 8.0 : null,
            ),
            icon: const Icon(Icons.stop),
            label: const Text('Stop Playing'),
          ),
          OutlinedButton.icon(
            onPressed: onTalkAboutMusic,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: showHighlight4 ? lightColor : Colors.grey.shade300,
                width: showHighlight4 ? 3.0 : 1.0,
              ),
              backgroundColor: showHighlight4 ? lightColor.withOpacity(0.1) : null,
            ),
            icon: const Icon(Icons.record_voice_over),
            label: const Text('Talk About Music'),
          ),
          OutlinedButton.icon(
            onPressed: onTalkAboutSomethingElse,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: showHighlight5 ? lightColor : Colors.grey.shade300,
                width: showHighlight5 ? 3.0 : 1.0,
              ),
              backgroundColor: showHighlight5 ? lightColor.withOpacity(0.1) : null,
            ),
            icon: const Icon(Icons.forum),
            label: const Text('Talk About Something Else'),
          ),
        ],
      ),
    );
  }
}
