import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Centralized authenticated HTTP client that follows Firebase best practices.
/// Calls getIdToken() right before each request to let Firebase handle refresh automatically.
/// Falls back to cached token if Firebase refresh fails (e.g., on restrictive networks).
class AuthenticatedHttpClient {
  static const int _defaultMaxRetries = 3;
  static const int _defaultTimeoutSeconds = 20;
  
  // Fallback token cache for when Firebase refresh fails (network issues, etc.)
  static String? _lastValidToken;

  /// Get a fresh Firebase ID token, with fallback to cached token if refresh fails.
  /// Firebase automatically handles refresh: if the token is valid, returns it instantly.
  /// If expired or expiring soon (within 5 mins), Firebase auto-refreshes using refresh token.
  /// If refresh fails (firebase_auth/internal-error), falls back to cached token.
  static Future<String?> getRefreshedIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      // Call getIdToken() right before using it - Firebase handles refresh automatically
      final token = await user.getIdToken();
      if (token != null && token.isNotEmpty) {
        _lastValidToken = token; // Cache this token as fallback
        return token;
      }
    } catch (e) {
      debugPrintFallback('Token refresh failed: $e, using cached token as fallback');
    }
    
    // Fallback: return cached token if refresh failed
    if (_lastValidToken != null && _lastValidToken!.isNotEmpty) {
      debugPrintFallback('Using cached token (Firebase refresh failed)');
      return _lastValidToken;
    }
    
    return null;
  }

  /// Make an authenticated HTTP request with automatic token handling.
  /// Calls getIdToken() right before the request to ensure fresh token.
  static Future<http.Response> makeAuthenticatedRequest(
    String method,
    String url, {
    Map<String, String> baseHeaders = const {},
    String? body,
    int maxRetries = _defaultMaxRetries,
    int timeoutSeconds = _defaultTimeoutSeconds,
  }) async {
    int attemptCount = 0;

    while (attemptCount <= maxRetries) {
      try {
        // Get fresh token right before request - Firebase handles refresh automatically
        final idToken = await getRefreshedIdToken();
        if (idToken == null) {
          throw Exception('Authentication required');
        }

        final headers = {
          ...baseHeaders,
          'Authorization': 'Bearer $idToken',
        };

        final uri = Uri.parse(url);
        final request = http.Request(method, uri)
          ..headers.addAll(headers);

        if (body != null) {
          request.body = body;
        }

        final response = await request.send().timeout(
          Duration(seconds: timeoutSeconds),
        );

        return http.Response(
          await response.stream.bytesToString(),
          response.statusCode,
          headers: response.headers,
        );
      } catch (e) {
        attemptCount++;

        if (attemptCount > maxRetries) {
          rethrow;
        }

        await Future.delayed(Duration(milliseconds: 200 * attemptCount));
      }
    }

    throw Exception('Request failed after $maxRetries retries');
  }

  static void debugPrintFallback(String message) {
    // ignore: avoid_print
    print('[Auth] $message');
  }
}
