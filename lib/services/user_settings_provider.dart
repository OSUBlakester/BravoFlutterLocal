
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'authenticated_http_client.dart';



class UserSettings {
  int scanDelay;
  String wakeWordInterjection;
  String wakeWordName;
  String countryCode;
  int speechRate;
  int llmOptions;
  int freestyleOptions;
  bool scanningOff;
  bool summaryOff;
  String selectedTtsVoiceName;
  // Note: primaryLlmModel removed - server now handles model selection via environment variables
  int gridColumns;
  int lightColorValue;
  int darkColorValue;
  String toolbarPIN;
  int scanLoopLimit; // Added scanLoopLimit field
  bool autoClean; // Added autoClean field
  
  // Speech bubble splash screen fields
  bool displaySplash;
  int displaySplashtime;
  
  // Mood selection fields
  bool enableMoodSelection;
  String currentMood;

  // Pictogram/image display field
  bool enablePictograms;

  // Disable all pictograms and sight-word formatting on Tap Interface
  bool disableTapPictograms;

  // Sight words grade level field
  String sightWordGradeLevel;

  // Enable/disable sight word logic for image suppression
  bool enableSightWords;
  
  // Spell page letter order (alphabetical, qwerty, or frequency)
  String spellLetterOrder;
  
  // Vocabulary level for LLM responses (functional, elementary, middle_school, high_school, collegiate)
  String vocabularyLevel;

  // Wait for switch press before starting scanning (only on page load)
  bool waitForSwitchToScan;

  // Scanning mode: 'auto' for timed auto-advance, 'step' for switch-based manual advance
  String scanMode;

  // Interface mode field - true for tap interface, false for scanning interface
  bool useTapInterface;

  // Application volume setting (0-10, where 10 is maximum volume)
  int applicationVolume;

  // Group wake word (universal wake phrase for multi-device / therapist use)
  // Default: 'hey friends'. Will be persisted via backend when backend support is added.
  String groupWakeWord;

  // Email compose defaults
  String emailDefaultRecipient;
  String emailSubjectTemplate;
  
  // Personal volume setting (0-10) - for cues/scanning (Bluetooth/Headphones)
  int personalVolume;
  
  // System volume setting (0-10) - for speech output (Built-in Speaker)
  int systemVolume;

  // Positive logic fields
  bool get enableAuditoryScanning => !scanningOff;
  set enableAuditoryScanning(bool value) => scanningOff = !value;

  bool get useShortSummaryOnButtons => summaryOff == false;
  set useShortSummaryOnButtons(bool value) => summaryOff = !value;

  Color get lightColor => Color(lightColorValue);
  set lightColor(Color c) => lightColorValue = c.value;
  Color get darkColor => Color(darkColorValue);
  set darkColor(Color c) => darkColorValue = c.value;

