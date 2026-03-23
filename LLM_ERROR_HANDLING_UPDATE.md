# LLM Error Handling Update

## Summary
Updated `_getLLMResponse` in `lib/main.dart` to provide better feedback and recovery when an LLM error occurs (e.g., network error, invalid JSON, or non-200 status code).

## Changes
1.  **Audio Announcement**: Added `await _speakPersonalVoice("AI Error has occurred");` to both the HTTP error block (`else`) and the exception block (`catch`).
2.  **Resume Scanning**: Added logic to clear scanning flags (`_suppressScanning`, `_waitingForUserInput`, `_isScanningPaused`) and call `_maybeStartScanning()` to ensure the user is not left in a stuck state.

## Files Modified
- `lib/main.dart`

## Verification
- Trigger an LLM error (e.g., by disconnecting network or mocking a bad response).
- Verify that "AI Error has occurred" is spoken.
- Verify that scanning resumes automatically.
