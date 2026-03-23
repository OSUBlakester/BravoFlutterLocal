import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '../models/tap_navigation_models.dart';
import '../services/tap_interface_api_service.dart';
import '../services/user_settings_provider.dart';

class TapInterfaceAdminPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;

  const TapInterfaceAdminPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
  });

  @override
  State<TapInterfaceAdminPage> createState() => _TapInterfaceAdminPageState();
}

class _TapInterfaceAdminPageState extends State<TapInterfaceAdminPage> {
  TapNavigationConfig? currentConfig;
  TapNavigationConfig? originalConfig;
  TapNavigationButton? selectedButton;
  ButtonPath? selectedPath;

  bool hasUnsavedChanges = false;
  bool isLoading = false;
  String? error;

  // Drag and drop state
  ButtonPath? draggedPath;
  bool isDragging = false;

  // Form controllers
  final TextEditingController labelController = TextEditingController();
  final TextEditingController speechTextController = TextEditingController();
  final TextEditingController imageUrlController = TextEditingController();
  final TextEditingController customAudioFileController = TextEditingController();
  final TextEditingController backgroundColorController = TextEditingController();
  final TextEditingController textColorController = TextEditingController();
  final TextEditingController llmPromptController = TextEditingController();
  final TextEditingController wordsPromptController = TextEditingController();
  final TextEditingController staticOptionsController = TextEditingController();
  final TextEditingController specialPageController = TextEditingController();
  
  // Form state
  bool _isHidden = false;

