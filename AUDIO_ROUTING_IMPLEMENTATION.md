# Audio Routing Implementation

This document describes how the Bravo app routes audio to two distinct output destinations:

- **Personal speaker** — the user's private audio device (Bluetooth headphones, AirPods, wired headphones, or the device's built-in speaker when nothing else is connected).
- **System speaker** — the device's built-in speaker, used for announcements that are meant to be heard by the room (button selections, LLM responses, wake-word confirmations).

---

## Table of Contents

1. [Concept Overview](#1-concept-overview)
2. [Flutter MethodChannel Bridge](#2-flutter-methodchannel-bridge)
3. [iOS Native Implementation](#3-ios-native-implementation)
4. [Android Native Implementation](#4-android-native-implementation)
5. [Web Implementation](#5-web-implementation)
6. [Flutter-Side Routing Logic](#6-flutter-side-routing-logic)
7. [Volume Control](#7-volume-control)
8. [Audio Session Initialization](#8-audio-session-initialization)
9. [Bluetooth & Headphone Reconnection Handling](#9-bluetooth--headphone-reconnection-handling)
10. [File Reference Summary](#10-file-reference-summary)

---

## 1. Concept Overview

Every piece of audio played by the app falls into one of two categories:

| Category | Routing Target | Typical Use Cases |
|---|---|---|
| `personal` | Bluetooth headphones / default personal device | Auditory scanning cues, TTS spoken to the AAC user only |
| `system` | Built-in device speaker | Button-press announcements, LLM responses, wake-word confirmations |

The **routing target** is an explicit string parameter (`'system'` or `'personal'`) passed deep through the call stack so every audio event is intentionally labeled. The actual hardware switching happens in platform-native code (Swift on iOS, Kotlin on Android) or via the Web Audio API's `setSinkId` on web.

---

## 2. Flutter MethodChannel Bridge

All native audio routing calls go through a single `MethodChannel` named `audio_routing`, declared in `lib/main.dart`:

```dart
const platform = MethodChannel('audio_routing');
```

### Methods Exposed

| Method | Direction | Description |
|---|---|---|
| `forceSpeaker` | Flutter → Native | Override current audio route to the built-in speaker. Used before any `system` announcement. |
| `routeToPersonal` | Flutter → Native (iOS) | Remove any speaker override so audio flows to Bluetooth/headphones. |
| `resetToDefault` | Flutter → Native | Restore normal audio routing (removes `forceSpeaker`). Used after system announcements on Android. Also called before personal (scanning) speech. |
| `setupOptimalAudioSession` | Flutter → Native (iOS) | Configure the iOS `AVAudioSession` for both built-in and Bluetooth A2DP output without selecting a specific destination. Used once at startup. |
| `initializeAudioWithVolume` | Flutter → Native (Android) | Initialize the Android audio subsystem with the user's saved volume levels before the first announcement. |
| `setApplicationVolume` | Flutter → Native (Android) | Set hardware stream volumes to a specific 0–10 level. |
| `captureCurrentVolume` | Flutter → Native | Read the current hardware volume and normalize it to the 0–10 scale used by the app. |
| `suppressNotificationSounds` | Flutter → Native (Android) | Mute the `STREAM_NOTIFICATION` channel during auditory scanning to prevent distracting chirps. |
| `restoreNotificationSounds` | Flutter → Native (Android) | Restore notification volume after scanning ends. |

---

## 3. iOS Native Implementation

**File:** `ios/Runner/AppDelegate.swift`

The iOS side uses `AVAudioSession` to control routing.

### Channel Registration

The `audio_routing` `FlutterMethodChannel` is registered in `application(_:didFinishLaunchingWithOptions:)` and all method calls are dispatched through a `switch` statement.

### Key Methods

#### `setupOptimalAudioSession()`
Called once at app startup (via `_initializeAudioSession` in Dart). Configures the session with:
```swift
try audioSession.setCategory(
    .playAndRecord,
    mode: .default,
    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
)
```
No output port override is applied, so the system routes to the best available output (Bluetooth A2DP if connected, built-in speaker otherwise).

#### `forceSpeaker()`
Used before every system announcement. Forces the built-in speaker regardless of any connected Bluetooth device:
```swift
try audioSession.overrideOutputAudioPort(.speaker)
```

#### `routeToPersonal()`
Called before personal (scanning) audio. Removes any speaker override so Bluetooth is preferred:
```swift
try audioSession.overrideOutputAudioPort(.none)
```

#### `resetToDefault()`
Removes the speaker override. Unlike earlier versions, it intentionally **does not** deactivate the session, ensuring an active Bluetooth connection is preserved.

#### Audio Route Change Observer

The app registers for `AVAudioSession.routeChangeNotification`. When a Bluetooth device connects or disconnects, `reestablishAudioSession()` is called to re-apply the `.playAndRecord` category with Bluetooth A2DP options and remove any speaker override. This keeps volume levels applied via software (`player.setVolume`) intact across hardware route changes.

---

## 4. Android Native Implementation

**File:** `android/app/src/main/kotlin/com/bravoaac/bravo/MainActivity.kt`

Android uses `AudioManager` for routing and stream-volume control.

### `forceSpeaker()`

This function is the core of Android speaker routing. It:

1. Saves the current `AudioManager.mode` and speakerphone state.
2. Requests audio focus (`AUDIOFOCUS_GAIN`).
3. Switches `audioManager.mode` to `MODE_IN_COMMUNICATION` and enables `isSpeakerphoneOn = true`.
4. Explicitly disables `isBluetoothScoOn`.
5. On Android 12+ (`Build.VERSION_CODES.S`), calls `audioManager.setCommunicationDevice()` targeting the `TYPE_BUILTIN_SPEAKER` audio device.
6. Applies the saved personal volume level (0–10 scale) to all relevant audio streams.
7. Sleeps 500 ms to allow the route to stabilize before audio begins playing.

### `restoreAudio()`

Called by `resetToDefault`. It:

1. Abandons the audio focus request.
2. Clears the communication device (Android 12+).
3. Restores stream volumes using the user's **saved** personal/system levels (not raw hardware levels).
4. Resets `audioManager.mode` to `MODE_NORMAL` and turns off the speakerphone.

### Volume Application Detail

Android has multiple audio streams (`STREAM_MUSIC`, `STREAM_VOICE_CALL`, `STREAM_SYSTEM`, etc.). Because `MODE_IN_COMMUNICATION` routes playback through `STREAM_VOICE_CALL`, the app explicitly sets all streams to the target level when forcing or restoring audio.

Two stored values drive this:
- `storedPersonalVolume` — the app's current runtime volume level.
- `savedPersonalVolume` / `savedSystemVolume` — the user's official saved levels (from admin settings). When `restoreAudio()` runs, it uses these saved values so the device doesn't revert to an unexpected hardware volume.

### Headphone & Bluetooth BroadcastReceiver

`setupHeadphoneDetection()` registers a `BroadcastReceiver` for:
- `AudioManager.ACTION_AUDIO_BECOMING_NOISY` — headphones unplugged.
- `AudioManager.ACTION_HEADSET_PLUG` — wired headset plug/unplug.
- `BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED` — Bluetooth device connect/disconnect.
- `BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED` — Bluetooth A2DP profile connect.

When a wired or Bluetooth device reconnects, the receiver restores `storedPersonalVolume` (with a 500 ms delay to let the audio route stabilize), preventing the device's default hardware volume from overriding the user's configured level.

---

## 5. Web Implementation

**File:** `web/index.html`

On the web platform, routing is done using the Web Audio API's `AudioContext.setSinkId()` and the `HTMLAudioElement.setSinkId()` APIs.

### Device Selection

Users can designate a **personal speaker device ID** (`bravoPersonalSpeakerId`) and a **system speaker device ID** (`bravoSystemSpeakerId`) stored in `localStorage`. The web frontend pages (e.g., `gridpage.js`, `threads.js`) read these values and pass the appropriate ID when creating an `AudioContext` or `<audio>` element.

### `playAudioToDevice(audioDataBuffer, sampleRate, announcementType)`

Called with `announcementType` of `'personal'` or `'system'`. It:

1. Creates an `AudioContext`.
2. Resumes it if suspended (Chrome autoplay policy).
3. Calls `audioContext.setSinkId(targetOutputDeviceId)` when the API is available and a non-default device is configured.
4. Decodes the audio buffer and plays it through the context.

### `playTTSAudio(base64Audio, deviceId)` (Flutter → Web bridge)

Defined in `web/index.html`, this JavaScript function is called from Flutter via `js` interop. It creates a hidden `<audio>` element, converts the base64 audio to a Blob URL, and calls `audio.setSinkId(deviceId)` to route to the correct physical output.

---

## 6. Flutter-Side Routing Logic

**File:** `lib/main.dart`

### `announceViaBackend(text, {routing: 'system'})`

The primary function for button-selection and LLM response audio. Flow:

1. **Resets audio routing to default** (Android only) via `resetToDefault` to clear any stale `forceSpeaker` state.
2. **Initializes the audio session** on first call via `_initializeAudioSession()`.
3. **Fetches synthesized audio** from the backend (`POST /play-audio`) passing `routing_target` in the request body. The backend uses this hint when generating audio.
4. **Routes and plays** the returned base64 audio:
   - **iOS**: Calls `forceSpeaker`, sets software volume to `systemVolume / 10.0` on the `AudioPlayer`, waits 600 ms for routing to stabilize, then plays the decoded audio.
   - **Android**: Calls `forceSpeaker`, waits for routing to stabilize (handled inside the native `forceSpeaker` itself), then plays the audio.
5. **Resets after playback** (iOS): Calls `resetToDefault` / `routeToPersonal` so subsequent audio (scanning cues) goes back to the personal device.

### `_speakPersonalVoice(text)`

Used for auditory scanning cues spoken only to the AAC user:

1. Calls `routeToPersonal` (iOS) or `resetToDefault` (Android) to remove any built-in speaker override.
2. Waits 100 ms for the route change.
3. Uses `flutter_tts` with volume set to `personalVolume / 10.0`.

### `_speakSystemVoice(text)`

Used for system TTS (fallback path when backend audio is unavailable):

1. Calls `forceSpeaker` on both iOS and Android.
2. Uses `flutter_tts` with volume set to `systemVolume / 10.0`.

### `announceLocal(text)`

Fast local TTS path (no backend round-trip) used for time-sensitive prompts (e.g., "Listening"):

1. Calls `forceSpeaker`.
2. Uses `flutter_tts` with `systemVolume / 10.0`.

---

## 7. Volume Control

The app maintains two independent volume settings on a 0–10 integer scale:

| Setting | Purpose |
|---|---|
| `personalVolume` | Volume for scanning cues / personal speaker audio |
| `systemVolume` | Volume for announcements / system speaker audio |

These are stored in the user's server-side settings (`UserSettings`) and can be overridden locally via `SharedPreferences` (`personalVolumeOverride` / `systemVolumeOverride`). `_getEffectivePersonalVolume()` and `_getEffectiveSystemVolume()` always check for a local override first.

On **iOS**, hardware volume cannot be set programmatically, so the app applies volume as a software multiplier via `AudioPlayer.setVolume()` and `FlutterTts.setVolume()` at playback time.

On **Android**, volume is applied to hardware audio streams (`STREAM_MUSIC`, `STREAM_VOICE_CALL`, `STREAM_SYSTEM`) proportionally — `targetVolume = (maxStreamVolume * level) / 10`.

---

## 8. Audio Session Initialization

`_initializeAudioSession()` runs once (guarded by `_audioSessionInitialized`) on the first call to `announceViaBackend`. It:

- **Android**: Calls `initializeAudioWithVolume` with the user's saved personal and system volumes. This stores the levels in native Kotlin before `forceSpeaker()` is first invoked, ensuring those levels (not system defaults) are used from the start.
- **iOS**: Calls `setupOptimalAudioSession` (Bluetooth A2DP–aware, no speaker override), then plays a silent `silence.mp3` through `AudioPlayer` at the personal volume level to warm up the audio pipeline. The session is deliberately *not* deactivated afterward so Bluetooth routing stays active.

---

## 9. Bluetooth & Headphone Reconnection Handling

Bluetooth audio connections can drop and reconnect at any time. Both platforms handle this so that the app's configured volumes are not lost.

### iOS

`AppDelegate` observes `AVAudioSession.routeChangeNotification`. On `newDeviceAvailable` or `oldDeviceUnavailable` events (device connect/disconnect only — not category changes, to avoid infinite loops), it calls `reestablishAudioSession()` which re-applies the `.playAndRecord` category with Bluetooth A2DP options and removes any speaker override.

### Android

The `BroadcastReceiver` registered in `setupHeadphoneDetection()` listens for `ACTION_HEADSET_PLUG` and `BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED`. On reconnect events, it waits 500 ms then calls `setApplicationVolumeLevel()` to restore the user's `storedPersonalVolume`. SharedPreferences is consulted first in case a local volume override is active.

---

## 10. File Reference Summary

| File | Role |
|---|---|
| `lib/main.dart` | Flutter orchestration: `announceViaBackend`, `_speakPersonalVoice`, `_speakSystemVoice`, `announceLocal`, `_initializeAudioSession`, `_setApplicationVolume`, `_getEffectivePersonalVolume`, `_getEffectiveSystemVolume` |
| `ios/Runner/AppDelegate.swift` | iOS native: `forceSpeaker`, `routeToPersonal`, `resetToDefault`, `setupOptimalAudioSession`, route-change observer |
| `android/app/src/main/kotlin/com/bravoaac/bravo/MainActivity.kt` | Android native: `forceSpeaker`, `restoreAudio`, `setApplicationVolumeLevel`, `setVolumeToLevel`, headphone/Bluetooth `BroadcastReceiver` |
| `web/index.html` | Web bridge: `playTTSAudio`, `playTestAudio` using `setSinkId` |
| `existingfrontend/gridpage.js` | Web frontend: `playAudioToDevice` routing `personal` / `system` via `AudioContext.setSinkId` |
| `existingfrontend/audio_admin.js` | Web: audio device selector — saves `bravoPersonalSpeakerId` / `bravoSystemSpeakerId` to `localStorage` |