  UserSettings({
    required this.scanDelay,
    required this.wakeWordInterjection,
    required this.wakeWordName,
    required this.countryCode,
    required this.speechRate,
    required this.llmOptions,
    required this.freestyleOptions,
    required this.scanningOff,
    required this.summaryOff,
    required this.selectedTtsVoiceName,
    // Note: primaryLlmModel removed - server now handles model selection
    required this.gridColumns,
    required this.lightColorValue,
    required this.darkColorValue,
    required this.toolbarPIN,
    required this.scanLoopLimit, // Added to constructor
    required this.autoClean, // Added to constructor
    required this.displaySplash, // Added splash screen field
    required this.displaySplashtime,
    required this.enableMoodSelection,
    required this.currentMood,
    required this.enablePictograms,
    required this.disableTapPictograms,
    required this.sightWordGradeLevel,
    required this.enableSightWords,
    required this.spellLetterOrder,
    required this.vocabularyLevel, // Added vocabulary level field
    required this.waitForSwitchToScan, // Added wait for switch field
    required this.scanMode, // Added scan mode field
    required this.useTapInterface, // Added interface mode field
    required this.applicationVolume, // Added application volume field
    required this.groupWakeWord,
    required this.emailDefaultRecipient,
    required this.emailSubjectTemplate,
    required this.personalVolume, // Added personal volume field
    required this.systemVolume, // Added system volume field
  });


  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      scanDelay: json['scanDelay'] ?? 3500,
      wakeWordInterjection: json['wakeWordInterjection'] ?? '',
      wakeWordName: json['wakeWordName'] ?? '',
      countryCode: json['CountryCode'] ?? '',
      speechRate: json['speech_rate'] ?? 180,
      llmOptions: json['LLMOptions'] ?? 10,
      freestyleOptions: json['FreestyleOptions'] ?? 20,
      scanningOff: json['ScanningOff'] ?? false,
      summaryOff: json['SummaryOff'] ?? false,
      selectedTtsVoiceName: json['selected_tts_voice_name'] ?? '',
      // Note: primaryLlmModel removed - server now handles model selection via environment variables
      gridColumns: (() {
        final val = json['gridColumns'];
        if (val == null) return 10;
        if (val is int) return val;
        if (val is num) return val.toInt();
        if (val is String) {
          final int? parsed = int.tryParse(val);
          if (parsed != null) return parsed;
        }
        return 10;
      })(),
      lightColorValue: json['lightColorValue'] ?? Colors.white.value,
      darkColorValue: json['darkColorValue'] ?? Colors.black.value,
      toolbarPIN: json['toolbarPIN'] ?? '1234',
      scanLoopLimit: json['scanLoopLimit'] ?? 0, // Changed to match web app default
      autoClean: json['autoClean'] ?? false, // Added autoClean field
      displaySplash: json['displaySplash'] ?? false, // Added splash screen field
      displaySplashtime: json['displaySplashtime'] ?? 3000, // Added splash screen field
      enableMoodSelection: json['enableMoodSelection'] ?? false, // Added mood selection field
      currentMood: json['currentMood'] ?? 'No Mood Selected', // Added mood selection field
      enablePictograms: json['enablePictograms'] ?? true, // Default true for testing - pictograms enabled by default
      disableTapPictograms: json['disableTapPictograms'] ?? false,
      sightWordGradeLevel: json['sightWordGradeLevel'] ?? 'Pre-K',
      spellLetterOrder: json['spellLetterOrder'] ?? 'alphabetical', // Default to alphabetical
      vocabularyLevel: json['vocabularyLevel'] ?? 'functional', // Default to functional vocabulary
      enableSightWords: json['enableSightWords'] ?? true,
      waitForSwitchToScan: json['waitForSwitchToScan'] ?? false, // Default to false (start immediately)
      scanMode: json['scanMode'] == 'step' ? 'step' : 'auto', // Default to auto
      useTapInterface: json['useTapInterface'] ?? false, // Default to scanning interface
      applicationVolume: json['applicationVolume'] ?? 10, // Default to maximum volume (10/10)
      groupWakeWord: (json['groupWakeWord'] as String? ?? 'hey friends').trim().toLowerCase().isEmpty ? 'hey friends' : (json['groupWakeWord'] as String? ?? 'hey friends').trim().toLowerCase(),
      emailDefaultRecipient: json['emailDefaultRecipient'] ?? '',
      emailSubjectTemplate: json['emailSubjectTemplate'] ?? 'Message from Bravo AAC',
      personalVolume: json['personalVolume'] ?? 10, // Default to maximum volume
      systemVolume: json['systemVolume'] ?? 10, // Default to maximum volume
    );
  }

  Map<String, dynamic> toJson() => {
        'scanDelay': scanDelay,
        'wakeWordInterjection': wakeWordInterjection,
        'wakeWordName': wakeWordName,
        'CountryCode': countryCode,
        'speech_rate': speechRate,
        'LLMOptions': llmOptions,
        'FreestyleOptions': freestyleOptions,
        'ScanningOff': scanningOff,
        'SummaryOff': summaryOff,
        'selected_tts_voice_name': selectedTtsVoiceName,
        // Note: primary_llm_model removed - server now handles model selection via environment variables
        'gridColumns': gridColumns,
        'lightColorValue': lightColorValue,
        'darkColorValue': darkColorValue,
        'toolbarPIN': toolbarPIN,
        'scanLoopLimit': scanLoopLimit, // Added scanLoopLimit field
        'autoClean': autoClean, // Added autoClean field
        'displaySplash': displaySplash, // Added splash screen field
        'displaySplashtime': displaySplashtime, // Added splash screen field
        'enableMoodSelection': enableMoodSelection, // Added mood selection field
        'currentMood': currentMood,
        'enablePictograms': enablePictograms,
        'disableTapPictograms': disableTapPictograms,
        'sightWordGradeLevel': sightWordGradeLevel,
        'spellLetterOrder': spellLetterOrder,
        'vocabularyLevel': vocabularyLevel,
        'enableSightWords': enableSightWords,
        'waitForSwitchToScan': waitForSwitchToScan, // Added wait for switch field
        'scanMode': scanMode, // Added scan mode field
        'useTapInterface': useTapInterface, // Added interface mode field
        'applicationVolume': applicationVolume, // Added application volume field
        'groupWakeWord': groupWakeWord,
        'emailDefaultRecipient': emailDefaultRecipient,
        'emailSubjectTemplate': emailSubjectTemplate,
        'personalVolume': personalVolume, // Added personal volume field
        'systemVolume': systemVolume, // Added system volume field
      };
}

