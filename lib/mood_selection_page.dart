import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'services/user_settings_provider.dart';
import 'constants/mood_options.dart';
import 'config/environment_config.dart';
import 'services/mood_image_service.dart';
import 'services/authenticated_http_client.dart';
import 'main.dart'; // Import GridPage from main.dart
import 'tap_interface_page.dart'; // Import TapInterfacePage directly

class MoodSelectionPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;

  const MoodSelectionPage({
    Key? key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
  }) : super(key: key);

  @override
  State<MoodSelectionPage> createState() => _MoodSelectionPageState();
}

class _MoodSelectionPageState extends State<MoodSelectionPage> {
  static const _translations = <String, Map<String, String>>{
    'How are you feeling?': {
      'es-US': '¿Cómo te sientes?',
      'fr-FR': 'Comment vous sentez-vous ?',
      'de-DE': 'Wie fühlst du dich?',
      'it-IT': 'Come ti senti?',
      'pt-BR': 'Como você está se sentindo?',
      'ar-XA': 'كيف تشعر؟',
    },
    'Select your current mood:': {
      'es-US': 'Selecciona tu estado de ánimo:',
      'fr-FR': 'Sélectionnez votre humeur :',
      'de-DE': 'Wähle deine aktuelle Stimmung:',
      'it-IT': 'Seleziona il tuo umore attuale:',
      'pt-BR': 'Selecione seu humor atual:',
      'ar-XA': 'اختر حالتك المزاجية الحالية:',
    },
    'Tap a mood to continue, or tap Skip to proceed without selecting a mood.': {
      'es-US': 'Toca un estado de ánimo o toca Omitir para continuar sin seleccionar.',
      'fr-FR': 'Appuyez sur une humeur ou sur Ignorer pour continuer sans en choisir.',
      'de-DE': 'Tippe auf eine Stimmung oder auf Überspringen, um ohne Auswahl fortzufahren.',
      'it-IT': 'Tocca un umore o tocca Salta per continuare senza selezionarne uno.',
      'pt-BR': 'Toque em um humor ou em Pular para continuar sem selecionar.',
      'ar-XA': 'اضغط على حالة مزاجية أو اضغط تخطى للمتابعة بدون اختيار.',
    },
    'Auditory scanning is active. Press spacebar or tap to select the highlighted option.': {
      'es-US': 'Escaneo auditivo activo. Presiona la barra espaciadora o toca para seleccionar.',
      'fr-FR': 'Balayage auditif actif. Appuyez sur la barre d\'espace ou touchez pour sélectionner.',
      'de-DE': 'Auditive Abtastung aktiv. Drücke die Leertaste oder tippe, um auszuwählen.',
      'it-IT': 'Scansione uditiva attiva. Premi la barra spaziatrice o tocca per selezionare.',
      'pt-BR': 'Varredura auditiva ativa. Pressione a barra de espaço ou toque para selecionar.',
      'ar-XA': 'المسح السمعي نشط. اضغط المسافة أو المس للاختيار.',
    },
    'Press switch to begin scanning': {
      'es-US': 'Presiona el interruptor para comenzar el escaneo',
      'fr-FR': 'Appuyez sur le commutateur pour commencer le balayage',
      'de-DE': 'Schalter drücken, um das Abtasten zu starten',
      'it-IT': 'Premi l\'interruttore per avviare la scansione',
      'pt-BR': 'Pressione o interruptor para iniciar a varredura',
      'ar-XA': 'اضغط المفتاح لبدء المسح',
    },
    'Happy': {'es-US': 'Feliz', 'fr-FR': 'Joyeux', 'de-DE': 'Froh', 'it-IT': 'Felice', 'pt-BR': 'Feliz', 'ar-XA': 'سعيد'},
    'Sad': {'es-US': 'Triste', 'fr-FR': 'Triste', 'de-DE': 'Traurig', 'it-IT': 'Triste', 'pt-BR': 'Triste', 'ar-XA': 'حزين'},
    'Excited': {'es-US': 'Emocionado', 'fr-FR': 'Enthousiaste', 'de-DE': 'Aufgeregt', 'it-IT': 'Entusiasta', 'pt-BR': 'Animado', 'ar-XA': 'متحمس'},
    'Calm': {'es-US': 'Tranquilo', 'fr-FR': 'Calme', 'de-DE': 'Ruhig', 'it-IT': 'Calmo', 'pt-BR': 'Calmo', 'ar-XA': 'هادئ'},
    'Angry': {'es-US': 'Enojado', 'fr-FR': 'En colère', 'de-DE': 'Wütend', 'it-IT': 'Arrabbiato', 'pt-BR': 'Com raiva', 'ar-XA': 'غاضب'},
    'Silly': {'es-US': 'Tontito', 'fr-FR': 'Rigolo', 'de-DE': 'Albern', 'it-IT': 'Sciocco', 'pt-BR': 'Bobo', 'ar-XA': 'مضحك'},
    'Tired': {'es-US': 'Cansado', 'fr-FR': 'Fatigué', 'de-DE': 'Müde', 'it-IT': 'Stanco', 'pt-BR': 'Cansado', 'ar-XA': 'متعب'},
    'Bored': {'es-US': 'Aburrido', 'fr-FR': 'Ennuyé', 'de-DE': 'Gelangweilt', 'it-IT': 'Annoiato', 'pt-BR': 'Entediado', 'ar-XA': 'ممل'},
    'Anxious': {'es-US': 'Ansioso', 'fr-FR': 'Anxieux', 'de-DE': 'Ängstlich', 'it-IT': 'Ansioso', 'pt-BR': 'Ansioso', 'ar-XA': 'قلق'},
    'Confused': {'es-US': 'Confundido', 'fr-FR': 'Confus', 'de-DE': 'Verwirrt', 'it-IT': 'Confuso', 'pt-BR': 'Confuso', 'ar-XA': 'مرتبك'},
    'Surprised': {'es-US': 'Sorprendido', 'fr-FR': 'Surpris', 'de-DE': 'Überrascht', 'it-IT': 'Sorpreso', 'pt-BR': 'Surpreso', 'ar-XA': 'متفاجئ'},
    'Proud': {'es-US': 'Orgulloso', 'fr-FR': 'Fier', 'de-DE': 'Stolz', 'it-IT': 'Orgoglioso', 'pt-BR': 'Orgulhoso', 'ar-XA': 'فخور'},
    'Worried': {'es-US': 'Preocupado', 'fr-FR': 'Inquiet', 'de-DE': 'Besorgt', 'it-IT': 'Preoccupato', 'pt-BR': 'Preocupado', 'ar-XA': 'قلق'},
    'Cranky': {'es-US': 'Malhumorado', 'fr-FR': 'Grincheux', 'de-DE': 'Griesgrämig', 'it-IT': 'Scontroso', 'pt-BR': 'Mal-humorado', 'ar-XA': 'سريع الغضب'},
    'Peaceful': {'es-US': 'En paz', 'fr-FR': 'Paisible', 'de-DE': 'Friedlich', 'it-IT': 'Pacifico', 'pt-BR': 'Pacífico', 'ar-XA': 'مسالم'},
    'Playful': {'es-US': 'Juguetón', 'fr-FR': 'Joueur', 'de-DE': 'Verspielt', 'it-IT': 'Giocoso', 'pt-BR': 'Brincalhão', 'ar-XA': 'مرح'},
    'Frustrated': {'es-US': 'Frustrado', 'fr-FR': 'Frustré', 'de-DE': 'Frustriert', 'it-IT': 'Frustrato', 'pt-BR': 'Frustrado', 'ar-XA': 'محبط'},
    'Curious': {'es-US': 'Curioso', 'fr-FR': 'Curieux', 'de-DE': 'Neugierig', 'it-IT': 'Curioso', 'pt-BR': 'Curioso', 'ar-XA': 'فضولي'},
    'Grateful': {'es-US': 'Agradecido', 'fr-FR': 'Reconnaissant', 'de-DE': 'Dankbar', 'it-IT': 'Grato', 'pt-BR': 'Grato', 'ar-XA': 'ممتنن'},
    'Lonely': {'es-US': 'Solo', 'fr-FR': 'Seul', 'de-DE': 'Einsam', 'it-IT': 'Solo', 'pt-BR': 'Solitário', 'ar-XA': 'وحيد'},
    'Content': {'es-US': 'Satisfecho', 'fr-FR': 'Content', 'de-DE': 'Zufrieden', 'it-IT': 'Contento', 'pt-BR': 'Satisfeito', 'ar-XA': 'راضٍ'},
    'Skip': {'es-US': 'Omitir', 'fr-FR': 'Ignorer', 'de-DE': 'Überspringen', 'it-IT': 'Salta', 'pt-BR': 'Pular', 'ar-XA': 'تخطى'},
  };

