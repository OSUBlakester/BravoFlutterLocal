
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'config/environment_config.dart';
import 'config/language_config.dart';
import 'services/user_settings_provider.dart';

class UserCurrentAdminPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  const UserCurrentAdminPage({Key? key, required this.idToken, required this.aacUserId}) : super(key: key);

  @override
  State<UserCurrentAdminPage> createState() => _UserCurrentAdminPageState();
}


class _UserCurrentAdminPageState extends State<UserCurrentAdminPage> {
  final TextEditingController locationController = TextEditingController();
  final TextEditingController peopleController = TextEditingController();
  final TextEditingController activityController = TextEditingController();
  String statusMessage = '';
  bool isLoading = false;

  // Favorites
  List<Map<String, dynamic>> favorites = [];
  Map<String, dynamic>? selectedFavorite;
  String? selectedFavoriteName;
  bool isFavoritesLoading = false;

  // Add Favorite Modal
  bool showAddFavoriteDialog = false;
  final TextEditingController favoriteNameController = TextEditingController();
  
  // Schedule State
  bool scheduleEnabled = false;
  List<String> selectedDays = [];
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  final List<String> daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  // Manage Favorites Modal
  bool showManageFavoritesDialog = false;
  List<Map<String, dynamic>> manageFavorites = [];

  // Dictation
  late stt.SpeechToText speech;
  bool isListening = false;
  String dictationField = '';

  static const Map<String, String> _localeLabelToTag = {
    'english (us)': 'en-US',
    'spanish (us)': 'es-US',
    'french (france)': 'fr-FR',
    'german (germany)': 'de-DE',
    'italian (italy)': 'it-IT',
    'portuguese (brazil)': 'pt-BR',
    'arabic': 'ar-XA',
  };

