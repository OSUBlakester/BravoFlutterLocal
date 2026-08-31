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
    return DateTime.now().difference(_lastPlayCommandTime!) < const Duration(seconds: 20);
  }
  String? get currentTrack => _currentTrack;
  String? get currentArtist => _currentArtist;
  String? get currentPlaylistName => _currentPlaylistName;
  String? get lastError => _lastError;
  bool get webApiForbidden => _webApiForbidden;
  // True while a playback start or reconnect chain is in progress — used by the
  // UI to show a spinner-style status banner instead of an orange warning icon.
  bool get isReconnecting => _isStartingPlayback;
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

  /// Called when the music page opens (or re-opens after navigation).
  /// Resets flags that can be left in an inconsistent state when the page is
  /// disposed mid-flight (e.g. navigating away while playPlaylistUri is running).
  /// Does NOT call any Spotify SDK methods — those can hang on a stale iOS
  /// App Remote session and should only be triggered by actual user actions.
  void prepareForNewSession() {
    _isStartingPlayback = false;
    _isConnected = false;   // treat any prior App Remote session as stale
    _lastError = null;
    _lastPlayCommandTime = null;
    // Leave _playbackRequested, _isPlaying, playlists, and track info intact
    // so the UI can show current state without re-fetching unnecessarily.
    notifyListeners();
  }

  Future<void> disconnect() async {
    await ensureInitialized();
    _isConnected = false;
    _isPlaying = false;
    _lastError = null;
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
      // With the Swift singleton guard, _getFreshAccessToken() returns the stored
      // token from the existing connected App Remote without creating a new instance.
      // _isConnected remains accurate — do NOT reset it here.
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

        if (response.statusCode == 401) {
          // Token expired. If we haven't already forced a new token, try to re-authorize once automatically.
          if (!forceNewToken) {
            needsReauth = true;
            break;
          } else {
            _webApiForbidden = false;
            _lastError = 'Spotify authorization expired (401). Tap Connect Spotify again.';
            break;
          }
        }
        // 403: dev-mode quota restriction — do NOT needsReauth (token is valid, re-auth would
        // needlessly replace the SPTAppRemote instance). Fall through to Content API fallback.

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
            // Web API is quota-restricted (dev mode). Try the App Remote Content API,
            // which bypasses Web API entirely and works on the existing connected session.
            debugPrint('Spotify 403: trying Content API (step 1 — direct)');
            var contentPlaylists = await _fetchPlaylistsViaContentAPI();
            debugPrint('Spotify 403: step 1 result: ${contentPlaylists.length} playlists [$_contentApiDiagnostic]');
            if (contentPlaylists.isEmpty) {
              // App Remote not connected (page loaded before user tapped Connect,
              // or auth-only App Remote from a previous attempt already disconnected).
              // Use the combined native method: OAuth + Content API in one round-trip.
              // The playlist fetch runs inside appRemoteDidEstablishConnection —
              // while the connection is guaranteed live — so the auth-only App Remote
              // cannot disconnect between the token callback and the Content API call.
              debugPrint('Spotify 403: calling combined getTokenAndContentPlaylists (step 2)');
              final combined = await _getTokenAndContentPlaylists();
              debugPrint('Spotify 403: step 2 result: combined=${combined != null} [$_contentApiDiagnostic]');
              if (combined != null) {
                final (newToken, fetchedPlaylists) = combined;
                _accessToken = newToken;
                unawaited(_storage.write(key: _accessTokenKey, value: _accessToken));
                // App Remote is live after getTokenAndContentPlaylists — mark it
                // connected so playPlaylistUri() uses the direct path without an
                // unnecessary disconnect/reconnect cycle.
                _isConnected = true;
                debugPrint('Spotify 403: step 2 playlists: ${fetchedPlaylists.length}');
                if (fetchedPlaylists.isNotEmpty) {
                  contentPlaylists = fetchedPlaylists;
                } else {
                  // Token obtained; App Remote may still be live — try direct Content API.
                  debugPrint('Spotify 403: step 2 empty playlists, retrying Content API (step 3)');
                  contentPlaylists = await _fetchPlaylistsViaContentAPI();
                  debugPrint('Spotify 403: step 3 result: ${contentPlaylists.length} playlists [$_contentApiDiagnostic]');
                }
              }
            }
            if (contentPlaylists.isNotEmpty) {
              loaded.addAll(contentPlaylists);
              _webApiForbidden = false;
              break; // Success via Content API — skip error handling
            }

            // Both Web API (403) and Content API failed.
            _webApiForbidden = true;
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
                '$accountText$apiText [$_contentApiDiagnostic]';

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

  // Diagnostic string from the most recent Content API attempt — included in
  // the 403 error banner so failures are visible without console access.
  String _contentApiDiagnostic = '';

  /// Combined native call: establishes an OAuth connection (if App Remote is not
  /// already connected) and fetches Content API playlists inside the connection
  /// callback — before the auth-only App Remote can disconnect.
  ///
  /// Returns (token, playlists) on success, or null on failure.
  Future<(String, List<SpotifyPlaylist>)?> _getTokenAndContentPlaylists() async {
    try {
      final rawResult = await const MethodChannel('spotify_sdk')
          .invokeMethod<Map>('getTokenAndContentPlaylists', <String, dynamic>{
            'clientId': _clientId,
            'redirectUrl': _redirectUri,
            'scope': _scope,
          })
          .timeout(const Duration(seconds: 30));

      if (rawResult == null) {
        _contentApiDiagnostic = 'CombinedAPI: null response';
        return null;
      }

      final token = rawResult['token']?.toString() ?? '';
      if (token.isEmpty) {
        _contentApiDiagnostic = 'CombinedAPI: empty token';
        return null;
      }

      final rawPlaylists = rawResult['playlists'];
      final List<SpotifyPlaylist> playlists;
      if (rawPlaylists is List) {
        playlists = rawPlaylists
            .whereType<Map>()
            .map((m) {
              final uri = (m['uri'] ?? '').toString();
              final name = (m['name'] ?? 'Playlist').toString();
              final subtitle = (m['subtitle'] ?? '').toString();
              int trackCount = 0;
              final match = RegExp(r'(\d+)\s+song').firstMatch(subtitle);
              if (match != null) {
                trackCount = int.tryParse(match.group(1) ?? '0') ?? 0;
              }
              return SpotifyPlaylist(
                id: uri,
                name: name,
                uri: uri,
                ownerName: null,
                trackCount: trackCount,
              );
            })
            .where((p) => p.uri.trim().isNotEmpty)
            .toList();
      } else {
        playlists = [];
      }

      _contentApiDiagnostic = playlists.isNotEmpty
          ? 'CombinedAPI: ${playlists.length} playlists'
          : 'CombinedAPI: token obtained, 0 playlists';
      debugPrint('Spotify CombinedAPI: token obtained, ${playlists.length} playlists');
      return (token, playlists);
    } on TimeoutException {
      _contentApiDiagnostic = 'CombinedAPI: timed out (30s)';
      debugPrint('Spotify getTokenAndContentPlaylists: timed out');
      return null;
    } catch (e) {
      _contentApiDiagnostic = 'CombinedAPI error: $e';
      debugPrint('Spotify getTokenAndContentPlaylists: failed: $e');
      return null;
    }
  }

  /// Uses the Spotify App Remote Content API (via native platform channel) to fetch
  /// the user's recommended/recent playlists. This bypasses the Web API quota
  /// restriction that causes 403s in Spotify Developer development mode.
  Future<List<SpotifyPlaylist>> _fetchPlaylistsViaContentAPI() async {
    try {
      final rawList = await const MethodChannel('spotify_sdk')
          .invokeMethod<List<dynamic>>('getContentPlaylists')
          .timeout(const Duration(seconds: 10));

      if (rawList == null) {
        _contentApiDiagnostic = 'ContentAPI: null response';
        return [];
      }
      if (rawList.isEmpty) {
        _contentApiDiagnostic = 'ContentAPI: empty list (0 items)';
        return [];
      }

      // Log every URI before filtering so we can see what Spotify returned.
      final allUris = rawList.whereType<Map>().map((m) => (m['uri'] ?? '').toString()).toList();
      debugPrint('Spotify ContentAPI raw URIs (${allUris.length}): $allUris');

      final result = rawList
          .whereType<Map>()
          .map((m) {
            final uri = (m['uri'] ?? '').toString();
            final name = (m['name'] ?? 'Playlist').toString();
            final subtitle = (m['subtitle'] ?? '').toString();
            int trackCount = 0;
            final match = RegExp(r'(\d+)\s+song').firstMatch(subtitle);
            if (match != null) {
              trackCount = int.tryParse(match.group(1) ?? '0') ?? 0;
            }
            return SpotifyPlaylist(
              id: uri,
              name: name,
              uri: uri,
              ownerName: null,
              trackCount: trackCount,
            );
          })
          .where((p) => p.uri.trim().isNotEmpty)
          .toList();

      final filtered = result.length;
      final total = allUris.length;
      // Sample the first URI type to diagnose filter misses.
      final firstUri = allUris.isNotEmpty ? allUris.first : 'none';
      _contentApiDiagnostic = filtered > 0
          ? 'ContentAPI: $filtered/$total items passed filter'
          : 'ContentAPI: 0/$total passed filter — first URI: $firstUri';

      return result;
    } on TimeoutException {
      _contentApiDiagnostic = 'ContentAPI: timed out (App Remote likely disconnected)';
      debugPrint('Spotify Content API timed out');
      return [];
    } catch (e) {
      _contentApiDiagnostic = 'ContentAPI error: $e';
      debugPrint('Spotify Content API fallback failed: $e');
      return [];
    }
  }

  Future<void> playPlaylist(SpotifyPlaylist playlist) async {
    await playPlaylistUri(uri: playlist.uri, playlistName: playlist.name);
  }

  /// Ensures the App Remote is in a clean play-ready state after refreshPlaylists().
  ///
  /// getTokenAndContentPlaylists() establishes OAuth + content-fetch connection
  /// but the player API pipeline may not be fully configured for play commands.
  /// A silent token-based reconnect resets the player session cleanly so that
  /// the first playPlaylistUri() call goes through the fast direct path.
  Future<void> ensureAppRemoteConnected() async {
    if (_accessToken.isEmpty) return;
    debugPrint('Spotify ensureAppRemoteConnected: silent reconnect for play-ready state');
    try {
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUri,
        accessToken: _accessToken,
      ).timeout(const Duration(seconds: 5));
      _isConnected = connected;
      debugPrint('Spotify ensureAppRemoteConnected: connected=$connected');
    } catch (e) {
      debugPrint('Spotify ensureAppRemoteConnected: failed ($e) — will reconnect on first play');
    }
  }

  Future<void> playPlaylistUri({
    required String uri,
    String? playlistName,
  }) async {
    await ensureInitialized();
    _playbackRequested = true;
    _isStartingPlayback = true;
    _lastPlayCommandTime = DateTime.now();
    // Show an early status so the banner has text + spinner while connecting.
    // Individual reconnect tiers overwrite this with more specific messages.
    _lastError = 'Starting ${playlistName ?? 'playlist'}...';
    notifyListeners();
    bool playSucceeded = false;

    try {
      // ── Connected path: direct App Remote play ────────────────────────────────
      // When the App Remote session is live, issue play() directly.
      // If the App Remote has silently disconnected (session expired while music
      // played in background), play() throws a PlatformException — catch it and
      // mark the session dead so the reconnect path uses the silent token approach.
      if (_isConnected) {
        debugPrint('Spotify playPlaylistUri: direct App Remote play');
        try {
          await SpotifySdk.play(spotifyUri: uri).timeout(const Duration(seconds: 8));
          playSucceeded = true;
        } on TimeoutException {
          // Direct play timed out — the playerAPI callback never fired, which means
          // the App Remote connection is dead (the SDK's isConnected flag was stale).
          // getPlayerState() would also hang on a dead connection, so skip it and go
          // straight to the reconnect path.
          _isConnected = false;
        } catch (_) {
          _isConnected = false; // PlatformException: App Remote session is dead
        }
        debugPrint('Spotify playPlaylistUri: direct App Remote → $playSucceeded, connected=$_isConnected');
      }

      // ── Web API fast path (no live App Remote) ────────────────────────────────
      if (!playSucceeded && _accessToken.isNotEmpty) {
        debugPrint('Spotify playPlaylistUri: fast-path Web API play');
        playSucceeded = await _webApiPlay(uri);
        debugPrint('Spotify playPlaylistUri: Web API → $playSucceeded');
      }

      // ── Reconnect path ─────────────────────────────────────────────────────────
      // Reached when no live App Remote session and Web API is unavailable (dev mode).
      if (!playSucceeded) {
        // No explicit disconnect needed — connectToSpotifyRemote(accessToken:) in
        // Swift tears down any stale App Remote session before reconnecting cleanly.
        _isConnected = false;
        await Future.delayed(const Duration(milliseconds: 200));

        // ── Silent reconnect: use stored access token — no Spotify UI ─────────
        // Common case: Spotify is already running in background, token still valid.
        // connectToSpotifyRemote(accessToken:) calls appRemote.connect() directly
        // instead of authorizeAndPlayURI(), so Spotify never comes to the foreground.
        bool connected = false;
        if (_accessToken.isNotEmpty) {
          try {
            debugPrint('Spotify playPlaylistUri: silent reconnect (stored token, no UI)');
            connected = await SpotifySdk.connectToSpotifyRemote(
              clientId: _clientId,
              redirectUrl: _redirectUri,
              accessToken: _accessToken,
            ).timeout(const Duration(seconds: 5));
          } catch (_) {}
          _isConnected = connected;
          debugPrint('Spotify playPlaylistUri: silent reconnect → $connected');
        }

        if (connected) {
          await Future.delayed(const Duration(milliseconds: 300));
          try {
            await SpotifySdk.play(spotifyUri: uri).timeout(const Duration(seconds: 8));
            playSucceeded = true;
          } on TimeoutException {
            // Play timed out after silent reconnect — callback hung, connection may be dead.
            // Skip getPlayerState (would also hang) and let the OAuth path try next.
            debugPrint('Spotify playPlaylistUri: silent reconnect play timed out — falling to OAuth');
          } catch (_) {}
          debugPrint('Spotify playPlaylistUri: silent reconnect play → $playSucceeded');
        }

        // ── OAuth reconnect — two-step: pure auth then explicit play ────────────
        // authorizeAndPlayURI(specificUri) skips the OAuth redirect when Spotify
        // already has a cached authorization for this app, leaving Spotify in the
        // foreground with no way back. An empty URI forces a full OAuth handshake
        // that always redirects, then we issue play() once the App Remote is live.
        if (!playSucceeded) {
          // No explicit disconnect — Swift connectToSpotify(spotifyUri:'') handles
          // session teardown before the new OAuth handshake.
          _isConnected = false;
          await Future.delayed(const Duration(milliseconds: 200));
          connected = false;

          _lastError = 'Opening Spotify to authorize...';
          notifyListeners();

          try {
            debugPrint('Spotify playPlaylistUri: OAuth — empty URI auth then play($uri)');
            // Step 1: pure auth with empty URI — Spotify always redirects back here.
            connected = await SpotifySdk.connectToSpotifyRemote(
              clientId: _clientId,
              redirectUrl: _redirectUri,
              spotifyUri: '', // empty = guaranteed OAuth redirect even when already authorized
            ).timeout(const Duration(seconds: 15));
            _isConnected = connected;
            debugPrint('Spotify playPlaylistUri: OAuth connected=$connected');

            if (connected) {
              // Step 2: App Remote is live — explicitly start the target playlist.
              _lastError = 'Starting playlist...';
              notifyListeners();
              await Future.delayed(const Duration(milliseconds: 300));
              try {
                await SpotifySdk.play(spotifyUri: uri).timeout(const Duration(seconds: 8));
                debugPrint('Spotify playPlaylistUri: OAuth post-auth play sent');
              } catch (playErr) {
                debugPrint('Spotify playPlaylistUri: OAuth post-auth play error: $playErr');
              }
              playSucceeded = true;
            }
          } on PlatformException catch (e) {
            final combined = '${e.code} ${e.message ?? ''}'.toLowerCase();
            if (combined.contains('not installed') ||
                combined.contains('couldnotfind') ||
                combined.contains('spotifynotinstalled')) {
              debugPrint('Spotify playPlaylistUri: Spotify not installed (${e.code})');
            } else {
              // App Remote dropped after redirect — optimistic success, Spotify is warm.
              // Try to reconnect silently and play.
              debugPrint('Spotify playPlaylistUri: App Remote dropped post-OAuth — silent reconnect (${e.code})');
              try {
                final rc = await SpotifySdk.connectToSpotifyRemote(
                  clientId: _clientId, redirectUrl: _redirectUri,
                  accessToken: _accessToken,
                ).timeout(const Duration(seconds: 5));
                if (rc) {
                  _isConnected = true;
                  await SpotifySdk.play(spotifyUri: uri).timeout(const Duration(seconds: 8));
                }
              } catch (_) {}
              playSucceeded = true;
            }
          } on TimeoutException {
            // 15 s timeout — Spotify never redirected. Try a silent reconnect now
            // that Spotify is warm and might accept App Remote connections.
            debugPrint('Spotify playPlaylistUri: OAuth timed out — attempting warm silent reconnect');
            _lastError = 'Reconnecting to Spotify...';
            notifyListeners();
            try {
              final rc = await SpotifySdk.connectToSpotifyRemote(
                clientId: _clientId, redirectUrl: _redirectUri,
                accessToken: _accessToken,
              ).timeout(const Duration(seconds: 5));
              if (rc) {
                _isConnected = true;
                connected = true;
                await SpotifySdk.play(spotifyUri: uri).timeout(const Duration(seconds: 6));
                playSucceeded = true;
                debugPrint('Spotify playPlaylistUri: warm silent reconnect succeeded');
              }
            } catch (_) {}
          } catch (e) {
            debugPrint('Spotify playPlaylistUri: OAuth error: $e');
          }

          // Refresh access token from the newly established OAuth session.
          if (connected) {
            try {
              final freshToken = await SpotifySdk.getAccessToken(
                clientId: _clientId, redirectUrl: _redirectUri, scope: _scope,
              ).timeout(const Duration(seconds: 5));
              _accessToken = freshToken;
              unawaited(_storage.write(key: _accessTokenKey, value: _accessToken));
            } catch (_) {}
          }
        }
      }

      if (playSucceeded) {
        _lastPlayCommandTime = DateTime.now();
        _isPlaying = true;
        _currentPlaylistName = playlistName;
        _lastPlayedUri = uri;
        // Clear any _lastTrackUri captured during the reconnect window (e.g. the
        // wake-track URI from _ensureAppRemoteConnected).  A stale value here
        // would cause resume() tier-2 to replay the wake track instead of the
        // user's playlist song.  pauseForScanning() will re-capture the correct
        // URI from the live player state when the user next pauses.
        _lastTrackUri = null;
        // play(playlistUri) via App Remote switches Spotify's context (loads the
        // playlist, shows the track) but often leaves the player in a paused state
        // while buffering. An explicit resume() kicks audio regardless of whether
        // play() auto-started it — safe no-op when already playing.
        await Future.delayed(const Duration(milliseconds: 800));
        // Guard: skip the deferred resume() if pauseForScanning() already set
        // _isPlaying = false during the 800 ms window (user pressed switch).
        // Firing resume() here would restart music mid-TTS announcement.
        if (_isConnected && _isPlaying) {
          try {
            await SpotifySdk.resume().timeout(const Duration(seconds: 3));
            debugPrint('Spotify playPlaylistUri: post-play resume sent');
          } catch (_) {}
        }
        // Settle for Spotify to start audio before querying state.
        await Future.delayed(const Duration(milliseconds: 700));
        try {
          await refreshPlayerState().timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      if (!playSucceeded) {
        try {
          final opened = await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
          _lastError = opened
              ? 'Opened Spotify for playback. If music did not start automatically, tap Play in Spotify.'
              : 'Spotify did not start playback. Open Spotify, start any song once, then try again.';
        } catch (e) {
          _lastError = 'Unable to launch Spotify: $e';
        }
      } else {
        _lastError = null; // Clear the in-progress status; SnackBar handles the success message.
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
      // Clear the flag before awaiting so any concurrent refreshPlayerState(),
      // lifecycle callback, or user action does not fire SDK commands against
      // the session while it is being torn down.
      _isConnected = false;
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
      // ── Fast path: App Remote skip (live session) ─────────────────────────────
      // skipNext() on the App Remote auto-advances AND auto-plays — no resume() call
      // needed. This is the common case when music is playing.
      if (_isConnected) {
        bool skipSucceeded = false;
        try {
          await SpotifySdk.skipNext().timeout(const Duration(seconds: 5));
          skipSucceeded = true;
        } on TimeoutException {
          debugPrint('MusicPlaybackService: skipNext() — App Remote skipNext timed out, will try Web API');
        } on PlatformException {
          debugPrint('MusicPlaybackService: skipNext() — App Remote skipNext failed, will try Web API');
        }

        if (skipSucceeded) {
          _isPlaying = true;
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 1500));
          try { await refreshPlayerState(); } catch (_) {}
          return;
        }
      }

      // ── Web API path (no live App Remote, or App Remote skip failed) ──────────
      // POST /me/player/next advances the track when this device is the active device.
      if (_accessToken.isNotEmpty) {
        final skipped = await _webApiSkipNext();
        debugPrint('MusicPlaybackService: skipNext() — Web API: $skipped');
        if (skipped) {
          _isPlaying = true;
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 1500));
          try { await refreshPlayerState(); } catch (_) {}
          return;
        }
      }

      // ── Reconnect path: connect App Remote fresh, then skip ───────────────────
      final connected = await _ensureAppRemoteConnected();
      _isConnected = connected;
      if (connected) {
        try {
          await SpotifySdk.skipNext().timeout(const Duration(seconds: 5));
        } on TimeoutException {
          debugPrint('MusicPlaybackService: skipNext() — reconnect App Remote skipNext timed out');
        }

        // Verify the skip auto-started playback.
        // _ensureAppRemoteConnected() disconnects/reconnects, which pauses Spotify.
        // skipNext() advances the track but the freshly reconnected session may
        // leave the player paused — issue an explicit resume() to cover that case.
        bool isNowPlaying = false;
        try {
          final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 3));
          isNowPlaying = state != null && !state.isPaused;
        } catch (_) {
          isNowPlaying = true; // assume success on state read failure
        }

        if (!isNowPlaying) {
          debugPrint('MusicPlaybackService: skipNext() — track paused after reconnect, sending resume()');
          try {
            await SpotifySdk.resume().timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint('MusicPlaybackService: skipNext() — post-reconnect resume failed: $e');
          }
        }

        _isPlaying = true;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 1500));
        try { await refreshPlayerState(); } catch (_) {}
      } else {
        throw Exception('Skip failed: App Remote reconnect failed.');
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
    // 1 s timeout: if App Remote is responsive the state arrives in < 200 ms;
    // if the queue is stuck we skip track capture and fall through to pause anyway.
    try {
      final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 1));
      _lastTrackUri = state?.track?.uri;
      _lastPlaybackPosition = state?.playbackPosition;
      debugPrint('MusicPlaybackService: pauseForScanning() — captured track URI: $_lastTrackUri, position: ${_lastPlaybackPosition}ms');
    } catch (_) {
      debugPrint('MusicPlaybackService: pauseForScanning() — could not capture track state');
    }

    _isPlaying = false;
    notifyListeners();

    // Primary: Web API pause — HTTP is always clean (no write-queue stall risk).
    // A healthy Web API call completes in < 500 ms, well within the 700 ms gap
    // before TTS begins in _handleSpacebarPress, so scanning announcements start
    // after the music has actually stopped.
    if (_accessToken.isNotEmpty) {
      try {
        final ok = await _webApiPause();
        debugPrint('MusicPlaybackService: pauseForScanning() — Web API pause result: $ok');
        if (ok) return;
      } catch (e) {
        debugPrint('MusicPlaybackService: pauseForScanning() — Web API pause exception: $e');
      }
    }

    // Fallback: App Remote pause — used when Web API token is absent or call fails.
    // 3 s timeout: a healthy App Remote responds in < 500 ms; if the write queue
    // is stuck the callback never arrives anyway so we fail fast.
    if (_isConnected) {
      try {
        await SpotifySdk.pause().timeout(const Duration(seconds: 3));
        debugPrint('MusicPlaybackService: pauseForScanning() — App Remote pause succeeded');
      } catch (e) {
        debugPrint('MusicPlaybackService: pauseForScanning() — App Remote pause failed: $e');
      }
    }
  }

  Future<void> pause() async {
    _lastError = null;
    _lastPlayCommandTime = null;

    // Capture current track URI and position before pausing so that resume()
    // tier 1 can call SpotifySdk.resume() on the right context rather than
    // falling through to tier 3, which restarts the playlist from the beginning.
    try {
      final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 2));
      _lastTrackUri = state?.track?.uri;
      _lastPlaybackPosition = state?.playbackPosition;
      debugPrint('MusicPlaybackService: pause() — captured track URI: $_lastTrackUri, position: ${_lastPlaybackPosition}ms');
    } catch (_) {
      debugPrint('MusicPlaybackService: pause() — could not capture track state');
    }

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
    // Guard against concurrent resume() calls — only one reconnect chain at a time.
    if (_isStartingPlayback) {
      debugPrint('MusicPlaybackService: resume() — already in progress, ignoring duplicate call');
      return;
    }
    _isStartingPlayback = true;
    _playbackRequested = true;
    _lastPlayCommandTime = DateTime.now();
    _lastError = null;
    debugPrint('MusicPlaybackService: resume() — isConnected=$_isConnected, lastTrackUri=$_lastTrackUri, lastPlayedUri=$_lastPlayedUri');
    try {
      // Tier 0: Web API resume — no App Remote needed, works whenever Spotify is
      // still the active device on this phone (the common case after Web API play).
      if (_accessToken.isNotEmpty) {
        final resumed = await _webApiResume();
        debugPrint('MusicPlaybackService: resume() — Web API resume: $resumed');
        if (resumed) {
          _isPlaying = true;
          _lastError = null;
          notifyListeners();
          return;
        }
      }

      // Tier 1: Session is live — SpotifySdk.resume() restores the exact track and
      // position because pause() was called on this same session. No reconnect
      // happened, so the App Remote context is exactly where we paused.
      // _lastTrackUri is not needed here — resume() resumes Spotify's current paused
      // context regardless of which track it is. Only fall through if the callback
      // times out (connection silently dropped).
      if (_isConnected) {
        try {
          debugPrint('MusicPlaybackService: resume() — tier 1: SpotifySdk.resume()');
          bool resumeStarted = false;
          try {
            await SpotifySdk.resume().timeout(const Duration(seconds: 5));
            resumeStarted = true;
          } on TimeoutException {
            // Callback timed out — check whether Spotify is actually playing already.
            try {
              final state = await SpotifySdk.getPlayerState().timeout(const Duration(seconds: 2));
              if (state != null && !state.isPaused) {
                debugPrint('MusicPlaybackService: resume() — tier 1 timed out but Spotify is playing — accepting');
                resumeStarted = true;
              } else {
                // Spotify is still paused — session write queue may be stuck.
                _lastError = 'Reconnecting to Spotify...';
                notifyListeners();
              }
            } catch (_) {
              _lastError = 'Reconnecting to Spotify...';
              notifyListeners();
            }
          }
          if (resumeStarted) {
            _isPlaying = true;
            _lastError = null;
            notifyListeners();
            return;
          }
          debugPrint('MusicPlaybackService: resume() — tier 1 did not start, trying reconnect');
        } catch (e) {
          debugPrint('MusicPlaybackService: resume() — tier 1 failed: $e, trying reconnect');
          _lastError = 'Reconnecting to Spotify...';
          notifyListeners();
        }
      } else {
        _lastError = 'Reconnecting to Spotify...';
        notifyListeners();
      }

      // Tier 2: Connection dropped — reconnect without a URI so we attach to
      // Spotify's current app state, then play the correct track.
      debugPrint('MusicPlaybackService: resume() — tier 2: reconnect then play');
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
              } else {
                _lastError = 'Still reconnecting — please wait...';
                notifyListeners();
              }
            } catch (_) {}
          }
          if (playStarted) {
            _isPlaying = true;
            _lastError = null;
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('MusicPlaybackService: resume() — tier 2 failed: $e');
        }
        debugPrint('MusicPlaybackService: resume() — tier 2 falling through to tier 3');
      }

      // Tier 3: Direct connect with the target URI — most reliable path when the
      // App Remote write queue is stuck. Opens Spotify briefly then returns.
      final resumeUri = _lastTrackUri ?? _lastPlayedUri;
      if (resumeUri == null) {
        _lastError = 'Could not resume — no track URI stored. Please select the playlist again.';
        notifyListeners();
        return;
      }

      _lastError = 'Reconnecting to Spotify — this may take a moment...';
      notifyListeners();

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
            _lastError = null;
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
        // playPlaylistUri manages _isStartingPlayback internally (sets false in its
        // finally block). Re-acquire the guard so resume()'s own finally clears it
        // and a concurrent resume() call cannot sneak in between the two finallys.
        await playPlaylistUri(uri: resumeUri, playlistName: _currentPlaylistName);
        _isStartingPlayback = true;
      }
    } on PlatformException catch (e) {
      _lastError = 'Spotify connection interrupted — please try again.';
      debugPrint('MusicPlaybackService: resume() — PlatformException: ${e.message}');
    } catch (e) {
      // Replace raw exceptions (TimeoutException, etc.) with a friendly message.
      _lastError = 'Spotify is taking longer than expected — please try again.';
      debugPrint('MusicPlaybackService: resume() — Exception: $e');
    } finally {
      _isStartingPlayback = false;
      notifyListeners();
    }
  }

  Future<void> stopPlayback() async {
    _playbackRequested = false;
    _lastPlayCommandTime = null;
    if (_isStartingPlayback) {
      // Abort in-progress playback start without issuing SDK commands that
      // would conflict with the active connection/play sequence.
      _isPlaying = false;
      notifyListeners();
      return;
    }
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
      ).timeout(const Duration(seconds: 8));

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
      ).timeout(const Duration(seconds: 8));
      debugPrint('MusicPlaybackService: _webApiPause() — HTTP status=${response.statusCode}');
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      debugPrint('MusicPlaybackService: _webApiPause() — exception: $e');
      return false;
    }
  }

  Future<bool> _webApiResume() async {
    if (_accessToken.isEmpty) return false;
    try {
      // PUT /me/player/play with no body resumes from the current paused position.
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
      debugPrint('MusicPlaybackService: _webApiResume() — HTTP ${response.statusCode}');
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      debugPrint('MusicPlaybackService: _webApiResume() — exception: $e');
      return false;
    }
  }

  Future<bool> _webApiPlay(String contextUri) async {
    if (_accessToken.isEmpty) return false;
    try {
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play'),
        headers: <String, String>{
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(<String, dynamic>{'context_uri': contextUri}),
      ).timeout(const Duration(seconds: 8));
      debugPrint('MusicPlaybackService: _webApiPlay() — HTTP ${response.statusCode}');
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      debugPrint('MusicPlaybackService: _webApiPlay() — exception: $e');
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
