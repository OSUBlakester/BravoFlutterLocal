import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/user_settings_provider.dart';
import 'config/language_config.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({Key? key}) : super(key: key);

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  bool _isInitialized = false;

  // Local preference: boards panel position ('left' | 'top' | 'right' | 'bottom')
  String _menuPosition = 'left';

  // Local preference: minimum tap hold duration in ms (0 = instant)
  int _tapMinDurationMs = 0;

  // Controllers for editable fields
  final TextEditingController _toolbarPinController = TextEditingController();

  // Location override languages table rows: each entry is {locale, voice}
  List<Map<String, String>> _locationOverrideRows = [];
  final TextEditingController _wakeWordInterjectionController = TextEditingController();
  final TextEditingController _wakeWordNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _llmOptionsController = TextEditingController();
  final TextEditingController _freestyleOptionsController = TextEditingController();
  final TextEditingController _scanLoopLimitController = TextEditingController();
  final TextEditingController _displaySplashtimeController = TextEditingController();
  final TextEditingController _emailRecipientController = TextEditingController();
  final TextEditingController _emailSubjectTemplateController = TextEditingController();

  String? _normalizeSupportedLocale(String? rawLocale) {
    final raw = (rawLocale ?? '').trim();
    if (raw.isEmpty) return null;

    final exactValue = kSupportedLanguages.firstWhere(
      (l) => (l['value'] ?? '') == raw,
      orElse: () => const {},
    );
    if (exactValue.isNotEmpty) return exactValue['value'];

    final lowerRaw = raw.toLowerCase();
    for (final lang in kSupportedLanguages) {
      final value = (lang['value'] ?? '').toLowerCase();
      final label = (lang['label'] ?? '').toLowerCase();
      if (value == lowerRaw || label == lowerRaw) {
        return lang['value'];
      }
    }

    // Handle shorthand language codes like "en" -> "en-US" when possible.
    if (!raw.contains('-') && raw.length == 2) {
      for (final lang in kSupportedLanguages) {
        final value = (lang['value'] ?? '').toLowerCase();
        if (value.startsWith('${lowerRaw}-')) {
          return lang['value'];
        }
      }
    }

    return null;
  }
  
  @override
  void initState() {
    super.initState();
    
    // Configure soft input mode for admin page (but don't show keyboard yet)
    _configureSoftInputModeForAdmin();

    // Load locally-stored preferences.
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _menuPosition = prefs.getString('tap_menu_position') ?? 'left';
          _tapMinDurationMs = prefs.getInt('tap_min_duration_ms') ?? 0;
        });
      }
    });

    // Use addPostFrameCallback to avoid setState() during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProvider();
    });
  }
  
  @override
  void dispose() {
    // Re-disable keyboard when leaving admin page
    _disableKeyboardForMainApp();
    
    _toolbarPinController.dispose();
    _wakeWordInterjectionController.dispose();
    _wakeWordNameController.dispose();
    _locationController.dispose();
    _llmOptionsController.dispose();
    _freestyleOptionsController.dispose();
    _scanLoopLimitController.dispose();
    _displaySplashtimeController.dispose();
    _emailRecipientController.dispose();
    _emailSubjectTemplateController.dispose();
    super.dispose();
  }

  // *** KEYBOARD MANAGEMENT FOR ADMIN PAGES ***
  Future<void> _configureSoftInputModeForAdmin() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        // Configure soft input mode for enhanced keyboard support (but don't show keyboard yet)
        await platform.invokeMethod('configureSoftInputMode');
        debugPrint('✅ Soft input mode configured for admin page');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to configure soft input mode: $e');
    }
  }

  Future<void> _showKeyboardWhenNeeded() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('showKeyboard');
        debugPrint('✅ Keyboard shown for text field');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to show keyboard: $e');
    }
  }

  Future<void> _disableKeyboardForMainApp() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('disableSoftKeyboard');
        debugPrint('✅ Keyboard disabled for main app');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to disable keyboard: $e');
    }
  }
  
  Future<void> _initializeProvider() async {
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      await userSettings.fetchSettings();
      
      print('🔍 LOADED waitForSwitchToScan = ${userSettings.settings?.waitForSwitchToScan}');
      
      // Initialize text controllers with loaded values
      if (userSettings.settings != null) {
        _toolbarPinController.text = userSettings.settings!.toolbarPIN;
        _wakeWordInterjectionController.text = userSettings.settings!.wakeWordInterjection;
        _wakeWordNameController.text = userSettings.settings!.wakeWordName;
        _locationController.text = userSettings.settings!.countryCode;
        _llmOptionsController.text = userSettings.settings!.llmOptions.toString();
        _freestyleOptionsController.text = userSettings.settings!.freestyleOptions.toString();
        _scanLoopLimitController.text = userSettings.settings!.scanLoopLimit.toString();
        _displaySplashtimeController.text = userSettings.settings!.displaySplashtime.toString();
        _emailRecipientController.text = userSettings.settings!.emailDefaultRecipient;
        _emailSubjectTemplateController.text = userSettings.settings!.emailSubjectTemplate;
      }
      
      // Fetch available options
      await userSettings.fetchTtsVoices();

      if (userSettings.settings != null) {
        _locationOverrideRows = userSettings.settings!.locationOverrideLanguages
            .map((e) {
              final normalizedLocale = _normalizeSupportedLocale(e.locale) ?? kDefaultPartnerLanguage;
              return {'locale': normalizedLocale, 'voice': e.voice};
            })
            .toList();
      }
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing provider: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  void _showColorPicker(BuildContext context, Color currentColor, Function(Color) onColorChanged) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a Color'),
          content: SingleChildScrollView(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 30,
              itemBuilder: (context, index) {
                final colors = [
                  Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
                  Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                  Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
                  Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                  Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
                  Colors.white, Colors.red[100]!, Colors.green[100]!, Colors.blue[100]!,
                  Colors.yellow[100]!, Colors.purple[100]!, Colors.orange[100]!, Colors.pink[100]!,
                  Colors.grey[100]!, Colors.grey[800]!,
                ];
                
                final color = colors[index % colors.length];
                return GestureDetector(
                  onTap: () {
                    onColorChanged(color);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  // Helper method to build number dropdown (0-10)
  Widget _buildNumberDropdown({
    required int currentValue,
    required String label,
    required String helperText,
    required int minValue,
    required int maxValue,
    required Function(int) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 200,
          child: DropdownButtonFormField<int>(
            value: currentValue,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: List.generate(
              maxValue - minValue + 1,
              (index) => DropdownMenuItem<int>(
                value: minValue + index,
                child: Text(
                  '${minValue + index}${(minValue + index) == 0 ? ' (unlimited)' : ''}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            onChanged: (int? value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
        ),
        if (helperText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ],
    );
  }

  // Helper method to build a section card with consistent styling
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              width: double.infinity,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  // Helper method to build consistent text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onTap: () {
            // Show keyboard when text field is tapped
            _showKeyboardWhenNeeded();
          },
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ],
    );
  }

  // Helper method to build consistent checkboxes with actual settings modification
  Widget _buildSettingsCheckbox({
    required UserSettingsProvider userSettings,
    required bool Function(UserSettings) getValue,
    required void Function(UserSettings, bool) setValue,
    required String title,
    String? subtitle,
  }) {
    if (userSettings.settings == null) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        Row(
          children: [
            Checkbox(
              value: getValue(userSettings.settings!),
              onChanged: (bool? value) {
                if (value != null) {
                  setState(() {
                    final settings = userSettings.settings!;
                    setValue(settings, value);
                  });
                  userSettings.saveSettings(userSettings.settings!);
                }
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            if (subtitle != null)
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveSettings() async {
    final settingsProvider = Provider.of<UserSettingsProvider>(context, listen: false);
    
    if (settingsProvider.settings == null) return;
    
    try {
      // Update settings from text controllers
      final settings = settingsProvider.settings!;
      settings.toolbarPIN = _toolbarPinController.text;
      settings.wakeWordInterjection = _wakeWordInterjectionController.text.trim();
      settings.wakeWordName = _wakeWordNameController.text.trim();
      settings.countryCode = _locationController.text;
      settings.emailDefaultRecipient = _emailRecipientController.text.trim();
      settings.emailSubjectTemplate = _emailSubjectTemplateController.text.trim();

      if (settings.wakeWordName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wake Word Name cannot be empty.')),
        );
        return;
      }
      
      // Handle LLM Options
      final llmOptionsValue = int.tryParse(_llmOptionsController.text);
      if (llmOptionsValue != null && llmOptionsValue >= 1 && llmOptionsValue <= 50) {
        settings.llmOptions = llmOptionsValue;
      }
      
      // Handle Freestyle Options
      final freestyleOptionsValue = int.tryParse(_freestyleOptionsController.text);
      if (freestyleOptionsValue != null && freestyleOptionsValue >= 1 && freestyleOptionsValue <= 50) {
        settings.freestyleOptions = freestyleOptionsValue;
      }
      
      // Handle Scan Loop Limit
      final scanLoopLimitValue = int.tryParse(_scanLoopLimitController.text);
      if (scanLoopLimitValue != null && scanLoopLimitValue >= 0 && scanLoopLimitValue <= 10) {
        settings.scanLoopLimit = scanLoopLimitValue;
      }
      
      // Handle Display Splash Time
      final displaySplashtimeValue = int.tryParse(_displaySplashtimeController.text);
      if (displaySplashtimeValue != null && displaySplashtimeValue >= 1000 && displaySplashtimeValue <= 10000) {
        settings.displaySplashtime = displaySplashtimeValue;
      }
      
      final normalizedOverrides = <LocationLanguageEntry>[];
      var droppedInvalidLocaleRows = 0;

      for (final row in _locationOverrideRows) {
        final normalizedLocale = _normalizeSupportedLocale(row['locale']);
        if (normalizedLocale == null) {
          droppedInvalidLocaleRows += 1;
          continue;
        }
        normalizedOverrides.add(
          LocationLanguageEntry(
            locale: normalizedLocale,
            voice: (row['voice'] ?? '').trim(),
          ),
        );
      }

      settings.locationOverrideLanguages = normalizedOverrides;

      final success = await settingsProvider.saveSettings(settings);

      if (success) {
        if (droppedInvalidLocaleRows > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Settings saved. Removed $droppedInvalidLocaleRows invalid location language row(s).',
              ),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
      } else {
        final saveError = settingsProvider.error ?? 'Unable to save settings.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saveError)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e')),
      );
    }
  }

  Future<void> _testTtsVoice(String voiceName, UserSettingsProvider provider) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Testing TTS voice...'),
          duration: Duration(seconds: 1),
        ),
      );

      // Make API call to test the voice
      final response = await http.post(
        Uri.parse('${provider.apiBaseUrl}/api/test-tts-voice'),
        headers: {
          'Authorization': 'Bearer ${provider.idToken}',
          'X-User-ID': provider.userId!,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'voice_name': voiceName,
          'text': 'Hello, this is a test of the $voiceName voice. How does it sound?',
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final audioUrl = responseData['audio_url'];
        final audioData = responseData['audio_data'];
        final sampleRate = responseData['sample_rate'];
        
        if (audioData != null && audioData.toString().isNotEmpty) {
          final AudioPlayer player = AudioPlayer();
          try {
            final pcmBytes = base64Decode(audioData.toString());
            final effectiveSampleRate = sampleRate is int
                ? sampleRate
                : int.tryParse(sampleRate?.toString() ?? '') ?? 24000;
            final wavBytes = _wrapPcm16ToWav(pcmBytes, effectiveSampleRate);
            final tempFile = File(
              '${Directory.systemTemp.path}/tts_voice_test_${DateTime.now().millisecondsSinceEpoch}.wav',
            );
            await tempFile.writeAsBytes(wavBytes, flush: true);

            await player.setFilePath(tempFile.path);
            await player.play();

            final completer = Completer<void>();
            final sub = player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed &&
                  !completer.isCompleted) {
                completer.complete();
              }
            });
            await completer.future.timeout(const Duration(seconds: 15));
            await sub.cancel();
            await player.dispose();
            if (await tempFile.exists()) {
              await tempFile.delete();
            }

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice test completed for $voiceName.'),
                duration: const Duration(seconds: 3),
              ),
            );
          } catch (e) {
            debugPrint('Error playing base64 test audio: $e');
            await player.dispose();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Voice test generated but playback failed.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (audioUrl != null && audioUrl.isNotEmpty) {
          // Play the audio locally
          final AudioPlayer player = AudioPlayer();
          try {
            await player.setUrl(audioUrl);
            await player.play();
            
            // Wait for playback to complete
            final completer = Completer<void>();
            final sub = player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                if (!completer.isCompleted) completer.complete();
              }
            });
            await completer.future;
            await sub.cancel();
            await player.dispose();
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice test completed for $voiceName.'),
                duration: const Duration(seconds: 3),
              ),
            );
          } catch (e) {
            debugPrint('Error playing test audio: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice test generated but playback failed.'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Voice test sent! Listen for the $voiceName voice.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('TTS test failed: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error testing voice: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Uint8List _wrapPcm16ToWav(Uint8List pcmBytes, int sampleRate) {
    final channels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataLength = pcmBytes.length;
    final fileLength = 44 + dataLength - 8;

    final header = ByteData(44);

    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileLength, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataLength, Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmBytes]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Settings'),
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Consumer<UserSettingsProvider>(
        builder: (context, provider, child) {
          // Show loading state if not initialized or (loading AND no settings)
          if (!_isInitialized || (provider.isLoading && provider.settings == null)) {
            return const Center(child: CircularProgressIndicator());
          }

          // Show error state if there's an error and no cached settings
          if (provider.error != null && provider.settings == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning, size: 64, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Settings not available',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Error: ${provider.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _initializeProvider(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final settings = provider.settings!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (provider.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: LinearProgressIndicator(),
                  ),
                // Security Section
                _buildSectionCard(
                  title: 'Security',
                  icon: Icons.security,
                  iconColor: Colors.red,
                  children: [
                    _buildTextField(
                      controller: _toolbarPinController,
                      label: 'Admin Toolbar PIN',
                      hint: 'Enter 4-digit PIN',
                      helperText: 'PIN required to access admin toolbar (4-10 digits recommended).',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // User Interface Section
                _buildSectionCard(
                  title: 'User Interface',
                  icon: Icons.touch_app,
                  iconColor: Colors.purple,
                  children: [
                    const Text(
                      'Interaction Mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            title: const Text('Auditory Scanning'),
                            subtitle: const Text('Use switch access with auditory cues'),
                            value: false,
                            groupValue: settings.useTapInterface,
                            onChanged: (bool? value) {
                              if (value != null) {
                                setState(() {
                                  settings.useTapInterface = value;
                                });
                                provider.saveSettings(settings);
                              }
                            },
                          ),
                          const Divider(height: 1),
                          RadioListTile<bool>(
                            title: const Text('Tap Screen'),
                            subtitle: const Text('Direct touch interaction'),
                            value: true,
                            groupValue: settings.useTapInterface,
                            onChanged: (bool? value) {
                              if (value != null) {
                                setState(() {
                                  settings.useTapInterface = value;
                                });
                                provider.saveSettings(settings);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // AI Settings Section
                _buildSectionCard(
                  title: 'AI Settings',
                  icon: Icons.psychology,
                  iconColor: Colors.blue,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _wakeWordInterjectionController,
                            label: 'Wake Word Interjection',
                            hint: 'e.g., Hey',
                            helperText: 'Word before the wake word',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _wakeWordNameController,
                            label: 'Wake Word Name',
                            hint: 'e.g., Bravo',
                            helperText: 'Main wake word',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _buildSettingsCheckbox(
                      userSettings: provider,
                      getValue: (s) => s.summaryOff,
                      setValue: (s, v) => s.summaryOff = v,
                      title: 'Turn off Button Summary',
                      subtitle: 'Turn off Button Summary. Buttons will show full speech option.',
                    ),
                    const SizedBox(height: 12),
                    
                    _buildSettingsCheckbox(
                      userSettings: provider,
                      getValue: (s) => s.autoClean,
                      setValue: (s, v) => s.autoClean = v,
                      title: 'Auto Clean in Freestyle',
                      subtitle: 'Automatically clean up text before speaking in Freestyle mode.',
                    ),
                    const SizedBox(height: 20),

                    // Number of AI Phrase Options
                    _buildTextField(
                      controller: _llmOptionsController,
                      label: 'Number of AI Phrase Options',
                      hint: 'e.g., 10',
                      helperText: 'Number of phrase options AI will return for user to select (applies to tap interface Phrases section)',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 20),

                    // Number of AI Word Options
                    _buildTextField(
                      controller: _freestyleOptionsController,
                      label: 'Number of AI Word Options',
                      hint: 'e.g., 20',
                      helperText: 'Number of word options AI will return in freestyle and tap interface Words section (1-50)',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 20),

                    _buildTextField(
                      controller: _locationController,
                      label: 'Location',
                      hint: '2 Letter Country Code',
                      helperText: 'Location Country to determine local info. Use 2-letter codes.',
                    ),
                    const SizedBox(height: 20),

                    _buildTextField(
                      controller: _emailRecipientController,
                      label: 'Default Email Recipient',
                      hint: 'name@example.com',
                      helperText: 'Optional default To: address for the Tap Interface email button.',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),

                    _buildTextField(
                      controller: _emailSubjectTemplateController,
                      label: 'Email Subject Template',
                      hint: 'Message from Bravo AAC',
                      helperText: 'Default subject line used when composing email from Tap Interface.',
                    ),
                    const SizedBox(height: 20),

                    // Speech Bubble Display Subsection
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Speech Bubble Display',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          _buildSettingsCheckbox(
                            userSettings: provider,
                            getValue: (s) => s.displaySplash,
                            setValue: (s, v) => s.displaySplash = v,
                            title: 'Enable Speech Bubble',
                            subtitle: 'Show speech bubble overlay when text is being announced.',
                          ),
                          const SizedBox(height: 16),
                          
                          // Speech Bubble Display Duration with plus/minus buttons
                          const Text(
                            'Display Duration:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  if (settings.displaySplashtime > 1000) {
                                    setState(() {
                                      settings.displaySplashtime = (settings.displaySplashtime - 100).clamp(1000, 10000);
                                    });
                                  }
                                },
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Decrease by 100ms',
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${settings.displaySplashtime}ms',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (settings.displaySplashtime < 10000) {
                                    setState(() {
                                      settings.displaySplashtime = (settings.displaySplashtime + 100).clamp(1000, 10000);
                                    });
                                  }
                                },
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Increase by 100ms',
                              ),
                            ],
                          ),
                          Text(
                            'How long to show the speech bubble (1000-10000ms)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Mood Selection Subsection moved to User Info page

                  ],
                ),
                const SizedBox(height: 16),

                // Language Settings Section
                _buildSectionCard(
                  title: 'Language Settings',
                  icon: Icons.language,
                  iconColor: Colors.teal,
                  children: [
                    // User language
                    const Text(
                      'User Language',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Language for AI-generated options.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      value: kSupportedLanguages.any((l) => l['value'] == settings.userLanguage)
                          ? settings.userLanguage
                          : kDefaultUserLanguage,
                      items: kSupportedLanguages
                          .map((l) => DropdownMenuItem<String>(value: l['value'], child: Text(l['label']!)))
                          .toList(),
                      onChanged: (v) { if (v != null) setState(() { settings.userLanguage = v; }); },
                    ),
                    const SizedBox(height: 20),

                    // Default partner language + voice
                    const Text(
                      'Default Partner Language',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Language used when announcing to the communication partner.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      value: kSupportedLanguages.any((l) => l['value'] == settings.defaultPartnerLanguage)
                          ? settings.defaultPartnerLanguage
                          : kDefaultPartnerLanguage,
                      items: kSupportedLanguages
                          .map((l) => DropdownMenuItem<String>(value: l['value'], child: Text(l['label']!)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            settings.defaultPartnerLanguage = v;
                            // Reset voice when language changes
                            final voices = provider.voicesForLocale(v);
                            settings.defaultPartnerVoice = voices.isNotEmpty ? voices.first['name'] as String : '';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Partner Voice:', style: TextStyle(fontSize: 14, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(builder: (context) {
                            final partnerVoices = provider.voicesForLocale(settings.defaultPartnerLanguage);
                            final currentVoice = partnerVoices.any((v) => v['name'] == settings.defaultPartnerVoice)
                                ? settings.defaultPartnerVoice
                                : (partnerVoices.isNotEmpty ? partnerVoices.first['name'] as String : null);
                            return DropdownButtonFormField<String>(
                              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              value: currentVoice,
                              items: partnerVoices.isEmpty
                                  ? [const DropdownMenuItem<String>(value: null, child: Text('No voices available'))]
                                  : partnerVoices.map((v) {
                                      final name = v['name'] as String? ?? '';
                                      final gender = (v['ssml_gender'] as String? ?? '').toLowerCase();
                                      return DropdownMenuItem<String>(value: name, child: Text('$name ($gender)'));
                                    }).toList(),
                              onChanged: (v) { if (v != null) setState(() { settings.defaultPartnerVoice = v; }); },
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _testTtsVoice(settings.defaultPartnerVoice, provider),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          child: const Text('Test'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Location override languages table
                    const Text(
                      'Location Override Languages',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Languages available for location-specific overrides. Select the active one from the User Current Location page.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ..._locationOverrideRows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final row = entry.value;
                      final rowLocale = row['locale'] ?? kDefaultPartnerLanguage;
                      final rowVoice = row['voice'] ?? '';
                      final rowVoices = provider.voicesForLocale(rowLocale);
                      final voiceValue = rowVoices.any((v) => v['name'] == rowVoice)
                          ? rowVoice
                          : (rowVoices.isNotEmpty ? rowVoices.first['name'] as String : null);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                value: kSupportedLanguages.any((l) => l['value'] == rowLocale) ? rowLocale : kSupportedLanguages.first['value'],
                                items: kSupportedLanguages
                                    .map((l) => DropdownMenuItem<String>(value: l['value'], child: Text(l['label']!)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      final voices = provider.voicesForLocale(v);
                                      _locationOverrideRows[i] = {'locale': v, 'voice': voices.isNotEmpty ? voices.first['name'] as String : ''};
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                value: voiceValue,
                                items: rowVoices.isEmpty
                                    ? [const DropdownMenuItem<String>(value: null, child: Text('No voices'))]
                                    : rowVoices.map((v) {
                                        final name = v['name'] as String? ?? '';
                                        final gender = (v['ssml_gender'] as String? ?? '').toLowerCase();
                                        return DropdownMenuItem<String>(value: name, child: Text('$name ($gender)', overflow: TextOverflow.ellipsis));
                                      }).toList(),
                                onChanged: (v) { if (v != null) setState(() { _locationOverrideRows[i]['voice'] = v; }); },
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Remove',
                              onPressed: () => setState(() => _locationOverrideRows.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Location Language'),
                      onPressed: () {
                        setState(() {
                          final firstLocale = kSupportedLanguages.first['value']!;
                          final voices = provider.voicesForLocale(firstLocale);
                          _locationOverrideRows.add({'locale': firstLocale, 'voice': voices.isNotEmpty ? voices.first['name'] as String : ''});
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Audio Settings Section
                _buildSectionCard(
                  title: 'Audio Settings',
                  icon: Icons.volume_up,
                  iconColor: Colors.green,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Speech Rate (WPM):',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Speech Rate with plus/minus buttons
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                if (settings.speechRate > 100) {
                                  setState(() {
                                    settings.speechRate = (settings.speechRate - 10).clamp(100, 300);
                                  });
                                }
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Decrease by 10',
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${settings.speechRate}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                if (settings.speechRate < 300) {
                                  setState(() {
                                    settings.speechRate = (settings.speechRate + 10).clamp(100, 300);
                                  });
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Increase by 10',
                            ),
                          ],
                        ),
                        Text(
                          'Words Per Minute: ${settings.speechRate} (${(settings.speechRate < 150) ? "Slow" : (settings.speechRate > 220) ? "Fast" : "Normal"})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'Volume Calibration:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use these buttons to activate a specific audio output, then use the device hardware buttons to adjust the volume for that output.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  // Test Personal Audio (Bluetooth/Headphones) and capture volume
                                  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
                                    try {
                                      // Play a test tone using just_audio
                                      final player = AudioPlayer();
                                      
                                      try {
                                        await player.setAsset('assets/volumetesttone.mp3');
                                        // Apply current admin personal volume as software volume
                                        // so the test tone previews the actual playback level.
                                        final currentPersonalVol = settings.personalVolume;
                                        final testVolume = (currentPersonalVol / 10.0).clamp(0.0, 1.0);
                                        debugPrint('🔊 ADMIN: Playing personal test tone at software volume $testVolume (setting: $currentPersonalVol/10)');
                                        await player.setVolume(testVolume);

                                        // Route to personal device (Bluetooth/headphones) for testing
                                        final platform = MethodChannel('audio_routing');
                                        if (Platform.isIOS) {
                                          await platform.invokeMethod('routeToPersonal');
                                        } else {
                                          await platform.invokeMethod('resetToDefault');
                                        }
                                        await Future.delayed(const Duration(milliseconds: 100));

                                        await player.play();
                                        
                                        // Wait for playback to complete
                                        await player.playerStateStream.firstWhere(
                                          (state) => state.processingState == ProcessingState.completed
                                        );
                                        
                                        // After test tone finishes, capture the current device volume
                                        if (Platform.isAndroid || Platform.isIOS) {
                                          try {
                                            debugPrint('Capturing current personal volume level from device...');
                                            final capturedVolume = await platform.invokeMethod<int>(
                                              'captureCurrentVolume',
                                              {'isPersonal': true},
                                            );
                                            
                                            if (capturedVolume != null && mounted) {
                                              debugPrint('🔊 ADMIN: Captured personal volume: $capturedVolume/10');
                                              
                                              // Persist locally so volume stays consistent even if backend resets
                                              final prefs = await SharedPreferences.getInstance();
                                              await prefs.setBool('personalVolumeOverride', true);
                                              await prefs.setInt('personalVolumeOverrideValue', capturedVolume);

                                              // Update the settings with the captured volume
                                              settings.personalVolume = capturedVolume;
                                              await provider.saveSettings(settings);
                                              
                                              debugPrint('🔊 ADMIN: Saved personal volume to settings: $capturedVolume/10');
                                              
                                              // Show confirmation to user
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Personal volume saved: $capturedVolume/10'),
                                                    duration: const Duration(seconds: 2),
                                                  ),
                                                );
                                              }
                                            }
                                          } on MissingPluginException {
                                            debugPrint('🔊 ADMIN: captureCurrentVolume not registered. A full app restart is required after native changes.');
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Native update detected. Please fully restart the app to enable volume capture.'),
                                                  duration: Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          }
                                        } else {
                                          debugPrint('🔊 ADMIN: Volume capture is not supported on this platform.');
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Volume capture is not supported on this platform.'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        }
                                      } finally {
                                        await player.dispose();
                                      }
                                    } catch (e) {
                                      debugPrint('Error testing personal audio or capturing volume: $e');
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.headset),
                                label: const Text('Adjust Personal Volume'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade100,
                                  foregroundColor: Colors.blue.shade900,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  // Test System Audio (Built-in Speaker) and capture volume
                                  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
                                    try {
                                      // Play a test tone using just_audio
                                      final player = AudioPlayer();
                                      
                                      try {
                                        await player.setAsset('assets/volumetesttone.mp3');
                                        // Apply current admin system volume as software volume
                                        // so the test tone previews the actual playback level.
                                        final currentSystemVol = settings.systemVolume;
                                        final testVolume = (currentSystemVol / 10.0).clamp(0.0, 1.0);
                                        debugPrint('🔊 ADMIN: Playing system test tone at software volume $testVolume (setting: $currentSystemVol/10)');
                                        await player.setVolume(testVolume);

                                        // Force speaker AFTER configuring player to ensure override persists
                                        final platform = MethodChannel('audio_routing');
                                        await platform.invokeMethod('forceSpeaker');
                                        await Future.delayed(const Duration(milliseconds: 100));

                                        await player.play();
                                        
                                        // Wait for playback to complete
                                        await player.playerStateStream.firstWhere(
                                          (state) => state.processingState == ProcessingState.completed
                                        );
                                        
                                        // After test tone finishes, capture the current device volume
                                        if (Platform.isAndroid || Platform.isIOS) {
                                          try {
                                            debugPrint('Capturing current system volume level from device...');
                                            final capturedVolume = await platform.invokeMethod<int>(
                                              'captureCurrentVolume',
                                              {'isPersonal': false},
                                            );
                                            
                                            if (capturedVolume != null && mounted) {
                                              debugPrint('🔊 ADMIN: Captured system volume: $capturedVolume/10');
                                              
                                              // Persist locally so volume stays consistent even if backend resets
                                              final prefs = await SharedPreferences.getInstance();
                                              await prefs.setBool('systemVolumeOverride', true);
                                              await prefs.setInt('systemVolumeOverrideValue', capturedVolume);

                                              // Update the settings with the captured volume
                                              settings.systemVolume = capturedVolume;
                                              await provider.saveSettings(settings);
                                              
                                              debugPrint('🔊 ADMIN: Saved system volume to settings: $capturedVolume/10');
                                              
                                              // Show confirmation to user
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('System volume saved: $capturedVolume/10'),
                                                    duration: const Duration(seconds: 2),
                                                  ),
                                                );
                                              }
                                            }
                                          } on MissingPluginException {
                                            debugPrint('🔊 ADMIN: captureCurrentVolume not registered. A full app restart is required after native changes.');
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Native update detected. Please fully restart the app to enable volume capture.'),
                                                  duration: Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          }
                                        } else {
                                          debugPrint('🔊 ADMIN: Volume capture is not supported on this platform.');
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Volume capture is not supported on this platform.'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        }
                                      } finally {
                                        await player.dispose();
                                      }
                                    } catch (e) {
                                      debugPrint('Error testing system audio or capturing volume: $e');
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.volume_up),
                                label: const Text('Adjust System Volume'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade100,
                                  foregroundColor: Colors.green.shade900,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'TTS Voice:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                value: settings.selectedTtsVoiceName.isNotEmpty && 
                                       provider.availableTtsVoices.contains(settings.selectedTtsVoiceName)
                                    ? settings.selectedTtsVoiceName 
                                    : (provider.availableTtsVoices.isNotEmpty 
                                       ? provider.availableTtsVoices.first 
                                       : null),
                                items: provider.availableTtsVoicesDetailed.isEmpty 
                                    ? [
                                        DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('Loading voices...'),
                                        )
                                      ]
                                    : provider.availableTtsVoicesDetailed.map((voiceData) {
                                        final voiceName = voiceData['name'] as String? ?? 'Unknown';
                                        final gender = voiceData['ssml_gender'] as String? ?? 'Unknown';
                                        
                                        return DropdownMenuItem<String>(
                                          value: voiceName,
                                          child: Text('$voiceName (${gender.toLowerCase()})'),
                                        );
                                      }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      settings.selectedTtsVoiceName = newValue;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                final selectedVoice = settings.selectedTtsVoiceName;
                                if (selectedVoice.isNotEmpty) {
                                  await _testTtsVoice(selectedVoice, provider);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please select a voice first'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Test'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Display Settings Section
                _buildSectionCard(
                  title: 'Display Settings',
                  icon: Icons.display_settings,
                  iconColor: Colors.orange,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Button Size:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                if (settings.gridColumns < 18) {
                                  setState(() {
                                    settings.gridColumns = (settings.gridColumns + 1).clamp(2, 18);
                                  });
                                }
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Smaller buttons',
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${settings.gridColumns} columns',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                if (settings.gridColumns > 2) {
                                  setState(() {
                                    settings.gridColumns = (settings.gridColumns - 1).clamp(2, 18);
                                  });
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Larger buttons',
                            ),
                          ],
                        ),
                        const Text(
                          'Adjust the number of columns to control button size (2 = largest buttons, 18 = smallest buttons).',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Menu Bar Location
                        const Text(
                          'Menu Bar Location:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final pos in ['left', 'top', 'right', 'bottom'])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () async {
                                      setState(() => _menuPosition = pos);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setString('tap_menu_position', pos);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _menuPosition == pos
                                            ? Colors.orange.shade100
                                            : Colors.grey.shade100,
                                        border: Border.all(
                                          color: _menuPosition == pos
                                              ? Colors.orange.shade400
                                              : Colors.grey.shade300,
                                          width: _menuPosition == pos ? 2 : 1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            pos == 'left'   ? Icons.border_left
                                            : pos == 'top'  ? Icons.border_top
                                            : pos == 'right'? Icons.border_right
                                                            : Icons.border_bottom,
                                            size: 24,
                                            color: _menuPosition == pos
                                                ? Colors.orange.shade700
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${pos[0].toUpperCase()}${pos.substring(1)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: _menuPosition == pos
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: _menuPosition == pos
                                                  ? Colors.orange.shade700
                                                  : Colors.grey.shade600,
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
                        const SizedBox(height: 6),
                        const Text(
                          'Choose which edge of the screen the Boards panel appears on.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),

                        // Tap Sensitivity
                        const Text(
                          'Tap Sensitivity:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final option in [
                              (ms: 0,   label: 'Normal',  icon: Icons.touch_app),
                              (ms: 100, label: 'Low',     icon: Icons.pan_tool_alt),
                              (ms: 200, label: 'Medium',  icon: Icons.back_hand),
                              (ms: 300, label: 'High',    icon: Icons.front_hand),
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () async {
                                      setState(() => _tapMinDurationMs = option.ms);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setInt('tap_min_duration_ms', option.ms);
                                      debugPrint('[TapSensitivity] Saved tap_min_duration_ms=${option.ms} to SharedPreferences');
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _tapMinDurationMs == option.ms
                                            ? Colors.orange.shade100
                                            : Colors.grey.shade100,
                                        border: Border.all(
                                          color: _tapMinDurationMs == option.ms
                                              ? Colors.orange.shade400
                                              : Colors.grey.shade300,
                                          width: _tapMinDurationMs == option.ms ? 2 : 1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            option.icon,
                                            size: 24,
                                            color: _tapMinDurationMs == option.ms
                                                ? Colors.orange.shade700
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            option.label,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: _tapMinDurationMs == option.ms
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: _tapMinDurationMs == option.ms
                                                  ? Colors.orange.shade700
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                          if (option.ms > 0)
                                            Text(
                                              '${option.ms}ms',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _tapMinDurationMs == option.ms
                                                    ? Colors.orange.shade500
                                                    : Colors.grey.shade400,
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
                        const SizedBox(height: 6),
                        const Text(
                          'Require a longer press to register a tap, reducing accidental activations.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),

                        // Color Settings
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Light Color:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showColorPicker(
                                context,
                                settings.lightColor,
                                (Color color) {
                                  setState(() {
                                    settings.lightColor = color;
                                  });
                                },
                              ),
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: settings.lightColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Dark Color:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showColorPicker(
                                context,
                                settings.darkColor,
                                (Color color) {
                                  setState(() {
                                    settings.darkColor = color;
                                  });
                                },
                              ),
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: settings.darkColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),



                        // Scanning interface pictograms setting
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Enable Pictograms (Scanning Interface)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Show pictogram images on buttons in the Auditory Scanning interface.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.enablePictograms,
                              onChanged: (value) {
                                setState(() {
                                  settings.enablePictograms = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Tap interface pictogram disable setting
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Disable Tap Interface Pictograms',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'When enabled, Tap Interface will not try to match or display images and will not apply sight word formatting.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.disableTapPictograms,
                              onChanged: (value) {
                                setState(() {
                                  settings.disableTapPictograms = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),



                        // Sight Words Settings
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Enable Sight Word Logic',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Use Dolch sight word logic to show sight words as text-only (no pictograms). When disabled, all words will show pictograms if pictograms are enabled.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.enableSightWords,
                              onChanged: (value) {
                                setState(() {
                                  settings.enableSightWords = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Sight Word Grade Level
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sight Words Grade Level:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: settings.sightWordGradeLevel,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'pre_k', child: Text('Pre-Kindergarten')),
                                DropdownMenuItem(value: 'kindergarten', child: Text('Kindergarten (includes Pre-K)')),
                                DropdownMenuItem(value: 'first_grade', child: Text('First Grade (includes Pre-K + K)')),
                                DropdownMenuItem(value: 'second_grade', child: Text('Second Grade (includes Pre-K + K + 1st)')),
                                DropdownMenuItem(value: 'third_grade', child: Text('Third Grade (includes Pre-K + K + 1st + 2nd)')),
                                DropdownMenuItem(value: 'third_grade_with_nouns', child: Text('Third Grade + Nouns (complete list)')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    settings.sightWordGradeLevel = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Dolch sight words at or below this level will show as text-only buttons (no pictograms) even when pictograms are enabled. Selection is cumulative - higher grades include all lower grade words.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Spell Page Letter Order
                        const Text(
                          'Spell Page Letter Order:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: settings.spellLetterOrder,
                          items: const [
                            DropdownMenuItem<String>(
                              value: 'alphabetical',
                              child: Text('Alphabetical (A-Z)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'qwerty',
                              child: Text('QWERTY Keyboard'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'frequency',
                              child: Text('Frequency-Based'),
                            ),
                          ],
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                settings.spellLetterOrder = newValue;
                              });
                            }
                          },
                        ),
                        const Text(
                          'Letter arrangement for the Spell page in Tap Interface and Freestyle.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Vocabulary Level
                        const Text(
                          'Vocabulary Level:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: settings.vocabularyLevel,
                          items: const [
                            DropdownMenuItem<String>(
                              value: 'emergent',
                              child: Text('Emergent - Basic everyday words (e.g., want, help, happy)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'functional',
                              child: Text('Functional - Practical daily living vocabulary (e.g., tired, wonderful, choose)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'developing',
                              child: Text('Developing - Expanded academic vocabulary (e.g., anxious, fascinating, investigate)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'proficient',
                              child: Text('Proficient - Sophisticated specialized vocabulary (e.g., lethargic, magnificent, articulate)'),
                            ),
                          ],
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                settings.vocabularyLevel = newValue;
                              });
                            }
                          },
                        ),
                        const Text(
                          'Controls the complexity of AI-generated vocabulary to match the user\'s communication level. Higher levels use more advanced words.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Auditory Scanning Settings Section
                _buildSectionCard(
                  title: 'Auditory Scanning Settings',
                  icon: Icons.hearing,
                  iconColor: Colors.purple,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auditory Scan Speed (ms):',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Scan Delay with plus/minus buttons
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                if (settings.scanDelay > 100) {
                                  setState(() {
                                    settings.scanDelay = (settings.scanDelay - 100).clamp(100, 10000);
                                  });
                                }
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Decrease by 100ms',
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${settings.scanDelay}ms',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                if (settings.scanDelay < 10000) {
                                  setState(() {
                                    settings.scanDelay = (settings.scanDelay + 100).clamp(100, 10000);
                                  });
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Increase by 100ms',
                            ),
                          ],
                        ),
                        Text(
                          'Delay between highlighting buttons: ${settings.scanDelay}ms',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Scan Loop Limit with dropdown
                        _buildNumberDropdown(
                          currentValue: settings.scanLoopLimit,
                          label: 'Scan Loop Limit',
                          helperText: 'Number of complete scanning cycles before pausing (0 = unlimited, 1-10 = limit cycles)',
                          minValue: 0,
                          maxValue: 10,
                          onChanged: (value) {
                            setState(() {
                              settings.scanLoopLimit = value;
                              _scanLoopLimitController.text = value.toString();
                            });
                          },
                        ),
                        const SizedBox(height: 20),

                        // Wait for Switch to Start Scanning
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Wait for Switch to Start Scanning',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'When enabled, scanning will pause on page load until the switch is pressed. Useful for giving users time to prepare before scanning begins.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.waitForSwitchToScan,
                              onChanged: (value) async {
                                print('🔔 BEFORE: waitForSwitchToScan = ${settings.waitForSwitchToScan}');
                                setState(() {
                                  settings.waitForSwitchToScan = value;
                                });
                                print('🔔 AFTER setState: waitForSwitchToScan = ${settings.waitForSwitchToScan}');
                                print('🔔 Full settings object: ${settings.toJson()}');
                                
                                // Auto-save when toggled
                                final provider = Provider.of<UserSettingsProvider>(context, listen: false);
                                final success = await provider.saveSettings(settings);
                                print('🔔 Save result: $success');
                                
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(success 
                                        ? 'Wait for Switch setting saved: $value' 
                                        : 'Failed to save Wait for Switch setting'),
                                      backgroundColor: success ? Colors.green : Colors.red,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Page Ready Chime',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'When enabled, a chime will play after a page has been loaded and is waiting for the switch to begin scanning.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.playWaitForSwitchChime,
                              onChanged: (value) async {
                                setState(() {
                                  settings.playWaitForSwitchChime = value;
                                });

                                final provider = Provider.of<UserSettingsProvider>(
                                  context,
                                  listen: false,
                                );
                                final success = await provider.saveSettings(settings);

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(success
                                          ? 'Wait chime setting saved: $value'
                                          : 'Failed to save wait chime setting'),
                                      backgroundColor:
                                          success ? Colors.green : Colors.red,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Scan Mode Selection
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Scan Mode',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: settings.scanMode == 'step' ? 'step' : 'auto',
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: const [
                                DropdownMenuItem<String>(
                                  value: 'auto',
                                  child: Text('Auto - advances by timer'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'step',
                                  child: Text('Step - advances with Tab switch'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) {
                                  setState(() {
                                    settings.scanMode = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Auto mode cycles options on a timer. Step mode waits for the second switch (Tab) to move to the next option.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),

                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Save Button
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _saveSettings,
                    child: const Text(
                      'Save Settings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
