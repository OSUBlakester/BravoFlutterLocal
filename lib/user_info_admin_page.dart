import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/user_settings_provider.dart';
import 'constants/mood_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'config/environment_config.dart';
import 'pages/audio_interview_page.dart';
import 'pages/family_friends_interview_page.dart';
import 'services/family_friends_interview_service.dart';
import 'services/custom_image_service.dart';
import 'services/pictogram_service.dart';
import 'services/storage_image_url_service.dart';
import 'widgets/custom_images_widget.dart';
import 'services/authenticated_http_client.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserInfoAdminPage extends StatefulWidget {
  final String idToken;
  final String aacUserId;
  const UserInfoAdminPage({Key? key, required this.idToken, required this.aacUserId}) : super(key: key);

  @override
  State<UserInfoAdminPage> createState() => _UserInfoAdminPageState();
}

class FriendFamily {
  String name;
  String relationship;
  String about;
  String birthday;

  FriendFamily({
    this.name = '',
    this.relationship = '',
    this.about = '',
    this.birthday = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'relationship': relationship,
    'about': about,
    'birthday': birthday,
  };

  factory FriendFamily.fromJson(Map<String, dynamic> json) => FriendFamily(
    name: json['name'] ?? '',
    relationship: json['relationship'] ?? '',
    about: json['about'] ?? '',
    birthday: json['birthday'] ?? '',
  );
}

class _UserInfoAdminPageState extends State<UserInfoAdminPage> {
  static const String _localProfileImagePathPrefix = 'local_profile_image_path_';

  // User Info Section
  final TextEditingController userInfoController = TextEditingController();
  final TextEditingController userBirthdateController = TextEditingController();
  final TextEditingController userNameController = TextEditingController();
  String userInfoStatus = '';
  bool isUserInfoLoading = false;
  String profileImageStatus = '';
  String? profileImageUrl;
  bool isProfileImageLoading = false;

  // Friends & Family Section
  List<FriendFamily> friendsFamily = [];
  List<String> availableRelationships = [];
  String friendsFamilyStatus = '';
  bool isFriendsFamilyLoading = false;

  // Relationship Management
  final TextEditingController newRelationshipController = TextEditingController();
  bool showRelationshipModal = false;
  
  // Prevent duplicate save operations
  bool _isCurrentlySaving = false;

  @override
  void initState() {
    super.initState();
    
    // Configure soft input mode for admin page (but don't show keyboard yet)
    _configureSoftInputMode();
    
    // Configure text field focus after the page is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _configureTextFieldFocus();
    });
    
    // Stop wake word listening when this page is shown
    final dynamic gridState = context.findAncestorStateOfType<State<StatefulWidget>>();
    if (gridState != null && gridState.runtimeType.toString() == '_GridPageState') {
      try {
        gridState._wakeWordService?.stopWakeWordListening();
      } catch (_) {}
    }
    
