# Firebase ID Token Expiration Fix

## Problem
Firebase ID tokens expire after **1 hour**. When a token expires, the backend returns a `401 Unauthorized` error with the message "Invalid Firebase ID token received." This causes API requests to fail silently, showing pages with no options.

### Error Log Example
```
WARNING:root:Invalid Firebase ID token received.
```

## Root Cause
The Flutter app was storing an old Firebase ID token in `UserSettingsProvider.idToken` and reusing it for multiple API calls over time. After 1 hour, the token would expire, but the app would continue using the stale token, causing all subsequent API requests to fail.

## Solution

### 1. New Helper Functions (in `main.dart`)
- **`getRefreshedIdToken()`**: Refreshes the Firebase token before use
  - Calls `user.getIdToken(true)` to force refresh
  - Falls back to cached token if refresh fails
  - Throws exception if no token available
  
- **`makeAuthenticatedRequest()`**: Enhanced HTTP request maker
  - Automatically refreshes token before every request
  - Supports GET, POST, PUT, DELETE methods
  - Handles 401 responses with retry logic
  - Includes timeout and retry handling

### 2. Updated Components
**`UserSettingsProvider` (lib/services/user_settings_provider.dart)**
- Removed dependency on stale `idToken` field
- Updated methods now use `makeAuthenticatedRequest()`:
  - `fetchInterfacePreference()` - GET request
  - `fetchSettings()` - GET request  
  - `saveSettings()` - POST request
  - `fetchTtsVoices()` - GET request

### 3. How It Works

```
API Call Flow:
1. App needs to make API request
2. Call makeAuthenticatedRequest('GET', url, ...)
3. Inside makeAuthenticatedRequest:
   a. Call getRefreshedIdToken() → Firebase.Auth.getIdToken(true)
   b. Firebase returns fresh token (< 1 minute old)
   c. Add Authorization header: Bearer <fresh_token>
   d. Make HTTP request
4. If request returns 401:
   a. Retry with newly refreshed token (auto-refresh on each retry)
   b. Max retries: configurable (default 2)
5. Return response to caller
```

### 4. Key Improvements

| Aspect | Before | After |
|--------|--------|-------|
| Token Management | Stored stale token for 1+ hour | Refreshed before every request |
| 401 Handling | Failed immediately | Retried with fresh token |
| Code Pattern | Manual token refresh in each page | Centralized in `makeAuthenticatedRequest()` |
| Consistency | Different approaches in different pages | Unified approach across all API calls |

## Implementation Details

### getRefreshedIdToken()
```dart
Future<String> getRefreshedIdToken() async {
  // 1. Try to force refresh
  final user = FirebaseAuth.instance.currentUser;
  final refreshedToken = await user.getIdToken(true);
  
  // 2. If refresh works, return fresh token
  if (refreshedToken != null && refreshedToken.isNotEmpty) {
    return refreshedToken;
  }
  
  // 3. Fallback: use cached token
  final cachedToken = await user.getIdToken(false);
  if (cachedToken != null && cachedToken.isNotEmpty) {
    return cachedToken;
  }
  
  // 4. No token available
  throw Exception('Failed to obtain Firebase ID token');
}
```

### makeAuthenticatedRequest()
```dart
Future<http.Response> makeAuthenticatedRequest(
  String method,
  String url, {
  Map<String, String>? baseHeaders,
  String? body,
  int maxRetries = 2,
  int timeoutSeconds = 10,
}) async {
  // 1. Refresh token before request
  String idToken = await getRefreshedIdToken();
  
  // 2. Merge headers with authorization
  final headers = {...?baseHeaders};
  headers['Authorization'] = 'Bearer $idToken';
  
  // 3. Make HTTP request (GET, POST, PUT, DELETE)
  http.Response response = ...
  
  // 4. Handle 401 with retry
  if (response.statusCode == 401) {
    if (attempt < maxRetries) {
      continue; // Retry with fresh token
    }
  }
  
  return response;
}
```

## Migration Notes

### What Changed
- UserSettingsProvider no longer uses the `idToken` parameter
- All API calls now use `makeAuthenticatedRequest()` instead of `cruiseShipSafeGet()` for authenticated endpoints
- Token is automatically refreshed on each API call

### What Stayed the Same
- `cruiseShipSafeGet()` still available for unauthenticated requests
- UserSettingsProvider public interface unchanged
- Callers don't need to specify Authorization header manually

### Pages Already Using Token Refresh
The following pages already had manual token refresh logic (from earlier debugging):
- `main.dart` - announceViaBackend()
- `freestyle_page.dart`
- `tap_interface_page.dart`
- `favorites_page.dart`

These manual refreshes are still compatible with the new system, but are now optional since makeAuthenticatedRequest() handles token refresh for UserSettingsProvider calls.

## Testing

### To Verify the Fix Works

1. **Start the app** and authenticate normally
2. **Wait 1+ hour** OR manually invalidate token:
   - Log out and back in to reset 1-hour timer
   - Or test with an expired token (advanced)
3. **Make a request** that requires API call (load settings, save settings, change TTS voice, etc.)
4. **Check logs** for:
   - `🔐 Firebase ID token refreshed (length: ...)` - Token was refreshed
   - No `Invalid Firebase ID token received.` errors
   - Page displays with working options

### Debug Output
The fix logs token refresh operations with `🔐` emoji:
```
🔐 Making authenticated GET request to https://api.example.com/api/settings
🔐 Firebase ID token refreshed (length: 3456)
🔐 RESPONSE: Status 200
🔐 ✅ Success!
```

## Remaining Work

Future enhancements could include:
1. Global token refresh scheduling (refresh every 50 minutes rather than on-demand)
2. Add token expiration time to debug logs
3. Add token refresh telemetry to understand refresh frequency
4. Centralized 401 error handler to redirect to login if user truly unauthenticated
5. Token caching strategy to avoid multiple refreshes within same request cycle

## Related Files
- `lib/main.dart` - New helper functions
- `lib/services/user_settings_provider.dart` - Updated to use makeAuthenticatedRequest()
- `existingbackend/server.py` - Token verification (unchanged, still works correctly)
- `server.py` - Token verification (unchanged, still works correctly)
