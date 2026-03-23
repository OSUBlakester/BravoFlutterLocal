import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  final TextEditingController _wakeWordsController = TextEditingController();
  final TextEditingController _llmOptionsController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeProvider();
  }
  
  @override
  void dispose() {
    _toolbarPinController.dispose();
    _wakeWordsController.dispose();
    _llmOptionsController.dispose();
    _locationController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeProvider() async {
    try {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      await userSettings.loadSettings();
      
      // Initialize text controllers with loaded values
      if (userSettings.settings != null) {
        _toolbarPinController.text = userSettings.settings!.toolbarPIN ?? '';
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
        Color selectedColor = currentColor;
        return AlertDialog(
          title: const Text('Pick a Color'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Simple color grid
                GridView.builder(
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
                        selectedColor = color;
                        onColorChanged(color);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selectedColor == color ? Colors.black : Colors.grey,
                            width: selectedColor == color ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
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
        // Extract a cleaner name from the model path
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

  // Helper method to build consistent checkboxes
  Widget _buildCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String title,
    String? subtitle,
  }) {
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
              value: value,
              onChanged: onChanged,
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
    
    try {
      // The settings are automatically saved by the provider when changed
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
          // Show loading while initializing or while provider is loading
          if (!_isInitialized || provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Check if settings are available
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
                      hint: 'Enter a PIN to secure the toolbar (1-6 digits)',
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
                    _buildTextField(
                      controller: _wakeWordsController,
                      label: 'Wake Words',
                      hint: 'Enter wake words separated by commas',
                      helperText: 'Words that trigger voice activation',
                    ),
                    const SizedBox(height: 20),
                    
                    _buildTextField(
                      controller: _llmOptionsController,
                      label: 'LLM Options',
                      hint: 'Enter LLM options (comma-separated)',
                      helperText: 'Additional options for the language model',
                    ),
                    const SizedBox(height: 20),

                    Consumer<UserSettingsProvider>(
                      builder: (context, userSettings, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCheckbox(
                              value: userSettings.summaryMode,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setSummaryMode(value);
                                }
                              },
                              title: 'Summary Mode',
                              subtitle: 'Enable to show abbreviated content',
                            ),
                            const SizedBox(height: 12),
                            
                            _buildCheckbox(
                              value: userSettings.autoCleanCategories,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setAutoCleanCategories(value);
                                }
                              },
                              title: 'Auto-Clean Categories',
                              subtitle: 'Automatically clean categories when selected',
                            ),
                          ],
                        );
                      },
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
                          Consumer<UserSettingsProvider>(
                            builder: (context, userSettings, child) {
                              return Column(
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
                                    value: userSettings.llmModel.isNotEmpty &&
                                           userSettings.availableLlmModels.contains(userSettings.llmModel)
                                        ? userSettings.llmModel
                                        : (userSettings.availableLlmModels.isNotEmpty
                                           ? userSettings.availableLlmModels.first
                                           : null),
                                    items: userSettings.availableLlmModels.map((model) {
                                      return DropdownMenuItem<String>(
                                        value: model,
                                        child: Text(_getLlmModelDisplayName(model)),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        userSettings.setLlmModel(newValue);
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
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
                    Consumer<UserSettingsProvider>(
                      builder: (context, userSettings, child) {
                        return Column(
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
                              value: userSettings.speechRate,
                              min: 0.1,
                              max: 3.0,
                              divisions: 29,
                              label: userSettings.speechRate.toStringAsFixed(1),
                              onChanged: (double value) {
                                userSettings.setSpeechRate(value);
                              },
                            ),
                            Text(
                              'Rate: ${userSettings.speechRate.toStringAsFixed(1)}',
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
                                    value: userSettings.ttsVoice.isNotEmpty && 
                                           userSettings.availableTtsVoices.contains(userSettings.ttsVoice)
                                        ? userSettings.ttsVoice 
                                        : (userSettings.availableTtsVoices.isNotEmpty 
                                           ? userSettings.availableTtsVoices.first 
                                           : null),
                                    items: userSettings.availableTtsVoices.map((voice) {
                                      return DropdownMenuItem<String>(
                                        value: voice,
                                        child: Text(voice),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        userSettings.setTtsVoice(newValue);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    // Test TTS voice
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
                        );
                      },
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
                    Consumer<UserSettingsProvider>(
                      builder: (context, userSettings, child) {
                        return Column(
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
                              value: userSettings.gridColumns.toDouble(),
                              min: 1,
                              max: 10,
                              divisions: 9,
                              label: userSettings.gridColumns.toString(),
                              onChanged: (double value) {
                                userSettings.setGridColumns(value.round());
                              },
                            ),
                            Text(
                              'Columns: ${userSettings.gridColumns}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 20),

                            _buildCheckbox(
                              value: userSettings.showCategoryButtons,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setShowCategoryButtons(value);
                                }
                              },
                              title: 'Show Category Buttons',
                              subtitle: 'Display category buttons in the interface',
                            ),
                            const SizedBox(height: 12),

                            _buildCheckbox(
                              value: userSettings.singleButtonMode,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setSingleButtonMode(value);
                                }
                              },
                              title: 'Single Button Mode',
                              subtitle: 'Use single button interface for easier access',
                            ),
                            const SizedBox(height: 12),

                            _buildCheckbox(
                              value: userSettings.largeButtonMode,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setLargeButtonMode(value);
                                }
                              },
                              title: 'Large Button Mode',
                              subtitle: 'Use larger buttons for better visibility',
                            ),
                            const SizedBox(height: 20),

                            // Color Settings
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Button Background Color:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showColorPicker(
                                    context,
                                    userSettings.buttonBackgroundColor,
                                    (Color color) => userSettings.setButtonBackgroundColor(color),
                                  ),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: userSettings.buttonBackgroundColor,
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
                                  'Button Text Color:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showColorPicker(
                                    context,
                                    userSettings.buttonTextColor,
                                    (Color color) => userSettings.setButtonTextColor(color),
                                  ),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: userSettings.buttonTextColor,
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
                                  'Grid Background Color:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showColorPicker(
                                    context,
                                    userSettings.gridBackgroundColor,
                                    (Color color) => userSettings.setGridBackgroundColor(color),
                                  ),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: userSettings.gridBackgroundColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
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
                    Consumer<UserSettingsProvider>(
                      builder: (context, userSettings, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Scan Delay (seconds):',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: userSettings.scanDelay,
                              min: 0.5,
                              max: 5.0,
                              divisions: 18,
                              label: userSettings.scanDelay.toStringAsFixed(1),
                              onChanged: (double value) {
                                userSettings.setScanDelay(value);
                              },
                            ),
                            Text(
                              'Delay: ${userSettings.scanDelay.toStringAsFixed(1)}s',
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
                              value: userSettings.scanLoopLimit.toDouble(),
                              min: 1,
                              max: 10,
                              divisions: 9,
                              label: userSettings.scanLoopLimit.toString(),
                              onChanged: (double value) {
                                userSettings.setScanLoopLimit(value.round());
                              },
                            ),
                            Text(
                              'Loops: ${userSettings.scanLoopLimit}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 20),

                            _buildCheckbox(
                              value: userSettings.auditoryScanMode,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setAuditoryScanMode(value);
                                }
                              },
                              title: 'Auditory Scanning',
                              subtitle: 'Enable voice-guided scanning mode',
                            ),
                            const SizedBox(height: 12),

                            _buildCheckbox(
                              value: userSettings.skipRecent,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setSkipRecent(value);
                                }
                              },
                              title: 'Skip Recent',
                              subtitle: 'Skip recently selected items during scanning',
                            ),
                            const SizedBox(height: 12),

                            _buildCheckbox(
                              value: userSettings.askMeMode,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  userSettings.setAskMeMode(value);
                                }
                              },
                              title: 'Ask Me Mode',
                              subtitle: 'Enable interactive questioning during scanning',
                            ),
                          ],
                        );
                      },
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