  String _t(String key) {
    final provider = Provider.of<UserSettingsProvider>(context, listen: false);
    final locale = provider.settings?.userLanguage ?? 'en-US';
    return _translations[key]?[locale] ?? key;
  }
  // Wait-for-switch feature tracking
  bool _waitingForInitialSwitch = false;
  bool _switchStartRequested = false;
  
  // Auditory scanning state
  int? scanningIndex;
  Timer? scanningTimer;
  bool isScanning = false;
  bool _isAnnouncingScanningPrompt = false;  // Track if announcing during scanning prompts (for Tab interrupt)
  
  // TTS for voice output
  late FlutterTts flutterTts;
  
  // Focus node for keyboard handling
  FocusNode? moodFocusNode;
  
  // Currently selected mood
  String? _selectedMoodName;
  
  // List of all options including moods + skip
  List<Map<String, String>> allOptions = [];

  @override
  void initState() {
    super.initState();
    debugPrint('🟣 MoodSelectionPage initState() START');
    flutterTts = FlutterTts();
    debugPrint('🟣 MoodSelectionPage FlutterTts created');
    moodFocusNode = FocusNode();
    debugPrint('🟣 MoodSelectionPage FocusNode created');
    _setupMoodOptions();
    debugPrint('🟣 MoodSelectionPage mood options setup complete');
    _preloadMoodImages();
    debugPrint('🟣 MoodSelectionPage preload images initiated');
    
    // Initialize selected mood from settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🟣 MoodSelectionPage postFrameCallback START');
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      if (settingsProvider.settings?.currentMood != null) {
        setState(() {
          _selectedMoodName = settingsProvider.settings!.currentMood;
        });
      }
      debugPrint('🟣 MoodSelectionPage about to call _maybeStartScanning()');
      _maybeStartScanning();
      debugPrint('🟣 MoodSelectionPage _maybeStartScanning() returned');
    });
    debugPrint('🟣 MoodSelectionPage initState() END');
  }

  @override
  void dispose() {
    scanningTimer?.cancel();
    moodFocusNode?.dispose();
    flutterTts.stop();
    super.dispose();
  }

  void _setupMoodOptions() {
    // Copy mood options and add skip option
    allOptions = List.from(MoodOptions.moodOptions);
    allOptions.add({'name': 'Skip', 'emoji': '⏭️'});
  }

  void _preloadMoodImages() {
    // Preload mood images in background for better performance
    final moodNames = MoodOptions.moodOptions.map((mood) => mood['name']!).toList();
    MoodImageService().preloadMoodImages(moodNames).then((_) {
      debugPrint('MoodSelection: Mood images preloaded successfully');
    }).catchError((error) {
      debugPrint('MoodSelection: Error preloading mood images: $error');
    });
  }

  void _maybeStartScanning() {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final enableScanning = settingsProvider.settings?.enableAuditoryScanning ?? false;
    final waitForSwitch = settingsProvider.settings?.waitForSwitchToScan ?? false;
    final useTapInterface = settingsProvider.settings?.useTapInterface ?? false;
    
    debugPrint('MoodSelection: enableScanning = $enableScanning, waitForSwitch = $waitForSwitch, useTapInterface = $useTapInterface');

    // REQUIREMENT: When Tap Interface is enabled, Mood Selection should not scan options.
    if (useTapInterface) {
      _stopAuditoryScanning();
      if (_waitingForInitialSwitch || _switchStartRequested) {
        setState(() {
          _waitingForInitialSwitch = false;
          _switchStartRequested = false;
        });
      }
      debugPrint('MoodSelection: Scanning disabled because Tap Interface is enabled');
      return;
    }
    
    if (!enableScanning || allOptions.isEmpty) {
      return;
    }
    
    // Check if we should wait for switch press before starting (applies to every navigation)
    if (waitForSwitch && !isScanning && !_waitingForInitialSwitch) {
      debugPrint('MoodSelection: Waiting for switch press to begin scanning...');
      setState(() {
        _waitingForInitialSwitch = true;
        _switchStartRequested = false;
      });
      // First spoken guidance happens once per session; later waits use a short notification sound.
      if (!hasPlayedInitialWaitForSwitchVoicePrompt) {
        unawaited(() async {
          await _speakSystemVoice(_t('Press switch to begin scanning'));
          await _playWaitForSwitchNotification();
        }());
        hasPlayedInitialWaitForSwitchVoicePrompt = true;
      } else {
        unawaited(_playWaitForSwitchNotification());
      }
      
      return; // IMPORTANT: Don't start scanning yet, wait for switch press
    }
    
    // Start scanning immediately (either wait-for-switch is disabled, or already waiting)
    debugPrint('MoodSelection: Starting scanning');
    _startAuditoryScanning();
  }

  void _startAuditoryScanning() {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final waitForSwitch = settingsProvider.settings?.waitForSwitchToScan ?? false;

    if (waitForSwitch && !_switchStartRequested) {
      debugPrint('MoodSelection: Switch not pressed, blocking scanning');
      return;
    }

    if (_waitingForInitialSwitch) {
      debugPrint('MoodSelection: Waiting for switch press, blocking scanning');
      return;
    }
    
    if (isScanning) return;
    
    debugPrint('MoodSelection: Starting auditory scanning...');
    
    setState(() {
      isScanning = true;
      scanningIndex = -1; // Step mode waits for first Tab before selecting first option
      _switchStartRequested = false;
    });

    // Start scanning behavior based on mode
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    
    debugPrint('MoodSelection: Scan mode: $scanMode');
    
    if (scanMode == 'auto') {
      debugPrint('MoodSelection: Starting first scan step + timer for auto mode...');
      _scanStep();
    } else {
      debugPrint('MoodSelection: Step mode - waiting for first Tab, timer not started');
    }
  }

  void _stopAuditoryScanning() {
    scanningTimer?.cancel();
    setState(() {
      isScanning = false;
      scanningIndex = null;
    });
  }

  void _scanStep() {
    if (!isScanning || allOptions.isEmpty) return;
    
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    final scanDelay = settingsProvider.settings?.scanDelay ?? 3500;
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    scanningTimer?.cancel();

    setState(() {
      scanningIndex = ((scanningIndex ?? -1) + 1) % allOptions.length;
    });
    
    // Speak the current option
    if (scanningIndex != null && scanningIndex! >= 0 && scanningIndex! < allOptions.length) {
      final currentOption = allOptions[scanningIndex!];
      _speakSystemVoice(_t(currentOption['name']!));
    }

    if (scanMode == 'auto') {
      scanningTimer = Timer(Duration(milliseconds: scanDelay), () {
        if (!mounted || !isScanning) return;
        _scanStep();
      });
    }
  }

  Future<int> _getEffectivePersonalVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        'MoodSelection: Using LOCAL personal volume override: $overrideValue/10',
      );
      return overrideValue;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final settingsValue = settingsProvider.settings?.personalVolume ?? 10;
    debugPrint(
      'MoodSelection: Using SETTINGS personal volume: $settingsValue/10',
    );
    return settingsValue;
  }

  Future<void> _speakSystemVoice(String text) async {
    debugPrint('MoodSelection: _speakSystemVoice: Starting TTS for: $text');
    
    try {
      setState(() {
        _isAnnouncingScanningPrompt = true;
      });
      
      // Use simple local TTS for mood selection scanning
      await flutterTts.stop();
      // Ensure awaited calls to _speakSystemVoice complete only after speech
      // playback actually finishes (important before playing notification chime).
      await flutterTts.awaitSpeakCompletion(true);
      // Configure TTS for Fire tablet compatibility  
      await flutterTts.setSpeechRate(0.5); // Slower speech for clarity
      
      // Get personalVolume from global settings (scanning uses personal volume, not system)
      final personalVolume = await _getEffectivePersonalVolume();
      final ttsVolume = (personalVolume / 10.0).clamp(0.0, 1.0);
      debugPrint('MoodSelection: Using personalVolume: $personalVolume/10 - TTS volume: $ttsVolume (scanning)');
      await flutterTts.setVolume(ttsVolume);
      
      await flutterTts.setPitch(1.0); // Normal pitch
      debugPrint('MoodSelection: _speakSystemVoice: Configured TTS settings');
      // Skip setVoice to avoid Fire tablet TTS voice errors
      await flutterTts.speak(text);
      debugPrint('MoodSelection: _speakSystemVoice: TTS speak() completed successfully');
    } catch (e) {
      debugPrint('MoodSelection: _speakSystemVoice: TTS ERROR - $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
    }
  }

  Future<void> _playWaitForSwitchNotification() async {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final playChime =
        settingsProvider.settings?.playWaitForSwitchChime ?? false;
    if (!playChime) {
      debugPrint('MoodSelection: wait notification chime disabled in settings');
      return;
    }

    final player = AudioPlayer();
    try {
      final personalVolume = await _getEffectivePersonalVolume();
      const chimeCompensation = 0.18;
      const chimeMaxCap = 0.16;
      const chimeMinFloor = 0.10;
      final chimeVolume = ((personalVolume / 10.0) * chimeCompensation)
          .clamp(chimeMinFloor, chimeMaxCap);

      debugPrint(
        'MoodSelection: wait notification volume from personal $personalVolume/10 -> $chimeVolume',
      );

      // Give the TTS engine a short moment to release focus before chime.
      await Future.delayed(const Duration(milliseconds: 200));

      await player.setAsset('assets/notification.mp3');
      await player.setVolume(chimeVolume);
      await player.play();
      await player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('MoodSelection: Error playing wait notification: $e');
    } finally {
      await player.dispose();
    }
  }

  /// Save mood to user info API so it's included in LLM context
  Future<void> _saveMoodToUserInfo(String mood) async {
    try {
      // First get current user info to preserve it
      final getCurrentResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/user-info',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      
      String currentUserInfo = "";
      if (getCurrentResponse.statusCode == 200) {
        final current = json.decode(getCurrentResponse.body);
        currentUserInfo = current['userInfo'] ?? current['narrative'] ?? "";
      }
      
      // Save mood along with existing user info to the user-info API
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/user-info',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'narrative': currentUserInfo,
          'currentMood': mood,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('MoodSelection: Successfully saved mood "$mood" to user info API');
      } else {
        debugPrint('MoodSelection: Failed to save mood to user info API: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('MoodSelection: Error saving mood to user info API: $error');
    }
  }

  Future<void> _selectMood(String moodName) async {
    debugPrint('MoodSelection: Selected mood: $moodName');
    
    // Update UI immediately to show selection
    setState(() {
      _selectedMoodName = moodName;
    });
    
    // Stop scanning
    _stopAuditoryScanning();
    
    // Add delay to allow any ongoing audio to complete before navigation
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('MoodSelection: Audio cleanup delay completed');
    
    // Update settings if mood was selected (not skipped)
    if (moodName != 'Skip') {
      final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
      if (settingsProvider.settings != null) {
        // Update local state immediately
        settingsProvider.updateSettings((s) => s.currentMood = moodName);
        debugPrint('MoodSelection: Saved mood: $moodName to settings');
      }
      
      // CRITICAL: Save mood to user info API so it's included in LLM context
      await _saveMoodToUserInfo(moodName);
    }
    
    // Additional delay before navigation to ensure audio routing is clear
    await Future.delayed(const Duration(milliseconds: 300));
    debugPrint('MoodSelection: Pre-navigation delay completed');
    
    // Navigate back to previous page or to GridPage if this is initial mood selection
    if (mounted) {
      // Check if we can pop (meaning we came from another page)
      if (Navigator.of(context).canPop()) {
        // This was called as a special page button - just go back
        Navigator.of(context).pop();
      } else {
        // This is initial mood selection - navigate to appropriate interface based on user preference
        final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
        final useTapInterface = settingsProvider.settings?.useTapInterface ?? false;
        
        if (useTapInterface) {
          debugPrint('MoodSelection: Navigating directly to TapInterfacePage');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TapInterfacePage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
              ),
            ),
          );
        } else {
          debugPrint('MoodSelection: Navigating to GridPage');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GridPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildMoodButton(Map<String, String> mood, int index) {
    final isScanning = this.isScanning && scanningIndex == index;
    final moodName = mood['name']!;
    final emoji = mood['emoji']!;
    final isSelected = moodName == _selectedMoodName;
    
    return Container(
      margin: const EdgeInsets.all(4),
      child: ElevatedButton(
        onPressed: () => _selectMood(moodName),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected 
              ? Colors.green[100] 
              : (isScanning ? Colors.blue[100] : Colors.white),
          foregroundColor: isSelected
              ? Colors.green[900]
              : (isScanning ? Colors.blue[800] : Colors.black87),
          elevation: (isScanning || isSelected) ? 8 : 2,
          padding: EdgeInsets.zero, // Remove padding for full bleed effect
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected 
                  ? Colors.green 
                  : (isScanning ? Colors.blue : Colors.grey[300]!),
              width: (isScanning || isSelected) ? 4 : 1,
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Image Layer - shifted up to make room for text
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0, top: 4.0, left: 4.0, right: 4.0),
              child: FutureBuilder<String?>(
                future: MoodImageService().getMoodImageUrl(moodName),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    // Show emoji while loading
                    return Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                    );
                  } else if (snapshot.hasData && snapshot.data != null) {
                    // Show mascot image
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return Center(
                          child: Image.network(
                            snapshot.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              // Fallback to emoji on image load error
                              debugPrint('MoodSelection: Error loading image for $moodName: $error');
                              return Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 32),
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              // Show emoji while image loads
                              return Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 32),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  } else {
                    // Fallback to emoji if no image found
                    return Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                    );
                  }
                },
              ),
            ),
            
            // Text Layer - pinned to bottom with dark background
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7), // Dark background for readability
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(6), // Match button radius roughly
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double availableWidth = constraints.maxWidth;
                    final String text = _t(moodName);
                    final bool isSingleWord = !text.trim().contains(' ');
                    
                    // Base font size target
                    double fontSize = 13.0;
                    
                    if (isSingleWord) {
                      // For single words, use FittedBox to ensure it fits without splitting
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          text,
                          style: const TextStyle(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }
                    
                    // For phrases, calculate max font size that fits longest word
                    int maxWordLen = text.split(' ').map((w) => w.length).fold(0, (p, c) => p > c ? p : c);
                    if (maxWordLen > 0) {
                       // Subtract padding (2.0 on each side = 4.0)
                       double maxFontSizeForWidth = (availableWidth - 4) / (maxWordLen * 0.75);
                       if (fontSize > maxFontSizeForWidth) {
                         fontSize = maxFontSizeForWidth;
                       }
                    }
                    
                    // Clamp to reasonable limits
                    fontSize = fontSize.clamp(9.0, 14.0);
                    
                    return Text(
                      text,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: true);
    final useTapInterface = settingsProvider.settings?.useTapInterface ?? false;

    return RawKeyboardListener(
      focusNode: moodFocusNode!,
      autofocus: true,
      onKey: (event) {
        if (useTapInterface) {
          return;
        }

        if (event is RawKeyDownEvent && event.logicalKey.keyLabel == ' ') {
          // Check if we're waiting for initial switch press
          if (_waitingForInitialSwitch) {
            debugPrint('MoodSelection: Initial switch detected (spacebar) - starting scanning');
            setState(() {
              _waitingForInitialSwitch = false;
              _switchStartRequested = true;
            });
            _startAuditoryScanning();
            return;
          }
          
          // Normal scanning behavior
          debugPrint('MoodSelection: Spacebar pressed - isScanning=$isScanning, scanningIndex=$scanningIndex');
          if (isScanning && scanningIndex != null && scanningIndex! >= 0 && scanningIndex! < allOptions.length) {
            // Select the currently highlighted mood
            final selectedMood = allOptions[scanningIndex!]['name']!;
            debugPrint('MoodSelection: Spacebar selecting mood: $selectedMood');
            _selectMood(selectedMood);
          }
        } else if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
          // Tab key for step-mode scanning advancement
          final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
          final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
          
          debugPrint('MoodSelection: Tab pressed: scanMode=$scanMode, isScanning=$isScanning, _isAnnouncingScanningPrompt=$_isAnnouncingScanningPrompt');
          
          if (scanMode == 'step' && isScanning && _isAnnouncingScanningPrompt) {
            debugPrint('MoodSelection: Tab: Interrupting scanning announcement');
            // Interrupt the current scanning prompt announcement
            flutterTts.stop();
            if (mounted) {
              setState(() {
                _isAnnouncingScanningPrompt = false;
              });
            }
          }
          
          if (scanMode == 'step' && isScanning && scanningIndex != null) {
            debugPrint('MoodSelection: Tab: Advancing in step mode from index $scanningIndex');
            // Advance to next option
            _scanStep();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t('How are you feeling?')),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          automaticallyImplyLeading: false, // Remove back button
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                _t('Select your current mood:'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // Mood grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8, // 8 moods per row for more compact layout
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: allOptions.length,
                  itemBuilder: (context, index) {
                    return _buildMoodButton(allOptions[index], index);
                  },
                ),
              ),
              
              // Instructions
              const SizedBox(height: 16),
              Text(
                (useTapInterface)
                    ? _t('Tap a mood to continue, or tap Skip to proceed without selecting a mood.')
                    : (isScanning
                    ? _t('Auditory scanning is active. Press spacebar or tap to select the highlighted option.')
                    : _t('Tap a mood to continue, or tap Skip to proceed without selecting a mood.')),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
