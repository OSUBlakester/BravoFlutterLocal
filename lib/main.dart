import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'services/user_settings_provider.dart';
import 'services/pictogram_service.dart';
import 'services/sight_word_service.dart';
import 'services/audio_device_provider.dart';
import 'services/audio_device_service.dart';
import 'services/chat_history_service.dart';
import 'services/authenticated_http_client.dart';
import 'services/auth_session_manager.dart';
import 'services/compose_session_service.dart';
import 'admin_pages_buttons.dart';
import 'user_current_admin_page.dart';
import 'user_info_admin_page.dart';
import 'user_diary_admin_page.dart';
import 'admin_settings_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_device_admin_page.dart';
import 'pages/tap_interface_admin_page.dart';
import 'services/wake_word_service.dart';
import 'services/app_health_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'config/environment_config.dart';
import 'freestyle_page.dart';
import 'threads_page.dart';
import 'favorites_page.dart';
import 'games_page.dart';
import 'tap_interface_page.dart';
import 'mood_selection_page.dart';
import 'app_loading_page.dart';
import 'email_page.dart';
import 'spelling_scan_page.dart';
import 'numbers_scan_page.dart';
import 'services/offline_cache_service.dart';
import 'services/offline_mode_provider.dart';
import 'services/music_playback_service.dart';

bool hasPlayedInitialWaitForSwitchVoicePrompt = false;

String? _safeRobotoCondensed() {
  return null;
}

class StandardHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 15);
    client.autoUncompress = true;
    return client;
  }
}

Future<T> retryNetworkOperation<T>(
  Future<T> Function() operation, {
  int maxRetries = 3,
  Duration delay = const Duration(seconds: 1),
  String operationName = 'Network operation',
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (e) {
      if (attempt == maxRetries) {
        rethrow;
      }
      await Future.delayed(delay * attempt);
    }
  }
  throw Exception('All retries failed');
}

Future<void> testTalkWithBravoServer() async {
  final testUrls = [
    'https://app.talkwithbravo.com',
    'http://app.talkwithbravo.com',
    'https://app.talkwithbravo.com/',
    'http://app.talkwithbravo.com/',
    'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app',
    'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app',
    'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app/',
    'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app/',
    'https://app.talkwithbravo.com/api',
    'http://app.talkwithbravo.com/api',
    'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api',
    'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api',
    'https://app.talkwithbravo.com/api/health',
    'http://app.talkwithbravo.com/api/health',
    'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api/health',
    'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api/health',
    'https://app.talkwithbravo.com/api/account',
    'http://app.talkwithbravo.com/api/account',
    'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api/account',
    'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api/account',
    'https://app.talkwithbravo.com/api/account/users',
    'http://app.talkwithbravo.com/api/account/users',
    'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api/account/users',
    'http://bravo-aac-api-lnquhqxkjq-uc.a.run.app/api/account/users',
  ];

  debugPrint('🔍 Testing TalkWithBravo server endpoints...');

  for (final testUrl in testUrls) {
    try {
      debugPrint('🔍 Testing: $testUrl');
      final response = await cruiseShipSafeGet(testUrl);
      debugPrint('🔍 RESULT: $testUrl -> Status ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('🔍 SUCCESS! Working endpoint found');
        final previewLength = response.body.length > 500
            ? 500
            : response.body.length;
        debugPrint(
          '🔍 Response preview: ${response.body.substring(0, previewLength)}',
        );
      } else if (response.statusCode == 503) {
        debugPrint('🔍 Server temporarily unavailable (503)');
      } else if (response.statusCode == 404) {
        debugPrint('🔍 Endpoint not found (404)');
      } else if (response.statusCode == 301 || response.statusCode == 302) {
        debugPrint('🔍 Redirect detected (${response.statusCode})');
        final location = response.headers['location'];
        if (location != null) {
          debugPrint('🔍 Redirect location: $location');
        }
      }
    } catch (e) {
      debugPrint('🔍 FAILED: $testUrl -> $e');
    }

    await Future.delayed(const Duration(milliseconds: 1000));
  }

  debugPrint('🔍 TalkWithBravo server test completed');
}

Future<String> getRefreshedIdToken() async {
  final token = await AuthenticatedHttpClient.getRefreshedIdToken();
  return token ?? '';
}

Future<http.Response> makeAuthenticatedRequest(
  String method,
  String url, {
  Map<String, String>? baseHeaders,
  String? body,
  int maxRetries = 3,
  int timeoutSeconds = 20,
}) async {
  debugPrint(
    '🔐 Making authenticated $method request to $url (timeout: ${timeoutSeconds}s)',
  );

  final uri = Uri.parse(url);

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      late String idToken;
      try {
        idToken = await getRefreshedIdToken();
        debugPrint(
          '🔐 Attempt $attempt: Token refreshed (length: ${idToken.length})',
        );
      } catch (e) {
        debugPrint('🔐 ❌ Failed to get ID token on attempt $attempt: $e');
        if (attempt == maxRetries) {
          throw Exception('Authentication required: $e');
        }
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        continue;
      }

      final headers = {...?baseHeaders};
      headers['Authorization'] = 'Bearer $idToken';

      http.Response response;

      if (method.toUpperCase() == 'GET') {
        response = await http
            .get(uri, headers: headers)
            .timeout(Duration(seconds: timeoutSeconds));
      } else if (method.toUpperCase() == 'POST') {
        response = await http
            .post(uri, headers: headers, body: body)
            .timeout(Duration(seconds: timeoutSeconds));
      } else if (method.toUpperCase() == 'PUT') {
        response = await http
            .put(uri, headers: headers, body: body)
            .timeout(Duration(seconds: timeoutSeconds));
      } else if (method.toUpperCase() == 'DELETE') {
        response = await http
            .delete(uri, headers: headers)
            .timeout(Duration(seconds: timeoutSeconds));
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }

      debugPrint('🔐 Attempt $attempt RESPONSE: Status ${response.statusCode}');

      if (response.statusCode == 401) {
        debugPrint(
          '🔐 ⚠️ Attempt $attempt got 401 Unauthorized - token may be invalid',
        );
        if (attempt < maxRetries) {
          debugPrint(
            '🔐 Retrying (attempt ${attempt + 1}/$maxRetries) with fresh token...',
          );
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        } else {
          debugPrint('🔐 ❌ Max retries exceeded on 401');
          return response;
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('🔐 ✅ Success on attempt $attempt!');
        return response;
      } else {
        debugPrint('🔐 ERROR on attempt $attempt: HTTP ${response.statusCode}');
        return response;
      }
    } catch (e) {
      debugPrint('🔐 Attempt $attempt failed with exception: $e');
      if (attempt == maxRetries) {
        rethrow;
      }
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }

  throw Exception('All retry attempts failed');
}

Future<http.Response> cruiseShipSafeGet(
  String url, {
  Map<String, String>? headers,
  int maxRetries = 2,
  int timeoutSeconds = 10,
}) async {
  debugPrint(
    '🚢 CruiseShip HTTP GET: Attempting connection to $url (timeout: ${timeoutSeconds}s)',
  );
  final uri = Uri.parse(url);
  try {
    final response = await http
        .get(uri, headers: headers)
        .timeout(
          Duration(seconds: timeoutSeconds),
          onTimeout: () => throw TimeoutException(
            'Request timeout',
            Duration(seconds: timeoutSeconds),
          ),
        );
    debugPrint('🚢 RESPONSE: Status ${response.statusCode}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('🚢 SUCCESS!');
      return response;
    } else {
      debugPrint('🚢 ERROR: HTTP ${response.statusCode}');
      throw Exception('HTTP error: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('🚢 FAILED: $url -> $e');
    throw Exception('Network request failed: $e');
  }
}

void main() {
  print('🚀🚀🚀 MAIN() STARTED 🚀🚀🚀');

  try {
    WidgetsFlutterBinding.ensureInitialized();
    print('✅ WidgetsFlutterBinding initialized');

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    print('✅ Screen orientation set to landscape');

    if (!kIsWeb) {
      HttpOverrides.global = StandardHttpOverrides();
    }
    print('✅ Network configuration complete');

    SightWordService()
        .initialize()
        .then((_) {
          print('✅ SightWordService initialized');
        })
        .catchError((e) {
          print('⚠️ SightWordService init failed: $e');
        });

    print('✅ main() initialization complete, preparing runApp()...');
  } catch (e, stackTrace) {
    print('❌ CRITICAL ERROR in main(): $e');
    print('❌ Stack trace: $stackTrace');
  }

  print('🚀 Calling runApp(MyApp())...');
  runApp(const MyApp());
  print('🚀 runApp() called successfully');
  print('🚀 runApp() called successfully');
}

// User Selection Page
class UserSelectionPage extends StatefulWidget {
  final String idToken;
  final List<dynamic> userProfiles;

  const UserSelectionPage({
    super.key,
    required this.idToken,
    required this.userProfiles,
  });

  @override
  State<UserSelectionPage> createState() => _UserSelectionPageState();
}

class _UserSelectionPageState extends State<UserSelectionPage> {
  String? selectedProfileId;
  List<dynamic> profiles = [];
  final TextEditingController newProfileController = TextEditingController();
  final TextEditingController editProfileController = TextEditingController();
  bool setAsDefault = false;
  String? currentDefaultProfileId;

  @override
  void initState() {
    super.initState();
    profiles = List.from(widget.userProfiles);
    if (profiles.isNotEmpty) {
      selectedProfileId = profiles[0]['aac_user_id'];
    }
    _loadDefaultProfile();
  }

  Future<void> _loadDefaultProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedDefaultProfileId = prefs.getString('default_profile_id');
    print(
      '🔵 ProfileSelection - Loading default profile: $loadedDefaultProfileId',
    );
    setState(() {
      currentDefaultProfileId = loadedDefaultProfileId;
      // If the current selection is the default, check the checkbox
      if (currentDefaultProfileId != null &&
          currentDefaultProfileId == selectedProfileId) {
        setAsDefault = true;
      }
    });
    print(
      '🔵 ProfileSelection - Set currentDefaultProfileId to: $currentDefaultProfileId',
    );
  }

  Future<void> _saveDefaultProfile() async {
    final prefs = await SharedPreferences.getInstance();
    print(
      '🔵 ProfileSelection - Saving default profile. setAsDefault: $setAsDefault, selectedProfileId: $selectedProfileId',
    );
    if (setAsDefault && selectedProfileId != null) {
      await prefs.setString('default_profile_id', selectedProfileId!);
      // Force synchronization to disk on iOS
      await prefs.reload();
      print(
        '🔵 ProfileSelection - Saved default_profile_id: $selectedProfileId',
      );
      setState(() {
        currentDefaultProfileId = selectedProfileId;
      });
    } else if (!setAsDefault && currentDefaultProfileId == selectedProfileId) {
      // User unchecked default for the current default profile
      await prefs.remove('default_profile_id');
      // Force synchronization to disk on iOS
      await prefs.reload();
      print('🔵 ProfileSelection - Removed default_profile_id');
      setState(() {
        currentDefaultProfileId = null;
      });
    }

    // Verify the save worked
    final savedValue = prefs.getString('default_profile_id');
    print(
      '🔵 ProfileSelection - Verification - default_profile_id after save: $savedValue',
    );
  }

  Future<void> _clearDefaultProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('default_profile_id');
    setState(() {
      currentDefaultProfileId = null;
      setAsDefault = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Default profile cleared')));
  }

  @override
  void dispose() {
    newProfileController.dispose();
    editProfileController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get selectedProfile {
    if (selectedProfileId == null) return null;
    return profiles.firstWhere(
      (profile) => profile['aac_user_id'] == selectedProfileId,
      orElse: () => null,
    );
  }

  Future<void> _editProfile() async {
    final profile = selectedProfile;
    if (profile == null) return;

    editProfileController.text = profile['display_name'] ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile Name'),
        content: TextField(
          controller: editProfileController,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter profile name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, editProfileController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _updateProfileName(profile['aac_user_id'], result);
    }
  }

  Future<void> _updateProfileName(String aacUserId, String newName) async {
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'PUT',
        '${EnvironmentConfig.apiBaseUrl}/api/account/edit-user-display-name',
        baseHeaders: {'Content-Type': 'application/json'},
        body: json.encode({
          'aac_user_id': aacUserId,
          'new_display_name': newName,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = profiles.indexWhere(
            (p) => p['aac_user_id'] == aacUserId,
          );
          if (index != -1) {
            profiles[index]['display_name'] = newName;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile name updated successfully')),
        );
      } else {
        throw Exception(
          'Failed to update profile name (${response.statusCode})',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    }
  }

  Future<void> _deleteProfile() async {
    final profile = selectedProfile;
    if (profile == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text(
          'Are you sure you want to delete "${profile['display_name']}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _performDeleteProfile(profile['aac_user_id']);
    }
  }

  Future<void> _performDeleteProfile(String aacUserId) async {
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'DELETE',
        '${EnvironmentConfig.apiBaseUrl}/api/account/delete-user',
        baseHeaders: {'Content-Type': 'application/json'},
        body: json.encode({'aac_user_id': aacUserId}),
      );

      if (response.statusCode == 200) {
        setState(() {
          profiles.removeWhere((p) => p['aac_user_id'] == aacUserId);
          if (selectedProfileId == aacUserId) {
            selectedProfileId = profiles.isNotEmpty
                ? profiles[0]['aac_user_id']
                : null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile deleted successfully')),
        );
      } else {
        throw Exception('Failed to delete profile (${response.statusCode})');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error deleting profile: $e')));
    }
  }

  Future<void> _copyProfile() async {
    final profile = selectedProfile;
    if (profile == null) return;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy Profile'),
        content: TextField(
          decoration: InputDecoration(
            labelText: 'New Profile Name',
            hintText: '${profile['display_name']} (Copy)',
          ),
          autofocus: true,
          onChanged: (value) => editProfileController.text = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, editProfileController.text.trim()),
            child: const Text('Copy'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _performCopyProfile(profile['aac_user_id'], newName);
    }
  }

  Future<void> _performCopyProfile(
    String sourceAacUserId,
    String newName,
  ) async {
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/account/copy-user',
        baseHeaders: {'Content-Type': 'application/json'},
        body: json.encode({
          'source_aac_user_id': sourceAacUserId,
          'new_display_name': newName,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final newProfile = json.decode(response.body);
        setState(() {
          profiles.add({
            'aac_user_id': newProfile['new_aac_user_id'],
            'display_name': newProfile['new_display_name'],
          });
          selectedProfileId = newProfile['new_aac_user_id'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile copied successfully')),
        );
      } else {
        throw Exception('Failed to copy profile (${response.statusCode})');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error copying profile: $e')));
    }
  }

  Future<void> _createNewProfile() async {
    final newName = newProfileController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a profile name')),
      );
      return;
    }

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/account/add-aac-user',
        baseHeaders: {'Content-Type': 'application/json'},
        body: json.encode({'display_name': newName}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final newProfile = json.decode(response.body);
        setState(() {
          profiles.add({
            'aac_user_id': newProfile['aac_user_id'],
            'display_name': newProfile['display_name'],
          });
          selectedProfileId = newProfile['aac_user_id'];
          newProfileController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile created successfully')),
        );
      } else {
        throw Exception('Failed to create profile (${response.statusCode})');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating profile: $e')));
    }
  }

  void _selectProfile() async {
    print('🔵 ProfileSelection - _selectProfile called');
    print(
      '🔵 ProfileSelection - Current selectedProfileId: $selectedProfileId',
    );
    final profile = selectedProfile;
    if (profile == null) {
      print('❌ ProfileSelection - No profile selected, returning early');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a profile first')),
      );
      return;
    }

    print(
      '🔵 ProfileSelection - Selected profile: ${profile['display_name']} (${profile['aac_user_id']})',
    );
    print(
      '🔵 ProfileSelection - CRITICAL DEBUG: About to navigate with aac_user_id: ${profile['aac_user_id']}',
    );

    try {
      // Save default profile setting if needed
      await _saveDefaultProfile();
      print('🔵 ProfileSelection - Default profile saved successfully');

      // Cache the selected profile for offline use
      await OfflineCacheService.saveProfile(
        userId: profile['aac_user_id'],
        displayName: profile['display_name'] ?? 'User',
      );

      // Use helper method to navigate based on mood selection settings
      print('🔵 ProfileSelection - Starting navigation to main app...');
      await _navigateToMainApp(
        widget.idToken,
        profile['aac_user_id'],
        profile['display_name'] ?? 'User',
      );
      print('🔵 ProfileSelection - Navigation completed');
    } catch (e) {
      print('❌ ProfileSelection - Error during profile selection: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error selecting profile: $e')));
    }
  }

  // Helper method to navigate to appropriate page based on mood selection settings
  Future<void> _navigateToMainApp(
    String idToken,
    String aacUserId,
    String displayName,
  ) async {
    print(
      '🔵 ProfileSelection - _navigateToMainApp called with userId: $aacUserId, displayName: $displayName',
    );
    print(
      '🚨 CRITICAL TRACE: _navigateToMainApp received aacUserId: $aacUserId',
    );
    print(
      '🚨 CRITICAL TRACE: About to create GridPage with this aacUserId: $aacUserId',
    );

    try {
      // Check if mood selection is enabled
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      print('🔵 ProfileSelection - Got settings provider');

      // Initialize settings if needed
      if (settingsProvider.settings == null) {
        print('🔵 ProfileSelection - Settings not loaded, fetching...');
        settingsProvider.idToken = idToken;
        print('🔵 SETTINGS PROVIDER: Setting userId to: $aacUserId');
        settingsProvider.userId = aacUserId;
        await settingsProvider.fetchSettings();
        print('🔵 ProfileSelection - Settings fetched successfully');
      } else {
        print('🔵 ProfileSelection - Using existing settings');
      }

      final enableMoodSelection =
          settingsProvider.settings?.enableMoodSelection ?? false;
      final useTapInterface =
          settingsProvider.settings?.useTapInterface ?? false;
      print(
        '🔵 ProfileSelection - Mood selection enabled: $enableMoodSelection',
      );
      print('🔵 ProfileSelection - Use tap interface: $useTapInterface');

      if (enableMoodSelection) {
        // Navigate to app loading page first
        print(
          '🔵 ProfileSelection - Navigating to AppLoadingPage for mood selection',
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppLoadingPage(
              idToken: idToken,
              aacUserId: aacUserId,
              displayName: displayName,
              useTapInterface: false,
            ),
          ),
        );
        print('🔵 ProfileSelection - Navigation to AppLoadingPage initiated');
      } else {
        // Navigate directly to appropriate interface based on user preference
        if (useTapInterface) {
          print(
            '🔵 ProfileSelection - Navigating to AppLoadingPage for tap interface',
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AppLoadingPage(
                idToken: idToken,
                aacUserId: aacUserId,
                displayName: displayName,
                useTapInterface: true,
              ),
            ),
          );
          print('🔵 ProfileSelection - Navigation to AppLoadingPage initiated');
        } else {
          print('🔵 ProfileSelection - Navigating to GridPage');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) {
                print(
                  '🚨 CRITICAL TRACE: Creating GridPage with aacUserId: $aacUserId',
                );
                return GridPage(
                  idToken: idToken,
                  aacUserId: aacUserId,
                  displayName: displayName,
                );
              },
            ),
          );
          print('🔵 ProfileSelection - Navigation to GridPage initiated');
        }
      }
    } catch (e, stackTrace) {
      print('❌ ProfileSelection - Error in _navigateToMainApp: $e');
      print('❌ ProfileSelection - Stack trace: $stackTrace');

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigation error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please select a profile to continue:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (currentDefaultProfileId != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Default Profile: ${profiles.firstWhere((p) => p['aac_user_id'] == currentDefaultProfileId, orElse: () => {'display_name': 'Unknown'})['display_name']}',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Profile Selection Row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedProfileId,
                    decoration: const InputDecoration(
                      labelText: 'Profile',
                      border: OutlineInputBorder(),
                    ),
                    items: profiles.map<DropdownMenuItem<String>>((profile) {
                      final displayName = profile['display_name'] ?? 'User';
                      return DropdownMenuItem<String>(
                        value: profile['aac_user_id'],
                        child: Text(displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedProfileId = value;
                        // Update checkbox state based on whether selected profile is the default
                        if (currentDefaultProfileId != null &&
                            currentDefaultProfileId == value) {
                          setAsDefault = true;
                        } else {
                          setAsDefault = false;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: profiles.isNotEmpty && selectedProfileId != null
                      ? _editProfile
                      : null,
                  child: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: profiles.isNotEmpty && selectedProfileId != null
                      ? _deleteProfile
                      : null,
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: profiles.isNotEmpty && selectedProfileId != null
                      ? _copyProfile
                      : null,
                  child: const Text('Copy'),
                ),
              ],
            ),

            // Default Profile Section
            if (profiles.length > 1) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('Set as default profile'),
                      subtitle: const Text(
                        'Skip profile selection on this device',
                      ),
                      value: setAsDefault,
                      onChanged: (value) {
                        setState(() {
                          setAsDefault = value ?? false;
                        });
                        print(
                          '🔵 ProfileSelection - Checkbox changed: setAsDefault = $setAsDefault',
                        );
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (currentDefaultProfileId != null) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _clearDefaultProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear Default'),
                    ),
                  ],
                ],
              ),
              if (setAsDefault) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.save, color: Colors.green[600], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This profile will be saved as default and automatically selected on app startup',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 24),

            // Create New Profile Section
            const Text(
              'Create New Profile:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: newProfileController,
                    decoration: const InputDecoration(
                      labelText: 'New Profile Name',
                      hintText: 'Enter profile name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _createNewProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add Profile'),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Select Profile Button
            if (profiles.isNotEmpty && selectedProfileId != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectProfile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    setAsDefault
                        ? 'Select "${selectedProfile?['display_name'] ?? 'Profile'}" (Set as Default)'
                        : 'Select "${selectedProfile?['display_name'] ?? 'Profile'}"',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),

            const Spacer(),

            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Sign out and return to auth page
                  AuthSessionManager.clearAuthenticatedSession();
                  FirebaseAuth.instance.signOut();
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/auth', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.grey[600],
                ),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLogin = true;
  bool isLoading = false;
  String error = '';
  bool _rememberMe = false;
  final _storage = const FlutterSecureStorage();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final accountNameController = TextEditingController();
  final numUsersController = TextEditingController(text: '1');
  final promoCodeController = TextEditingController();
  final addressController = TextEditingController();
  final phoneController = TextEditingController();
  final therapistEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  // Load saved credentials on app start
  Future<void> _loadSavedCredentials() async {
    try {
      final savedEmail = await _storage.read(key: 'saved_email');
      final savedPassword = await _storage.read(key: 'saved_password');

      if (savedEmail != null && savedPassword != null) {
        setState(() {
          emailController.text = savedEmail;
          passwordController.text = savedPassword;
          _rememberMe = true;
        });
      }
    } catch (e) {
      print('Error loading saved credentials: $e');
    }
  }

  // Save credentials to secure storage
  Future<void> _saveCredentials() async {
    if (_rememberMe &&
        emailController.text.isNotEmpty &&
        passwordController.text.isNotEmpty) {
      try {
        await _storage.write(
          key: 'saved_email',
          value: emailController.text.trim(),
        );
        await _storage.write(
          key: 'saved_password',
          value: passwordController.text.trim(),
        );
      } catch (e) {
        print('Error saving credentials: $e');
      }
    }
  }

  // Clear saved credentials
  Future<void> _clearSavedCredentials() async {
    try {
      await _storage.delete(key: 'saved_email');
      await _storage.delete(key: 'saved_password');
    } catch (e) {
      print('Error clearing credentials: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('AuthPage build method called');
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Register')),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLogin ? 'Login' : 'Register',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                if (isLogin) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                            if (!_rememberMe) {
                              _clearSavedCredentials();
                            }
                          });
                        },
                      ),
                      const Text('Remember me'),
                      const Spacer(),
                      if (_rememberMe) ...[
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _rememberMe = false;
                              emailController.clear();
                              passwordController.clear();
                            });
                            _clearSavedCredentials();
                          },
                          child: const Text('Clear saved'),
                        ),
                      ],
                    ],
                  ),
                ],
                if (!isLogin) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: accountNameController,
                    decoration: const InputDecoration(
                      labelText: 'Account Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numUsersController,
                    decoration: const InputDecoration(
                      labelText: 'Number of Users',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: promoCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Promo Code (Optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address (Optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone (Optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: therapistEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Therapist/Admin Email (Optional)',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (error.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Authentication Error',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: error));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Error copied to clipboard'),
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.copy,
                                size: 16,
                                color: Colors.red.shade600,
                              ),
                              tooltip: 'Copy error to clipboard',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () => isLogin ? handleLogin() : handleRegister(),
                  child: Text(isLogin ? 'Login' : 'Register'),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => setState(() => isLogin = !isLogin),
                  child: Text(
                    isLogin
                        ? "Don't have an account? Register here"
                        : "Already have an account? Login here",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> handleLogin() async {
    setState(() {
      isLoading = true;
      error = '';
    });

    // COMPREHENSIVE ERROR LOGGING AND USER FEEDBACK
    print('🔐🔐🔐 LOGIN ATTEMPT STARTED 🔐🔐🔐');
    print('🔐 Email: ${emailController.text.trim()}');
    print('🔐 Password length: ${passwordController.text.length}');

    try {
      // Check if Firebase is initialized
      print('🔐 STEP 1: Checking Firebase initialization...');
      try {
        final app = Firebase.app();
        print(
          '🔐 ✅ Firebase app found: ${app.name}, project: ${app.options.projectId}',
        );

        // Additional verification: ensure FirebaseAuth instance is ready
        final auth = FirebaseAuth.instance;
        print('🔐 ✅ FirebaseAuth instance verified: ${auth.app.name}');

        // Small delay to ensure all Firebase services are fully ready
        await Future.delayed(const Duration(milliseconds: 200));
        print('🔐 ✅ Firebase services ready for authentication');
      } catch (e) {
        print('🔐 ❌ Firebase not initialized: $e');
        setState(() {
          error =
              'FIREBASE ERROR: Firebase not initialized properly. Please restart the app and wait for initialization to complete.';
          isLoading = false;
        });
        throw Exception(
          'Firebase not initialized properly. Please restart the app and wait for initialization to complete.',
        );
      }

      print('🔐 STEP 2: Attempting Firebase Auth login...');
      print('🔐 Email for authentication: "${emailController.text.trim()}"');

      UserCredential? userCredential;
      try {
        userCredential = await retryNetworkOperation(
          () async {
            print('🔐 🚀 Calling Firebase signInWithEmailAndPassword...');
            final result = await FirebaseAuth.instance
                .signInWithEmailAndPassword(
                  email: emailController.text.trim(),
                  password: passwordController.text.trim(),
                );
            print('🔐 ✅ Firebase auth call completed successfully');
            return result;
          },
          operationName: 'Firebase Authentication',
          maxRetries: 5, // More retries for cruise ship networks
          delay: const Duration(seconds: 3),
        );
        print('🔐 ✅ Firebase authentication successful');
      } catch (authError) {
        print('🔐 ❌ Firebase authentication FAILED: $authError');
        setState(() {
          error = 'LOGIN FAILED: ${authError.toString()}';
          isLoading = false;
        });
        throw authError;
      }

      print('🔐 STEP 3: Processing user credentials...');
      final user = userCredential?.user;
      if (user == null) {
        print('🔐 ❌ No user returned from Firebase');
        setState(() {
          error = 'AUTHENTICATION ERROR: No user returned from Firebase.';
          isLoading = false;
        });
        throw Exception('No user returned from Firebase.');
      }
      print('🔐 ✅ User obtained from Firebase: ${user.email}');

      print('🔐 STEP 4: Getting ID token...');
      final idToken = await user.getIdToken() ?? '';
      if (idToken.isEmpty) {
        print('🔐 ❌ Failed to retrieve ID token');
        setState(() {
          error = 'TOKEN ERROR: Failed to retrieve ID token.';
          isLoading = false;
        });
        throw Exception('Failed to retrieve ID token.');
      }
      print('🔐 ✅ ID token retrieved successfully (length: ${idToken.length})');
      AuthSessionManager.recordAuthenticatedSession(idToken);

      // Save credentials if remember me is checked
      if (_rememberMe) {
        print('🔐 STEP 5: Saving credentials...');
        await _saveCredentials();
        print('🔐 ✅ Credentials saved');
      }

      print('🔐 STEP 6: Fetching AAC user profiles from backend...');
      // Fetch AAC user profiles from backend
      http.Response? response;
      try {
        response = await retryNetworkOperation(
          () async {
            print(
              '🔐 📡 Making API call to: ${EnvironmentConfig.apiBaseUrl}/api/account/users',
            );
            final result = await cruiseShipSafeGet(
              '${EnvironmentConfig.apiBaseUrl}/api/account/users',
              headers: {
                'Authorization': 'Bearer $idToken',
                'Content-Type': 'application/json',
              },
              timeoutSeconds:
                  30, // Longer timeout for initial login (handles Cloud Run cold starts)
            );
            print('🔐 📡 API call completed with status: ${result.statusCode}');
            return result;
          },
          operationName: 'Backend API call (user profiles)',
          maxRetries: 4,
        );
        print('🔐 ✅ Backend API call successful');
      } catch (apiError) {
        print('🔐 ❌ Backend API call FAILED: $apiError');

        // Check for offline/network errors and offer offline mode
        final errorStr = apiError.toString().toLowerCase();
        final isNetworkError = apiError is SocketException ||
            apiError is TimeoutException ||
            errorStr.contains('network') ||
            errorStr.contains('connection') ||
            errorStr.contains('socketexception') ||
            errorStr.contains('timeout');

        if (isNetworkError && mounted) {
          setState(() { isLoading = false; });
          final cached = await OfflineCacheService.loadProfile();
          if (cached == null) {
            if (mounted) {
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('No Network Connection'),
                  content: const Text(
                    'No network connection and no cached profile available. '
                    'Please connect to the internet and try again.',
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text('Exit'),
                    ),
                  ],
                ),
              );
            }
            return;
          } else {
            // Cached profile available — offer offline mode
            bool continueOffline = false;
            if (mounted) {
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('No Network Connection'),
                  content: Text(
                    'Continue offline using the last-used profile: ${cached.displayName}?\n\n'
                    'Some features will be unavailable.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        SystemNavigator.pop();
                      },
                      child: const Text('Exit'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        continueOffline = true;
                        Navigator.pop(ctx);
                      },
                      child: const Text('Continue Offline'),
                    ),
                  ],
                ),
              );
            }
            if (continueOffline && mounted) {
              final offlineProvider = Provider.of<OfflineModeProvider>(
                context,
                listen: false,
              );
              offlineProvider.setOffline(true);
              final cachedIdToken =
                  await FirebaseAuth.instance.currentUser?.getIdToken(false) ?? '';
              // Navigate based on settings — use AppLoadingPage which handles offline path
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => AppLoadingPage(
                    idToken: cachedIdToken,
                    aacUserId: cached.userId,
                    displayName: cached.displayName,
                    useTapInterface: true,
                  ),
                ),
              );
            }
            return;
          }
        }

        setState(() {
          error = 'API ERROR: Failed to fetch user profiles - $apiError';
          isLoading = false;
        });
        throw apiError;
      }

      print(
        '🔐 STEP 7: Processing response (Status: ${response?.statusCode})...',
      );
      if (response != null && response.statusCode == 200) {
        print('🔐 ✅ Response status 200 - parsing user profiles...');
        final userProfiles = json.decode(response.body);
        print('🔐 📝 User profiles received: ${userProfiles.length} profiles');

        if (userProfiles is List && userProfiles.isNotEmpty) {
          // Check for default profile first
          final prefs = await SharedPreferences.getInstance();
          final defaultProfileId = prefs.getString('default_profile_id');
          print(
            '🔵 AuthenticationWrapper - Checking for default profile: $defaultProfileId',
          );

          if (defaultProfileId != null) {
            print(
              '🔵 AuthenticationWrapper - Default profile found: $defaultProfileId',
            );
            // Try to find the default profile in the list
            final defaultProfile = userProfiles.firstWhere(
              (profile) => profile['aac_user_id'] == defaultProfileId,
              orElse: () => null,
            );
            print(
              '🔵 AuthenticationWrapper - Default profile lookup result: ${defaultProfile != null ? "Found" : "Not found"}',
            );

            if (defaultProfile != null) {
              print(
                '🔵 AuthenticationWrapper - Using default profile: ${defaultProfile['display_name']} (${defaultProfile['aac_user_id']})',
              );
              // Default profile found - check for mood selection
              final settingsProvider = Provider.of<UserSettingsProvider>(
                context,
                listen: false,
              );
              settingsProvider.idToken = idToken;
              settingsProvider.userId = defaultProfile['aac_user_id'];
              await settingsProvider.fetchSettings();

              final enableMoodSelection =
                  settingsProvider.settings?.enableMoodSelection ?? false;
              final useTapInterface =
                  settingsProvider.settings?.useTapInterface ?? false;

              if (enableMoodSelection) {
                print(
                  '🔵 AuthenticationWrapper - Navigating to app loading for mood selection with default profile',
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => AppLoadingPage(
                      idToken: idToken,
                      aacUserId: defaultProfile['aac_user_id'],
                      displayName: defaultProfile['display_name'] ?? 'User',
                      useTapInterface: useTapInterface,
                    ),
                  ),
                );
              } else if (useTapInterface) {
                print(
                  '🔵 AuthenticationWrapper - Navigating to tap interface with default profile',
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => TapInterfacePage(
                      idToken: idToken,
                      aacUserId: defaultProfile['aac_user_id'],
                      displayName: defaultProfile['display_name'] ?? 'User',
                    ),
                  ),
                );
              } else {
                print(
                  '🔵 AuthenticationWrapper - Navigating to grid page with default profile',
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) {
                      print(
                        '🚨 CRITICAL TRACE: Creating GridPage (DEFAULT PROFILE) with aacUserId: ${defaultProfile['aac_user_id']}',
                      );
                      return GridPage(
                        idToken: idToken,
                        aacUserId: defaultProfile['aac_user_id'],
                        displayName: defaultProfile['display_name'] ?? 'User',
                      );
                    },
                  ),
                );
              }
              return; // Exit early
            } else {
              print(
                '🔵 AuthenticationWrapper - Default profile no longer exists, clearing it',
              );
              // Default profile no longer exists, clear it
              await prefs.remove('default_profile_id');
            }
          } else {
            print('🔵 AuthenticationWrapper - No default profile found');
          }

          // If only one AAC user, auto-select (original behavior)
          if (userProfiles.length == 1) {
            final selectedAacUserId = userProfiles[0]['aac_user_id'];
            final selectedDisplayName = userProfiles[0]['display_name'];

            // Check for mood selection
            final settingsProvider = Provider.of<UserSettingsProvider>(
              context,
              listen: false,
            );
            settingsProvider.idToken = idToken;
            settingsProvider.userId = selectedAacUserId;
            await settingsProvider.fetchSettings();

            final enableMoodSelection =
                settingsProvider.settings?.enableMoodSelection ?? false;
            final useTapInterface =
                settingsProvider.settings?.useTapInterface ?? false;

            if (enableMoodSelection) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => AppLoadingPage(
                    idToken: idToken,
                    aacUserId: selectedAacUserId ?? '',
                    displayName: selectedDisplayName,
                    useTapInterface: useTapInterface,
                  ),
                ),
              );
            } else if (useTapInterface) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => TapInterfacePage(
                    idToken: idToken,
                    aacUserId: selectedAacUserId ?? '',
                    displayName: selectedDisplayName,
                  ),
                ),
              );
            } else {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) {
                    print(
                      '🚨 CRITICAL TRACE: Creating GridPage (SELECTED PROFILE 1) with aacUserId: ${selectedAacUserId ?? ""}',
                    );
                    return GridPage(
                      idToken: idToken,
                      aacUserId: selectedAacUserId ?? '',
                      displayName: selectedDisplayName,
                    );
                  },
                ),
              );
            }
          } else {
            // Multiple users - show selection page
            print(
              '🔵 AuthenticationWrapper - Multiple profiles found (${userProfiles.length}), showing selection screen',
            );
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => UserSelectionPage(
                  idToken: idToken,
                  userProfiles: userProfiles,
                ),
              ),
            );
          }
        } else {
          print('🔐 ❌ No AAC user profiles found');
          setState(() {
            error =
                'PROFILE ERROR: No AAC user profiles found for this account.';
            isLoading = false;
          });
        }
      } else {
        print(
          '🔐 ❌ Failed to fetch user profiles - Status: ${response?.statusCode}',
        );
        setState(() {
          error =
              'SERVER ERROR: Failed to fetch user profiles (${response?.statusCode}).';
          isLoading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      print('🔐 ❌❌❌ FIREBASE AUTH EXCEPTION: ${e.code} - ${e.message}');
      setState(() {
        error =
            'FIREBASE AUTH ERROR [${e.code}]: ${e.message ?? 'Login failed.'}';
        isLoading = false;
      });
    } catch (e) {
      print('🔐 ❌❌❌ GENERAL EXCEPTION: $e');
      print('🔐 Exception type: ${e.runtimeType}');
      setState(() {
        error = 'UNEXPECTED ERROR: ${e.toString()}';
        isLoading = false;
      });
    } finally {
      print('🔐 🏁 LOGIN ATTEMPT COMPLETED 🏁');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> handleRegister() async {
    setState(() {
      isLoading = true;
      error = '';
    });
    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );
      final user = userCredential.user;
      if (user == null) throw Exception('No user returned from Firebase.');
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty)
        throw Exception('Failed to retrieve ID token.');
      // Register account in backend
      final backendResponse = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/auth/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({
          'email': emailController.text.trim(),
          'account_name': accountNameController.text.trim(),
          'num_users_allowed':
              int.tryParse(numUsersController.text.trim()) ?? 1,
          'promo_code': promoCodeController.text.trim().isEmpty
              ? null
              : promoCodeController.text.trim(),
          'address': addressController.text.trim().isEmpty
              ? null
              : addressController.text.trim(),
          'phone': phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          'therapist_email': therapistEmailController.text.trim().isEmpty
              ? null
              : therapistEmailController.text.trim(),
        }),
      );
      if (backendResponse.statusCode == 200 ||
          backendResponse.statusCode == 201) {
        final backendResult = json.decode(backendResponse.body);
        final selectedAacUserId = backendResult['first_aac_user_id'];
        final selectedDisplayName =
            accountNameController.text.trim() + "'s Device 1";

        // Check for mood selection for new registrations
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        settingsProvider.idToken = idToken;
        settingsProvider.userId = selectedAacUserId;
        await settingsProvider.fetchSettings();

        final enableMoodSelection =
            settingsProvider.settings?.enableMoodSelection ?? false;

        if (enableMoodSelection) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MoodSelectionPage(
                idToken: idToken,
                aacUserId: selectedAacUserId ?? '',
                displayName: selectedDisplayName,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) {
                print(
                  '🚨 CRITICAL TRACE: Creating GridPage (SELECTED PROFILE 2) with aacUserId: ${selectedAacUserId ?? ""}',
                );
                return GridPage(
                  idToken: idToken,
                  aacUserId: selectedAacUserId ?? '',
                  displayName: selectedDisplayName,
                );
              },
            ),
          );
        }
      } else {
        setState(() {
          error =
              'Backend registration failed (${backendResponse.statusCode}).';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message ?? 'Registration failed.';
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
}

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
// --- End custom widgets ---
// --- Top-level app classes ---

// Firebase Initialization Wrapper to ensure Firebase is ready before showing AuthPage
class FirebaseInitializationWrapper extends StatefulWidget {
  const FirebaseInitializationWrapper({super.key});

  @override
  State<FirebaseInitializationWrapper> createState() =>
      _FirebaseInitializationWrapperState();
}

class _FirebaseInitializationWrapperState
    extends State<FirebaseInitializationWrapper> {
  bool _isFirebaseInitialized = false;

  @override
  void initState() {
    super.initState();
    print('🔥🔥🔥 FirebaseInitializationWrapper initState() called');

    // Proceed immediately to avoid black screen
    setState(() {
      _isFirebaseInitialized = true;
    });

    // Initialize Firebase in the background WITHOUT BLOCKING
    _initializeFirebaseAsync();
  }

  Future<void> _initializeFirebaseAsync() async {
    try {
      print('🔥 Starting Firebase initialization in background...');
      print('🔥 Environment: ${EnvironmentConfig.environmentName}');

      // Initialize Firebase with timeout
      if (kIsWeb) {
        final config = EnvironmentConfig.firebaseWebConfig;
        await Future.any([
          Future.delayed(
            const Duration(seconds: 15),
            () => throw TimeoutException('Firebase init timeout'),
          ),
          Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: config['apiKey']!,
              authDomain: config['authDomain']!,
              projectId: config['projectId']!,
              storageBucket: config['storageBucket']!,
              messagingSenderId: config['messagingSenderId']!,
              appId: config['appId']!,
            ),
          ),
        ]);
      } else {
        final config = EnvironmentConfig.firebaseIosConfig;
        await Future.any([
          Future.delayed(
            const Duration(seconds: 15),
            () => throw TimeoutException('Firebase init timeout'),
          ),
          Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: config['apiKey']!,
              appId: config['appId']!,
              messagingSenderId: config['messagingSenderId']!,
              projectId: config['projectId']!,
              storageBucket: config['storageBucket']!,
            ),
          ),
        ]);
      }

      print('✅ Firebase initialized successfully');

      // Set Firebase Auth persistence
      if (!kIsWeb) {
        try {
          await Future.any([
            Future.delayed(
              const Duration(seconds: 5),
              () => throw TimeoutException('Auth persistence timeout'),
            ),
            FirebaseAuth.instance.setPersistence(Persistence.LOCAL),
          ]);
          print('✅ Firebase Auth persistence set');
        } catch (e) {
          print('⚠️ Firebase Auth config warning: $e');
        }
      }
    } catch (e) {
      print('⚠️ Firebase initialization timeout/error: $e');
      print('⚠️ Continuing without Firebase - some features may be limited');
    }
  }

  Future<void> _checkFirebaseInitialization() async {
    try {
      print('🔥 Checking Firebase initialization status...');

      // Add timeout to prevent infinite waiting
      final app = await Future.any([
        Future.delayed(
          const Duration(seconds: 5),
          () => throw TimeoutException('Firebase check timeout'),
        ),
        Future(() => Firebase.app()),
      ]);

      print(
        '🔥 ✅ Firebase is initialized: ${app.name}, project: ${app.options.projectId}',
      );
    } catch (e) {
      print('🔥 ⚠️ Firebase initialization check warning: $e');
      // Don't block UI - just log the warning
    }
  }

  Future<void> _testFirebaseConnectivity() async {
    try {
      print('🔥 Testing Firebase Auth connectivity...');

      // Try to get current user (this will test if Firebase Auth is responding)
      final user = FirebaseAuth.instance.currentUser;
      print('🔥 Current user: ${user?.email ?? 'No user signed in'}');

      print('🔥 ✅ Firebase connectivity test passed');
    } catch (e) {
      print('🔥 ⚠️ Firebase connectivity test warning: $e');
      // Don't fail initialization for connectivity issues, just log them
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔥🔥🔥 FirebaseInitializationWrapper build() called');

    // Return AuthPage - Firebase initializes in background
    return const AuthPage();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('MyApp build method called');
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UserSettingsProvider>(
          create: (_) =>
              UserSettingsProvider(apiBaseUrl: EnvironmentConfig.apiBaseUrl),
        ),
        ChangeNotifierProvider<AudioDeviceProvider>(
          create: (_) => AudioDeviceProvider(),
        ),
        ChangeNotifierProvider<OfflineModeProvider>(
          create: (_) => OfflineModeProvider(),
        ),
        ChangeNotifierProvider<MusicPlaybackService>(
          create: (_) => MusicPlaybackService(),
        ),
      ],
      child: MaterialApp(
        title: 'Bravo AAC',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        navigatorKey: AuthSessionManager.navigatorKey,
        scaffoldMessengerKey: AuthSessionManager.scaffoldMessengerKey,
        home: const FirebaseInitializationWrapper(),
        routes: {
          '/auth': (_) => const AuthPage(),
          '/admin-settings': (_) => const AdminSettingsPage(),
          '/admin-pages': (_) => const AdminPagesButtonsPage(),
          '/admin-user-current': (context) {
            final settingsProvider = Provider.of<UserSettingsProvider>(
              context,
              listen: false,
            );
            final idToken = settingsProvider.idToken ?? '';
            final aacUserId = settingsProvider.userId ?? '';
            return UserCurrentAdminPage(idToken: idToken, aacUserId: aacUserId);
          },
          '/admin-user-info': (context) {
            final settingsProvider = Provider.of<UserSettingsProvider>(
              context,
              listen: false,
            );
            final idToken = settingsProvider.idToken ?? '';
            final aacUserId = settingsProvider.userId ?? '';
            return UserInfoAdminPage(idToken: idToken, aacUserId: aacUserId);
          },
          '/admin-user-diary': (context) {
            final settingsProvider = Provider.of<UserSettingsProvider>(
              context,
              listen: false,
            );
            final idToken = settingsProvider.idToken ?? '';
            final aacUserId = settingsProvider.userId ?? '';
            return UserDiaryAdminPage(idToken: idToken, aacUserId: aacUserId);
          },
          '/admin-audio-devices': (_) => const AudioDeviceAdminPage(),
          '/admin-tap-interface': (context) {
            final settingsProvider = Provider.of<UserSettingsProvider>(
              context,
              listen: false,
            );
            final idToken = settingsProvider.idToken ?? '';
            final aacUserId = settingsProvider.userId ?? '';
            return TapInterfaceAdminPage(
              idToken: idToken,
              aacUserId: aacUserId,
            );
          },
        },
        navigatorObservers: [routeObserver],
      ),
    );
  }
}

class GridPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  final String displayName;
  GridPage({
    super.key,
    required this.idToken,
    required this.aacUserId,
    required this.displayName,
  }) {
    print('🔵 GridPage - Constructor called with aacUserId: $aacUserId');
    print(
      '🔵 GridPage - CRITICAL DEBUG: GridPage initialized with profile ID: $aacUserId',
    );
  }

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage>
    with RouteAware, WidgetsBindingObserver {
  // --- Prevent scanning until announcement and grid update are complete ---
  bool _suppressScanning = false;
  // Orientation lock code removed: always landscape left via platform config
  // --- Color variables for user settings (defaults, but will use provider if available) ---
  static const Color kDefaultDarkColor = Color(0xFF002244); // Default dark blue
  static const Color kDefaultLightColor = Color(0xFFFB4F14); // Default orange
  // --- Audio session initialization tracking ---
  static bool _audioSessionInitialized = false;

  // Microphone permission is now handled automatically - no UI needed

  // --- Settings provider reference for proper cleanup ---
  UserSettingsProvider? _settingsProvider;

  // --- LLM DEBUGGING ---
  // Debug: Track every LLM call and every grid update for LLM
  void debugLogLLM({
    required String stage,
    String? prompt,
    dynamic response,
    List<Map<String, dynamic>>? gridButtons,
  }) {
    debugPrint('==== LLM DEBUG [$stage] ====');
    if (prompt != null) debugPrint('Prompt: $prompt');
    if (response != null) debugPrint('LLM Response: $response');
    if (gridButtons != null)
      debugPrint('Grid Buttons: ${gridButtons.map((b) => b['text']).toList()}');
    debugPrint('===========================');
  }

  /// Process {RANDOM:...} pattern in speech phrase and return a random selection
  /// Example: "{RANDOM:hi|hello|hey}" returns one of "hi", "hello", or "hey"
  String _processRandomPhrase(String? speechPhrase) {
    if (speechPhrase == null || speechPhrase.isEmpty) return '';

    // Check for {RANDOM:...} pattern
    final randomPattern = RegExp(r'\{RANDOM:([^}]+)\}');
    final match = randomPattern.firstMatch(speechPhrase);

    if (match != null) {
      final optionsString = match.group(1);
      if (optionsString != null && optionsString.isNotEmpty) {
        // Split by pipe character and trim whitespace
        final options = optionsString
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (options.isNotEmpty) {
          // Select a random option
          final random = math.Random();
          final selectedOption = options[random.nextInt(options.length)];
          debugPrint(
            '_processRandomPhrase: Selected "$selectedOption" from ${options.length} options',
          );
          return selectedOption;
        }
      }
    }

    // No {RANDOM:...} pattern found, return original phrase
    return speechPhrase;
  }

  // --- Microphone permission helper ---
  Future<bool> _requestMicrophonePermission() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        debugPrint(
          '_requestMicrophonePermission: Starting microphone permission request...',
        );
        debugPrint(
          '_requestMicrophonePermission: Platform - iOS: ${Platform.isIOS}, Android: ${Platform.isAndroid}',
        );

        // First check current permission status
        final permission = Permission.microphone;
        final initialStatus = await permission.status;

        debugPrint(
          '_requestMicrophonePermission: Initial status: $initialStatus',
        );
        debugPrint(
          '_requestMicrophonePermission: Initial details - isGranted: ${initialStatus.isGranted}, isDenied: ${initialStatus.isDenied}, isRestricted: ${initialStatus.isRestricted}, isPermanentlyDenied: ${initialStatus.isPermanentlyDenied}',
        );

        if (initialStatus.isGranted) {
          debugPrint(
            '_requestMicrophonePermission: Permission already granted',
          );
          return true;
        }

        // For iOS, we'll let the WakeWordService handle the actual microphone access
        // which will trigger the permission dialog when it tries to initialize speech recognition
        debugPrint(
          '_requestMicrophonePermission: Letting WakeWordService handle permission dialog during initialization',
        );

        // Return true if permission is already granted, false if not yet determined or denied
        return initialStatus.isGranted;
      } catch (e) {
        debugPrint(
          '_requestMicrophonePermission: ❌ ERROR requesting microphone permission: $e',
        );
        await flutterTts.speak(
          'Error requesting microphone permission. Please try again.',
        );
        return false;
      }
    }

    debugPrint(
      '_requestMicrophonePermission: Web platform - assuming permission handled by browser',
    );
    return true; // On web, assume permission is handled by browser
  }

  /// Initialize WakeWordService after permission is granted
  Future<void> _initializeWakeWordServiceWithPermission() async {
    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );

      _wakeWordInterjection =
          (settingsProvider.settings?.wakeWordInterjection ?? 'hey')
              .trim()
              .toLowerCase();
      _wakeWordName = (settingsProvider.settings?.wakeWordName ?? 'bravo')
          .trim()
          .toLowerCase();
      _wakeWordVariants = [
        '${_wakeWordInterjection} ${_wakeWordName}',
        '${_wakeWordInterjection}, ${_wakeWordName}',
        '${_wakeWordInterjection},${_wakeWordName}',
      ];

      // Configure group wake word from settings (defaults to 'hey friends' if not set)
      final groupWakeWord =
          (settingsProvider.settings?.groupWakeWord ?? 'hey friends')
              .trim()
              .toLowerCase();
      WakeWordService.setGroupWakeWord(
        groupWakeWord.isEmpty ? 'hey friends' : groupWakeWord,
      );

      debugPrint(
        '🎤 Wake word variants configured: \'${_wakeWordVariants.join("' | ")}\'',
      );
      debugPrint('🎤 Group wake word: \'$groupWakeWord\'');

      _wakeWordService = WakeWordService(wakeWords: _wakeWordVariants);

      // Setup wake word callbacks
      _setupWakeWordCallbacks();

      // Set microphone as enabled since we have permission
      setState(() {
        _microphoneListening = false;
      });

      debugPrint('🎤 Starting wake word service after permission grant.');
      _wakeWordService?.resumeWakeWordAutoRestart();
      _wakeWordService?.startWakeWordListening();

      // Add extra status update after initialization
      debugPrint(
        '🎤 Wake word service initialization complete. Testing microphone...',
      );
    } catch (e) {
      debugPrint('❌ Error initializing WakeWordService: $e');
    }
  }

  /// Re-check microphone permission and initialize wake word service if granted
  Future<void> _recheckMicrophonePermissionAndInitialize() async {
    if (kIsWeb || (!Platform.isIOS && !Platform.isAndroid)) {
      return; // Skip on web and unsupported platforms
    }

    try {
      final permission = Permission.microphone;
      final currentStatus = await permission.status;

      debugPrint('🔊 Re-checking microphone permission: $currentStatus');

      if (currentStatus.isGranted && !_microphonePermissionGranted) {
        debugPrint(
          '🔊 ✅ Microphone permission was granted! Initializing wake word service...',
        );

        setState(() {
          _microphonePermissionGranted = true;
        });

        // Initialize WakeWordService now that we have permission
        await _initializeWakeWordServiceWithPermission();

        // Announce that voice commands are ready
        await flutterTts.speak(
          'Voice commands are now enabled. Say "Hey Bravo" to ask questions.',
        );
      } else if (!currentStatus.isGranted) {
        debugPrint(
          '🔊 ❌ Microphone permission still not granted: $currentStatus',
        );
      }
    } catch (e) {
      debugPrint('🔊 ❌ Error re-checking microphone permission: $e');
    }
  }

  /// Setup wake word service callbacks
  void _setupWakeWordCallbacks() {
    if (_wakeWordService == null) return;

    _initializeWakeWordCallbacks();

    // Don't start listening here - let the main initialization method handle it
    debugPrint('Wake word service callbacks initialized successfully');
  }

  // Initialize wake word service callbacks - separate method for reuse
  void _initializeWakeWordCallbacks() {
    if (_wakeWordService == null) return;

    _wakeWordService!.onWakeWord = (transcript) async {
      final callbackStart = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[TIMER] CALLBACK START: onWakeWord at $callbackStart');

      debugPrint('Wake word detected in transcript: $transcript');

      // Android notification sounds suppressed globally

      // CRITICAL: Check if widget is still mounted before setState
      if (!mounted) {
        debugPrint(
          '[WakeWord] onWakeWord: Widget not mounted, skipping setState',
        );
        return;
      }

      setState(() {
        _showBottomStatusText = true;
        statusMessage = 'Wake word heard! Preparing to listen...';
        _listeningForQuestion = true;
        _microphoneListening = true;
      });

      _stopAuditoryScanning();
      debugPrint('Auditory scanning stopped.');

      // SIMPLIFIED: Quick stop like POC - no complex delays
      debugPrint('[WakeWord] Quick stop like POC...');
      _wakeWordService?.pauseWakeWordAutoRestart();

      // Remove settings change listener to prevent scanning restart
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      settingsProvider.removeListener(_maybeStartScanning);

      // Sequence the listening prompt ahead of question recognition so the app
      // does not transcribe its own "I am listening" announcement.
      debugPrint(
        '[TIMER] GridPage: Before announceViaBackend at ${DateTime.now().millisecondsSinceEpoch}',
      );

      // Set up state for announcement
      setState(() {
        statusMessage = 'Playing announcement...';
      });
      _inQuestionMode = true;
      previousPageName = currentPageName;

      try {
        debugPrint(
          '[WakeWord] Sequenced announcement + question setup...',
        );

        // SIMPLIFIED FAST APPROACH: Use backend but with shorter message
        debugPrint(
          '[WakeWord] Playing short announcement for faster response...',
        );
        const platform = MethodChannel('audio_routing');

        try {
          await platform.invokeMethod(
            'forceSpeaker',
          ); // Ensure speaker routing first
          debugPrint('[WakeWord] forceSpeaker called successfully');
        } catch (e) {
          debugPrint('[WakeWord] Error calling forceSpeaker: $e');
        }

        debugPrint(
          '[WakeWord] About to call FAST announcement (skipping complex audio routing)...',
        );
        final fastAnnounceStart = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[TIMER] Fast announce START at $fastAnnounceStart');

        // Play the listening cue to completion before enabling question capture.
        final announcementFuture = _announceSimpleTTS("I'm listening");

        final fastAnnounceEnd = DateTime.now().millisecondsSinceEpoch;
        debugPrint(
          '[TIMER] Fast announce dispatched at $fastAnnounceEnd (delta: ${fastAnnounceEnd - fastAnnounceStart}ms)',
        );

        // Setup audio session concurrently (simplified)
        Future<void> audioSetupFuture = Future.delayed(Duration.zero);
        if (!kIsWeb && Platform.isIOS) {
          audioSetupFuture = () async {
            try {
              final audioSetupStart = DateTime.now().millisecondsSinceEpoch;
              debugPrint('[TIMER] Audio setup START at $audioSetupStart');

              debugPrint(
                '[WakeWord] Setting up optimal audio session for question listening...',
              );
              await platform.invokeMethod('setupOptimalAudioSession');

              final audioSetupEnd = DateTime.now().millisecondsSinceEpoch;
              debugPrint(
                '[TIMER] Audio setup END at $audioSetupEnd (delta: ${audioSetupEnd - audioSetupStart}ms)',
              );
              debugPrint(
                '[WakeWord] Audio session optimized - Bluetooth microphone should be available',
              );
            } catch (e) {
              debugPrint(
                '[WakeWord] Failed to setup optimal audio session: $e',
              );
            }
          }();
        }

        // Keep iOS audio-session setup short so it does not block the prompt.
        await audioSetupFuture.timeout(
          const Duration(milliseconds: 350),
          onTimeout: () {
            debugPrint(
              '[WakeWord] Audio setup timed out quickly, continuing to listening',
            );
          },
        );

        await announcementFuture;
        await Future.delayed(const Duration(milliseconds: 150));

        debugPrint(
          '[WakeWord] Listening prompt and audio setup completed',
        );
        debugPrint(
          '[TIMER] GridPage: After fast announcement at ${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          setState(() {
            statusMessage = 'Ready to listen...';
          });
        }

        // Only start question listening after the prompt has fully finished.
        debugPrint(
          '[TIMER] GridPage: Before startQuestionListening at ${DateTime.now().millisecondsSinceEpoch}',
        );
        debugPrint(
          '[WakeWord] Starting question listening immediately (POC approach)...',
        );

        final questionListenStart = DateTime.now().millisecondsSinceEpoch;
        debugPrint(
          '[TIMER] Question listening call START at $questionListenStart',
        );

        await _wakeWordService!.startQuestionListening();

        final questionListenEnd = DateTime.now().millisecondsSinceEpoch;
        debugPrint(
          '[TIMER] Question listening call END at $questionListenEnd (delta: ${questionListenEnd - questionListenStart}ms)',
        );

        debugPrint('[WakeWord] Question listening started successfully');
        debugPrint(
          '[TIMER] GridPage: After startQuestionListening at ${DateTime.now().millisecondsSinceEpoch}',
        );

        // Android notification sounds managed globally
      } catch (e) {
        debugPrint('[WakeWord] Error with concurrent setup: $e');
        _forceRestartWakeWordService();
        return;
      }

      // Set up timeout protection for stuck listening states (reduced to 10 seconds)
      Timer(const Duration(seconds: 10), () {
        if (_inQuestionMode && _listeningForQuestion) {
          debugPrint(
            '[WakeWord] TIMEOUT: Question listening stuck after 10 seconds, forcing reset...',
          );

          // Restore Android notification sounds on timeout
          if (!kIsWeb && Platform.isAndroid) {
            try {
              const platform = MethodChannel('audio_routing');
              platform.invokeMethod('restoreNotificationSounds');
              debugPrint(
                '[WakeWord] TIMEOUT: Android notification sounds restored',
              );
            } catch (e) {
              debugPrint(
                '[WakeWord] TIMEOUT: Failed to restore notification sounds: $e',
              );
            }
          }

          if (!mounted) {
            debugPrint(
              '[WakeWord] TIMEOUT: Widget not mounted, skipping setState',
            );
            return;
          }
          setState(() {
            _listeningForQuestion = false;
            _microphoneListening = false;
            statusMessage =
                'Listening timed out. Say "Hey Brady" to try again.';
          });
          _forceRestartWakeWordService();
        }
      });

      // REMOVED: The "Still listening..." progress indicator was causing confusion
      // Question processing timeout is handled by the WakeWordService directly

      final callbackEnd = DateTime.now().millisecondsSinceEpoch;
      debugPrint(
        '[TIMER] CALLBACK END: onWakeWord at $callbackEnd (total delta: ${callbackEnd - callbackStart}ms)',
      );
    };

    _wakeWordService!.onQuestion = (question) async {
      debugPrint('Question detected: $question');

      // CRITICAL: Check if widget is still mounted before setState
      if (!mounted) {
        debugPrint(
          '[WakeWord] onQuestion: Widget not mounted, skipping setState',
        );
        return;
      }

      // *** CAPTURE PAUSED STATE BEFORE PROCESSING QUESTION ***
      final wasScanningPaused = _isScanningPaused && _waitingForUserInput;
      debugPrint('onQuestion: Captured paused state: $wasScanningPaused');

      setState(() {
        _questionText = question;
        questionDisplay = question;
        // Add question to speech history immediately (answer will update this row)
        speechHistory =
            'Q: $question${speechHistory.isNotEmpty ? '\n' : ''}$speechHistory';
        _listeningForQuestion = false;
        _isProcessingLLM = true;
        _showBottomStatusText = true;
        statusMessage = 'Okay, I heard $question. Give me a moment to respond.';
        _microphoneListening = false;
      });

      await _announceWithTimeout(
        'Okay, I heard $question. Give me a moment to respond.',
        routing: 'system',
        speechRate: 140,
      );

      await Future.delayed(const Duration(milliseconds: 300));
      _inQuestionMode = false;

      await _getLLMResponse(question, wasInPausedState: wasScanningPaused);
    };

    // Enhanced restart logic wrapper
    _wakeWordService!.shouldAllowWakeWordRestart = () {
      final shouldAllow =
          !_inQuestionMode && !_isProcessingLLM && !_isAnnouncementPlaying;
      debugPrint(
        '[WakeWord] shouldAllowWakeWordRestart called: $_inQuestionMode (question mode), $_isProcessingLLM (processing LLM), $_isAnnouncementPlaying (announcement) => $shouldAllow',
      );
      return shouldAllow;
    };

    // Wire up announcement callback for robust error handling with timeout handling
    _wakeWordService!.onAnnounce = (msg) async {
      debugPrint('🚨 Main.dart - onAnnounce callback FIRED with message: $msg');

      // Special handling for timeout announcements
      if (msg.contains("I didn't hear anything") || msg.contains("Try again")) {
        debugPrint(
          '🟢 Main.dart - Detected timeout announcement, PAUSING wake word service first',
        );

        // CRITICAL: Reset question mode flag since timeout means question session is over
        _inQuestionMode = false;

        // CRITICAL: Pause wake word service BEFORE announcement to prevent interference
        _wakeWordService?.pauseWakeWordAutoRestart();
        await _wakeWordService?.stopAllRecognizers();

        // Stop any current scanning that might have been started prematurely
        if (isScanning) {
          _stopAuditoryScanning();
        }

        // Announce the message and wait for completion
        debugPrint(
          '🟢 Main.dart - Playing timeout announcement with wake word service stopped',
        );
        await announceViaBackend(msg, routing: 'system');
        debugPrint(
          '🟢 Main.dart - Timeout announcement completed successfully',
        );

        // Add delay to allow audio routing to reset before starting scanning (matching working button pattern)
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('🟢 Main.dart - Audio routing reset delay completed');

        // Use WidgetsBinding to ensure proper sequencing (matching working button pattern)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint(
            '🟢 Main.dart - Starting scanning and wake word service after timeout announcement',
          );
          if (gridButtons.isNotEmpty) {
            _maybeStartScanning();
          }
          // CRITICAL FIX: Also restart wake word service like working button announcements do
          _forceRestartWakeWordService();
        });
      } else {
        // Normal announcements - just play them
        await announceViaBackend(msg);
      }
    };

    // Keep callback wired for compatibility with WakeWordService
    _wakeWordService!.onQuestionHighlight = (highlight) {
      // CRITICAL: Check if widget is still mounted before setState
      if (!mounted) {
        debugPrint(
          '[WakeWord] onQuestionHighlight: Widget not mounted, skipping setState',
        );
        return;
      }
      setState(() {});
    };

    // Add status bar update callback for real-time speech feedback
    _wakeWordService!.onStatusBarUpdate = (heardText) {
      // CRITICAL: Check if widget is still mounted before setState
      if (!mounted) {
        debugPrint(
          '[WakeWord] onStatusBarUpdate: Widget not mounted, skipping setState for: "$heardText"',
        );
        return;
      }

      // Add extra debugging for speech detection
      debugPrint(
        '[WakeWord] onStatusBarUpdate called: heardText="$heardText", microphoneListening=$_microphoneListening, listeningForQuestion=$_listeningForQuestion',
      );

      setState(() {
        // IMPORTANT: Do not display wake-word phase transcription.
        // We only show transcription after wake word is heard, during question listening,
        // via onQuestionStatusUpdate below.
        if (_listeningForQuestion) {
          debugPrint(
            '[WakeWord] onStatusBarUpdate ignored while question listener is active: "$heardText"',
          );
        }
      });
    };

    // Add separate status bar update callback for question processing
    _wakeWordService!.onQuestionStatusUpdate = (questionText) {
      // CRITICAL: Check if widget is still mounted before setState
      if (!mounted) {
        debugPrint(
          '[WakeWord] onQuestionStatusUpdate: Widget not mounted, skipping setState',
        );
        return;
      }

      if (!_inQuestionMode || !_listeningForQuestion || !_microphoneListening) {
        debugPrint(
          '[WakeWord] onQuestionStatusUpdate ignored (inactive question mode): inQuestionMode=$_inQuestionMode, listeningForQuestion=$_listeningForQuestion, microphoneListening=$_microphoneListening, text="$questionText"',
        );
        return;
      }

      debugPrint(
        '[WakeWord] onQuestionStatusUpdate: questionText="$questionText"',
      );

      // During question processing, update status differently (no auto-reset timer)
      if (mounted) {
        setState(() {
          _showBottomStatusText = true;
          statusMessage = 'Hearing: "$questionText"';
        });
      }
    };

    // Add callback for first speech detection to reset audio routing
    _wakeWordService!.onFirstSpeechDetected = () async {
      debugPrint(
        '[WakeWord] First speech detected - SKIPPING audio routing reset to maintain transcription accuracy',
      );
      // ACCURACY FIX: Do NOT reset audio routing during question listening as it disrupts speech recognition
      // The audio routing will be handled after the question is fully processed in _getLLMResponse
      debugPrint(
        '[WakeWord] Audio routing will be reset after question processing completes',
      );
    };
  }

  // --- STATUS MESSAGE AUTO-RESET HELPER METHOD ---
  void _updateStatusMessageWithAutoReset(
    String message, {
    Duration resetAfter = const Duration(seconds: 5),
  }) {
    // Cancel any existing timer
    _statusMessageTimer?.cancel();

    // Update the status message with additional debug info for Android
    debugPrint(
      '[StatusMessage] Updating status: "$message" (resetAfter: ${resetAfter.inSeconds}s)',
    );

    if (mounted) {
      setState(() {
        _showBottomStatusText = true;
        statusMessage = message;
      });
      debugPrint('[StatusMessage] Status message set successfully');
    } else {
      debugPrint(
        '[StatusMessage] WARNING: Widget not mounted, cannot update status',
      );
    }

    // Set up auto-reset timer for wake word listening messages to prevent transcription overload
    if (message.contains('Listening for wake word:')) {
      _statusMessageTimer = Timer(resetAfter, () {
        if (mounted && _microphoneListening && !_inQuestionMode) {
          setState(() {
            // Show a cleaner default status instead of clearing completely
            final wakeWordExample = _wakeWordVariants.isNotEmpty
                ? _wakeWordVariants.first
                : 'Hey Bravo';
            statusMessage =
                'Wake word listening active - say "$wakeWordExample"';
          });
          debugPrint(
            '[WakeWord] Auto-reset: Cleared transcription overload, showing default wake word status',
          );
        } else {
          debugPrint(
            '[WakeWord] Auto-reset skipped: mounted=$mounted, microphoneListening=$_microphoneListening, inQuestionMode=$_inQuestionMode',
          );
        }
      });
    }
  }

  // Add a comprehensive wake word service restart method
  Future<void> _forceRestartWakeWordService() async {
    debugPrint('[WakeWord] _forceRestartWakeWordService called');

    // Check if wake word should be active before attempting restart
    if (!WakeWordService.wakeWordShouldBeActive) {
      debugPrint(
        '[WakeWord] _forceRestartWakeWordService: wakeWordShouldBeActive=false, skipping restart',
      );
      return;
    }

    if (_wakeWordService == null) {
      debugPrint(
        '[WakeWord] _forceRestartWakeWordService: service is null, skipping',
      );
      return;
    }

    try {
      // AUDIO SESSION FIX: Wait longer to avoid conflicts with TTS audio routing
      debugPrint(
        '[WakeWord] _forceRestartWakeWordService: waiting for audio session to stabilize',
      );
      await Future.delayed(const Duration(milliseconds: 1500));

      // Always resume auto-restart first
      _wakeWordService!.resumeWakeWordAutoRestart();
      debugPrint(
        '[WakeWord] _forceRestartWakeWordService: resumed auto-restart',
      );

      // Wait a moment for any pending operations
      await Future.delayed(const Duration(milliseconds: 500));

      // Don't check isListening - always force a restart for timeout recovery
      debugPrint(
        '[WakeWord] _forceRestartWakeWordService: forcing restart regardless of current state',
      );

      // Start listening - the resumeWakeWordAutoRestart() now handles this automatically
      await _wakeWordService!.startWakeWordListening();
      debugPrint(
        '[WakeWord] _forceRestartWakeWordService: started wake word listening',
      );

      // Verify it started
      await Future.delayed(const Duration(milliseconds: 500));
      if (_wakeWordService!.isListening) {
        debugPrint(
          '[WakeWord] _forceRestartWakeWordService: SUCCESS - service is now listening',
        );
        // Update UI to show microphone is active
        if (mounted) {
          setState(() {
            _microphoneListening =
                false; // Green icon - listening for wake word
            // Use the actual configured wake word instead of hardcoded "Hey Bravo"
            final wakeWordExample = _wakeWordVariants.isNotEmpty
                ? _wakeWordVariants.first
                : 'Hey Bravo';
            statusMessage =
                'Wake word listening active - say "$wakeWordExample"';
          });
        }
      } else {
        debugPrint(
          '[WakeWord] _forceRestartWakeWordService: WARNING - service may not be listening properly',
        );
      }
    } catch (e) {
      debugPrint('[WakeWord] _forceRestartWakeWordService: ERROR - $e');
    }
  }

  // --- Volume control helpers ---
  Future<int> _getEffectivePersonalVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('personalVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('personalVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        '🔊 VOLUME: Using LOCAL personal volume override: $overrideValue/10',
      );
      return overrideValue;
    }
    final settingsValue = _settingsProvider?.settings?.personalVolume ?? 10;
    debugPrint('🔊 VOLUME: Using SETTINGS personal volume: $settingsValue/10');
    return settingsValue;
  }

  Future<int> _getEffectiveSystemVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOverride = prefs.getBool('systemVolumeOverride') ?? false;
    final overrideValue = prefs.getInt('systemVolumeOverrideValue');
    if (hasOverride && overrideValue != null) {
      debugPrint(
        '🔊 VOLUME: Using LOCAL system volume override: $overrideValue/10',
      );
      return overrideValue;
    }
    final settingsValue = _settingsProvider?.settings?.systemVolume ?? 10;
    debugPrint('🔊 VOLUME: Using SETTINGS system volume: $settingsValue/10');
    return settingsValue;
  }

  Future<void> _setApplicationVolume({
    UserSettings? settings,
    bool isSystemSpeaker = false,
  }) async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        final platform = MethodChannel('audio_routing');

        // Determine which volume setting to use
        // If isSystemSpeaker is true, use systemVolume (for speech output)
        // Otherwise use personalVolume (for cues/scanning)
        // Fallback to applicationVolume for backward compatibility if new settings are missing
        int targetVolume;

        if (isSystemSpeaker) {
          targetVolume =
              settings?.systemVolume ?? settings?.applicationVolume ?? 10;
          debugPrint(
            '🔊 VOLUME: Using SYSTEM volume setting: $targetVolume/10',
          );
        } else {
          targetVolume =
              settings?.personalVolume ?? settings?.applicationVolume ?? 10;
          debugPrint(
            '🔊 VOLUME: Using PERSONAL volume setting: $targetVolume/10',
          );
        }

        debugPrint('🔊 VOLUME: Setting volume to level: $targetVolume/10');

        if (Platform.isAndroid) {
          await platform.invokeMethod('setApplicationVolume', {
            'applicationVolume': targetVolume,
            'isPersonal':
                !isSystemSpeaker, // true for personal volume, false for system volume
          });
        } else if (Platform.isIOS) {
          // On iOS, we can't control the hardware volume programmatically.
          // However, we CAN re-establish the optimal audio session to ensure
          // Bluetooth routing is preserved after app resume/backgrounding.
          // The actual volume control for the audio player is done via
          // player.setVolume() and flutterTts.setVolume() at playback time.
          debugPrint(
            '🔊 VOLUME: iOS - Re-establishing optimal audio session for BT routing. '
            'Volume will be applied via player.setVolume($targetVolume/10) at playback time.',
          );
          try {
            await platform.invokeMethod('setupOptimalAudioSession');
          } catch (e) {
            debugPrint(
              '🔊 VOLUME: iOS - setupOptimalAudioSession failed on resume: $e',
            );
          }
        }

        debugPrint(
          '🔊 VOLUME: ✅ Volume configuration completed for level: $targetVolume/10',
        );

        // Re-suppress notifications after volume change
        if (!kIsWeb && Platform.isAndroid) {
          try {
            await platform.invokeMethod('suppressNotificationSounds');
            debugPrint(
              '🔊 VOLUME: Re-suppressed notifications after volume change',
            );
          } catch (e) {
            debugPrint(
              '🔊 VOLUME: Failed to re-suppress notifications after volume change: $e',
            );
          }
        }
      } catch (e) {
        debugPrint('🔊 VOLUME: ⚠️  Failed to set volume: $e');
      }
    }
  }

  // --- Audio session initialization helper ---
  Future<void> _initializeAudioSession() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        debugPrint(
          '🔊 VOLUME: _initializeAudioSession: Starting audio session initialization...',
        );
        final platform = MethodChannel('audio_routing');
        final player = AudioPlayer();

        // Get current saved volume settings (use local overrides when present)
        final personalVolume = await _getEffectivePersonalVolume();
        final systemVolume = await _getEffectiveSystemVolume();

        debugPrint(
          '🔊 VOLUME: _initializeAudioSession: Applying saved volume settings (personal: $personalVolume/10, system: $systemVolume/10)...',
        );

        if (Platform.isAndroid) {
          // For Android, initialize audio with the saved volumes
          // This ensures storedPersonalVolume and storedSystemVolume are set BEFORE forceSpeaker() is called
          await platform.invokeMethod('initializeAudioWithVolume', {
            'personalVolume': personalVolume,
            'systemVolume': systemVolume,
          });
          debugPrint(
            '🔊 VOLUME: Android audio initialized with saved volume settings',
          );
        } else if (Platform.isIOS) {
          // Set up optimal audio session with Bluetooth A2DP support
          // This does NOT force speaker — it configures the session to use the best available route
          // (Bluetooth speaker if connected, built-in speaker otherwise)
          try {
            debugPrint(
              '_initializeAudioSession: Setting up optimal audio session with BT A2DP support...',
            );
            await platform.invokeMethod('setupOptimalAudioSession');
            debugPrint(
              '_initializeAudioSession: Optimal audio session setup completed',
            );
          } catch (e) {
            debugPrint(
              '_initializeAudioSession: Failed to setup optimal audio session: $e',
            );
          }

          // Play silence to warm up the audio pipeline WITHOUT forcing to built-in speaker
          // This keeps audio routing on Bluetooth if connected
          debugPrint(
            '_initializeAudioSession: Playing silence.mp3 to warm up audio session (keeping current routing)...',
          );

          // Apply the admin personal volume setting for warm-up so the audio pipeline
          // initializes at the correct software volume level.
          final personalVolumeLevel = personalVolume / 10.0;
          await player.setVolume(personalVolumeLevel);
          await player.setAsset('assets/silence.mp3');

          // Wait for playback to complete
          final completer = Completer<void>();
          final sub = player.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed) {
              if (!completer.isCompleted) completer.complete();
            }
          });
          await player.play();
          await completer.future;
          await sub.cancel();

          // Do NOT call resetToDefault here — session should stay active with current routing
          debugPrint(
            '_initializeAudioSession: iOS audio session initialized successfully (BT-aware)',
          );
        } else {
          // For Android, match EXACTLY the same audio priming sequence as announceViaBackend
          // This ensures the first announceViaBackend call won't be choppy
          debugPrint(
            '_initializeAudioSession: Android - matching announceViaBackend priming sequence...',
          );

          try {
            // Step 1: Force to built-in speakers (same as announceViaBackend)
            await platform.invokeMethod('forceSpeaker');
            debugPrint(
              '_initializeAudioSession: Android speaker forcing completed',
            );

            // Step 2: Critical delay for audio routing to fully establish (same as announceViaBackend)
            debugPrint(
              '_initializeAudioSession: Waiting 300ms for complete routing setup...',
            );
            await Future.delayed(const Duration(milliseconds: 300));
            debugPrint('_initializeAudioSession: Audio routing setup complete');
          } catch (e) {
            debugPrint(
              '_initializeAudioSession: Android speaker forcing failed: $e',
            );
          }

          // SKIP silence.mp3 priming - it fails after forceSpeaker due to AudioTrack resource limits
          // The actual announcement audio will serve as the first audio played
          debugPrint(
            '_initializeAudioSession: Skipping silence.mp3 priming (causes AudioTrack errors after forceSpeaker)',
          );
          debugPrint(
            '_initializeAudioSession: Android audio session initialized - ready for announcement',
          );
        }
      } catch (e) {
        debugPrint(
          '_initializeAudioSession: Error initializing audio session: $e',
        );
      }
    }
  }

  // --- Audio chirp for listening indicator ---
  Future<void> _playAudioChirp() async {
    try {
      // SUPPRESS CHIRPS: Only play chirp if no announcement is currently playing
      if (_isAnnouncementPlaying) {
        debugPrint(
          '_playAudioChirp: Suppressing chirp - announcement is playing',
        );
        return;
      }

      debugPrint(
        '_playAudioChirp: Playing audio chirp to indicate listening start...',
      );
      final player = AudioPlayer();

      // Simplified chirp - faster setup without complex routing
      await player.setAsset('assets/test.mp3');
      await player.play();

      // Don't wait for completion - let it play while proceeding
      debugPrint('_playAudioChirp: Audio chirp started successfully');

      // Clean up after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        player.dispose();
      });
    } catch (e) {
      debugPrint('_playAudioChirp: Error playing audio chirp: $e');
    }
  }

  // --- Helper function to parse malformed LLM JSON responses ---
  dynamic _parseLLMResponse(dynamic rawOptions) {
    debugPrint('🔍 _parseLLMResponse CALLED');
    debugPrint('🔍 Input type: ${rawOptions.runtimeType}');
    debugPrint('🔍 Input value: $rawOptions');

    // Handle case where backend returns array of JSON-encoded strings instead of objects
    if (rawOptions is Map && rawOptions['options'] is List) {
      debugPrint('🔍 Detected Map with "options" key containing List');
      final optionsList = rawOptions['options'] as List;
      debugPrint('🔍 Options list has ${optionsList.length} items');
      final parsedOptions = <dynamic>[];

      for (var i = 0; i < optionsList.length; i++) {
        final item = optionsList[i];
        debugPrint(
          '🔍 Processing item $i: type=${item.runtimeType}, value="$item"',
        );

        if (item is String) {
          // Try to parse string as JSON object
          try {
            // Skip malformed items like "[" or "]" or markdown artifacts
            final trimmed = item.trim();
            if (trimmed.isEmpty ||
                trimmed == '[' ||
                trimmed == ']' ||
                trimmed == ',' ||
                trimmed.startsWith('```') ||
                trimmed == 'json') {
              debugPrint('🔍 Skipping malformed/markdown item: "$trimmed"');
              continue;
            }

            // Remove trailing comma if present
            String cleanedItem = trimmed.endsWith(',')
                ? trimmed.substring(0, trimmed.length - 1)
                : trimmed;
            debugPrint('🔍 Cleaned item: "$cleanedItem"');

            // Try to parse as JSON
            if (cleanedItem.startsWith('{') && cleanedItem.endsWith('}')) {
              final parsed = json.decode(cleanedItem);
              debugPrint('🔍 ✅ Successfully parsed JSON object: $parsed');
              parsedOptions.add(parsed);
            } else {
              debugPrint('🔍 ⚠️ Item does not look like JSON object, skipping');
            }
          } catch (e) {
            debugPrint('🔍 ❌ Failed to parse option string: $item - Error: $e');
          }
        } else {
          // Already a proper object
          debugPrint('🔍 ✅ Item is already an object, adding as-is');
          parsedOptions.add(item);
        }
      }

      debugPrint(
        '🔍 RESULT: Parsed ${parsedOptions.length} options from Map->List format',
      );
      debugPrint('🔍 RESULT DATA: $parsedOptions');
      return parsedOptions;
    }

    // If it's already a list, still check if items are string-encoded
    if (rawOptions is List) {
      debugPrint('🔍 Detected direct List with ${rawOptions.length} items');
      final parsedOptions = <dynamic>[];

      for (var i = 0; i < rawOptions.length; i++) {
        final item = rawOptions[i];
        debugPrint(
          '🔍 Processing list item $i: type=${item.runtimeType}, value="$item"',
        );

        if (item is String) {
          try {
            final trimmed = item.trim();
            if (trimmed.isEmpty ||
                trimmed == '[' ||
                trimmed == ']' ||
                trimmed == ',' ||
                trimmed.startsWith('```') ||
                trimmed == 'json') {
              debugPrint('🔍 Skipping malformed/markdown item: "$trimmed"');
              continue;
            }

            String cleanedItem = trimmed.endsWith(',')
                ? trimmed.substring(0, trimmed.length - 1)
                : trimmed;
            debugPrint('🔍 Cleaned item: "$cleanedItem"');

            if (cleanedItem.startsWith('{') && cleanedItem.endsWith('}')) {
              final parsed = json.decode(cleanedItem);
              debugPrint('🔍 ✅ Successfully parsed JSON string: $parsed');
              parsedOptions.add(parsed);
            } else {
              // Not JSON, use as-is
              debugPrint('🔍 ⚠️ Not JSON, using as-is: "$item"');
              parsedOptions.add(item);
            }
          } catch (e) {
            // Failed to parse, use as-is
            debugPrint(
              '🔍 ❌ Failed to parse, using as-is: "$item" - Error: $e',
            );
            parsedOptions.add(item);
          }
        } else {
          debugPrint('🔍 ✅ Item is already an object, adding as-is');
          parsedOptions.add(item);
        }
      }

      debugPrint(
        '🔍 RESULT: Parsed ${parsedOptions.length} options from List format',
      );
      debugPrint('🔍 RESULT DATA: $parsedOptions');
      return parsedOptions;
    }

    debugPrint(
      '🔍 RESULT: Returning rawOptions unchanged (type: ${rawOptions.runtimeType})',
    );
    return rawOptions;
  }

  void _resetFollowUpConversation() {
    _followUpOriginalQuestion = null;
    _followUpSelectedResponses.clear();
  }

  void _initializeFollowUpConversation(String? questionText) {
    final normalizedQuestion = (questionText ?? '').trim();
    if (normalizedQuestion.isEmpty) {
      _resetFollowUpConversation();
      return;
    }
    _followUpOriginalQuestion = normalizedQuestion;
    _followUpSelectedResponses.clear();
  }

  void _addFollowUpSelection(String selectionText) {
    final normalizedSelection = selectionText.trim();
    if (normalizedSelection.isEmpty) return;
    _followUpSelectedResponses.add(normalizedSelection);
  }

  String _getConversationContextText() {
    final baseQuestion = (_followUpOriginalQuestion ?? '').trim().isNotEmpty
        ? _followUpOriginalQuestion!
        : questionDisplay;
    if (baseQuestion.trim().isEmpty) return '';
    final historyText = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses
              .asMap()
              .entries
              .map((entry) => '${entry.key + 1}. ${entry.value}')
              .join('\n')
        : 'None yet';
    return 'Original question: "$baseQuestion"\nSelected follow-ups so far:\n$historyText';
  }

  String _getComposePromptContext() {
    if (!_composeSession.active) return '';
    final compositionText = _composeSession.text.trim();
    if (compositionText.isEmpty) return '';
    return '\n\nCREATION CONTEXT:\n'
        'The user is actively creating a written document for someone who may not be physically present. '
        'Ignore current location, people present, room context, nearby people, and current activity. '
        'Prioritize options that continue or refine this creation in natural written language:\n'
        '"$compositionText"\n'
        'Keep continuity with this creation.';
  }

  String _sanitizeComposePrompt(String prompt) {
    if (!_composeSession.active) return prompt;
    var cleaned = prompt;
    final patterns = <RegExp>[
      RegExp(
        r"\bconsider the user's current location, people present, personal interests, and the time of year\b\.??",
        caseSensitive: false,
      ),
      RegExp(
        r'\bbased on my current location and interests\b\.??',
        caseSensitive: false,
      ),
      RegExp(
        r'\bprioritize options that are more relevant to the current location and people in the room\b\.??',
        caseSensitive: false,
      ),
      RegExp(
        r'\bphrase the option as if it is coming from the user and asking, suggesting or recommending the activity for those nearby\b\.??',
        caseSensitive: false,
      ),
      RegExp(
        r"\busing the 'people present' values from context\b\.??",
        caseSensitive: false,
      ),
      RegExp(r'\bpeople present\b', caseSensitive: false),
      RegExp(r'\bcurrent location\b', caseSensitive: false),
      RegExp(r'\bin the room\b', caseSensitive: false),
      RegExp(r'\bthose nearby\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _tokenizeForContext(String text) {
    if (text.trim().isEmpty) return [];
    const stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'but',
      'if',
      'then',
      'to',
      'of',
      'for',
      'in',
      'on',
      'at',
      'with',
      'from',
      'is',
      'are',
      'was',
      'were',
      'be',
      'been',
      'being',
      'it',
      'this',
      'that',
      'i',
      'you',
      'we',
      'they',
      'he',
      'she',
      'do',
      'does',
      'did',
      'want',
      'wants',
      'would',
      'could',
      'should',
      'can',
      'will',
      'today',
      'tonight',
      'afternoon',
    };
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.length > 1 && !stopWords.contains(token))
        .toList();
  }

  String _normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'["“”‘’]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _classifyCommunicationType(String text) {
    final normalized = text.toLowerCase().trim();
    if (RegExp(
      r'^(hello|hi|hey|goodbye|bye|good morning|good afternoon|good evening|howdy)\b',
    ).hasMatch(normalized)) {
      return 'greeting';
    }
    if (RegExp(r'\?$').hasMatch(normalized) ||
        RegExp(
          r'^(what|why|how|when|where|who|which|do|does|did|can|could|will|would|should|is|are|am|have|has|had)\b',
        ).hasMatch(normalized)) {
      return 'question';
    }
    if (RegExp(
      r"\b(want|need|can you|could you|will you|would you|let's|let me|i need|i want|please|can i|could i)\b",
    ).hasMatch(normalized)) {
      return 'request';
    }
    if (RegExp(
      r'^(yes|no|yeah|yep|nope|sure|definitely|absolutely|maybe|perhaps|probably)\b|\b(yes|no)$',
    ).hasMatch(normalized)) {
      return 'answer';
    }
    if (RegExp(
      r"\b(haha|lol|funny|joke|made me laugh|that's hilarious|isn't that funny)\b",
    ).hasMatch(normalized)) {
      return 'joke';
    }
    if (RegExp(
      r"\b(i am strong|i can do|i'm amazing|i'm great|i'm capable|i'm confident|proud of)\b",
    ).hasMatch(normalized)) {
      return 'affirmation';
    }
    return 'assertion';
  }

  Map<String, dynamic> _classifyFollowUpGuidance(String communicationType) {
    const guidance = {
      'greeting': {
        'description':
            'The user greeted someone. Follow-ups should respond appropriately.',
        'patterns': [
          'How are you doing?',
          'What have you been up to?',
          'Good to see you!',
          'I missed you!',
        ],
      },
      'assertion': {
        'description':
            'The user made a statement or opinion. Follow-ups should engage the partner at the same level.',
        'patterns': [
          'What do you think about that?',
          'Do you agree?',
          'Have you experienced that too?',
          'Would you like to do that with me?',
        ],
      },
      'question': {
        'description':
            'The user asked a question. Follow-ups should provide alternatives, clarifications, or related questions.',
        'patterns': [
          'Is it something fun?',
          'Can we find that out together?',
          "I'm curious about that too",
          'Should we ask someone?',
        ],
      },
      'request': {
        'description':
            'The user made a request. Follow-ups should expand the idea or get partner input.',
        'patterns': [
          'Do you want to go with me?',
          'When can we do that?',
          'What do you think about that?',
          'Can we start planning that?',
        ],
      },
      'answer': {
        'description':
            'The user gave an answer. Follow-ups should continue the conversation or explain the answer.',
        'patterns': [
          "Maybe we could try this instead",
          "Here's why I think that",
          'Would you do that?',
          'Can we talk about why?',
        ],
      },
      'joke': {
        'description':
            'The user shared humor. Follow-ups should engage with the joke or build on playfulness.',
        'patterns': [
          "Isn't that funny?",
          'Do you like jokes like that?',
          'Did that make you laugh?',
          'Tell me another funny one!',
        ],
      },
      'affirmation': {
        'description':
            'The user made a positive self-statement. Follow-ups should reinforce that positivity.',
        'patterns': [
          'Do you feel the same way?',
          "That's awesome!",
          'I believe in you',
          'Do you want to join me?',
        ],
      },
    };
    return guidance[communicationType] ?? guidance['assertion']!;
  }

  bool _isPartnerInterrogativePattern(String text) {
    if (text.trim().isEmpty) return false;
    final normalized = text.toLowerCase().trim();
    final latestResponse = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final latestWasUserAssertion = RegExp(
      r'^i\b',
      caseSensitive: false,
    ).hasMatch(latestResponse);
    if (latestWasUserAssertion) {
      if (RegExp(r'\btell me\b').hasMatch(normalized)) return true;
      if (RegExp(r"what('s| is) making you").hasMatch(normalized)) return true;
      if (RegExp(r'what makes you').hasMatch(normalized)) return true;
      if (RegExp(r'^(share more|describe|explain)').hasMatch(normalized))
        return true;
    }
    if (RegExp(
      r'^(why are you|why do you|how does (that|it|this) make you feel|how are you feel)',
    ).hasMatch(normalized))
      return true;
    if (RegExp(r'^what kind of .+ are you').hasMatch(normalized)) return true;
    if (RegExp(r'^can you tell me').hasMatch(normalized)) return true;
    return false;
  }

  int _scoreUserVoicePerspective(String optionText) {
    if (optionText.trim().isEmpty) return 0;
    final normalized = optionText.trim().toLowerCase();
    var score = 0;
    if (RegExp(
      r"^(i\b|i'm\b|i am\b|i want\b|i need\b|i feel\b|let's\b|can we\b|could we\b|tell me\b|show me\b)",
      caseSensitive: false,
    ).hasMatch(optionText))
      score += 3;
    if (RegExp(
      r'^(do you\b|have you\b|can you\b|would you\b|could you\b|what do you think\b|which do you\b|did you\b)',
      caseSensitive: false,
    ).hasMatch(optionText))
      score += 4;
    if (RegExp(r'\bwith me\b', caseSensitive: false).hasMatch(optionText))
      score += 2;
    if (RegExp(
      r'^(what should i do\b|which (rides|one|park|option) should i\b)',
      caseSensitive: false,
    ).hasMatch(optionText))
      score -= 3;
    final addressedPatterns = [
      RegExp(r'\bwhat\s+is\s+it\s+you\s+find\b'),
      RegExp(r'\bwhat\s+is\s+making\s+you\s+feel\b'),
      RegExp(r'\bwhat\s+makes\s+you\s+feel\b'),
      RegExp(r'\bwhy\s+did\s+you\s+choose\b'),
      RegExp(r'\bwhy\s+are\s+you\s+feeling\b'),
      RegExp(r'\bwhy\s+do\s+you\s+feel\b'),
      RegExp(r'\bhow\s+does\s+that\s+make\s+you\s+feel\b'),
      RegExp(r'\bhow\s+are\s+you\s+feeling\s+about\s+(that|this|your)\b'),
      RegExp(r'\byour\s+answer\b'),
      RegExp(r'\byou\s+selected\b'),
      RegExp(r'\byou\s+chose\b'),
    ];
    for (final pattern in addressedPatterns) {
      if (pattern.hasMatch(normalized)) score -= 6;
    }
    return score;
  }

  int _scoreOptionContextualFit(
    Map<String, dynamic> optionData,
    List<String> contextTerms,
    List<String> latestResponseTerms,
  ) {
    final optionText = (optionData['option'] ?? '').toString();
    final summaryText = (optionData['summary'] ?? '').toString();
    final keywords = optionData['keywords'];
    final keywordText = keywords is List ? keywords.join(' ') : '';
    final combinedText = '$optionText $summaryText $keywordText';
    final optionTerms = _tokenizeForContext(combinedText);
    final optionTermSet = optionTerms.toSet();
    var score = 0;
    for (final term in contextTerms) {
      if (optionTermSet.contains(term)) score += 4;
    }
    for (final term in latestResponseTerms) {
      if (optionTermSet.contains(term)) score += 6;
    }
    final wordCount = optionText
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    if (wordCount >= 2 && wordCount <= 10) score += 1;
    if (wordCount > 14) score -= 2;
    if (RegExp(
      r"^i\s+want\s+to\b|^let's\b|^how about\b",
      caseSensitive: false,
    ).hasMatch(optionText))
      score += 1;
    final partnerPatterns = [
      RegExp(r'^do you\b', caseSensitive: false),
      RegExp(r'^would you\b', caseSensitive: false),
      RegExp(r'^can you\b', caseSensitive: false),
      RegExp(r'^could you\b', caseSensitive: false),
      RegExp(r'^have you\b', caseSensitive: false),
      RegExp(r'^what do you think\b', caseSensitive: false),
      RegExp(r'^what do you feel\b', caseSensitive: false),
      RegExp(r'^are you\b', caseSensitive: false),
      RegExp(r'^should we\b', caseSensitive: false),
      RegExp(r'^do you want\b', caseSensitive: false),
      RegExp(r'^will you\b', caseSensitive: false),
      RegExp(r'^do you like\b', caseSensitive: false),
      RegExp(r"^what's your\b", caseSensitive: false),
      RegExp(r'^who wants\b', caseSensitive: false),
    ];
    if (partnerPatterns.any((pattern) => pattern.hasMatch(optionText)))
      score += 8;
    if (RegExp(r'[.!?]').allMatches(optionText).length > 1) score -= 2;
    return score;
  }

  List<Map<String, dynamic>> _prioritizeContextualOptions(
    List<Map<String, dynamic>> options,
    String contextText,
    int maxCount,
  ) {
    if (options.isEmpty) return [];
    final contextTerms = _tokenizeForContext(contextText);
    final latestResponse = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final latestResponseTerms = _tokenizeForContext(latestResponse);
    final scored = options.asMap().entries.map((entry) {
      return {
        'optionData': entry.value,
        'index': entry.key,
        'score': _scoreOptionContextualFit(
          entry.value,
          contextTerms,
          latestResponseTerms,
        ),
      };
    }).toList();
    scored.sort((a, b) {
      final scoreCmp = (b['score'] as int).compareTo(a['score'] as int);
      if (scoreCmp != 0) return scoreCmp;
      return (a['index'] as int).compareTo(b['index'] as int);
    });
    return scored
        .take(math.max(1, maxCount))
        .map((item) => item['optionData'] as Map<String, dynamic>)
        .toList();
  }

  List<Map<String, dynamic>> _filterOptionsForUserVoicePerspective(
    List<Map<String, dynamic>> options,
  ) {
    final latestSelectedResponse = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final latestLooksFirstPerson = RegExp(
      r"^\s*(i\b|i'm\b|i am\b|i feel\b|i want\b|i like\b|i love\b)",
      caseSensitive: false,
    ).hasMatch(latestSelectedResponse);
    final mirroredPatterns = [
      RegExp(r'^\s*what\s+is\s+making\s+you\s+feel\b', caseSensitive: false),
      RegExp(r'^\s*what\s+makes\s+you\s+feel\b', caseSensitive: false),
      RegExp(r'^\s*why\s+do\s+you\s+feel\b', caseSensitive: false),
      RegExp(
        r'^\s*how\s+does\s+that\s+make\s+you\s+feel\b',
        caseSensitive: false,
      ),
      RegExp(r'^\s*why\s+are\s+you\s+so\b', caseSensitive: false),
    ];
    return options.where((item) {
      final optionText = (item['option'] ?? '').toString().trim();
      if (optionText.isEmpty) return false;
      if (latestLooksFirstPerson &&
          mirroredPatterns.any((p) => p.hasMatch(optionText))) {
        return false;
      }
      return _scoreUserVoicePerspective(optionText) > -5;
    }).toList();
  }

  List<Map<String, dynamic>> _buildPartnerQuestionFallbacks(
    String latestSelectedResponse,
    int neededCount,
  ) {
    final communicationType = _classifyCommunicationType(
      latestSelectedResponse,
    );
    final templatesByType = {
      'assertion': [
        'What do you think about this?',
        'Do you agree with me?',
        'Have you felt this way too?',
        'Can we talk about this?',
        'What would you do in my place?',
      ],
      'affirmation': [
        'Do you feel the same way?',
        'Would you agree with that?',
        'What do you think?',
        'Should we do that together?',
        'Do you want to join me?',
      ],
      'request': [
        'Can you help me with this?',
        'Would you do this with me?',
        'Do you think this would work?',
        'Should we try this now?',
        'Can we do this together?',
      ],
      'answer': [
        'Does that make sense to you?',
        'What do you think about that?',
        'Do you want to know more?',
        'Should I explain more?',
        'Do you agree with that?',
      ],
      'joke': [
        'Do you think that is funny?',
        'Want to hear another one?',
        'Did that make you laugh?',
        'Do you have a joke too?',
        'Should I tell one more?',
      ],
      'greeting': [
        'How are you doing today?',
        'What are you up to?',
        'Can we chat for a bit?',
        'Are you having a good day?',
        'Do you want to talk?',
      ],
      'question': [
        'What do you think about that?',
        'Do you have an idea?',
        'Can we figure this out together?',
        'Would you choose the same?',
        'Should we decide together?',
      ],
    };
    final templates =
        templatesByType[communicationType] ?? templatesByType['assertion']!;
    return templates.take(math.max(0, neededCount)).map((text) {
      return {
        'option': text,
        'summary': text,
        'keywords': _tokenizeForContext(text).take(5).toList(),
      };
    }).toList();
  }

  bool _isQuestionLikeOption(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'\?\s*$').hasMatch(trimmed)) return true;
    return RegExp(
      r'^(do|does|did|are|is|can|could|would|will|have|has|should|what|which|when|where|why|how|who)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  List<Map<String, dynamic>> _prioritizePartnerEngagementQuestions(
    List<Map<String, dynamic>> options,
    int maxCount,
    int minQuestionCount,
  ) {
    if (options.isEmpty) return [];
    final questions = <Map<String, dynamic>>[];
    final nonQuestions = <Map<String, dynamic>>[];
    for (final item in options) {
      final text = (item['option'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      if (_isQuestionLikeOption(text)) {
        questions.add(item);
      } else {
        nonQuestions.add(item);
      }
    }
    final targetQuestions = math.min(
      math.max(1, minQuestionCount),
      math.max(1, maxCount),
    );
    final latestResponse = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final supplemental = questions.length < targetQuestions
        ? _buildPartnerQuestionFallbacks(
            latestResponse,
            targetQuestions - questions.length,
          )
        : <Map<String, dynamic>>[];
    final merged = <Map<String, dynamic>>[
      ...questions,
      ...supplemental,
      ...nonQuestions,
    ];
    final deduped = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in merged) {
      final text = (item['option'] ?? '').toString().trim();
      final normalized = _normalizeForComparison(text);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      deduped.add(item);
    }
    return deduped.take(math.max(1, maxCount)).toList();
  }

  List<Map<String, dynamic>> _ensurePartnerPerspectiveMix(
    List<Map<String, dynamic>> options,
    int maxCount,
  ) {
    if (options.isEmpty) return [];
    final latest = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final isAssertion = RegExp(
      r"^\s*(i\b|i'm\b|i am\b|i want\b|i like\b|i love\b|i feel\b)",
      caseSensitive: false,
    ).hasMatch(latest);
    if (!isAssertion) return options.take(math.max(1, maxCount)).toList();
    final partnerDirected = <Map<String, dynamic>>[];
    final others = <Map<String, dynamic>>[];
    for (final item in options) {
      final text = (item['option'] ?? '').toString().trim();
      if (RegExp(
        r'^(do you\b|have you\b|would you\b|could you\b|can you\b|did you\b|what do you think\b)',
        caseSensitive: false,
      ).hasMatch(text)) {
        partnerDirected.add(item);
      } else {
        others.add(item);
      }
    }
    final targetPartnerCount = math.min(
      3,
      math.max(1, (math.max(1, maxCount) / 3).floor()),
    );
    final prioritized = <Map<String, dynamic>>[
      ...partnerDirected.take(targetPartnerCount),
      ...others,
      ...partnerDirected.skip(targetPartnerCount),
    ];
    return prioritized.take(math.max(1, maxCount)).toList();
  }

  List<Map<String, dynamic>> _enforceAdditiveFollowUpOptions(
    List<Map<String, dynamic>> options,
    int maxCount,
  ) {
    if (options.isEmpty) return [];
    final latest = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final latestNormalized = _normalizeForComparison(latest);
    if (latestNormalized.isEmpty)
      return options.take(math.max(1, maxCount)).toList();
    final additive = <Map<String, dynamic>>[];
    for (final item in options) {
      final rawOption = (item['option'] ?? '').toString().trim();
      if (rawOption.isEmpty) continue;
      var updatedOption = rawOption;
      final normalizedOption = _normalizeForComparison(rawOption);
      if (normalizedOption == latestNormalized) continue;
      if (normalizedOption.startsWith(latestNormalized)) {
        final escapedLatest = RegExp.escape(latest.trim());
        final prefixRegex = RegExp(
          '^\\s*$escapedLatest\\s*[!?.:,;\\-–—]*\\s*',
          caseSensitive: false,
        );
        updatedOption = updatedOption.replaceFirst(prefixRegex, '').trim();
      }
      final updatedNormalized = _normalizeForComparison(updatedOption);
      if (updatedNormalized.isEmpty || updatedNormalized == latestNormalized)
        continue;
      additive.add({
        ...item,
        'option': updatedOption,
        'summary': (item['summary'] ?? '').toString().trim().isNotEmpty
            ? item['summary']
            : updatedOption,
      });
    }
    return additive.take(math.max(1, maxCount)).toList();
  }

  String _buildFollowUpPrompt({
    required int llmOptions,
    required bool useSummary,
    required String? currentMood,
    String excludedOptionsText = '',
  }) {
    if (_composeSession.active) {
      final summaryInstruction = useSummary
          ? 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.'
          : 'The "summary" key should contain the exact same FULL text as the "option" key.';
      final composeBody = _composeSession.text.trim();
      final latestSelectedResponse = _followUpSelectedResponses.isNotEmpty
          ? _followUpSelectedResponses.last
          : '';
      final moodLine =
          (currentMood != null &&
              currentMood.isNotEmpty &&
              currentMood != 'No Mood Selected')
          ? 'Current user mood for this writing session: "$currentMood". Keep the tone naturally consistent with this mood.\n'
          : '';
      final exclusionLine = excludedOptionsText.trim().isNotEmpty
          ? 'Avoid repeating these existing options: "$excludedOptionsText".\n'
          : '';
      return '''
  AAC COMPOSE MODE - GENERATING THE USER'S NEXT WRITTEN OPTIONS

  SCENARIO:
  The user is actively writing a document using AAC.
  This is written composition for someone who may NOT be physically present.
  IGNORE ALL room-based context such as current location, people present, activity, and anything nearby.
  Generate $llmOptions possible next phrases or sentences the user could ADD to the written composition.

  CURRENT COMPOSITION:
  "$composeBody"

  MOST RECENTLY ADDED TEXT:
  "$latestSelectedResponse"

  YOUR TASK:
  Generate natural next written options that continue or expand the composition.
  These should sound like written message/story/letter text, not spoken conversation starters.

  RULES:
  1. Ignore location, room, nearby people, and in-person conversation context
  2. Continue the written composition naturally
  3. Improve flow, detail, and continuity without changing the meaning abruptly
  4. Keep options concise, grammatical, and conversational in written form
  5. Do not generate greetings tied to the current room or current activity

  $moodLine$exclusionLine
  Return ONLY a JSON list where each item has "option", "summary", and "keywords" keys.
  The "option" key should contain the FULL option text.
  $summaryInstruction
  The "keywords" key should contain 3-5 words that match available symbols. Focus on concrete, simple words.
  ''';
    }
    final summaryInstruction = useSummary
        ? 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.'
        : 'The "summary" key should contain the exact same FULL text as the "option" key.';
    final conversationContext = _getConversationContextText();
    final latestSelectedResponse = _followUpSelectedResponses.isNotEmpty
        ? _followUpSelectedResponses.last
        : '';
    final communicationType = latestSelectedResponse.isNotEmpty
        ? _classifyCommunicationType(latestSelectedResponse)
        : 'assertion';
    final typeGuidance = _classifyFollowUpGuidance(communicationType);
    final typePatterns = ((typeGuidance['patterns'] as List?) ?? [])
        .take(4)
        .map((pattern) => '  • $pattern')
        .join('\n');
    final moodLine =
        (currentMood != null &&
            currentMood.isNotEmpty &&
            currentMood != 'No Mood Selected')
        ? 'Current user mood for this session: "$currentMood". Keep follow-up options naturally consistent with this mood.\n'
        : '';
    final exclusionLine = excludedOptionsText.trim().isNotEmpty
        ? 'Avoid repeating these existing options: "$excludedOptionsText".\n'
        : '';
    return '''
AAC COMMUNICATION SYSTEM - GENERATING USER'S NEXT SPEECH OPTIONS

SCENARIO:
An AAC user is having a conversation. They select pre-written options to speak.
The user has ALREADY SPOKEN the following words out loud to their communication partner:
$conversationContext
Most recently, the user JUST SAID OUT LOUD: "$latestSelectedResponse"

YOUR TASK:
Generate $llmOptions MORE things the SAME user can SAY, ASK, BUILD, or EXPOUND next to continue THEIR speaking turn.
These are OPTIONS FOR THE USER TO SELECT AND SPEAK (including statements and partner-engagement questions), not responses TO the user.

🚫🚫🚫 CRITICAL ERROR TO AVOID 🚫🚫🚫
DO NOT GENERATE: "Tell me more about what makes you feel this way!"
DO NOT GENERATE: "What's making you so excited?"
DO NOT GENERATE: "Tell me...", "What makes you...", "What's making you...", "Describe...", "Explain..."

✅ CORRECT EXAMPLES:
GENERATE: "This is the best day ever!"
GENERATE: "Do you want to celebrate with me?"
GENERATE: "Are you excited too?"

COMMUNICATION TYPE: ${communicationType.toUpperCase()}
${typeGuidance['description']}

PATTERN EXAMPLES FOR ${communicationType.toUpperCase()}:
$typePatterns

RULES FOR GENERATION:
1. The user is SPEAKING, not being interviewed
2. The user is continuing THEIR turn
3. Generate things the user would SAY or ASK to engage the partner
4. Options should BUILD/EXPOUND the point OR invite partner engagement
5. Keep options short, conversational, and natural
6. NO "Tell me", "What makes you", "Describe", "Explain" after user assertions
7. Include at least 4 partner-engagement QUESTIONS that end with "?"

$moodLine$exclusionLine
Return ONLY a JSON list where each item has "option", "summary", and "keywords" keys.
The "option" key should contain the FULL option text.
$summaryInstruction
The "keywords" key should contain 3-5 words that match available symbols. Focus on concrete, simple words.
''';
  }

  List<Map<String, dynamic>> _mapFollowUpOptionsToButtons(
    List<Map<String, dynamic>> options,
  ) {
    final buttons = <Map<String, dynamic>>[];
    buttons.add({
      'text': 'Home',
      'speechPhrase': 'Home',
      'isLLMGenerated': true,
      'llmSpecial': 'home',
      'row': 0,
      'col': 0,
      'hidden': false,
      'queryType': '',
      'LLMQuery': '',
      'customAudioFile': null,
      'enablePictograms': true,
    });
    for (final opt in options) {
      final optionText = (opt['option'] ?? '').toString().trim();
      if (optionText.isEmpty) continue;
      final summary = (opt['summary'] ?? '').toString().trim();
      final label = summary.isNotEmpty ? summary : optionText;
      buttons.add({
        'text': label,
        'speechPhrase': optionText,
        'isLLMGenerated': true,
        'targetPage': 'home',
        'row': buttons.length,
        'col': 0,
        'summary': summary,
        'keywords': opt['keywords'],
        'hidden': false,
        'queryType': '',
        'LLMQuery': '',
        'customAudioFile': null,
        'enablePictograms': true,
      });
    }
    buttons.add({
      'text': 'Free Style',
      'speechPhrase': 'Free Style',
      'isLLMGenerated': true,
      'llmSpecial': 'freeStyle',
      'row': buttons.length,
      'col': 0,
      'hidden': false,
      'queryType': '',
      'LLMQuery': '',
      'customAudioFile': null,
      'enablePictograms': true,
    });
    buttons.add({
      'text': 'Something Else',
      'speechPhrase': 'Something Else',
      'isLLMGenerated': true,
      'llmSpecial': 'somethingElse',
      'row': buttons.length,
      'col': 0,
      'hidden': false,
      'queryType': '',
      'LLMQuery': '',
      'customAudioFile': null,
      'enablePictograms': true,
    });
    return buttons;
  }

  Future<List<Map<String, dynamic>>> _generateFollowUpButtonsAfterSelection(
    String selectedOptionText,
  ) async {
    if (mounted) {
      setState(() {
        _showBottomStatusText = true;
        statusMessage = 'Generating AI follow-up options...';
      });
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final llmOptions = settingsProvider.settings?.llmOptions ?? 10;
    final useSummary =
        settingsProvider.settings?.useShortSummaryOnButtons ?? false;
    final currentMood = settingsProvider.settings?.currentMood;

    _addFollowUpSelection(selectedOptionText);

    final excludedOptionsText = gridButtons
        .where(
          (btn) => btn['isLLMGenerated'] == true && btn['llmSpecial'] == null,
        )
        .map((btn) => (btn['speechPhrase'] ?? '').toString().trim())
        .where((text) => text.isNotEmpty)
        .join('; ');

    final followUpPrompt = _buildFollowUpPrompt(
      llmOptions: llmOptions,
      useSummary: useSummary,
      currentMood: currentMood,
      excludedOptionsText: excludedOptionsText,
    );

    final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
      'POST',
      '${EnvironmentConfig.apiBaseUrl}/llm',
      baseHeaders: {
        'X-User-ID': widget.aacUserId,
        'Content-Type': 'application/json',
      },
      body: json.encode(_buildLlmRequestBody(followUpPrompt)),
      timeoutSeconds: 30,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Follow-up LLM request failed with status ${response.statusCode}',
      );
    }

    dynamic parsed = json.decode(response.body);
    parsed = _parseLLMResponse(parsed);
    final rawOptions = parsed is List ? parsed : <dynamic>[];
    var options = rawOptions
        .map<Map<String, dynamic>>((item) {
          if (item is Map) {
            return {
              'option': (item['option'] ?? '').toString(),
              'summary': (item['summary'] ?? item['option'] ?? '').toString(),
              'keywords': item['keywords'] is List ? item['keywords'] : null,
            };
          }
          final text = item.toString();
          return {'option': text, 'summary': text, 'keywords': null};
        })
        .where((item) => (item['option'] ?? '').toString().trim().isNotEmpty)
        .toList();

    options = options
        .where(
          (item) => !_isPartnerInterrogativePattern(
            (item['option'] ?? '').toString(),
          ),
        )
        .toList();
    options = _filterOptionsForUserVoicePerspective(options);
    options = _prioritizeContextualOptions(
      options,
      _getConversationContextText(),
      llmOptions,
    );
    options = _enforceAdditiveFollowUpOptions(options, llmOptions);
    options = _prioritizePartnerEngagementQuestions(options, llmOptions, 4);
    options = _ensurePartnerPerspectiveMix(options, llmOptions);
    if (options.length > llmOptions) {
      options = options.take(llmOptions).toList();
    }

    llmOriginalPrompt = followUpPrompt;
    activeLLMPromptForContext = _getConversationContextText();
    _currentQueryType = 'question';
    llmPreviousOptions = options
        .map((item) => (item['option'] ?? '').toString())
        .where((text) => text.trim().isNotEmpty)
        .toList();

    return _mapFollowUpOptionsToButtons(options);
  }

  // --- Simple beep for question ready indicator ---
  Future<void> _playSimpleBeep() async {
    try {
      debugPrint(
        '_playSimpleBeep: Playing subtle beep to indicate microphone ready...',
      );

      // Use TTS to generate a short, audible beep sound
      await flutterTts.setSpeechRate(1.0); // Normal speed

      // Get systemVolume from global settings (beep is not a scanning prompt, it's an announcement cue)
      final systemVolume = await _getEffectiveSystemVolume();
      final beepVolume = (systemVolume / 10.0).clamp(0.0, 1.0);
      debugPrint(
        '_playSimpleBeep: Using systemVolume: $systemVolume/10 → beep volume: $beepVolume',
      );
      await flutterTts.setVolume(beepVolume);

      await flutterTts.setPitch(1.5); // Higher pitch for beep-like sound
      await flutterTts.speak("beep"); // Clear, short word

      debugPrint('_playSimpleBeep: Simple beep completed');
    } catch (e) {
      debugPrint('_playSimpleBeep: Error playing simple beep: $e');
    }
  }

  // --- Auditory scanning methods: must be at the top of the class ---
  void _maybeStartScanning() {
    // Check if this page is currently visible
    // This prevents scanning from starting when navigating to other pages (like Admin Settings)
    if (ModalRoute.of(context)?.isCurrent == false) {
      debugPrint(
        'maybeStartScanning: page is not current, skipping scanning start',
      );
      return;
    }

    if (_suppressScanning) {
      debugPrint('maybeStartScanning: scanning suppressed');
      return;
    }

    if (_isHandlingSwitchSelection) {
      debugPrint(
        'maybeStartScanning: selection handling in progress, delaying scan restart',
      );
      return;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final enableScanning =
        settingsProvider.settings?.enableAuditoryScanning ?? false;
    final waitForSwitch =
        settingsProvider.settings?.waitForSwitchToScan ?? false;
    debugPrint(
      'maybeStartScanning: enableAuditoryScanning = $enableScanning, waitForSwitch = $waitForSwitch',
    );
    debugPrint('maybeStartScanning: current isScanning = $isScanning');
    debugPrint('maybeStartScanning: _suppressScanning = $_suppressScanning');
    debugPrint(
      'maybeStartScanning: gridButtons.length = ${gridButtons.length}',
    );

    if (!enableScanning) {
      debugPrint('maybeStartScanning: calling _stopAuditoryScanning()');
      _stopAuditoryScanning();
      return;
    }

    // Check if we should wait for switch press before starting (applies to every navigation)
    if (waitForSwitch &&
        !isScanning &&
        gridButtons.isNotEmpty &&
        !_waitingForInitialSwitch) {
      debugPrint(
        'maybeStartScanning: Waiting for switch press to begin scanning on gridpage...',
      );
      setState(() {
        _waitingForInitialSwitch = true;
        _switchStartRequested = false;
      });
      // First grid wait prompt uses speech; later waits use a short notification sound.
      if (!hasPlayedInitialWaitForSwitchVoicePrompt) {
        unawaited(() async {
          await _speakPersonalVoice('Press switch to begin scanning');
          await _playWaitForSwitchNotification();
        }());
        hasPlayedInitialWaitForSwitchVoicePrompt = true;
        _hasPlayedWaitPromptThisSession = true;
      } else {
        unawaited(_playWaitForSwitchNotification());
      }

      return; // IMPORTANT: Don't start scanning yet, wait for switch press
    }

    // Start scanning immediately (either wait-for-switch is disabled, or already waiting)
    debugPrint('maybeStartScanning: calling _startAuditoryScanning()');
    _startAuditoryScanning();
  }

  Future<void> _playWaitForSwitchNotification() async {
    final now = DateTime.now();
    if (_lastWaitForSwitchNotificationAt != null &&
        now.difference(_lastWaitForSwitchNotificationAt!).inMilliseconds <
            1200) {
      debugPrint(
        'waitForSwitchNotification: Skipping duplicate notification playback',
      );
      return;
    }
    _lastWaitForSwitchNotificationAt = now;

    final player = _createTrackedAudioPlayer('wait_for_switch_notification');
    try {
      await player.setAsset('assets/notification_v2.mp3');
      await player.play();
      await player.playerStateStream
          .firstWhere(
            (state) => state.processingState == ProcessingState.completed,
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint(
        'waitForSwitchNotification: Error playing notification sound: $e',
      );
    } finally {
      await _disposeAudioPlayer(player, 'wait_for_switch_notification');
    }
  }

  bool _shouldAutoScanBeRunning() {
    if (!mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (_suppressScanning) return false;
    if (_isHandlingSwitchSelection) return false;
    if (_isScanningPaused && _waitingForUserInput) return false;
    if (_waitingForInitialSwitch) return false;
    if (_isProcessingLLM || _inQuestionMode || _listeningForQuestion) {
      return false;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final enableScanning =
        settingsProvider.settings?.enableAuditoryScanning ?? false;
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    return enableScanning && scanMode == 'auto';
  }

  void _ensureScanWatchdogRunning() {
    _scanWatchdogTimer?.cancel();
    _scanWatchdogTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _runScanWatchdogCheck();
    });
  }

  void _runScanWatchdogCheck() {
    if (!_shouldAutoScanBeRunning()) {
      return;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final delayMs = settingsProvider.settings?.scanDelay ?? 3500;
    final maxSilenceMs = (delayMs * 2) + 2500;
    final now = DateTime.now();
    final lastStep = _lastScanStepAt;
    final isTimerMissing = scanningTimer == null || !(scanningTimer!.isActive);
    final isStepStale =
        lastStep != null &&
        now.difference(lastStep).inMilliseconds > maxSilenceMs;

    if (!isScanning || isTimerMissing || isStepStale) {
      final ageMs = lastStep == null
          ? -1
          : now.difference(lastStep).inMilliseconds;
      debugPrint(
        'scanWatchdog: detected stall (isScanning=$isScanning, timerMissing=$isTimerMissing, stale=$isStepStale, lastStepAgeMs=$ageMs). Recovering...',
      );
      _recoverAuditoryScanning('watchdog');
    }
  }

  Future<void> _recoverAuditoryScanning(String reason) async {
    if (_scanRecoveryInProgress || !mounted) return;
    if (!_shouldAutoScanBeRunning()) return;

    _scanRecoveryInProgress = true;
    try {
      debugPrint('scanRecovery: attempting recovery (reason=$reason)');
      scanningTimer?.cancel();
      if (mounted) {
        setState(() {
          isScanning = false;
          _isScanningPaused = false;
          _waitingForUserInput = false;
        });
      }

      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted || !_shouldAutoScanBeRunning()) return;

      await _startAuditoryScanning();
      debugPrint('scanRecovery: recovery complete');
    } catch (e) {
      debugPrint('scanRecovery: failed: $e');
    } finally {
      _scanRecoveryInProgress = false;
    }
  }

  void _runScanStepSafe(String source) {
    if (!mounted) return;
    _lastScanStepAt = DateTime.now();
    unawaited(
      _scanStep().catchError((error, stackTrace) {
        debugPrint('scanStepSafe: error from $source: $error');
        _recoverAuditoryScanning('scan_step_error_$source');
      }),
    );
  }

  Future<void> _startAuditoryScanning() async {
    debugPrint(
      'startAuditoryScanning: called, isScanning=' + isScanning.toString(),
    );

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final waitForSwitch =
        settingsProvider.settings?.waitForSwitchToScan ?? false;

    if (waitForSwitch && !_switchStartRequested) {
      debugPrint(
        'startAuditoryScanning: Switch not pressed, blocking scanning',
      );
      return;
    }

    // CRITICAL: Don't start scanning if we're waiting for the user to press switch
    if (_waitingForInitialSwitch) {
      debugPrint(
        'startAuditoryScanning: Waiting for switch press, blocking scanning',
      );
      return;
    }

    if (isScanning) {
      debugPrint('startAuditoryScanning: already scanning, returning');
      return;
    }

    debugPrint('startAuditoryScanning: Setting up scanning state...');
    setState(() {
      isScanning = true;
      scanningIndex = -1;
      _currentScanCycle = 0; // Reset cycle counter
      _isScanningPaused = false; // Reset pause state
      _waitingForUserInput = false; // Reset waiting state
      _switchStartRequested = false;
    });
    _lastScanStepAt = DateTime.now();
    debugPrint('startAuditoryScanning: State set - isScanning=$isScanning');

    // Android notification sounds suppressed globally

    int delay = settingsProvider.settings?.scanDelay ?? 3500;
    debugPrint('startAuditoryScanning: Using scan delay: $delay ms');

    scanningTimer?.cancel();
    final audioDeviceProvider = Provider.of<AudioDeviceProvider>(
      context,
      listen: false,
    );
    if (!kIsWeb && Platform.isWindows) {
      debugPrint(
        'startAuditoryScanning: Routing to personal device: \\${audioDeviceProvider.personalDeviceId}',
      );
      await AudioDeviceService().playAudioToDevice(
        audioDeviceProvider.personalDeviceId ?? 'default',
        isPersonal: true,
      );
    }
    // No force speaker for iOS/Android
    // Only setup immediate prompt + periodic timer for auto mode
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';
    debugPrint('startAuditoryScanning: Scan mode: $scanMode');

    if (scanMode == 'auto') {
      debugPrint(
        'startAuditoryScanning: Starting first scan step for auto mode...',
      );
      _runScanStepSafe('initial');
      debugPrint(
        'startAuditoryScanning: Setting up periodic timer for auto mode...',
      );
      scanningTimer = Timer.periodic(
        Duration(milliseconds: delay),
        (_) => _runScanStepSafe('periodic'),
      );
      _ensureScanWatchdogRunning();
    } else {
      debugPrint(
        'startAuditoryScanning: Step mode - waiting for first Tab, timer not started',
      );
      _scanWatchdogTimer?.cancel();
    }
    gridFocusNode?.requestFocus();
    debugPrint('startAuditoryScanning: Setup complete');
  }

  void _stopAuditoryScanning() {
    debugPrint(
      'stopAuditoryScanning: called, isScanning=' + isScanning.toString(),
    );

    // Android notification sounds managed globally

    setState(() {
      isScanning = false;
      scanningTimer?.cancel();
      _scanWatchdogTimer?.cancel();
      scanningIndex = null;
      _currentScanCycle = 0; // Reset cycle counter
      _isScanningPaused = false; // Reset pause state
      _waitingForUserInput = false; // Reset waiting state
    });
  }

  Future<void> _pauseScanning({bool silent = false}) async {
    debugPrint('pauseScanning: called (silent=$silent)');
    setState(() {
      _isScanningPaused = true;
      _waitingForUserInput = true;
      scanningTimer?.cancel(); // Stop the timer
      // Keep current scanningIndex - don't change it
    });

    if (!silent) {
      // Play "Scanning paused. Use your switch to resume" using the same voice as button scanning
      await _speakPersonalVoice("Scanning paused. Use your switch to resume");
    }
  }

  Future<void> _resumeScanning() async {
    debugPrint('resumeScanning: called');
    if (!_isScanningPaused) return;

    setState(() {
      _isScanningPaused = false;
      _waitingForUserInput = false;
      _currentScanCycle = 0; // Reset cycle counter when resuming
    });

    // Play "Scanning resumed" using the same voice as button scanning
    await _speakPersonalVoice("Scanning resumed");

    // Speak the current button (where we paused) before starting the timer
    final definedButtons = _effectiveGridButtons();
    if (definedButtons.isNotEmpty &&
        scanningIndex != null &&
        scanningIndex! < definedButtons.length) {
      final btn = definedButtons[scanningIndex!];
      await _speakPersonalVoice(
        btn['text'] ?? btn['summary'] ?? btn['option'] ?? '',
      );
    }

    // Restart the scanning timer
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    int delay = settingsProvider.settings?.scanDelay ?? 3500;
    scanningTimer = Timer.periodic(
      Duration(milliseconds: delay),
      (_) => _runScanStepSafe('resume_periodic'),
    );
    _ensureScanWatchdogRunning();
  }

  Future<void> _scanStep() async {
    debugPrint('scanStep: called');

    // Re-suppress Android notification sounds during each scan step
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('suppressNotificationSounds');
        debugPrint('🔊 SCAN: Re-suppressed notifications during scan step');
      } catch (e) {
        debugPrint(
          '🔊 SCAN: Failed to re-suppress notifications during scan step: $e',
        );
      }
    }

    // Check if we're paused and waiting for user input
    if (_isScanningPaused && _waitingForUserInput) {
      debugPrint('scanStep: Scanning is paused, waiting for user input');
      return;
    }

    final definedButtons = _effectiveGridButtons();
    if (definedButtons.isEmpty) {
      debugPrint('scanStep: No defined buttons');
      return;
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final scanLoopLimit = settingsProvider.settings?.scanLoopLimit ?? 3;

    setState(() {
      scanningIndex = scanningIndex == null
          ? 0
          : (scanningIndex! + 1) % definedButtons.length;

      // Check if we've completed a full cycle (back to index 0)
      if (scanningIndex == 0 && _currentScanCycle > 0) {
        _currentScanCycle++;
        debugPrint('scanStep: Completed scan cycle $_currentScanCycle');
      } else if (scanningIndex == 0) {
        // First time reaching index 0, start counting cycles
        _currentScanCycle = 1;
        debugPrint('scanStep: Starting scan cycle 1');
      }
    });

    // Check if we should pause BEFORE speaking the button (scanLoopLimit > 0 and we've reached the limit)
    if (scanLoopLimit > 0 && _currentScanCycle > scanLoopLimit) {
      debugPrint('scanStep: Reached scan loop limit ($scanLoopLimit), pausing');
      _pauseScanning();
      return;
    }

    final btn = definedButtons[scanningIndex!];
    debugPrint(
      'scanStep: Speaking button text: \\${btn['text'] ?? btn['summary'] ?? btn['option'] ?? ''}',
    );
    // Mark that we're announcing a scanning prompt
    setState(() {
      _isAnnouncingScanningPrompt = true;
    });
    await _speakPersonalVoice(
      btn['text'] ?? btn['summary'] ?? btn['option'] ?? '',
    );
    // Clear the flag when done
    if (mounted) {
      setState(() {
        _isAnnouncingScanningPrompt = false;
      });
    }

    _lastScanStepAt = DateTime.now();
  }

  static const platform = MethodChannel('audio_routing');

  // Placeholder for grid data (to be fetched from backend)
  List<Map<String, dynamic>> gridButtons = [
    {"text": "Greetings"},
    {"text": "Feelings"},
    {"text": "Needs"},
    {"text": "Questions"},
    {"text": "About Me"},
    {"text": "My Day"},
    {"text": "Current Events"},
    {"text": "Food"},
    {"text": "Drink"},
  ];
  List<Map<String, dynamic>>?
  previousGridButtons; // Store previous grid for LLM
  String? previousPageName; // Store previous page name for LLM

  // Compose grid navigation stack (replaces dialog-based menus)
  final List<List<Map<String, dynamic>>> _composeGridStack = [];
  final List<String> _composePageStack = [];

  String speechHistory = '';
  ComposeSessionData _composeSession = const ComposeSessionData.inactive();
  String questionDisplay = '';
  bool _isSpeechHistoryMaximized = false;
  bool isLoading = false;
  late FlutterTts flutterTts;
  String? statusMessage = '';

  List<String> llmPreviousOptions = [];
  String? llmOriginalPrompt;
  String?
  _currentQueryType; // Track current query type ('jokes', 'currentevents', etc.) for Something Else
  String?
  originatingButtonText; // Store the text of the button that initiated LLM query
  String?
  activeLLMPromptForContext; // Store the LLM query as primary context for freestyle

  // Session-only follow-up conversation state
  String? _followUpOriginalQuestion;
  final List<String> _followUpSelectedResponses = [];

  String currentPageName = 'home'; // Track the current page name
  String currentPageDisplayName = 'Home'; // Track the current page display name
  List<dynamic> _cachedPagesPayload = []; // Last successful /pages payload

  // Navigation history stack for GO-BACK and TEMPORARY navigation
  List<String> _navigationHistory = [
    'home',
  ]; // Stack of page names, always starts with home
  String?
  _temporaryNavigationReturnPage; // Store return page for TEMPORARY navigation

  int? scanningIndex;
  Timer? scanningTimer;
  FocusNode? gridFocusNode;
  bool isScanning = false;

  // Scan loop limit tracking
  int _currentScanCycle = 0; // Track how many complete cycles we've done
  bool _isScanningPaused = false; // Track if scanning is paused
  bool _isAnnouncementPlaying =
      false; // Track if announcement is currently playing
  bool _waitingForUserInput =
      false; // Track if we're waiting for user to resume

  // Wait-for-switch feature tracking
  bool _waitingForInitialSwitch =
      false; // Track if waiting for initial switch press to start scanning
  bool _switchStartRequested =
      false; // Track explicit switch press for scan start
  bool _hasPlayedWaitPromptThisSession =
      false; // Track if we've already played the wait-for-switch prompt (only play once per session)
  DateTime? _lastWaitForSwitchNotificationAt;

  WakeWordService? _wakeWordService;
  bool _listeningForQuestion = false;
  bool _isProcessingLLM = false;
  bool _inQuestionMode = false; // Track if we're in question listening mode
  String? _questionText;
  String? _wakeWordInterjection; // NEW
  String? _wakeWordName; // NEW
  List<String> _wakeWordVariants = []; // NEW
  bool _showBottomStatusText = false;

  // --- LLM RETRY TRACKING ---
  static const int _maxLLMRetries = 2; // Allow 2 retries (3 total attempts)
  int _llmRetryCount = 0; // Track retry attempts for current query
  String? _lastLLMQuery; // Store last query for retry
  Map<String, dynamic>? _lastLLMButtonData; // Store button data for retry
  bool _lastWasScanningPaused = false; // Store scanning state for retry

  // --- Microphone Status Tracking ---
  bool _microphoneListening = false;
  bool _microphonePermissionGranted = false;

  // --- Spacebar Hold Protection ---
  bool _isSpacebarDown = false;
  bool _isSpacebarDisabled = false;
  Timer? _spacebarHoldTimer;

  // --- Admin Toolbar Lock State ---
  bool _isAdminToolbarLocked = true; // Default to locked
  int _pinAttempts = 0;
  String? _currentPIN = '1234'; // Will be loaded from settings

  // --- App Lifecycle Focus Management ---
  bool _needsFocusRefresh =
      true; // Track if we need to refresh focus after app resume
  bool _appWasMinimized = false; // Track if app was minimized
  bool _showWelcomeDialog = true; // Show focus-establishing welcome dialog

  // --- SPEECH BUBBLE OVERLAY VARIABLES ---
  bool _showSpeechBubble = false; // Track if speech bubble is visible
  String _speechBubbleText = ''; // Text to display in speech bubble
  Timer? _speechBubbleTimer; // Timer to auto-hide speech bubble

  // --- AUDIO PLAYER RESOURCE TRACKING ---
  final List<AudioPlayer> _activeAudioPlayers =
      []; // Track all AudioPlayer instances to prevent resource leaks

  // --- STATUS MESSAGE AUTO-RESET ---
  Timer? _statusMessageTimer; // Timer to auto-reset long status messages

  // --- STEP MODE SCANNING ---
  bool _isAnnouncingScanningPrompt =
      false; // Track if current announcement is a scanning prompt (not regular announcement)
    bool _isHandlingSwitchSelection =
      false; // Ignore additional switch presses while selection is processing
  Timer? _scanWatchdogTimer; // Self-heal timer for stalled scanning sessions
  DateTime? _lastScanStepAt; // Last successful scan step execution timestamp
  bool _scanRecoveryInProgress = false; // Prevent overlapping recovery attempts

  // --- APP REFRESH STATE ---
  bool _isRefreshing = false; // Track if app is currently refreshing

  // --- GRID SIZE VARIABLE ---
  static const int gridSize =
      10; // Default 10x10 grid, can be made configurable later

  @override
  void initState() {
    super.initState();
    unawaited(_loadComposeSession());
    print(
      '🔵 GridPageState - initState called with aacUserId: ${widget.aacUserId}',
    );
    print(
      '🔵 GridPageState - CRITICAL DEBUG: State initialized with profile ID: ${widget.aacUserId}',
    );
    flutterTts = FlutterTts();
    gridFocusNode = FocusNode();

    // Register as lifecycle observer to detect minimize/restore cycles
    WidgetsBinding.instance.addObserver(this);

    // Orientation lock handled by platform (Info.plist/AndroidManifest)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // CRITICAL: Globally suppress Android notification sounds FIRST before any audio operations
      if (!kIsWeb && Platform.isAndroid) {
        try {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('suppressNotificationSounds');
          debugPrint(
            '🔊 GLOBAL: Android notification sounds globally suppressed BEFORE audio init',
          );
        } catch (e) {
          debugPrint(
            '🔊 GLOBAL: Failed to globally suppress notification sounds: $e',
          );
        }
      }

      // CRITICAL: Load settings FIRST before audio initialization
      // This ensures _settingsProvider has volume settings before _initializeAudioSession() is called
      debugPrint(
        '🔊 VOLUME: initState: Loading settings FIRST before audio initialization...',
      );
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      // Store settings provider reference for safe cleanup
      _settingsProvider = settingsProvider;
      settingsProvider.idToken = widget.idToken;
      print(
        '🔵 GridPage initState: Setting settingsProvider.userId to: ${widget.aacUserId}',
      );
      settingsProvider.userId = widget.aacUserId;
      await settingsProvider.fetchSettings();
      debugPrint(
        '🔊 VOLUME: initState: Settings loaded successfully - personal volume: ${settingsProvider.settings?.personalVolume}, system volume: ${settingsProvider.settings?.systemVolume}',
      );

      // Initialize audio session AFTER settings are loaded
      if (!_audioSessionInitialized) {
        debugPrint(
          '🔊 VOLUME: initState: Initializing audio session with loaded settings...',
        );
        try {
          await _initializeAudioSession();
          _audioSessionInitialized = true;
          debugPrint(
            '🔊 VOLUME: initState: Audio session initialization completed successfully',
          );

          // Re-suppress notifications after audio session in case it restored them
          if (!kIsWeb && Platform.isAndroid) {
            try {
              const platform = MethodChannel('audio_routing');
              await platform.invokeMethod('suppressNotificationSounds');
              debugPrint(
                '🔊 GLOBAL: Re-suppressed notifications after audio session initialization',
              );
            } catch (e) {
              debugPrint(
                '🔊 GLOBAL: Failed to re-suppress notifications after audio init: $e',
              );
            }
          }
        } catch (e) {
          debugPrint(
            '🔊 VOLUME: initState: Audio session initialization failed: $e',
          );
        }
      }

      // Initialize pictogram service cache
      debugPrint('initState: Loading pictogram cache...');
      await PictogramService().loadCacheFromPrefs();
      debugPrint('initState: Pictogram cache loaded');

      // Preload common pictograms in background
      // DISABLED: This was causing unwanted missing image logging for words not on visited pages
      // PictogramService().preloadCommonWords();

      // Check microphone permission status (don't request yet)
      debugPrint('initState: Checking microphone permission status...');
      debugPrint(
        'initState: Platform check - iOS: ${Platform.isIOS}, Android: ${Platform.isAndroid}, Web: $kIsWeb',
      );

      _microphonePermissionGranted = true; // Default for web

      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        try {
          final permissionStatus = await Permission.microphone.status;
          debugPrint('initState: Raw permission status: $permissionStatus');
          debugPrint(
            'initState: Permission details - isGranted: ${permissionStatus.isGranted}, isDenied: ${permissionStatus.isDenied}, isRestricted: ${permissionStatus.isRestricted}, isPermanentlyDenied: ${permissionStatus.isPermanentlyDenied}',
          );

          _microphonePermissionGranted = permissionStatus.isGranted;
          debugPrint(
            'initState: Final microphonePermissionGranted: $_microphonePermissionGranted',
          );

          // Auto-request permission if denied (but not permanently denied)
          if (permissionStatus.isDenied &&
              !permissionStatus.isPermanentlyDenied) {
            debugPrint(
              'initState: Permission denied but not permanently - requesting automatically...',
            );
            final hasPermission = await _requestMicrophonePermission();
            _microphonePermissionGranted = hasPermission;
            debugPrint('initState: Auto-request result: $hasPermission');
          }

          // Additional iOS-specific checks
          if (Platform.isIOS) {
            debugPrint('iOS: Detailed permission analysis');
            if (permissionStatus.isDenied) {
              debugPrint(
                'iOS: Permission is DENIED - user needs to grant permission',
              );
            } else if (permissionStatus.isRestricted) {
              debugPrint(
                'iOS: Permission is RESTRICTED - system-level restriction',
              );
            } else if (permissionStatus.isPermanentlyDenied) {
              debugPrint(
                'iOS: Permission is PERMANENTLY DENIED - user must go to Settings',
              );
            } else if (permissionStatus.isGranted) {
              debugPrint('iOS: Permission is GRANTED - should work normally');
            } else {
              debugPrint(
                'iOS: Permission status is unclear: $permissionStatus',
              );
            }
          }
        } catch (e) {
          debugPrint('initState: ERROR checking microphone permission: $e');
          _microphonePermissionGranted = false; // Assume not granted on error
        }
      } else {
        debugPrint(
          'initState: Web platform - skipping microphone permission check',
        );
      }

      if (!_microphonePermissionGranted) {
        debugPrint(
          'initState: Microphone permission not granted - will work without voice commands',
        );
      } else {
        debugPrint('initState: Microphone permission already granted');
      }

      // --- Load PIN from settings ---
      _updatePINFromSettings(settingsProvider);

      // --- Wake Word Setup (always initialize - let WakeWordService handle permissions internally) ---
      // Add a small delay to ensure scanning and other initialization is complete
      await Future.delayed(const Duration(milliseconds: 1000));

      // Always initialize wake word service - it will handle permission internally
      debugPrint(
        'initState: Initializing wake word service (will handle permission internally)',
      );
      await _initializeWakeWordServiceWithPermission();
      await fetchGridData();

      // *** INITIALIZE APP HEALTH MONITORING ***
      debugPrint('initState: Starting app health monitoring...');
      AppHealthManager.instance.startHealthMonitoring(
        onNeedsRefresh: () {
          debugPrint('🚨 App health manager detected degraded performance');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '⚠️ App performance degraded - consider refreshing',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
        },
        onTimeout: () {
          debugPrint('🚨 App health manager detected timeout');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔄 App has been inactive - refresh recommended'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 8),
              ),
            );
          }
        },
        onHealthChanged: (healthData) {
          // Record activity when health status changes
          AppHealthManager.instance.recordActivity();
        },
      );

      // *** NUCLEAR FOCUS RESET - ONCE ON GRID PAGE LOAD ***
      debugPrint(
        'initState: Performing nuclear focus reset on grid page load...',
      );
      _resetFocusTree();

      _maybeStartScanning();
      // Add listener for settings changes
      _settingsProvider!.addListener(_maybeStartScanning);
    });
  }

  @override
  void dispose() {
    scanningTimer?.cancel();
    _scanWatchdogTimer?.cancel();
    _speechBubbleTimer?.cancel(); // Clean up speech bubble timer
    _statusMessageTimer?.cancel(); // Clean up status message timer
    gridFocusNode?.dispose();

    // Restore notification sounds on Android when app is actually closing
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const platform = MethodChannel('audio_routing');
        platform.invokeMethod('restoreNotificationSounds');
        debugPrint('🔊 GLOBAL: Notification sounds restored on app close');
      } catch (e) {
        debugPrint(
          '🔊 GLOBAL: Failed to restore notification sounds on app close: $e',
        );
      }
    }

    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // CRITICAL: Clean up wake word service callbacks to prevent setState on disposed widget
    debugPrint('[GridPage] dispose: Cleaning up wake word service callbacks');
    if (_wakeWordService != null) {
      // NOTE: Don't directly clear callbacks as other pages (like ThreadsPage)
      // may have set their own callbacks. Let those pages manage their own callbacks.
      debugPrint(
        '[GridPage] dispose: Letting other pages manage their own wake word callbacks',
      );
    }

    // Remove settings listener safely using stored reference
    _settingsProvider?.removeListener(_maybeStartScanning);

    // Clean up route observer (no need to access providers in dispose)
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Find the didPushNext method (around line 2969) and replace it with this:
  @override
  void didPushNext() {
    debugPrint(
      '🔴 MAIN PAGE didPushNext: CALLED - Stopping auditory scanning and wake word listening',
    );

    // Stop auditory scanning when navigating away
    debugPrint(
      'didPushNext: Stopping auditory scanning and wake word listening',
    );
    _stopAuditoryScanning();

    // CRITICAL FIX: COMPLETELY STOP wake word service instead of just pausing it
    debugPrint(
      '🔴 MAIN PAGE didPushNext: COMPLETELY STOPPING wake word service to prevent session conflicts',
    );
    if (_wakeWordService != null) {
      _wakeWordService!.stopAllRecognizers();
      _wakeWordService!.stopWakeWordListening();
      debugPrint(
        '🔴 MAIN PAGE didPushNext: Wake word service completely stopped',
      );
    }

    // Keep global flag active so freestyle page can start its own service
    WakeWordService.wakeWordShouldBeActive = true;
    debugPrint(
      '🔴 MAIN PAGE didPushNext: Global wake word flag kept active for next page',
    );
  }

  // Update the didPopNext method to use the existing setter methods
  @override
  void didPopNext() {
    // Returned to grid page
    print('🔴 MAIN PAGE didPopNext: CALLED - Returned to grid page');
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    settingsProvider.addListener(_maybeStartScanning);

    if (mounted) {
      setState(() {
        statusMessage = null;
        scanningIndex = null;
      });
    }

    // CRITICAL: Check if freestyle page detected a wake word
    if (WakeWordService.pendingWakeWordFromFreestyle != null) {
      final transcript = WakeWordService.pendingWakeWordFromFreestyle!;
      WakeWordService.pendingWakeWordFromFreestyle = null; // Clear the flag

      print(
        '🎤 MAIN PAGE didPopNext: Processing wake word from freestyle page: "$transcript"',
      );

      // Trigger the main page's wake word process
      // This will run the full "I am listening" -> question listening -> LLM flow
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Small delay to ensure main page is fully ready
        await Future.delayed(const Duration(milliseconds: 200));

        if (_wakeWordService != null && _wakeWordService!.onWakeWord != null) {
          print(
            '🎤 MAIN PAGE didPopNext: Setting wake word flags using existing setter methods',
          );

          // Use the existing setter methods that are already in WakeWordService
          _wakeWordService!.setWakeWordDetected(
            true,
          ); // This tells QuestionService that a wake word was detected
          _wakeWordService!.setProcessingWakeWord(
            true,
          ); // This tells other parts we're processing a wake word

          print(
            '🎤 MAIN PAGE didPopNext: Wake word flags set using existing setter methods',
          );

          print(
            '🎤 MAIN PAGE didPopNext: Triggering main page wake word callback',
          );
          _wakeWordService!.onWakeWord!(transcript);
        } else {
          print(
            '🎤 MAIN PAGE didPopNext: Wake word service or callback not available',
          );
        }
      });
    } else {
      print(
        '🔄 MAIN PAGE didPopNext: Normal return - restarting scanning and wake word service',
      );

      _stopAuditoryScanning();
      if (mounted) {
        setState(() {
          _waitingForInitialSwitch = false;
          _switchStartRequested = false;
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        gridFocusNode?.requestFocus();
        _maybeStartScanning();
      });

      // Resume wake word service that was paused in didPushNext
      if (_wakeWordService != null) {
        print('🎤 MAIN PAGE didPopNext: Resuming wake word service');
        _wakeWordService!.resumeWakeWordAutoRestart();
        _wakeWordService!.startWakeWordListening();
        debugPrint(
          'didPopNext: Wake word service resumed and listening restarted',
        );
      } else {
        debugPrint(
          'didPopNext: Wake word service not initialized - skipping restart',
        );
      }
    }

    super.didPopNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  // *** APP LIFECYCLE FOCUS MANAGEMENT - MIMIC MINIMIZE/RESTORE BEHAVIOR ***
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('AppLifecycle: State changed to $state');

    switch (state) {
      case AppLifecycleState.paused:
        // App is being minimized/backgrounded
        debugPrint(
          'AppLifecycle: App paused (minimized) - marking for focus refresh',
        );
        _appWasMinimized = true;
        _needsFocusRefresh = true;
        break;

      case AppLifecycleState.resumed:
        // App is being restored/foregrounded
        if (_appWasMinimized && _needsFocusRefresh) {
          debugPrint(
            'AppLifecycle: App resumed after minimize - triggering focus refresh for keyboard suppression!',
          );

          // Restore saved volume settings when app resumes
          // This ensures volume preferences are maintained if user adjusted system volume while app was backgrounded
          debugPrint(
            '🔊 VOLUME: AppLifecycle: Restoring saved volume settings on app resume...',
          );
          Future.delayed(const Duration(milliseconds: 100), () async {
            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              try {
                final platform = MethodChannel('audio_routing');
                await _setApplicationVolume(
                  settings: _settingsProvider?.settings,
                );
                debugPrint(
                  '🔊 VOLUME: ✅ Saved volume settings restored successfully on app resume',
                );
              } catch (e) {
                debugPrint(
                  '🔊 VOLUME: ⚠️  Failed to restore volume on resume: $e',
                );
              }
            }
          });

          // Check if microphone permission was granted while app was in background
          if (!_microphonePermissionGranted) {
            debugPrint(
              'AppLifecycle: Checking if microphone permission was granted while app was backgrounded...',
            );
            _recheckMicrophonePermissionAndInitialize();
          }

          // Use a small delay to ensure app is fully restored
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && gridFocusNode != null) {
              debugPrint(
                'AppLifecycle: Requesting focus to establish keyboard suppression',
              );
              gridFocusNode!.requestFocus();

              // Mark that we've handled this cycle
              _needsFocusRefresh = false;
              _appWasMinimized = false;

              debugPrint(
                'AppLifecycle: Focus refresh complete - keyboard should now be suppressed!',
              );
            }
          });
        }
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Other states - no action needed
        break;
    }
  }

  // *** FORCE FOCUS RECLAIM - CALL AFTER DIALOGS/SNACKBARS ***
  void _reclaimFocus() {
    debugPrint('_reclaimFocus: Forcing focus back to RawKeyboardListener...');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && gridFocusNode != null) {
        gridFocusNode!.unfocus();
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && gridFocusNode != null) {
            gridFocusNode!.requestFocus();
            debugPrint('_reclaimFocus: Focus reclaimed successfully');
          }
        });
      }
    });
  }

  // *** NUCLEAR FOCUS RESET + COMPLETE KEYBOARD DISABLE ***
  void _resetFocusTree() async {
    debugPrint(
      '_resetFocusTree: Starting nuclear focus reset + complete keyboard disable...',
    );

    try {
      // Platform-specific keyboard disable and focus reset
      if (Platform.isAndroid) {
        debugPrint(
          '_resetFocusTree: Calling Android complete keyboard disable...',
        );
        await platform.invokeMethod('disableSoftKeyboard');

        debugPrint('_resetFocusTree: Calling Android native focus reset...');
        await platform.invokeMethod('resetFocus');
      } else if (Platform.isIOS) {
        debugPrint(
          '_resetFocusTree: iOS - skipping Android-specific keyboard disable',
        );
        // iOS doesn't need keyboard disable - it handles this differently
      }

      // Universal Flutter focus management (works on all platforms)
      FocusManager.instance.primaryFocus?.unfocus();
      debugPrint('_resetFocusTree: Unfocused primary focus');

      // Reset the entire focus tree
      FocusManager.instance.rootScope.requestFocus(FocusNode());
      debugPrint('_resetFocusTree: Reset root focus scope');

      // Delay slightly before reclaiming focus
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && gridFocusNode != null) {
          gridFocusNode!.requestFocus();
          debugPrint('_resetFocusTree: Reclaimed grid focus after delay');
        }
      });

      debugPrint('_resetFocusTree: Platform-specific focus reset complete');
    } catch (e) {
      debugPrint('_resetFocusTree: Error during platform-specific reset: $e');
      // Fallback to Flutter-only approach
      FocusManager.instance.primaryFocus?.unfocus();
      FocusManager.instance.rootScope.requestFocus(FocusNode());
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && gridFocusNode != null) {
          gridFocusNode!.requestFocus();
        }
      });
    }
  }

  // *** FOCUS DEBUGGING HELPER ***
  void _debugFocusTree() {
    debugPrint('=== FOCUS TREE DEBUG START ===');
    debugDumpFocusTree();

    final focused = FocusManager.instance.primaryFocus;
    if (focused != null) {
      debugPrint('Focused widget: ${focused.context?.widget}');
      debugPrint('Focus node: $focused');
    } else {
      debugPrint('No primary focus found');
    }
    debugPrint('=== FOCUS TREE DEBUG END ===');
  }

  // *** ESTABLISH PROPER FOCUS - MIMICS THE MINIMIZE/RESTORE BEHAVIOR ***
  void _establishProperFocus() {
    debugPrint(
      '_establishProperFocus: Starting focus establishment sequence...',
    );

    // Step 1: Small delay to ensure dialog is fully closed
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && gridFocusNode != null) {
        debugPrint('_establishProperFocus: Step 1 - Unfocusing everything...');

        // Step 2: Unfocus everything first (like when app goes to background)
        gridFocusNode!.unfocus();
        FocusScope.of(context).unfocus();

        // Step 3: Wait a bit more, then request focus (like when app comes to foreground)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && gridFocusNode != null) {
            debugPrint(
              '_establishProperFocus: Step 2 - Requesting focus for RawKeyboardListener...',
            );
            gridFocusNode!.requestFocus();

            // Step 4: Final verification
            Future.delayed(const Duration(milliseconds: 100), () {
              final hasFocus = gridFocusNode?.hasFocus ?? false;
              debugPrint(
                '_establishProperFocus: Complete! RawKeyboardListener hasFocus=$hasFocus',
              );

              if (hasFocus) {
                debugPrint(
                  '🎉 SUCCESS: Spacebar should now work without triggering keyboard!',
                );
              } else {
                debugPrint(
                  '⚠️ WARNING: Focus establishment may have failed. Try tapping the screen once.',
                );
              }
            });
          }
        });
      }
    });
  }

  bool _isEmailSpecialButton(Map<String, dynamic> button) {
    final target =
        (button['targetPage'] ??
                button['target_page'] ??
                button['targetNavigation'] ??
                button['target_navigation'] ??
                button['target navigation'] ??
                button['target'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    if (target == '!email' || target == 'email') {
      return true;
    }

    final special =
        (button['specialPage'] ??
                button['special_page'] ??
                button['special function'] ??
                button['special_navigation'] ??
                button['special navigation'] ??
                button['special_function'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    return special == 'email' ||
        special == 'email-page' ||
        special == 'email_page' ||
        special == 'mail';
  }

  List<Map<String, dynamic>> _ensureEmailButtonVisible(
    List<Map<String, dynamic>> allButtons,
    List<Map<String, dynamic>> visibleButtons,
  ) {
    final alreadyVisible = visibleButtons.any(_isEmailSpecialButton);
    if (alreadyVisible) {
      return visibleButtons;
    }

    final hiddenOrFilteredEmail = allButtons
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (button) => button != null && _isEmailSpecialButton(button),
          orElse: () => null,
        );

    // No email button configured for this page.
    if (hiddenOrFilteredEmail == null) {
      return visibleButtons;
    }

    final promoted = Map<String, dynamic>.from(hiddenOrFilteredEmail);
    promoted['hidden'] = false;
    promoted['targetPage'] = '!email';
    if ((promoted['text'] ?? '').toString().trim().isEmpty) {
      promoted['text'] = 'Email';
    }

    if (promoted['row'] == null || promoted['col'] == null) {
      promoted['row'] = visibleButtons.length;
      promoted['col'] = 0;
    }

    return <Map<String, dynamic>>[...visibleButtons, promoted];
  }

  String _normalizeSpecialPageName(String rawSpecialPage) {
    final normalized = rawSpecialPage
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(' ', '-');

    switch (normalized) {
      case 'guesswho':
      case 'guess-who':
        return 'guess-who';
      case 'free-style':
      case 'freestyle':
        return 'freestyle';
      case 'thread':
      case 'threads':
        return 'threads';
      case 'favorite':
      case 'favorites':
        return 'favorites';
      case 'game':
      case 'games':
        return 'games';
      case 'moods':
      case 'mood':
        return 'mood';
      case 'email-page':
      case 'emailpage':
      case 'mail':
      case 'email':
        return 'email';
      case 'joke':
      case 'jokes':
        return 'jokes';
      case 'spell':
      case 'spelling-page':
      case 'spellingpage':
      case 'spelling':
        return 'spelling';
      case 'number':
      case 'numbers-page':
      case 'numberspage':
      case 'numbers':
        return 'numbers';
      default:
        return normalized;
    }
  }

  Map<String, dynamic> _normalizeGridButton(Map<String, dynamic> rawButton) {
    final button = Map<String, dynamic>.from(rawButton);

    final text =
        (button['text'] ??
                button['label'] ??
                button['title'] ??
                button['buttonText'] ??
                button['button_text'] ??
                button['name'] ??
                '')
            .toString();
    final speechPhrase =
        button['speechPhrase'] ??
        button['speech_phrase'] ??
        button['speechText'];
    final customAudioFile =
        button['customAudioFile'] ?? button['custom_audio_file'];
    final llmQuery =
        button['LLMQuery'] ?? button['llmQuery'] ?? button['llm_query'];
    final queryType = button['queryType'] ?? button['query_type'];

    String? targetPage =
        (button['targetPage'] ??
                button['target_page'] ??
                button['targetNavigation'] ??
                button['target_navigation'] ??
                button['target navigation'] ??
                button['target'] ??
                button['pageName'] ??
                button['page_name'] ??
                button['destinationPage'] ??
                button['destination_page'] ??
                button['navigateTo'] ??
                button['navigate_to'])
            ?.toString();
    final specialPageRaw =
        (button['specialPage'] ??
                button['special_page'] ??
                button['special_function'] ??
                button['special function'] ??
                button['special_navigation'] ??
                button['special navigation'])
            ?.toString();
    if ((targetPage == null || targetPage.trim().isEmpty) &&
        specialPageRaw != null &&
        specialPageRaw.trim().isNotEmpty) {
      var specialPageNormalized = specialPageRaw.trim();
      if (specialPageNormalized.startsWith('!')) {
        specialPageNormalized = specialPageNormalized.substring(1);
      }
      specialPageNormalized = _normalizeSpecialPageName(specialPageNormalized);
      targetPage = '!$specialPageNormalized';
    }

    if (targetPage != null &&
        targetPage.trim().isNotEmpty &&
        targetPage.trim().startsWith('!')) {
      var normalizedSpecialTarget = targetPage.trim();
      normalizedSpecialTarget =
          '!${_normalizeSpecialPageName(normalizedSpecialTarget.substring(1).trim())}';
      targetPage = normalizedSpecialTarget;
    }

    var resolvedText = text;
    if (resolvedText.trim().isEmpty && targetPage == '!email') {
      resolvedText = 'Email';
    }

    final hiddenRaw =
        button['hidden'] ?? button['isHidden'] ?? button['is_hidden'];
    final hidden =
        hiddenRaw == true ||
        hiddenRaw == 1 ||
        hiddenRaw.toString().trim().toLowerCase() == 'true';

    button['text'] = resolvedText;
    button['speechPhrase'] = speechPhrase;
    button['customAudioFile'] = customAudioFile;
    button['LLMQuery'] = llmQuery;
    button['queryType'] = queryType;
    button['targetPage'] = targetPage;
    button['hidden'] = hidden;

    return button;
  }

  // Restore fetchGridData method for initial grid loading
  Future<void> fetchGridData() async {
    print('🎯🎯🎯 FETCH GRID DATA STARTED 🎯🎯🎯');
    setState(() {
      isLoading = true;
    });
    try {
      print('🎯 STEP 1: Making cruise ship safe request to fetch grid data...');
      print('🎯 URL: ${EnvironmentConfig.apiBaseUrl}/pages');
      print('🎯 User ID: ${widget.aacUserId}');
      print(
        '🔵 fetchGridData - CRITICAL DEBUG: API call will use X-User-ID header: ${widget.aacUserId}',
      );

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/pages',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        maxRetries: 3, // Multiple retries for cruise ship networks
        timeoutSeconds: 30,
      );

      print(
        '🎯 STEP 2: Grid data request completed with status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        print('🎯 ✅ Grid data fetch successful - parsing response...');
        final List<dynamic> data = json.decode(response.body);
        _cachedPagesPayload = data;
        print('🎯 📝 Received ${data.length} pages from API');

        Map<String, dynamic>? initialPage;
        if (data.isNotEmpty) {
          for (final page in data) {
            if (page is! Map) continue;
            final pageName = (page['name'] ?? page['pageName'] ?? '')
                .toString();
            if (pageName.trim().toLowerCase() == 'home') {
              initialPage = Map<String, dynamic>.from(page);
              break;
            }
          }
          initialPage ??= Map<String, dynamic>.from(data.first as Map);
        }

        if (initialPage != null && initialPage['buttons'] != null) {
          print('🎯 ✅ Found page with buttons - processing...');
          // --- Apply sorting to initial grid buttons ---
          final settingsProvider = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final int gridCols = settingsProvider.settings?.gridColumns ?? 10;
          List<Map<String, dynamic>> buttons = List<Map<String, dynamic>>.from(
            initialPage['buttons'] ?? [],
          ).map(_normalizeGridButton).toList();
          print('🎯 📝 Found ${buttons.length} total buttons');

          List<Map<String, dynamic>> visibleButtons = buttons
              .where(
                (btn) =>
                    (btn['hidden'] != true) &&
                    ((btn['text'] ?? '').toString().trim().isNotEmpty),
              )
              .toList();
          visibleButtons = _ensureEmailButtonVisible(buttons, visibleButtons);
          final emailCandidates = buttons.where(_isEmailSpecialButton).length;
          final emailVisible = visibleButtons
              .where(_isEmailSpecialButton)
              .length;
          print(
            '🎯 EMAIL DEBUG (initial): candidates=$emailCandidates, visible=$emailVisible, page=${(initialPage['name'] ?? initialPage['pageName'] ?? 'home')}',
          );
          print(
            '🎯 📝 ${visibleButtons.length} visible buttons after filtering',
          );

          visibleButtons.sort((a, b) {
            int rowA = int.tryParse(a['row']?.toString() ?? '0') ?? 0;
            int rowB = int.tryParse(b['row']?.toString() ?? '0') ?? 0;
            if (rowA != rowB) return rowA.compareTo(rowB);
            int colA = int.tryParse(a['col']?.toString() ?? '0') ?? 0;
            int colB = int.tryParse(b['col']?.toString() ?? '0') ?? 0;
            return colA.compareTo(colB);
          });
          for (int i = 0; i < visibleButtons.length; i++) {
            visibleButtons[i]['gridRow'] = (i ~/ gridCols);
            visibleButtons[i]['gridCol'] = (i % gridCols);
          }

          print('🎯 ✅ Grid buttons processed and sorted');
          setState(() {
            gridButtons = visibleButtons;
            currentPageName =
                (initialPage!['name'] ?? initialPage['pageName'] ?? 'home')
                    .toString();
            currentPageDisplayName =
                (initialPage['displayName'] ??
                        initialPage['display_name'] ??
                        currentPageName)
                    .toString();
            _showBottomStatusText = true;
            final wakeWordExample = _wakeWordVariants.isNotEmpty
                ? _wakeWordVariants.first
                : 'Hey Bravo';
            statusMessage =
                'Wake word listening active - say "$wakeWordExample"';
          });
          print('🎯 ✅ Grid state updated - starting scanning...');
          _maybeStartScanning();
        } else {
          print('🎯 ❌ No buttons found in page data');
          setState(() {
            gridButtons = [];
            currentPageName = 'home';
            currentPageDisplayName = 'Home';
            _showBottomStatusText = true;
            statusMessage = 'No grid data found.';
          });
        }
      } else {
        print(
          '🎯 ❌ Grid data fetch failed with status: ${response.statusCode}',
        );
        setState(() {
          gridButtons = [];
          _showBottomStatusText = true;
          statusMessage =
              'Error fetching grid. Status: ' + response.statusCode.toString();
        });
      }
    } catch (e) {
      print('🎯 ❌❌❌ GRID DATA FETCH EXCEPTION: $e');
      print('🎯 Exception type: ${e.runtimeType}');
      setState(() {
        gridButtons = [];
        _showBottomStatusText = true;
        statusMessage = 'Exception fetching grid: $e';
      });
    } finally {
      print('🎯 🏁 FETCH GRID DATA COMPLETED 🏁');
      setState(() {
        isLoading = false;
      });
    }
  }

  // Example usage in your admin button(s):
  // Replace:
  //   onPressed: () => Navigator.pushNamed(context, '/admin-settings'),
  // With:
  //   onPressed: () => _onAdminButtonPressed('/admin-settings'),

  // --- Auditory scanning and announcement routing ---

  /// Announce for grid scanning via personal audio (Bluetooth headphones) with selected voice
  Future<void> _speakPersonalVoice(String text) async {
    debugPrint('_speakPersonalVoice: Starting TTS for: $text');
    debugPrint(
      '_speakPersonalVoice: _settingsProvider is null? ${_settingsProvider == null}',
    );
    debugPrint(
      '_speakPersonalVoice: _settingsProvider.settings is null? ${_settingsProvider?.settings == null}',
    );

    // CRITICAL: Get the saved personal volume (use local override if available)
    final finalVolume = await _getEffectivePersonalVolume();
    final ttsVolume = (finalVolume / 10.0).clamp(0.0, 1.0);
    debugPrint(
      '_speakPersonalVoice: Effective personal volume = $finalVolume/10 (TTS: $ttsVolume)',
    );

    // CRITICAL: Always ensure audio routing is reset to default/personal before speaking
    // This ensures scanning announcements go to Bluetooth/default device, not built-in speaker
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        debugPrint(
          '_speakPersonalVoice: Routing audio to personal device (Bluetooth/default)...',
        );
        final platform = MethodChannel('audio_routing');
        if (Platform.isIOS) {
          // On iOS, use routeToPersonal to remove speaker override and route to Bluetooth
          await platform.invokeMethod('routeToPersonal');
        } else {
          await platform.invokeMethod('resetToDefault');
        }
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint(
          '_speakPersonalVoice: Audio routing to personal device completed',
        );
      } catch (e) {
        debugPrint(
          '_speakPersonalVoice: Audio routing reset failed (non-critical): $e',
        );
      }
    }

    // Wait for any ongoing announcements to complete before starting personal voice
    if (_isAnnouncementPlaying) {
      debugPrint(
        '_speakPersonalVoice: Waiting for ongoing announcement to complete...',
      );
      int waitCount = 0;
      while (_isAnnouncementPlaying && waitCount < 30) {
        // Max 3 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      debugPrint(
        '_speakPersonalVoice: Wait completed after ${waitCount * 100}ms',
      );
    }

    try {
      // Route audio to personal device (Bluetooth headphones) for scanning
      final audioDeviceProvider = Provider.of<AudioDeviceProvider>(
        context,
        listen: false,
      );
      if (!kIsWeb && Platform.isWindows) {
        debugPrint(
          '_speakPersonalVoice: Routing to personal device: ${audioDeviceProvider.personalDeviceId}',
        );
        await AudioDeviceService().playAudioToDevice(
          audioDeviceProvider.personalDeviceId ?? 'default',
          isPersonal: true,
        );
      }

      // For scanning audio, use simple local TTS to personal audio device (Bluetooth)
      // Don't use announceViaBackend for scanning - only for button selections
      await flutterTts.stop();
      await flutterTts.setSpeechRate(0.5); // Slower speech for clarity

      // Apply the admin personal volume setting as software volume on ALL platforms.
      // This ensures volume persists through Bluetooth disconnect/reconnect cycles
      // since software volume is independent of hardware/route state.
      // On Android, setApplicationVolume also sets the stream volume.
      // On iOS, the admin setting IS the software volume control.
      debugPrint(
        '_speakPersonalVoice: Setting TTS volume to $ttsVolume (personalVolume: $finalVolume/10)',
      );
      await flutterTts.setVolume(ttsVolume);

      await flutterTts.setPitch(1.0); // Normal pitch
      await flutterTts.speak(text);
      debugPrint(
        '_speakPersonalVoice: Local TTS completed with volume: $ttsVolume',
      );
    } catch (e) {
      debugPrint('_speakPersonalVoice: Local TTS failed: $e');
    }
  }

  Future<void> _speakSystemVoice(String text) async {
    final audioDeviceProvider = Provider.of<AudioDeviceProvider>(
      context,
      listen: false,
    );
    if (!kIsWeb && Platform.isWindows) {
      await AudioDeviceService().playAudioToDevice(
        audioDeviceProvider.systemDeviceId ?? 'default',
        isPersonal: false,
      );
    }

    // For iOS/Android, explicitly force speaker for system voice
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        final platform = MethodChannel('audio_routing');
        await platform.invokeMethod('forceSpeaker');
        // Small delay to let routing take effect
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('_speakSystemVoice: Failed to force speaker: $e');
      }
    }

    // For scanning audio, use basic TTS to default speaker (no forceSpeaker)
    debugPrint('_speakSystemVoice: Starting TTS for: $text');

    // AUDIO ROUTING FIX: Check if announcement is still playing and wait briefly if needed
    // This is more responsive than a fixed delay since it only waits when necessary
    if (_isAnnouncementPlaying) {
      debugPrint(
        '_speakSystemVoice: Announcement still playing, waiting for completion...',
      );
      int waitCount = 0;
      while (_isAnnouncementPlaying && waitCount < 10) {
        // Max 1 second (10 * 100ms)
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      debugPrint('_speakSystemVoice: Wait complete after ${waitCount * 100}ms');
    }

    try {
      await flutterTts.stop();
      // Configure TTS for Fire tablet compatibility
      await flutterTts.setSpeechRate(0.5); // Slower speech for clarity

      // Get system volume from settings
      final savedSystemVolume = await _getEffectiveSystemVolume();
      final ttsVolume = (savedSystemVolume / 10.0).clamp(0.0, 1.0);
      // Apply admin system volume setting as software volume on all platforms.
      // This ensures volume persists through Bluetooth disconnect/reconnect.
      debugPrint(
        '_speakSystemVoice: Setting TTS volume to $ttsVolume (systemVolume: $savedSystemVolume/10)',
      );
      await flutterTts.setVolume(ttsVolume);

      await flutterTts.setPitch(1.0); // Normal pitch
      debugPrint('_speakSystemVoice: Configured TTS settings');
      // Skip setVoice to avoid Fire tablet TTS voice errors
      await flutterTts.speak(text);
      debugPrint(
        '_speakSystemVoice: TTS speak() completed with volume: $ttsVolume',
      );
    } catch (e) {
      debugPrint('_speakSystemVoice: TTS ERROR - $e');

      // Fallback: Try native Android TTS via platform channel
      try {
        debugPrint('_speakSystemVoice: Trying native Android TTS fallback');

        // Use system volume setting
        final settings = _settingsProvider?.settings;
        final systemVolume =
            settings?.systemVolume ?? settings?.applicationVolume ?? 10;
        final volumeLevel = systemVolume / 10.0;

        final Map<String, dynamic> arguments = {
          'text': text,
          'rate': 0.5,
          'volume': volumeLevel,
          'pitch': 1.0,
        };
        await platform.invokeMethod('speakNativeTTS', arguments);
        debugPrint('_speakSystemVoice: Native Android TTS called successfully');
      } catch (nativeError) {
        debugPrint(
          '_speakSystemVoice: Native TTS fallback also failed: $nativeError',
        );
      }
    }
  }

  /// Fast local TTS announcement for voice prompts (faster and more reliable than backend)
  Future<void> announceLocal(String text) async {
    debugPrint('announceLocal: Starting TTS for: $text');

    try {
      // Force audio to built-in speaker (same as announceViaBackend)
      if (Platform.isIOS) {
        debugPrint('announceLocal: Before forceSpeaker (iOS)');
        await platform.invokeMethod('forceSpeaker');
      } else if (Platform.isAndroid) {
        debugPrint('announceLocal: Before forceSpeaker (Android)');
        try {
          await platform.invokeMethod('forceSpeaker');
          debugPrint('Android forceSpeaker call completed successfully');
        } catch (e) {
          debugPrint('Android forceSpeaker call FAILED: $e');
        }
      }

      await flutterTts.stop();
      // Configure TTS for normal speech rate (not the slow 0.5 used for grid scanning)
      await flutterTts.setSpeechRate(
        0.75,
      ); // Slightly slower than normal for clarity

      // Use system volume setting for announcements
      final settings = _settingsProvider?.settings;
      final systemVolume =
          settings?.systemVolume ?? settings?.applicationVolume ?? 10;
      final volumeLevel = systemVolume / 10.0;
      // Apply admin system volume setting as software volume on all platforms.
      // This ensures volume persists through Bluetooth disconnect/reconnect.
      debugPrint(
        'announceLocal: Setting volume to $volumeLevel (Level: $systemVolume/10)',
      );
      await flutterTts.setVolume(volumeLevel);

      await flutterTts.setPitch(1.0); // Normal pitch
      debugPrint('announceLocal: Configured TTS settings');

      await flutterTts.speak(text);
      debugPrint('announceLocal: TTS speak() completed successfully');
    } catch (e) {
      debugPrint('announceLocal: TTS ERROR - $e');
    }
  }

  // --- SPEECH BUBBLE OVERLAY METHODS ---

  /// Show speech bubble overlay with announcement text
  void _showSpeechBubbleOverlay(String text) {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );

    // Check if speech bubble feature is enabled
    if (settingsProvider.settings?.displaySplash != true) {
      return; // Feature is disabled
    }

    // Cancel any existing timer
    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = true;
        _speechBubbleText = text;
      });
    }

    // Get duration from settings (default 3000ms)
    final duration = settingsProvider.settings?.displaySplashtime ?? 3000;

    // Auto-hide after specified duration
    _speechBubbleTimer = Timer(Duration(milliseconds: duration), () {
      _hideSpeechBubbleOverlay();
    });

    debugPrint('Speech bubble displayed for ${duration}ms: "$text"');
  }

  /// Hide speech bubble overlay
  void _hideSpeechBubbleOverlay() {
    _speechBubbleTimer?.cancel();

    if (mounted) {
      setState(() {
        _showSpeechBubble = false;
        _speechBubbleText = '';
      });
    }

    debugPrint('Speech bubble hidden');
  }

  /// Simplified announcement based on POC approach - zero delays, minimal routing
  Future<void> announceViaBackendSimple(
    String text, {
    String routing = 'system',
    int? speechRate,
    bool preserveMicrophoneSession =
        false, // NEW: Don't reset audio during question listening
  }) async {
    try {
      // Android notification sounds suppressed globally

      // Show speech bubble overlay if enabled in settings
      _showSpeechBubbleOverlay(text);

      // Set announcement playing flag to suppress chirps
      _isAnnouncementPlaying = true;

      String idToken = widget.idToken;
      final aacUserId = widget.aacUserId;

      // Refresh token using cached token from AuthenticatedHttpClient
      try {
        final token = await AuthenticatedHttpClient.getRefreshedIdToken();
        if (token != null && token.isNotEmpty) {
          idToken = token;
        }
      } catch (e) {
        // Continue with original token
      }

      // Request backend audio
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/play-audio'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': text,
          'routing_target': routing,
          if (speechRate != null) 'speech_rate': speechRate,
        }),
      );

      bool backendAudioPlayed = false;

      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final base64Audio =
            RegExp(
              '"audio_data"\\s*:\\s*"([^"]+)"',
            ).firstMatch(jsonStr)?.group(1) ??
            RegExp(
              '"audioContent"\\s*:\\s*"([^"]+)"',
            ).firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);

        if (base64Audio != null && base64Audio.isNotEmpty) {
          final player = AudioPlayer();

          try {
            // Simple audio routing like POC - force speaker before playing
            if (!kIsWeb && Platform.isIOS) {
              await platform.invokeMethod('forceSpeaker');
            }

            // Stop scanning for system announcements
            if (routing == 'system') {
              _stopAuditoryScanning();
            }

            // Play audio directly without warmup
            final bytes = base64Decode(base64Audio);
            final tempDir = Directory.systemTemp;
            final tempFile = await File(
              '${tempDir.path}/backend_tts.mp3',
            ).create();
            await tempFile.writeAsBytes(bytes, flush: true);
            await player.setFilePath(tempFile.path);
            await player.play();

            // Only reset to default if NOT preserving microphone session
            if (!kIsWeb && Platform.isIOS && !preserveMicrophoneSession) {
              await platform.invokeMethod('resetToDefault');
            } else if (preserveMicrophoneSession) {
              print('Preserving microphone session - skipping resetToDefault');
            }

            backendAudioPlayed = true;
          } catch (e) {
            print('Audio playback failed: $e');
          } finally {
            player.dispose();
          }
        }
      }

      // Simple TTS fallback if backend audio failed
      if (!backendAudioPlayed) {
        if (routing == 'system' && !kIsWeb && Platform.isIOS) {
          await platform.invokeMethod('forceSpeaker');
        }

        await flutterTts.speak(text);

        // Only reset if we're not preserving microphone session
        if (!preserveMicrophoneSession &&
            routing == 'system' &&
            !kIsWeb &&
            Platform.isIOS) {
          await platform.invokeMethod('resetToDefault');
        }
      }
    } catch (e) {
      print('announceViaBackendSimple: Exception: $e');
      // Simple fallback with improved TTS completion detection
      try {
        final ttsCompleter = Completer<void>();
        flutterTts.setCompletionHandler(() {
          if (!ttsCompleter.isCompleted) ttsCompleter.complete();
        });
        await flutterTts.speak(text);

        // Wait for completion with a dynamic safety timeout based on announcement length
        final wordCount = text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        final estimatedDurationMs = (wordCount * 700) + 3000;
        final timeout = Duration(
          milliseconds: estimatedDurationMs.clamp(5000, 60000),
        );

        try {
          await ttsCompleter.future.timeout(timeout);
        } on TimeoutException {
          debugPrint(
            '⚠️ announceViaBackendSimple: TTS completion timeout - forcing completion',
          );
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        }

        flutterTts.setCompletionHandler(() {});
      } catch (ttsError) {
        debugPrint('announceViaBackendSimple: TTS fallback error: $ttsError');
      }
    } finally {
      _isAnnouncementPlaying = false;

      // Android notification sounds managed globally
    }
  }

  /// Timeout wrapper for announceViaBackend to prevent app freezing
  Future<void> _announceWithTimeout(
    String text, {
    String routing = 'system',
    int? speechRate,
    Duration timeout = const Duration(
      seconds: 30,
    ), // Increased from 15s to 30s for longer jokes/announcements
  }) async {
    try {
      debugPrint(
        '_announceWithTimeout: Starting announcement with ${timeout.inSeconds}s timeout: "$text"',
      );

      await announceViaBackend(
        text,
        routing: routing,
        speechRate: speechRate,
      ).timeout(
        timeout,
        onTimeout: () {
          debugPrint(
            '🚨 ANNOUNCEMENT TIMEOUT: announceViaBackend timed out after ${timeout.inSeconds} seconds for: "$text"',
          );
          debugPrint(
            '🚨 TIMEOUT RECOVERY: Starting comprehensive audio system reset...',
          );

          // CRITICAL: Reset audio session initialization flag so next announcement will reinitialize
          _audioSessionInitialized = false;
          debugPrint(
            '🚨 TIMEOUT RECOVERY: Reset _audioSessionInitialized flag for fresh audio system setup',
          );

          // Clear the announcement flag to prevent permanent blocking
          _isAnnouncementPlaying = false;
          debugPrint(
            '🚨 TIMEOUT RECOVERY: Cleared _isAnnouncementPlaying flag',
          );

          // Try to stop any ongoing audio players synchronously
          try {
            flutterTts.stop();
            debugPrint('🚨 TIMEOUT RECOVERY: Stopped FlutterTTS');
          } catch (e) {
            debugPrint('🚨 TIMEOUT RECOVERY: Error stopping TTS: $e');
          }

          // Try to reset audio routing if possible (synchronous)
          try {
            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              platform.invokeMethod('resetToDefault');
              debugPrint('🚨 TIMEOUT RECOVERY: Reset audio routing to default');
            }
          } catch (e) {
            debugPrint(
              '🚨 TIMEOUT RECOVERY: Error resetting audio routing: $e',
            );
          }

          // Resume keyboard focus if needed
          if (gridFocusNode != null) {
            gridFocusNode!.requestFocus();
            debugPrint('🚨 TIMEOUT RECOVERY: Restored keyboard focus');
          }

          // Schedule comprehensive recovery to run after the timeout exception is handled
          // This ensures the async operations don't interfere with the timeout flow
          Future.delayed(const Duration(milliseconds: 100), () async {
            await _performTimeoutRecovery();
          });

          debugPrint(
            '🚨 TIMEOUT RECOVERY: Immediate recovery completed, comprehensive recovery scheduled',
          );
          throw TimeoutException(
            'Announcement timed out after ${timeout.inSeconds} seconds',
            timeout,
          );
        },
      );

      debugPrint(
        '_announceWithTimeout: Announcement completed successfully within timeout',
      );
    } catch (e) {
      if (e is TimeoutException) {
        debugPrint(
          '🚨 _announceWithTimeout: Announcement timed out - showing user notification',
        );

        // Show user-friendly error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Audio announcement timed out. The app is still working normally.',
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        debugPrint('🚨 _announceWithTimeout: Error during announcement: $e');
        rethrow; // Re-throw non-timeout exceptions
      }
    }
  }

  /// Comprehensive audio system reset - call this on ANY audio error to ensure clean recovery
  Future<void> _resetAudioSystem({String reason = 'error'}) async {
    try {
      debugPrint(
        '🔄 AUDIO RESET: Starting comprehensive audio system reset (reason: $reason)...',
      );

      // CRITICAL: Force clear all flags to prevent stuck state
      _isAnnouncementPlaying = false;
      _audioSessionInitialized = false;
      debugPrint('🔄 AUDIO RESET: Cleared all audio flags');

      // Stop ALL audio immediately
      try {
        await flutterTts.stop();
        debugPrint('🔄 AUDIO RESET: Stopped FlutterTTS');
      } catch (e) {
        debugPrint('🔄 AUDIO RESET: Error stopping TTS: $e');
      }

      // CRITICAL: Stop and dispose ALL tracked AudioPlayer instances to free AudioTrack resources
      if (_activeAudioPlayers.isNotEmpty) {
        debugPrint(
          '🔄 AUDIO RESET: Disposing ${_activeAudioPlayers.length} active AudioPlayer instances...',
        );
        for (final player in _activeAudioPlayers) {
          try {
            await player.stop();
            await player.dispose();
          } catch (e) {
            debugPrint('🔄 AUDIO RESET: Error disposing player: $e');
          }
        }
        _activeAudioPlayers.clear();
        debugPrint(
          '🔄 AUDIO RESET: All AudioPlayer instances disposed and cleared',
        );
      } else {
        debugPrint(
          '🔄 AUDIO RESET: No active AudioPlayer instances to dispose',
        );
      }

      // Reset audio routing completely
      try {
        if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
          final platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
          debugPrint('🔄 AUDIO RESET: Audio routing reset to default');

          // Give audio system time to settle
          await Future.delayed(const Duration(milliseconds: 300));
          debugPrint('🔄 AUDIO RESET: Audio routing settlement complete');
        }
      } catch (e) {
        debugPrint('🔄 AUDIO RESET: Error resetting audio routing: $e');
      }

      // Restore Android notification sounds if needed
      if (!kIsWeb && Platform.isAndroid) {
        try {
          const platform = MethodChannel('audio_routing');
          platform.invokeMethod('restoreNotificationSounds');
          debugPrint('🔄 AUDIO RESET: Notification sounds restored');
        } catch (e) {
          debugPrint('🔄 AUDIO RESET: Error restoring notifications: $e');
        }
      }

      debugPrint(
        '🔄 AUDIO RESET: Comprehensive audio system reset completed successfully',
      );
    } catch (e) {
      debugPrint('🔄 AUDIO RESET: Error during audio system reset: $e');
    }
  }

  /// Create and track an AudioPlayer to ensure it gets disposed properly
  AudioPlayer _createTrackedAudioPlayer(String purpose) {
    final player = AudioPlayer();
    _activeAudioPlayers.add(player);
    debugPrint(
      '🎵 Created AudioPlayer for: $purpose (Total active: ${_activeAudioPlayers.length})',
    );
    return player;
  }

  /// Dispose and untrack an AudioPlayer
  Future<void> _disposeAudioPlayer(AudioPlayer player, String purpose) async {
    try {
      await player.stop();
      await player.dispose();
      _activeAudioPlayers.remove(player);
      debugPrint(
        '🎵 Disposed AudioPlayer for: $purpose (Remaining active: ${_activeAudioPlayers.length})',
      );
    } catch (e) {
      debugPrint('🎵 Error disposing AudioPlayer for $purpose: $e');
      _activeAudioPlayers.remove(player); // Remove even if dispose fails
    }
  }

  /// Comprehensive timeout recovery to reset audio system and restart scanning if needed
  Future<void> _performTimeoutRecovery() async {
    try {
      debugPrint(
        '🔄 TIMEOUT RECOVERY: Starting comprehensive audio and scanning recovery...',
      );

      // Use the comprehensive audio reset function
      await _resetAudioSystem(reason: 'timeout');

      // Check if scanning needs to be restarted and we're still mounted
      if (!mounted) {
        debugPrint(
          '🔄 TIMEOUT RECOVERY: Widget not mounted, canceling recovery',
        );
        return;
      }

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final enableScanning =
          settingsProvider.settings?.enableAuditoryScanning ?? false;

      if (enableScanning && !isScanning) {
        debugPrint(
          '🔄 TIMEOUT RECOVERY: Scanning was enabled but stopped, restarting scanning...',
        );

        // Add delay before restarting scanning to ensure audio system is fully reset
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted && !isScanning) {
          // Double-check we're still mounted and scanning is still off
          _startAuditoryScanning();
          debugPrint('🔄 TIMEOUT RECOVERY: Scanning restarted successfully');
        } else {
          debugPrint(
            '🔄 TIMEOUT RECOVERY: Scanning restart skipped - widget unmounted or scanning already active',
          );
        }
      } else {
        debugPrint(
          '🔄 TIMEOUT RECOVERY: Scanning status: enableScanning=$enableScanning, isScanning=$isScanning',
        );
      }

      debugPrint(
        '🔄 TIMEOUT RECOVERY: Comprehensive recovery completed successfully',
      );
    } catch (e) {
      debugPrint(
        '🔄 TIMEOUT RECOVERY: Error during comprehensive recovery: $e',
      );
    }
  }

  /// Announce using the backend TTS (selected voice, correct routing)
  Future<void> announceViaBackend(
    String text, {
    String routing = 'system',
    int? speechRate, // Optional speech rate override
    bool showSpeechBubble =
        true, // Allow caller to disable speech bubble (for games page)
  }) async {
    final announceStart = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
      '[TIMER] ANNOUNCE START: announceViaBackend("$text") at $announceStart',
    );
    // Pause keyboard listener during announcement
    if (gridFocusNode != null) {
      gridFocusNode!.unfocus();
    }

    // Handle [PAUSE] markers (used in jokes and other content)
    if (text.contains('[PAUSE]')) {
      final parts = text
          .split('[PAUSE]')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      for (int i = 0; i < parts.length; i++) {
        await announceViaBackend(
          parts[i],
          routing: routing,
          speechRate: speechRate,
          showSpeechBubble: showSpeechBubble,
        );
        if (i < parts.length - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
      return;
    }

    // Special handling for jokes - detect if text contains a question followed by an answer
    final jokePattern = RegExp(r'^(.+\?)\s*(.+[!.])$');
    final jokeMatch = jokePattern.firstMatch(text);

    if (jokeMatch != null) {
      final question = jokeMatch.group(1)?.trim() ?? '';
      final punchline = jokeMatch.group(2)?.trim() ?? '';

      debugPrint('JOKE DETECTED: Question="$question" Punchline="$punchline"');

      // Announce the question first
      await announceViaBackend(
        question,
        routing: routing,
        speechRate: speechRate,
      );

      // Add a 0.5-second pause (reduced from 1.5s due to existing built-in delays)
      await Future.delayed(Duration(milliseconds: 500));

      // Then announce the punchline
      await announceViaBackend(
        punchline,
        routing: routing,
        speechRate: speechRate,
      );

      return; // Exit early for jokes
    }

    String idToken = widget.idToken;
    final aacUserId = widget.aacUserId;
    try {
      // Android notification sounds suppressed globally

      // CRITICAL SAFEGUARD: Detect if we're entering with flag already set (hung state)
      if (_isAnnouncementPlaying) {
        debugPrint(
          '⚠️ announceViaBackend: WARNING - Entering with _isAnnouncementPlaying already true!',
        );
        debugPrint(
          '⚠️ announceViaBackend: This indicates a previous announcement didn\'t complete properly',
        );
        debugPrint(
          '⚠️ announceViaBackend: Force clearing flag and resetting audio session...',
        );

        // Force clear the stuck flag
        _isAnnouncementPlaying = false;

        // Reset audio session to ensure clean state
        _audioSessionInitialized = false;

        // Stop any stuck TTS
        try {
          await flutterTts.stop();
        } catch (e) {
          debugPrint('⚠️ announceViaBackend: Error stopping stuck TTS: $e');
        }

        // Small delay to let audio system settle
        await Future.delayed(const Duration(milliseconds: 200));
        debugPrint(
          '⚠️ announceViaBackend: Recovery completed, proceeding with announcement',
        );
      }

      // Set announcement playing flag to suppress chirps
      _isAnnouncementPlaying = true;

      // CRITICAL: Always ensure audio routing is reset to default before each announcement
      // This prevents Android AudioFlinger from getting stuck in forceSpeaker mode
      debugPrint(
        'announceViaBackend: Resetting audio routing to default before announcement...',
      );
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
          debugPrint('announceViaBackend: Audio routing reset completed');
          // Small delay to let audio routing fully settle
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint(
            'announceViaBackend: Audio routing reset failed (non-critical): $e',
          );
        }
      }

      // Initialize audio session on first use (fixes "Test" button issue on first app launch)
      if (!_audioSessionInitialized) {
        debugPrint(
          'announceViaBackend: First call, initializing audio session...',
        );
        await _initializeAudioSession();
        _audioSessionInitialized = true;
      }

      final startTotal = DateTime.now();

      debugPrint(
        '[TIMER] announceViaBackend: START for "$text" at ${startTotal.millisecondsSinceEpoch}',
      );
      // Use cached token from AuthenticatedHttpClient instead of forcing refresh
      try {
        final token = await AuthenticatedHttpClient.getRefreshedIdToken();
        if (token != null && token.isNotEmpty) {
          idToken = token;
        }
      } catch (e) {
        debugPrint(
          'announceViaBackend: Could not get fresh token: $e, using original token',
        );
        // Continue with original token - don't fail the entire function
      }

      bool backendAudioPlayed = false;
      final startRequest = DateTime.now();
      debugPrint(
        '[TIMER] announceViaBackend: Requesting backend audio for "$text" at ${startRequest.millisecondsSinceEpoch}',
      );
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/play-audio'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': text,
          'routing_target': routing,
          if (speechRate != null) 'speech_rate': speechRate,
        }),
      );
      final endRequest = DateTime.now();
      debugPrint(
        '[TIMER] announceViaBackend: Backend response received at ${endRequest.millisecondsSinceEpoch} (delta: ${endRequest.difference(startRequest).inMilliseconds} ms)',
      );
      debugPrint(
        'announceViaBackend: Response status: \\${response.statusCode}',
      );
      if (response.statusCode == 200) {
        final jsonStr = response.body;
        final audioUrl = RegExp(
          '"audio_url"\s*:\s*"([^"]+)"',
        ).firstMatch(jsonStr)?.group(1);
        final base64Audio =
            RegExp(
              '"audio_data"\\s*:\\s*"([^"]+)"',
            ).firstMatch(jsonStr)?.group(1) ??
            RegExp(
              '"audioContent"\\s*:\\s*"([^"]+)"',
            ).firstMatch(jsonStr)?.group(1) ??
            RegExp('"audio"\\s*:\\s*"([^"]+)"').firstMatch(jsonStr)?.group(1);
        try {
          if (!kIsWeb && Platform.isIOS) {
            final platform = MethodChannel('audio_routing');
            final player = _createTrackedAudioPlayer('iOS announcement');
            await flutterTts.stop();
            await player.stop();

            // AUDIO ROUTING: Force to built-in speaker for system announcements
            debugPrint(
              '[TIMER] announceViaBackend: Setting speaker routing once (iOS) at ${DateTime.now().millisecondsSinceEpoch}',
            );
            await platform.invokeMethod('forceSpeaker');

            // Apply admin system volume as software volume on iOS.
            // This ensures volume persists through Bluetooth disconnect/reconnect
            // since software volume is independent of hardware route state.
            final settings = _settingsProvider?.settings;
            final systemVolume =
                settings?.systemVolume ?? settings?.applicationVolume ?? 10;
            final iOSVolumeLevel = systemVolume / 10.0;
            debugPrint(
              'announceViaBackend: Setting iOS player volume to $iOSVolumeLevel (systemVolume: $systemVolume/10)',
            );
            await player.setVolume(iOSVolumeLevel);

            // Show speech bubble overlay RIGHT BEFORE the stabilization delay
            // This provides immediate visual feedback while audio routing stabilizes
            if (showSpeechBubble) {
              _showSpeechBubbleOverlay(text);
            }

            // Wait for audio routing to fully stabilize to prevent audio cutoff
            debugPrint(
              'iOS: Waiting for audio routing to stabilize (v1.0.2+10 Extended Delay)...',
            );
            await Future.delayed(
              const Duration(milliseconds: 600),
            ); // Increased from 300ms for Play Store
            debugPrint(
              'iOS: Audio routing stabilization complete (v1.0.2+10 Extended Delay)',
            );

            // Only stop scanning for system announcements (button selections), not personal announcements (scanning audio)
            if (routing == 'system') {
              debugPrint(
                'Stopping scanning before system audio playback (button selection)',
              );
              _stopAuditoryScanning();
            } else {
              debugPrint(
                'Not stopping scanning for personal audio playback (scanning audio)',
              );
            }

            // --- PREFER BASE64 AUDIO OVER AUDIOURL ---
            if (base64Audio != null && base64Audio.isNotEmpty) {
              debugPrint(
                'announceViaBackend: Playing base64 audio (preferred)',
              );
              final base64Start = DateTime.now();
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File(
                '${tempDir.path}/backend_tts.mp3',
              ).create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);
              // --- Wait for playback to finish ---
              final completer = Completer<void>();
              final sub = player.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) completer.complete();
                }
              });
              await player.play();
              await completer.future;
              await sub.cancel();
              final base64End = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: After base64 audio playback at ${base64End.millisecondsSinceEpoch} (delta: ${base64End.difference(base64Start).inMilliseconds} ms)',
              );
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              try {
                debugPrint(
                  '[TIMER] announceViaBackend: Before setUrl/play audioUrl at ${DateTime.now().millisecondsSinceEpoch}',
                );
                final audioUrlStart = DateTime.now();
                await player.setUrl(audioUrl);
                // --- Wait for playback to finish ---
                final completer = Completer<void>();
                final sub = player.playerStateStream.listen((state) {
                  if (state.processingState == ProcessingState.completed) {
                    if (!completer.isCompleted) completer.complete();
                  }
                });
                await player.play();
                await completer.future;
                await sub.cancel();
                final audioUrlEnd = DateTime.now();
                debugPrint(
                  '[TIMER] announceViaBackend: After audioUrl playback at ${audioUrlEnd.millisecondsSinceEpoch} (delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms)',
                );
                backendAudioPlayed = true;
              } catch (e) {
                debugPrint(
                  'announceViaBackend: setUrl/play failed for audioUrl: $e',
                );
              }
            } else {
              debugPrint(
                'announceViaBackend: No audio_url or base64 audio found in response',
              );
            }

            // Route back to personal device (Bluetooth) after system announcement is complete
            // Use routeToPersonal instead of resetToDefault to keep session active for BT
            debugPrint(
              'iOS: Routing back to personal device (Bluetooth) after system announcement',
            );
            await platform.invokeMethod('routeToPersonal');

            // Dispose the player to free AudioTrack resources
            await _disposeAudioPlayer(player, 'iOS announcement');
          } else if (!kIsWeb && Platform.isWindows) {
            // Show speech bubble overlay immediately for Windows
            if (showSpeechBubble) {
              _showSpeechBubbleOverlay(text);
            }

            // AUDIO PRIMING: Play silence.mp3 first to wake up the audio system
            debugPrint('Windows: Priming audio system with silence.mp3...');
            try {
              final primingPlayer = AudioPlayer();
              await primingPlayer.setAsset('assets/silence.mp3');

              // Use timeout to prevent app crashes if silence.mp3 fails
              await primingPlayer.play().timeout(
                const Duration(milliseconds: 2000),
                onTimeout: () {
                  debugPrint(
                    'Windows: silence.mp3 priming timed out, continuing anyway',
                  );
                },
              );

              // Wait for silence playbook to complete with timeout
              final completer = Completer<void>();
              StreamSubscription? sub;

              sub = primingPlayer.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) {
                    completer.complete();
                    sub?.cancel();
                  }
                }
              });

              await completer.future.timeout(
                const Duration(milliseconds: 1000),
                onTimeout: () {
                  debugPrint(
                    'Windows: silence.mp3 completion timed out, continuing anyway',
                  );
                  sub?.cancel();
                },
              );

              await primingPlayer.dispose();
              debugPrint(
                'Windows: Audio priming with silence.mp3 completed successfully',
              );
            } catch (e) {
              debugPrint(
                'Windows: Audio priming with silence.mp3 failed: $e, continuing anyway',
              );
            }

            // Use AudioDeviceService for Windows
            final audioDeviceService = AudioDeviceService();
            await audioDeviceService.initialize();
            debugPrint(
              'announceViaBackend: Using AudioDeviceService for TTS playback with system device routing',
            );
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              await audioDeviceService.playTTSAudio(
                base64Audio,
                isPersonal: false,
              );
              final base64End = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: Windows base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms',
              );
              backendAudioPlayed = true;
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              final player = _createTrackedAudioPlayer('Windows audioUrl');
              final audioUrlStart = DateTime.now();
              await player.setUrl(audioUrl);
              await player.play();
              final audioUrlEnd = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: Windows audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms',
              );
              backendAudioPlayed = true;
              await _disposeAudioPlayer(player, 'Windows audioUrl');
            }
          } else if (!kIsWeb && Platform.isAndroid) {
            final platform = MethodChannel('audio_routing');
            final player = _createTrackedAudioPlayer('Android announcement');
            await flutterTts.stop();
            await player.stop();

            // SIMPLIFIED AUDIO ROUTING: Set speaker once and play without switching
            debugPrint(
              '[TIMER] announceViaBackend: Setting speaker routing once (Android) at ${DateTime.now().millisecondsSinceEpoch}',
            );
            try {
              await platform.invokeMethod('forceSpeaker');
              debugPrint('Android forceSpeaker call completed successfully');

              // Show speech bubble overlay RIGHT BEFORE the stabilization delay
              // This provides immediate visual feedback while audio routing stabilizes
              if (showSpeechBubble) {
                _showSpeechBubbleOverlay(text);
              }

              // Wait for audio routing to fully stabilize to prevent audio cutoff
              debugPrint(
                'Android: Waiting for audio routing to stabilize (v1.0.2+15 Extended Delay)...',
              );
              await Future.delayed(
                const Duration(milliseconds: 1200),
              ); // Dramatically increased for Play Store
              debugPrint(
                'Android: Audio routing stabilization complete (v1.0.2+15 Extended Delay)',
              );

              // CRITICAL FIX: Audio priming AFTER forceSpeaker to prime the correct audio device
              // This ensures we prime the built-in speaker, not headphones/Bluetooth
              debugPrint(
                'Android: AGGRESSIVE audio priming on SPEAKER device for Play Store build compatibility...',
              );
              try {
                // Strategy 1: Immediate short burst to wake speaker system
                final quickPrimingPlayer = AudioPlayer();
                await quickPrimingPlayer.setAsset('assets/silence.mp3');
                await quickPrimingPlayer.play();
                await quickPrimingPlayer.dispose();
                debugPrint('Android: Quick speaker silence burst completed');

                // Strategy 2: Longer 1-second priming with enhanced timeout handling on speaker
                final earlyPrimingPlayer = AudioPlayer();
                await earlyPrimingPlayer.setAsset('assets/silence_1000MS.mp3');

                // Use timeout to prevent app crashes if silence file fails
                await earlyPrimingPlayer.play().timeout(
                  const Duration(milliseconds: 3000),
                  onTimeout: () {
                    debugPrint(
                      'Android: 1-second speaker silence priming timed out, continuing anyway',
                    );
                  },
                );

                // Wait for the full 1-second silence playback to complete with timeout
                final completer = Completer<void>();
                StreamSubscription? sub;

                sub = earlyPrimingPlayer.playerStateStream.listen((state) {
                  if (state.processingState == ProcessingState.completed) {
                    if (!completer.isCompleted) {
                      completer.complete();
                      sub?.cancel();
                    }
                  }
                });

                await completer.future.timeout(
                  const Duration(
                    milliseconds: 2000,
                  ), // Should complete in ~1 second
                  onTimeout: () {
                    debugPrint(
                      'Android: 1-second speaker silence completion timed out, continuing anyway',
                    );
                    sub?.cancel();
                  },
                );

                await earlyPrimingPlayer.dispose();
                debugPrint(
                  'Android: 1-second speaker silence audio priming completed successfully',
                );

                // Strategy 3: Additional short silence for Play Store builds
                // This addresses the 5-second gap issue reported by user
                final finalPrimingPlayer = AudioPlayer();
                await finalPrimingPlayer.setAsset('assets/silence.mp3');
                await finalPrimingPlayer.play();
                await finalPrimingPlayer.dispose();
                debugPrint(
                  'Android: Final speaker priming burst completed - SPEAKER audio system fully primed',
                );
              } catch (e) {
                debugPrint(
                  'Android: Aggressive SPEAKER audio priming failed: $e, continuing anyway',
                );
              }
            } catch (e) {
              debugPrint('Android forceSpeaker call FAILED: $e');
            }

            debugPrint('Stopping scanning before backend audio playback');
            _stopAuditoryScanning();

            // --- PRIORITIZE BASE64 AUDIO (FASTER) OVER AUDIO URL ---
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              debugPrint(
                '*** ANDROID: Using base64 audio (PREFERRED - faster than audioUrl) ***',
              );
              try {
                final bytes = base64Decode(base64Audio);
                final tempDir = Directory.systemTemp;
                final tempFile = await File(
                  '${tempDir.path}/backend_tts.mp3',
                ).create();
                await tempFile.writeAsBytes(bytes, flush: true);
                await player.setFilePath(tempFile.path);

                // Use system volume setting for backend audio
                final settings = _settingsProvider?.settings;
                final systemVolume =
                    settings?.systemVolume ?? settings?.applicationVolume ?? 10;
                final volumeLevel = systemVolume / 10.0;
                debugPrint(
                  'announceViaBackend: Setting Android base64 player volume to $volumeLevel (Level: $systemVolume/10)',
                );
                await player.setVolume(volumeLevel);

                // Additional delay before starting playback to prevent cutoff
                debugPrint(
                  'Android: Adding pre-playback delay for audio cutoff prevention...',
                );
                await Future.delayed(const Duration(milliseconds: 200));
                debugPrint(
                  'Android: Pre-playback delay complete, starting audio...',
                );

                // --- Wait for playback to finish ---
                // CRITICAL FIX: Don't rely solely on ProcessingState.completed
                // For audio with pauses (like jokes), we need to check position vs duration
                final completer = Completer<void>();
                final sub = player.playerStateStream.listen((state) async {
                  if (state.processingState == ProcessingState.completed) {
                    // Double-check: verify we're truly at the end by comparing position and duration
                    final duration = await player.duration;
                    final position = await player.position;

                    // Allow 200ms tolerance for completion detection
                    final remainingMs =
                        (duration?.inMilliseconds ?? 0) -
                        position.inMilliseconds;
                    if (remainingMs <= 200) {
                      debugPrint(
                        'Android base64: Audio truly completed (position: ${position.inSeconds}s, duration: ${duration?.inSeconds ?? 0}s)',
                      );
                      if (!completer.isCompleted) completer.complete();
                    } else {
                      debugPrint(
                        'Android base64: False completion detected - ${remainingMs}ms remaining, continuing playback',
                      );
                    }
                  }
                });
                await player.play();
                await completer.future;
                await sub.cancel();
                final base64End = DateTime.now();
                debugPrint(
                  '[TIMER] announceViaBackend: Android base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms',
                );
                backendAudioPlayed = true;
              } catch (e) {
                debugPrint(
                  '[ERROR] Android: Exception during base64 audio playback: $e',
                );
                backendAudioPlayed = false;
              }
            } else if (audioUrl != null && audioUrl.isNotEmpty) {
              final audioUrlStart = DateTime.now();
              debugPrint(
                '*** ANDROID: Fallback to audioUrl (slower than base64) for: $audioUrl ***',
              );
              try {
                await player.setUrl(audioUrl);

                // Use system volume setting for backend audio
                final settings = _settingsProvider?.settings;
                final systemVolume =
                    settings?.systemVolume ?? settings?.applicationVolume ?? 10;
                final volumeLevel = systemVolume / 10.0;
                debugPrint(
                  'announceViaBackend: Setting Android URL player volume to $volumeLevel (Level: $systemVolume/10)',
                );
                await player.setVolume(volumeLevel);

                // --- Wait for playback to finish ---
                // CRITICAL FIX: Don't rely solely on ProcessingState.completed
                // For audio with pauses (like jokes), we need to check position vs duration
                final completer = Completer<void>();
                final sub = player.playerStateStream.listen((state) async {
                  if (state.processingState == ProcessingState.completed) {
                    // Double-check: verify we're truly at the end by comparing position and duration
                    final duration = await player.duration;
                    final position = await player.position;

                    // Allow 200ms tolerance for completion detection
                    final remainingMs =
                        (duration?.inMilliseconds ?? 0) -
                        position.inMilliseconds;
                    if (remainingMs <= 200) {
                      debugPrint(
                        'Android audioUrl: Audio truly completed (position: ${position.inSeconds}s, duration: ${duration?.inSeconds ?? 0}s)',
                      );
                      if (!completer.isCompleted) completer.complete();
                    } else {
                      debugPrint(
                        'Android audioUrl: False completion detected - ${remainingMs}ms remaining, continuing playback',
                      );
                    }
                  }
                });
                await player.play();
                await completer.future;
                await sub.cancel();
                debugPrint(
                  '*** ANDROID: AudioUrl playback completed successfully ***',
                );
                backendAudioPlayed = true;
              } catch (e) {
                debugPrint(
                  '[ERROR] Android: Exception during audioUrl playback: $e',
                );
                backendAudioPlayed = false;
              }
              final audioUrlEnd = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: Android audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms',
              );
            }

            // Reset to default routing only after all audio is complete
            debugPrint(
              'Android: Resetting to default routing after audio complete',
            );
            try {
              await platform.invokeMethod('resetToDefault');
              debugPrint('Android resetToDefault call completed successfully');
            } catch (e) {
              debugPrint('Android resetToDefault call FAILED: $e');
            }

            // Dispose the player to free AudioTrack resources
            await _disposeAudioPlayer(player, 'Android announcement');
          } else {
            // Fallback: try just_audio (Web or other platforms)
            debugPrint(
              'announceViaBackend: Using fallback just_audio for Web/other platforms',
            );

            // Show speech bubble overlay immediately for fallback platforms
            if (showSpeechBubble) {
              _showSpeechBubbleOverlay(text);
            }

            // AUDIO PRIMING: Play silence.mp3 first to wake up the audio system
            debugPrint('Fallback: Priming audio system with silence.mp3...');
            try {
              final primingPlayer = AudioPlayer();
              await primingPlayer.setAsset('assets/silence.mp3');

              // Use timeout to prevent app crashes if silence.mp3 fails
              await primingPlayer.play().timeout(
                const Duration(milliseconds: 2000),
                onTimeout: () {
                  debugPrint(
                    'Fallback: silence.mp3 priming timed out, continuing anyway',
                  );
                },
              );

              // Wait for silence playback to complete with timeout
              final completer = Completer<void>();
              StreamSubscription? sub;

              sub = primingPlayer.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) {
                    completer.complete();
                    sub?.cancel();
                  }
                }
              });

              await completer.future.timeout(
                const Duration(milliseconds: 1000),
                onTimeout: () {
                  debugPrint(
                    'Fallback: silence.mp3 completion timed out, continuing anyway',
                  );
                  sub?.cancel();
                },
              );

              await primingPlayer.dispose();
              debugPrint(
                'Fallback: Audio priming with silence.mp3 completed successfully',
              );
            } catch (e) {
              debugPrint(
                'Fallback: Audio priming with silence.mp3 failed: $e, continuing anyway',
              );
            }

            final player = _createTrackedAudioPlayer('Fallback platform');

            // Use system volume setting for fallback platforms
            final settings = _settingsProvider?.settings;
            final systemVolume =
                settings?.systemVolume ?? settings?.applicationVolume ?? 10;
            final volumeLevel = systemVolume / 10.0;
            debugPrint(
              'announceViaBackend: Setting fallback player volume to $volumeLevel (Level: $systemVolume/10)',
            );
            await player.setVolume(volumeLevel);

            // Add brief warmup delay for fallback platforms to prevent audio cutoff
            await Future.delayed(const Duration(milliseconds: 100));
            debugPrint('Fallback: Audio session warmup delay completed');

            if (audioUrl != null && audioUrl.isNotEmpty) {
              final audioUrlStart = DateTime.now();
              await player.setUrl(audioUrl);

              // Wait for playback to complete
              final completer = Completer<void>();
              final sub = player.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) completer.complete();
                }
              });

              await player.play();
              await completer.future;
              await sub.cancel();

              final audioUrlEnd = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: Fallback audioUrl playback delta: ${audioUrlEnd.difference(audioUrlStart).inMilliseconds} ms',
              );
              backendAudioPlayed = true;
            } else if (base64Audio != null && base64Audio.isNotEmpty) {
              final base64Start = DateTime.now();
              final bytes = base64Decode(base64Audio);
              final tempDir = Directory.systemTemp;
              final tempFile = await File(
                '${tempDir.path}/backend_tts.mp3',
              ).create();
              await tempFile.writeAsBytes(bytes, flush: true);
              await player.setFilePath(tempFile.path);

              // Wait for playback to complete
              final completer = Completer<void>();
              final sub = player.playerStateStream.listen((state) {
                if (state.processingState == ProcessingState.completed) {
                  if (!completer.isCompleted) completer.complete();
                }
              });

              await player.play();
              await completer.future;
              await sub.cancel();

              final base64End = DateTime.now();
              debugPrint(
                '[TIMER] announceViaBackend: Fallback base64 audio playback delta: ${base64End.difference(base64Start).inMilliseconds} ms',
              );
              backendAudioPlayed = true;
            }

            // Dispose the fallback player to free AudioTrack resources
            await _disposeAudioPlayer(player, 'Fallback platform');
          }
        } catch (e) {
          debugPrint('❌ announceViaBackend: Audio playback failed: $e');
          debugPrint('❌ CRITICAL: Triggering comprehensive audio reset...');
          backendAudioPlayed = false;

          // CRITICAL: Reset entire audio system on ANY playback error
          await _resetAudioSystem(reason: 'playback error');
        }
      } else {
        debugPrint(
          'announceViaBackend: Backend error \\${response.statusCode}: \\${response.body}',
        );
      }
      // Fallback: use local TTS if backend audio not played
      if (!backendAudioPlayed) {
        debugPrint('announceViaBackend: Fallback to local TTS for "$text"');

        try {
          // For system routing, force speaker to match backend behavior
          if (routing == 'system' &&
              !kIsWeb &&
              (Platform.isIOS || Platform.isAndroid)) {
            try {
              final platform = MethodChannel('audio_routing');
              debugPrint(
                'announceViaBackend: Forcing speaker for local TTS fallback',
              );
              await platform.invokeMethod('forceSpeaker');
            } catch (e) {
              debugPrint(
                'announceViaBackend: forceSpeaker failed for local TTS: $e',
              );
            }
          }

          await flutterTts.stop();

          // Brief delay to ensure audio system is ready for TTS
          await Future.delayed(const Duration(milliseconds: 100));
          debugPrint('Fallback TTS: Audio system warmup delay completed');

          // Skip setVoice to avoid Fire tablet TTS voice errors
          // *** IMPROVED: Robust TTS completion detection with timeout safety ***
          final ttsCompleter = Completer<void>();

          // Set completion handler BEFORE calling speak()
          flutterTts.setCompletionHandler(() {
            debugPrint(
              'announceViaBackend: TTS completion handler triggered for "$text"',
            );
            if (!ttsCompleter.isCompleted) {
              debugPrint(
                'announceViaBackend: TTS completion confirmed - resolving completer',
              );
              ttsCompleter.complete();
            }
          });

          debugPrint('announceViaBackend: Starting local TTS: "$text"');
          await flutterTts.speak(text);

          // Wait for completion with a dynamic safety timeout based on announcement length
          final wordCount = text
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
          final estimatedDurationMs = (wordCount * 700) + 3000;
          final timeout = Duration(
            milliseconds: estimatedDurationMs.clamp(5000, 120000),
          );

          debugPrint(
            'announceViaBackend: Waiting for TTS completion (timeout: ${timeout.inMilliseconds}ms for "$text")',
          );

          try {
            await ttsCompleter.future.timeout(timeout);
            debugPrint('announceViaBackend: TTS completed within timeout');
          } on TimeoutException {
            debugPrint(
              '⚠️ announceViaBackend: TTS completion timeout after ${timeout.inMilliseconds}ms - forcing completion',
            );
            if (!ttsCompleter.isCompleted) {
              ttsCompleter.complete();
            }
          }

          // Clear handler AFTER completion is confirmed
          debugPrint(
            'announceViaBackend: Clearing TTS completion handler after "$text"',
          );
          flutterTts.setCompletionHandler(() {});

          // Small additional delay to ensure TTS system has fully settled
          await Future.delayed(const Duration(milliseconds: 100));
          debugPrint(
            'announceViaBackend: Local TTS playback complete for "$text"',
          );
        } catch (ttsError) {
          debugPrint('❌ announceViaBackend: TTS fallback failed: $ttsError');
          // TTS fallback failed - trigger audio reset
          await _resetAudioSystem(reason: 'TTS fallback error in try block');
        }
      }
      // After using forceSpeaker, restore routing for personal audio (Bluetooth)
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        try {
          final platform = MethodChannel('audio_routing');
          if (Platform.isIOS) {
            debugPrint(
              'routeToPersonal called after option announcement (iOS)',
            );
            await platform.invokeMethod('routeToPersonal');
            await Future.delayed(const Duration(milliseconds: 200));
            debugPrint('iOS: Audio routing restored to personal/Bluetooth');
          } else {
            debugPrint(
              'resetToDefault called after option announcement (Android)',
            );
            await platform.invokeMethod('resetToDefault');
          }
        } catch (e) {
          debugPrint('resetToDefault not implemented or failed: $e');
        }
      }
      final endTotal = DateTime.now();
      debugPrint(
        '[TIMER] announceViaBackend: END at ${endTotal.millisecondsSinceEpoch} (total delta: ${endTotal.difference(startTotal).inMilliseconds} ms)',
      );

      // No more fixed delay - the calling code will use _waitForAnnouncementComplete()
      // to properly check when announcements are finished
    } catch (e) {
      debugPrint('❌ announceViaBackend: Exception: $e');
      debugPrint(
        '❌ CRITICAL: Exception caught, resetting audio system and attempting TTS fallback...',
      );

      // CRITICAL: Reset entire audio system FIRST before attempting fallback
      await _resetAudioSystem(reason: 'exception');

      // Now attempt TTS fallback with fresh audio system
      try {
        // For system routing, force speaker to match backend behavior
        if (routing == 'system' &&
            !kIsWeb &&
            (Platform.isIOS || Platform.isAndroid)) {
          try {
            final platform = MethodChannel('audio_routing');
            debugPrint(
              'announceViaBackend: Forcing speaker for exception TTS fallback',
            );
            await platform.invokeMethod('forceSpeaker');
          } catch (speakerError) {
            debugPrint(
              'announceViaBackend: forceSpeaker failed for exception TTS: $speakerError',
            );
          }
        }

        await flutterTts.stop();

        // Brief delay to ensure audio system is ready
        await Future.delayed(const Duration(milliseconds: 100));

        // Skip setVoice to avoid Fire tablet TTS voice errors
        // *** IMPROVED: Robust TTS completion detection with timeout safety ***
        final ttsCompleter = Completer<void>();

        // Set completion handler BEFORE calling speak()
        flutterTts.setCompletionHandler(() {
          debugPrint(
            'announceViaBackend: Exception fallback - TTS completion handler triggered for "$text"',
          );
          if (!ttsCompleter.isCompleted) {
            debugPrint(
              'announceViaBackend: Exception fallback - TTS completion confirmed',
            );
            ttsCompleter.complete();
          }
        });

        debugPrint(
          'announceViaBackend: Starting exception fallback local TTS: "$text"',
        );
        await flutterTts.speak(text);

        // Wait for completion with a dynamic safety timeout based on announcement length
        final wordCount = text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        final estimatedDurationMs = (wordCount * 700) + 3000;
        final timeout = Duration(
          milliseconds: estimatedDurationMs.clamp(5000, 120000),
        );

        debugPrint(
          'announceViaBackend: Exception fallback - Waiting for TTS completion (timeout: ${timeout.inMilliseconds}ms)',
        );

        try {
          await ttsCompleter.future.timeout(timeout);
          debugPrint(
            'announceViaBackend: Exception fallback - TTS completed within timeout',
          );
        } on TimeoutException {
          debugPrint(
            '⚠️ announceViaBackend: Exception fallback - TTS completion timeout after ${timeout.inMilliseconds}ms - forcing completion',
          );
          if (!ttsCompleter.isCompleted) {
            ttsCompleter.complete();
          }
        }

        // Clear handler AFTER completion is confirmed
        debugPrint(
          'announceViaBackend: Exception fallback - Clearing TTS handler',
        );
        flutterTts.setCompletionHandler(() {});

        // Small additional delay to ensure TTS system has fully settled
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint(
          '✅ announceViaBackend: TTS fallback completed successfully after audio reset',
        );
      } catch (ttsError) {
        debugPrint('❌ announceViaBackend: TTS fallback also failed: $ttsError');
        // Even TTS fallback failed - trigger another reset
        await _resetAudioSystem(reason: 'TTS fallback error');
      }
    } finally {
      // Clear announcement playing flag and ensure audio routing has settled
      _isAnnouncementPlaying = false;

      // Always restore Android notification sounds
      if (!kIsWeb && Platform.isAndroid) {
        try {
          const platform = MethodChannel('audio_routing');
          platform.invokeMethod('restoreNotificationSounds');
          debugPrint('announceViaBackend: Notification sounds restored');
        } catch (e) {
          debugPrint(
            'announceViaBackend: Failed to restore notification sounds: $e',
          );
        }
      }

      // Resume keyboard listener after announcement
      if (gridFocusNode != null) {
        gridFocusNode!.requestFocus();
      }
      final announceEnd = DateTime.now().millisecondsSinceEpoch;
      debugPrint(
        '[TIMER] ANNOUNCE END: announceViaBackend("$text") at $announceEnd (total delta: ${announceEnd - announceStart}ms)',
      );

      // CRITICAL FIX: Always attempt to restart wake word service after any announcement
      // This ensures microphone doesn't stay off after button presses
      debugPrint(
        '[WakeWord] announceViaBackend: Scheduling wake word restart after announcement',
      );
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted && _wakeWordService != null) {
          final isCurrentlyListening = _wakeWordService!.isListening;
          debugPrint(
            '[WakeWord] announceViaBackend: Post-announcement check - isListening=$isCurrentlyListening',
          );

          if (!isCurrentlyListening) {
            // Check if wake word should be active before restarting
            if (WakeWordService.wakeWordShouldBeActive) {
              debugPrint(
                '[WakeWord] announceViaBackend: Wake word NOT listening after announcement, forcing restart',
              );
              _forceRestartWakeWordService();
            } else {
              debugPrint(
                '[WakeWord] announceViaBackend: Wake word disabled (wakeWordShouldBeActive=false), skipping restart',
              );
            }
          } else {
            debugPrint(
              '[WakeWord] announceViaBackend: Wake word already listening, no restart needed',
            );
          }
        }
      });
    }
  }

  /// Play custom MP3 audio file for button with fallback handling
  Future<void> playCustomButtonAudio(String audioUrl) async {
    if (audioUrl.isEmpty) {
      debugPrint('playCustomButtonAudio: Empty audio URL provided');
      return;
    }

    debugPrint('playCustomButtonAudio: Starting playback of $audioUrl');
    final audioStart = DateTime.now();

    // CRITICAL FIX: Pause wake word service during MP3 playback to prevent audio interference
    debugPrint(
      'playCustomButtonAudio: Pausing wake word service to prevent audio interference...',
    );
    if (_wakeWordService != null) {
      _wakeWordService!.pauseWakeWordAutoRestart();
      await _wakeWordService!.stopAllRecognizers();
      debugPrint('playCustomButtonAudio: Wake word service paused');
    }

    try {
      final player = AudioPlayer();

      // MATCH ANNOUNCEVIBACKEND: Force audio to built-in speakers like announceViaBackend does
      debugPrint(
        'playCustomButtonAudio: Using same audio routing as announceViaBackend (built-in speakers)',
      );

      if (!kIsWeb && Platform.isAndroid) {
        // Match EXACT audio routing from announceViaBackend for Android
        const platform = MethodChannel('audio_routing');

        try {
          // Step 1: Force to built-in speakers (same as announceViaBackend)
          await platform.invokeMethod('forceSpeaker');
          debugPrint(
            'playCustomButtonAudio: Android speaker forcing completed',
          );

          // Step 2: Wait for audio routing to stabilize (same delay as announceViaBackend)
          debugPrint(
            'playCustomButtonAudio: Waiting for audio routing to stabilize...',
          );
          await Future.delayed(const Duration(milliseconds: 300));
          debugPrint('playCustomButtonAudio: Audio routing setup complete');

          // Step 3: Audio priming with silence.mp3 (same as announceViaBackend)
          debugPrint(
            'playCustomButtonAudio: Priming speaker with silence.mp3...',
          );
          final primingPlayer = AudioPlayer();
          await primingPlayer.setAsset('assets/silence.mp3');

          // Wait for silence priming to complete
          final primingCompleter = Completer<void>();
          final primingSub = primingPlayer.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed) {
              if (!primingCompleter.isCompleted) primingCompleter.complete();
            }
          });

          await primingPlayer.play();
          await primingCompleter.future.timeout(
            const Duration(milliseconds: 1000),
            onTimeout: () {
              debugPrint(
                'playCustomButtonAudio: Silence priming timed out, continuing anyway',
              );
            },
          );
          await primingSub.cancel();
          await primingPlayer.dispose();

          debugPrint(
            'playCustomButtonAudio: Speaker priming completed successfully',
          );
        } catch (e) {
          debugPrint(
            'playCustomButtonAudio: Android audio routing setup failed: $e',
          );
        }
      } else if (!kIsWeb && Platform.isIOS) {
        // Match EXACT audio routing from announceViaBackend for iOS
        const platform = MethodChannel('audio_routing');

        try {
          // Step 1: Force to built-in speakers (same as announceViaBackend)
          await platform.invokeMethod('forceSpeaker');
          debugPrint('playCustomButtonAudio: iOS speaker forcing completed');

          // Step 2: Wait for audio routing to stabilize (same delay as announceViaBackend)
          debugPrint(
            'playCustomButtonAudio: iOS waiting for audio routing to stabilize...',
          );
          await Future.delayed(const Duration(milliseconds: 600));
          debugPrint('playCustomButtonAudio: iOS audio routing setup complete');
        } catch (e) {
          debugPrint(
            'playCustomButtonAudio: iOS audio routing setup failed: $e',
          );
        }
      }

      // Handle different audio source types
      if (audioUrl.startsWith('data:audio/')) {
        // Handle base64 data URLs by creating a temporary file
        debugPrint('playCustomButtonAudio: Processing base64 data URL');
        try {
          // Extract base64 data from data URL
          final dataUrlParts = audioUrl.split(',');
          if (dataUrlParts.length != 2) {
            throw Exception('Invalid data URL format');
          }

          final base64Data = dataUrlParts[1];
          final audioBytes = base64Decode(base64Data);

          // Create a temporary file
          final tempDir = Directory.systemTemp;
          final tempFile = File(
            '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          await tempFile.writeAsBytes(audioBytes);

          debugPrint(
            'playCustomButtonAudio: Created temporary file: ${tempFile.path}',
          );

          // Create audio source from temporary file
          await player.setAudioSource(AudioSource.file(tempFile.path));

          // Clean up the temporary file after playback
          player.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed) {
              tempFile.delete().catchError((e) {
                debugPrint(
                  'playCustomButtonAudio: Failed to delete temp file: $e',
                );
                return tempFile; // Return the file to satisfy the type requirement
              });
            }
          });
        } catch (e) {
          debugPrint(
            'playCustomButtonAudio: Failed to process base64 data URL: $e',
          );
          return;
        }
      } else {
        // Handle regular HTTP/HTTPS URLs
        await player.setUrl(audioUrl);
      }

      // Enhanced playback logic for short MP3 clips
      final completer = Completer<void>();
      late StreamSubscription subscription;

      subscription = player.playerStateStream.listen((state) {
        debugPrint(
          'playCustomButtonAudio: Player state: ${state.processingState}, playing: ${state.playing}',
        );

        if (state.processingState == ProcessingState.completed) {
          debugPrint('playCustomButtonAudio: Playback completed normally');
          if (!completer.isCompleted) {
            completer.complete();
            subscription.cancel();
          }
        }
      });

      // Start playback with better error handling
      try {
        await player.play();
        debugPrint('playCustomButtonAudio: MP3 playback started successfully');
      } catch (e) {
        debugPrint('playCustomButtonAudio: Failed to start playback: $e');
        if (!completer.isCompleted) {
          completer.complete();
        }
        subscription.cancel();
        await player.dispose();
        return;
      }

      // Wait for completion with shorter timeout for typical short clips
      try {
        await completer.future.timeout(
          const Duration(seconds: 10), // Shorter timeout for short audio clips
          onTimeout: () {
            debugPrint(
              'playCustomButtonAudio: Audio playback timed out after 10 seconds',
            );
            subscription.cancel();
          },
        );
      } catch (e) {
        debugPrint(
          'playCustomButtonAudio: Timeout or error during playback: $e',
        );
        subscription.cancel();
      }

      // Clean up
      await player.dispose();

      // MATCH ANNOUNCEVIBACKEND: Reset audio routing back to default after playback (same as announceViaBackend)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('resetToDefault');
          debugPrint(
            'playCustomButtonAudio: Audio routing reset to default after MP3 playback',
          );
        } catch (e) {
          debugPrint(
            'playCustomButtonAudio: Failed to reset audio routing: $e',
          );
        }
      }

      final audioEnd = DateTime.now();
      final duration = audioEnd.difference(audioStart).inMilliseconds;
      debugPrint(
        'playCustomButtonAudio: MP3 playback completed in ${duration}ms',
      );
    } catch (e) {
      debugPrint('playCustomButtonAudio: Failed to play custom audio: $e');
      // Continue with normal flow on error - don't block button functionality
    } finally {
      // CRITICAL FIX: Resume wake word service after MP3 playback completes (same as announceViaBackend)
      debugPrint(
        'playCustomButtonAudio: Resuming wake word service after MP3 playback...',
      );
      if (_wakeWordService != null) {
        // Add delay to allow audio routing to fully reset before resuming wake word service
        await Future.delayed(const Duration(milliseconds: 500));
        _wakeWordService!.resumeWakeWordAutoRestart();
        await _wakeWordService!.startWakeWordListening();
        debugPrint(
          'playCustomButtonAudio: Wake word service resumed successfully',
        );

        // Verify it actually started listening
        await Future.delayed(const Duration(milliseconds: 500));
        if (!_wakeWordService!.isListening) {
          debugPrint(
            'playCustomButtonAudio: WARNING - Wake word service not listening after resume, forcing restart',
          );
          _forceRestartWakeWordService();
        }
      }
    }
  }

  /// Ultra-fast TTS announcement using exact POC approach for built-in speaker routing
  Future<void> _announceSimpleTTS(String text) async {
    try {
      debugPrint('[POC TTS] Starting exact POC-style TTS for: "$text"');

      // CRITICAL POC FIX: Use new pauseSpeechRecognition to stop audio interference without losing wake word state
      debugPrint(
        '[POC TTS] Pausing speech recognition to prevent audio interference...',
      );
      await WakeWordService.pauseSpeechRecognition();
      await Future.delayed(
        Duration(milliseconds: 100),
      ); // POC-style brief pause

      // Minimal delay before audio routing change (like POC)
      await Future.delayed(Duration(milliseconds: 100));

      // Force speaker routing for audio feedback (POC approach)
      if (!kIsWeb && Platform.isIOS) {
        try {
          const platform = MethodChannel('audio_routing');
          await platform.invokeMethod('forceSpeaker');
          debugPrint('[POC TTS] Audio routing set to speaker for announcement');
          await Future.delayed(
            Duration(milliseconds: 200),
          ); // Longer delay for audio routing to settle
        } catch (e) {
          debugPrint('[POC TTS] Failed to force speaker: $e');
        }
      }

      debugPrint(
        '[POC TTS] Playing "$text" announcement through speaker...',
      );

      // FAST ANNOUNCEMENT: Use announceViaBackendSimple with preserveMicrophoneSession=true
      // This skips the resetToDefault and Bluetooth routing steps that cause lag
      debugPrint('[POC TTS] Using fast backend TTS without Bluetooth setup...');

      // Call simplified backend TTS that preserves microphone session (no audio routing changes)
      await announceViaBackendSimple(
        text,
        routing: 'system',
        preserveMicrophoneSession: true,
      );

      debugPrint('[POC TTS] Fast backend TTS announcement completed');

      // Minimal delay since we're not doing audio routing
      await Future.delayed(Duration(milliseconds: 100)); // Very short delay
      debugPrint('[POC TTS] Ready for immediate question listening');

      debugPrint(
        '[POC TTS] Fast announcement completed, starting question listening...',
      );
    } catch (e) {
      debugPrint('[POC TTS] Error: $e');
    }
  }

  /// Wait for any ongoing announcements to complete and audio routing to settle
  Future<void> _waitForAnnouncementComplete() async {
    debugPrint('_waitForAnnouncementComplete: Checking announcement state...');

    // First, wait for any active announcement to finish
    int waitCount = 0;
    while (_isAnnouncementPlaying && waitCount < 50) {
      // Max 5 seconds (50 * 100ms)
      debugPrint(
        '_waitForAnnouncementComplete: Announcement still playing, waiting... (${waitCount + 1}/50)',
      );
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (_isAnnouncementPlaying) {
      debugPrint(
        '_waitForAnnouncementComplete: WARNING - Announcement flag still set after 5 seconds, proceeding anyway',
      );
    } else {
      debugPrint(
        '_waitForAnnouncementComplete: Announcement completed in ${waitCount * 100}ms',
      );
    }

    // Add a brief additional wait for audio routing to settle completely
    // This is much shorter than the previous fixed delay and only happens after
    // we know the announcement is actually complete
    if (waitCount > 0) {
      // Only delay if there was actually an announcement
      debugPrint(
        '_waitForAnnouncementComplete: Adding brief audio routing settle delay...',
      );
      await Future.delayed(
        const Duration(milliseconds: 300),
      ); // Much shorter than 1200ms
      debugPrint('_waitForAnnouncementComplete: Audio routing settle complete');
    }

    debugPrint('_waitForAnnouncementComplete: Complete - ready for scanning');
  }

  Future<void> handleButtonAction(Map<String, dynamic> buttonData) async {
    // Android notification sounds suppressed globally

    // *** CAPTURE PAUSED STATE BEFORE STOPPING SCANNING ***
    final wasScanningPaused = _isScanningPaused && _waitingForUserInput;
    debugPrint('handleButtonAction: Captured paused state: $wasScanningPaused');

    // *** IMMEDIATELY STOP SCANNING ON ANY BUTTON CLICK ***
    debugPrint(
      'handleButtonAction: IMMEDIATELY stopping scanning for any button click',
    );
    _stopAuditoryScanning();

    // *** CHECK FOR TEMPORARY NAVIGATION AUTO-RETURN ***
    if (_temporaryNavigationReturnPage != null) {
      final returnPage = _temporaryNavigationReturnPage!;
      _temporaryNavigationReturnPage = null; // Clear the flag
      debugPrint(
        'handleButtonAction: TEMPORARY navigation - auto-returning to: $returnPage',
      );

      // Extract and process button action first (speech/audio/etc)
      final speechPhrase = buttonData['speechPhrase'] as String?;
      final customAudioFile = buttonData['customAudioFile'] as String?;

      // Announce speech phrase if present
      if (speechPhrase != null && speechPhrase.isNotEmpty) {
        setState(() {
          statusMessage = '';
          _suppressScanning = true;
        });
        try {
          await _announceWithTimeout(speechPhrase, routing: 'system');
          if (customAudioFile != null && customAudioFile.isNotEmpty) {
            await playCustomButtonAudio(customAudioFile);
          }
        } catch (e) {
          debugPrint(
            'handleButtonAction: TEMPORARY page announcement failed: $e',
          );
        } finally {
          _suppressScanning = false;
        }
      } else if (customAudioFile != null && customAudioFile.isNotEmpty) {
        // Play audio even if no speech phrase
        await playCustomButtonAudio(customAudioFile);
      }

      // Now navigate back to the return page
      setState(() {
        statusMessage = 'Returning to \"$returnPage\"...';
      });

      // Remove the temporary page from history before going back
      if (_navigationHistory.isNotEmpty) {
        _navigationHistory.removeLast();
      }

      await fetchGridDataForPage(returnPage, addToHistory: false);

      // Restart scanning after navigation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          setState(() {
            scanningIndex = null;
          });
          _maybeStartScanning();
          _forceRestartWakeWordService();
        });
      });

      return; // Stop processing - we've handled the auto-return
    }

    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final llmQuery = buttonData['LLMQuery'] as String?;
    final targetPage = buttonData['targetPage'] as String?;
    final speechPhraseRaw = buttonData['speechPhrase'] as String?;
    final speechPhrase = _processRandomPhrase(
      speechPhraseRaw,
    ); // Process {RANDOM:...} pattern
    final queryType = buttonData['queryType'] as String?;
    final customAudioFile = buttonData['customAudioFile'] as String?;
    final navigationType =
        buttonData['navigationType'] as String?; // NEW: Get navigation type
    final composeSpecial = buttonData['composeSpecial'] as String?;
    final keepFollowUpContext = buttonData['keepFollowUpContext'] == true;

    if (composeSpecial != null && composeSpecial.isNotEmpty) {
      switch (composeSpecial) {
        case 'exit_creation':
          _openComposeFinalizeGrid();
          return;
        case 'compose_back':
          _restoreFromComposeGrid();
          return;
        case 'compose_new':
          _composeGridStack.clear();
          _composePageStack.clear();
          await _initializeComposeSession(
            documentType: 'story',
            sourceFrom: 'compose',
          );
          await _openComposeBuilder(sourceContext: 'compose a message');
          return;
        case 'compose_open_list':
          await _openComposeDocListGrid();
          return;
        case 'compose_delete_list':
          await _openComposeDocListGrid(forDelete: true);
          return;
        case 'compose_open_doc':
          _composeGridStack.clear();
          _composePageStack.clear();
          final docId = (buttonData['composeDocId'] ?? '').toString().trim();
          await _initializeComposeSession(
            documentType: (buttonData['composeDocType'] ?? 'story').toString(),
            seedText: (buttonData['composeDocBody'] ?? '').toString(),
            documentId: docId.isEmpty ? null : docId,
            title: (buttonData['composeDocTitle'] ?? '').toString(),
            sourceFrom: 'compose',
          );
          await _openComposeBuilder(sourceContext: 'compose a message');
          return;
        case 'compose_delete_select':
          await _openComposeDeleteConfirmGrid(buttonData);
          return;
        case 'compose_delete_no':
          _restoreFromComposeGrid();
          setState(() {
            statusMessage = 'Delete canceled.';
          });
          return;
        case 'compose_delete_yes':
          final docId = (buttonData['composeDocId'] ?? '').toString().trim();
          final title = (buttonData['composeDocTitle'] ?? 'Untitled')
              .toString();
          final isLocalFallback =
              buttonData['composeDocIsLocalFallback'] == true;
          await _deleteComposeDocument(
            documentId: docId,
            title: title,
            isLocalFallback: isLocalFallback,
          );
          return;
        case 'compose_save':
          _composeGridStack.clear();
          _composePageStack.clear();
          await _saveComposeAndExit();
          return;
        case 'compose_return_builder':
          _composeGridStack.clear();
          _composePageStack.clear();
          await _openComposeBuilder();
          return;
        case 'compose_discard':
          _restoreFromComposeGrid();
          _composeGridStack.clear();
          _composePageStack.clear();
          await _discardComposeAndExit();
          return;
        case 'compose_read':
          await _announceWithTimeout(
            _composeSession.text.trim().isEmpty
                ? 'Creation is empty.'
                : _composeSession.text,
            routing: 'system',
          );
          return;
        case 'compose_export_menu':
          _openComposeExportGrid();
          return;
        case 'compose_ai_edit':
          final aiEditSucceeded = await _aiEditCompose();
          if (aiEditSucceeded) {
            setState(() {
              questionDisplay = _composeSession.text;
              statusMessage =
                  'AI edit complete. Finalize options are still active.';
            });
            await _announceWithTimeout(
              _composeSession.text.trim().isEmpty
                  ? 'AI edit complete.'
                  : _composeSession.text,
              routing: 'system',
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _maybeStartScanning();
            });
          } else {
            final failureMessage = (statusMessage ?? '').trim().isNotEmpty
                ? statusMessage!.trim()
                : 'Unable to AI edit creation right now.';
            await _announceWithTimeout(failureMessage, routing: 'system');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _maybeStartScanning();
            });
          }
          return;
        case 'compose_copy':
          await _copyComposeToClipboard();
          return;
        case 'compose_save_file':
          await _saveComposeToFile();
          return;
        case 'compose_read_aloud':
          await _announceWithTimeout(
            _composeSession.text.trim().isEmpty
                ? 'Creation is empty.'
                : _composeSession.text,
            routing: 'system',
          );
          return;
      }
      return;
    }
    // Debug: print entry to handleButtonAction with FULL button data
    debugPrint(
      'handleButtonAction called. llmQuery: $llmQuery, queryType: $queryType, isLLMGenerated: ${buttonData['isLLMGenerated']}',
    );
    debugPrint('handleButtonAction FULL buttonData: $buttonData');
    debugPrint(
      'handleButtonAction extracted values: targetPage=$targetPage, speechPhrase=$speechPhrase (raw: $speechPhraseRaw), customAudioFile=$customAudioFile, navigationType=$navigationType',
    );
    if (llmQuery != null && llmQuery.isNotEmpty) {
      debugLogLLM(stage: 'LLM Query Start', prompt: llmQuery);
      // Always store both previous grid and page before showing LLM options
      previousPageName = currentPageName;
      previousGridButtons = List<Map<String, dynamic>>.from(gridButtons);
      _stopAuditoryScanning();
      setState(() {
        _showBottomStatusText = true;
        statusMessage = 'Processing LLM...';
        isLoading = true;
      });
      // Prevent double LLM calls: set a flag
      if (_isProcessingLLM) {
        debugPrint('LLM is already processing, skipping duplicate call.');
        return;
      }

      // Store query details for potential retry (only if not already retrying)
      if (_llmRetryCount == 0) {
        _lastLLMQuery = llmQuery;
        _lastLLMButtonData = Map<String, dynamic>.from(buttonData);
        _lastWasScanningPaused = wasScanningPaused;
        debugPrint('🔄 LLM: Stored query for potential retry');
      } else {
        debugPrint('🔄 LLM: Retry attempt #$_llmRetryCount');
      }

      _isProcessingLLM = true;
      try {
        final llmOptions = settingsProvider.settings?.llmOptions ?? 10;
        final useSummary =
            settingsProvider.settings?.useShortSummaryOnButtons ?? false;
        final vocabularyLevel =
            settingsProvider.settings?.vocabularyLevel ?? 'functional';

        // Map vocabulary level to user-friendly description for LLM
        String vocabularyInstruction;
        switch (vocabularyLevel) {
          case 'emergent':
            vocabularyInstruction =
                'Use basic everyday words appropriate for emergent communicators (e.g., want, help, happy, more, go, stop).';
            break;
          case 'functional':
            vocabularyInstruction =
                'Use practical daily living vocabulary suitable for functional communication (e.g., tired, wonderful, choose, delicious, uncomfortable).';
            break;
          case 'developing':
            vocabularyInstruction =
                'Use expanded academic vocabulary for developing communicators (e.g., anxious, fascinating, investigate, appreciate, collaborate).';
            break;
          case 'proficient':
            vocabularyInstruction =
                'Use sophisticated specialized vocabulary for proficient communicators (e.g., lethargic, magnificent, articulate, contemplative, exceptional).';
            break;
          default:
            vocabularyInstruction =
                'Use practical daily living vocabulary suitable for functional communication.';
        }

        String summaryInstruction = useSummary
            ? 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.'
            : 'The "summary" key should contain the exact same FULL text as the "option" key.';
        final rawPrompt = llmQuery.replaceAll(
          '#LLMOptions',
          llmOptions.toString(),
        );
        final formatInstructions =
            'Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.\n'
            'The "option" key should contain the FULL option text.\n'
            'The "keywords" key should contain a list of 3-5 important words from the option.\n'
            '${vocabularyInstruction}\n'
            '${summaryInstruction}\n'
            'Example:\n'
            '[\n'
            '  {"summary": "How are you?", "option": "Hello, how are you doing today?", "keywords": ["hello", "how", "you", "today", "doing"]},\n'
            '  {"summary": "See You", "option": "Goodbye!  It was great seeing you. See you later!", "keywords": ["goodbye", "see", "you", "later", "great"]}\n'
            ']';
        final prompt = _composeSession.active
            ? '"${_sanitizeComposePrompt(rawPrompt)}". '
                  'Generate written composition options, not in-room conversation options. '
                  'Ignore location, people present, nearby people, and current activity.\n'
                  '$formatInstructions'
                  '${_getComposePromptContext()}'
            : rawPrompt.trim() + '\n' + formatInstructions;
        llmOriginalPrompt = prompt; // Store for "Something Else"
        if (!keepFollowUpContext) {
          _initializeFollowUpConversation(llmQuery);
        }
        originatingButtonText =
            buttonData['text'] as String?; // Store originating button text
        activeLLMPromptForContext =
            prompt; // Store LLM query as primary context for freestyle
        debugPrint('LLM PROMPT: ' + prompt);
        debugLogLLM(stage: 'LLM Prompt Sent', prompt: prompt);
        debugPrint('LLM REQUEST URL: ${EnvironmentConfig.apiBaseUrl}/llm');
        debugPrint(
          'LLM REQUEST BODY: ' + json.encode(_buildLlmRequestBody(prompt)),
        );

        // Add 30-second timeout to LLM requests to prevent hanging
        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'POST',
          '${EnvironmentConfig.apiBaseUrl}/llm',
          baseHeaders: {
            'X-User-ID': widget.aacUserId,
            'Content-Type': 'application/json',
          },
          body: json.encode(_buildLlmRequestBody(prompt)),
          timeoutSeconds: 30,
        );

        if (response.statusCode == 200) {
          dynamic options;
          try {
            var responseBody = response.body;

            // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
            if (responseBody.contains('```json')) {
              debugPrint(
                '🔍 Detected markdown code fence in response, stripping...',
              );
              responseBody = responseBody
                  .replaceAll('```json', '')
                  .replaceAll('```', '')
                  .trim();
            }

            options = json.decode(responseBody);

            // Parse potentially malformed LLM response
            options = _parseLLMResponse(options);

            // Successful parse - reset retry counter
            _llmRetryCount = 0;
            _lastLLMQuery = null;
            _lastLLMButtonData = null;
          } catch (e) {
            debugPrint('🚨 LLM JSON PARSE ERROR: $e');
            debugPrint('🚨 RAW RESPONSE BODY: ${response.body}');
            throw FormatException(
              'Failed to parse AI response. Please try again.',
            );
          }

          debugPrint('DEBUG: Raw LLM response body: ${response.body}');
          debugPrint(
            'DEBUG: Parsed options: $options (type: ${options.runtimeType})',
          );
          debugLogLLM(stage: 'LLM Raw Response', response: options);
          List<Map<String, dynamic>> llmButtons = [];
          llmPreviousOptions = [];
          if (options is List && options.isNotEmpty) {
            // Track that this is an LLM query (not jokes/currentevents)
            _currentQueryType = 'llm';
            // Only update previousGridButtons if not already in an LLM grid
            if (previousGridButtons == null) {
              previousGridButtons = List<Map<String, dynamic>>.from(
                gridButtons,
              );
            }
            // Map LLM options: summary for label, option for speechPhrase
            llmButtons = options.asMap().entries.map<Map<String, dynamic>>((
              entry,
            ) {
              final i = entry.key;
              final opt = entry.value;
              debugPrint(
                'DEBUG: Processing LLM option $i: $opt (type: ${opt.runtimeType})',
              );
              String summary = '';
              String optionText = '';
              if (opt is Map) {
                summary = (opt['summary'] ?? '').toString();
                optionText = (opt['option'] ?? '').toString();
                debugPrint(
                  'DEBUG: Map parsed - summary: "$summary", optionText: "$optionText"',
                );
              } else {
                summary = opt.toString();
                optionText = opt.toString();
                debugPrint(
                  'DEBUG: Non-map fallback - both set to: "$optionText"',
                );
              }
              String label = summary.trim().isNotEmpty ? summary : optionText;
              llmPreviousOptions.add(optionText);
              return {
                'text': label,
                'speechPhrase': optionText,
                'isLLMGenerated': true,
                'targetPage': previousPageName,
                'row': i,
                'col': 0,
                'summary': summary, // Include summary for image matching
                'keywords': opt is Map && opt['keywords'] != null
                    ? opt['keywords']
                    : null, // Include LLM keywords
                'hidden': false, // Ensure button is visible
                'queryType': '', // Empty queryType to match category buttons
                'LLMQuery': '', // Empty LLMQuery since these are result buttons
                'customAudioFile': null, // No custom audio file
                // Enable pictogram support for LLM buttons to match category buttons
                'enablePictograms': true,
              };
            }).toList();
            // SIMPLIFIED LOGIC: Always add Free Style and Ask Again buttons for any LLM response
            // The user should always have these options when the LLM generates responses
            debugPrint('DEBUG: LLM Response Analysis:');
            debugPrint(
              'DEBUG: - buttonData queryType: "${buttonData['queryType']}"',
            );
            debugPrint('DEBUG: - llmQuery: "$llmQuery"');
            debugPrint('DEBUG: - llmButtons.length: ${llmButtons.length}');
            debugPrint(
              'DEBUG: - Always adding Free Style and Ask Again buttons for LLM responses',
            );

            // Add "Free Style" button - allows user to construct their own response
            llmButtons.add({
              'text': 'Free Style',
              'speechPhrase': 'Free Style',
              'isLLMGenerated': true,
              'llmSpecial': 'freeStyle',
              'row': llmButtons.length,
              'col': 0,
              'hidden': false,
              'queryType': '',
              'LLMQuery': '',
              'customAudioFile': null,
              'enablePictograms': true,
            });
            debugPrint('DEBUG: Added Free Style button');

            // Note: Do NOT add "Please Ask Me Again" button for LLM query buttons
            // This button should only appear for wake word questions, not for buttons with predefined LLM queries

            // Add default buttons: Something Else, Go Back
            int nextIndex = llmButtons.length;
            llmButtons.add({
              'text': 'Something Else',
              'speechPhrase': 'Something Else',
              'isLLMGenerated': true,
              'llmSpecial': 'somethingElse',
              'row': nextIndex,
              'col': 0,
              'hidden': false,
              'queryType': '',
              'LLMQuery': '',
              'customAudioFile': null,
              'enablePictograms': true,
            });
            nextIndex++;
            llmButtons.add({
              'text': 'Go Back',
              'speechPhrase': 'Go Back',
              'isLLMGenerated': true,
              'llmSpecial': 'goBack',
              'row': nextIndex,
              'col': 0,
              'hidden': false,
              'queryType': '',
              'LLMQuery': '',
              'customAudioFile': null,
              'enablePictograms': true,
            });
            final nonEmptyButtons = llmButtons
                .where(
                  (btn) => (btn['text'] ?? '').toString().trim().isNotEmpty,
                )
                .toList();
            setState(() {
              gridButtons = llmButtons;
              statusMessage =
                  'LLM returned ${llmButtons.length} option(s) (including standard buttons). Displaying ${nonEmptyButtons.length} button(s). First: ' +
                  (nonEmptyButtons.isNotEmpty
                      ? nonEmptyButtons[0]['text']
                      : 'None');
              isLoading = false;
            });
            debugLogLLM(stage: 'LLM Grid Set', gridButtons: llmButtons);
            // Start scanning after the frame is built - check if we need to auto-resume
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (wasScanningPaused) {
                debugPrint(
                  'handleButtonAction LLM: Auto-resuming scanning because we were paused',
                );
                debugPrint(
                  'handleButtonAction LLM: Current _suppressScanning state: $_suppressScanning',
                );

                // Ensure scanning is not suppressed for auto-resume
                _suppressScanning = false;

                _maybeStartScanning();

                final settingsProvider = Provider.of<UserSettingsProvider>(
                  context,
                  listen: false,
                );
                final waitForSwitch =
                    settingsProvider.settings?.waitForSwitchToScan ?? false;
                if (waitForSwitch && _waitingForInitialSwitch) {
                  unawaited(_playWaitForSwitchNotification());
                } else {
                  // Add a small delay to let scanning start, then announce that we have new options
                  Future.delayed(const Duration(milliseconds: 500), () async {
                    await _speakPersonalVoice(
                      "New options available. Scanning resumed.",
                    );
                  });
                }

                // Resume wake word service after LLM options are displayed
                debugPrint(
                  'Resuming wake word listening after LLM options display (auto-resume)',
                );
                _wakeWordService?.resumeWakeWordAutoRestart();
              } else {
                debugPrint(
                  'handleButtonAction LLM: Starting normal scanning after LLM',
                );
                debugPrint(
                  'handleButtonAction LLM: Current _suppressScanning state: $_suppressScanning',
                );
                _maybeStartScanning();

                final settingsProvider = Provider.of<UserSettingsProvider>(
                  context,
                  listen: false,
                );
                final waitForSwitch =
                    settingsProvider.settings?.waitForSwitchToScan ?? false;
                if (waitForSwitch && _waitingForInitialSwitch) {
                  unawaited(_playWaitForSwitchNotification());
                }

                // Resume wake word service after LLM options are displayed
                debugPrint(
                  'Resuming wake word listening after LLM options display (normal)',
                );
                _wakeWordService?.resumeWakeWordAutoRestart();
              }
              //_stopAuditoryScanning();
              //_startAuditoryScanning();
            });
            if (nonEmptyButtons.isEmpty) {
              setState(() {
                statusMessage =
                    (statusMessage ?? '') +
                    '\nWarning: All LLM options have empty text.';
              });
            }
          } else {
            setState(() {
              statusMessage =
                  'No options returned. LLM raw: ' + response.body.toString();
            });
          }
        } else {
          // HTTP error response (non-200 status code)
          debugPrint(
            '🚨 LLM HTTP ERROR: Status ${response.statusCode}, retryCount=$_llmRetryCount, maxRetries=$_maxLLMRetries',
          );

          // Check if we should retry (allow up to _maxLLMRetries attempts)
          if (_llmRetryCount < _maxLLMRetries && _lastLLMQuery != null) {
            _llmRetryCount++;
            debugPrint(
              '🔄 LLM RETRY #$_llmRetryCount: HTTP ${response.statusCode} - Attempting retry...',
            );

            _updateStatusMessageWithAutoReset(
              '🔄 AI query failed (${response.statusCode}) - Retrying ($_llmRetryCount/$_maxLLMRetries)...',
              resetAfter: const Duration(seconds: 2),
            );

            await _speakPersonalVoice("AI query failed. Retrying.");

            if (_lastLLMButtonData != null) {
              debugPrint(
                '🔄 LLM RETRY #$_llmRetryCount: Re-executing query with stored button data',
              );

              // CRITICAL: Reset processing flag BEFORE retry to avoid duplicate prevention
              setState(() {
                _isProcessingLLM = false;
              });

              await handleButtonAction(_lastLLMButtonData!);
              return; // Exit - let retry handle success/failure
            }
          }

          // Retry limit reached or no query to retry - restart scanning
          debugPrint(
            '🚨 LLM HTTP ERROR FINAL: Retry limit reached ($_llmRetryCount retries attempted). Restarting scanning.',
          );
          _llmRetryCount = 0;
          _lastLLMQuery = null;
          _lastLLMButtonData = null;

          setState(() {
            statusMessage =
                'LLM error (${response.statusCode}). Raw: ' +
                response.body.toString();
          });

          // Show user-friendly red error banner with auto-reset
          _updateStatusMessageWithAutoReset(
            '❌ AI query failed - Scanning restarted',
            resetAfter: const Duration(seconds: 3),
          );

          // Announce error to user via personal speaker
          await _speakPersonalVoice("AI query failed. Scanning restarted.");

          // Resume scanning and wake word on error
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_lastWasScanningPaused || wasScanningPaused) {
              debugPrint(
                'handleButtonAction LLM Error: Auto-resuming scanning (paused state)',
              );
              _suppressScanning = false;
              _maybeStartScanning();
              _wakeWordService?.resumeWakeWordAutoRestart();
            } else {
              debugPrint(
                'handleButtonAction LLM Error: Resuming normal scanning',
              );
              _maybeStartScanning();
              _wakeWordService?.resumeWakeWordAutoRestart();
            }
          });
        }
      } catch (e) {
        debugPrint('🚨 LLM PROCESSING ERROR: $e');
        debugPrint(
          '🚨 LLM ERROR DETAILS: retryCount=$_llmRetryCount, maxRetries=$_maxLLMRetries, hasStoredQuery=${_lastLLMQuery != null}',
        );

        // Check if we should retry (allow up to _maxLLMRetries attempts)
        if (_llmRetryCount < _maxLLMRetries && _lastLLMQuery != null) {
          _llmRetryCount++;
          debugPrint(
            '🔄 LLM RETRY #$_llmRetryCount: Attempting retry after error...',
          );

          // Show user-friendly retry message
          final isTimeout =
              e.toString().contains('TimeoutException') ||
              e.toString().contains('timed out');
          final retryMessage = isTimeout
              ? '⏳ AI request timed out - Retrying ($_llmRetryCount/$_maxLLMRetries)...'
              : '🔄 AI query failed - Retrying ($_llmRetryCount/$_maxLLMRetries)...';

          _updateStatusMessageWithAutoReset(
            retryMessage,
            resetAfter: const Duration(seconds: 2),
          );

          // Announce retry to user
          final audioMessage = isTimeout
              ? "AI request timed out. Retrying."
              : "AI query failed. Retrying.";
          await _speakPersonalVoice(audioMessage);

          // Retry the same query by recursively calling handleButtonAction
          if (_lastLLMButtonData != null) {
            debugPrint(
              '🔄 LLM RETRY #$_llmRetryCount: Re-executing query with stored button data',
            );

            // CRITICAL: Reset processing flag BEFORE retry to avoid duplicate prevention
            setState(() {
              _isProcessingLLM = false;
            });

            await handleButtonAction(_lastLLMButtonData!);
            return; // Exit this catch block - let retry handle success/failure
          }
        }

        // If we get here, either:
        // 1. This is the final failure (all retries exhausted)
        // 2. No stored query to retry
        // Reset retry counter and restart scanning
        debugPrint(
          '🚨 LLM FINAL FAILURE: All retries exhausted ($_llmRetryCount attempts). Restarting scanning.',
        );
        _llmRetryCount = 0;
        _lastLLMQuery = null;
        _lastLLMButtonData = null;

        // User-friendly error message for logs
        String debugMessage;
        if (e.toString().contains('FormatException')) {
          debugMessage = 'AI response format error. Please try again.';
        } else {
          debugMessage =
              'AI Error: ${e.toString().replaceAll('Exception:', '').trim()}';
        }

        setState(() {
          statusMessage = debugMessage;
        });

        // Show user-friendly red error banner with auto-reset
        final isTimeout =
            e.toString().contains('TimeoutException') ||
            e.toString().contains('timed out');
        final userMessage = isTimeout
            ? '❌ AI request timed out - Scanning restarted'
            : '❌ AI query failed - Scanning restarted';

        _updateStatusMessageWithAutoReset(
          userMessage,
          resetAfter: const Duration(seconds: 3),
        );

        // Announce error to user via personal speaker
        final audioMessage = isTimeout
            ? "AI request timed out. Scanning restarted."
            : "AI query failed. Scanning restarted.";
        await _speakPersonalVoice(audioMessage);

        // Resume scanning and wake word on error
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_lastWasScanningPaused || wasScanningPaused) {
            debugPrint(
              'handleButtonAction LLM Exception: Auto-resuming scanning (paused state)',
            );
            _suppressScanning = false;
            _maybeStartScanning();
            _wakeWordService?.resumeWakeWordAutoRestart();
          } else {
            debugPrint(
              'handleButtonAction LLM Exception: Resuming normal scanning',
            );
            _maybeStartScanning();
            _wakeWordService?.resumeWakeWordAutoRestart();
          }
        });
      } finally {
        setState(() {
          isLoading = false;
          _isProcessingLLM = false;
        });
      }
      return;
    } else if (buttonData['isLLMGenerated'] == true &&
        buttonData['speechPhrase'] != null) {
      // Handle special LLM buttons
      if (buttonData['llmSpecial'] == 'home') {
        debugPrint(
          'handleButtonAction: Home button pressed from LLM follow-up flow',
        );

        _resetFollowUpConversation();
        setState(() {
          originatingButtonText = null;
          activeLLMPromptForContext = null;
        });
        _currentQueryType = null;

        await fetchGridDataForPage('home', addToHistory: false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            scanningIndex = null;
          });
          _maybeStartScanning();
          _forceRestartWakeWordService();
        });
        return;
      } else if (buttonData['llmSpecial'] == 'goBack') {
        debugPrint(
          'handleButtonAction: Go Back button pressed - starting comprehensive restoration',
        );

        _resetFollowUpConversation();

        // Clear context variables to match web app behavior
        setState(() {
          originatingButtonText = null;
          activeLLMPromptForContext = null;
        });
        _currentQueryType = null; // Clear query type on Go Back
        debugPrint('handleButtonAction: Go Back - cleared context variables');

        if (previousPageName != null) {
          final pageToRestore = previousPageName;
          previousPageName = null;
          previousGridButtons = null;
          await fetchGridDataForPage(pageToRestore!);
        } else if (previousGridButtons != null) {
          setState(() {
            gridButtons = previousGridButtons!;
            previousGridButtons = null;
          });
        }

        // *** RESET SCANNING INDEX FOR GO BACK FUNCTIONALITY ***
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint(
            'handleButtonAction: Go Back completed, resetting scanning index to start from first option',
          );
          setState(() {
            scanningIndex = null; // Reset to start from first button
          });
          _maybeStartScanning();

          final settingsProvider = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final waitForSwitch =
              settingsProvider.settings?.waitForSwitchToScan ?? false;
          if (waitForSwitch && _waitingForInitialSwitch) {
            unawaited(_playWaitForSwitchNotification());
          }

          // *** ENHANCED WAKE WORD SERVICE RESTORATION AFTER GO BACK ***
          debugPrint(
            'handleButtonAction: Go Back - performing enhanced wake word service restoration',
          );

          // Force complete restart instead of reset to ensure clean state
          _forceRestartWakeWordService();

          // Additional verification and restart if needed
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted && _wakeWordService != null) {
              final isListening = _wakeWordService!.isListening;
              debugPrint(
                'handleButtonAction: Go Back - verification check: isListening=$isListening',
              );

              if (!isListening) {
                debugPrint(
                  'handleButtonAction: Go Back - wake word service not listening, forcing restart',
                );

                // Ensure the global flag is enabled
                WakeWordService.wakeWordShouldBeActive = true;

                // Re-initialize all callbacks to restore proper main page functionality
                debugPrint(
                  'handleButtonAction: Go Back - restoring main page wake word callbacks',
                );
                _initializeWakeWordCallbacks();

                // Start fresh with a new session
                if (_microphonePermissionGranted) {
                  debugPrint(
                    'handleButtonAction: Go Back - starting fresh wake word session',
                  );
                  _wakeWordService!.startWakeWordListening();
                }
              } else {
                debugPrint(
                  'handleButtonAction: Go Back - wake word service already listening, no additional restart needed',
                );
              }
            }
          });
        });
        return;
      } else if (buttonData['llmSpecial'] == 'somethingElse') {
        // Check if we're in jokes mode — re-fetch from jokes endpoint instead of LLM
        if (_currentQueryType == 'jokes') {
          debugPrint('Something Else for Jokes: re-fetching from jokes API');
          handleButtonAction({'text': 'Jokes', 'queryType': 'jokes'});
          return;
        }
        // Generate new LLM prompt excluding previous options
        final origPrompt = llmOriginalPrompt ?? '';
        final excludeList = llmPreviousOptions;
        final excludeText = excludeList.isNotEmpty
            ? ' IMPORTANTLY, exclude the following options if possible: "' +
                  excludeList.join('; ') +
                  '".'
            : '';
        final newPrompt = origPrompt + excludeText;
        debugPrint('Something Else LLM prompt: $newPrompt');
        setState(() {
          statusMessage = 'Requesting more LLM options...';
        });
        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'POST',
          '${EnvironmentConfig.apiBaseUrl}/llm',
          baseHeaders: {
            'X-User-ID': widget.aacUserId,
            'Content-Type': 'application/json',
          },
          body: json.encode(_buildLlmRequestBody(newPrompt)),
          timeoutSeconds: 30,
        );
        if (response.statusCode == 200) {
          dynamic options = json.decode(response.body);

          // Parse potentially malformed LLM response
          options = _parseLLMResponse(options);

          debugLogLLM(
            stage: 'LLM Something Else Raw Response',
            response: options,
          );
          // Recursively call handleButtonAction with a fake buttonData to trigger LLM mapping
          handleButtonAction({
            'LLMQuery': newPrompt,
            'queryType': buttonData['queryType'] ?? 'question',
            'keepFollowUpContext': true,
          });
        } else {
          setState(() {
            statusMessage =
                'LLM error (${response.statusCode}) on Something Else. Raw: ' +
                response.body.toString();
          });
        }
        return;
      } else if (buttonData['llmSpecial'] == 'freeStyle') {
        // Navigate to Freestyle page for custom response construction
        setState(() {
          statusMessage = 'Opening Free Style page...';
        });
        await _announceWithTimeout(
          'I\'m choosing my own words.  Please give me a moment.',
        );

        // Determine context from stored LLM prompt and button data (matching web app approach)
        String? sourceContext;
        bool isLLMGenerated = buttonData['isLLMGenerated'] == true;

        // Use LLM query as primary context (matching web app approach)
        if (activeLLMPromptForContext != null) {
          sourceContext = activeLLMPromptForContext;
        } else if (isLLMGenerated && llmOriginalPrompt != null) {
          // Fallback to stored LLM query
          sourceContext = llmOriginalPrompt;
        } else if (buttonData['text'] != null) {
          // For admin pages, use the button text as context
          sourceContext = buttonData['text'].toString();
        } else if (currentPageName != 'home') {
          // Fall back to page name if it's not the generic home page
          sourceContext = currentPageName;
        }

        // Capture originating button text before clearing (needed for Freestyle context)
        String? capturedOriginatingButtonText = originatingButtonText;

        // Clear context after capturing it (matching web app behavior)
        setState(() {
          activeLLMPromptForContext = null;
          originatingButtonText = null;
        });

        // Navigate to the Freestyle page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FreestylePage(
              idToken: widget.idToken,
              aacUserId: widget.aacUserId,
              displayName: 'Free Style Response',
              sourceContext: sourceContext,
              sourcePage: currentPageName,
              isLLMGenerated: isLLMGenerated,
              originatingButtonText: capturedOriginatingButtonText,
              onComposeAppend: _appendToComposeText,
            ),
          ),
        );
        return;
      } else if (buttonData['llmSpecial'] == 'askAgain') {
        setState(() {
          statusMessage = 'Please ask your question again.';
        });
        await _announceWithTimeout(
          'Okay, please ask your question again after the tone.',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        previousPageName = currentPageName;
        _wakeWordService?.startQuestionListening();
        return;
      }
      final optionText = buttonData['speechPhrase'] as String;
      // Only announce if not a default button
      if (buttonData['llmSpecial'] != 'goBack' &&
          buttonData['llmSpecial'] != 'somethingElse' &&
          buttonData['llmSpecial'] != 'askAgain' &&
          buttonData['llmSpecial'] != 'freeStyle') {
        // Capture question for chat history and speech-history row updates
        final currentQuestion = (_questionText?.trim().isNotEmpty ?? false)
            ? _questionText!.trim()
            : (questionDisplay.isNotEmpty ? questionDisplay : '');

        setState(() {
          if (currentQuestion.isNotEmpty) {
            final qPrefix = 'Q: $currentQuestion';
            final lines = speechHistory.split('\n');
            final matchIndex = lines.indexWhere((l) => l.startsWith(qPrefix));
            if (matchIndex >= 0) {
              lines[matchIndex] = 'Q: $currentQuestion | A: $optionText';
              speechHistory = lines.join('\n');
            } else {
              speechHistory =
                  'Q: $currentQuestion | A: $optionText' +
                  (speechHistory.isNotEmpty ? '\n' : '') +
                  speechHistory;
            }
            questionDisplay = '';
            _questionText = null;
          } else {
            speechHistory =
                optionText +
                (speechHistory.isNotEmpty ? '\n' : '') +
                speechHistory;
          }
        });

        unawaited(_appendToComposeText(optionText));

        // Record to chat history (same as web app)
        final chatService = ChatHistoryService();
        final userSettings = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        chatService
            .recordChatHistoryWithProvider(
              question: currentQuestion,
              response: optionText,
              userSettingsProvider: userSettings,
            )
            .catchError((error) {
              print('❌ Failed to record chat history: $error');
            });
        _wakeWordService?.pauseWakeWordAutoRestart();
        debugPrint(
          'Stopping wake word listening before announcing LLM option: $optionText',
        );

        // *** OPTIMIZED TIMEOUT-PROTECTED WAKE WORD SERVICE SHUTDOWN ***
        debugPrint(
          'LLM AUDIO FIX: Starting optimized wake word service shutdown...',
        );

        try {
          // Reduced attempts and timeouts for faster response
          for (int i = 0; i < 2; i++) {
            // Reduced from 3 to 2 attempts
            debugPrint('LLM AUDIO FIX: Stop attempt ${i + 1}/2');

            try {
              // Wrap each stop call in a shorter timeout to prevent hanging
              final stopFutures = Future.wait([
                _wakeWordService?.stopWakeWordListening() ?? Future.value(),
                _wakeWordService?.stopAllRecognizers() ?? Future.value(),
              ]);

              await stopFutures.timeout(
                const Duration(milliseconds: 500),
              ); // Reduced from 2s to 500ms
              debugPrint(
                'LLM AUDIO FIX: Stop calls completed for attempt ${i + 1}',
              );
            } catch (timeoutError) {
              debugPrint(
                'LLM AUDIO FIX: Stop attempt ${i + 1} timed out: $timeoutError',
              );
            }

            await Future.delayed(
              const Duration(milliseconds: 100),
            ); // Reduced from 200ms to 100ms

            final isListening = _wakeWordService?.isListening ?? false;
            debugPrint(
              'LLM AUDIO FIX: After attempt ${i + 1}: isListening=$isListening',
            );

            if (!isListening) {
              debugPrint(
                'LLM AUDIO FIX: Wake word service stopped successfully on attempt ${i + 1}',
              );
              break;
            }
          }
        } catch (e) {
          debugPrint('LLM AUDIO FIX: Error during shutdown: $e');
        }

        // Final check and force proceed
        final finalListening = _wakeWordService?.isListening ?? false;
        debugPrint(
          'LLM AUDIO FIX: Final status check: isListening=$finalListening',
        );

        // Reduced safety delay for faster response
        debugPrint(
          'LLM AUDIO FIX: Adding 300ms safety delay for audio cleanup...',
        );
        await Future.delayed(
          const Duration(milliseconds: 300),
        ); // Reduced from 1000ms to 300ms
        debugPrint(
          'LLM AUDIO FIX: Wake word service shutdown complete - proceeding with audio playback',
        );

        // --- Suppress scanning until announcement and grid update are complete ---
        _suppressScanning = true;
        await _announceWithTimeout(optionText);

        // For jokes, keep the old behavior of exiting to Home after selection.
        if (_currentQueryType == 'jokes') {
          _resetFollowUpConversation();
          await fetchGridDataForPage('home', addToHistory: false);
        } else {
          final followUpButtons = await _generateFollowUpButtonsAfterSelection(
            optionText,
          );
          setState(() {
            gridButtons = followUpButtons;
            statusMessage =
                'Next-step options ready (${followUpButtons.length} total, Home first).';
          });
        }

        // Only allow scanning after the grid is updated and frame is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // add delay to ensure grid is updated
          int delay = settingsProvider.settings?.scanDelay ?? 3500;
          Future.delayed(Duration(milliseconds: delay), () {
            _suppressScanning = false;
            // Stop any existing scanning and restart from first option
            _stopAuditoryScanning();
            // *** RESET SCANNING INDEX TO START FROM FIRST OPTION ***
            debugPrint(
              'handleButtonAction: Resetting scanning index to start from first option after LLM response',
            );
            setState(() {
              scanningIndex = null; // Reset to start from first button
            });

            // Add delay to allow audio routing to reset before starting scanning
            Future.delayed(const Duration(milliseconds: 500), () {
              debugPrint(
                'handleButtonAction: Audio routing reset delay completed after LLM response',
              );
              _maybeStartScanning();

              final waitForSwitch =
                  settingsProvider.settings?.waitForSwitchToScan ?? false;
              if (waitForSwitch && _waitingForInitialSwitch) {
                unawaited(_playWaitForSwitchNotification());
              }

              // Resume wake word service after LLM response is complete
              debugPrint(
                'Resuming wake word listening after LLM response and navigation',
              );
              _wakeWordService?.resumeWakeWordAutoRestart();
            });
          });
        });
      }
    } else if (queryType == 'currentevents') {
      setState(() {
        statusMessage = 'Loading current events...';
        isLoading = true;
      });

      try {
        final eventType = buttonData['text']?.toString().toLowerCase() ?? '';
        debugPrint('Fetching current events for type: $eventType');

        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'POST',
          '${EnvironmentConfig.apiBaseUrl}/get-current-events',
          baseHeaders: {
            'X-User-ID': widget.aacUserId,
            'Content-Type': 'application/json',
          },
          body: json.encode({'eventType': eventType}),
        );

        if (response.statusCode == 200) {
          final List<dynamic> currentEventsData = json.decode(response.body);
          debugPrint(
            'Current events response: ${currentEventsData.length} items',
          );

          if (currentEventsData.isNotEmpty) {
            _currentQueryType = 'currentevents';
            // Convert to the same format as LLM buttons
            List<Map<String, dynamic>> eventButtons = currentEventsData
                .asMap()
                .entries
                .map<Map<String, dynamic>>((entry) {
                  final i = entry.key;
                  final item = entry.value;

                  String summary = '';
                  String optionText = '';

                  if (item is Map) {
                    summary = (item['summary'] ?? '').toString();
                    optionText = (item['option'] ?? '').toString();
                  } else {
                    summary = item.toString();
                    optionText = item.toString();
                  }

                  String label = summary.trim().isNotEmpty
                      ? summary
                      : optionText;

                  return {
                    'text': label,
                    'speechPhrase': optionText,
                    'isLLMGenerated': true,
                    'targetPage':
                        currentPageName, // Store current page to go back to
                    'row': i,
                    'col': 0,
                  };
                })
                .toList();

            // Add Go Back button
            eventButtons.add({
              'text': 'Go Back',
              'speechPhrase': 'Go Back',
              'isLLMGenerated': true,
              'llmSpecial': 'goBack',
              'row': eventButtons.length,
              'col': 0,
            });

            // Store current grid to restore later
            previousPageName = currentPageName;
            previousGridButtons = List<Map<String, dynamic>>.from(gridButtons);

            setState(() {
              gridButtons = eventButtons;
              statusMessage =
                  'Loaded ${currentEventsData.length} current events items';
              isLoading = false;
            });

            // *** RESET SCANNING INDEX FOR CURRENT EVENTS ***
            // Start scanning after the frame is built with audio routing delay
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              debugPrint(
                'handleButtonAction: Current events loaded, resetting scanning index to start from first option',
              );
              setState(() {
                scanningIndex = null; // Reset to start from first button
              });

              // Add delay to allow audio routing to reset before starting scanning
              await Future.delayed(const Duration(milliseconds: 500));
              debugPrint(
                'handleButtonAction: Audio routing reset delay completed after current events load',
              );

              _maybeStartScanning();
            });
          } else {
            setState(() {
              statusMessage = 'No current events found';
              isLoading = false;
            });
          }
        } else {
          setState(() {
            statusMessage =
                'Error loading current events: ${response.statusCode}';
            isLoading = false;
          });
          debugPrint(
            'Current events error: ${response.statusCode} - ${response.body}',
          );
        }
      } catch (e) {
        setState(() {
          statusMessage = 'Error loading current events: $e';
          isLoading = false;
        });
        debugPrint('Current events exception: $e');
      }
    } else if (queryType == 'jokes') {
      // Handle jokes query type - fetch from jokes API (like gridpage.js does)
      setState(() {
        statusMessage = 'Loading Jokes...';
        isLoading = true;
      });

      try {
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: false,
        );
        final llmOptions = settingsProvider.settings?.llmOptions ?? 10;
        debugPrint('Fetching jokes with limit: $llmOptions');

        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'GET',
          '${EnvironmentConfig.apiBaseUrl}/api/jokes/contextual?limit=$llmOptions',
          baseHeaders: {'X-User-ID': widget.aacUserId},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> jokes = data['jokes'] ?? [];
          debugPrint('Jokes response: ${jokes.length} jokes');

          if (jokes.isNotEmpty) {
            // Helper to add [PAUSE] to joke text if not already present
            String addPauseToJokeText(String text) {
              if (text.isEmpty) return '';
              if (text.contains('[PAUSE]')) return text;
              final questionIndex = text.indexOf('?');
              if (questionIndex != -1 && questionIndex < text.length - 1) {
                return '${text.substring(0, questionIndex + 1)} [PAUSE] ${text.substring(questionIndex + 1).trim()}';
              }
              if (text.contains(' - ')) {
                return text.replaceFirst(' - ', ' [PAUSE] ');
              }
              if (text.contains(' — ')) {
                return text.replaceFirst(' — ', ' [PAUSE] ');
              }
              if (text.contains(': ')) {
                return text.replaceFirst(': ', ': [PAUSE] ');
              }
              return text;
            }

            // Map jokes to buttons (same format as LLM buttons)
            List<Map<String, dynamic>> jokeButtons = jokes
                .asMap()
                .entries
                .map<Map<String, dynamic>>((entry) {
                  final i = entry.key;
                  final joke = entry.value;
                  final jokeText = (joke['text'] ?? '').toString().trim();
                  final summary = (joke['summary'] ?? 'Joke').toString().trim();
                  final tags = joke['tags'];

                  return {
                    'text': summary.isNotEmpty ? summary : 'Joke',
                    'speechPhrase': addPauseToJokeText(jokeText),
                    'isLLMGenerated': true,
                    'targetPage': currentPageName,
                    'row': i,
                    'col': 0,
                    'summary': summary,
                    'keywords': tags != null
                        ? (tags is List ? tags : [tags])
                        : ['joke', 'humor'],
                    'hidden': false,
                    'queryType': '',
                    'LLMQuery': '',
                    'customAudioFile': null,
                    'enablePictograms': true,
                  };
                })
                .where(
                  (btn) =>
                      (btn['speechPhrase'] ?? '').toString().trim().isNotEmpty,
                )
                .toList();

            // Track previous options for Something Else exclusion
            llmPreviousOptions = jokeButtons
                .map((btn) => btn['speechPhrase'].toString())
                .toList();

            // Add Something Else button (to get more jokes)
            jokeButtons.add({
              'text': 'Something Else',
              'speechPhrase': 'Something Else',
              'isLLMGenerated': true,
              'llmSpecial': 'somethingElse',
              'row': jokeButtons.length,
              'col': 0,
              'hidden': false,
              'queryType': '',
              'LLMQuery': '',
              'customAudioFile': null,
              'enablePictograms': true,
            });

            // Add Go Back button
            jokeButtons.add({
              'text': 'Go Back',
              'speechPhrase': 'Go Back',
              'isLLMGenerated': true,
              'llmSpecial': 'goBack',
              'row': jokeButtons.length,
              'col': 0,
              'hidden': false,
              'queryType': '',
              'LLMQuery': '',
              'customAudioFile': null,
              'enablePictograms': true,
            });

            // Store current grid to restore later
            if (previousGridButtons == null) {
              previousPageName = currentPageName;
              previousGridButtons = List<Map<String, dynamic>>.from(
                gridButtons,
              );
            }

            // Mark current query type as jokes for Something Else handling
            _currentQueryType = 'jokes';

            setState(() {
              gridButtons = jokeButtons;
              statusMessage = 'Loaded ${jokes.length} jokes';
              isLoading = false;
            });

            // Reset scanning for new joke buttons
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              debugPrint(
                'handleButtonAction: Jokes loaded, resetting scanning index',
              );
              setState(() {
                scanningIndex = null;
              });
              await Future.delayed(const Duration(milliseconds: 500));
              _maybeStartScanning();
            });
          } else {
            setState(() {
              statusMessage = 'No jokes found';
              isLoading = false;
            });
          }
        } else {
          setState(() {
            statusMessage = 'Error loading jokes: ${response.statusCode}';
            isLoading = false;
          });
          debugPrint('Jokes error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        setState(() {
          statusMessage = 'Error loading jokes: $e';
          isLoading = false;
        });
        debugPrint('Jokes exception: $e');
      }
    } else if (queryType == 'thread') {
      // Handle thread query type by navigating to threads page
      setState(() {
        statusMessage = 'Opening Thread Communication...';
      });

      // Announce first, then navigate
      if (speechPhrase.isNotEmpty) {
        await _announceWithTimeout(speechPhrase, routing: 'system');
      }

      // Play custom MP3 audio file if assigned (after TTS)
      if (customAudioFile != null && customAudioFile.isNotEmpty) {
        debugPrint(
          'handleButtonAction: Playing custom MP3 audio for thread button: $customAudioFile',
        );
        await playCustomButtonAudio(customAudioFile);
      }

      // Navigate to threads page - PUSH instead of REPLACE to enable proper didPopNext callbacks
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              ThreadsPage(idToken: widget.idToken, aacUserId: widget.aacUserId),
        ),
      );

      setState(() {
        statusMessage = '';
      });
    } else if (navigationType == 'GO-BACK-PAGE') {
      // GO-BACK-PAGE navigation: Go back to previous page in history
      debugPrint('handleButtonAction: GO-BACK-PAGE navigation triggered');

      // Announce speech phrase if present
      if (speechPhrase.isNotEmpty) {
        setState(() {
          statusMessage = '';
          _suppressScanning = true;
        });
        try {
          await _announceWithTimeout(speechPhrase, routing: 'system');
          if (customAudioFile != null && customAudioFile.isNotEmpty) {
            await playCustomButtonAudio(customAudioFile);
          }
        } catch (e) {
          debugPrint('handleButtonAction: GO-BACK announcement failed: $e');
        } finally {
          _suppressScanning = false;
        }
      }

      // Navigate back in history
      if (_navigationHistory.length > 1) {
        // Remove current page from history
        _navigationHistory.removeLast();
        final previousPage = _navigationHistory.last;
        debugPrint(
          'handleButtonAction: Navigating back to: $previousPage (history: $_navigationHistory)',
        );

        setState(() {
          statusMessage = 'Going back to "$previousPage"...';
        });

        // Don't add to history since we're going back
        await fetchGridDataForPage(previousPage, addToHistory: false);
      } else {
        // No history, go to home as fallback
        debugPrint('handleButtonAction: No history, navigating to home');
        setState(() {
          statusMessage = 'Going to Home...';
        });
        _navigationHistory = ['home']; // Reset history
        await fetchGridDataForPage('home', addToHistory: false);
      }

      // Restart scanning after navigation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          setState(() {
            scanningIndex = null;
          });
          _maybeStartScanning();
          _forceRestartWakeWordService();
        });
      });

      return; // Don't continue with normal navigation
    } else if (targetPage != null && targetPage.isNotEmpty) {
      // Check for special navigation targets with ! prefix
      if (targetPage.startsWith('!')) {
        final specialPage = targetPage.substring(1); // Remove the ! prefix

        if (speechPhrase.isNotEmpty) {
          setState(() {
            statusMessage = ''; // Clear status
          });
          await announceViaBackend(speechPhrase, routing: 'system');
        }

        // Play custom MP3 audio file if assigned (after TTS)
        if (customAudioFile != null && customAudioFile.isNotEmpty) {
          debugPrint(
            'handleButtonAction: Playing custom MP3 audio for special page: $customAudioFile',
          );
          await playCustomButtonAudio(customAudioFile);
          // Small delay to let audio session stabilize after MP3 playback
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // Navigate to special pages (outside of gridpage system)
        if (specialPage == 'freestyle') {
          setState(() {
            statusMessage = 'Opening Freestyle Communication...';
          });

          // Use LLM query as primary context (matching web app approach), or fallback to page context
          String? sourceContext =
              activeLLMPromptForContext ??
              (currentPageName != 'home' ? currentPageName : null);

          // Clear context after capturing it (matching web app behavior)
          setState(() {
            activeLLMPromptForContext = null;
            originatingButtonText = null;
          });

          // Navigate to freestyle page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FreestylePage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
                sourceContext: sourceContext,
                sourcePage: currentPageName,
                isLLMGenerated:
                    false, // Special page navigation is typically from admin pages
                originatingButtonText:
                    null, // No originating button for special page navigation
                onComposeAppend: _appendToComposeText,
              ),
            ),
          );
        } else if (specialPage == 'games') {
          setState(() {
            statusMessage = 'Opening Games...';
          });

          // Don't unfocus - let the new route's FocusScope handle focus naturally
          // Navigator will pop the old route out of the focus hierarchy

          // Navigate to games page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => GamesPage(
                fromInterface: 'auditory',
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                announceFunction: announceViaBackend,
              ),
            ),
          );
        } else if (specialPage == 'threads') {
          setState(() {
            statusMessage = 'Opening Thread Communication...';
          });

          // Announce first, then navigate
          if (speechPhrase.isNotEmpty) {
            await announceViaBackend(speechPhrase, routing: 'system');
          }

          // Navigate to threads page - PUSH instead of REPLACE to enable proper didPopNext callbacks
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ThreadsPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
              ),
            ),
          );
        } else if (specialPage == 'favorites') {
          setState(() {
            statusMessage = 'Opening Favorites...';
          });

          // Navigate to favorites page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FavoritesPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
              ),
            ),
          );
        } else if (specialPage == 'mood') {
          setState(() {
            statusMessage = 'Opening Mood Selection...';
          });

          // Navigate to mood selection page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => MoodSelectionPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
              ),
            ),
          );
        } else if (specialPage == 'email') {
          setState(() {
            statusMessage = 'Opening Email...';
          });

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => EmailPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
                onEnterComposeMode: _activateComposeFromEmail,
              ),
            ),
          );
        } else if (specialPage == 'jokes') {
          setState(() {
            statusMessage = 'Loading Jokes...';
          });

          // Load jokes inline (same pattern as gridpage.js)
          handleButtonAction({'text': 'Jokes', 'queryType': 'jokes'});
        } else if (specialPage == 'guess-who' || specialPage == 'guesswho') {
          setState(() {
            statusMessage = 'Opening Guess Who...';
          });

          // Navigate to games page with Guess Who auto-started
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => GamesPage(
                fromInterface: 'auditory',
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                announceFunction: announceViaBackend,
                initialGame: 'guess_who',
              ),
            ),
          );
        } else if (specialPage == 'spelling' || specialPage == 'spell') {
          setState(() {
            statusMessage = 'Opening Spelling...';
          });

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SpellingScanPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                announceFunction: announceViaBackend,
                scanPromptFunction: _speakPersonalVoice,
                onComposeAppend: _appendToComposeText,
              ),
            ),
          );
        } else if (specialPage == 'numbers' || specialPage == 'number') {
          setState(() {
            statusMessage = 'Opening Numbers...';
          });

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => NumbersScanPage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                announceFunction: announceViaBackend,
                scanPromptFunction: _speakPersonalVoice,
                onComposeAppend: _appendToComposeText,
              ),
            ),
          );
        } else if (specialPage == 'compose' || specialPage == 'composition') {
          setState(() {
            statusMessage = 'Opening creation menu...';
          });

          setState(() {
            activeLLMPromptForContext = null;
            originatingButtonText = null;
          });

          _openComposeEntryGrid();
        } else {
          setState(() {
            statusMessage = 'Unknown special page: $specialPage';
          });
        }
        return; // Don't continue with normal grid navigation
      }

      // If speechPhrase is present, announce it first, then navigate
      if (speechPhrase.isNotEmpty) {
        setState(() {
          statusMessage = ''; // Clear status
          // CRITICAL: Suppress scanning and rebuilds during announcement
          _suppressScanning = true;
        });
        debugPrint(
          'handleButtonAction: About to announce speechPhrase: $speechPhrase',
        );

        try {
          await _announceWithTimeout(speechPhrase, routing: 'system');
          debugPrint(
            'handleButtonAction: Announcement completed successfully, proceeding with navigation',
          );

          // Play custom MP3 audio file if assigned (after TTS)
          if (customAudioFile != null && customAudioFile.isNotEmpty) {
            debugPrint(
              'handleButtonAction: Playing custom MP3 audio after TTS: $customAudioFile',
            );
            await playCustomButtonAudio(customAudioFile);
            debugPrint(
              'handleButtonAction: Custom MP3 audio playback completed',
            );
          }
        } catch (e) {
          debugPrint(
            'handleButtonAction: Announcement or audio failed with error: $e, proceeding with navigation anyway',
          );
        } finally {
          // Always re-enable scanning after announcement attempt
          _suppressScanning = false;
        }
      }
      debugPrint(
        'handleButtonAction: Starting navigation to targetPage: $targetPage, navigationType: $navigationType',
      );

      // Handle TEMPORARY navigation: Store return page before navigating
      if (navigationType == 'TEMPORARY') {
        _temporaryNavigationReturnPage = currentPageName;
        debugPrint(
          'handleButtonAction: TEMPORARY navigation - storing return page: $_temporaryNavigationReturnPage',
        );
      }

      setState(() {
        statusMessage = 'Navigating to "' + targetPage + '"...';
      });
      debugPrint(
        'handleButtonAction: About to call fetchGridDataForPage($targetPage)',
      );
      await fetchGridDataForPage(targetPage);
      debugPrint('handleButtonAction: fetchGridDataForPage completed');

      // *** ENSURE SCANNING RESETS PROPERLY AFTER PAGE NAVIGATION ***
      debugPrint(
        'handleButtonAction: Page navigation completed, preparing to restart scanning',
      );

      // Use WidgetsBinding to ensure the grid is fully built before starting scanning
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Add a small delay to ensure audio system has settled after navigation
        Future.delayed(const Duration(milliseconds: 300), () {
          debugPrint(
            'handleButtonAction: Starting scanning after navigation delay',
          );
          // Reset scanning index to start from beginning
          setState(() {
            scanningIndex = null; // Reset to start from first button
          });
          _maybeStartScanning();
          // Also restart wake word service after navigation
          _forceRestartWakeWordService();
        });
      });

      // Debug: show gridButtons after navigation
      final nonEmptyButtons = gridButtons
          .where((btn) => (btn['text'] ?? '').toString().trim().isNotEmpty)
          .toList();
      setState(() {
        statusMessage =
            'Loaded page "' +
            targetPage +
            '" with ' +
            gridButtons.length.toString() +
            ' button(s). Displaying ' +
            nonEmptyButtons.length.toString() +
            ' button(s). First: ' +
            (nonEmptyButtons.isNotEmpty ? nonEmptyButtons[0]['text'] : 'None');
        // Do not update questionDisplay
      });
      if (gridButtons.isEmpty || nonEmptyButtons.isEmpty) {
        setState(() {
          statusMessage =
              (statusMessage ?? '') +
              '\nWarning: Page "' +
              targetPage +
              '" is empty or all buttons have empty text.';
        });
      }
    } else if (speechPhrase.isNotEmpty) {
      if (_composeSession.active) {
        await _appendToComposeText(speechPhrase);
        setState(() {
          questionDisplay = speechPhrase;
          statusMessage = 'Added to creation.';
        });
      } else {
        setState(() {
          questionDisplay = speechPhrase;
        });
        await announceViaBackend(speechPhrase, routing: 'system');
      }

      // Play custom MP3 audio file if assigned (after TTS)
      if (customAudioFile != null && customAudioFile.isNotEmpty) {
        debugPrint(
          'handleButtonAction: Playing custom MP3 audio for speech-only button: $customAudioFile',
        );
        await playCustomButtonAudio(customAudioFile);
      }

      // *** RESTART SCANNING AFTER SPEECH PHRASE ANNOUNCEMENT ***
      debugPrint(
        'handleButtonAction: Speech phrase announced, restarting scanning',
      );

      // Add delay to allow audio routing to reset before starting scanning
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint('handleButtonAction: Audio routing reset delay completed');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeStartScanning();
        // Also restart wake word service
        _forceRestartWakeWordService();
      });
    } else if (customAudioFile != null && customAudioFile.isNotEmpty) {
      // Button has only custom audio file (no speech phrase or navigation)
      debugPrint(
        'handleButtonAction: Playing custom MP3 audio for audio-only button: $customAudioFile',
      );
      await playCustomButtonAudio(customAudioFile);

      // *** RESTART SCANNING AFTER AUDIO-ONLY BUTTON ***
      debugPrint(
        'handleButtonAction: Audio-only button completed, restarting scanning',
      );

      // Add delay to allow audio routing to reset before starting scanning
      Future.delayed(const Duration(milliseconds: 500), () {
        debugPrint(
          'handleButtonAction: Audio routing reset delay completed for audio-only button',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeStartScanning();
          // Also restart wake word service
          _forceRestartWakeWordService();
        });
      });
    } else {
      setState(() {
        statusMessage = 'No action for this button.';
      });

      // *** RESTART SCANNING EVEN FOR BUTTONS WITH NO ACTION ***
      debugPrint('handleButtonAction: No action button, restarting scanning');

      // Add delay to allow audio routing to reset before starting scanning
      Future.delayed(const Duration(milliseconds: 500), () {
        debugPrint(
          'handleButtonAction: Audio routing reset delay completed for no action button',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeStartScanning();
        });
      });
    }

    // Always restore Android notification sounds after button action processing
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const platform = MethodChannel('audio_routing');
        platform.invokeMethod('restoreNotificationSounds');
        debugPrint('handleButtonAction: Notification sounds restored');
      } catch (e) {
        debugPrint(
          'handleButtonAction: Failed to restore notification sounds: $e',
        );
      }
    }
  }

  Future<void> fetchGridDataForPage(
    String pageName, {
    bool addToHistory = true,
  }) async {
    debugPrint(
      'fetchGridDataForPage: Starting fetch for pageName: $pageName, addToHistory: $addToHistory',
    );

    bool applyPageFromPayload(List<dynamic> payload, {required String source}) {
      final normalizedPageName = pageName.trim().toLowerCase();
      Map<String, dynamic>? matchedPage;
      final List<String> pageNames = [];

      for (final page in payload) {
        if (page is! Map) continue;
        final name = (page['name'] ?? page['pageName'] ?? '').toString();
        pageNames.add(name);
        if (name.trim().toLowerCase() == normalizedPageName) {
          matchedPage = Map<String, dynamic>.from(page);
        }
      }

      if (matchedPage == null || matchedPage['buttons'] == null) {
        return false;
      }

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final int gridCols = settingsProvider.settings?.gridColumns ?? 10;
      List<Map<String, dynamic>> buttons = List<Map<String, dynamic>>.from(
        matchedPage['buttons'] as List,
      ).map(_normalizeGridButton).toList();
      List<Map<String, dynamic>> visibleButtons = buttons
          .where(
            (btn) =>
                (btn['hidden'] != true) &&
                ((btn['text'] ?? '').toString().trim().isNotEmpty),
          )
          .toList();
      visibleButtons = _ensureEmailButtonVisible(buttons, visibleButtons);
      final emailCandidates = buttons.where(_isEmailSpecialButton).length;
      final emailVisible = visibleButtons.where(_isEmailSpecialButton).length;
      debugPrint(
        'fetchGridDataForPage EMAIL DEBUG: candidates=$emailCandidates, visible=$emailVisible, page=${(matchedPage['name'] ?? matchedPage['pageName'] ?? pageName)}',
      );
      visibleButtons.sort((a, b) {
        int rowA = int.tryParse(a['row']?.toString() ?? '0') ?? 0;
        int rowB = int.tryParse(b['row']?.toString() ?? '0') ?? 0;
        if (rowA != rowB) return rowA.compareTo(rowB);
        int colA = int.tryParse(a['col']?.toString() ?? '0') ?? 0;
        int colB = int.tryParse(b['col']?.toString() ?? '0') ?? 0;
        return colA.compareTo(colB);
      });
      for (int i = 0; i < visibleButtons.length; i++) {
        visibleButtons[i]['gridRow'] = (i ~/ gridCols);
        visibleButtons[i]['gridCol'] = (i % gridCols);
      }

      final Map<String, dynamic> resolvedPage = matchedPage;

      setState(() {
        gridButtons = visibleButtons;
        currentPageName =
            (resolvedPage['name'] ?? resolvedPage['pageName'] ?? pageName)
                .toString();
        currentPageDisplayName =
            (resolvedPage['displayName'] ??
                    resolvedPage['display_name'] ??
                    currentPageName)
                .toString();
        statusMessage = source == 'live'
            ? 'Matched page "$pageName".'
            : 'Using cached page data for "$pageName" due to temporary fetch issues.';

        _waitingForInitialSwitch = false;

        if (addToHistory) {
          if (_navigationHistory.isEmpty ||
              _navigationHistory.last != currentPageName) {
            _navigationHistory.add(currentPageName);
            debugPrint(
              'fetchGridDataForPage: Added to history. Stack: $_navigationHistory',
            );
          }
        }
      });
      return true;
    }

    setState(() {
      isLoading = true;
    });
    try {
      debugPrint(
        'fetchGridDataForPage: Making HTTP request to ${EnvironmentConfig.apiBaseUrl}/pages?name=$pageName',
      );
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/pages?name=$pageName',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        maxRetries: 3,
        timeoutSeconds: 30,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _cachedPagesPayload = data;
        if (!applyPageFromPayload(data, source: 'live')) {
          setState(() {
            gridButtons = [];
            currentPageName = pageName;
            currentPageDisplayName = pageName;
            statusMessage = 'No matching page found for "$pageName".';
          });
        }
      } else {
        if (_cachedPagesPayload.isNotEmpty &&
            applyPageFromPayload(_cachedPagesPayload, source: 'cache')) {
          return;
        }
        setState(() {
          gridButtons = [];
          currentPageName = pageName;
          currentPageDisplayName = pageName;
          statusMessage =
              'Error fetching page "$pageName". Status: ' +
              response.statusCode.toString();
        });
      }
    } catch (e) {
      if (_cachedPagesPayload.isNotEmpty &&
          applyPageFromPayload(_cachedPagesPayload, source: 'cache')) {
        return;
      }
      setState(() {
        gridButtons = [];
        currentPageName = pageName;
        currentPageDisplayName = pageName;
        statusMessage = 'Exception fetching page "$pageName": $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadComposeSession() async {
    final loaded = await ComposeSessionService.load(widget.aacUserId);
    if (!mounted) return;
    setState(() {
      _composeSession = loaded;
    });
  }

  Future<void> _persistComposeSession() async {
    await ComposeSessionService.save(widget.aacUserId, _composeSession);
  }

  Map<String, dynamic> _buildLlmRequestBody(String prompt) {
    return {
      'prompt': prompt,
      'compose_mode': _composeSession.active,
      'compose_body': _composeSession.active ? _composeSession.text : '',
    };
  }

  List<Map<String, dynamic>> _effectiveGridButtons() {
    final baseButtons = gridButtons
        .where(
          (btn) =>
              (btn['hidden'] != true) &&
              ((btn['text'] ?? '').toString().trim().isNotEmpty),
        )
        .map((btn) => Map<String, dynamic>.from(btn))
        .toList();

    return baseButtons;
  }

  Future<void> _appendToComposeText(String rawText) async {
    if (!_composeSession.active) return;
    final normalized = rawText
        .replaceAll('[PAUSE]', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return;

    final existing = _composeSession.text.trim();
    final merged = existing.isEmpty ? normalized : '$existing $normalized';

    if (!mounted) return;
    setState(() {
      _composeSession = _composeSession.copyWith(text: merged);
      statusMessage = 'Creation in progress';
    });
    await _persistComposeSession();
  }

  Future<void> _startComposeSession({
    required String documentType,
    String seedText = '',
    String? documentId,
    String title = '',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _composeSession = ComposeSessionData(
        active: true,
        documentType: documentType,
        documentId: documentId,
        title: title,
        text: seedText.trim(),
        startedAt: now,
        sourceFrom: currentPageName,
      );
      statusMessage = 'Creation in progress';
    });
    await _persistComposeSession();

    if (currentPageName != 'home') {
      await fetchGridDataForPage('home');
    }
  }

  Future<void> _initializeComposeSession({
    required String documentType,
    String seedText = '',
    String? documentId,
    String title = '',
    String? sourceFrom,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _composeSession = ComposeSessionData(
        active: true,
        documentType: documentType,
        documentId: documentId,
        title: title,
        text: seedText.trim(),
        startedAt: now,
        sourceFrom: sourceFrom ?? currentPageName,
      );
      statusMessage = 'Creation in progress';
    });
    await _persistComposeSession();
  }

  Future<void> _openComposeBuilder({String? sourceContext}) async {
    final initialSession = _composeSession.active
        ? _composeSession
        : await ComposeSessionService.load(widget.aacUserId);
    if (!mounted || !initialSession.active) {
      return;
    }

    const resolvedSourceContext = 'compose a message';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FreestylePage(
          idToken: widget.idToken,
          aacUserId: widget.aacUserId,
          displayName: widget.displayName,
          sourceContext: resolvedSourceContext,
          sourcePage: 'compose',
          isLLMGenerated: false,
          originatingButtonText: null,
          composeMode: true,
          initialComposeSession: initialSession,
          initialDocumentType: initialSession.documentType,
        ),
      ),
    );

    if (!mounted) return;

    final refreshed = await ComposeSessionService.load(widget.aacUserId);
    if (!mounted) return;

    setState(() {
      _composeSession = refreshed;
    });

    if (_composeSession.active) {
      _composeGridStack.clear();
      _composePageStack.clear();
      _openComposeFinalizeGrid();
      return;
    }

    await fetchGridDataForPage('home', addToHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        scanningIndex = null;
      });
      _maybeStartScanning();
    });
  }

  // ---------- compose grid navigation helpers ----------

  void _loadComposeGrid(
    List<Map<String, dynamic>> buttons,
    String gridName, {
    bool pushToStack = true,
    String? nextStatusMessage,
  }) {
    if (pushToStack) {
      _composeGridStack.add(List<Map<String, dynamic>>.from(gridButtons));
      _composePageStack.add(currentPageName);
    }
    setState(() {
      gridButtons = buttons;
      currentPageName = gridName;
      scanningIndex = null;
      isLoading = false;
      statusMessage = nextStatusMessage ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        scanningIndex = null;
      });
      _maybeStartScanning();
    });
  }

  void _restoreFromComposeGrid() {
    if (_composeGridStack.isNotEmpty) {
      final prevButtons = _composeGridStack.removeLast();
      final prevPage = _composePageStack.isNotEmpty
          ? _composePageStack.removeLast()
          : 'home';
      setState(() {
        gridButtons = prevButtons;
        currentPageName = prevPage;
        scanningIndex = null;
        statusMessage = '';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          scanningIndex = null;
        });
        _maybeStartScanning();
      });
    } else {
      fetchGridDataForPage('home');
    }
  }

  void _openComposeEntryGrid() {
    _loadComposeGrid([
      {
        'text': 'Cancel',
        'speechPhrase': 'Cancel',
        'composeSpecial': 'compose_back',
        'hidden': false,
      },
      {
        'text': 'Create New',
        'speechPhrase': 'Create New',
        'composeSpecial': 'compose_new',
        'hidden': false,
      },
      {
        'text': 'Open Existing',
        'speechPhrase': 'Open Existing',
        'composeSpecial': 'compose_open_list',
        'hidden': false,
      },
      {
        'text': 'Delete Existing',
        'speechPhrase': 'Delete Existing',
        'composeSpecial': 'compose_delete_list',
        'hidden': false,
      },
    ], '__compose_entry__');
  }

  Future<void> _openComposeDocListGrid({
    bool forDelete = false,
    bool pushToStack = true,
    String? statusOverride,
  }) async {
    setState(() {
      isLoading = true;
      statusMessage = forDelete
          ? 'Loading creations to delete...'
          : 'Loading saved creations...';
    });
    try {
      List<dynamic> docs = <dynamic>[];
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/compose/documents',
        baseHeaders: {'X-User-ID': widget.aacUserId},
      );
      if (!mounted) return;
      if (response.statusCode == 404) {
        docs = await ComposeSessionService.loadLocalDocuments(widget.aacUserId);
      } else if (response.statusCode != 200) {
        setState(() {
          isLoading = false;
          statusMessage = 'Unable to load creations (${response.statusCode}).';
        });
        return;
      } else {
        final decoded = json.decode(response.body);
        docs =
            (decoded is Map<String, dynamic>
                ? decoded['documents'] as List<dynamic>?
                : null) ??
            <dynamic>[];
      }

      if (docs.isEmpty) {
        if (forDelete) {
          _loadComposeGrid(
            [
              {
                'text': 'Back',
                'speechPhrase': 'Back',
                'composeSpecial': 'compose_back',
                'hidden': false,
              },
            ],
            '__compose_delete_list__',
            pushToStack: pushToStack,
            nextStatusMessage:
                statusOverride ?? 'No saved creations to delete.',
          );
        } else {
          setState(() {
            isLoading = false;
            statusMessage = 'No saved creations yet.';
          });
        }
        return;
      }
      final List<Map<String, dynamic>> docButtons = [
        {
          'text': 'Back',
          'speechPhrase': 'Back',
          'composeSpecial': 'compose_back',
          'hidden': false,
        },
      ];
      for (final rawDoc in docs) {
        final doc = rawDoc as Map<String, dynamic>;
        final title = (doc['title'] ?? 'Untitled').toString();
        docButtons.add({
          'text': title,
          'speechPhrase': title,
          'composeSpecial': forDelete
              ? 'compose_delete_select'
              : 'compose_open_doc',
          'composeDocId': (doc['id'] ?? '').toString(),
          'composeDocType': (doc['document_type'] ?? 'story').toString(),
          'composeDocBody': (doc['body'] ?? '').toString(),
          'composeDocTitle': title,
          'composeDocIsLocalFallback': doc['is_local_fallback'] == true,
          'hidden': false,
        });
      }
      _loadComposeGrid(
        docButtons,
        forDelete ? '__compose_delete_list__' : '__compose_doc_list__',
        pushToStack: pushToStack,
        nextStatusMessage: statusOverride,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        statusMessage = 'Unable to load creations: $e';
      });
    }
  }

  Future<void> _openComposeDeleteConfirmGrid(
    Map<String, dynamic> buttonData,
  ) async {
    final title = (buttonData['composeDocTitle'] ?? 'Untitled').toString();
    final docId = (buttonData['composeDocId'] ?? '').toString().trim();
    final documentType = (buttonData['composeDocType'] ?? 'story').toString();
    final body = (buttonData['composeDocBody'] ?? '').toString();
    final isLocalFallback = buttonData['composeDocIsLocalFallback'] == true;

    _loadComposeGrid(
      [
        {
          'text': 'No',
          'speechPhrase': 'No',
          'composeSpecial': 'compose_delete_no',
          'hidden': false,
        },
        {
          'text': 'Yes',
          'speechPhrase': 'Yes',
          'composeSpecial': 'compose_delete_yes',
          'composeDocId': docId,
          'composeDocType': documentType,
          'composeDocBody': body,
          'composeDocTitle': title,
          'composeDocIsLocalFallback': isLocalFallback,
          'hidden': false,
        },
      ],
      '__compose_delete_confirm__',
      nextStatusMessage: 'Delete "$title"?',
    );

    await _announceWithTimeout(
      'Delete $title? Select yes or no.',
      routing: 'system',
    );
  }

  Future<void> _deleteComposeDocument({
    required String documentId,
    required String title,
    bool isLocalFallback = false,
  }) async {
    if (documentId.trim().isEmpty) {
      setState(() {
        statusMessage = 'Unable to delete this creation.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      statusMessage = 'Deleting "$title"...';
    });

    try {
      bool deleted = false;

      if (isLocalFallback || documentId.startsWith('local_')) {
        deleted = await ComposeSessionService.deleteLocalDocument(
          widget.aacUserId,
          documentId,
        );
      } else {
        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'DELETE',
          '${EnvironmentConfig.apiBaseUrl}/api/compose/documents/${Uri.encodeComponent(documentId)}',
          baseHeaders: {'X-User-ID': widget.aacUserId},
        );

        if (!mounted) return;
        if (response.statusCode == 200) {
          deleted = true;
        } else if (response.statusCode == 404) {
          deleted = await ComposeSessionService.deleteLocalDocument(
            widget.aacUserId,
            documentId,
          );
        } else {
          setState(() {
            isLoading = false;
            statusMessage = 'Delete failed (${response.statusCode}).';
          });
          return;
        }
      }

      if (!deleted) {
        setState(() {
          isLoading = false;
          statusMessage = 'Creation not found.';
        });
        return;
      }

      if (currentPageName == '__compose_delete_confirm__') {
        _restoreFromComposeGrid();
      }

      await _announceWithTimeout('Deleted $title.', routing: 'system');

      await _openComposeDocListGrid(
        forDelete: true,
        pushToStack: false,
        statusOverride: 'Deleted "$title".',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        statusMessage = 'Delete failed: $e';
      });
    }
  }

  Future<void> _saveComposeAndExit() async {
    final body = _composeSession.text.trim();
    if (body.isEmpty) {
      setState(() {
        statusMessage = 'Creation is empty. Add words before saving.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      statusMessage = 'Saving creation...';
    });

    try {
      bool isTitleInvalid(String value) {
        final normalized = value.trim().toLowerCase();
        if (normalized.isEmpty) return true;
        const invalid = <String>{
          'json',
          'title',
          'response',
          'option',
          'options',
          'untitled',
          'untitled creation',
          'n/a',
          'na',
          'null',
        };
        if (invalid.contains(normalized)) return true;
        if (normalized.startsWith('{') || normalized.startsWith('[')) {
          return true;
        }
        return false;
      }

      String generatedTitle = _composeSession.title.trim();
      if (isTitleInvalid(generatedTitle)) {
        generatedTitle = await _generateComposeTitle(body);
      }

      if (isTitleInvalid(generatedTitle)) {
        generatedTitle = 'Untitled Creation';
      }

      setState(() {
        statusMessage = 'Generated title: "$generatedTitle"';
      });

      final payload = {
        'document_type': _composeSession.documentType,
        'title': generatedTitle,
        'body': body,
        'to': const <String>[],
        'cc': const <String>[],
        'bcc': const <String>[],
        'subject': '',
      };

      final isUpdate = (_composeSession.documentId ?? '').trim().isNotEmpty;
      final endpoint = isUpdate
          ? '${EnvironmentConfig.apiBaseUrl}/api/compose/documents/${Uri.encodeComponent(_composeSession.documentId!.trim())}'
          : '${EnvironmentConfig.apiBaseUrl}/api/compose/documents';

      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        isUpdate ? 'PUT' : 'POST',
        endpoint,
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      var savedViaLocalFallback = false;
      if (response.statusCode == 404) {
        final localId = await ComposeSessionService.upsertLocalDocument(
          widget.aacUserId,
          documentId: _composeSession.documentId,
          documentType: _composeSession.documentType,
          title: generatedTitle,
          body: body,
        );
        savedViaLocalFallback = true;
        if ((_composeSession.documentId ?? '').trim().isEmpty) {
          setState(() {
            _composeSession = _composeSession.copyWith(documentId: localId);
          });
        }
      } else if (response.statusCode != 200) {
        setState(() {
          statusMessage = 'Save failed (${response.statusCode}).';
        });
        return;
      }

      setState(() {
        _composeSession = const ComposeSessionData.inactive();
        statusMessage = savedViaLocalFallback
            ? 'Creation saved locally as "$generatedTitle".'
            : 'Creation saved as "$generatedTitle".';
      });
      await ComposeSessionService.clear(widget.aacUserId);

      await _announceWithTimeout(
        savedViaLocalFallback
            ? 'Creation saved locally as $generatedTitle. Returning home.'
            : 'Creation saved as $generatedTitle. Returning home.',
        routing: 'system',
      );

      await fetchGridDataForPage('home', addToHistory: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          scanningIndex = null;
        });
        _maybeStartScanning();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'Save failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<String> _generateComposeTitle(String body) async {
    final invalidExact = <String>{
      'json',
      'title',
      'response',
      'option',
      'options',
      'untitled',
      'untitled creation',
      'n/a',
      'na',
      'null',
    };

    String normalizeCandidate(String input) {
      var text = input.replaceAll(RegExp(r'\s+'), ' ').trim();
      text = text.replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceAll(RegExp(r'\s*```$'), '');
      text = text.replaceAll(RegExp(r'^[\-*#\d\.\)\s]+'), '');
      text = text.replaceAll(
        RegExp(r'^(title|name|subject)\s*[:\-]\s*', caseSensitive: false),
        '',
      );
      text = text.replaceAll('`', '');
      text = text.replaceAll(RegExp("^['\\\"]+|['\\\"]+\$"), '').trim();
      text = text.replaceAll(RegExp(r'[.!?]+$'), '').trim();
      if (text.contains('\n')) {
        final firstLine = text
            .split('\n')
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        text = firstLine;
      }
      return text;
    }

    String extractCandidate(dynamic raw) {
      if (raw == null) return '';

      if (raw is Map<String, dynamic>) {
        const preferredKeys = <String>[
          'title',
          'name',
          'subject',
          'text',
          'content',
          'response',
          'option',
        ];
        for (final key in preferredKeys) {
          if (raw.containsKey(key)) {
            final candidate = extractCandidate(raw[key]);
            if (candidate.isNotEmpty) return candidate;
          }
        }
        for (final value in raw.values) {
          final candidate = extractCandidate(value);
          if (candidate.isNotEmpty) return candidate;
        }
        return '';
      }

      if (raw is List) {
        for (final item in raw) {
          final candidate = extractCandidate(item);
          if (candidate.isNotEmpty) return candidate;
        }
        return '';
      }

      var text = normalizeCandidate(raw.toString());
      if (text.isEmpty) return '';

      if ((text.startsWith('{') && text.endsWith('}')) ||
          (text.startsWith('[') && text.endsWith(']'))) {
        try {
          final decoded = json.decode(text);
          final nested = extractCandidate(decoded);
          if (nested.isNotEmpty) {
            text = nested;
          }
        } catch (_) {}
      }

      text = normalizeCandidate(text);
      final lower = text.toLowerCase();
      if (invalidExact.contains(lower)) return '';
      if (RegExp(r'^[^a-zA-Z0-9]+$').hasMatch(text)) return '';
      if (lower.startsWith('json ') || lower.contains(' json ')) return '';

      final words = text.split(' ').where((w) => w.trim().isNotEmpty).toList();
      if (words.isEmpty) return '';
      if (words.length == 1 &&
          invalidExact.contains(words.first.toLowerCase())) {
        return '';
      }
      if (words.length > 6) {
        text = words.take(6).join(' ');
      }
      return text;
    }

    String buildContentBasedTitle(String text) {
      final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty) return 'Untitled Creation';

      final stopwords = <String>{
        'the',
        'and',
        'for',
        'with',
        'that',
        'this',
        'from',
        'have',
        'your',
        'you',
        'are',
        'was',
        'were',
        'been',
        'into',
        'about',
        'their',
        'they',
        'them',
        'then',
        'than',
        'there',
        'here',
        'what',
        'when',
        'where',
        'will',
        'would',
        'could',
        'should',
        'because',
        'while',
        'after',
        'before',
        'during',
        'over',
        'under',
        'between',
        'through',
        'within',
        'without',
        'onto',
        'upon',
        'very',
        'just',
        'also',
        'only',
        'more',
        'most',
        'some',
        'such',
        'much',
        'many',
        'like',
        'make',
        'made',
        'json',
      };

      final matches = RegExp(r"[A-Za-z][A-Za-z']+").allMatches(clean);
      final freq = <String, int>{};
      for (final match in matches) {
        final word = match.group(0)!.toLowerCase();
        if (word.length < 4) continue;
        if (stopwords.contains(word)) continue;
        freq[word] = (freq[word] ?? 0) + 1;
      }

      if (freq.isNotEmpty) {
        final sorted = freq.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topWords = sorted.take(3).map((entry) => entry.key).toList();
        if (topWords.length >= 2) {
          final titled = topWords
              .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
              .join(' ');
          return titled;
        }
      }

      final fallbackWords = clean
          .split(' ')
          .map((word) => word.replaceAll(RegExp(r"[^A-Za-z0-9'-]"), ''))
          .where((word) => word.isNotEmpty)
          .where((word) => word.toLowerCase() != 'json')
          .take(5)
          .toList();
      if (fallbackWords.isNotEmpty) {
        return fallbackWords.join(' ');
      }
      return 'Untitled Creation';
    }

    String generatedTitle = '';
    String debugInfo = '';

    try {
      final titleResp = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/compose/generate-title',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'body': body}),
        timeoutSeconds: 45,
      );
      if (titleResp.statusCode == 200) {
        try {
          final titleData = json.decode(titleResp.body);
          generatedTitle = extractCandidate(titleData);
          debugInfo = generatedTitle.isNotEmpty
              ? '[Tier1-compose-title]'
              : '[Tier1-invalid-payload]';
        } catch (e) {
          debugInfo = '[Tier1-parse-error: $e]';
        }
      } else {
        debugInfo = '[Tier1-http-${titleResp.statusCode}]';
      }
    } catch (e) {
      debugInfo = '[Tier1-exception: $e]';
    }

    if (generatedTitle.isEmpty) {
      try {
        final fallbackPrompt =
            'Read this composition and return exactly one descriptive title (2 to 6 words). '
            'Return plain title text only. No JSON, no code block, no list, no explanation.\n\n'
            'Composition:\n${body.substring(0, body.length > 800 ? 800 : body.length)}';

        final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'POST',
          '${EnvironmentConfig.apiBaseUrl}/api/generate-options',
          baseHeaders: {
            'X-User-ID': widget.aacUserId,
            'Content-Type': 'application/json',
          },
          body: json.encode({'prompt': fallbackPrompt, 'count': 1}),
          timeoutSeconds: 45,
        );

        if (response.statusCode == 200) {
          try {
            final data = json.decode(response.body);
            generatedTitle = extractCandidate(data);
            debugInfo += generatedTitle.isNotEmpty
                ? '[Tier2-generate-options]'
                : '[Tier2-invalid-payload]';
          } catch (e) {
            debugInfo += '[Tier2-parse-error: $e]';
          }
        } else {
          debugInfo += '[Tier2-http-${response.statusCode}]';
        }
      } catch (e) {
        debugInfo += '[Tier2-exception: $e]';
      }
    }

    if (generatedTitle.isEmpty) {
      generatedTitle = buildContentBasedTitle(body);
      debugInfo += '[Tier3-content-analysis]';
    }

    final finalTitle = normalizeCandidate(generatedTitle);
    final resolvedTitle = finalTitle.isEmpty ? 'Untitled Creation' : finalTitle;
    print('DEBUG_TITLE_GENERATION: $debugInfo => "$resolvedTitle"');
    return resolvedTitle;
  }

  Future<void> _discardComposeAndExit() async {
    setState(() {
      _composeSession = const ComposeSessionData.inactive();
      statusMessage = 'Creation discarded.';
    });
    await ComposeSessionService.clear(widget.aacUserId);
  }

  Future<bool> _aiEditCompose() async {
    final body = _composeSession.text.trim();
    if (body.isEmpty) {
      setState(() {
        statusMessage = 'Creation is empty. Add words before AI edit.';
      });
      return false;
    }

    setState(() {
      isLoading = true;
      statusMessage = 'AI editing creation...';
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/compose/ai-edit',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({'body': body}),
        timeoutSeconds: 90,
      );

      if (response.statusCode == 404) {
        final fallbackResponse =
            await AuthenticatedHttpClient.makeAuthenticatedRequest(
              'POST',
              '${EnvironmentConfig.apiBaseUrl}/api/freestyle/cleanup-text',
              baseHeaders: {
                'X-User-ID': widget.aacUserId,
                'Content-Type': 'application/json',
              },
              body: json.encode({'text_to_cleanup': body}),
              timeoutSeconds: 90,
            );

        if (fallbackResponse.statusCode == 200) {
          final fallbackDecoded = json.decode(fallbackResponse.body);
          final cleaned =
              (fallbackDecoded is Map<String, dynamic>
                      ? fallbackDecoded['cleaned_text']
                      : '')
                  .toString()
                  .trim();

          if (cleaned.isNotEmpty) {
            setState(() {
              _composeSession = _composeSession.copyWith(text: cleaned);
              statusMessage = 'AI edit complete. Revised creation loaded.';
            });
            await _persistComposeSession();
            return true;
          }
        }

        setState(() {
          statusMessage =
              'AI edit endpoint not available (404), and cleanup fallback failed.';
        });
        return false;
      }

      if (response.statusCode != 200) {
        String backendError = '';
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic>) {
            backendError = (decoded['error'] ?? decoded['detail'] ?? '')
                .toString()
                .trim();
          }
        } catch (_) {}
        setState(() {
          statusMessage = backendError.isNotEmpty
              ? 'AI edit failed (${response.statusCode}): $backendError'
              : 'AI edit failed (${response.statusCode}).';
        });
        return false;
      }

      final decoded = json.decode(response.body);
      final success = decoded is Map<String, dynamic>
          ? decoded['success'] != false
          : false;
      final edited =
          (decoded is Map<String, dynamic> ? decoded['edited_body'] : '')
              .toString()
              .trim();

      if (!success) {
        final backendError = decoded is Map<String, dynamic>
            ? (decoded['error'] ?? 'AI edit failed.').toString().trim()
            : 'AI edit failed.';
        setState(() {
          statusMessage = backendError;
        });
        return false;
      }

      if (edited.isEmpty) {
        setState(() {
          statusMessage = 'AI edit returned empty content.';
        });
        return false;
      }

      setState(() {
        _composeSession = _composeSession.copyWith(text: edited);
        statusMessage = 'AI edit complete. Review updated creation below.';
      });
      await _persistComposeSession();
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        statusMessage = 'AI edit failed: $e';
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _copyComposeToClipboard() async {
    final text = _composeSession.text.trim();
    if (text.isEmpty) {
      setState(() {
        statusMessage = 'Creation is empty. Nothing to copy.';
      });
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      statusMessage = 'Creation copied to clipboard.';
    });
  }

  Future<void> _saveComposeToFile() async {
    final text = _composeSession.text.trim();
    if (text.isEmpty) {
      setState(() {
        statusMessage = 'Creation is empty. Nothing to export.';
      });
      return;
    }

    final safeTitle =
        (_composeSession.title.trim().isEmpty
                ? 'creation_${DateTime.now().toIso8601String().substring(0, 10)}'
                : _composeSession.title.trim())
            .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save creation',
      fileName: '$safeTitle.txt',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );

    if (path == null || path.trim().isEmpty) {
      return;
    }

    final file = File(path);
    await file.writeAsString(text, flush: true);
    if (!mounted) return;
    setState(() {
      statusMessage = 'Creation exported to file.';
    });
  }

  void _openComposeExportGrid() {
    _loadComposeGrid([
      {
        'text': 'Back',
        'speechPhrase': 'Back',
        'composeSpecial': 'compose_back',
        'hidden': false,
      },
      {
        'text': 'Copy',
        'speechPhrase': 'Copy to clipboard',
        'composeSpecial': 'compose_copy',
        'hidden': false,
      },
      {
        'text': 'Save .txt',
        'speechPhrase': 'Save as text file',
        'composeSpecial': 'compose_save_file',
        'hidden': false,
      },
      {
        'text': 'Read Aloud',
        'speechPhrase': 'Read aloud',
        'composeSpecial': 'compose_read_aloud',
        'hidden': false,
      },
    ], '__compose_export__');
  }

  void _openComposeFinalizeGrid() {
    if (!_composeSession.active) return;
    _loadComposeGrid([
      {
        'text': 'Return',
        'speechPhrase': 'Return to creation',
        'composeSpecial': 'compose_return_builder',
        'hidden': false,
      },
      {
        'text': 'Save',
        'speechPhrase': 'Save creation',
        'composeSpecial': 'compose_save',
        'hidden': false,
      },
      {
        'text': 'Discard',
        'speechPhrase': 'Discard creation',
        'composeSpecial': 'compose_discard',
        'hidden': false,
      },
      {
        'text': 'Read',
        'speechPhrase': 'Read creation',
        'composeSpecial': 'compose_read',
        'hidden': false,
      },
      {
        'text': 'Export',
        'speechPhrase': 'Export creation',
        'composeSpecial': 'compose_export_menu',
        'hidden': false,
      },
      {
        'text': 'AI Edit',
        'speechPhrase': 'AI Edit creation',
        'composeSpecial': 'compose_ai_edit',
        'hidden': false,
      },
    ], '__compose_finalize__');
  }

  Future<void> _activateComposeFromEmail({
    String seedText = '',
    String documentType = 'email',
  }) async {
    await _startComposeSession(documentType: documentType, seedText: seedText);
  }

  void _onAdminButtonPressed(String routeName) {
    debugPrint('Admin button pressed: $routeName');

    // Pause scanning silently instead of stopping it completely
    // This prevents the "Scanning paused" announcement but stops the audio switching
    if (isScanning) {
      _pauseScanning(silent: true);
    }

    _wakeWordService?.pauseWakeWordAutoRestart();
    _wakeWordService?.stopAllRecognizers();

    Navigator.pushNamed(context, routeName).then((_) {
      debugPrint('Returned from admin page: $routeName');

      // Resume scanning if it was paused
      if (_isScanningPaused) {
        _resumeScanning();
      } else {
        _maybeStartScanning();
      }

      _wakeWordService?.resumeWakeWordAutoRestart();
    });
  }

  void _onButtonSelected(int index) async {
    if (_isHandlingSwitchSelection) {
      debugPrint('_onButtonSelected: Ignoring duplicate switch selection');
      return;
    }

    _isHandlingSwitchSelection = true;
    _stopAuditoryScanning();
    if (_isAnnouncingScanningPrompt) {
      flutterTts.stop();
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      } else {
        _isAnnouncingScanningPrompt = false;
      }
    }

    try {
      final definedButtons = _effectiveGridButtons();
      if (index < 0 || index >= definedButtons.length) return;
      final btn = definedButtons[index];
      // Only handle the button action; let handleButtonAction manage all TTS/announcement logic
      await handleButtonAction(btn);
      // Do NOT restart scanning here. Scanning will be restarted after grid update/navigation.
    } finally {
      _isHandlingSwitchSelection = false;
    }
  }

  void _handleStepModeTabAdvance() {
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final scanMode = settingsProvider.settings?.scanMode ?? 'auto';

    if (scanMode != 'step' || !isScanning) {
      return;
    }

    debugPrint(
      'Tab pressed: scanMode=$scanMode, isScanning=$isScanning, _isAnnouncingScanningPrompt=$_isAnnouncingScanningPrompt',
    );

    if (_isAnnouncingScanningPrompt) {
      debugPrint('Tab: Interrupting scanning announcement');
      flutterTts.stop();
      if (mounted) {
        setState(() {
          _isAnnouncingScanningPrompt = false;
        });
      }
    }

    if (scanningIndex != null) {
      debugPrint('Tab: Advancing in step mode from index $scanningIndex');
      _runScanStepSafe('step_mode_tab');
    }

    gridFocusNode?.requestFocus();
  }

  Future<void> _announce(String text) async {
    // Use backend TTS with force speaker and bracketed silence.mp3 for iOS
    _wakeWordService?.pauseWakeWordAutoRestart();
    debugPrint('Stopping wake word listening before announcement: $text');
    _wakeWordService?.stopWakeWordListening();
    await announceViaBackend(text);
    _wakeWordService?.resumeWakeWordAutoRestart();
    debugPrint('Resumed wake word listening after announcement');
  }

  Future<void> _performAppRefresh() async {
    if (_isRefreshing) return; // Prevent multiple refreshes

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Show refresh feedback
      _showSpeechBubbleOverlay('Refreshing app...');

      // Trigger native Android refresh
      await AppHealthManager.instance.triggerAppRefresh();

      // Record activity to reset timeout
      AppHealthManager.instance.recordActivity();

      // Restart scanning if needed
      _maybeStartScanning();

      // Show completion feedback
      _showSpeechBubbleOverlay('App refreshed!');
    } catch (e) {
      debugPrint('App refresh failed: $e');
      _showSpeechBubbleOverlay('Refresh failed');
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _getLLMResponse(
    String question, {
    bool wasInPausedState = false,
  }) async {
    try {
      if (mounted) {
        setState(() {
          _showBottomStatusText = true;
          statusMessage = 'Generating AI options...';
        });
      }

      // Android notification sounds suppressed globally

      // Use the passed paused state information instead of checking current state
      debugPrint(
        '_getLLMResponse: Starting LLM call, wasInPausedState=$wasInPausedState',
      );

      // NOW setup Bluetooth audio routing after question is heard (was skipped during announcement)
      debugPrint(
        '_getLLMResponse: Setting up Bluetooth audio routing after question detection...',
      );
      if (!kIsWeb && Platform.isIOS) {
        try {
          const platform = MethodChannel('audio_routing');
          debugPrint(
            '_getLLMResponse: Switching to default audio routing (Bluetooth)...',
          );
          await platform.invokeMethod('resetToDefault');
          await Future.delayed(
            Duration(milliseconds: 100),
          ); // Brief settle time

          debugPrint(
            '_getLLMResponse: Playing silence.mp3 to prime Bluetooth audio path...',
          );
          final player = AudioPlayer();
          await player.setAsset('assets/silence.mp3');

          // Wait for silence to complete to ensure Bluetooth audio path is ready
          final completer = Completer<void>();
          StreamSubscription? sub;

          sub = player.playerStateStream.listen((state) {
            if (state.processingState == ProcessingState.completed) {
              debugPrint(
                '_getLLMResponse: Silence playback completed - Bluetooth audio path primed',
              );
              if (!completer.isCompleted) {
                completer.complete();
                sub?.cancel();
              }
            }
          });

          await player.play();

          // Add timeout protection to prevent freezing if silence.mp3 doesn't complete
          await completer.future.timeout(
            const Duration(milliseconds: 2000),
            onTimeout: () {
              debugPrint(
                '_getLLMResponse: Bluetooth priming silence.mp3 timed out, continuing anyway',
              );
              sub?.cancel();
            },
          );

          await player.dispose();

          debugPrint(
            '_getLLMResponse: Bluetooth audio priming completed successfully',
          );
        } catch (e) {
          debugPrint('_getLLMResponse: Error with audio routing/priming: $e');
        }
      }

      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      final userSettings = settingsProvider.settings;
      final llmOptions = userSettings?.llmOptions ?? 10;
      final summaryInstruction = (userSettings?.summaryOff ?? false)
          ? 'The "summary" key should contain the exact same FULL text as the "option" key.'
          : 'If the generated option is more than 5 words, the "summary" key should be a 3-5 word abbreviation of each option, including the exact key words from the option. If the option is 5 words or less, the "summary" key should contain the exact same FULL text as the "option" key.';
      final promptForLLM = _composeSession.active
          ? 'Provide up to "$llmOptions" short written-composition options related to: "$question".\n'
                'This is COMPOSE MODE. The user is writing a document for someone who may not be physically present.\n'
                'Ignore location, people present, room context, and current activity.\n'
                'Generate natural next phrases or sentences the user could add to the written composition.\n'
                'Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.\n'
                'The "option" key should contain the FULL option text.\n'
                'The "keywords" key should contain a list of 3-5 important words from the option.\n'
                '${summaryInstruction}\n'
                'Example: [{"option": "I wanted to write and tell you how much this meant to me.", "summary": "Tell you this meant", "keywords": ["write", "tell", "meant", "much", "you"]}, {"option": "It made the whole day feel more special.", "summary": "Day more special", "keywords": ["day", "special", "feel", "whole", "made"]}]'
                '${_getComposePromptContext()}'
          : 'Provide up to "$llmOptions" short, single-phrase options related to: "$question".\n'
                'Format your response as a JSON list where each item has "option", "summary", and "keywords" keys.\n'
                'The "option" key should contain the FULL option text.\n'
                'The "keywords" key should contain a list of 3-5 important words from the option.\n'
                '${summaryInstruction}\n'
                'Example: [{"option": "What a fantastic day!", "summary": "Fantastic day", "keywords": ["good", "happy", "great", "day", "fun"]}, {"option": "Can I have some water please?", "summary": "Water please", "keywords": ["water", "drink", "thirsty", "beverage"]}]';
      debugPrint('🤖🤖🤖 LLM REQUEST STARTED 🤖🤖🤖');
      debugPrint('🤖 Question: $question');
      debugPrint('🤖 LLM Options Count: $llmOptions');
      _initializeFollowUpConversation(question);

      final response = await retryNetworkOperation(
        () async => await AuthenticatedHttpClient.makeAuthenticatedRequest(
          'POST',
          '${EnvironmentConfig.apiBaseUrl}/llm',
          baseHeaders: {
            'X-User-ID': widget.aacUserId,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(_buildLlmRequestBody(promptForLLM)),
          timeoutSeconds: 30,
        ),
        operationName: 'LLM Query',
        maxRetries: 3,
      );

      debugPrint('🤖 LLM Response Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        debugLogLLM(stage: 'LLM Response', response: response.body);

        var responseBody = response.body;

        // CRITICAL FIX: Strip markdown code fences if present (```json ... ```)
        if (responseBody.contains('```json')) {
          debugPrint(
            '🔍 Detected markdown code fence in response, stripping...',
          );
          responseBody = responseBody
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          debugPrint(
            '🔍 After stripping fences: ${responseBody.substring(0, responseBody.length > 200 ? 200 : responseBody.length)}',
          );
        }

        dynamic rawData = jsonDecode(responseBody);
        // Parse potentially malformed LLM response
        rawData = _parseLLMResponse(rawData);

        final List<dynamic> data = rawData is List ? rawData : [];
        List<Map<String, dynamic>> llmButtons = data
            .map(
              (item) => {
                'text': item['summary'] ?? item['option'] ?? '',
                'summary': item['summary'] ?? '',
                'option': item['option'] ?? '',
                'speechPhrase': item['option'] ?? '',
                'isLLMGenerated': true,
              },
            )
            .toList();

        // ALWAYS ADD Free Style and Ask Again buttons for wake word LLM responses
        debugPrint('DEBUG: Wake Word LLM Response Analysis:');
        debugPrint('DEBUG: - question: "$question"');
        debugPrint('DEBUG: - llmButtons.length: ${llmButtons.length}');
        debugPrint(
          'DEBUG: - Always adding Free Style and Ask Again buttons for wake word responses',
        );

        // Add "Free Style" button - allows user to construct their own response
        llmButtons.add({
          'text': 'Free Style',
          'speechPhrase': 'Free Style',
          'isLLMGenerated': true,
          'llmSpecial': 'freeStyle',
          'row': llmButtons.length,
          'col': 0,
        });
        debugPrint('DEBUG: Added Free Style button to wake word response');

        // Add "Please ask me again" button
        llmButtons.add({
          'text': 'Please ask me again',
          'speechPhrase': 'Please ask me again',
          'isLLMGenerated': true,
          'llmSpecial': 'askAgain',
          'row': llmButtons.length,
          'col': 0,
        });
        debugPrint(
          'DEBUG: Added Please ask me again button to wake word response',
        );

        // Add default buttons: Something Else, Go Back
        int nextIndex = llmButtons.length;
        llmButtons.add({
          'text': 'Something Else',
          'speechPhrase': 'Something Else',
          'isLLMGenerated': true,
          'llmSpecial': 'somethingElse',
          'row': nextIndex,
          'col': 0,
        });
        nextIndex++;
        llmButtons.add({
          'text': 'Go Back',
          'speechPhrase': 'Go Back',
          'isLLMGenerated': true,
          'llmSpecial': 'goBack',
          'row': nextIndex,
          'col': 0,
        });
        _stopAuditoryScanning();
        setState(() {
          gridButtons = llmButtons;
          _isProcessingLLM = false;
          statusMessage = null;
        });

        // AUDIO ROUTING FIX: Wait for any announcements to completely finish
        // before starting scanning to prevent audio routing conflicts
        await _waitForAnnouncementComplete();

        // If we were in a paused state before LLM, automatically resume scanning with new options
        if (wasInPausedState) {
          debugPrint(
            '_getLLMResponse: Auto-resuming scanning because we were paused before LLM',
          );
          debugPrint(
            '_getLLMResponse: Current _suppressScanning state: $_suppressScanning',
          );
          debugPrint(
            '_getLLMResponse: Current _waitingForUserInput state: $_waitingForUserInput',
          );
          debugPrint(
            '_getLLMResponse: Current _isScanningPaused state: $_isScanningPaused',
          );
          debugPrint(
            '_getLLMResponse: Resetting scan cycle count for fresh start with new options',
          );

          // CRITICAL FIX: Reset the scan cycle count when auto-resuming with new LLM options
          // This allows the full scanning loop cycles to run with the new options
          _currentScanCycle = 0;

          // CRITICAL FIX: Ensure ALL scanning blocking flags are cleared for auto-resume
          _suppressScanning = false;
          _waitingForUserInput = false;
          _isScanningPaused = false;

          debugPrint(
            '_getLLMResponse: After clearing flags - _suppressScanning: $_suppressScanning, _waitingForUserInput: $_waitingForUserInput, _isScanningPaused: $_isScanningPaused',
          );

          _maybeStartScanning(); // This will start fresh scanning

          final settingsProvider = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final waitForSwitch =
              settingsProvider.settings?.waitForSwitchToScan ?? false;
          if (waitForSwitch && _waitingForInitialSwitch) {
            unawaited(_playWaitForSwitchNotification());
          } else {
            // Add a small delay to let scanning start, then announce that we have new options
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await Future.delayed(const Duration(milliseconds: 500));
              await _speakPersonalVoice(
                "New options available. Scanning resumed.",
              );
            });
          }
        } else {
          // Normal restart scanning after LLM results
          debugPrint('_getLLMResponse: Starting normal scanning after LLM');
          debugPrint(
            '_getLLMResponse: Current _suppressScanning state: $_suppressScanning',
          );
          _maybeStartScanning();

          final settingsProvider = Provider.of<UserSettingsProvider>(
            context,
            listen: false,
          );
          final waitForSwitch =
              settingsProvider.settings?.waitForSwitchToScan ?? false;
          if (waitForSwitch && _waitingForInitialSwitch) {
            unawaited(_playWaitForSwitchNotification());
          }
        }

        // CRITICAL: Restart wake word listening after LLM processing completes
        await _forceRestartWakeWordService();
        debugPrint(
          '[LLM] Wake word service restarted after LLM processing complete',
        );

        // Note: Audio routing should already be reset to default when first speech was detected
        // No need to reset again here since onFirstSpeechDetected callback handles it
        //_stopAuditoryScanning();
        //_startAuditoryScanning();
      } else {
        setState(() {
          _isProcessingLLM = false;
          statusMessage = '❌ AI query failed - Scanning restarted';
        });

        // Show error banner with auto-reset after 5 seconds
        _updateStatusMessageWithAutoReset(
          '❌ AI query failed - Scanning restarted',
          resetAfter: const Duration(seconds: 5),
        );

        // Announce error and resume scanning
        await _speakPersonalVoice("AI Error has occurred");

        // CRITICAL FIX: Ensure ALL scanning blocking flags are cleared for auto-resume
        _suppressScanning = false;
        _waitingForUserInput = false;
        _isScanningPaused = false;

        _maybeStartScanning();

        // Restart wake word service even on error
        await _forceRestartWakeWordService();
        debugPrint('[LLM] Wake word service restarted after LLM error');

        // Note: Audio routing should already be reset when first speech was detected
        // No need to reset again here since onFirstSpeechDetected callback handles it
      }
    } catch (e) {
      final isTimeout =
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out');
      final errorMessage = isTimeout
          ? '❌ AI request timed out - Scanning restarted'
          : '❌ AI query failed - Scanning restarted';

      setState(() {
        _isProcessingLLM = false;
        statusMessage = errorMessage;
      });

      // Show error banner with auto-reset after 5 seconds
      _updateStatusMessageWithAutoReset(
        errorMessage,
        resetAfter: const Duration(seconds: 5),
      );

      debugPrint('[LLM] Error caught: $e');

      // Announce error and resume scanning
      await _speakPersonalVoice("AI Error has occurred");

      // CRITICAL FIX: Ensure ALL scanning blocking flags are cleared for auto-resume
      _suppressScanning = false;
      _waitingForUserInput = false;
      _isScanningPaused = false;

      _maybeStartScanning();

      // Restart wake word service even on exception
      await _forceRestartWakeWordService();
      debugPrint('[LLM] Wake word service restarted after LLM exception: $e');

      // Note: Audio routing should already be reset when first speech was detected
      // No need to reset again here since onFirstSpeechDetected callback handles it
    } finally {
      // CRITICAL: Ensure _isProcessingLLM is ALWAYS reset, even if exception occurs
      if (_isProcessingLLM) {
        setState(() {
          _isProcessingLLM = false;
        });
        debugPrint(
          '[LLM] SAFETY: Force-reset _isProcessingLLM flag in finally block',
        );
      }
    }

    // Always restore Android notification sounds after LLM processing
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const platform = MethodChannel('audio_routing');
        platform.invokeMethod('restoreNotificationSounds');
        debugPrint('_getLLMResponse: Notification sounds restored');
      } catch (e) {
        debugPrint(
          '_getLLMResponse: Failed to restore notification sounds: $e',
        );
      }
    }
  }

  // --- Admin Toolbar Lock/Unlock Methods ---

  void _toggleAdminToolbarLock() {
    if (_isAdminToolbarLocked) {
      _showPINDialog();
    } else {
      setState(() {
        _isAdminToolbarLocked = true;
        _pinAttempts = 0;
      });
    }
  }

  void _showPINDialog() {
    final TextEditingController pinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Admin PIN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter your 4-digit PIN:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, letterSpacing: 3),
                  decoration: const InputDecoration(
                    hintText: '••••',
                    counterText: '',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _validatePIN(pinController.text, context),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Or tap numbers below:',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                // Compact numeric keypad
                StatefulBuilder(
                  builder: (context, setKeypadState) {
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '1',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '2',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '3',
                              pinController,
                              setKeypadState,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '4',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '5',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '6',
                              pinController,
                              setKeypadState,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '7',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '8',
                              pinController,
                              setKeypadState,
                            ),
                            _buildKeypadButton(
                              '9',
                              pinController,
                              setKeypadState,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildKeypadButton(
                              '⌫',
                              pinController,
                              setKeypadState,
                              isBackspace: true,
                            ),
                            _buildKeypadButton(
                              '0',
                              pinController,
                              setKeypadState,
                            ),
                            const SizedBox(width: 40), // Empty space
                          ],
                        ),
                      ],
                    );
                  },
                ),
                if (_pinAttempts > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Incorrect PIN. Attempts: $_pinAttempts/2',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Reclaim focus after dialog closes
                _reclaimFocus();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _validatePIN(pinController.text, context),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    ).then((_) {
      // Reclaim focus when dialog is dismissed by any means
      _reclaimFocus();
    });
  }

  /// Build a simple keypad button for PIN entry
  Widget _buildKeypadButton(
    String label,
    TextEditingController controller,
    Function setState, {
    bool isBackspace = false,
  }) {
    return SizedBox(
      width: 50,
      height: 40,
      child: ElevatedButton(
        onPressed: () {
          if (isBackspace) {
            if (controller.text.isNotEmpty) {
              controller.text = controller.text.substring(
                0,
                controller.text.length - 1,
              );
              setState(() {});
            }
          } else {
            if (controller.text.length < 4) {
              controller.text += label;
              setState(() {});
            }
          }
        },
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          side: BorderSide(color: Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isBackspace ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _validatePIN(String enteredPIN, BuildContext dialogContext) {
    if (enteredPIN == _currentPIN) {
      // Correct PIN
      setState(() {
        _isAdminToolbarLocked = false;
        _pinAttempts = 0;
      });
      Navigator.of(dialogContext).pop();
      // Reclaim focus after successful PIN entry
      _reclaimFocus();
    } else {
      // Incorrect PIN
      setState(() {
        _pinAttempts++;
      });

      if (_pinAttempts >= 2) {
        // After 2 failed attempts, close dialog and stop prompting
        Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Too many incorrect attempts. Click the lock icon to try again.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {
          _pinAttempts = 0; // Reset for next time
        });
        // Reclaim focus after failed attempts
        _reclaimFocus();
      } else {
        // Show error in dialog and stay open
        Navigator.of(dialogContext).pop();
        _showPINDialog(); // Show dialog again with error count
      }
    }
  }

  // --- PIN Management Methods ---
  void _updatePINFromSettings(UserSettingsProvider settingsProvider) {
    final newPIN = settingsProvider.settings?.toolbarPIN ?? '1234';
    if (_currentPIN != newPIN) {
      setState(() {
        _currentPIN = newPIN;
      });
      debugPrint('Updated admin toolbar PIN (length: ${_currentPIN?.length})');
    }
  }

  // --- User Account & Authentication Methods ---
  void _switchUserAccount() async {
    try {
      // Get current Firebase user and token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user logged in');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No user currently logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final idToken = await user.getIdToken();
      if (idToken == null) {
        debugPrint('Failed to get user token');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to get authentication token'),
            backgroundColor: Colors.red,
          ),
        );
        // Reclaim focus after SnackBar
        _reclaimFocus();
        return;
      }

      // Fetch all user profiles to show selection page (use correct endpoint)
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/account/users'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('Switch account API response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final userProfiles = json.decode(response.body);
        debugPrint('User profiles received: ${userProfiles.length} profiles');

        if (userProfiles is List && userProfiles.isNotEmpty) {
          // Navigate to user selection page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => UserSelectionPage(
                idToken: idToken,
                userProfiles: userProfiles,
              ),
            ),
          );
        } else {
          debugPrint('No user profiles found in response');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No user accounts found for this login'),
              backgroundColor: Colors.orange,
            ),
          );
          // Reclaim focus after SnackBar
          _reclaimFocus();
        }
      } else {
        debugPrint('Failed to fetch user profiles: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load user accounts (${response.statusCode})',
            ),
            backgroundColor: Colors.red,
          ),
        );
        // Reclaim focus after SnackBar
        _reclaimFocus();
      }
    } catch (e) {
      debugPrint('Error switching user account: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error switching user account: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Reclaim focus after SnackBar
      _reclaimFocus();
    }
  }

  void _toggleTapInterface() async {
    try {
      if (_settingsProvider?.settings != null) {
        // Create updated settings with toggled interface mode
        final currentSettings = _settingsProvider!.settings!;
        final updatedSettings = UserSettings(
          scanDelay: currentSettings.scanDelay,
          wakeWordInterjection: currentSettings.wakeWordInterjection,
          wakeWordName: currentSettings.wakeWordName,
          countryCode: currentSettings.countryCode,
          speechRate: currentSettings.speechRate,
          llmOptions: currentSettings.llmOptions,
          freestyleOptions: currentSettings.freestyleOptions,
          scanningOff: currentSettings.scanningOff,
          summaryOff: currentSettings.summaryOff,
          selectedTtsVoiceName: currentSettings.selectedTtsVoiceName,
          gridColumns: currentSettings.gridColumns,
          lightColorValue: currentSettings.lightColorValue,
          darkColorValue: currentSettings.darkColorValue,
          toolbarPIN: currentSettings.toolbarPIN,
          scanLoopLimit: currentSettings.scanLoopLimit,
          autoClean: currentSettings.autoClean,
          displaySplash: currentSettings.displaySplash,
          displaySplashtime: currentSettings.displaySplashtime,
          enableMoodSelection: currentSettings.enableMoodSelection,
          currentMood: currentSettings.currentMood,
          enablePictograms: currentSettings.enablePictograms,
          disableTapPictograms: currentSettings.disableTapPictograms,
          sightWordGradeLevel: currentSettings.sightWordGradeLevel,
          enableSightWords: currentSettings.enableSightWords,
          spellLetterOrder: currentSettings.spellLetterOrder,
          vocabularyLevel: currentSettings.vocabularyLevel,
          waitForSwitchToScan: currentSettings.waitForSwitchToScan,
          scanMode: currentSettings.scanMode,
          useTapInterface:
              !currentSettings.useTapInterface, // Toggle the interface mode
          applicationVolume: currentSettings.applicationVolume,
          groupWakeWord: currentSettings.groupWakeWord,
          emailDefaultRecipient: currentSettings.emailDefaultRecipient,
          emailSubjectTemplate: currentSettings.emailSubjectTemplate,
          personalVolume: currentSettings.personalVolume,
          systemVolume: currentSettings.systemVolume,
          playWaitForSwitchChime: currentSettings.playWaitForSwitchChime,
          tapWordsRows: currentSettings.tapWordsRows,
          tapPhrasesRows: currentSettings.tapPhrasesRows,
          tapDynamicRows: currentSettings.tapDynamicRows,
          userLanguage: currentSettings.userLanguage,
          defaultPartnerLanguage: currentSettings.defaultPartnerLanguage,
          defaultPartnerVoice: currentSettings.defaultPartnerVoice,
          locationOverrideLanguages: currentSettings.locationOverrideLanguages,
          mascot: currentSettings.mascot,
        );

        // Save the settings
        await _settingsProvider!.saveSettings(updatedSettings);

        // Show feedback to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updatedSettings.useTapInterface
                  ? 'Switched to Tap Interface'
                  : 'Switched to Grid Interface',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Reclaim focus after SnackBar
        _reclaimFocus();

        // Navigate to tap interface if enabled
        if (updatedSettings.useTapInterface) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TapInterfacePage(
                idToken: widget.idToken,
                aacUserId: widget.aacUserId,
                displayName: widget.displayName,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling tap interface: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error switching interface: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Reclaim focus after SnackBar
      _reclaimFocus();
    }
  }

  void _signOut() async {
    try {
      // Sign out from Firebase
      AuthSessionManager.clearAuthenticatedSession();
      await FirebaseAuth.instance.signOut();

      // Navigate back to auth page
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } catch (e) {
      debugPrint('Error signing out: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error signing out'),
          backgroundColor: Colors.red,
        ),
      );
      // Reclaim focus after SnackBar
      _reclaimFocus();
    }
  }

  void _showShutdownConfirmation() async {
    // Show confirmation dialog
    final bool? shouldShutdown = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.power_settings_new, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Shut Down App'),
            ],
          ),
          content: const Text(
            'Are you sure you want to shut down the application?\n\n'
            'This will completely close the app and you will need to restart it manually.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Shut Down',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    // If user confirmed, shut down the app
    if (shouldShutdown == true) {
      _shutdownApp();
    }

    // Reclaim focus after dialog
    _reclaimFocus();
  }

  void _shutdownApp() async {
    debugPrint('App shutdown requested by user - closing application');

    try {
      // Stop any ongoing audio or TTS
      await flutterTts.stop();

      // Clean up any timers or background processes
      scanningTimer?.cancel();

      // Show brief shutdown message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shutting down application...'),
            backgroundColor: Colors.red,
            duration: Duration(milliseconds: 1500),
          ),
        );

        // Small delay to show the message
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      // Close the application
      if (Platform.isAndroid) {
        // For Android, use SystemNavigator to pop to system
        SystemNavigator.pop();
      } else if (Platform.isIOS) {
        // For iOS, exit is not allowed by App Store guidelines
        // Instead, just show a message that the user should manually close
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('App Minimized'),
              content: const Text(
                'iOS apps cannot be closed programmatically. Please use the home button or app switcher to close the app manually.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        // For other platforms, try to exit
        exit(0);
      }
    } catch (e) {
      debugPrint('Error during app shutdown: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during shutdown: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Update PIN from settings automatically
    final settingsProvider = Provider.of<UserSettingsProvider>(
      context,
      listen: true,
    );
    _updatePINFromSettings(settingsProvider);

    // Get user-selected colors, fall back to defaults
    final userSettings = settingsProvider.settings;
    final Color headerTextColor = userSettings != null
        ? Color(userSettings.lightColorValue)
        : kDefaultLightColor; // Color1 for text
    final Color headerBackgroundColor = userSettings != null
        ? Color(userSettings.darkColorValue)
        : kDefaultDarkColor; // Color2 for background

    return RawKeyboardListener(
      focusNode: gridFocusNode!,
      autofocus: true,
      onKey: (event) {
        if (ModalRoute.of(context)?.isCurrent == false) {
          return;
        }

        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          _handleStepModeTabAdvance();
          return;
        }

        // Handle Spacebar Key Events
        if (event.logicalKey.keyLabel == ' ') {
          if (event is RawKeyDownEvent) {
            // First check: Long press disable (always honored)
            if (_isSpacebarDisabled) {
              debugPrint(
                'Spacebar ignored: Switch is disabled due to long press.',
              );
              return;
            }

            // DEFENSIVE DESIGN: Switch is ONLY enabled during scanning or initial press
            // All other times (announcements, processing, LLM, navigation) → automatically blocked
            if (!isScanning && !_waitingForInitialSwitch) {
              debugPrint(
                '🚫 SWITCH BLOCKED: Not scanning (processing/announcements/navigation in progress)',
              );
              return;
            }

            if (_isHandlingSwitchSelection) {
              debugPrint(
                '🚫 SWITCH BLOCKED: Selection already in progress',
              );
              return;
            }

            // Handle initial switch press to start scanning
            if (_waitingForInitialSwitch) {
              debugPrint(
                'Initial switch detected (spacebar) - starting scanning on gridpage',
              );
              setState(() {
                _waitingForInitialSwitch = false;
                _switchStartRequested = true;
              });
              _startAuditoryScanning();
              return;
            }

            // If already down (repeat), ignore to prevent rapid fire
            if (_isSpacebarDown) {
              debugPrint('Spacebar ignored: Repeat event.');
              return;
            }

            // First press
            _isSpacebarDown = true;

            // Start Hold Timer
            _spacebarHoldTimer?.cancel();
            _spacebarHoldTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted) {
                setState(() {
                  _isSpacebarDisabled = true;
                  debugPrint('Spacebar disabled: Held too long.');
                  // Optional: Show feedback
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Switch disabled. Release to reset.'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                });
              }
            });

            // Execute Action
            debugPrint(
              'Spacebar pressed: _waitingForUserInput=$_waitingForUserInput, _isScanningPaused=$_isScanningPaused, isScanning=$isScanning, scanningIndex=$scanningIndex',
            );
            if (_waitingForUserInput) {
              debugPrint('Spacebar: Resuming scanning from paused state');
              _resumeScanning();
            } else if (isScanning &&
                scanningIndex != null &&
                scanningIndex! >= 0) {
              debugPrint('Spacebar: Selecting button at index $scanningIndex');
              _onButtonSelected(scanningIndex!);
            }
          } else if (event is RawKeyUpEvent) {
            // Key Released
            _isSpacebarDown = false;
            _spacebarHoldTimer?.cancel();

            if (_isSpacebarDisabled) {
              // Re-enable
              if (mounted) {
                setState(() {
                  _isSpacebarDisabled = false;
                  debugPrint('Spacebar re-enabled: Switch released.');
                });
              }
            }
          }
        }
      },
      child: Scaffold(
        body: GestureDetector(
          onDoubleTap: () {
            // Double-tap to refresh the app
            _performAppRefresh();
          },
          child: Stack(
            children: [
              // Main content
              Column(
                children: [
                  // Custom Header/Title Bar with user colors
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: headerBackgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            // Page Title with Version
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentPageDisplayName,
                                    style: TextStyle(
                                      color: headerTextColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'v1.0.2+18',
                                    style: TextStyle(
                                      color: headerTextColor.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Admin Toolbar - moved to floating position to avoid washout
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    offset: Offset(0, 2),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  iconTheme: const IconThemeData(size: 20),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Lock/Unlock Icon - Always visible
                                    IconButton(
                                      icon: Icon(
                                        _isAdminToolbarLocked
                                            ? Icons.lock
                                            : Icons.lock_open,
                                        color: Colors.black87,
                                      ),
                                      tooltip: _isAdminToolbarLocked
                                          ? 'Unlock Admin Toolbar'
                                          : 'Lock Admin Toolbar',
                                      onPressed: _toggleAdminToolbarLock,
                                    ),
                                    // Admin buttons - Only show when unlocked
                                    if (!_isAdminToolbarLocked) ...[
                                      IconButton(
                                        icon: const Icon(
                                          Icons.settings,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'Admin Settings',
                                        onPressed: () {
                                          _onAdminButtonPressed(
                                            '/admin-settings',
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.grid_on,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'Admin Pages & Buttons',
                                        onPressed: () {
                                          _onAdminButtonPressed('/admin-pages');
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.location_on,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'User Current Location',
                                        onPressed: () {
                                          _onAdminButtonPressed(
                                            '/admin-user-current',
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.info_outline,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'User Info & Birthdays',
                                        onPressed: () {
                                          _onAdminButtonPressed(
                                            '/admin-user-info',
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.book,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'User Diary',
                                        onPressed: () {
                                          _onAdminButtonPressed(
                                            '/admin-user-diary',
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.volume_up,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'Audio Device Admin',
                                        onPressed: () {
                                          _onAdminButtonPressed(
                                            '/admin-audio-devices',
                                          );
                                        },
                                      ),
                                      // Separator
                                      Container(
                                        height: 30,
                                        width: 1,
                                        color: Colors.grey[400],
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                      ),
                                      // Tap Interface Toggle button
                                      IconButton(
                                        icon: Icon(
                                          _settingsProvider
                                                      ?.settings
                                                      ?.useTapInterface ==
                                                  true
                                              ? Icons.touch_app
                                              : Icons.grid_view,
                                          color:
                                              _settingsProvider
                                                      ?.settings
                                                      ?.useTapInterface ==
                                                  true
                                              ? Colors.blue
                                              : Colors.black87,
                                        ),
                                        tooltip:
                                            _settingsProvider
                                                    ?.settings
                                                    ?.useTapInterface ==
                                                true
                                            ? 'Switch to Grid Interface'
                                            : 'Switch to Tap Interface',
                                        onPressed: _toggleTapInterface,
                                      ),
                                      // Switch User Account button
                                      IconButton(
                                        icon: const Icon(
                                          Icons.account_circle,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'Switch User Account',
                                        onPressed: _switchUserAccount,
                                      ),
                                      // Sign Out button
                                      IconButton(
                                        icon: const Icon(
                                          Icons.logout,
                                          color: Colors.black87,
                                        ),
                                        tooltip: 'Sign Out',
                                        onPressed: _signOut,
                                      ),
                                      // App Shutdown button
                                      IconButton(
                                        icon: const Icon(
                                          Icons.power_settings_new,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Shut Down App',
                                        onPressed: _showShutdownConfirmation,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Speech History
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (context) {
                            final composeActive = _composeSession.active;
                            return Row(
                              children: [
                                Text(
                                  'Speech History:',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () async {
                                    if (composeActive) {
                                      setState(() {
                                        _composeSession = _composeSession
                                            .copyWith(text: '');
                                      });
                                      await _persistComposeSession();
                                    } else {
                                      setState(() {
                                        speechHistory = '';
                                      });
                                    }
                                  },
                                  child: const Text('Clear'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.red.shade700,
                                    elevation: 2,
                                    shadowColor: Colors.red.withOpacity(0.3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        color: Colors.red.shade100,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isSpeechHistoryMaximized =
                                          !_isSpeechHistoryMaximized;
                                    });
                                  },
                                  child: Text(
                                    _isSpeechHistoryMaximized
                                        ? 'Minimize'
                                        : 'Maximize',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.blue.shade700,
                                    elevation: 2,
                                    shadowColor: Colors.blue.withOpacity(0.3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        color: Colors.blue.shade100,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: _isSpeechHistoryMaximized ? 160 : 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: TextEditingController(
                              text: _composeSession.active
                                  ? _composeSession.text
                                  : speechHistory,
                            ),
                            readOnly: true,
                            maxLines: null,
                            style: TextStyle(
                              fontSize: _isSpeechHistoryMaximized ? 40 : 20,
                              height: 1.5,
                            ),
                            focusNode: FocusNode(
                              canRequestFocus: false,
                            ), // Prevent focus!
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Grid of Buttons
                  Flexible(
                    fit: FlexFit.loose,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: gridButtons.isEmpty
                          ? const Center(
                              child: Text('No grid buttons available.'),
                            )
                          : _buildDynamicUserGrid(),
                    ),
                  ),
                  // Status message at the bottom (fade in/out)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child:
                        (_showBottomStatusText &&
                            statusMessage != null &&
                            statusMessage!.isNotEmpty)
                        ? (statusMessage!.startsWith('❌')
                              ? Container(
                                  key: ValueKey('grid_error_${statusMessage!}'),
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12.0,
                                    horizontal: 16.0,
                                  ),
                                  decoration: BoxDecoration(color: Colors.red),
                                  child: Text(
                                    statusMessage!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : Padding(
                                  key: ValueKey(
                                    'grid_status_${statusMessage!}',
                                  ),
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        statusMessage!,
                                        style: const TextStyle(
                                          color: Colors.blueGrey,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                        : const SizedBox(key: ValueKey('grid_status_hidden')),
                  ),
                ],
              ),
              // Speech Bubble Overlay
              if (_showSpeechBubble)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(
                      0.3,
                    ), // Semi-transparent background
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(
                          60,
                        ), // Increased from 40 to 60 (50% larger)
                        padding: const EdgeInsets.all(
                          30,
                        ), // Increased from 20 to 30 (50% larger)
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            30,
                          ), // Increased from 20 to 30 (50% larger)
                          border: Border.all(
                            color: Colors.grey[400]!,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              offset: Offset(0, 4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Speech bubble icon
                            Image.asset(
                              'assets/whitespeechbubble.jpg',
                              width: 90, // Increased from 60 to 90 (50% larger)
                              height:
                                  90, // Increased from 60 to 90 (50% larger)
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width:
                                      90, // Increased from 60 to 90 (50% larger)
                                  height:
                                      90, // Increased from 60 to 90 (50% larger)
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(
                                      45,
                                    ), // Increased from 30 to 45 (50% larger)
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline,
                                    size:
                                        45, // Increased from 30 to 45 (50% larger)
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(
                              width: 30,
                            ), // Increased from 20 to 30 (50% larger)
                            // Speech bubble text
                            Flexible(
                              child: Text(
                                _speechBubbleText,
                                style: const TextStyle(
                                  fontSize:
                                      36, // Increased from 24 to 36 (50% larger)
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Refresh indicator overlay
              if (_isRefreshing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Refreshing App...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Double-tap anywhere to refresh',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicUserGrid() {
    // Responsive grid: fill screen, adjust button/font size
    return LayoutBuilder(
      builder: (context, constraints) {
        final settingsProvider = Provider.of<UserSettingsProvider>(
          context,
          listen: true,
        );
        final userSettings = settingsProvider.settings;
        // Use int gridColumns directly
        final int gridCols = userSettings?.gridColumns ?? 10;
        // Set button size based on columns (smaller buttons for more columns)
        double buttonSizePx;
        if (gridCols >= 16) {
          buttonSizePx = 50.0;
        } else if (gridCols >= 12) {
          buttonSizePx = 60.0;
        } else if (gridCols >= 9) {
          buttonSizePx = 80.0;
        } else if (gridCols >= 7) {
          buttonSizePx = 100.0;
        } else if (gridCols >= 5) {
          buttonSizePx = 130.0;
        } else {
          buttonSizePx = 160.0;
        }
        final int numButtons = gridButtons
            .where((btn) => (btn['text'] ?? '').toString().trim().isNotEmpty)
            .length;
        final int gridRows = (numButtons / gridCols).ceil();
        final Color darkColor = userSettings?.darkColor ?? kDefaultDarkColor;
        final Color lightColor = userSettings?.lightColor ?? kDefaultLightColor;
        final double gridPadding = 12;
        final double spacing = 10;
        final double availableWidth =
            constraints.maxWidth - gridPadding * 2 - spacing * (gridCols - 1);
        // final double availableHeight = constraints.maxHeight - gridPadding * 2 - spacing * (gridRows - 1);
        // Use fixed button size per label, but clamp to available width if needed
        double effectiveButtonSize = buttonSizePx;
        if (availableWidth / gridCols < buttonSizePx) {
          effectiveButtonSize = (availableWidth / gridCols).clamp(
            40.0,
            buttonSizePx,
          );
        }
        // Increased font size multiplier and max clamp for better readability
        final double fontSize = ((effectiveButtonSize / 10) * 1.5).clamp(
          14.0,
          28.0,
        );
        debugPrint(
          '[DEBUG] _buildDynamicUserGrid: availableWidth=$availableWidth, gridCols=$gridCols, buttonSize=$effectiveButtonSize, fontSize=$fontSize',
        );

        final definedButtons = _effectiveGridButtons();
        final List<Map<String, dynamic>> visibleButtons =
            List<Map<String, dynamic>>.from(definedButtons);
        // No padding: only show defined buttons
        return Container(
          decoration: BoxDecoration(
            color: Colors.blueGrey[50], // Softer background
            image: DecorationImage(
              image: AssetImage(
                'assets/subtle_pattern.png',
              ), // Optional: if you have a pattern
              fit: BoxFit.cover,
              opacity: 0.05,
              onError: (exception, stackTrace) {}, // Ignore if asset missing
            ),
          ),
          padding: EdgeInsets.all(gridPadding),
          child: Scrollbar(
            thumbVisibility: true,
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCols,
                childAspectRatio: 1.33,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: visibleButtons.length,
              itemBuilder: (context, index) {
                final btn = visibleButtons[index];
                final isActive = (btn['text'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: SizedBox(
                    width: effectiveButtonSize,
                    height: effectiveButtonSize,
                    child: SpeechBubbleButton(
                      label: isActive ? (btn['text'] ?? '') : '',
                      onPressed: isActive
                          ? () async {
                              if (_isScanningPaused && _waitingForUserInput) {
                                // If scanning is paused, ONLY resume it - do NOT perform button action
                                await _resumeScanning();
                              } else {
                                // Normal button action when scanning is active
                                handleButtonAction(btn);
                              }
                            }
                          : null,
                      isActive: isActive,
                      isHighlighted:
                          scanningIndex == index &&
                          (isScanning || _isScanningPaused),
                      darkColor: darkColor,
                      lightColor: lightColor,
                      fontSize: fontSize,
                      enablePictograms: userSettings?.enablePictograms ?? false,
                      buttonData:
                          btn, // Pass button data for manual pictogram support
                      sightWordGradeLevel: userSettings
                          ?.sightWordGradeLevel, // Pass sight word grade level
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// --- Custom SpeechBubbleButton Widget ---
class SpeechBubbleButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;
  final bool isHighlighted;
  final Color darkColor;
  final Color lightColor;
  final double fontSize;
  final bool enablePictograms;
  final Map<String, dynamic>?
  buttonData; // Button configuration data for manual pictograms
  final String? sightWordGradeLevel; // Grade level for sight word checking

  const SpeechBubbleButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.isActive,
    required this.isHighlighted,
    required this.darkColor,
    required this.lightColor,
    required this.fontSize,
    this.enablePictograms = false,
    this.buttonData,
    this.sightWordGradeLevel,
  });

  @override
  State<SpeechBubbleButton> createState() => _SpeechBubbleButtonState();
}

class _SpeechBubbleButtonState extends State<SpeechBubbleButton> {
  String? _pictogramUrl;
  bool _isLoading = false;
  bool _isSightWord = false; // Track if this button contains a sight word
  String? _lastLoadedKey; // Cache key to prevent redundant loads

  // Long press handling
  Timer? _longPressTimer;
  bool _isLongPressDisabled = false;

  @override
  void initState() {
    super.initState();
    _loadPictogram();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _startLongPressTimer() {
    _isLongPressDisabled = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isLongPressDisabled = true;
        });
      }
    });
  }

  void _handleRelease() {
    _longPressTimer?.cancel();
    if (_isLongPressDisabled) {
      // Delay re-enabling to ensure any pending tap is blocked
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _isLongPressDisabled = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(SpeechBubbleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload pictogram if meaningful properties changed
    final labelChanged = widget.label != oldWidget.label;
    final enabledChanged =
        widget.enablePictograms != oldWidget.enablePictograms;

    // Check if buttonData actually changed content (not just reference)
    final buttonDataChanged = _hasButtonDataChanged(
      oldWidget.buttonData,
      widget.buttonData,
    );

    if (labelChanged || buttonDataChanged || enabledChanged) {
      debugPrint(
        '🔄 SpeechBubbleButton: Reloading pictogram - label: $labelChanged, buttonData: $buttonDataChanged, enabled: $enabledChanged',
      );
      debugPrint(
        '🔄 SpeechBubbleButton: Label changed from "${oldWidget.label}" to "${widget.label}"',
      );
      _loadPictogram();
    }
  }

  /// Check if buttonData actually changed content, not just reference
  bool _hasButtonDataChanged(
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  ) {
    if (oldData == null && newData == null) return false;
    if (oldData == null || newData == null) return true;

    // Check specific fields that matter for pictograms
    final oldImageUrl = oldData['assigned_image_url'] as String?;
    final newImageUrl = newData['assigned_image_url'] as String?;

    return oldImageUrl != newImageUrl;
  }

  Future<void> _loadPictogram() async {
    if (!widget.enablePictograms || widget.label.trim().isEmpty) {
      return;
    }

    // Create cache key from label and manual image URL
    final manualImageUrl = widget.buttonData?['assigned_image_url'] as String?;
    final cacheKey = '${widget.label}|${manualImageUrl ?? ''}';

    // Skip if we already loaded this exact combination
    if (_lastLoadedKey == cacheKey && _pictogramUrl != null) {
      debugPrint(
        '🔄 SpeechBubbleButton: Skipping reload, cache key unchanged: $cacheKey',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isSightWord = false; // Reset sight word status at start of load
    });

    try {
      // Check for manually assigned pictogram first
      if (widget.buttonData != null) {
        final manualPictogramUrl =
            widget.buttonData!['assigned_image_url'] as String?;
        if (manualPictogramUrl != null && manualPictogramUrl.isNotEmpty) {
          if (mounted) {
            setState(() {
              _pictogramUrl = manualPictogramUrl;
              _isSightWord =
                  false; // Reset sight word status for manual pictograms
              _isLoading = false;
              _lastLoadedKey = cacheKey;
            });
          }
          return;
        }
      }

      // If no manual pictogram, use dynamic lookup
      final pictogramService = PictogramService();
      pictogramService.enablePictograms = widget.enablePictograms;

      // Convert string grade level to int
      int? gradeLevel;
      if (widget.sightWordGradeLevel != null) {
        gradeLevel = int.tryParse(widget.sightWordGradeLevel!);
      }

      final result = await pictogramService.getPictogramResult(
        widget.label,
        sightWordGradeLevel: gradeLevel,
        shouldLogMissing:
            false, // Don't log missing images for UI elements in speech bubbles
      );

      if (mounted) {
        setState(() {
          _pictogramUrl = result?.imageUrl;
          _isSightWord = result?.isSightWord ?? false;
          _isLoading = false;
          _lastLoadedKey = cacheKey;
        });
      }
    } catch (e) {
      debugPrint('Error loading pictogram for "${widget.label}": $e');
      if (mounted) {
        setState(() {
          _isSightWord = false; // Reset sight word status on error
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if button should look disabled due to long press
    final bool isTemporarilyDisabled = _isLongPressDisabled;

    return Listener(
      onPointerDown: widget.isActive ? (_) => _startLongPressTimer() : null,
      onPointerUp: widget.isActive ? (_) => _handleRelease() : null,
      onPointerCancel: widget.isActive ? (_) => _handleRelease() : null,
      child: GestureDetector(
        onTap: widget.isActive
            ? () {
                if (_isLongPressDisabled) return;
                widget.onPressed?.call();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 1.0],
              colors: isTemporarilyDisabled
                  ? [
                      Colors.grey.shade300,
                      Colors.grey.shade400,
                    ] // Disabled look
                  : (widget.isHighlighted
                        ? [Colors.white, widget.lightColor.withOpacity(0.5)]
                        : [Colors.white, Colors.white]),
            ),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: isTemporarilyDisabled
                  ? Colors.grey.shade500
                  : (widget.isHighlighted
                        ? widget.lightColor
                        : Colors.grey.shade300),
              width: widget.isHighlighted ? 3.0 : 1.0,
            ),
            boxShadow: isTemporarilyDisabled
                ? [] // No shadow when disabled
                : (widget.isHighlighted
                      ? [
                          BoxShadow(
                            color: widget.lightColor.withOpacity(0.6),
                            blurRadius: 12.0,
                            spreadRadius: 1.0,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 6.0,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 2.0,
                            offset: const Offset(0, 1),
                          ),
                        ]),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.0),
            child: Opacity(
              opacity: isTemporarilyDisabled
                  ? 0.5
                  : 1.0, // Fade content when disabled
              child: widget.enablePictograms && widget.label.isNotEmpty
                  ? _buildPictogramContent()
                  : _buildTextOnlyContent(widget.label, widget.fontSize),
            ),
          ),
        ),
      ),
    );
  } // Build text-only content with auto-sizing to prevent word splitting

  Widget _buildTextOnlyContent(String label, double fontSize) {
    // Apply special formatting for sight words
    final bool isSpecialSightWord = _isSightWord;
    final double baseFontSize = isSpecialSightWord
        ? fontSize * 1.3
        : fontSize; // 30% larger for sight words
    final FontWeight fontWeight = isSpecialSightWord
        ? FontWeight.w700
        : FontWeight.w300; // Bold for sight words
    final Color textColor = isSpecialSightWord
        ? const Color(0xFF0066CC)
        : Colors.black; // Blue for sight words

    return Container(
      decoration: isSpecialSightWord
          ? BoxDecoration(
              // Subtle background highlight for sight words
              color: const Color(0xFFF0F8FF), // Very light blue background
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF0066CC).withOpacity(0.3),
                width: 1,
              ),
            )
          : null,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: _buildAutoSizingText(
            label,
            baseFontSize,
            textColor,
            fontWeight,
            isSpecialSightWord,
          ),
        ),
      ),
    );
  }

  // Build auto-sizing text that prevents word splitting
  Widget _buildAutoSizingText(
    String label,
    double baseFontSize,
    Color textColor,
    FontWeight fontWeight,
    bool isSpecialSightWord,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate optimal font size to prevent word splitting
        double optimalFontSize = _calculateOptimalFontSize(
          label,
          baseFontSize,
          constraints.maxWidth,
          fontWeight,
        );

        return Text(
          label,
          textAlign: TextAlign.center,
          textScaleFactor:
              1.0, // Prevent system font scaling from breaking layout
          softWrap: true,
          style: TextStyle(
            color: textColor,
            fontWeight: fontWeight,
            fontSize: optimalFontSize,
            fontFamily: _safeRobotoCondensed(),
            // Add subtle shadow for sight words
            shadows: isSpecialSightWord
                ? [
                    const Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Color(0x30000000),
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }

  // Calculate optimal font size to prevent word splitting
  double _calculateOptimalFontSize(
    String text,
    double baseFontSize,
    double maxWidth,
    FontWeight fontWeight,
  ) {
    if (text.trim().isEmpty) return baseFontSize;

    // Words in the text
    final words = text.trim().split(RegExp(r'\s+'));

    // Helper to check if text fits at a given size without splitting words
    bool fitsWithoutSplitting(double fontSize) {
      // Use a larger safety margin (80%) to aggressively prevent word splitting
      final double safeMaxWidth = maxWidth * 0.80;

      // First check if any single word is wider than maxWidth
      for (final word in words) {
        final wordPainter = TextPainter(
          textDirection: TextDirection.ltr,
          textScaleFactor: 1.0, // Explicitly match Text widget scaling
          text: TextSpan(
            text: word,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              fontFamily: _safeRobotoCondensed(),
            ),
          ),
        );
        wordPainter.layout();
        if (wordPainter.width > safeMaxWidth) return false;
      }

      return true;
    }

    // Binary search for the largest font size that fits without splitting words
    double low = baseFontSize * 0.4;
    double high = baseFontSize * 1.5; // Allow it to go larger if it fits
    double bestSize = low;

    // Perform more iterations for better precision
    for (int i = 0; i < 8; i++) {
      double mid = (low + high) / 2;
      if (fitsWithoutSplitting(mid)) {
        bestSize = mid;
        low = mid;
      } else {
        high = mid;
      }
    }

    return bestSize.clamp(baseFontSize * 0.5, baseFontSize * 1.3);
  }

  // Build pictogram content (large image with footer text)
  Widget _buildPictogramContent() {
    // Show loading state while pictogram is being fetched
    if (_isLoading) {
      return _buildTextOnlyContent(widget.label, widget.fontSize);
    }

    // If we have a pictogram URL (manual or dynamic), display it
    if (_pictogramUrl != null && _pictogramUrl!.isNotEmpty) {
      return _buildPictogramLayout(
        _pictogramUrl!,
        widget.label,
        widget.fontSize,
      );
    }

    // No pictogram found - show text only
    return _buildTextOnlyContent(widget.label, widget.fontSize);
  }

  // Build the pictogram layout (extracted to reuse for manual and dynamic pictograms)
  Widget _buildPictogramLayout(
    String pictogramUrl,
    String label,
    double fontSize,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Maximum size image container - dominates the button
        Expanded(
          flex: 9, // Maximum flex for largest possible images
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              1.0,
            ), // Minimal padding for maximum image space
            child: _buildSpeechBubblePictogramImage(pictogramUrl, label),
          ),
        ),
        // Minimal text footer at bottom
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 4.0,
            vertical: 1.0,
          ), // Minimal padding
          decoration: BoxDecoration(
            color: Colors.grey.shade100, // Subtle footer background
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(10.0),
              bottomRight: Radius.circular(10.0),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w500,
              fontSize: (fontSize * 0.6).clamp(
                8.0,
                12.0,
              ), // Smaller footer text
              fontFamily: _safeRobotoCondensed(),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Build the pictogram image for speech bubble
  Widget _buildSpeechBubblePictogramImage(String pictogramUrl, String label) {
    debugPrint(
      '_buildSpeechBubblePictogramImage: Loading image for "$label" from URL: $pictogramUrl',
    );

    // Check if it's an emoji (fallback pictogram) or a URL
    if (!pictogramUrl.startsWith('http')) {
      debugPrint(
        '_buildSpeechBubblePictogramImage: Treating as emoji: $pictogramUrl',
      );
      // It's an emoji - display as much larger text
      return Center(
        child: Text(
          pictogramUrl,
          style: const TextStyle(
            fontSize: 40,
          ), // Much larger emoji for speech bubbles
          textAlign: TextAlign.center,
        ),
      );
    }

    debugPrint(
      '_buildSpeechBubblePictogramImage: Loading network image from: $pictogramUrl',
    );
    // It's a URL - display as network image
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        pictogramUrl,
        fit: BoxFit.cover, // Changed from contain to cover for maximum size
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            debugPrint(
              '_buildSpeechBubblePictogramImage: Image loaded successfully for "$label"',
            );
            return child;
          }
          debugPrint(
            '_buildSpeechBubblePictogramImage: Loading image for "$label" - ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes} bytes',
          );
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // Image failed to load - show text only
          debugPrint(
            '❌ FAILED to load speech bubble image for "$label" from URL: $pictogramUrl',
          );
          debugPrint('❌ Error: $error');
          debugPrint('❌ Stack trace: $stackTrace');
          return Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.w300,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}
