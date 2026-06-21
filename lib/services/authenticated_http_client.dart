import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'auth_session_manager.dart';

/// Centralized authenticated HTTP client that follows Firebase best practices.
/// Calls getIdToken() right before each request to let Firebase handle refresh automatically.
/// Falls back to cached token if Firebase refresh fails (e.g., on restrictive networks).
class AuthenticatedHttpClient {
  static const int _defaultMaxRetries = 3;
  static const int _defaultTimeoutSeconds = 20;

  static String _rememberValidToken(String token) {
    AuthSessionManager.recordAuthenticatedSession(token);
    return token;
  }

  /// Get a fresh Firebase ID token, with fallback to cached token if refresh fails.
  /// Firebase automatically handles refresh: if the token is valid, returns it instantly.
  /// If expired or expiring soon (within 5 mins), Firebase auto-refreshes using refresh token.
  /// If refresh fails, attempt a silent re-login using saved credentials.
  static Future<String?> getRefreshedIdToken() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final token = await user
            .getIdToken()
            .timeout(const Duration(seconds: 6));
        if (token != null && token.isNotEmpty) {
          return _rememberValidToken(token);
        }
      } catch (e) {
        debugPrintFallback('Token refresh failed: $e');
      }

      try {
        final forcedToken = await user
            .getIdToken(true)
            .timeout(const Duration(seconds: 6));
        if (forcedToken != null && forcedToken.isNotEmpty) {
          return _rememberValidToken(forcedToken);
        }
      } catch (e) {
        debugPrintFallback('Forced token refresh failed: $e');
      }
    }

    try {
      final recoveredToken = await AuthSessionManager.recoverSession(
        reason: user == null ? 'no_current_user' : 'token_refresh_failed',
        navigateToLoginOnFailure: false,
        showStatusMessages: true,
        showFailureMessages: false,
      );
      if (recoveredToken != null && recoveredToken.isNotEmpty) {
        return _rememberValidToken(recoveredToken);
      }
    } catch (e) {
      debugPrintFallback('Silent session recovery failed: $e');
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
    bool attemptedRecoveryAfterUnauthorized = false;

    while (attemptCount <= maxRetries) {
      try {
        // Get fresh token right before request - Firebase handles refresh automatically
        final idToken = await getRefreshedIdToken();
        if (idToken == null) {
          if (AuthSessionManager.lastRecoveryRequiresLogin) {
            await AuthSessionManager.redirectToLogin(reason: 'missing_id_token');
            throw Exception('Authentication required');
          }

          throw Exception('Authentication temporarily unavailable');
        }

        final headers = {
          if (body != null) 'Content-Type': 'application/json',
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

        final httpResponse = http.Response(
          await response.stream.bytesToString(),
          response.statusCode,
          headers: response.headers,
        );

        if (httpResponse.statusCode == 401 &&
            !attemptedRecoveryAfterUnauthorized) {
          attemptedRecoveryAfterUnauthorized = true;
          final recoveredToken = await AuthSessionManager.recoverSession(
            reason: 'http_401',
            navigateToLoginOnFailure: false,
            showStatusMessages: true,
            showFailureMessages: false,
          );
          if (recoveredToken != null && recoveredToken.isNotEmpty) {
            continue;
          }

          if (AuthSessionManager.lastRecoveryRequiresLogin) {
            await AuthSessionManager.redirectToLogin(reason: 'http_401');
          }
        }

        return httpResponse;
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