    // Refresh settings first, then load user info to ensure mood sync takes precedence
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Provider.of<UserSettingsProvider>(context, listen: false).fetchSettings();
      if (mounted) {
        debugPrint('UserInfoAdminPage: Settings fetched, now loading user info');
        loadUserInfo();
        loadFriendsFamily();
      }
    });
    
    debugPrint('UserInfoAdminPage: initState - scheduled data loading');
  }

  // Configure text fields to be properly focusable for keyboard input
  void _configureTextFieldFocus() {
    try {
      // Request focus for the first text field to ensure keyboard can appear
      if (mounted) {
        userInfoController.addListener(() {
          // This ensures the text field stays focusable
        });
        debugPrint('✅ Text field focus configured for admin page');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to configure text field focus: $e');
    }
  }

  // User Info Methods
  String _localProfileImageStorageKey() {
    return '$_localProfileImagePathPrefix${widget.aacUserId}';
  }

  bool _isLocalFileUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('file://') || url.startsWith('/');
  }

  String _toLocalFilePath(String url) {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    return url;
  }

  Future<String?> _loadLocalProfileImageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPath = prefs.getString(_localProfileImageStorageKey());
    if (storedPath == null || storedPath.isEmpty) return null;

    final file = File(storedPath);
    if (await file.exists()) {
      return 'file://$storedPath';
    }

    await prefs.remove(_localProfileImageStorageKey());
    return null;
  }

  Future<String?> _saveLocalProfileImage(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/profile_image_${widget.aacUserId}.jpg';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localProfileImageStorageKey(), path);
    return 'file://$path';
  }

  Future<void> _clearLocalProfileImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedPath = prefs.getString(_localProfileImageStorageKey());
      if (storedPath != null && storedPath.isNotEmpty) {
        final file = File(storedPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await prefs.remove(_localProfileImageStorageKey());
      // Also clear the PictogramService in-memory profile image cache so that
      // pronoun buttons (I/me/my) immediately re-fetch the canonical URL from
      // the server instead of serving the now-deleted file:// path.
      PictogramService().clearProfileImageCache();
    } catch (e) {
      debugPrint('⚠️ Failed to clear local profile image: $e');
    }
  }

  Future<void> _loadProfileImageFromProfileEndpoint({
    bool updateStatusOnError = false,
  }) async {
    try {
      // Use any cached local file only as a temporary preview while loading
      // canonical server metadata from /api/get_profile_image.
      final localProfileImageUrl = await _loadLocalProfileImageUrl();
      if (localProfileImageUrl != null && localProfileImageUrl.isNotEmpty) {
        if (mounted) {
          setState(() {
            profileImageUrl = localProfileImageUrl;
          });
        }
      }

      final idToken = await AuthenticatedHttpClient.getRefreshedIdToken();
      if (idToken == null || idToken.isEmpty) {
        if (updateStatusOnError) {
          setState(() {
            profileImageStatus =
                'Could not load profile image preview (no auth token).';
          });
        }
        return;
      }

      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/get_profile_image'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final profileImage = data['profile_image'];
        if (profileImage is Map<String, dynamic>) {
          final resolved = _normalizeProfileImageUrl(
            profileImage['signed_image_url'] ??
                data['profileImageSignedUrl'] ??
                profileImage['signed_url'] ??
                profileImage['image_url'],
          );
          final resolvedFromStoragePath = await StorageImageUrlService.resolveImageUrl(
            storagePath: profileImage['storage_path']?.toString(),
            fallbackUrl: resolved,
            bucketName: '${EnvironmentConfig.projectId}-aac-images',
          );
          final canonicalUrl = resolvedFromStoragePath ?? resolved;

          // Canonical server URL is authoritative; clear stale local cache.
          if (canonicalUrl != null && canonicalUrl.isNotEmpty) {
            await _clearLocalProfileImage();
          }

          setState(() {
            profileImageUrl = canonicalUrl;
          });
        } else {
          setState(() {
            profileImageUrl = null;
          });
        }
      } else if (response.statusCode == 404) {
        // No profile image set yet.
        await _clearLocalProfileImage();
        setState(() {
          profileImageUrl = null;
        });
      } else if (response.statusCode == 403) {
        // Non-fatal: keep any known URL and avoid showing a hard error.
        if (updateStatusOnError) {
          setState(() {
            profileImageStatus =
                'Profile image is saved, but preview metadata is currently restricted (403).';
          });
        }
      } else if (updateStatusOnError) {
        setState(() {
          profileImageStatus =
              'Could not load profile image preview (status ${response.statusCode}).';
        });
      }
    } catch (e) {
      if (updateStatusOnError) {
        setState(() {
          profileImageStatus = 'Could not load profile image preview: $e';
        });
      }
    }
  }

  String? _normalizeProfileImageUrl(dynamic rawUrl) {
    if (rawUrl == null) return null;

    var url = rawUrl.toString().trim();
    if (url.isEmpty || url.toLowerCase() == 'null') return null;

    if (_isLocalFileUrl(url)) {
      return url;
    }

    // Convert gs://bucket/path to a public HTTPS URL.
    if (url.startsWith('gs://')) {
      final storagePath = url.substring(5);
      final slashIndex = storagePath.indexOf('/');
      if (slashIndex > 0) {
        final bucket = storagePath.substring(0, slashIndex);
        final objectPath = storagePath.substring(slashIndex + 1);
        url = 'https://storage.googleapis.com/$bucket/$objectPath';
      }
    }

    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (url.startsWith('/')) {
      url = '${EnvironmentConfig.apiBaseUrl}$url';
    } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final looksLikeStorageHost =
          url.contains('storage.googleapis.com/') ||
          url.contains('.googleapis.com/');
      url = looksLikeStorageHost
          ? 'https://$url'
          : '${EnvironmentConfig.apiBaseUrl}/$url';
    }

    if (url.contains(' ')) {
      url = Uri.encodeFull(url);
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) return null;
    return parsed.toString();
  }

  Future<void> loadUserInfo() async {
    setState(() { 
      isUserInfoLoading = true; 
      userInfoStatus = 'Loading...'; 
    });
    
    try {
      // Load user info
      final userInfoResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/user-info',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
      );
      
      if (userInfoResponse.statusCode == 200) {
        final userInfoData = json.decode(userInfoResponse.body);
        final localProfileImageUrl = await _loadLocalProfileImageUrl();
        setState(() {
          userInfoController.text = userInfoData['userInfo'] ?? '';
          userNameController.text = userInfoData['name'] ?? '';
          profileImageUrl = localProfileImageUrl ??
              _normalizeProfileImageUrl(
                userInfoData['profileImageUrl'],
              );
          print("🔍 LOAD DEBUG - Loaded name: " + (userInfoData["name"] ?? ""));
        });

        // Mirror web app behavior: load profile image via dedicated endpoint.
        await _loadProfileImageFromProfileEndpoint();
        
        // Sync mood from user info if available
        if (userInfoData['currentMood'] != null) {
          final mood = userInfoData['currentMood'];
          debugPrint('UserInfoAdminPage: Syncing mood from user info API: $mood');
          // Update provider without triggering a save, just update local state
          Provider.of<UserSettingsProvider>(context, listen: false)
              .updateSettings((s) => s.currentMood = mood, save: false);
        }
      } else {
        throw Exception('User info fetch failed: ${userInfoResponse.statusCode}');
      }

      // Load birthdate
      final birthdayResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/birthdays',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
      );
      
      if (birthdayResponse.statusCode == 200) {
        final birthdayData = json.decode(birthdayResponse.body);
        userBirthdateController.text = birthdayData['userBirthdate'] ?? '';
      } else {
        throw Exception('Birthday fetch failed: ${birthdayResponse.statusCode}');
      }

      setState(() { userInfoStatus = 'Loaded.'; });
      
    } catch (e) {
      setState(() { userInfoStatus = 'Error loading: $e'; });
    } finally {
      setState(() { isUserInfoLoading = false; });
    }
  }

  Future<void> saveUserInfoAndBirthday() async {
    setState(() { 
      isUserInfoLoading = true; 
      userInfoStatus = 'Saving...'; 
    });

    // Validate birthday format
    final userBday = userBirthdateController.text.trim();
    if (userBday.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(userBday)) {
      setState(() { 
        userInfoStatus = 'User Birthdate must be in YYYY-MM-DD format or empty.'; 
        isUserInfoLoading = false;
      });
      return;
    }

    try {
      // Save user info
      print("�� SAVE DEBUG - Name field value: " + userNameController.text.trim());
      print("🔍 SAVE DEBUG - Request URL: ${EnvironmentConfig.apiBaseUrl}/api/user-info");
      
      final requestBody = {
        'userInfo': userInfoController.text,
        'name': userNameController.text.trim(),
      };
      print("🔍 SAVE DEBUG - Request body: ${json.encode(requestBody)}");
      
      final userInfoResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/user-info',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      print("🔍 SAVE DEBUG - Response status: ${userInfoResponse.statusCode}");
      print("🔍 SAVE DEBUG - Response body: ${userInfoResponse.body}");
      
      if (userInfoResponse.statusCode != 200) {
        throw Exception('User info save failed: ${userInfoResponse.statusCode} - ${userInfoResponse.body}');
      }
      
      // WORKAROUND: Since GCP server doesn't return name field yet, 
      // but we got 200 response (save successful), keep the name field populated
      final responseData = json.decode(userInfoResponse.body);
      if (!responseData.containsKey('name') && userNameController.text.trim().isNotEmpty) {
        print("🔧 WORKAROUND: Server didn't return name field, preserving local value: ${userNameController.text.trim()}");
        // Don't clear the name field since server saved it successfully but didn't return it
      }

      // Save birthday
      final birthdayResponse = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/birthdays',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({ 
          'userBirthdate': userBday.isEmpty ? null : userBday,
          'friendsFamily': [],
        }),
      );
      
      if (birthdayResponse.statusCode != 200) {
        throw Exception('Birthday save failed: ${birthdayResponse.statusCode}');
      }

      setState(() { userInfoStatus = 'Saved successfully!'; });
      
    } catch (e) {
      print('🚨 SAVE ERROR DEBUG - Full error: $e');
      setState(() { userInfoStatus = 'Error saving: $e'; });
    } finally {
      setState(() { isUserInfoLoading = false; });
    }
  }

  Future<void> uploadProfileImage() async {
    // Check if user has set their name first
    if (userNameController.text.trim().isEmpty) {
      setState(() {
        profileImageStatus = 'Please enter and save your name first before uploading a profile picture.';
      });
      return;
    }

    setState(() {
      isProfileImageLoading = true;
      profileImageStatus = 'Selecting image...';
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) {
        setState(() {
          profileImageStatus = 'No image selected.';
          isProfileImageLoading = false;
        });
        return;
      }

      setState(() {
        profileImageStatus = 'Processing and compressing image...';
      });

      final File imageFile = File(image.path);
      
      // Convert to JPEG for broad iPad/Safari/WebKit compatibility.
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        imageFile.absolute.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 85,
        format: CompressFormat.jpeg,
      );

      if (compressedBytes == null) {
        throw Exception('Failed to process and convert profile image.');
      }

      print('📸 UserInfoAdminPage: Image compressed successfully. Original size: ${await imageFile.length()} bytes, compressed size: ${compressedBytes.length} bytes');

      // Generate filename with jpg extension to match converted image format.
      String baseName = 'profile_picture';
      if (image.name.contains('.')) {
        baseName = image.name.substring(0, image.name.lastIndexOf('.'));
      }
      final compressedFilename = '$baseName.jpg';

      setState(() {
        profileImageStatus = 'Uploading profile image...';
      });

      // Prepare multipart request with automatic token refresh
      final idToken = await AuthenticatedHttpClient.getRefreshedIdToken();
      if (idToken == null) {
        throw Exception('No Firebase ID token available');
      }
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/upload_user_profile_image'),
      );

      // Add headers
      request.headers.addAll({
        'Authorization': 'Bearer $idToken',
        'X-User-ID': widget.aacUserId,
      });

      // Add image file as bytes
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        compressedBytes,
        filename: compressedFilename,
        contentType: MediaType('image', 'jpeg'),
      ));

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final localProfileImageUrl = await _saveLocalProfileImage(compressedBytes);
        setState(() {
          profileImageStatus = responseData['message'] ?? 'Profile image uploaded successfully!';
          profileImageUrl = localProfileImageUrl ??
              _normalizeProfileImageUrl(
            responseData['profileImageSignedUrl'] ??
                responseData['profileImageUrl'],
          );
          isProfileImageLoading = false;
        });

        final uploadedImageData = responseData['image_data'];
        final resolvedUploadedUrl = await StorageImageUrlService.resolveImageUrl(
          storagePath: uploadedImageData is Map<String, dynamic>
              ? uploadedImageData['storage_path']?.toString()
              : null,
          fallbackUrl: _normalizeProfileImageUrl(
            responseData['profileImageSignedUrl'] ?? responseData['profileImageUrl'],
          ),
          bucketName: '${EnvironmentConfig.projectId}-aac-images',
        );

        if (mounted && resolvedUploadedUrl != null && resolvedUploadedUrl.isNotEmpty) {
          setState(() {
            profileImageUrl = localProfileImageUrl ?? resolvedUploadedUrl;
          });
        }

        // Re-fetch profile image metadata from the canonical endpoint used by web app.
        await _loadProfileImageFromProfileEndpoint(updateStatusOnError: true);
        
        // Clear both pictogram and custom image caches to ensure new image appears immediately
        try {
          CustomImageService.clearCache();
          await PictogramService().clearCache();
          print('✅ Both CustomImage and Pictogram caches cleared after profile image upload');
        } catch (e) {
          print('Could not clear cache: $e');
        }
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile image uploaded successfully! Cache cleared. Your image will now appear when you use personal pronouns like "I", "me", or your name.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        await _clearLocalProfileImage();
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Upload failed');
      }
    } catch (e) {
      await _clearLocalProfileImage();
      setState(() {
        profileImageStatus = 'Error uploading image: $e';
      });
    } finally {
      setState(() {
        isProfileImageLoading = false;
      });
    }
  }

  Future<void> removeProfileImage() async {
    if ((_normalizeProfileImageUrl(profileImageUrl) ?? '').isEmpty) {
      setState(() {
        profileImageStatus = 'No profile image to remove.';
      });
      return;
    }

    setState(() {
      isProfileImageLoading = true;
      profileImageStatus = 'Removing profile image...';
    });

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'DELETE',
        '${EnvironmentConfig.apiBaseUrl}/api/remove_profile_image',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Remove failed: ${response.statusCode} ${response.body}');
      }

      await _clearLocalProfileImage();

      if (!mounted) return;
      setState(() {
        profileImageUrl = null;
        profileImageStatus = 'Profile image removed successfully!';
      });

      try {
        CustomImageService.clearCache();
        await PictogramService().clearCache();
      } catch (e) {
        debugPrint('⚠️ Failed to clear image caches after profile removal: $e');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        profileImageStatus = 'Error removing profile image: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        isProfileImageLoading = false;
      });
    }
  }

  // Friends & Family Methods
  Future<void> loadFriendsFamily() async {
    setState(() { 
      isFriendsFamilyLoading = true; 
      friendsFamilyStatus = 'Loading...'; 
    });
    
    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'GET',
        '${EnvironmentConfig.apiBaseUrl}/api/friends-family',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> ffList = data['friends_family'] ?? [];
        friendsFamily = ffList.map((e) => FriendFamily.fromJson(e)).toList();
        
        final List<dynamic> relationships = data['available_relationships'] ?? [];
        availableRelationships = relationships.cast<String>();
        
        setState(() { friendsFamilyStatus = 'Loaded.'; });
      } else {
        throw Exception('Friends & family fetch failed: ${response.statusCode}');
      }
      
    } catch (e) {
      setState(() { 
        friendsFamilyStatus = 'Error loading: $e';
        friendsFamily = [];
        availableRelationships = [];
      });
    } finally {
      setState(() { isFriendsFamilyLoading = false; });
    }
  }

  Future<void> saveFriendsFamily() async {
    // Prevent duplicate saves
    if (_isCurrentlySaving) {
      debugPrint('Save already in progress, skipping duplicate save request');
      return;
    }
    
    _isCurrentlySaving = true;
    setState(() { 
      isFriendsFamilyLoading = true; 
      friendsFamilyStatus = 'Saving...'; 
    });

    // Filter out incomplete entries and show details for debugging
    final validEntries = friendsFamily.where((person) {
      final isValid = person.name.trim().isNotEmpty;
      if (!isValid) {
        debugPrint('Excluding invalid entry - Name: "${person.name}", Relationship: "${person.relationship}"');
      }
      return isValid;
    }).toList();
    
    debugPrint('Saving ${validEntries.length} valid entries out of ${friendsFamily.length} total entries');
    for (final entry in validEntries) {
      debugPrint('Valid entry - Name: "${entry.name}", Relationship: "${entry.relationship}"');
    }

    final dataToSave = {
      'friends_family': validEntries.map((e) => e.toJson()).toList(),
      'available_relationships': availableRelationships,
    };

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/friends-family',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode(dataToSave),
      );
      
      debugPrint('Save response status: ${response.statusCode}');
      debugPrint('Save response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> ffList = responseData['friends_family'] ?? [];
        
        // Update the local list with server response to ensure consistency
        final updatedFriendFamily = ffList.map((e) => FriendFamily.fromJson(e)).toList();
        
        setState(() { 
          friendsFamily = updatedFriendFamily;
          friendsFamilyStatus = 'Saved successfully! ${updatedFriendFamily.length} entries saved.';
        });
        
        debugPrint('Successfully saved ${updatedFriendFamily.length} friends/family entries');
      } else {
        // Enhanced error handling for debugging
        String errorDetails = 'Save failed: ${response.statusCode}';
        if (response.statusCode == 422) {
          try {
            final errorBody = json.decode(response.body);
            errorDetails = 'Validation Error: ${errorBody['message'] ?? errorBody.toString()}';
            debugPrint('422 Error Details: ${response.body}');
          } catch (e) {
            errorDetails = 'Validation Error: ${response.body}';
          }
        } else if (response.statusCode >= 500) {
          errorDetails = 'Server Error: ${response.statusCode} - Please try again';
        }
        throw Exception(errorDetails);
      }
      
    } catch (e) {
      setState(() { friendsFamilyStatus = 'Error saving: $e'; });
    } finally {
      setState(() { 
        isFriendsFamilyLoading = false; 
      });
      _isCurrentlySaving = false; // Reset the duplicate save flag
    }
  }

  void addFriendsFamilyRow() {
    setState(() {
      friendsFamily.add(FriendFamily());
    });
  }

  // Audio Interview Methods
  Future<void> _launchAudioInterview() async {
    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => AudioInterviewPage(
            idToken: widget.idToken,
            aacUserId: widget.aacUserId,
          ),
        ),
      );
      
      if (result != null) {
        _processInterviewResults(result);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching audio interview: $e')),
      );
    }
  }

  void _processInterviewResults(Map<String, dynamic> results) {
    setState(() {
      // Update the narrative text field with generated content
      if (results['narrative'] != null && results['narrative'].toString().isNotEmpty) {
        userInfoController.text = results['narrative'];
        userInfoStatus = 'Interview completed! Profile generated automatically.';
      }
      
      // Update the name field if extracted from interview
      if (results['userName'] != null && results['userName'].toString().isNotEmpty) {
        userNameController.text = results['userName'];
      }
      
      // Update the birthday field if extracted from interview
      if (results['userBirthday'] != null && results['userBirthday'].toString().isNotEmpty) {
        userBirthdateController.text = results['userBirthday'];
      }
      
      // TODO: Update friends & family if provided in future enhancement
      // if (results['friendsFamily'] != null) {
      //   final List<dynamic> ffResults = results['friendsFamily'];
      //   // Process and add to friendsFamily list
      // }
    });
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Interview completed successfully! User profile has been generated.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Family & Friends Interview Methods
  Future<void> _startFamilyFriendsInterview() async {
    try {
      await showDialog<ExtractedPerson>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return FamilyFriendsInterviewPage(
            idToken: widget.idToken,
            aacUserId: widget.aacUserId,
            onPersonAdded: (person) {
              // Add person immediately to the list
              _addPersonFromInterview(person);
              // Don't close dialog here - let the interview page handle it
            },
          );
        },
      );
      
      // Person addition is now handled in the callback immediately
      // No need to process result here since _addPersonFromInterview is called directly
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting family & friends interview: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addPersonFromInterview(ExtractedPerson person) {
    debugPrint('🔄 _addPersonFromInterview called for: ${person.name} (${person.relationship})');
    debugPrint('🔄 Current save state: _isCurrentlySaving = $_isCurrentlySaving');
    
    // Add relationship to available list if it's not already there
    if (person.relationship.trim().isNotEmpty && !availableRelationships.contains(person.relationship)) {
      debugPrint('Adding new relationship to available list: ${person.relationship}');
      setState(() {
        availableRelationships.add(person.relationship);
      });
      // Save the new relationship to the backend
      _saveNewRelationship(person.relationship);
    }
    
    // Convert ExtractedPerson to FriendFamily and add to list
    final newPerson = FriendFamily(
      name: person.name,
      relationship: person.relationship,
      about: person.about,
      birthday: person.birthday,
    );

    // Check if this person already exists to prevent duplicates
    final existingPersonIndex = friendsFamily.indexWhere(
      (existing) => existing.name.toLowerCase() == person.name.toLowerCase() && 
                   existing.relationship.toLowerCase() == person.relationship.toLowerCase()
    );
    
    if (existingPersonIndex != -1) {
      debugPrint('⚠️ Person ${person.name} (${person.relationship}) already exists, not adding duplicate');
      return;
    }

    setState(() {
      friendsFamily.add(newPerson);
    });
    
    debugPrint('✅ Added new person: ${person.name} (${person.relationship})');

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${person.name} to your Friends & Family!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );

    // Auto-save the updated friends & family list
    debugPrint('🔄 Calling auto-save for friends & family');
    saveFriendsFamily();
  }

  void removeFriendsFamilyRow(int index) {
    setState(() {
      friendsFamily.removeAt(index);
    });
  }

  // Relationship Management Methods
  Future<void> _saveNewRelationship(String relationship) async {
    try {
      debugPrint('Saving new relationship to backend: $relationship');
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/manage-relationships'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': 'add',
          'relationship': relationship,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Successfully saved new relationship: $relationship');
      } else {
        debugPrint('Failed to save relationship: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error saving new relationship: $e');
    }
  }

  Future<void> addRelationship() async {
    final newRelationship = newRelationshipController.text.trim();
    if (newRelationship.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a relationship type.')),
      );
      return;
    }

    if (availableRelationships.contains(newRelationship)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This relationship type already exists.')),
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiBaseUrl}/api/manage-relationships'),
        headers: {
          'Authorization': 'Bearer ${widget.idToken}',
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': 'add',
          'relationship': newRelationship,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> relationships = data['available_relationships'] ?? [];
        setState(() {
          availableRelationships = relationships.cast<String>();
          newRelationshipController.clear();
        });
      } else {
        throw Exception('Add relationship failed: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding relationship: $e')),
      );
    }
  }

  Future<void> removeRelationship(String relationship) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm'),
        content: Text('Remove "$relationship" from available relationships?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await AuthenticatedHttpClient.makeAuthenticatedRequest(
        'POST',
        '${EnvironmentConfig.apiBaseUrl}/api/manage-relationships',
        baseHeaders: {
          'X-User-ID': widget.aacUserId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': 'remove',
          'relationship': relationship,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> relationships = data['available_relationships'] ?? [];
        setState(() {
          availableRelationships = relationships.cast<String>();
        });
      } else {
        throw Exception('Remove relationship failed: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing relationship: $e')),
      );
    }
  }

  @override
  void dispose() {
    // Re-disable keyboard when leaving admin page
    _disableKeyboardForMainApp();
    
    userInfoController.dispose();
    userBirthdateController.dispose();
    userNameController.dispose();
    newRelationshipController.dispose();
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

  Widget _buildUserInfoSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'User Information',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _launchAudioInterview,
                  icon: const Icon(Icons.mic, color: Colors.white),
                  label: const Text('Audio Interview', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border.all(color: Colors.blue[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Try the Audio Interview feature! It will ask you targeted questions about the user and automatically generate a comprehensive profile. The user\'s name and birthday will be automatically extracted and populated in the fields below.',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'General Information & Interests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userInfoController,
              maxLines: 10,
              onTap: () {
                // Show keyboard when text field is tapped
                _showKeyboardWhenNeeded();
              },
              decoration: const InputDecoration(
                hintText: 'Enter general details about the user, interests, preferences, etc. This helps personalize responses.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Include as much relevant detail as possible.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              "User's Name",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userNameController,
              onTap: () {
                // Show keyboard when text field is tapped
                _showKeyboardWhenNeeded();
              },
              decoration: const InputDecoration(
                hintText: 'Enter the user\'s preferred name',
                border: OutlineInputBorder(),
                constraints: BoxConstraints(maxWidth: 300),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'This name will be used for tagging profile pictures and personal pronouns.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              "User's Birthday",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userBirthdateController,
              onTap: () {
                // Show keyboard when text field is tapped
                _showKeyboardWhenNeeded();
              },
              decoration: const InputDecoration(
                hintText: 'YYYY-MM-DD',
                border: OutlineInputBorder(),
                constraints: BoxConstraints(maxWidth: 200),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Include the year to calculate age.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              "Profile Picture",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                border: Border.all(color: Colors.green[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.photo_camera, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Upload a picture of the user. It will be automatically tagged with their name and personal pronouns (I, me, myself) so it appears when they use these words.',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Display current profile image if available
            if ((_normalizeProfileImageUrl(profileImageUrl) ?? '').isNotEmpty) ...[
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Builder(
                    builder: (context) {
                      final resolvedUrl = _normalizeProfileImageUrl(profileImageUrl)!;
                      if (_isLocalFileUrl(resolvedUrl)) {
                        final localPath = _toLocalFilePath(resolvedUrl);
                        return Image.file(
                          File(localPath),
                          key: ValueKey(localPath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.error, color: Colors.red, size: 24),
                            );
                          },
                        );
                      }

                      return Image.network(
                        resolvedUrl,
                        key: ValueKey(resolvedUrl),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              profileImageStatus =
                                  'Profile image preview failed to load: $error';
                            });
                          });
                          return const Center(
                            child: Icon(Icons.error, color: Colors.red, size: 24),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Current Profile Picture',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isProfileImageLoading ? null : uploadProfileImage,
                  icon: const Icon(Icons.add_a_photo),
                  label: Text((_normalizeProfileImageUrl(profileImageUrl) ?? '').isNotEmpty
                      ? 'Replace Profile Picture' 
                      : 'Upload Profile Picture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                if ((_normalizeProfileImageUrl(profileImageUrl) ?? '').isNotEmpty) ...[
                  ElevatedButton.icon(
                    onPressed: isProfileImageLoading ? null : removeProfileImage,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove Profile Picture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        CustomImageService.clearCache();
                        await PictogramService().clearCache();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Image cache cleared! Your profile picture should now appear on tap interface buttons.'),
                            backgroundColor: Colors.blue,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      } catch (e) {
                        print('Cache clear error: $e');
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Cache'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                if (isProfileImageLoading) const CircularProgressIndicator(),
              ],
            ),
            if (profileImageStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                profileImageStatus,
                style: TextStyle(
                  fontSize: 12,
                  color: profileImageStatus.toLowerCase().contains('error') 
                    ? Colors.red 
                    : Colors.green[700],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isUserInfoLoading ? null : saveUserInfoAndBirthday,
                  icon: const Icon(Icons.save),
                  label: const Text('Save User Information'),
                ),
                const SizedBox(width: 16),
                if (isUserInfoLoading) const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    userInfoStatus,
                    style: TextStyle(
                      color: userInfoStatus.toLowerCase().contains('error') 
                        ? Colors.red 
                        : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodSection() {
    return Consumer<UserSettingsProvider>(
      builder: (context, provider, child) {
        final settings = provider.settings;
        if (settings == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.only(bottom: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mood Selection',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // Enable Mood Selection Checkbox
                CheckboxListTile(
                  title: const Text('Enable Mood Selection'),
                  subtitle: const Text('Allow users to select their current mood before using the app.'),
                  value: settings.enableMoodSelection,
                  onChanged: (bool? value) {
                    if (value != null) {
                      provider.updateSettings((s) => s.enableMoodSelection = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                // Current Mood Dropdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Mood:',
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
                            value: settings.currentMood,
                            items: MoodOptions.allMoodNames.map((mood) {
                              return DropdownMenuItem<String>(
                                value: mood,
                                child: Text(
                                  mood == MoodOptions.noMoodSelected 
                                      ? mood 
                                      : MoodOptions.getMoodWithEmoji(mood)
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                provider.updateSettings((s) => s.currentMood = newValue);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            provider.updateSettings((s) => s.currentMood = MoodOptions.noMoodSelected);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[400],
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Clear Session Mood'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            final success = await provider.saveSettings(provider.settings!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(success ? 'Mood saved successfully' : 'Failed to save mood'),
                                  backgroundColor: success ? Colors.green : Colors.red,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  Widget _buildCustomImagesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CustomImagesWidget(
          idToken: widget.idToken,
          aacUserId: widget.aacUserId,
        ),
      ),
    );
  }

  Widget _buildFriendsFamilySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Friends & Family',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => setState(() { showRelationshipModal = true; }),
                  icon: const Icon(Icons.settings),
                  label: const Text('Manage Relationship Types'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Add people important to you with their relationship, background info, and birthdays.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _buildFriendsFamilyTable(),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: addFriendsFamilyRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Person'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _startFamilyFriendsInterview,
                  icon: const Icon(Icons.mic),
                  label: const Text('Audio Interview'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isFriendsFamilyLoading ? null : saveFriendsFamily,
                  icon: const Icon(Icons.people),
                  label: const Text('Save Friends & Family'),
                ),
                const SizedBox(width: 16),
                if (isFriendsFamilyLoading) const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    friendsFamilyStatus,
                    style: TextStyle(
                      color: friendsFamilyStatus.toLowerCase().contains('error') 
                        ? Colors.red 
                        : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsFamilyTable() {
    if (friendsFamily.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No friends or family added yet. Click "Add Person" to get started.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Relationship', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('About', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Birthday (MM-DD)', style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(width: 60, child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        // Rows
        ...friendsFamily.asMap().entries.map((entry) {
          final index = entry.key;
          final person = entry.value;
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                // Name
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: TextEditingController(text: person.name),
                    decoration: const InputDecoration(
                      hintText: 'Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => person.name = value,
                  ),
                ),
                const SizedBox(width: 8),
                // Relationship
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: person.relationship.isEmpty ? null : person.relationship,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    hint: const Text('Select...'),
                    items: availableRelationships.map((relationship) {
                      return DropdownMenuItem(
                        value: relationship,
                        child: Text(relationship),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() {
                      person.relationship = value ?? '';
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                // About
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: TextEditingController(text: person.about),
                    decoration: const InputDecoration(
                      hintText: 'Background, interests, etc.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                    onChanged: (value) => person.about = value,
                  ),
                ),
                const SizedBox(width: 8),
                // Birthday
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: TextEditingController(text: person.birthday),
                    decoration: const InputDecoration(
                      hintText: 'MM-DD',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      if (value.isEmpty || RegExp(r'^\d{2}-\d{2}$').hasMatch(value)) {
                        if (value.isNotEmpty) {
                          final parts = value.split('-');
                          final month = int.tryParse(parts[0]);
                          final day = int.tryParse(parts[1]);
                          if (month != null && day != null && 
                              month >= 1 && month <= 12 && 
                              day >= 1 && day <= 31) {
                            person.birthday = value;
                          }
                        } else {
                          person.birthday = value;
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Delete button
                SizedBox(
                  width: 60,
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => removeFriendsFamilyRow(index),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildRelationshipModal() {
    return AlertDialog(
      title: const Text('Manage Relationship Types'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add new relationship
            const Text(
              'Add New Relationship Type',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: newRelationshipController,
                    decoration: const InputDecoration(
                      hintText: 'Enter relationship type',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: addRelationship,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Current relationships
            const Text(
              'Current Relationship Types',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                itemCount: availableRelationships.length,
                itemBuilder: (context, index) {
                  final relationship = availableRelationships[index];
                  return ListTile(
                    title: Text(relationship),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => removeRelationship(relationship),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() { showRelationshipModal = false; }),
          child: const Text('Close'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Data is loaded in initState(), no need to reload in build method
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Information & Friends & Family Admin'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserInfoSection(),
                const SizedBox(height: 32),
                _buildMoodSection(),
                const SizedBox(height: 32),
                _buildFriendsFamilySection(),
                const SizedBox(height: 32),
                _buildCustomImagesSection(),
              ],
            ),
          ),
          if (showRelationshipModal)
            Container(
              color: Colors.black54,
              child: Center(
                child: _buildRelationshipModal(),
              ),
            ),
        ],
      ),
    );
  }
}
