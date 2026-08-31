import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  TapBoardsResponse? _tapBoards;
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

      // Step 2: Load in-memory cache from persistent storage
      setState(() {
        _currentTask = 'Loading image cache...';
        _progress = 0.1;
      });

      await PictogramService().loadCacheFromPrefs();

      // Step 2b: Download the symbol library (mirrors what the web app does at login
      // in auth.html before the tap interface opens). This populates the local library
      // index so word options can be resolved zero-network on first render.
      // Timeout 120s — the library JSON is large (~15k images).
      setState(() {
        _currentTask = 'Downloading image library...';
        _progress = 0.2;
      });

      try {
        await PictogramService().ensureLibraryLoaded()
            .timeout(const Duration(seconds: 120));
        debugPrint('📚 AppLoadingPage: Symbol library ready');
      } catch (e) {
        debugPrint('⚠️ AppLoadingPage: Symbol library download timed out or failed: $e (continuing without it)');
      }

      // Step 3: Always fetch the tap config so it can be passed through mood
      // selection to TapInterfacePage without a redundant API call.
      setState(() {
        _currentTask = 'Preparing communication interface...';
        _progress = 0.6;
      });

      final tapService = TapInterfaceService(userSettingsProvider: userSettings);

      if (widget.useTapInterface) {
        // Direct-to-tap path: also generate LLM word/phrase options in parallel.
        final tapConfigFuture = tapService.fetchTapInterfaceConfig();

        final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
        String wordContext = 'general communication topics';
        String phraseContext = 'general conversation starters and common phrases';
        if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
          wordContext = 'general communication topics appropriate for someone feeling $currentMood';
          phraseContext = 'general conversation starters and common phrases appropriate for someone feeling $currentMood';
        }

        final results = await Future.wait([
          tapConfigFuture,
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

        _tapConfig = results[0];
        _wordOptions = results[1] as List<String>;
        _phraseOptions = results[2] as List<Map<String, String>>;
      } else {
        // Mood-selection path: read from the offline cache first (instant disk
        // read — no network wait). Then kick off an API refresh in the
        // background so the cache stays fresh for the next session.
        // Only falls back to a blocking API call on first install (empty cache).
        final configJson = await OfflineCacheService.loadTapConfigJson();

        TapInterfaceConfig? cachedConfig;
        if (configJson != null && configJson.length > 2) {
          try {
            cachedConfig = TapInterfaceConfig.fromJson(
              jsonDecode(configJson) as Map<String, dynamic>,
            );
          } catch (_) {}
        }

        if (cachedConfig != null && cachedConfig.buttons.isNotEmpty) {
          _tapConfig = cachedConfig;
          // Load cached boards from disk so TapInterfacePage starts with
          // the most-recently-saved board data rather than re-reading disk itself.
          try {
            final boardsJson = await OfflineCacheService.loadTapBoardsJson();
            if (boardsJson != null && boardsJson.length > 2) {
              _tapBoards = TapBoardsResponse.fromJson(
                jsonDecode(boardsJson) as Map<String, dynamic>,
              );
            }
          } catch (_) {}
          // Background refresh — updates cache silently, no blocking.
          unawaited(() async {
            try {
              final r = await Future.wait([
                tapService.fetchTapInterfaceConfig(),
                tapService.fetchTapBoards(),
              ]);
              final fresh = r[0] as TapInterfaceConfig?;
              final freshBoards = r[1] as TapBoardsResponse?;
              if (fresh != null) {
                OfflineCacheService.saveTapConfig(jsonEncode(fresh.toJson()))
                    .catchError((_) {});
              }
              if (freshBoards != null) {
                OfflineCacheService.saveTapBoards(jsonEncode(freshBoards.toJson()))
                    .catchError((_) {});
              }
            } catch (_) {}
          }());
        } else {
          // No cache yet (first install) — must wait for API.
          try {
            final r = await Future.wait([
              tapService.fetchTapInterfaceConfig(),
              tapService.fetchTapBoards(),
            ]);
            _tapConfig = r[0] as TapInterfaceConfig?;
            final freshBoards = r[1] as TapBoardsResponse?;
            if (freshBoards != null) {
              _tapBoards = freshBoards;
              OfflineCacheService.saveTapBoards(jsonEncode(freshBoards.toJson()))
                  .catchError((_) {});
            }
            if (_tapConfig != null) {
              OfflineCacheService.saveTapConfig(jsonEncode(_tapConfig!.toJson()))
                  .catchError((_) {});
            }
          } catch (_) {}
        }
      }

      // Prefetch images for word options (only runs when useTapInterface=true
      // since _wordOptions is empty in the mood-selection path).
      if (_wordOptions.isNotEmpty) {
        setState(() {
          _currentTask = 'Loading word images...';
          _progress = 0.78;
        });
        final kwMap = <String, List<String>>{};
        for (final w in _wordOptions) {
          kwMap[w] = [w];
        }
        try {
          await PictogramService().prefetchButtonPictograms(
            words: _wordOptions,
            keywordMap: kwMap,
            locale: userSettings.settings?.userLanguage ?? 'en-US',
            maxItems: _wordOptions.length,
          ).timeout(const Duration(seconds: 30));
        } catch (e) {
          debugPrint('⚠️ AppLoadingPage: Image prefetch timed out: $e (images will load lazily)');
        }

        unawaited(_logConfirmedMissingWordOptions(
          _wordOptions,
          locale: userSettings.settings?.userLanguage ?? 'en-US',
        ));
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
                preloadedBoards: _tapBoards,
                preloadedWordOptions: _wordOptions,
                preloadedPhraseOptions: _phraseOptions,
              ),
            ),
          );
        } else {
          // Go to mood selection page, carrying the already-fetched config so
          // TapInterfacePage doesn't need to re-fetch it after mood selection.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MoodSelectionPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
                preloadedConfig: _tapConfig,
                preloadedWordOptions: _wordOptions,
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

  /// After prefetch completes, check every word option for a cached image.
  /// Any word with no image at this point is a confirmed miss (the full
  /// library → batch-search → button-search chain ran and found nothing).
  /// Writes to Firestore missing_images — fire-and-forget, non-blocking.
  Future<void> _logConfirmedMissingWordOptions(
    List<String> words, {
    required String locale,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final firestore = FirebaseFirestore.instance;
      final pictogramService = PictogramService();

      for (final word in words) {
        final cachedUrl = pictogramService.getCachedImageUrl(word, locale: locale);
        if (cachedUrl != null) continue; // image found — not missing

        final textTrimmed = word.trim();
        if (textTrimmed.isEmpty) continue;

        // Deduplicate against existing records for this user.
        final existing = await firestore
            .collection('missing_images')
            .where('text', isEqualTo: textTrimmed)
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) continue;

        await firestore.collection('missing_images').add({
          'text': textTrimmed,
          'timestamp': FieldValue.serverTimestamp(),
          'source': 'word_option_prefetch_confirmed_miss',
          'uid': user.uid,
        });
        debugPrint('📋 Confirmed-missing word option logged: "$textTrimmed"');
      }
    } catch (e) {
      debugPrint('⚠️ AppLoadingPage: Error logging confirmed-missing word options: $e');
    }
  }

  /// Saves current loaded data to offline cache (best-effort, non-blocking).
  /// Boards are saved separately when fetched — we never write '{}' here so
  /// we don't overwrite valid boards data that was saved on a previous launch.
  void _saveOfflineCache(UserSettingsProvider userSettings) {
    final audioUrls = _collectTapAudioUrls();
    Future.wait([
      OfflineCacheService.saveProfile(
        userId: widget.aacUserId,
        displayName: widget.displayName,
      ),
      OfflineCacheService.saveUserSettings(
        jsonEncode(userSettings.settings?.toJson() ?? {}),
      ),
      OfflineCacheService.saveTapConfig(
        jsonEncode(_tapConfig?.toJson() ?? {}),
      ),
    ]).catchError((e) {
      debugPrint('AppLoadingPage: Offline cache save failed: $e');
      return <void>[];
    });
    if (audioUrls.isNotEmpty) {
      OfflineCacheService.cacheAudioFiles(audioUrls, widget.idToken)
          .catchError((_) {});
    }
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