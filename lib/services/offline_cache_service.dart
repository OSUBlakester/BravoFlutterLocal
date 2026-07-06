import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCachedProfile {
  final String userId;
  final String displayName;

  const OfflineCachedProfile({
    required this.userId,
    required this.displayName,
  });
}

/// Service for caching app data locally for offline use.
/// All methods are static; no instantiation needed.
class OfflineCacheService {
  static const String _keyUserId = 'offline_profile_user_id';
  static const String _keyDisplayName = 'offline_profile_display_name';
  static const String _keyUserSettings = 'offline_user_settings_json';
  static const String _tapConfigFileName = 'tap_config.json';
  static const String _tapBoardsFileName = 'tap_boards.json';
  static const String _audioSubdir = 'audio';
  static const int _maxAudioFiles = 200;

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  static Future<void> saveProfile({
    required String userId,
    required String displayName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserId, userId);
      await prefs.setString(_keyDisplayName, displayName);
    } catch (e) {
      // Best-effort; do not throw
    }
  }

  static Future<OfflineCachedProfile?> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_keyUserId);
      final displayName = prefs.getString(_keyDisplayName);
      if (userId == null || userId.isEmpty) return null;
      return OfflineCachedProfile(
        userId: userId,
        displayName: displayName ?? 'User',
      );
    } catch (e) {
      return null;
    }
  }

  static Future<bool> hasCachedProfile() async {
    final profile = await loadProfile();
    return profile != null;
  }

  // ---------------------------------------------------------------------------
  // User settings
  // ---------------------------------------------------------------------------

  static Future<void> saveUserSettings(String settingsJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserSettings, settingsJson);
    } catch (e) {
      // Best-effort
    }
  }

  static Future<String?> loadUserSettingsJson() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyUserSettings);
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Tap config
  // ---------------------------------------------------------------------------

  static Future<Directory> _offlineDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/bravo_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> saveTapConfig(String configJson) async {
    try {
      final dir = await _offlineDir();
      final file = File('${dir.path}/$_tapConfigFileName');
      await file.writeAsString(configJson, flush: true);
    } catch (e) {
      // Best-effort
    }
  }

  static Future<String?> loadTapConfigJson() async {
    try {
      final dir = await _offlineDir();
      final file = File('${dir.path}/$_tapConfigFileName');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Tap boards
  // ---------------------------------------------------------------------------

  static Future<void> saveTapBoards(String boardsJson) async {
    try {
      final dir = await _offlineDir();
      final file = File('${dir.path}/$_tapBoardsFileName');
      await file.writeAsString(boardsJson, flush: true);
    } catch (e) {
      // Best-effort
    }
  }

  static Future<String?> loadTapBoardsJson() async {
    try {
      final dir = await _offlineDir();
      final file = File('${dir.path}/$_tapBoardsFileName');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Audio caching
  // ---------------------------------------------------------------------------

  static String _audioHash(String url) => url.hashCode.abs().toString();

  static Future<Directory> _audioDir() async {
    final dir = await _offlineDir();
    final audioDir = Directory('${dir.path}/$_audioSubdir');
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    return audioDir;
  }

  static Future<void> cacheAudioFiles(
    List<String> urls,
    String idToken,
  ) async {
    if (urls.isEmpty) return;
    final audioDir = await _audioDir();

    for (final url in urls) {
      if (url.isEmpty || !url.startsWith('http')) continue;
      try {
        final hash = _audioHash(url);
        final file = File('${audioDir.path}/$hash.audio');
        if (await file.exists()) continue; // already cached

        final response = await http
            .get(
              Uri.parse(url),
              headers: {'Authorization': 'Bearer $idToken'},
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(response.bodyBytes, flush: true);
        }
      } catch (e) {
        // Best-effort per file
      }
    }

    // Enforce max file limit
    await _pruneAudioCache(audioDir);
  }

  static Future<void> _pruneAudioCache(Directory audioDir) async {
    try {
      final files = await audioDir
          .list()
          .where((e) => e is File && e.path.endsWith('.audio'))
          .cast<File>()
          .toList();

      if (files.length <= _maxAudioFiles) return;

      final withStat = <MapEntry<File, FileStat>>[];
      for (final f in files) {
        withStat.add(MapEntry(f, await f.stat()));
      }
      withStat.sort(
        (a, b) => a.value.modified.compareTo(b.value.modified),
      );

      final toDelete = withStat.length - _maxAudioFiles;
      for (int i = 0; i < toDelete; i++) {
        await withStat[i].key.delete();
      }
    } catch (e) {
      // Best-effort
    }
  }

  static Future<String?> getLocalAudioPath(String url) async {
    try {
      final audioDir = await _audioDir();
      final hash = _audioHash(url);
      final file = File('${audioDir.path}/$hash.audio');
      if (await file.exists()) return file.path;
      return null;
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Master save-all
  // ---------------------------------------------------------------------------

  static Future<void> saveAll({
    required String userId,
    required String displayName,
    required String settingsJson,
    required String tapConfigJson,
    required String tapBoardsJson,
    required List<String> audioUrls,
    required String idToken,
  }) async {
    await Future.wait([
      saveProfile(userId: userId, displayName: displayName),
      saveUserSettings(settingsJson),
      saveTapConfig(tapConfigJson),
      saveTapBoards(tapBoardsJson),
    ]);

    // Cache audio in the background (non-blocking)
    if (audioUrls.isNotEmpty) {
      cacheAudioFiles(audioUrls, idToken).catchError((_) {});
    }
  }
}
