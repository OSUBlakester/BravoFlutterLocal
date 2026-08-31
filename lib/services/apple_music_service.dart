import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApplePlaylist {
  final String id;
  final String name;
  final int trackCount;

  const ApplePlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
  });
}

class AppleMusicService extends ChangeNotifier {
  static const _channel = MethodChannel('audio_routing');
  static const _prefKey = 'music_service_preference';

  List<ApplePlaylist> _playlists = [];
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _currentTrack;
  String? _currentArtist;
  String? _currentPlaylistName;
  String? _lastError;

  List<ApplePlaylist> get playlists => _playlists;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  String? get currentTrack => _currentTrack;
  String? get currentArtist => _currentArtist;
  String? get currentPlaylistName => _currentPlaylistName;
  String? get lastError => _lastError;

  // ---------- Permission ----------

  // Returns MPMediaLibrary auth status: 0=notDetermined 1=denied 2=restricted 3=authorized
  Future<int> getAuthStatus() async {
    try {
      return await _channel.invokeMethod<int>('appleMusic_getAuthStatus') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('appleMusic_requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------- Playlists ----------

  Future<void> loadPlaylists() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final status = await getAuthStatus();
      if (status == 0) {
        final granted = await requestPermission();
        if (!granted) {
          _lastError =
              'Apple Music access not authorized. Allow access in Settings > Privacy > Media & Apple Music.';
          _isLoading = false;
          notifyListeners();
          return;
        }
      } else if (status != 3) {
        _lastError =
            'Apple Music access denied. Enable in Settings > Privacy > Media & Apple Music.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final List<dynamic>? raw = await _channel.invokeMethod('appleMusic_getPlaylists');
      _playlists = (raw ?? []).map((p) {
        final m = Map<String, dynamic>.from(p as Map);
        return ApplePlaylist(
          id: m['id'] as String? ?? '',
          name: m['name'] as String? ?? 'Unnamed',
          trackCount: m['trackCount'] as int? ?? 0,
        );
      }).toList();

      if (_playlists.isEmpty) {
        _lastError =
            'No playlists found in your Apple Music library. Add playlists in the Music app first.';
      }
    } catch (e) {
      _lastError = 'Failed to load Apple Music playlists: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------- Playback ----------

  Future<void> playPlaylist(ApplePlaylist playlist) async {
    _lastError = null;
    try {
      await _channel.invokeMethod('appleMusic_playPlaylist', {'id': playlist.id});
      _isPlaying = true;
      _currentPlaylistName = playlist.name;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 1500));
      await _refreshState();
    } catch (e) {
      _lastError = 'Failed to play: $e';
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _lastError = null;
    try {
      await _channel.invokeMethod('appleMusic_pause');
      _isPlaying = false;
      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to pause: $e';
      notifyListeners();
    }
  }

  Future<void> pauseForScanning() => pause();

  Future<void> resume() async {
    _lastError = null;
    try {
      await _channel.invokeMethod('appleMusic_resume');
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to resume: $e';
      notifyListeners();
    }
  }

  Future<void> skipNext() async {
    _lastError = null;
    try {
      await _channel.invokeMethod('appleMusic_skipNext');
      // MPMusicPlayerController needs time to buffer the next track before play()
      // takes effect. Calling play() immediately after skipToNextItem() is a no-op
      // while the player is still loading. Wait 500 ms then issue an explicit play.
      await Future.delayed(const Duration(milliseconds: 500));
      await _channel.invokeMethod('appleMusic_resume');
      _isPlaying = true;
      notifyListeners();
      // Allow playback to fully start before reading state back.
      await Future.delayed(const Duration(milliseconds: 600));
      await _refreshState();
    } catch (e) {
      _lastError = 'Failed to skip: $e';
      notifyListeners();
    }
  }

  Future<void> stopPlayback() async {
    await pause();
    _currentTrack = null;
    _currentArtist = null;
    _currentPlaylistName = null;
    notifyListeners();
  }

  void prepareForNewSession() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> _refreshState() async {
    try {
      final Map<dynamic, dynamic>? state =
          await _channel.invokeMethod('appleMusic_getPlayerState');
      if (state != null) {
        _isPlaying = state['isPlaying'] as bool? ?? false;
        final track = state['trackName'] as String? ?? '';
        final artist = state['artistName'] as String? ?? '';
        _currentTrack = track.isNotEmpty ? track : null;
        _currentArtist = artist.isNotEmpty ? artist : null;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---------- Service preference ----------

  static Future<bool> hasServicePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefKey);
  }

  static Future<String> loadServicePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? 'spotify';
  }

  static Future<void> saveServicePreference(String service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, service);
  }
}