  String? _normalizeLocaleTag(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final labelMatch = _localeLabelToTag[raw.toLowerCase()];
    if (labelMatch != null) return labelMatch;

    final cleaned = raw.replaceAll('_', '-');
    final match = RegExp(r'^([a-zA-Z]{2})(?:-([a-zA-Z]{2,3}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final language = match.group(1)!.toLowerCase();
    final region = match.group(2)?.toUpperCase();
    return region == null ? language : '$language-$region';
  }

  void _applyLocationLanguageOverride(dynamic localeValue) {
    final settingsProvider = context.read<UserSettingsProvider>();
    final normalizedLocale = _normalizeLocaleTag(localeValue);
    if (normalizedLocale == null) {
      settingsProvider.clearLocationOverride();
      return;
    }

    final entry = settingsProvider.settings?.locationOverrideLanguages.firstWhere(
      (e) => e.locale == normalizedLocale,
      orElse: () => LocationLanguageEntry(locale: normalizedLocale, voice: ''),
    );
    settingsProvider.setLocationOverride(normalizedLocale, entry?.voice ?? '');
  }


  @override
  void initState() {
    super.initState();
    
    // Configure soft input mode for admin page (but don't show keyboard yet)
    _configureSoftInputMode();
    
    // Stop wake word listening when this page is shown
    final dynamic gridState = context.findAncestorStateOfType<State<StatefulWidget>>();
    if (gridState != null && gridState.runtimeType.toString() == '_GridPageState') {
      try {
        gridState._wakeWordService?.stopWakeWordListening();
      } catch (_) {}
    }
    fetchCurrentUserState();
    fetchFavorites();
    speech = stt.SpeechToText();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsProvider = context.read<UserSettingsProvider>();
      if (!settingsProvider.isLoading && settingsProvider.settings == null) {
        settingsProvider.fetchSettings();
      }
    });
  }
  Future<void> fetchFavorites() async {
    setState(() { isFavoritesLoading = true; });
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          favorites = List<Map<String, dynamic>>.from(data['favorites'] ?? []);
        });
      }
    } catch (e) {
      // ignore for now
    } finally {
      setState(() { isFavoritesLoading = false; });
    }
  }

  Future<void> loadSelectedFavorite(Map<String, dynamic> favorite) async {
    setState(() {
      locationController.text = favorite['location'] ?? '';
      peopleController.text = favorite['people'] ?? '';
      activityController.text = favorite['activity'] ?? '';
      selectedFavoriteName = favorite['name'];
    });
    _applyLocationLanguageOverride(favorite['locationLanguageOverride']);
    
    // Automatically save the loaded data with timestamps (matching Web implementation)
    await _saveUserCurrentWithTimestamp(favorite['name']);
    setState(() { statusMessage = 'Loaded and saved favorite: ${favorite['name']}'; });
  }

  Future<void> saveFavorite() async {
    final name = favoriteNameController.text.trim();
    if (name.isEmpty) {
      setState(() { statusMessage = 'Please enter a name for the favorite'; });
      return;
    }
    
    Map<String, dynamic> favoriteData = {
      'name': name,
      'location': locationController.text,
      'locationLanguageOverride': context.read<UserSettingsProvider>().currentLocationOverrideLocale ?? '',
      'people': peopleController.text,
      'activity': activityController.text,
    };

    if (scheduleEnabled) {
      if (startTime == null || endTime == null) {
        setState(() { statusMessage = 'Please select start and end times'; });
        return;
      }
      if (selectedDays.isEmpty) {
        setState(() { statusMessage = 'Please select at least one day'; });
        return;
      }

      // Format times as HH:MM
      final startStr = '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}';
      final endStr = '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}';

      favoriteData['schedule'] = {
        'enabled': true,
        'days_of_week': selectedDays,
        'start_time': startStr,
        'end_time': endStr,
      };
    } else {
      favoriteData['schedule'] = null;
    }

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode(favoriteData),
      );
      final result = json.decode(response.body);
      if (result['success'] == true) {
        setState(() { 
          statusMessage = result['message'] ?? 'Favorite saved.'; 
          showAddFavoriteDialog = false; 
          // Reset schedule state
          scheduleEnabled = false;
          selectedDays = [];
          startTime = null;
          endTime = null;
        });
        favoriteNameController.clear();
        await fetchFavorites();
      } else {
        setState(() { statusMessage = result['message'] ?? 'Error saving favorite.'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error saving favorite: $e'; });
    }
  }

  Future<void> showManageFavoritesModal() async {
    setState(() { showManageFavoritesDialog = true; });
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          manageFavorites = List<Map<String, dynamic>>.from(data['favorites'] ?? []);
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> editFavorite(Map<String, dynamic> favorite, String newName, String newLocation, String newPeople, String newActivity, {Map<String, dynamic>? schedule}) async {
    try {
      final Map<String, dynamic> favoriteData = {
        'name': newName,
        'location': newLocation,
        'locationLanguageOverride': context.read<UserSettingsProvider>().currentLocationOverrideLocale ?? '',
        'people': newPeople,
        'activity': newActivity,
      };

      if (schedule != null) {
        favoriteData['schedule'] = schedule;
      } else {
        favoriteData['schedule'] = null;
      }

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites/manage'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': 'edit',
          'old_name': favorite['name'],
          'favorite': favoriteData
        }),
      );
      final result = json.decode(response.body);
      if (result['success'] == true) {
        setState(() { statusMessage = result['message'] ?? 'Favorite updated.'; });
        await fetchFavorites();
        await showManageFavoritesModal();
      } else {
        setState(() { statusMessage = result['message'] ?? 'Error editing favorite.'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error editing favorite: $e'; });
    }
  }

  Future<void> deleteFavorite(String favoriteName) async {
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/user-current-favorites/manage'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': 'delete',
          'old_name': favoriteName,
        }),
      );
      final result = json.decode(response.body);
      if (result['success'] == true) {
        setState(() { statusMessage = result['message'] ?? 'Favorite deleted.'; });
        await fetchFavorites();
        await showManageFavoritesModal();
      } else {
        setState(() { statusMessage = result['message'] ?? 'Error deleting favorite.'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error deleting favorite: $e'; });
    }
  }

  Future<void> startDictation(String field) async {
    bool available = await speech.initialize();
    if (!available) {
      setState(() { statusMessage = 'Speech recognition unavailable.'; });
      return;
    }
    setState(() { isListening = true; dictationField = field; statusMessage = 'Listening...'; });
    speech.listen(
      onResult: (result) {
        setState(() {
          if (field == 'location') locationController.text = result.recognizedWords;
          if (field == 'people') peopleController.text = result.recognizedWords;
          if (field == 'activity') activityController.text = result.recognizedWords;
        });
      },
      listenFor: const Duration(seconds: 10),
      localeId: 'en_US',
      cancelOnError: true,
      partialResults: false,
      onSoundLevelChange: null,
      pauseFor: const Duration(seconds: 2),
      listenMode: stt.ListenMode.confirmation,
    );
  }

  void stopDictation() {
    speech.stop();
    setState(() { isListening = false; statusMessage = ''; });
  }

  Future<void> fetchCurrentUserState() async {
    setState(() { isLoading = true; statusMessage = 'Loading current state...'; });
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/get-user-current'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        locationController.text = data['location'] ?? '';
        peopleController.text = data['people'] ?? '';
        activityController.text = data['activity'] ?? '';
        _applyLocationLanguageOverride(data['locationLanguageOverride']);
        setState(() { statusMessage = 'Current state loaded.'; });
      } else {
        setState(() { statusMessage = 'Error loading state: ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { statusMessage = 'Error loading state: $e'; });
    } finally {
      setState(() { isLoading = false; });
    }
  }

  Future<void> saveCurrentUserState({bool auto = false, bool showMsg = true}) async {
    setState(() { isLoading = true; if (showMsg) statusMessage = 'Saving...'; });
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/user_current'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'location': locationController.text,
          'locationLanguageOverride': context.read<UserSettingsProvider>().currentLocationOverrideLocale ?? '',
          'people': peopleController.text,
          'activity': activityController.text,
        }),
      );
      if (response.statusCode == 200) {
        if (showMsg) setState(() { statusMessage = 'Current state saved successfully!'; });
      } else {
        if (showMsg) setState(() { statusMessage = 'Save failed: ${response.statusCode}'; });
      }
    } catch (e) {
      if (showMsg) setState(() { statusMessage = 'Error saving: $e'; });
    } finally {
      setState(() { isLoading = false; });
    }
  }

  // New method for saving when a favorite is loaded (includes timestamps and favorite name)
  Future<void> _saveUserCurrentWithTimestamp(String favoriteName) async {
    setState(() { isLoading = true; });
    
    try {
      // Use UTC timestamp with explicit timezone to match backend expectations
      final loadTimestamp = DateTime.now().toUtc().toIso8601String(); // Use same timestamp for both loaded_at and saved_at
      
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/user_current'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'location': locationController.text,
          'locationLanguageOverride': context.read<UserSettingsProvider>().currentLocationOverrideLocale ?? '',
          'people': peopleController.text,
          'activity': activityController.text,
          'loaded_at': loadTimestamp,  // Timestamp when favorite is loaded
          'favorite_name': favoriteName,  // Include the favorite name for tracking
          'saved_at': loadTimestamp,  // Use same timestamp to indicate this save is part of loading, not manual
        }),
      );
      
      if (response.statusCode == 200) {
        debugPrint('Favorite loaded and saved with timestamps: $favoriteName');
      } else {
        debugPrint('Failed to save favorite with timestamps: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error saving favorite with timestamps: $e');
    } finally {
      setState(() { isLoading = false; });
    }
  }


  @override
  void dispose() {
    // Re-disable keyboard when leaving admin page
    _disableKeyboardForMainApp();
    
    locationController.dispose();
    peopleController.dispose();
    activityController.dispose();
    favoriteNameController.dispose();
    speech.stop();
    super.dispose();
  }

  // *** KEYBOARD MANAGEMENT FOR ADMIN PAGES ***
  Future<void> _configureSoftInputMode() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        // Configure window to allow keyboard input
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Current Location and Info')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Update User Current Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              // Favorites Dropdown and Buttons
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<Map<String, dynamic>>(
                      isExpanded: true,
                      value: selectedFavorite,
                      hint: const Text('Choose a favorite...'),
                      items: favorites.map((fav) {
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: fav,
                          child: Text(fav['name'] ?? ''),
                        );
                      }).toList(),
                      onChanged: isFavoritesLoading ? null : (fav) async {
                        if (fav != null) {
                          setState(() { selectedFavorite = fav; });
                          await loadSelectedFavorite(fav);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => setState(() { showAddFavoriteDialog = true; }),
                    child: const Text('Add to Favorites'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: showManageFavoritesModal,
                    child: const Text('Manage Favorites'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Main Form
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: locationController,
                      onTap: () {
                        // Show keyboard when text field is tapped
                        _showKeyboardWhenNeeded();
                      },
                      decoration: InputDecoration(
                        labelText: 'Location',
                        suffixIcon: IconButton(
                          icon: Icon(isListening && dictationField == 'location' ? Icons.mic : Icons.mic_none),
                          onPressed: isListening ? stopDictation : () => startDictation('location'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: peopleController,
                      decoration: InputDecoration(
                        labelText: 'People Present',
                        suffixIcon: IconButton(
                          icon: Icon(isListening && dictationField == 'people' ? Icons.mic : Icons.mic_none),
                          onPressed: isListening ? stopDictation : () => startDictation('people'),
                        ),
                      ),
                      onTap: _showKeyboardWhenNeeded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: activityController,
                      decoration: InputDecoration(
                        labelText: 'Activity',
                        suffixIcon: IconButton(
                          icon: Icon(isListening && dictationField == 'activity' ? Icons.mic : Icons.mic_none),
                          onPressed: isListening ? stopDictation : () => startDictation('activity'),
                        ),
                      ),
                      onTap: _showKeyboardWhenNeeded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Location Language Override
              Consumer<UserSettingsProvider>(
                builder: (context, settingsProvider, _) {
                  final overrides = settingsProvider.settings?.locationOverrideLanguages ?? [];
                  if (overrides.isEmpty) return const SizedBox.shrink();

                  final activeLocale = settingsProvider.currentLocationOverrideLocale;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Location Language Override',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select a location language to override the default partner language.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        value: activeLocale,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No Override / Default'),
                          ),
                          ...overrides.map((entry) => DropdownMenuItem<String?>(
                            value: entry.locale,
                            child: Text(languageLabelForLocale(entry.locale)),
                          )),
                        ],
                        onChanged: (locale) {
                          if (locale == null) {
                            settingsProvider.clearLocationOverride();
                          } else {
                            final entry = overrides.firstWhere(
                              (e) => e.locale == locale,
                              orElse: () => LocationLanguageEntry(locale: locale, voice: ''),
                            );
                            settingsProvider.setLocationOverride(entry.locale, entry.voice);
                          }
                        },
                      ),
                      if (activeLocale != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Override active: ${languageLabelForLocale(activeLocale)}',
                          style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w500),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),

              Row(
                children: [
                  ElevatedButton(
                    onPressed: isLoading ? null : saveCurrentUserState,
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 16),
                  if (isLoading) const CircularProgressIndicator(),
                ],
              ),
              const SizedBox(height: 16),
              Text(statusMessage, style: TextStyle(color: statusMessage.contains('error') || statusMessage.contains('Error') ? Colors.red : Colors.green)),

              // Add Favorite Dialog
              if (showAddFavoriteDialog)
                AlertDialog(
                  title: const Text('Add to Favorites'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: favoriteNameController,
                          decoration: const InputDecoration(labelText: 'Favorite Name'),
                          onTap: _showKeyboardWhenNeeded,
                        ),
                        const SizedBox(height: 12),
                        Text('Location: ${locationController.text}'),
                        Text('People: ${peopleController.text}'),
                        Text('Activity: ${activityController.text}'),
                        const Divider(),
                        CheckboxListTile(
                          title: const Text('Enable Schedule'),
                          value: scheduleEnabled,
                          onChanged: (val) => setState(() => scheduleEnabled = val ?? false),
                        ),
                        if (scheduleEnabled) ...[
                          const Text('Days of Week:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Wrap(
                            spacing: 8.0,
                            children: daysOfWeek.map((day) {
                              final isSelected = selectedDays.contains(day);
                              return FilterChip(
                                label: Text(day.substring(0, 3)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      selectedDays.add(day);
                                    } else {
                                      selectedDays.remove(day);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: startTime ?? TimeOfDay.now(),
                                    );
                                    if (time != null) setState(() => startTime = time);
                                  },
                                  child: Text(startTime == null ? 'Start Time' : 'Start: ${startTime!.format(context)}'),
                                ),
                              ),
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: endTime ?? TimeOfDay.now(),
                                    );
                                    if (time != null) setState(() => endTime = time);
                                  },
                                  child: Text(endTime == null ? 'End Time' : 'End: ${endTime!.format(context)}'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() { 
                        showAddFavoriteDialog = false; 
                        favoriteNameController.clear();
                        scheduleEnabled = false;
                        selectedDays = [];
                        startTime = null;
                        endTime = null;
                      }),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: saveFavorite,
                      child: const Text('Save Favorite'),
                    ),
                  ],
                ),

              // Manage Favorites Dialog
              if (showManageFavoritesDialog)
                AlertDialog(
                  title: const Text('Manage Favorites'),
                  content: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (manageFavorites.isEmpty)
                          const Text('No favorites saved yet.'),
                        for (final fav in manageFavorites)
                          ListTile(
                            title: Text(fav['name'] ?? ''),
                            subtitle: Text('Location: ${fav['location'] ?? ''}\nPeople: ${fav['people'] ?? ''}\nActivity: ${fav['activity'] ?? ''}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () async {
                                    final nameController = TextEditingController(text: fav['name']);
                                    final locController = TextEditingController(text: fav['location']);
                                    final peopleController2 = TextEditingController(text: fav['people']);
                                    final activityController2 = TextEditingController(text: fav['activity']);
                                    
                                    // Initialize schedule state
                                    bool editScheduleEnabled = false;
                                    List<String> editSelectedDays = [];
                                    TimeOfDay? editStartTime;
                                    TimeOfDay? editEndTime;
                                    
                                    if (fav['schedule'] != null && fav['schedule']['enabled'] == true) {
                                      editScheduleEnabled = true;
                                      editSelectedDays = List<String>.from(fav['schedule']['days_of_week'] ?? []);
                                      try {
                                        final startParts = (fav['schedule']['start_time'] as String).split(':');
                                        editStartTime = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
                                        final endParts = (fav['schedule']['end_time'] as String).split(':');
                                        editEndTime = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));
                                      } catch (e) {
                                        debugPrint('Error parsing schedule time: $e');
                                      }
                                    }

                                    await showDialog(
                                      context: context,
                                      builder: (context) => StatefulBuilder(
                                        builder: (context, setStateDialog) {
                                          return AlertDialog(
                                            title: const Text('Edit Favorite'),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name'), onTap: _showKeyboardWhenNeeded),
                                                  TextField(controller: locController, decoration: const InputDecoration(labelText: 'Location'), onTap: _showKeyboardWhenNeeded),
                                                  TextField(controller: peopleController2, decoration: const InputDecoration(labelText: 'People'), onTap: _showKeyboardWhenNeeded),
                                                  TextField(controller: activityController2, decoration: const InputDecoration(labelText: 'Activity'), onTap: _showKeyboardWhenNeeded),
                                                  const Divider(),
                                                  CheckboxListTile(
                                                    title: const Text('Enable Schedule'),
                                                    value: editScheduleEnabled,
                                                    onChanged: (val) => setStateDialog(() => editScheduleEnabled = val ?? false),
                                                  ),
                                                  if (editScheduleEnabled) ...[
                                                    const Text('Days of Week:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                    Wrap(
                                                      spacing: 8.0,
                                                      children: daysOfWeek.map((day) {
                                                        final isSelected = editSelectedDays.contains(day);
                                                        return FilterChip(
                                                          label: Text(day.substring(0, 3)),
                                                          selected: isSelected,
                                                          onSelected: (selected) {
                                                            setStateDialog(() {
                                                              if (selected) {
                                                                editSelectedDays.add(day);
                                                              } else {
                                                                editSelectedDays.remove(day);
                                                              }
                                                            });
                                                          },
                                                        );
                                                      }).toList(),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextButton(
                                                            onPressed: () async {
                                                              final time = await showTimePicker(
                                                                context: context,
                                                                initialTime: editStartTime ?? TimeOfDay.now(),
                                                              );
                                                              if (time != null) setStateDialog(() => editStartTime = time);
                                                            },
                                                            child: Text(editStartTime == null ? 'Start Time' : 'Start: ${editStartTime!.format(context)}'),
                                                          ),
                                                        ),
                                                        Expanded(
                                                          child: TextButton(
                                                            onPressed: () async {
                                                              final time = await showTimePicker(
                                                                context: context,
                                                                initialTime: editEndTime ?? TimeOfDay.now(),
                                                              );
                                                              if (time != null) setStateDialog(() => editEndTime = time);
                                                            },
                                                            child: Text(editEndTime == null ? 'End Time' : 'End: ${editEndTime!.format(context)}'),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  Map<String, dynamic>? scheduleData;
                                                  if (editScheduleEnabled) {
                                                    if (editStartTime == null || editEndTime == null || editSelectedDays.isEmpty) {
                                                      // Basic validation - could show error
                                                      return; 
                                                    }
                                                    final startStr = '${editStartTime!.hour.toString().padLeft(2, '0')}:${editStartTime!.minute.toString().padLeft(2, '0')}';
                                                    final endStr = '${editEndTime!.hour.toString().padLeft(2, '0')}:${editEndTime!.minute.toString().padLeft(2, '0')}';
                                                    
                                                    scheduleData = {
                                                      'enabled': true,
                                                      'days_of_week': editSelectedDays,
                                                      'start_time': startStr,
                                                      'end_time': endStr,
                                                    };
                                                  }

                                                  await editFavorite(
                                                    fav,
                                                    nameController.text,
                                                    locController.text,
                                                    peopleController2.text,
                                                    activityController2.text,
                                                    schedule: scheduleData,
                                                  );
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Save'),
                                              ),
                                            ],
                                          );
                                        }
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Favorite'),
                                        content: Text('Are you sure you want to delete "${fav['name']}"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await deleteFavorite(fav['name']);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() { showManageFavoritesDialog = false; }),
                      child: const Text('Close'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
