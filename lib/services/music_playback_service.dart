import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

class SpotifyPlaylist {
  final String id;
  final String name;
  final String uri;
  final String? ownerName;
  final int trackCount;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.uri,
    required this.ownerName,
    required this.trackCount,
  });

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    // Spotify February 2026 API updates renamed 'tracks' to 'items'
    final itemsObj = json['items'] ?? json['tracks'];
    return SpotifyPlaylist(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Playlist').toString(),
      uri: (json['uri'] ?? '').toString(),
      ownerName: (json['owner']?['display_name'] ?? '').toString(),
      trackCount: (itemsObj?['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class MusicPlaybackService extends ChangeNotifier with WidgetsBindingObserver {
  MusicPlaybackService() {
    WidgetsBinding.instance.addObserver(this);
    ensureInitialized();
  }

  Future<void>? _initFuture;

  Future<void> ensureInitialized() async {
    _initFuture ??= _loadCredentials();
    await _initFuture;
  }

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _defaultSpotifyClientId =
      'edc14b20420c4f37bf0aa11de1d4b916';
  static const String _defaultSpotifyRedirectUri =
      'bravo://spotify-auth-callback';
    static const String _iosWakeSpotifyUri =
      'spotify:track:1yO1F9Yv1u1rW6Q9Gq4t5L';
  static const String _clientIdKey = 'spotify_client_id';
  static const String _redirectUriKey = 'spotify_redirect_uri';
  static const String _accessTokenKey = 'spotify_access_token';
  static const String _scope =
      'app-remote-control,user-read-playback-state,user-modify-playback-state,playlist-read-private,playlist-read-collaborative,user-read-currently-playing,user-read-private,user-read-email';

  String _clientId = '';
  String _redirectUri = '';
  String _accessToken = '';

  bool _isLoading = false;
  bool _isConnected = false;
  bool _shouldReconnectOnActive = false;
  bool _isPlaying = false;
  bool _webApiForbidden = false;
  bool _isDucked = false;
  int _activeAnnouncementCount = 0;
  int _savedVolume = 100;
  String? _currentTrack;
  String? _currentArtist;
  String? _currentPlaylistName;
  String? _lastPlayedUri;
  String? _lastTrackUri; // URI of the track playing at the moment pause was triggered
  int? _lastPlaybackPosition; // Playback position (ms) at the moment pause was triggered
  String? _lastError;
  bool _playbackRequested = false;
  bool _isStartingPlayback = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  final List<SpotifyPlaylist> _playlists = <SpotifyPlaylist>[];

  String get clientId => _clientId;
  String get redirectUri => _redirectUri;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  bool get isPlaying => _isPlaying;
  bool get isConfigured => _clientId.trim().isNotEmpty && _redirectUri.trim().isNotEmpty;

  DateTime? _lastPlayCommandTime;

  bool get _isTransitioningToPlay {
    if (_lastPlayCommandTime == null) return false;
    return DateTime.now().difference(_lastPlayCommandTime!) < const Duration(seconds: 6);
  }
  String? get currentTrack => _currentTrack;
  String? get currentArtist => _currentArtist;
  String? get currentPlaylistName => _currentPlaylistName;
  String? get lastError => _lastError;
  bool get webApiForbidden => _webApiForbidden;
  List<SpotifyPlaylist> get playlists => List<SpotifyPlaylist>.unmodifiable(_playlists);
  List<SpotifyPlaylist> get fallbackPlaylists =>
      List<SpotifyPlaylist>.unmodifiable(_fallbackPlaylists);

  static const List<SpotifyPlaylist> _fallbackPlaylists = <SpotifyPlaylist>[
    SpotifyPlaylist(
      id: 'fallback-kids-pop',
      name: 'Kids Pop Mix',
      uri: 'spotify:playlist:37i9dQZF1DWVGy1YP1ojM8',
      ownerName: 'Spotify',
      trackCount: 0,
    ),
    SpotifyPlaylist(
      id: 'fallback-direct-track',
      name: 'Start With A Song (Direct Track)',
      uri: 'spotify:track:4iV5W9uYEdYUVa79Axb7Rh',
      ownerName: 'Spotify',
      trackCount: 1,
    ),
    SpotifyPlaylist(
      id: 'fallback-family-favorites',
      name: 'Family Road Trip',
      uri: 'spotify:playlist:37i9dQZF1DX1lVhptIYRda',
      ownerName: 'Spotify',
      trackCount: 0,
    ),
    SpotifyPlaylist(
      id: 'fallback-disney-hits',
      name: 'Disney Hits',
      uri: 'spotify:playlist:37i9dQZF1DX8C9xQcOrE6T',
      ownerName: 'Spotify',
      trackCount: 0,
    ),
    SpotifyPlaylist(
      id: 'fallback-happy-beats',
      name: 'Happy Beats',
      uri: 'spotify:playlist:37i9dQZF1DXdPec7aLTmlC',
      ownerName: 'Spotify',
      trackCount: 0,
    ),
  ];

  String get musicContextSummary {
    final song = _currentTrack?.trim() ?? '';
    final artist = _currentArtist?.trim() ?? '';
    final playlist = _currentPlaylistName?.trim() ?? '';

    if (song.isNotEmpty && artist.isNotEmpty && playlist.isNotEmpty) {
      return 'We are listening to $song by $artist from the playlist $playlist.';
    }
    if (song.isNotEmpty && artist.isNotEmpty) {
      return 'We are listening to $song by $artist.';
    }
    if (playlist.isNotEmpty) {
      return 'We are listening to music from the playlist $playlist.';
    }
    return 'We are listening to music.';
  }

  Future<void> _loadCredentials() async {
    // Read from secure storage first to enable custom developer profiles.
    _clientId = await _storage.read(key: _clientIdKey) ?? '';
    _redirectUri = await _storage.read(key: _redirectUriKey) ?? '';

    if (_clientId.trim().isEmpty) {
      _clientId = _defaultSpotifyClientId;
      await _storage.write(key: _clientIdKey, value: _clientId);
    }
    if (_redirectUri.trim().isEmpty) {
      _redirectUri = _defaultSpotifyRedirectUri;
      await _storage.write(key: _redirectUriKey, value: _redirectUri);
    }

    _accessToken = await _storage.read(key: _accessTokenKey) ?? '';
    notifyListeners();
  }

  Future<void> saveCredentials({
    required String clientId,
    required String redirectUri,
  }) async {
    await ensureInitialized();
    _clientId = clientId.trim();
    _redirectUri = redirectUri.trim();

    await _storage.write(key: _clientIdKey, value: _clientId);
    await _storage.write(key: _redirectUriKey, value: _redirectUri);
    notifyListeners();
  }

  Future<void> clearCredentials() async {
    await ensureInitialized();
    _clientId = _defaultSpotifyClientId;
    _redirectUri = _defaultSpotifyRedirectUri;
    _accessToken = '';
    _isConnected = false;
    _isPlaying = false;
    _currentTrack = null;
    _currentArtist = null;
    _currentPlaylistName = null;
    _playlists.clear();

    await _storage.write(key: _clientIdKey, value: _clientId);
    await _storage.write(key: _redirectUriKey, value: _redirectUri);
    await _storage.delete(key: _accessTokenKey);

    try {
      await SpotifySdk.disconnect();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> connect({bool autoPause = false, bool showSpinner = true}) async {
    await ensureInitialized();
    if (showSpinner) {
      _setLoading(true);
    }
    _lastError = null;
    _playbackRequested = false;

    if (!isConfigured) {
      _lastError = 'Spotify is not configured yet. Add Client ID and Redirect URI first.';
      if (showSpinner) {
        _setLoading(false);
      }
      return;
    }

    final trimmedClientId = _clientId.trim();
    final looksLikeEmailOrUsername = trimmedClientId.contains('@');
    final validClientIdFormat = RegExp(r'^[A-Za-z0-9]{32}$').hasMatch(
      trimmedClientId,
    );
    if (!validClientIdFormat || looksLikeEmailOrUsername) {
      _lastError =
          'Invalid Spotify Client ID. Use the 32-character Client ID from Spotify Developer Dashboard (not email/username).';
      if (showSpinner) {
        _setLoading(false);
      }
      return;
    }

    try {
      // Retrieve existing token if present to prevent multiple authorization redirects.
      if (_accessToken.trim().isEmpty) {
        _accessToken = await _storage.read(key: _accessTokenKey) ?? '';
      }

      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUri,
        spotifyUri: _iosWakeSpotifyUri,
      ).timeout(
        const Duration(seconds: 20),
      );

      _isConnected = connected;
      _webApiForbidden = false;
      if (!connected) {
        _lastError = 'Could not connect to Spotify app.';
      }

      if (_isConnected) {
        if (autoPause && !_playbackRequested) {
          // Wait a short moment for Spotify to register connection and start wake track, then pause
          await Future.delayed(const Duration(milliseconds: 1000));
          if (!_playbackRequested) {
            try {
              await SpotifySdk.pause().timeout(const Duration(seconds: 2));
            } catch (_) {}
          }
        }
        await refreshPlayerState();
        _lastError = null;
        try {
          await refreshPlaylists().timeout(
            const Duration(seconds: 15),
          );
        } catch (_) {}
      }
    } on PlatformException catch (e) {
      final code = e.code.trim();
      final message = (e.message ?? '').trim();
      final combined = '$code $message'.toLowerCase();

      if (combined.contains('redirect') ||
          combined.contains('invalid client') ||
          combined.contains('authentication') ||
          combined.contains('auth')) {
        _lastError =
            'Spotify authentication failed. Verify Client ID and ensure Redirect URI bravo://spotify-auth-callback is added in Spotify Dashboard.';
      } else if (combined.contains('spotify app') ||
          combined.contains('not installed') ||
          combined.contains('app not found')) {
        _lastError =
            'Unable to complete Spotify handoff. Make sure Spotify is installed, signed in, and unlocked, then tap Connect Spotify again.';
      } else {
        _lastError =
            message.isNotEmpty ? 'Spotify connection failed: $message' : 'Spotify connection failed ($code).';
      }
    } catch (e) {
      _lastError = 'Spotify connection failed: $e';
    } finally {
      if (showSpinner) {
        _setLoading(false);
      }
    }
  }

  Future<void> disconnect() async {
    await ensureInitialized();
    _isConnected = false;
    _isPlaying = false;
    _currentTrack = null;
    _currentArtist = null;
    _currentPlaylistName = null;
    _lastPlayedUri = null;
    _lastTrackUri = null;
    _lastPlaybackPosition = null;
    try {
      await SpotifySdk.pause().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await _webApiPause();
    try {
      await SpotifySdk.disconnect();
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> _getFreshAccessToken() async {
    try {
      final token = await SpotifySdk.getAccessToken(
        clientId: _clientId,
        redirectUrl: _redirectUri,
        scope: _scope,
      ).timeout(
        const Duration(seconds: 15),
      );
      _accessToken = token;
      await _storage.write(key: _accessTokenKey, value: _accessToken);
      return true;
    } on PlatformException catch (e) {
      final message = (e.message ?? '').trim();
      final combined = '${e.code} $message'.toLowerCase();
      final tokenExchangeTransportFailure =
          combined.contains('tokenexchanger') ||
          combined.contains('tokenechanger') ||
          combined.contains('accounts_http_transport_error') ||
          combined.contains('kpermanentnetworkerror') ||
          combined.contains('transport failure');

      if (tokenExchangeTransportFailure) {
        _webApiForbidden = true;
        _lastError = 'Spotify Web API token exchange unavailable on this device/network: $message';
      } else {
        _webApiForbidden = false;
        _lastError = message.isNotEmpty
            ? 'Connected to Spotify, but playlist authorization failed: $message'
            : 'Connected to Spotify, but playlist authorization failed.';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _webApiForbidden = true;
      _lastError = 'Spotify connection failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshPlaylists({bool forceNewToken = false}) async {
    await ensureInitialized();
    _setLoading(true);
    _lastError = null;

    if (_accessToken.isEmpty || forceNewToken) {
      final gotToken = await _getFreshAccessToken();
      if (!gotToken) {
        _setLoading(false);
        return;
      }
    }

    try {
      final loaded = <SpotifyPlaylist>[];
      String? nextUrl = 'https://api.spotify.com/v1/me/playlists?limit=50';
      bool needsReauth = false;

      while (nextUrl != null) {
        final response = await http.get(
          Uri.parse(nextUrl),
          headers: <String, String>{
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 401 || response.statusCode == 403) {
          // Token expired (401) or forbidden (403). If we haven't already forced a new token, try to re-authorize once automatically.
          if (!forceNewToken) {
            needsReauth = true;
            break;
          } else if (response.statusCode == 401) {
            _webApiForbidden = false;
            _lastError = 'Spotify authorization expired (401). Tap Connect Spotify again.';
            break;
          }
        }

        if (response.statusCode != 200) {
          String spotifyApiMessage = '';
          try {
            final payload = json.decode(response.body);
            if (payload is Map<String, dynamic>) {
              final error = payload['error'];
              if (error is Map<String, dynamic>) {
                spotifyApiMessage = (error['message'] ?? '').toString().trim();
              } else {
                spotifyApiMessage = (payload['message'] ?? '').toString().trim();
              }
            }
          } catch (_) {}

          if (response.statusCode == 403) {
            _webApiForbidden = true; // Set to true to show fallback banner in UI
            final accountDetails = await _fetchSpotifyAccountDetails();
            final product = (accountDetails['product'] ?? '').toString();
            final email = (accountDetails['email'] ?? '').toString();

            final accountText = email.isNotEmpty
                ? ' Current account: $email ($product).'
                : '';
            final apiText = spotifyApiMessage.isNotEmpty
                ? ' Spotify says: $spotifyApiMessage.'
                : '';

            _lastError = 'Access denied (403) for Client ID: $_clientId. Make sure your account is registered as a Sandbox User in the Spotify Developer Dashboard.'
                '$accountText$apiText';

            assert(() {
              debugPrint('Spotify Web API restricted (403).$accountText$apiText');
              return true;
            }());
          } else {
            _webApiForbidden = false;
            _lastError =
                'Unable to load playlists (${response.statusCode}). $spotifyApiMessage';
          }
          break;
        }

        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(SpotifyPlaylist.fromJson)
            .where((playlist) => playlist.uri.trim().isNotEmpty)
            .toList();

        loaded.addAll(items);
        nextUrl = data['next']?.toString();
      }

      if (needsReauth) {
        // Clear token, force a new token and retry once
        _accessToken = '';
        await _storage.delete(key: _accessTokenKey);
        _setLoading(false); // reset loading before recursive call
        await refreshPlaylists(forceNewToken: true);
        return;
      }

      if (_lastError == null) {
        _playlists
          ..clear()
          ..addAll(loaded);
        _webApiForbidden = false;
      }

      // Keep empty playlist responses non-blocking.
      if (_playlists.isEmpty && _lastError == null) {
        _lastError = null;
      }
    } catch (e) {
      _lastError = 'Unable to load playlists: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> playPlaylist(SpotifyPlaylist playlist) async {
    await playPlaylistUri(uri: playlist.uri, playlistName: playlist.name);
  }

  Future<void> playPlaylistUri({
    required String uri,
    String? playlistName,
  }) async {
    await ensureInitialized();
    _playbackRequested = true;
    _isStartingPlayback = true;
    _lastPlayCommandTime = DateTime.now();
    _lastError = null;
    bool connected = false;
    bool playSucceeded = false;

    try {
      const maxRetries = 3;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        // If the app has gone to the background, it means Spotify was opened successfully.
        // We must abort the retry loop immediately to prevent calling disconnect/reconnect
        // while Spotify is booting and starting playback.
        if (attempt > 1 && (_lifecycleState == AppLifecycleState.paused || _lifecycleState == AppLifecycleState.inactive)) {
          assert(() {
            debugPrint('Spotify playPlaylistUri: App went to background (Spotify launched), stopping retry loop.');
            return true;
          }());
          playSucceeded = true;
          connected = true;
          break;
        }
        try {
          assert(() {
            debugPrint('Spotify playPlaylistUri: Playback attempt $attempt of $maxRetries');
            return true;
          }());

          // If it's a retry attempt, force a clean disconnect first to clear any stale state.
          // Add a timeout: SpotifySdk.disconnect() with no callback (stuck write queue) would
          // otherwise hang indefinitely, making all retries silently block.
          // Set _isConnected=false after so _ensureAppRemoteConnected skips a redundant
          // second disconnect, which would otherwise double-disconnect on every retry.
          if (attempt > 1) {
            assert(() {
              debugPrint('Attempt $attempt: Disconnecting before reconnecting to clear stale session');
              return true;
            }());
            try {
              await SpotifySdk.disconnect().timeout(const Duration(seconds: 3));
            } catch (_) {}
            _isConnected = false;
            await Future.delayed(const Duration(milliseconds: 1000));
          }

          // Use 30s outer timeout: _ensureAppRemoteConnected internally runs
          // connectToSpotifyRemote (≤20s) + pause (≤3s) + 1.5s delay = ≤24.5s max.
          // A 20s outer timeout would race with the inner connect on slow starts.
          connected = await _ensureAppRemoteConnected(spotifyUri: uri).timeout(
            const Duration(seconds: 30),
            onTimeout: () => false,
          );

          if (connected) {
            bool playStarted = false;
            try {
              await SpotifySdk.play(spotifyUri: uri).timeout(const Duration(seconds: 15));
              playStarted = true; // callback confirmed — definitive success
            } on TimeoutException {
              // The native play command was sent but the iOS callback never fired.
              // This happens when the App Remote write queue delivers the command
              // but drops the completion callback (iOS background/resume timing).
              // Verify actual Spotify state: if it's playing, accept as success
              // rather than waiting for a retry that would restart the track.
              try {
                final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 3));
                if (state != null && !state.isPaused) {
                  assert(() {
                    debugPrint('Spotify: play() timed out but Spotify is playing — accepting');
                    return true;
                  }());
                  playStarted = true;
                }
              } catch (_) {}
            }

            if (playStarted) {
              _lastPlayCommandTime = DateTime.now();
              _isPlaying = true;
              _currentPlaylistName = playlistName;
              _lastPlayedUri = uri;
              playSucceeded = true;
              break; // Succeeded! Break out of the retry loop.
            } else {
              throw Exception('Play command sent but Spotify remains paused — retrying.');
            }
          } else {
            throw Exception('Failed to connect to Spotify App Remote.');
          }
        } catch (e) {
          assert(() {
            debugPrint('Spotify App Remote playback failed (attempt $attempt): $e');
            return true;
          }());
          playSucceeded = false;
        }

        if (!playSucceeded && attempt < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }

      if (playSucceeded) {
        // Update current track state synchronously to ensure isPlaying is updated before returning
        try {
          await refreshPlayerState().timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      // Fallback: Only open Spotify app if we were unable to connect or if play failed.
      if (!connected || !playSucceeded) {
        try {
          final opened = await launchUrl(
            Uri.parse(uri),
            mode: LaunchMode.externalApplication,
          );
          if (opened) {
            _lastError =
                'Opened Spotify for playback. If music did not start automatically, tap Play in Spotify.';
          } else {
            _lastError =
                'Spotify did not start playback. Open Spotify, start any song once, then try again.';
          }
        } catch (e) {
          _lastError = 'Unable to launch Spotify: $e';
        }
      } else {
        _lastError =
            'Playback started in Spotify. If not audible, check device volume and Spotify output target.';
      }
    } finally {
      _isStartingPlayback = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureAppRemoteConnected({String? spotifyUri}) async {
    // Only disconnect if we believe a live App Remote session exists. Calling
    // SpotifySdk.disconnect() on iOS when no session is active may never fire its
    // native callback, blocking the Dart side indefinitely.
    // When _isConnected=true a prior write (pause/play) may have stuck the native
    // write queue — disconnecting resets it completely before reconnecting.
    if (_isConnected) {
      try {
        await SpotifySdk.disconnect().timeout(const Duration(seconds: 3));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
    }

    try {
      final bool connected;
      if (spotifyUri != null) {
        // Fresh connection needed for playback. Use the wake track — not the actual
        // playlist URI — to open a stable App Remote session before sending play().
        // This mirrors the proven connect(autoPause:true) → play() flow: passing the
        // real URI here starts Spotify before the App Remote handshake is stable,
        // causing the connection to drop within ~1 s on a fresh launch.
        connected = await SpotifySdk.connectToSpotifyRemote(
          clientId: _clientId,
          redirectUrl: _redirectUri,
          spotifyUri: _iosWakeSpotifyUri,
        ).timeout(const Duration(seconds: 20));
        if (connected) {
          // Silence the wake track immediately, then give the App Remote session
          // time to fully stabilize before the caller issues play(playlistUri).
          try {
            await SpotifySdk.pause().timeout(const Duration(seconds: 3));
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      } else {
        // Reconnect without forcing any content (skip fallback path after Web API skip).
        connected = await SpotifySdk.connectToSpotifyRemote(
          clientId: _clientId,
          redirectUrl: _redirectUri,
        ).timeout(const Duration(seconds: 20));
        if (connected) {
          // Give the fresh session time to stabilize before issuing write commands.
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
      _isConnected = connected;
      return connected;
    } catch (_) {
      return false;
    }
  }

  Future<void> skipNext() async {
    _lastError = null;
    _lastPlayCommandTime = DateTime.now();
    try {
      // Skip via Web API first — advances the track in Spotify's cloud and app
      // without touching the App Remote write queue (which may be stuck).
      bool skipped = _accessToken.isNotEmpty && await _webApiSkipNext();
      debugPrint('MusicPlaybackService: skipNext() — Web API skip result: $skipped');

      // Reconnect the App Remote with a fresh session. The Web API skip advances
      // the track in Spotify's cloud; a fresh App Remote connection then sees the
      // next track and can resume it reliably via SpotifySdk.resume().
      final connected = await _ensureAppRemoteConnected();
      _isConnected = connected;
      debugPrint('MusicPlaybackService: skipNext() — App Remote reconnect: $connected');

      if (connected) {
        if (!skipped) {
          // Web API skip failed — use App Remote skip on the fresh session.
          await SpotifySdk.skipNext().timeout(const Duration(seconds: 5));
        }
        await SpotifySdk.resume().timeout(const Duration(seconds: 5));
        _isPlaying = true;
        await refreshPlayerState();
      } else {
        throw Exception('Skip failed: App Remote reconnect failed and Web API skip may not have worked.');
      }
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Unable to skip track.';
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Pause Spotify when scanning controls start (first switch press).
  ///
  /// Uses App Remote pause as the primary path — the connection is alive
  /// immediately after playPlaylistUri() succeeds, so the write queue is clean
  /// and SpotifySdk.pause() is reliable here. Web API pause returns 404/403
  /// for App Remote sessions (the device is not registered as an active Web API
  /// device), so it is used only as a last-resort fallback.
  ///
  /// Captures _lastTrackUri from player state before pausing so that a later
  /// resume can play back the correct song rather than the first playlist track.
  Future<void> pauseForScanning() async {
    if (!_isPlaying) return;
    _lastPlayCommandTime = null;

    // Capture current track URI and position before issuing any pause command.
    // getPlayerState() is a read and works even with a stuck write queue.
    try {
      final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 2));
      _lastTrackUri = state?.track?.uri;
      _lastPlaybackPosition = state?.playbackPosition;
      debugPrint('MusicPlaybackService: pauseForScanning() — captured track URI: $_lastTrackUri, position: ${_lastPlaybackPosition}ms');
    } catch (_) {
      debugPrint('MusicPlaybackService: pauseForScanning() — could not capture track state');
    }

    _isPlaying = false;
    notifyListeners();

    // Primary: App Remote pause. The connection is live right after playPlaylistUri()
    // so the write queue is clean and the callback should fire promptly.
    if (_isConnected) {
      try {
        await SpotifySdk.pause().timeout(const Duration(seconds: 5));
        debugPrint('MusicPlaybackService: pauseForScanning() — App Remote pause succeeded');
        return;
      } catch (e) {
        debugPrint('MusicPlaybackService: pauseForScanning() — App Remote pause failed: $e');
      }
    }

    // Fallback: Web API pause (may fail with 404/403 for App Remote sessions).
    if (_accessToken.isNotEmpty) {
      try {
        final ok = await _webApiPause();
        debugPrint('MusicPlaybackService: pauseForScanning() — Web API pause result: $ok');
      } catch (e) {
        debugPrint('MusicPlaybackService: pauseForScanning() — Web API pause exception: $e');
      }
    }
  }

  Future<void> pause() async {
    _lastError = null;
    _lastPlayCommandTime = null;
    try {
      // Web API first — SpotifySdk.pause() (App Remote write) can hang with a
      // stuck native write queue, while the Web API HTTP path is always clean.
      if (_accessToken.isNotEmpty) {
        final success = await _webApiPause();
        if (success) {
          _isPlaying = false;
          notifyListeners();
          return;
        }
      }
      // App Remote fallback when token is absent or Web API call fails.
      if (_isConnected) {
        await SpotifySdk.pause().timeout(const Duration(seconds: 5));
        _isPlaying = false;
      } else {
        throw Exception('Pause failed: Web API unavailable and App Remote not connected.');
      }
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Unable to pause playback.';
    } catch (e) {
      _lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> resume() async {
    _playbackRequested = true;
    _lastPlayCommandTime = DateTime.now();
    _lastError = null;
    debugPrint('MusicPlaybackService: resume() — isConnected=$_isConnected, lastTrackUri=$_lastTrackUri, lastPlayedUri=$_lastPlayedUri');
    try {
      // Tier 1: Session is live — SpotifySdk.resume() restores the exact track and
      // position because pause() was called on this same session. No reconnect
      // happened, so the App Remote context is exactly where we paused.
      // Only fall through if the callback times out (connection silently dropped).
      if (_isConnected && _lastTrackUri != null) {
        try {
          debugPrint('MusicPlaybackService: resume() — tier 1: SpotifySdk.resume()');
          bool resumeStarted = false;
          try {
            await SpotifySdk.resume().timeout(const Duration(seconds: 5));
            resumeStarted = true;
          } on TimeoutException {
            try {
              final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 2));
              if (state != null && !state.isPaused) {
                debugPrint('MusicPlaybackService: resume() — tier 1 timed out but Spotify is playing — accepting');
                resumeStarted = true;
              }
            } catch (_) {}
          }
          if (resumeStarted) {
            _isPlaying = true;
            notifyListeners();
            return;
          }
          debugPrint('MusicPlaybackService: resume() — tier 1 did not start, trying reconnect');
        } catch (e) {
          debugPrint('MusicPlaybackService: resume() — tier 1 failed: $e, trying reconnect');
        }
      }

      // Tier 2: Connection dropped — reconnect without a URI so we attach to
      // Spotify's current app state, then play the correct track and seek to position.
      debugPrint('MusicPlaybackService: resume() — tier 2: reconnect then play+seek');
      final connected = await _ensureAppRemoteConnected();
      _isConnected = connected;
      if (connected && _lastTrackUri != null) {
        try {
          bool playStarted = false;
          try {
            await SpotifySdk.play(spotifyUri: _lastTrackUri!).timeout(const Duration(seconds: 5));
            playStarted = true;
          } on TimeoutException {
            try {
              final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 2));
              if (state != null && !state.isPaused) {
                playStarted = true;
              }
            } catch (_) {}
          }
          if (playStarted) {
            _isPlaying = true;
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('MusicPlaybackService: resume() — tier 2 failed: $e');
        }
        debugPrint('MusicPlaybackService: resume() — tier 2 falling through to tier 3');
      }

      // Tier 3: Direct connect with the target URI — no wake-track, no audio blip.
      // connectToSpotifyRemote(spotifyUri: uri) starts the correct track immediately
      // without playing an unrelated wake track first. Works reliably when Spotify
      // is warm (already running from the initial session).
      // Falls back to playPlaylistUri() (wake-track approach) only if direct connect fails.
      final resumeUri = _lastTrackUri ?? _lastPlayedUri;
      if (resumeUri == null) {
        throw Exception('Resume failed: no active App Remote session and no stored URI.');
      }

      bool tier3Succeeded = false;
      try {
        debugPrint('MusicPlaybackService: resume() — tier 3 direct connect: $resumeUri');
        if (_isConnected) {
          try { await SpotifySdk.disconnect().timeout(const Duration(seconds: 3)); } catch (_) {}
          _isConnected = false;
          await Future.delayed(const Duration(milliseconds: 300));
        }
        final directConnected = await SpotifySdk.connectToSpotifyRemote(
          clientId: _clientId,
          redirectUrl: _redirectUri,
          spotifyUri: resumeUri,
        ).timeout(const Duration(seconds: 20));
        if (directConnected) {
          _isConnected = true;
          await Future.delayed(const Duration(milliseconds: 1500));
          final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 3));
          if (state != null && !state.isPaused) {
            _isPlaying = true;
            _lastPlayCommandTime = DateTime.now();
            await refreshPlayerState();
            tier3Succeeded = true;
            debugPrint('MusicPlaybackService: resume() — tier 3 direct succeeded');
          }
        }
      } catch (e) {
        debugPrint('MusicPlaybackService: resume() — tier 3 direct failed: $e');
      }

      if (!tier3Succeeded) {
        debugPrint('MusicPlaybackService: resume() — tier 3 wake-track fallback: $resumeUri');
        await playPlaylistUri(uri: resumeUri, playlistName: _currentPlaylistName);
      }
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Unable to resume playback.';
      debugPrint('MusicPlaybackService: resume() — PlatformException: ${e.message}');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('MusicPlaybackService: resume() — Exception: $e');
    } finally {
      _isStartingPlayback = false;
      notifyListeners();
    }
  }

  Future<void> stopPlayback() async {
    _playbackRequested = false;
    _lastPlayCommandTime = null;
    // Only issue a pause command when we believe Spotify is still playing.
    // If pause() was already called (e.g. the user started scanning by pressing
    // the switch), calling SpotifySdk.pause() a second time on an already-paused
    // player can cause the iOS App Remote SDK to never fire its completion callback,
    // which hangs the Dart side indefinitely and blocks every subsequent action.
    if (_isPlaying) {
      await pause();
    } else {
      _isPlaying = false; // Ensure state is consistent
    }
    _currentTrack = null;
    _currentArtist = null;
    _lastPlayedUri = null;
    _lastTrackUri = null;
    _lastPlaybackPosition = null;
    _isDucked = false;
    _activeAnnouncementCount = 0;
    notifyListeners();
  }

  Future<void> refreshPlayerState() async {
    bool gotState = false;
    if (_isConnected) {
      try {
        final playerState = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 5));
        final isPaused = playerState?.isPaused ?? true;
        if (_isTransitioningToPlay && isPaused) {
          _isPlaying = true;
        } else {
          _isPlaying = !isPaused;
        }
        _currentTrack = playerState?.track?.name;
        _currentArtist = playerState?.track?.artist.name;
        gotState = true;
      } catch (_) {
        if (_isTransitioningToPlay) {
          _isPlaying = true;
        }
      }
    }

    if (!gotState) {
      await _webApiRefreshPlayerState();
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _fetchSpotifyAccountDetails() async {
    if (_accessToken.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        String message = '';
        try {
          final payload = json.decode(response.body);
          if (payload is Map<String, dynamic>) {
            final error = payload['error'];
            if (error is Map<String, dynamic>) {
              message = (error['message'] ?? '').toString().trim();
            } else {
              message = (payload['message'] ?? '').toString().trim();
            }
          }
        } catch (_) {}

        return <String, dynamic>{
          'statusCode': response.statusCode,
          'errorMessage': message,
        };
      }

      final data = json.decode(response.body);
      if (data is Map<String, dynamic>) {
        data['statusCode'] = response.statusCode;
        return data;
      }
    } catch (_) {}

    return <String, dynamic>{};
  }

  Future<int?> _fetchCurrentVolumePercent() async {
    if (_accessToken.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final device = data['device'];
      if (device is! Map<String, dynamic>) {
        return null;
      }

      final volume = device['volume_percent'];
      if (volume is num) {
        return volume.toInt().clamp(0, 100);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _setSpotifyWebApiVolume(int volumePercent) async {
    if (_accessToken.isEmpty) return false;
    final normalized = volumePercent.clamp(0, 100);

    try {
      final response = await http.put(
        Uri.parse(
          'https://api.spotify.com/v1/me/player/volume?volume_percent=$normalized',
        ),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _webApiPause() async {
    if (_accessToken.isEmpty) return false;
    try {
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/pause'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );
      debugPrint('MusicPlaybackService: _webApiPause() — HTTP status=${response.statusCode}');
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      debugPrint('MusicPlaybackService: _webApiPause() — exception: $e');
      return false;
    }
  }


  Future<bool> _webApiSkipNext() async {
    if (_accessToken.isEmpty) return false;
    try {
      final response = await http.post(
        Uri.parse('https://api.spotify.com/v1/me/player/next'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _webApiRefreshPlayerState() async {
    if (_accessToken.isEmpty) return false;
    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          _isPlaying = data['is_playing'] ?? false;
          final item = data['item'];
          if (item is Map<String, dynamic>) {
            _currentTrack = item['name']?.toString();
            final artists = item['artists'];
            if (artists is List && artists.isNotEmpty) {
              final firstArtist = artists[0];
              if (firstArtist is Map<String, dynamic>) {
                _currentArtist = firstArtist['name']?.toString();
              }
            }
          }
          notifyListeners();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> beginAnnouncementDucking() async {
    _activeAnnouncementCount++;
    if (_activeAnnouncementCount > 1 || !_isPlaying || _isDucked) {
      return;
    }

    _savedVolume = await _fetchCurrentVolumePercent() ?? 100;

    final volumeSet = await _setSpotifyWebApiVolume(25);
    if (volumeSet) {
      _isDucked = true;
    }

    notifyListeners();
  }

  Future<void> endAnnouncementDucking() async {
    _activeAnnouncementCount = (_activeAnnouncementCount - 1).clamp(0, 999);
    if (_activeAnnouncementCount > 0 || !_isDucked) {
      return;
    }

    final restored = await _setSpotifyWebApiVolume(_savedVolume.clamp(0, 100));
    if (restored) {
      _isDucked = false;
    }

    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isConnected) {
        // Keep the App Remote alive while playback is starting, recently started,
        // or the user has an active playback session (music playing or paused).
        // _playbackRequested stays true from playPlaylistUri() until stopPlayback()
        // or connect(), covering the window between pause() and a skip/resume action.
        if (_isStartingPlayback || _isTransitioningToPlay || _playbackRequested) {
          assert(() {
            debugPrint('MusicPlaybackService: App going to background during play transition. Skipping disconnect.');
            return true;
          }());
          return;
        }
        _shouldReconnectOnActive = true;
        unawaited(
          () async {
            try {
              await SpotifySdk.disconnect();
            } catch (_) {}
            _isConnected = false;
            notifyListeners();
          }(),
        );
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_shouldReconnectOnActive || _playbackRequested) {
        _shouldReconnectOnActive = false;
        unawaited(
          () async {
            if (Platform.isIOS) {
              await refreshPlayerState();
            } else {
              final connected = await _ensureAppRemoteConnected();
              _isConnected = connected;
              if (connected) {
                await refreshPlayerState();
              }
            }
            notifyListeners();
          }(),
        );
      }
      return;
    }

    if (state == AppLifecycleState.detached) {
      unawaited(stopPlayback());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