class UserSettingsProvider extends ChangeNotifier {
  UserSettings? settings;
  bool isLoading = false;
  String? error;

  // You will need to provide these from your auth logic
  String? idToken;
  String? userId;
  final String apiBaseUrl;

  UserSettingsProvider({required this.apiBaseUrl, this.idToken, this.userId});

  /// Safely notify listeners, deferring if we're currently in a build phase.
  /// This prevents "setState() during build" errors.
  void safeNotifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      // We're in a build phase, defer the notification to after the frame
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          notifyListeners();
        } catch (e) {
          debugPrint('Error notifying listeners: $e');
        }
      });
    } else {
      // Not in a build phase, notify immediately
      try {
        notifyListeners();
      } catch (e) {
        debugPrint('Error notifying listeners: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> fetchInterfacePreference() async {
    if (userId == null) {
      return null;
    }
    
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '$apiBaseUrl/api/interface-preference',
        baseHeaders: {
          'X-User-ID': userId!,
        },
        maxRetries: 3,
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Error fetching interface preference: $e');
    }
    return null;
  }

  Future<void> fetchSettings() async {
    if (userId == null) {
      error = 'Not authenticated';
      safeNotifyListeners();
      return;
    }
    isLoading = true;
    error = null;
    safeNotifyListeners();
    
    try {
      // Use authenticated request with automatic token refresh
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '$apiBaseUrl/api/settings',
        baseHeaders: {
          'X-User-ID': userId!,
        },
        maxRetries: 2,
      );
      
      if (response.statusCode == 200) {
        debugPrint("Fetched settings: ${response.body}");
        final jsonData = json.decode(response.body);
        debugPrint("🔍 waitForSwitchToScan in JSON: ${jsonData['waitForSwitchToScan']}");
        settings = UserSettings.fromJson(jsonData);
        debugPrint("🔍 waitForSwitchToScan after fromJson: ${settings?.waitForSwitchToScan}");
        error = null;
      } else {
        error = 'Failed to load settings: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint("Settings fetch error: $e");
      error = 'Network error loading settings: $e';
    }
    
    isLoading = false;
    safeNotifyListeners();
  }

  Future<bool> updateSettings(void Function(UserSettings) updateFn, {bool save = true}) async {
    if (settings == null) return false;
    
    // Modify settings in place
    updateFn(settings!);
    
    // Notify listeners immediately so UI updates
    safeNotifyListeners();
    
    // Save the updated settings if requested
    if (save) {
      return await saveSettings(settings!);
    }
    return true;
  }

  Future<bool> saveSettings(UserSettings newSettings) async {
    debugPrint("Saving settings: ${newSettings.toJson()}");
    if (userId == null) {
      error = 'Not authenticated';
      safeNotifyListeners();
      return false;
    }
    isLoading = true;
    error = null;
    safeNotifyListeners();
    
    try {
      // Use authenticated request with automatic token refresh
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '$apiBaseUrl/api/settings',
        baseHeaders: {
          'X-User-ID': userId!,
          'Content-Type': 'application/json',
        },
        body: json.encode(newSettings.toJson()),
        maxRetries: 2,
      );
      
      if (response.statusCode == 200) {
        settings = UserSettings.fromJson(json.decode(response.body));
        error = null;
        isLoading = false;
        safeNotifyListeners();
        return true;
      } else {
        error = 'Failed to save settings: ${response.statusCode}';
        isLoading = false;
        safeNotifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint("Settings save error: $e");
      error = 'Network error saving settings: $e';
      isLoading = false;
      safeNotifyListeners();
      return false;
    }
  }

  List<String> availableTtsVoices = [];
  List<Map<String, dynamic>> availableTtsVoicesDetailed = []; // Store full voice data

  Future<void> fetchTtsVoices() async {
    if (userId == null) return;
    
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '$apiBaseUrl/api/tts-voices',
        baseHeaders: {
          'X-User-ID': userId!,
        },
        maxRetries: 3,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          availableTtsVoicesDetailed = data.cast<Map<String, dynamic>>();
          availableTtsVoices = data.map<String>((v) => v['name'] as String).toList();
        }
      }
    } catch (e) {
      debugPrint("TTS voices fetch error: $e");
    }
    
    safeNotifyListeners();
  }
}
