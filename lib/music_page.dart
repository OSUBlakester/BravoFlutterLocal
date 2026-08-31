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

import 'services/apple_music_service.dart';
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

  const MusicPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
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

  // Set to true once the initial playlist load finishes (success or failure).
  // Scanning is blocked until this fires so TTS doesn't announce items before
  // the list is visible on screen.
  bool _playlistsLoaded = false;

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
  AppleMusicService? _appleMusicService;

  // Which music service is active: 'spotify' | 'apple_music'
  String _servicePreference = 'spotify';

  // True while a modal dialog is open — blocks all switch/key handling.
  bool _dialogIsOpen = false;

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
      _appleMusicService = Provider.of<AppleMusicService>(context, listen: false);
      _appleMusicService?.addListener(_onAppleMusicServiceChanged);

      // Clear any stale App Remote / in-flight state from a previous session so
      // playPlaylistUri does not try to disconnect a dropped iOS connection (which
      // can hang) before reconnecting.
      _musicService?.prepareForNewSession();
      _appleMusicService?.prepareForNewSession();

      // Load saved service preference, then initialise whichever service is active.
      unawaited(() async {
        // First launch: no preference saved yet — ask the user which service to use.
        // _startScanningAfterDelay() is called AFTER the dialog so the scanning
        // loop (and its "Connecting to …" TTS) doesn't fire while the picker is open.
        final hasPref = await AppleMusicService.hasServicePreference();
        if (!mounted) return;
        if (!hasPref) {
          final picked = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _ServicePickerDialog(),
          );
          if (!mounted) return;
          // Treat a dismissed dialog (null) as Spotify so the page is never stuck.
          final chosen = picked ?? 'spotify';
          await AppleMusicService.saveServicePreference(chosen);
          setState(() => _servicePreference = chosen);
        }

        final pref = await AppleMusicService.loadServicePreference();
        if (!mounted) return;
        setState(() { _servicePreference = pref; });

        // Start scanning now that _servicePreference is known — the polling loop's
        // TTS announcement will name the correct service (Spotify vs Apple Music).
        _startScanningAfterDelay();

        if (pref == 'apple_music') {
          await _appleMusicService?.loadPlaylists();
        } else {
          await _musicService!.ensureInitialized();
          if (mounted && _musicService!.isConfigured) {
            await _musicService!.refreshPlaylists();
          }
        }
        // Signal that loading is complete so scanning and switch input may begin.
        if (mounted) setState(() => _playlistsLoaded = true);
      }());

      // Keyboard focus only — scanning now starts inside the async block above
      // so it never fires before the service-picker dialog is dismissed.
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
    _appleMusicService?.removeListener(_onAppleMusicServiceChanged);
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
      // Do NOT call _resetAudioRouteToSpeaker() here. forceSpeaker() activates
      // Bravo's AVAudioSession, which steals audio focus from Spotify and causes
      // a ~20 second pause. Audio routing is set immediately before each TTS
      // announcement, so there is no need to set it proactively on play/resume.

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

  void _onAppleMusicServiceChanged() {
    if (!mounted) return;
    final apple = _appleMusicService;
    if (apple == null || _servicePreference != 'apple_music') return;

    if (apple.isPlaying && !_musicIsPlayingState && _scanningPhase == 'controls' && !_isScanning) {
      setState(() {
        _musicIsPlayingState = true;
        _isScanning = false;
        _isScanningPaused = true;
        _waitingForUserInput = true;
        _scanningIndex = -1;
      });
      _scanningTimer?.cancel();
      _scanningTimer = null;
      _startSilenceLoop();
      // Do NOT call _resetAudioRouteToSpeaker() here — same reason as the
      // Spotify listener: forceSpeaker() steals audio focus and interrupts playback.
      _keyboardFocusNode.requestFocus();
    } else if (!apple.isPlaying && _musicIsPlayingState) {
      setState(() { _musicIsPlayingState = false; });
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
      _pollUntilPlaylistsLoadedThenScan();
    });
  }

  // Waits up to 20 s for the initial Spotify connection + playlist fetch to
  // complete before starting the scan cycle.  Announces "Connecting to Spotify"
  // once so the user knows the app is working.  Falls through after the timeout
  // so a network failure does not lock the user out of scanning entirely.
  void _pollUntilPlaylistsLoadedThenScan({int elapsedMs = 0}) {
    if (!mounted) return;
    if (elapsedMs == 0) {
      // Announce loading on first call (TTS may not be ready yet — small delay).
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_playlistsLoaded && _flutterTts != null) {
          final svcName = _servicePreference == 'apple_music' ? 'Apple Music' : 'Spotify';
          unawaited(_flutterTts!.speak('Connecting to $svcName, please wait'));
        }
      });
    }
    if (_playlistsLoaded || elapsedMs >= 20000) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_isAnnouncing) _maybeStartScanning();
      });
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        _pollUntilPlaylistsLoadedThenScan(elapsedMs: elapsedMs + 300);
      });
    }
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
      final playlistsList = _activePlaylists();

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
        if (_scanningIndex > 3) {
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

  // Returns playlist names for whichever service is active.
  List<({String name})> _activePlaylists() {
    if (_servicePreference == 'apple_music') {
      return _appleMusicService?.playlists
              .map((p) => (name: p.name))
              .toList() ??
          [];
    }
    final music = Provider.of<MusicPlaybackService>(context, listen: false);
    final raw = music.playlists.isNotEmpty ? music.playlists : music.fallbackPlaylists;
    return raw.map((p) => (name: p.name)).toList();
  }

  void _announceCurrentButton() async {
    try {
      String text = '';
      if (_scanningPhase == 'playlists') {
        if (_scanningIndex == -1) {
          text = 'Go Back';
        } else {
          final list = _activePlaylists();
          if (_scanningIndex >= 0 && _scanningIndex < list.length) {
            text = list[_scanningIndex].name;
          } else {
            return;
          }
        }
      } else {
        // _scanningPhase == 'controls'
        if (_scanningIndex == 0) {
          text = 'Continue';
        } else if (_scanningIndex == 1) {
          text = 'Skip Song';
        } else if (_scanningIndex == 2) {
          text = 'Change Music';
        } else if (_scanningIndex == 3) {
          text = 'Stop Playing';
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

    // Announce before switching audio route to speaker so the user hears the
    // confirmation through their Bluetooth/personal device while Spotify connects.
    // This is especially important when switching takes 30-60 s.
    if (_flutterTts != null) {
      try {
        await _flutterTts!.speak('Starting ${playlist.name}, please wait');
        // Let the announcement begin before handing audio to Spotify/speaker.
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (_) {}
    }

    await _resetAudioRouteToSpeaker();

    if (!mounted) return;

    _keyboardFocusNode.requestFocus();

    // Reconnect App Remote immediately before playing so the connection is
    // fresh. The initState reconnect drops before the user picks a playlist,
    // causing playPlaylistUri() to fall through the full 30-60s timeout chain.
    // Calling here means: still-connected → instant (Swift singleton guard returns
    // true immediately); dropped → ~3s fresh reconnect. Either way, playPlaylistUri()
    // then takes the fast direct-play path instead of the reconnect cascade.
    await music.ensureAppRemoteConnected();

    if (!mounted) return;
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

  Future<void> _selectAppleMusicPlaylist(ApplePlaylist playlist) async {
    _currentSpeechId++;
    _flutterTts?.stop();
    _pauseScanning();
    setState(() {
      _scanningPhase = 'controls';
      _musicIsPlayingState = true;
      _scanningIndex = -1;
    });
    final apple = Provider.of<AppleMusicService>(context, listen: false);
    await _resetAudioRouteToSpeaker();
    if (!mounted) return;
    _keyboardFocusNode.requestFocus();
    await apple.playPlaylist(playlist);
    if (mounted && !apple.isPlaying) {
      setState(() {
        _scanningPhase = 'playlists';
        _musicIsPlayingState = false;
      });
      _startScanning(force: true);
    } else {
      await _startSilenceLoop();
    }
    if (mounted) _keyboardFocusNode.requestFocus();
  }

  void _handlePauseResume() async {
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    if (_servicePreference == 'apple_music') {
      final apple = Provider.of<AppleMusicService>(context, listen: false);
      if (apple.isPlaying) {
        await apple.pause();
      } else {
        await apple.resume();
        // Do NOT call _resetAudioRouteToSpeaker() here — forceSpeaker() activates
        // Bravo's AVAudioSession which steals audio focus and pauses the music.
        // Audio routing is set right before each TTS announcement instead.
      }
    } else {
      final music = Provider.of<MusicPlaybackService>(context, listen: false);
      if (music.isPlaying) {
        await music.pause();
      } else {
        await music.resume();
        // Do NOT call _resetAudioRouteToSpeaker() here — same reason as above.
      }
    }
  }

  void _handleSkipNext() async {
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    // Do NOT call _resetAudioRouteToSpeaker() here — forceSpeaker() steals audio
    // focus mid-playback and interrupts Spotify. Route is set before TTS instead.
    if (_servicePreference == 'apple_music') {
      await Provider.of<AppleMusicService>(context, listen: false).skipNext();
    } else {
      await Provider.of<MusicPlaybackService>(context, listen: false).skipNext();
    }
  }

  void _handleStopPlayback() async {
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    if (_servicePreference == 'apple_music') {
      await Provider.of<AppleMusicService>(context, listen: false).stopPlayback();
    } else {
      await Provider.of<MusicPlaybackService>(context, listen: false).stopPlayback();
    }
    setState(() {
      _scanningPhase = 'playlists';
      _musicIsPlayingState = false;
      _scanningIndex = -1;
    });
    await _stopSilenceLoop();
    _handleBackButton();
  }

  void _handleChangeMusic() async {
    _pauseScanning();
    _keyboardFocusNode.requestFocus();
    if (_servicePreference == 'apple_music') {
      await Provider.of<AppleMusicService>(context, listen: false).stopPlayback();
    } else {
      await Provider.of<MusicPlaybackService>(context, listen: false).stopPlayback();
    }
    setState(() {
      _scanningPhase = 'playlists';
      _musicIsPlayingState = false;
      _scanningIndex = -1;
    });
    await _stopSilenceLoop();
    _startScanning(force: true);
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
    }
  }

  Future<void> _handleSpacebarPress() async {
    debugPrint('MusicPage: Spacebar pressed - _waitingForUserInput=$_waitingForUserInput, _isScanningPaused=$_isScanningPaused, _isScanning=$_isScanning, _scanningIndex=$_scanningIndex, _scanningPhase=$_scanningPhase');
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    // Block all switch input until the initial Spotify connection and playlist
    // load are complete.  Premature input during this window leaves the state
    // machine inconsistent (scanning starts before music is ready, _onMusicServiceChanged
    // is ignored because _isScanning=true, controls phase becomes unresponsive).
    if (!_playlistsLoaded) {
      debugPrint('MusicPage: Spacebar blocked — Spotify still loading (playlistsLoaded=$_playlistsLoaded)');
      return;
    }

    // Block switch input while a playlist is loading / App Remote is reconnecting.
    // Presses during this window set _isScanning=true which breaks the state machine
    // once playback eventually starts (_onMusicServiceChanged is ignored).
    if (_servicePreference != 'apple_music') {
      final music = Provider.of<MusicPlaybackService>(context, listen: false);
      if (music.isReconnecting) {
        debugPrint('MusicPage: Spacebar blocked — playlist loading in progress (isReconnecting=true)');
        return;
      }
    }

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
        if (_servicePreference == 'apple_music') {
          final apple = Provider.of<AppleMusicService>(context, listen: false);
          if (apple.isPlaying) unawaited(apple.pauseForScanning());
        } else {
          final music = Provider.of<MusicPlaybackService>(context, listen: false);
          if (music.isPlaying) unawaited(music.pauseForScanning());
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
        // Give Spotify a moment to process the pause command before TTS begins.
        // pauseForScanning() is fire-and-forget above — without this gap the TTS
        // announcement overlaps with still-playing music when the App Remote is slow.
        await Future.delayed(const Duration(milliseconds: 700));
        debugPrint('MusicPage: _handleSpacebarPress announcing current button');
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
      } else if (_servicePreference == 'apple_music') {
        final apple = Provider.of<AppleMusicService>(context, listen: false);
        if (_scanningIndex >= 0 && _scanningIndex < apple.playlists.length) {
          _selectAppleMusicPlaylist(apple.playlists[_scanningIndex]);
        }
      } else {
        final music = Provider.of<MusicPlaybackService>(context, listen: false);
        final playlistsList = music.playlists.isNotEmpty ? music.playlists : music.fallbackPlaylists;
        if (_scanningIndex >= 0 && _scanningIndex < playlistsList.length) {
          _selectPlaylistAndStartPlayback(playlistsList[_scanningIndex]);
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
      ).timeout(const Duration(seconds: 5));
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

  void _showMusicSettingsDialog(BuildContext context) {
    _pauseScanning();
    setState(() { _dialogIsOpen = true; });
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MusicSettingsDialog(
        initialService: _servicePreference,
      ),
    ).then((saved) {
      if (!mounted) return;
      setState(() { _dialogIsOpen = false; });
      if (saved == null) return;
      setState(() { _servicePreference = saved; });
      if (saved == 'apple_music') _appleMusicService?.loadPlaylists();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(saved == 'apple_music' ? 'Switched to Apple Music.' : 'Spotify settings saved.')),
      );
    });
  }

  void _handleRawKey(RawKeyEvent event) {
    if (_dialogIsOpen || ModalRoute.of(context)?.isCurrent == false) {
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
    final apple = context.watch<AppleMusicService>();
    final usingApple = _servicePreference == 'apple_music';

    final String? activeError = usingApple ? apple.lastError : music.lastError;
    final bool activeIsInfo = usingApple ? false : music.webApiForbidden;
    final String? activeTrack = usingApple ? apple.currentTrack : music.currentTrack;
    final String? activeArtist = usingApple ? apple.currentArtist : music.currentArtist;
    final String? activePlaylist = usingApple ? apple.currentPlaylistName : music.currentPlaylistName;
    final bool activeIsPlaying = usingApple ? apple.isPlaying : music.isPlaying;

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
                tooltip: 'Music Settings',
                onPressed: () => _showMusicSettingsDialog(context),
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StatusBanner(
                  // During initial load show "Connecting to Spotify..." with a
                  // spinner rather than an error — isLoading covers the window
                  // between page open and the first playlistsLoaded signal.
                  errorText: (!usingApple && music.isLoading)
                      ? 'Connecting to Spotify...'  // shown only when usingApple=false
                      : activeError,
                  isInfo: activeIsInfo,
                  isReconnecting: !usingApple && (music.isReconnecting || music.isLoading),
                ),
                _NowPlayingCard(
                  currentTrack: activeTrack,
                  currentArtist: activeArtist,
                  currentPlaylistName: activePlaylist,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      usingApple
                          ? _AppleMusicContent(
                              apple: apple,
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
                              handleBackButton: _handleBackButton,
                              onPlaylistSelected: _selectAppleMusicPlaylist,
                            )
                          : _MusicContent(
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
                      // Full-area loading overlay shown while Spotify is connecting
                      // or switching playlists — more visible than the top banner.
                      if (!usingApple && music.isReconnecting)
                        Container(
                          color: Colors.black54,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    music.lastError ?? 'Starting playlist...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _ControlBar(
                  isPlaying: activeIsPlaying,
                  isScanning: _isScanning,
                  scanningIndex: _scanningIndex,
                  scanningPhase: _scanningPhase,
                  lightColor: _lightColor,
                  darkColor: _darkColor,
                  onPauseResume: _handlePauseResume,
                  onSkipNext: _handleSkipNext,
                  onStopPlayback: _handleStopPlayback,
                  onChangeMusic: _handleChangeMusic,
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
  final bool isReconnecting;

  const _StatusBanner({
    required this.errorText,
    this.isInfo = false,
    this.isReconnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    if (errorText == null || errorText!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    // Three visual states:
    //   isReconnecting → neutral blue spinner (working, not an error)
    //   isInfo         → blue info icon (informational)
    //   default        → orange warning icon (actual error)
    final Color bgColor = isReconnecting
        ? const Color(0xFFEFF6FF)
        : isInfo
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFFFF2EE);
    final Color borderColor = isReconnecting
        ? const Color(0xFF93C5FD)
        : isInfo
            ? const Color(0xFFBFDBFE)
            : const Color(0xFFFFB49F);
    final Color textColor = isReconnecting
        ? const Color(0xFF1E40AF)
        : isInfo
            ? const Color(0xFF1E3A8A)
            : const Color(0xFF7A2E0E);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          if (isReconnecting)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
              ),
            )
          else
            Icon(
              isInfo ? Icons.info_outline : Icons.warning_amber_rounded,
              color: isInfo ? const Color(0xFF1E40AF) : const Color(0xFFB54708),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorText!,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final String? currentTrack;
  final String? currentArtist;
  final String? currentPlaylistName;

  const _NowPlayingCard({
    this.currentTrack,
    this.currentArtist,
    this.currentPlaylistName,
  });

  @override
  Widget build(BuildContext context) {
    final title = currentTrack?.trim().isNotEmpty == true
        ? currentTrack!
        : 'Nothing playing';

    final subtitleParts = <String>[];
    if (currentArtist?.trim().isNotEmpty == true) {
      subtitleParts.add(currentArtist!);
    }
    if (currentPlaylistName?.trim().isNotEmpty == true) {
      subtitleParts.add('Playlist: $currentPlaylistName');
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
    const spacing = 10.0;
    const gridPadding = 20.0;

    // Never use more columns than there are buttons — prevents tiny invisible tiles
    // when only a handful of fallback playlists are shown on a wide grid setting.
    final effectiveColumns = allButtons.length.clamp(1, gridColumns);
    double effectiveButtonSize = (availableWidth / effectiveColumns).clamp(40.0, buttonSize);
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
                  crossAxisCount: effectiveColumns,
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
  final bool isPlaying;
  final bool isScanning;
  final int scanningIndex;
  final String scanningPhase;
  final Color lightColor;
  final Color darkColor;
  final VoidCallback onPauseResume;
  final VoidCallback onSkipNext;
  final VoidCallback onStopPlayback;
  final VoidCallback onChangeMusic;

  const _ControlBar({
    required this.isPlaying,
    required this.isScanning,
    required this.scanningIndex,
    required this.scanningPhase,
    required this.lightColor,
    required this.darkColor,
    required this.onPauseResume,
    required this.onSkipNext,
    required this.onStopPlayback,
    required this.onChangeMusic,
  });

  @override
  Widget build(BuildContext context) {
    final bool isControlsPhase = scanningPhase == 'controls';
    final bool showHighlight0 = isControlsPhase && isScanning && scanningIndex == 0;
    final bool showHighlight1 = isControlsPhase && isScanning && scanningIndex == 1;
    final bool showHighlight2 = isControlsPhase && isScanning && scanningIndex == 2;
    final bool showHighlight3 = isControlsPhase && isScanning && scanningIndex == 3;

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
            icon: Icon((isPlaying && !isScanning) ? Icons.pause : Icons.play_arrow),
            label: Text((isPlaying && !isScanning) ? 'Pause' : 'Continue'),
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
        ],
      ),
    );
  }
}

// Shown on the very first Music page launch when no service preference has been
// saved. Cannot be dismissed without picking a service — barrierDismissible: false.
class _ServicePickerDialog extends StatefulWidget {
  const _ServicePickerDialog();

  @override
  State<_ServicePickerDialog> createState() => _ServicePickerDialogState();
}

class _ServicePickerDialogState extends State<_ServicePickerDialog> {
  String _selected = 'spotify';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.music_note, color: Color(0xFF0369A1)),
          SizedBox(width: 8),
          Text('Choose Music Service'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Which music service would you like to use?',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ServiceToggleButton(
                  label: 'Spotify',
                  icon: Icons.music_note,
                  selected: _selected == 'spotify',
                  onTap: () => setState(() => _selected = 'spotify'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ServiceToggleButton(
                  label: 'Apple Music',
                  icon: Icons.apple,
                  selected: _selected == 'apple_music',
                  onTap: () => setState(() => _selected = 'apple_music'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _selected == 'apple_music'
                ? 'Uses your device\'s Music library. Allow access under Settings > Privacy & Security > Media & Apple Music.'
                : 'Plays music from your Spotify account. You\'ll be prompted to connect Spotify on the next screen.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0369A1),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Get Started'),
        ),
      ],
    );
  }
}

class _MusicSettingsDialog extends StatefulWidget {
  final String initialService;

  const _MusicSettingsDialog({required this.initialService});

  @override
  State<_MusicSettingsDialog> createState() => _MusicSettingsDialogState();
}

class _MusicSettingsDialogState extends State<_MusicSettingsDialog> {
  late String _selectedService;

  @override
  void initState() {
    super.initState();
    _selectedService = widget.initialService;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.settings, color: Color(0xFF0369A1)),
          SizedBox(width: 8),
          Text('Music Settings'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Music Service', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ServiceToggleButton(
                  label: 'Spotify',
                  icon: Icons.music_note,
                  selected: _selectedService == 'spotify',
                  onTap: () => setState(() => _selectedService = 'spotify'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ServiceToggleButton(
                  label: 'Apple Music',
                  icon: Icons.apple,
                  selected: _selectedService == 'apple_music',
                  onTap: () => setState(() => _selectedService = 'apple_music'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _selectedService == 'apple_music'
                ? 'Uses your device\'s Music library. Allow access under Settings > Privacy & Security > Media & Apple Music.'
                : 'Plays music from your Spotify account.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    await AppleMusicService.saveServicePreference(_selectedService);
    if (mounted) Navigator.of(context).pop(_selectedService);
  }
}

class _ServiceToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ServiceToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0369A1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF0369A1) : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleMusicContent extends StatelessWidget {
  final AppleMusicService apple;
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
  final VoidCallback handleBackButton;
  final Function(ApplePlaylist) onPlaylistSelected;

  const _AppleMusicContent({
    required this.apple,
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
    required this.handleBackButton,
    required this.onPlaylistSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (apple.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (apple.lastError != null && apple.playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apple, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(apple.lastError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: apple.loadPlaylists,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final allButtons = [
      {'name': 'Go Back', 'isBackButton': true},
      ...apple.playlists.map((p) => {'name': p.name, 'isBackButton': false, 'playlist': p}),
    ];

    final availableWidth = MediaQuery.of(context).size.width - 40;
    const spacing = 10.0;
    const gridPadding = 20.0;
    final effectiveButtonSize = (availableWidth / gridColumns).clamp(40.0, buttonSize);
    final fontSize = ((effectiveButtonSize / 10) * 1.44).clamp(14.4, 25.9);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: apple.loadPlaylists,
                icon: const Icon(Icons.queue_music),
                label: const Text('Refresh Playlists'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(gridPadding),
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
                  final buttonScanIndex = isBackButton ? -1 : index - 1;
                  final isHighlighted = scanningPhase == 'playlists' &&
                      buttonScanIndex == scanningIndex &&
                      (isScanning || isScanningPaused);

                  return Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: SizedBox(
                      width: effectiveButtonSize,
                      height: effectiveButtonSize,
                      child: SpeechBubbleButton(
                        label: label,
                        onPressed: () {
                          if (isScanningPaused && !isScanning && scanningPhase == 'playlists') {
                            resumeScanning();
                          } else if (isBackButton) {
                            handleBackButton();
                          } else {
                            onPlaylistSelected(button['playlist'] as ApplePlaylist);
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
