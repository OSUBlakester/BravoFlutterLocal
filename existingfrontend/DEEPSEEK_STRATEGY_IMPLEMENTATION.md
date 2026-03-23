# DeepSeek Audio Routing Strategy - Implementation Guide

## Overview
This strategy successfully forces audio to play through device speakers even when headphones are connected, using Android's communication device APIs and aggressive audio routing control.

## Required Files/Changes

### 1. AndroidManifest.xml - Add Permission
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <!-- ... rest of your manifest -->
</manifest>
```

### 2. MainActivity.kt - Add These Imports
```kotlin
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
```

### 3. MainActivity.kt - Add These Class Variables
```kotlin
class MainActivity: FlutterActivity() {
    private val CHANNEL = "your_app_package/audio"  // Change to match your package
    private val TAG = "AudioRouting"
    private lateinit var audioManager: AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null
    private var originalMode: Int = AudioManager.MODE_NORMAL
    private var originalSpeakerphone: Boolean = false
    private var mediaPlayer: MediaPlayer? = null
```

### 4. MainActivity.kt - Core DeepSeek Audio Routing Method
```kotlin
private fun forceSpeaker(): Boolean {
    return try {
        Log.d(TAG, "Forcing audio to speaker using DeepSeek approach")
        
        // Save current state
        originalMode = audioManager.mode
        originalSpeakerphone = audioManager.isSpeakerphoneOn
        
        Log.d(TAG, "Original state - Mode: $originalMode, Speakerphone: $originalSpeakerphone")
        
        // Request audio focus first
        requestAudioFocus()
        
        // DeepSeek approach: Use MODE_IN_COMMUNICATION and disable other audio routes
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = true
        audioManager.isBluetoothScoOn = false
        
        // Try to disable wired headset routing
        try {
            val clazz = AudioManager::class.java
            val method = clazz.getMethod("setWiredHeadsetOn", Boolean::class.javaPrimitiveType)
            method.invoke(audioManager, false)
            Log.d(TAG, "Wired headset disabled via reflection")
        } catch (e: Exception) {
            Log.w(TAG, "Could not disable wired headset (method not available): ${e.message}")
        }
        
        // Set communication device to built-in speaker (Android S+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val outputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val builtInSpeaker = outputDevices.find { 
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER 
                }
                
                if (builtInSpeaker != null) {
                    Log.d(TAG, "Found built-in speaker device: ${builtInSpeaker.productName}")
                    val setCommunicationDeviceResult = audioManager.setCommunicationDevice(builtInSpeaker)
                    Log.d(TAG, "Set communication device result: $setCommunicationDeviceResult")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not set communication device: ${e.message}")
            }
        }
        
        Log.d(TAG, "✓ Audio forced to speaker - Mode: ${audioManager.mode}, Speakerphone: ${audioManager.isSpeakerphoneOn}")
        
        true
    } catch (e: Exception) {
        Log.e(TAG, "✗ Failed to force speaker: ${e.message}")
        false
    }
}
```

### 5. MainActivity.kt - Audio Focus Request Method
```kotlin
private fun requestAudioFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAcceptsDelayedFocusGain(true)
            .setOnAudioFocusChangeListener { focusChange ->
                Log.d(TAG, "Audio focus change: $focusChange")
            }
            .build()

        val focusResult = audioManager.requestAudioFocus(audioFocusRequest!!)
        Log.d(TAG, "Audio focus request result: $focusResult")
    }
}
```

### 6. MainActivity.kt - Restore Audio Method
```kotlin
private fun restoreAudio(): Boolean {
    return try {
        Log.d(TAG, "Restoring original audio settings")
        
        // Release audio focus
        audioFocusRequest?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioManager.abandonAudioFocusRequest(it)
            }
        }
        audioFocusRequest = null
        
        // Clear communication device (Android S+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                audioManager.clearCommunicationDevice()
                Log.d(TAG, "Communication device cleared")
            } catch (e: Exception) {
                Log.w(TAG, "Could not clear communication device: ${e.message}")
            }
        }
        
        // Restore original settings
        audioManager.mode = originalMode
        audioManager.isSpeakerphoneOn = originalSpeakerphone
        
        Log.d(TAG, "✓ Audio restored - Mode: ${audioManager.mode}, Speakerphone: ${audioManager.isSpeakerphoneOn}")
        true
    } catch (e: Exception) {
        Log.e(TAG, "✗ Failed to restore audio: ${e.message}")
        false
    }
}
```

### 7. MainActivity.kt - Method Channel Handler
```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    
    audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    Log.d(TAG, "Audio system initialized")

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
        try {
            when (call.method) {
                "forceSpeaker" -> {
                    Log.d(TAG, "Forcing audio to speaker using DeepSeek approach")
                    val success = forceSpeaker()
                    result.success(success)
                }
                "restoreAudio" -> {
                    Log.d(TAG, "Restoring audio to default")
                    val success = restoreAudio()
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in method channel: ${e.message}")
            result.error("ERROR", e.message, null)
        }
    }
}
```

### 8. Flutter/Dart - Platform Channel Calls
```dart
static const platform = MethodChannel('your_app_package/audio');

// Call this to force audio to speaker
Future<void> _forceSpeaker() async {
  try {
    final bool result = await platform.invokeMethod('forceSpeaker');
    print('Force speaker result: $result');
  } on PlatformException catch (e) {
    print('Failed to force speaker: ${e.message}');
  }
}

// Call this to restore normal audio routing
Future<void> _restoreAudio() async {
  try {
    final bool result = await platform.invokeMethod('restoreAudio');
    print('Restore audio result: $result');
  } on PlatformException catch (e) {
    print('Failed to restore audio: ${e.message}');
  }
}
```

## Key Success Factors

1. **MODIFY_AUDIO_SETTINGS permission** - Critical for audio routing control
2. **MODE_IN_COMMUNICATION** - Puts AudioManager in VoIP mode for better routing control
3. **Disable all other audio routes** - Bluetooth SCO, wired headset via reflection
4. **setCommunicationDevice()** - Explicitly sets communication device on Android S+
5. **Proper cleanup** - Always restore original audio settings

## Integration Steps

1. Add the MODIFY_AUDIO_SETTINGS permission to AndroidManifest.xml
2. Add the required imports to your MainActivity.kt
3. Add the class variables to your MainActivity
4. Add the core methods (forceSpeaker, requestAudioFocus, restoreAudio)
5. Integrate the MethodChannel handler into your configureFlutterEngine
6. Update your Dart/Flutter code to use the platform channel calls
7. Replace your existing ALARM strategy with calls to `_forceSpeaker()` and `_restoreAudio()`

## Usage
- Call `_forceSpeaker()` when you want audio to play through device speakers
- Call `_restoreAudio()` when you want to return to normal audio routing
- This works even when headphones are connected!
