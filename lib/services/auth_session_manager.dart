import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'user_settings_provider.dart';

class AuthSessionManager {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String?>? _activeRecovery;
  static bool _redirectInProgress = false;
  static bool _statusVisible = false;
  static bool _lastRecoveryRequiresLogin = false;

  static void recordAuthenticatedSession(String token) {
    _redirectInProgress = false;
    _lastRecoveryRequiresLogin = false;
    _hideRecoveryStatus();
    _updateProviderToken(token);
  }

  static bool get lastRecoveryRequiresLogin => _lastRecoveryRequiresLogin;

  static void clearAuthenticatedSession() {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      settingsProvider.idToken = null;
      settingsProvider.safeNotifyListeners();
    } catch (error) {
      debugPrint('[AuthRecovery] Failed to clear provider state: $error');
    }
  }

  static Future<String?> recoverSession({
    String reason = 'unknown',
    bool navigateToLoginOnFailure = false,
    bool showStatusMessages = true,
    bool showFailureMessages = true,
  }) async {
    final existingRecovery = _activeRecovery;
    if (existingRecovery != null) {
      return existingRecovery;
    }

    final recovery = _recoverSessionInternal(
      reason: reason,
      navigateToLoginOnFailure: navigateToLoginOnFailure,
      showStatusMessages: showStatusMessages,
      showFailureMessages: showFailureMessages,
    );
    _activeRecovery = recovery;

    try {
      return await recovery;
    } finally {
      if (identical(_activeRecovery, recovery)) {
        _activeRecovery = null;
      }
    }
  }

  static Future<void> redirectToLogin({
    String reason = 'session_expired',
  }) async {
    if (_redirectInProgress) {
      return;
    }

    _redirectInProgress = true;
    _hideRecoveryStatus();
    clearAuthenticatedSession();
    debugPrint('[AuthRecovery] Redirecting to login: $reason');

    try {
      await FirebaseAuth.instance.signOut();
    } catch (error) {
      debugPrint('[AuthRecovery] Sign-out during redirect failed: $error');
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('[AuthRecovery] Navigator unavailable for redirect');
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator.pushNamedAndRemoveUntil('/auth', (route) => false);
    });
  }

  static Future<String?> _recoverSessionInternal({
    required String reason,
    required bool navigateToLoginOnFailure,
    required bool showStatusMessages,
    required bool showFailureMessages,
  }) async {
    debugPrint('[AuthRecovery] Starting silent recovery: $reason');
    _lastRecoveryRequiresLogin = false;
    if (showStatusMessages) {
      _showRecoveryStatus('Session expired. Logging back in...');
    }

    final savedEmail = await _storage.read(key: 'saved_email');
    final savedPassword = await _storage.read(key: 'saved_password');

    if (savedEmail == null ||
        savedPassword == null ||
        savedEmail.trim().isEmpty ||
        savedPassword.trim().isEmpty) {
      debugPrint('[AuthRecovery] No saved credentials available');
      _lastRecoveryRequiresLogin = true;
      if (navigateToLoginOnFailure) {
        await redirectToLogin(reason: 'missing_saved_credentials');
      } else if (showStatusMessages && showFailureMessages) {
        _showRecoveryStatus('Session expired. Please log in again.');
      }
      return null;
    }

    try {
      final token = await _attemptSilentLogin(
        savedEmail: savedEmail,
        savedPassword: savedPassword,
      );

      debugPrint('[AuthRecovery] Silent recovery succeeded');
      if (showStatusMessages) {
        _showRecoveryStatus('Login restored. Continuing...');
        Future.delayed(const Duration(seconds: 2), _hideRecoveryStatus);
      }
      recordAuthenticatedSession(token);
      return token;
    } catch (error) {
      debugPrint('[AuthRecovery] Silent recovery failed: $error');
      final requiresLogin = _isCredentialFailure(error);
      _lastRecoveryRequiresLogin = requiresLogin;

      if (requiresLogin) {
        if (showStatusMessages && showFailureMessages) {
          _showRecoveryStatus('Saved login expired. Please log in again.');
        }
      } else {
        for (int retry = 0; retry < 2; retry++) {
          try {
            debugPrint('[AuthRecovery] Retrying silent recovery (attempt ${retry + 1})');
            final token = await _attemptSilentLogin(
              savedEmail: savedEmail,
              savedPassword: savedPassword,
            );

            recordAuthenticatedSession(token);
            return token;
          } catch (retryError) {
            if (_isCredentialFailure(retryError)) {
              _lastRecoveryRequiresLogin = true;
              if (navigateToLoginOnFailure) {
                await redirectToLogin(reason: 'silent_reauth_failed');
              }
              if (showStatusMessages && showFailureMessages) {
                _showRecoveryStatus('Saved login expired. Please log in again.');
              }
              return null;
            }
            debugPrint('[AuthRecovery] Retry attempt ${retry + 1} failed: $retryError');
          }
        }

        if (showStatusMessages && showFailureMessages) {
          _showRecoveryStatus('Unable to restore login right now. Please try again.');
          Future.delayed(const Duration(seconds: 4), _hideRecoveryStatus);
        } else if (showStatusMessages) {
          Future.delayed(const Duration(seconds: 1), _hideRecoveryStatus);
        }
      }

      if (navigateToLoginOnFailure && requiresLogin) {
        await redirectToLogin(reason: 'silent_reauth_failed');
      }
      return null;
    }
  }

  static Future<String> _attemptSilentLogin({
    required String savedEmail,
    required String savedPassword,
  }) async {
    UserCredential? credential;
    Object? lastError;

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        debugPrint('[AuthRecovery] Silent login attempt $attempt/3');
        credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: savedEmail.trim(),
          password: savedPassword.trim(),
        );
        break;
      } catch (error) {
        lastError = error;
        debugPrint('[AuthRecovery] Silent login attempt $attempt failed: $error');

        if (_isCredentialFailure(error)) {
          rethrow;
        }

        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    if (credential == null) {
      throw lastError ?? Exception('Silent login failed');
    }

    final user = credential.user;
    final token = await user?.getIdToken(true);

    if (token == null || token.isEmpty) {
      throw Exception('Silent login completed without an ID token');
    }

    return token;
  }

  static bool _isCredentialFailure(Object error) {
    if (error is! FirebaseAuthException) {
      return false;
    }

    return error.code == 'invalid-credential' ||
        error.code == 'invalid-login-credentials' ||
        error.code == 'user-not-found' ||
        error.code == 'wrong-password' ||
        error.code == 'invalid-email' ||
        error.code == 'user-disabled';
  }

  static void _showRecoveryStatus(String message) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) {
      debugPrint('[AuthRecovery] ScaffoldMessenger unavailable for status: $message');
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(minutes: 5),
      ),
    );
    _statusVisible = true;
  }

  static void _hideRecoveryStatus() {
    if (!_statusVisible) {
      return;
    }

    final messenger = scaffoldMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    _statusVisible = false;
  }

  static void _updateProviderToken(String token) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    try {
      final settingsProvider = Provider.of<UserSettingsProvider>(
        context,
        listen: false,
      );
      settingsProvider.idToken = token;
      settingsProvider.safeNotifyListeners();
    } catch (error) {
      debugPrint('[AuthRecovery] Failed to update provider token: $error');
    }
  }
}