import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/tap_interface_service.dart';
import 'services/user_settings_provider.dart';
import 'services/pictogram_service.dart';
import 'services/offline_cache_service.dart';
import 'services/offline_mode_provider.dart';
import 'mood_selection_page.dart';
import 'tap_interface_page.dart';

class AppLoadingPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;
  final bool useTapInterface;

  const AppLoadingPage({
    Key? key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
    required this.useTapInterface,
  }) : super(key: key);

  @override
  State<AppLoadingPage> createState() => _AppLoadingPageState();
}

class _AppLoadingPageState extends State<AppLoadingPage> 
    with SingleTickerProviderStateMixin {
  String _currentTask = 'Preparing your experience...';
  double _progress = 0.0;
  bool _hasError = false;
  String _errorMessage = '';

  // Animation controller for the spinning speech bubble
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  // Preloaded data for tap interface (if needed)
  dynamic _tapConfig;
  List<String> _wordOptions = [];
  List<Map<String, String>> _phraseOptions = [];

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller for spinning speech bubble
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));
    
    // Start the spinning animation
    _animationController.repeat();
    
    _loadAllAppData();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAllAppData() async {
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final offlineModeProvider = Provider.of<OfflineModeProvider>(context, listen: false);
      final isOffline = offlineModeProvider.isOffline;

      // -----------------------------------------------------------------------
      // OFFLINE PATH
      // -----------------------------------------------------------------------
      if (isOffline) {
        setState(() {
          _currentTask = 'Loading cached profile data...';
          _progress = 0.2;
        });

        // Load settings from cache
        final settingsJson = await OfflineCacheService.loadUserSettingsJson();
        if (settingsJson != null) {
          try {
            final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
            userSettings.settings = UserSettings.fromJson(decoded);
          } catch (e) {
            debugPrint('AppLoadingPage: Failed to parse cached settings: $e');
          }
        }

        setState(() {
          _currentTask = 'Loading cached interface...';
          _progress = 0.5;
        });

        // Load tap config from cache
        final tapConfigJson = await OfflineCacheService.loadTapConfigJson();
        if (tapConfigJson != null) {
          try {
            final decoded = jsonDecode(tapConfigJson) as Map<String, dynamic>;
            _tapConfig = TapInterfaceConfig.fromJson(decoded);
          } catch (e) {
            debugPrint('AppLoadingPage: Failed to parse cached tap config: $e');
          }
        }

        setState(() {
          _currentTask = 'Ready!';
          _progress = 1.0;
        });

        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TapInterfacePage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
                preloadedConfig: _tapConfig,
                preloadedWordOptions: const [],
                preloadedPhraseOptions: const [],
                isOfflineMode: true,
              ),
            ),
          );
        }
        return;
      }

      // -----------------------------------------------------------------------
      // ONLINE PATH (unchanged)
      // -----------------------------------------------------------------------

      // Step 1: CRITICAL - Update UserSettingsProvider with correct profile information
      setState(() {
        _currentTask = 'Preparing user profile...';
        _progress = 0.05;
      });

      // CRITICAL FIX: Update the provider with the selected profile's information
      print('🔧 AppLoadingPage: Current provider userId: ${userSettings.userId}');
      print('🔧 AppLoadingPage: Widget aacUserId: ${widget.aacUserId}');
      print('🔧 AppLoadingPage: Setting provider userId to: ${widget.aacUserId}');

      userSettings.idToken = widget.idToken;
      userSettings.userId = widget.aacUserId;

      print('🔧 AppLoadingPage: Provider userId after update: ${userSettings.userId}');

      // Ensure settings are loaded with the correct profile
      await userSettings.fetchSettings();

      print('🔧 AppLoadingPage: Settings fetched for profile: ${userSettings.userId}');

      // Set user context in PictogramService for debugging
      PictogramService().setUserContext(
        userId: widget.aacUserId,
        idToken: widget.idToken,
        mascot: userSettings.settings?.mascot,
      );

      // Step 2: Initialize pictogram cache (global shared library)
      setState(() {
        _currentTask = 'Loading image cache...';
        _progress = 0.1;
      });

      await PictogramService().loadCacheFromPrefs();

      // Step 2: Preload common images for mood selection and interface
      setState(() {
        _currentTask = 'Preloading interface images...';
        _progress = 0.3;
      });

      // SKIP image preloading during splash screen to prevent unwanted API calls and missing_images logging
      // Images will be loaded naturally/lazily when the user navigates to different pages
      // This prevents the "preload logging bug" where image searches during splash trigger false missing_images entries
      setState(() {
        _currentTask = 'Finalizing initialization...';
        _progress = 0.68;
      });

      // Brief delay to allow UI to update
      await Future.delayed(const Duration(milliseconds: 100));

      debugPrint('⏭️ Skipping image preload during splash screen (images will load on demand)');

      // Step 3: Load tap interface data if needed
      if (widget.useTapInterface) {
        setState(() {
          _currentTask = 'Preparing communication interface...';
          _progress = 0.7;
        });

        final tapService = TapInterfaceService(userSettingsProvider: userSettings);

        // Load config
        _tapConfig = await tapService.fetchTapInterfaceConfig();

        // Load initial options based on current mood
        final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';

        String wordContext = 'general communication topics';
        String phraseContext = 'general conversation starters and common phrases';

        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          wordContext = 'general communication topics appropriate for someone feeling $currentMood';
          phraseContext = 'general conversation starters and common phrases appropriate for someone feeling $currentMood';
        }

        // Load word and phrase options in parallel
        final futures = await Future.wait([
          tapService.generateFreestyleOptions(
            context: wordContext,
            buildSpaceText: '',
            singleWordsOnly: true,
            maxOptions: 35,
          ),
          tapService.generateLLMPhraseOptions(
            context: phraseContext,
            maxOptions: 25,
          ),
        ]);

        _wordOptions = futures[0] as List<String>;
        _phraseOptions = futures[1] as List<Map<String, String>>;
      }

      // Step 4: Final preparation and verification
      setState(() {
        _currentTask = 'Preparing interface...';
        _progress = 0.9;
      });

      // Persist data for offline use (best-effort, non-blocking)
      _saveOfflineCache(userSettings);

      // Longer delay to ensure all async operations complete
      await Future.delayed(const Duration(milliseconds: 1000));

      setState(() {
        _currentTask = 'Ready!';
        _progress = 1.0;
      });

      // Show completion state longer so user sees 100%
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        // Navigate to appropriate page based on interface type
        if (widget.useTapInterface) {
          // Go directly to tap interface with preloaded data
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TapInterfacePage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
                preloadedConfig: _tapConfig,
                preloadedWordOptions: _wordOptions,
                preloadedPhraseOptions: _phraseOptions,
              ),
            ),
          );
        } else {
          // Go to mood selection page with preloaded images
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MoodSelectionPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
              ),
            ),
          );
        }
      }

    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to prepare app: $e';
        _currentTask = 'Loading error occurred';
      });
    }
  }

  /// Saves current loaded data to offline cache (best-effort, non-blocking).
  void _saveOfflineCache(UserSettingsProvider userSettings) {
    final audioUrls = _collectTapAudioUrls();
    OfflineCacheService.saveAll(
      userId: widget.aacUserId,
      displayName: widget.displayName,
      settingsJson: jsonEncode(userSettings.settings?.toJson() ?? {}),
      tapConfigJson: jsonEncode(_tapConfig?.toJson() ?? {}),
      tapBoardsJson: '{}', // tap boards not fetched in this version
      audioUrls: audioUrls,
      idToken: widget.idToken,
    ).catchError((e) {
      debugPrint('AppLoadingPage: Offline cache save failed: $e');
    });
  }

  /// Collects all custom audio file URLs from the tap config.
  List<String> _collectTapAudioUrls() {
    final urls = <String>[];
    final seen = <String>{};

    void addUrl(String? raw) {
      final normalized = (raw ?? '').trim();
      if (!normalized.startsWith('http')) return;
      if (seen.contains(normalized)) return;
      seen.add(normalized);
      urls.add(normalized);
    }

    void collectCategoryUrls(TapInterfaceCategory category) {
      if (category.hidden) return;
      addUrl(category.customAudioFile);
      for (final child in category.children) {
        collectCategoryUrls(child);
      }
    }

    for (final category in _tapConfig?.buttons ?? const <TapInterfaceCategory>[]) {
      collectCategoryUrls(category);
    }

    return urls;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002244), // Denver Broncos navy blue
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated speech bubble spinner
              AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value * 2.0 * 3.14159,
                    child: Image.asset(
                      'assets/speech_bubble_spinner.png',
                      width: 100,
                      height: 100,
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 40),
              
              // App name with Denver Broncos orange and white outline
              Stack(
                children: [
                  // White outline
                  Text(
                    'Welcome to Bravo!',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..color = Colors.white,
                    ),
                  ),
                  // Orange fill
                  Text(
                    'Welcome to Bravo!',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFB4F14), // Denver Broncos orange
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 60),
              
              // Loading indicator
              if (!_hasError) ...[
                SizedBox(
                  width: 250,
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                
                const SizedBox(height: 25),
                
                Text(
                  _currentTask,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 15),
                
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
              
              // Error state
              if (_hasError) ...[
                Icon(
                  Icons.error_outline,
                  size: 70,
                  color: Colors.red[300],
                ),
                
                const SizedBox(height: 25),
                
                Text(
                  'Loading Error',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[300],
                  ),
                ),
                
                const SizedBox(height: 15),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 35),
                
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _progress = 0.0;
                      _currentTask = 'Retrying...';
                    });
                    _loadAllAppData();
                  },
                  icon: Icon(Icons.refresh),
                  label: Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}