  TapInterfaceApiService? apiService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      apiService = TapInterfaceApiService(
        apiBaseUrl: userSettings.apiBaseUrl,
        idToken: widget.idToken,
        userId: widget.aacUserId,
      );
      _loadConfiguration();
    });

    // Add listeners to form controllers
    _addFormListeners();
  }

  @override
  void dispose() {
    labelController.dispose();
    speechTextController.dispose();
    imageUrlController.dispose();
    customAudioFileController.dispose();
    backgroundColorController.dispose();
    textColorController.dispose();
    llmPromptController.dispose();
    wordsPromptController.dispose();
    staticOptionsController.dispose();
    specialPageController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final config = await apiService?.loadConfiguration();
      if (config != null) {
        print('Loaded config: ${config.toJson()}');
        print('Number of buttons: ${config.buttons.length}');
        for (int i = 0; i < config.buttons.length; i++) {
          final button = config.buttons[i];
          print('Button $i: ${button.label}, LLM: ${button.llmPrompt}, Children: ${button.children.length}');
        }
        setState(() {
          currentConfig = config;
          originalConfig = TapNavigationConfig.fromJson(config.toJson());
          hasUnsavedChanges = false;
          isLoading = false;
        });
        _showSnackBar('Configuration loaded successfully!', isError: false);
      } else {
        setState(() {
          error = 'Failed to load configuration';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (currentConfig == null || !hasUnsavedChanges) return;

    setState(() {
      isLoading = true;
    });

    try {
      final success = await apiService?.saveConfiguration(currentConfig!);
      if (success == true) {
        setState(() {
          originalConfig = TapNavigationConfig.fromJson(currentConfig!.toJson());
          hasUnsavedChanges = false;
          isLoading = false;
        });
        _showSnackBar('Configuration saved successfully!', isError: false);
      } else {
        setState(() {
          isLoading = false;
        });
        _showSnackBar('Failed to save configuration', isError: true);
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      _showSnackBar('Error saving configuration: $e', isError: true);
    }
  }

  void _cancelChanges() {
    if (!hasUnsavedChanges) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes'),
        content: const Text('Are you sure you want to discard all unsaved changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                currentConfig = originalConfig != null 
                    ? TapNavigationConfig.fromJson(originalConfig!.toJson()) 
                    : null;
                selectedButton = null;
                selectedPath = null;
                hasUnsavedChanges = false;
              });
              _clearForm();
              // Force UI refresh
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {});
              });
              _showSnackBar('Changes canceled successfully!', isError: false);
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _markAsChanged() {
    setState(() {
      hasUnsavedChanges = true;
    });
  }

  void _selectButton(ButtonPath path) {
    final button = _getButtonByPath(path);
    if (button != null) {
      setState(() {
        selectedButton = button;
        selectedPath = path;
      });
      _populateForm(button);
    }
  }

  TapNavigationButton? _getButtonByPath(ButtonPath path) {
    if (currentConfig == null) return null;
    
    List<TapNavigationButton> currentList = currentConfig!.buttons;
    TapNavigationButton? current;

    for (int i = 0; i < path.indices.length; i++) {
      final index = path.indices[i];
      if (index >= currentList.length) return null;
      
      current = currentList[index];
      if (i < path.indices.length - 1) {
        currentList = current.children;
      }
    }
    
    return current;
  }

  void _populateForm(TapNavigationButton button) {
    print('Populating form for button: ${button.label}');
    print('Button data: ${button.toJson()}');
    
    // Temporarily remove listeners to prevent _updateButtonFromForm from being called
    _removeFormListeners();
    
    labelController.text = button.label;
    speechTextController.text = button.speechText ?? '';
    imageUrlController.text = button.imageUrl ?? '';
    customAudioFileController.text = button.customAudioFile ?? '';
    backgroundColorController.text = button.backgroundColor;
    llmPromptController.text = button.llmPrompt ?? '';
    wordsPromptController.text = button.wordsPrompt ?? '';
    staticOptionsController.text = button.staticOptions ?? '';
    specialPageController.text = button.specialPage ?? '';
    _isHidden = button.hidden;
    
    print('Form populated - LLM Prompt: "${llmPromptController.text}"');
    print('Form populated - LLM Prompt: "${llmPromptController.text}"');
    
    // Re-add listeners
    _addFormListeners();
  }

  void _removeFormListeners() {
    labelController.removeListener(_updateButtonFromForm);
    speechTextController.removeListener(_updateButtonFromForm);
    imageUrlController.removeListener(_updateButtonFromForm);
    customAudioFileController.removeListener(_updateButtonFromForm);
    llmPromptController.removeListener(_updateButtonFromForm);
    wordsPromptController.removeListener(_updateButtonFromForm);
    staticOptionsController.removeListener(_updateButtonFromForm);
    specialPageController.removeListener(_updateButtonFromForm);
  }

  void _addFormListeners() {
    labelController.addListener(_updateButtonFromForm);
    speechTextController.addListener(_updateButtonFromForm);
    imageUrlController.addListener(_updateButtonFromForm);
    customAudioFileController.addListener(_updateButtonFromForm);
    backgroundColorController.addListener(_updateButtonFromForm);
    textColorController.addListener(_updateButtonFromForm);
    llmPromptController.addListener(_updateButtonFromForm);
    wordsPromptController.addListener(_updateButtonFromForm);
    staticOptionsController.addListener(_updateButtonFromForm);
    specialPageController.addListener(_updateButtonFromForm);
  }

  // Drag and drop helper methods
  bool _isChildPath(ButtonPath parentPath, ButtonPath childPath) {
    if (childPath.indices.length <= parentPath.indices.length) return false;
    
    for (int i = 0; i < parentPath.indices.length; i++) {
      if (childPath.indices[i] != parentPath.indices[i]) return false;
    }
    return true;
  }

  bool _pathsEqual(ButtonPath path1, ButtonPath path2) {
    if (path1.indices.length != path2.indices.length) return false;
    return path1.indices.asMap().entries.every((e) => e.value == path2.indices[e.key]);
  }

  void _handleButtonDrop(ButtonPath draggedPath, ButtonPath targetPath) {
    if (currentConfig == null) return;
    
    // Get the dragged button
    final draggedButton = _getButtonByPath(draggedPath);
    if (draggedButton == null) return;
    
    // Create a copy of the button
    final buttonCopy = TapNavigationButton.fromJson(draggedButton.toJson());
    
    // Remove from original position
    _removeButtonFromPath(draggedPath);
    
    // Insert after target position
    _insertButtonAfterPath(buttonCopy, targetPath);
    
    _markAsChanged();
    setState(() {});
    _showSnackBar('Button moved successfully', isError: false);
  }

  void _insertButtonAfterPath(TapNavigationButton button, ButtonPath afterPath) {
    if (currentConfig == null) return;
    
    if (afterPath.indices.length == 1) {
      // Insert at root level after the target
      currentConfig!.buttons.insert(afterPath.indices[0] + 1, button);
    } else {
      // Insert in parent's children after the target
      final parentPath = ButtonPath(afterPath.indices.sublist(0, afterPath.indices.length - 1));
      final parent = _getButtonByPath(parentPath);
      if (parent != null) {
        parent.children.insert(afterPath.indices.last + 1, button);
      }
    }
  }

  void _clearForm() {
    // Temporarily remove listeners to prevent unwanted updates
    _removeFormListeners();
    
    labelController.clear();
    speechTextController.clear();
    llmPromptController.clear();
    wordsPromptController.clear();
    staticOptionsController.clear();
    specialPageController.clear();
    
    // Re-add listeners
    _addFormListeners();
  }

  void _updateButtonFromForm() {
    if (selectedButton == null || selectedPath == null) return;

    final button = _getButtonByPath(selectedPath!);
    if (button != null) {
      button.label = labelController.text.isEmpty ? 'Untitled Button' : labelController.text;
      button.speechText = speechTextController.text.isEmpty ? null : speechTextController.text;
      button.imageUrl = imageUrlController.text.isEmpty ? null : imageUrlController.text;
      button.customAudioFile = customAudioFileController.text.isEmpty ? null : customAudioFileController.text;
      button.backgroundColor = backgroundColorController.text.isEmpty ? '#FFFFFF' : backgroundColorController.text;
      button.textColor = textColorController.text.isEmpty ? '#000000' : textColorController.text;
      button.llmPrompt = llmPromptController.text.isEmpty ? null : llmPromptController.text;
      button.wordsPrompt = wordsPromptController.text.isEmpty ? null : wordsPromptController.text;
      button.staticOptions = staticOptionsController.text.isEmpty ? null : staticOptionsController.text;
      button.specialPage = specialPageController.text.isEmpty ? null : specialPageController.text;
      button.hidden = _isHidden;
      
      _markAsChanged();
    }
  }

  void _addNewButton() {
    if (currentConfig == null) return;

    final newButton = TapNavigationButton(
      id: 'button_${DateTime.now().millisecondsSinceEpoch}',
      label: 'New Button',
      backgroundColor: '#FFFFFF',
      textColor: '#000000',
    );

    setState(() {
      currentConfig!.buttons.add(newButton);
    });
    _markAsChanged();

    // Select the new button
    final newPath = ButtonPath([currentConfig!.buttons.length - 1]);
    _selectButton(newPath);
  }

  void _addChildButton() {
    if (selectedButton == null || selectedPath == null) return;

    final newButton = TapNavigationButton(
      id: 'button_${DateTime.now().millisecondsSinceEpoch}',
      label: 'New Child Button',
      backgroundColor: '#FFFFFF',
      textColor: '#000000',
    );

    setState(() {
      selectedButton!.children.add(newButton);
    });
    _markAsChanged();

    // Select the new child button
    final newPath = ButtonPath([...selectedPath!.indices, selectedButton!.children.length - 1]);
    _selectButton(newPath);
  }

  void _deleteButton() {
    if (selectedButton == null || selectedPath == null) return;

    final childrenCount = selectedButton!.children.length;
    final confirmMessage = 'Are you sure you want to delete "${selectedButton!.label}"?' + 
        (childrenCount > 0 ? ' This will also delete $childrenCount child button(s).' : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Button'),
        content: Text(confirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeButtonFromPath(selectedPath!);
              setState(() {
                selectedButton = null;
                selectedPath = null;
              });
              _clearForm();
              _markAsChanged();
              _showSnackBar('Button deleted successfully', isError: false);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _removeButtonFromPath(ButtonPath path) {
    if (currentConfig == null) return;

    if (path.indices.length == 1) {
      currentConfig!.buttons.removeAt(path.indices[0]);
    } else {
      final parentPath = ButtonPath(path.indices.sublist(0, path.indices.length - 1));
      final parent = _getButtonByPath(parentPath);
      if (parent != null) {
        parent.children.removeAt(path.indices.last);
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      String hex = colorString.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      return Colors.white;
    } catch (e) {
      return Colors.white;
    }
  }

  Widget _buildTree() {
    if (currentConfig == null || currentConfig!.buttons.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No buttons configured',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: currentConfig!.buttons.asMap().entries.map((entry) {
          final index = entry.key;
          final button = entry.value;
          return _buildButtonTree(button, ButtonPath([index]), 0);
        }).toList(),
      ),
    );
  }

  Widget _buildButtonTree(TapNavigationButton button, ButtonPath path, int depth) {
    final isSelected = selectedPath?.indices.length == path.indices.length &&
        selectedPath!.indices.asMap().entries.every((e) => e.value == path.indices[e.key]);
    final isDraggedItem = draggedPath?.indices.length == path.indices.length &&
        draggedPath!.indices.asMap().entries.every((e) => e.value == path.indices[e.key]);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Indentation for hierarchy
            SizedBox(width: depth * 24.0),
            // Connection lines for child buttons
            if (depth > 0) ...[
              Container(
                width: 20,
                height: 1,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
            ],
            // Button card with drag and drop
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Draggable<ButtonPath>(
                  data: path,
                  onDragStarted: () {
                    setState(() {
                      draggedPath = path;
                      isDragging = true;
                    });
                  },
                  onDragEnd: (details) {
                    setState(() {
                      draggedPath = null;
                      isDragging = false;
                    });
                  },
                  feedback: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.blue.shade100,
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      child: Text(
                        button.label.isEmpty ? 'Untitled Button' : button.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ),
                  childWhenDragging: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade200,
                      border: Border.all(color: Colors.grey.shade400, width: 1),
                    ),
                    child: Text(
                      button.label.isEmpty ? 'Untitled Button' : button.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  child: DragTarget<ButtonPath>(
                    onWillAccept: (draggedButtonPath) {
                      return draggedButtonPath != null && 
                             !_isChildPath(path, draggedButtonPath) && 
                             !_pathsEqual(path, draggedButtonPath);
                    },
                    onAccept: (draggedButtonPath) {
                      _handleButtonDrop(draggedButtonPath, path);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isDropTarget = candidateData.isNotEmpty;
                      return Material(
                        elevation: isSelected ? 4 : (isDropTarget ? 6 : 1),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () => _selectButton(path),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDropTarget ? Colors.blue :
                                       isSelected ? Colors.green : 
                                       isDraggedItem ? Colors.orange :
                                       Colors.grey.shade300,
                                width: (isSelected || isDropTarget) ? 2 : 1,
                              ),
                              color: isDropTarget ? Colors.blue.shade50 :
                                     isSelected ? Colors.green.shade50 : 
                                     isDraggedItem ? Colors.orange.shade50 :
                                     Colors.white,
                            ),
                            child: Row(
                              children: [
                                // Drag handle
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.drag_handle,
                                    size: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                // Hierarchy indicator
                                if (depth > 0)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.subdirectory_arrow_right,
                                      size: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        button.label.isEmpty ? 'Untitled Button' : button.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: isSelected ? Colors.green.shade700 : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        button.children.isEmpty 
                                            ? 'No children'
                                            : '${button.children.length} child button(s)' +
                                              (button.llmPrompt != null ? ' • Has LLM prompt' : ''),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        // Render children with vertical connecting line
        if (button.children.isNotEmpty) ...[
          // Vertical line for children
          if (depth >= 0)
            Row(
              children: [
                SizedBox(width: depth * 24.0 + 12),
                Container(
                  width: 1,
                  height: 8,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          // Child buttons
          ...button.children.asMap().entries.map((entry) {
            final index = entry.key;
            final child = entry.value;
            final childPath = ButtonPath([...path.indices, index]);
            return _buildButtonTree(child, childPath, depth + 1);
          }),
        ],
      ],
    );
  }

  Widget _buildColorPalette(String label, TextEditingController controller) {
    final List<Map<String, String>> colors = [
      {'name': 'White', 'hex': '#FFFFFF'},
      {'name': 'Black', 'hex': '#000000'},
      {'name': 'Red', 'hex': '#FF0000'},
      {'name': 'Green', 'hex': '#00FF00'},
      {'name': 'Blue', 'hex': '#0000FF'},
      {'name': 'Yellow', 'hex': '#FFFF00'},
      {'name': 'Orange', 'hex': '#FFA500'},
      {'name': 'Purple', 'hex': '#800080'},
      {'name': 'Grey', 'hex': '#808080'},
      {'name': 'Light Blue', 'hex': '#ADD8E6'},
      {'name': 'Light Green', 'hex': '#90EE90'},
      {'name': 'Pink', 'hex': '#FFC0CB'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            final isSelected = controller.text.toUpperCase() == color['hex'];
            return Tooltip(
              message: color['name']!,
              child: InkWell(
                onTap: () {
                  setState(() {
                    controller.text = color['hex']!;
                  });
                  _updateButtonFromForm();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _parseColor(color['hex']!),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: _parseColor(color['hex']!).computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Fallback text input for custom colors
        Row(
          children: [
            const Text('Custom Hex:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (_) => _updateButtonFromForm(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForm() {
    if (selectedButton == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Select a button to edit',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'Choose a button from the navigation tree to modify its properties.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit Button: ${selectedButton!.label}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Modify the properties of the selected button.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          
          // Button Label
          TextFormField(
            controller: labelController,
            decoration: const InputDecoration(
              labelText: 'Button Label *',
              hintText: 'Enter button text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          
          // Speech Text
          TextFormField(
            controller: speechTextController,
            decoration: const InputDecoration(
              labelText: 'Speech Text (Optional)',
              hintText: 'Text to speak (if different from label)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          
          // Image URL
          TextFormField(
            controller: imageUrlController,
            decoration: const InputDecoration(
              labelText: 'Image URL (Optional)',
              hintText: 'https://example.com/icon.png',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          
          // Audio URL with Upload Button
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: customAudioFileController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Audio (Optional)',
                    hintText: 'Upload MP3 file for custom button audio',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _uploadAudioFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload MP3'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              if (customAudioFileController.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    customAudioFileController.clear();
                    _updateButtonFromForm();
                  },
                  icon: const Icon(Icons.clear, color: Colors.red),
                  tooltip: 'Remove Audio',
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          
          // Background Color
          _buildColorPalette('Background Color', backgroundColorController),
          const SizedBox(height: 24),
          
          // Text Color
          _buildColorPalette('Text Color', textColorController),
          const SizedBox(height: 24),

          // Special Page Dropdown
          DropdownButtonFormField<String>(
            value: specialPageController.text.isEmpty ? null : specialPageController.text,
            decoration: const InputDecoration(
              labelText: 'Special Page (Optional)',
              hintText: 'Select a special page function',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('None')),
              DropdownMenuItem(value: 'spell', child: Text('Spelling')),
              DropdownMenuItem(value: 'freestyle', child: Text('Freestyle')),
              DropdownMenuItem(value: 'threads', child: Text('Threads')),
              DropdownMenuItem(value: 'favorites', child: Text('Favorites')),
              DropdownMenuItem(value: 'email', child: Text('Email')),
              DropdownMenuItem(value: 'games', child: Text('Games')),
              DropdownMenuItem(value: 'jokes', child: Text('Jokes')),
              DropdownMenuItem(value: 'guess-who', child: Text('Guess Who')),
              DropdownMenuItem(value: 'mood', child: Text('Mood Selection')),
            ],
            onChanged: (value) {
              setState(() {
                specialPageController.text = value ?? '';
              });
              _updateButtonFromForm();
            },
          ),
          const SizedBox(height: 16),

          // Hidden Switch
          SwitchListTile(
            title: const Text('Hidden'),
            subtitle: const Text('Hide this button from the interface'),
            value: _isHidden,
            onChanged: (bool value) {
              setState(() {
                _isHidden = value;
              });
              _updateButtonFromForm();
            },
            secondary: const Icon(Icons.visibility_off),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          
          // LLM Prompt
          TextFormField(
            controller: llmPromptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'LLM Prompt for Phrases (Optional)',
              hintText: 'Enter prompt for AI to generate phrase options (e.g., "Generate greeting phrases for social interactions")',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          
          // Words Prompt
          TextFormField(
            controller: wordsPromptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Text Prompt for Word Completion (Optional)',
              hintText: 'Enter text prompt for word completion (e.g., "Where" to complete phrases like "Where is my...")',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          
          // Static Options
          TextFormField(
            controller: staticOptionsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Static Options (Optional)',
              hintText: 'Enter comma-separated list of options (e.g., "Hello, Hi there, Good morning, How are you")',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'LLM Prompt generates full phrases, Text Prompt generates single words for completion. Use Static Options to override LLM generation.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          
          // Action buttons
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _deleteButton,
                icon: const Icon(Icons.delete),
                label: const Text('Delete Button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _addChildButton,
                icon: const Icon(Icons.add_circle),
                label: const Text('Add Child Button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tap Interface Admin', style: TextStyle(fontSize: 18)),
            Text(
              'Configure navigation buttons for the tap interface',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        actions: [
          if (hasUnsavedChanges)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                '⚠️ Unsaved Changes',
                style: TextStyle(fontSize: 12),
              ),
            ),
          TextButton.icon(
            onPressed: hasUnsavedChanges ? _saveChanges : null,
            icon: isLoading ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ) : const Icon(Icons.save, color: Colors.white),
            label: const Text('Save Changes', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: hasUnsavedChanges ? _cancelChanges : null,
            icon: const Icon(Icons.cancel, color: Colors.white),
            label: const Text('Cancel Changes', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading && currentConfig == null
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading configuration',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadConfiguration,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Row(
                  children: [
                    // Left sidebar - Navigation tree
                    Container(
                      width: 350,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(right: BorderSide(color: Colors.grey.shade300)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'Navigation Structure',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: _addNewButton,
                                  icon: const Icon(Icons.add_circle, color: Colors.blue),
                                  tooltip: 'Add New Button',
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: _buildTree()),
                        ],
                      ),
                    ),
                    
                    // Right content area - Form
                    Expanded(child: _buildForm()),
                  ],
                ),
    );
  }

  Future<void> _uploadAudioFile() async {
    try {
      // Pick audio file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        final fileBytes = file.bytes!;
        final fileName = file.name;

        // Check file size (10MB limit to match backend)
        if (fileBytes.length > 10 * 1024 * 1024) {
          _showSnackBar('File size must be less than 10MB', isError: true);
          return;
        }

        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Uploading audio file...'),
              ],
            ),
          ),
        );

        try {
          // Upload to server
          final audioUrl = await _uploadAudioToServer(fileBytes, fileName);
          
          // Close loading dialog
          Navigator.of(context).pop();

          // Update the form
          setState(() {
            customAudioFileController.text = audioUrl;
          });
          _updateButtonFromForm();
          
          _showSnackBar('Audio uploaded successfully!', isError: false);
        } catch (e) {
          // Close loading dialog
          Navigator.of(context).pop();
          _showSnackBar('Upload failed: ${e.toString()}', isError: true);
        }
      }
    } catch (e) {
      _showSnackBar('Error selecting file: ${e.toString()}', isError: true);
    }
  }

  Future<String> _uploadAudioToServer(Uint8List fileBytes, String fileName) async {
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    final uri = Uri.parse('${userSettings.apiBaseUrl}/api/admin/upload-button-audio');

    var request = http.MultipartRequest('POST', uri);
    
    // Add authorization header
    request.headers['Authorization'] = 'Bearer ${widget.idToken}';
    
    // Add file
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(responseBody);
      if (jsonResponse['success'] == true && jsonResponse['audio_url'] != null) {
        return jsonResponse['audio_url'] as String;
      } else {
        throw Exception('Server did not return audio URL');
      }
    } else {
      final errorData = json.decode(responseBody);
      throw Exception(errorData['detail'] ?? 'Upload failed with status ${response.statusCode}');
    }
  }
}