import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/user_settings_provider.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({Key? key}) : super(key: key);

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  bool _isInitialized = false;
  
  // Controllers for editable fields
  final TextEditingController _toolbarPinController = TextEditingController();
  final TextEditingController _wakeWordInterjectionController = TextEditingController();
  final TextEditingController _wakeWordNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeProvider();
  }
  
  @override
  void dispose() {
    _toolbarPinController.dispose();
    _wakeWordInterjectionController.dispose();
    _wakeWordNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeProvider() async {
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      await userSettings.fetchSettings();
      
      // Initialize text controllers with loaded values
      if (userSettings.settings != null) {
        _toolbarPinController.text = userSettings.settings!.toolbarPIN;
        _wakeWordInterjectionController.text = userSettings.settings!.wakeWordInterjection;
        _wakeWordNameController.text = userSettings.settings!.wakeWordName;
        _locationController.text = userSettings.settings!.countryCode;
      }
      
      // Fetch available options
      await userSettings.fetchTtsVoices();
      await userSettings.fetchLlmModels();
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing provider: $e');
      setState(() {
        _isInitialized = true;
      });
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

  // Helper method to convert model names to display names
  String _getLlmModelDisplayName(String modelName) {
    switch (modelName) {
      case 'models/gemini-1.5-flash-latest':
        return 'Gemini 1.5 Flash (Latest)';
      case 'models/gemini-1.5-pro-latest':
        return 'Gemini 1.5 Pro (Latest)';
      case 'models/gemini-2.0-flash-exp':
        return 'Gemini 2.0 Flash (Experimental)';
      case 'models/gemini-2.5-flash':
        return 'Gemini 2.5 Flash';
      case 'models/gemini-pro':
        return 'Gemini Pro';
      default:
        final parts = modelName.split('/');
        final name = parts.length > 1 ? parts.last : modelName;
        return name.replaceAll('-', ' ').split(' ').map((word) => 
          word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : word
        ).join(' ');
    }
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
                  final settings = userSettings.settings!;
                  setValue(settings, value);
                  userSettings.saveSettings(settings);
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
      settings.wakeWordInterjection = _wakeWordInterjectionController.text;
      settings.wakeWordName = _wakeWordNameController.text;
      settings.countryCode = _locationController.text;
      
      await settingsProvider.saveSettings(settings);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e')),
      );
    }
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
          if (!_isInitialized || provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.settings == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning, size: 64, color: Colors.orange),
                  SizedBox(height: 16),
                  Text(
                    'Settings not available',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Please login first or try refreshing.'),
                ],
              ),
            );
          }

          final settings = provider.settings!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Security Section
                _buildSectionCard(
                  title: 'Security',
                  icon: Icons.security,
                  iconColor: Colors.red,
                  children: [
                    _buildTextField(
                      controller: _toolbarPinController,
                      label: 'Toolbar PIN',
                      hint: 'Enter a PIN to secure the toolbar',
                      helperText: 'Leave blank to disable PIN protection',
                      keyboardType: TextInputType.number,
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
                      getValue: (s) => s.useShortSummaryOnButtons,
                      setValue: (s, v) => s.useShortSummaryOnButtons = v,
                      title: 'Summary Mode',
                      subtitle: 'Enable to show abbreviated content',
                    ),
                    const SizedBox(height: 12),
                    
                    _buildSettingsCheckbox(
                      userSettings: provider,
                      getValue: (s) => s.autoClean,
                      setValue: (s, v) => s.autoClean = v,
                      title: 'Auto-Clean Categories',
                      subtitle: 'Automatically clean categories when selected',
                    ),
                    const SizedBox(height: 20),

                    _buildTextField(
                      controller: _locationController,
                      label: 'Location',
                      hint: 'Enter your location',
                      helperText: 'Used for location-based AI responses',
                    ),
                    const SizedBox(height: 20),

                    // LLM Model Configuration Subsection
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
                            'LLM Model Configuration',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'LLM Model:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                value: settings.primaryLlmModel.isNotEmpty &&
                                       provider.availableLlmModels.contains(settings.primaryLlmModel)
                                    ? settings.primaryLlmModel
                                    : (provider.availableLlmModels.isNotEmpty
                                       ? provider.availableLlmModels.first
                                       : null),
                                items: provider.availableLlmModels.map((model) {
                                  return DropdownMenuItem<String>(
                                    value: model,
                                    child: Text(_getLlmModelDisplayName(model)),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    settings.primaryLlmModel = newValue;
                                    provider.saveSettings(settings);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
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
                          'Speech Rate:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: settings.speechRate.toDouble(),
                          min: 50,
                          max: 300,
                          divisions: 25,
                          label: settings.speechRate.toString(),
                          onChanged: (double value) {
                            settings.speechRate = value.round();
                            provider.saveSettings(settings);
                          },
                        ),
                        Text(
                          'Rate: ${settings.speechRate}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
                                items: provider.availableTtsVoices.map((voice) {
                                  return DropdownMenuItem<String>(
                                    value: voice,
                                    child: Text(voice),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    settings.selectedTtsVoiceName = newValue;
                                    provider.saveSettings(settings);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Testing TTS voice...'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
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
                          'Grid Columns:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: settings.gridColumns.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: settings.gridColumns.toString(),
                          onChanged: (double value) {
                            settings.gridColumns = value.round();
                            provider.saveSettings(settings);
                          },
                        ),
                        Text(
                          'Columns: ${settings.gridColumns}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
                                  settings.lightColor = color;
                                  provider.saveSettings(settings);
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
                                  settings.darkColor = color;
                                  provider.saveSettings(settings);
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
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                              settings.spellLetterOrder = newValue;
                              provider.saveSettings(settings);
                            }
                          },
                        ),
                        Text(
                          'Letter arrangement for the Spell page',
                          style: const TextStyle(
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
                          'Scan Delay (ms):',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: settings.scanDelay.toDouble(),
                          min: 500,
                          max: 10000,
                          divisions: 19,
                          label: settings.scanDelay.toString(),
                          onChanged: (double value) {
                            settings.scanDelay = value.round();
                            provider.saveSettings(settings);
                          },
                        ),
                        Text(
                          'Delay: ${settings.scanDelay}ms',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'Scan Loop Limit:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: settings.scanLoopLimit.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: settings.scanLoopLimit.toString(),
                          onChanged: (double value) {
                            settings.scanLoopLimit = value.round();
                            provider.saveSettings(settings);
                          },
                        ),
                        Text(
                          'Loops: ${settings.scanLoopLimit}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),

                        _buildSettingsCheckbox(
                          userSettings: provider,
                          getValue: (s) => s.enableAuditoryScanning,
                          setValue: (s, v) => s.enableAuditoryScanning = v,
                          title: 'Auditory Scanning',
                          subtitle: 'Enable voice-guided scanning mode',
                        ),
                        const SizedBox(height: 12),

                        _buildSettingsCheckbox(
                          userSettings: provider,
                          getValue: (s) => s.waitForSwitchToScan,
                          setValue: (s, v) => s.waitForSwitchToScan = v,
                          title: 'Wait for Switch to Start Scanning',
                          subtitle: 'Require switch press to begin scanning on first page',
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
