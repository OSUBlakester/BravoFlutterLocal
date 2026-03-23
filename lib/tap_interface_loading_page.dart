import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/tap_interface_service.dart';
import 'services/user_settings_provider.dart';
import 'tap_interface_page.dart';

class TapInterfaceLoadingPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String mood;

  const TapInterfaceLoadingPage({
    Key? key,
    required this.idToken,
    required this.aacUserId,
    required this.mood,
  }) : super(key: key);

  @override
  State<TapInterfaceLoadingPage> createState() => _TapInterfaceLoadingPageState();
}

class _TapInterfaceLoadingPageState extends State<TapInterfaceLoadingPage> 
    with SingleTickerProviderStateMixin {
  String _currentTask = 'Initializing...';
  double _progress = 0.0;
  bool _hasError = false;
  String _errorMessage = '';

  // Animation controller for the spinning speech bubble
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  // Preloaded data
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
    
    _loadAllData();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      final tapService = TapInterfaceService(userSettingsProvider: userSettings);
      
      // Ensure we have the latest settings, especially the mood
      await userSettings.fetchSettings();
      
      // Step 1: Load tap interface config
      setState(() {
        _currentTask = 'Loading interface configuration...';
        _progress = 0.1;
      });
      
      _tapConfig = await tapService.fetchTapInterfaceConfig();
      
      // Step 2: Load word options
      setState(() {
        _currentTask = 'Generating word options...';
        _progress = 0.4;
      });
      
      final currentMood = userSettings.settings?.currentMood ?? 'No Mood Selected';
      String wordContext = 'general communication topics';
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        wordContext = 'general communication topics appropriate for someone feeling $currentMood';
      }
      
      _wordOptions = await tapService.generateFreestyleOptions(
        context: wordContext,
        buildSpaceText: '',
        singleWordsOnly: true,
        maxOptions: 35,
        currentMood: currentMood,
      );
      
      // Step 3: Load phrase options  
      setState(() {
        _currentTask = 'Generating phrase options...';
        _progress = 0.7;
      });
      
      String phraseContext = 'general conversation starters and common phrases';
      if (currentMood != 'No Mood Selected' && currentMood.isNotEmpty) {
        phraseContext = 'general conversation starters and common phrases appropriate for someone feeling $currentMood';
      }
      
      _phraseOptions = await tapService.generateLLMPhraseOptions(
        context: phraseContext,
        maxOptions: 25,
        currentMood: currentMood,
      );
      
      // Step 4: Navigation
      setState(() {
        _currentTask = 'Loading interface...';
        _progress = 1.0;
      });
      
      // Small delay to show completion
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        // Navigate to the actual tap interface with preloaded data
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TapInterfacePage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: widget.mood, // Use mood as display name for now
              preloadedConfig: _tapConfig,
              preloadedWordOptions: _wordOptions,
              preloadedPhraseOptions: _phraseOptions,
            ),
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load interface: $e';
        _currentTask = 'Error occurred';
      });
    }
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
                      width: 80,
                      height: 80,
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
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 2
                        ..color = Colors.white,
                    ),
                  ),
                  // Orange fill
                  Text(
                    'Welcome to Bravo!',
                    style: TextStyle(
                      fontSize: 32,
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
                  width: 200,
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                Text(
                  _currentTask,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 10),
                
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
              
              // Error state
              if (_hasError) ...[
                Icon(
                  Icons.error_outline,
                  size: 60,
                  color: Colors.red[300],
                ),
                
                const SizedBox(height: 20),
                
                Text(
                  'Loading Error',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[300],
                  ),
                ),
                
                const SizedBox(height: 10),
                
                Text(
                  _errorMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 30),
                
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _progress = 0.0;
                      _currentTask = 'Retrying...';
                    });
                    _loadAllData();
                  },
                  child: Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}