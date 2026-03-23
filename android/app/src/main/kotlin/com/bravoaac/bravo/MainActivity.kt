package com.bravoaac.bravo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.MediaPlayer
import android.media.AudioDeviceInfo
import android.content.Context
import android.util.Log
import android.speech.tts.TextToSpeech
import android.os.Bundle
import android.os.Build
import android.view.inputmethod.InputMethodManager
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import java.util.*

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val CHANNEL = "audio_routing"
    private val TAG = "AudioRouting"
    private lateinit var audioManager: AudioManager
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    
    // DeepSeek audio routing variables
    private var audioFocusRequest: AudioFocusRequest? = null
    private var originalMode: Int = AudioManager.MODE_NORMAL
    private var originalSpeakerphone: Boolean = false
    private var originalVoiceCallVolume: Int = 0
    private var originalMediaVolume: Int = 0
    private var originalSystemVolume: Int = 0
    
    // Notification suppression variables
    private var originalNotificationVolume: Int = 0
    private var notificationSoundsSuppressed: Boolean = false
    
    // Audio device change detection for automatic volume control
    private var headphoneReceiver: BroadcastReceiver? = null
    
    // Store user's volume settings to restore after device reconnection
    private var storedPersonalVolume: Int? = null
    private var storedSystemVolume: Int? = null
    
    // Save user's preferred volumes from settings (to restore instead of original device volumes)
    private var savedPersonalVolume: Int = 10
    private var savedSystemVolume: Int = 10

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // MainActivity initialized for RP2040 integration
        Log.d("MainActivity", "MainActivity initialized for RP2040 input handling")
        
        // Set up headphone detection for automatic volume control
        setupHeadphoneDetection()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        // Initialize native TTS
        try {
            textToSpeech = TextToSpeech(this, this)
            Log.d("MainActivity", "TextToSpeech initialization started")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to initialize TextToSpeech: ${e.message}")
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "forceSpeaker" -> {
                    try {
                        Log.d("BravoAudioRouting", "forceSpeaker method called")
                        val success = forceSpeaker()
                        if (success) {
                            Log.d("BravoAudioRouting", "✓ Audio successfully routed to speaker")
                            result.success(true)
                        } else {
                            Log.e("BravoAudioRouting", "✗ Failed to route audio to speaker")
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e("BravoAudioRouting", "Exception in forceSpeaker: ${e.message}", e)
                        result.success(false)
                    }
                }
                "resetToDefault" -> {
                    try {
                        Log.d(TAG, "Restoring audio to default")
                        val success = restoreAudio()
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error resetting audio: ${e.message}")
                        result.error("AUDIO_ERROR", "Failed to reset audio route", e.message)
                    }
                }
                "prewarmAudioSession" -> {
                    try {
                        Log.d(TAG, "prewarmAudioSession using DeepSeek approach")
                        val success = forceSpeaker()
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error prewarming audio session: ${e.message}")
                        result.error("AUDIO_ERROR", "Failed to prewarm audio session", e.message)
                    }
                }
                "hideKeyboard" -> {
                    try {
                        Log.d("MainActivity", "hideKeyboard method called from Flutter")
                        hideKeyboard()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error hiding keyboard: ${e.message}")
                        result.error("KEYBOARD_ERROR", "Failed to hide keyboard", e.message)
                    }
                }
                "checkNativeTTS" -> {
                    try {
                        Log.d("MainActivity", "checkNativeTTS called")
                        if (ttsReady && textToSpeech != null) {
                            Log.d("MainActivity", "Native TTS is ready and available")
                            result.success("Native TTS available")
                        } else if (textToSpeech != null) {
                            Log.w("MainActivity", "Native TTS exists but not ready yet")
                            result.success("Native TTS initializing")
                        } else {
                            Log.e("MainActivity", "Native TTS is not available")
                            result.error("TTS_ERROR", "Native TTS not available", null)
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error checking native TTS: ${e.message}")
                        result.error("TTS_ERROR", "Error checking native TTS", e.message)
                    }
                }
                "speakNativeTTS" -> {
                    try {
                        Log.d("MainActivity", "speakNativeTTS called")
                        val text = call.argument<String>("text") ?: ""
                        val rate = call.argument<Double>("rate")?.toFloat() ?: 0.5f
                        val volume = call.argument<Double>("volume")?.toFloat() ?: 1.0f
                        val pitch = call.argument<Double>("pitch")?.toFloat() ?: 1.0f
                        
                        if (ttsReady && textToSpeech != null) {
                            Log.d("MainActivity", "Native TTS speaking: '$text' with rate=$rate, volume=$volume, pitch=$pitch")
                            
                            // Configure TTS settings
                            textToSpeech!!.setSpeechRate(rate)
                            textToSpeech!!.setPitch(pitch)
                            
                            // Create audio attributes to route to speaker
                            val audioAttributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                            
                            // Speak the text
                            val utteranceId = "native_tts_${System.currentTimeMillis()}"
                            val bundle = Bundle()
                            bundle.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
                            
                            val speakResult = textToSpeech!!.speak(text, TextToSpeech.QUEUE_FLUSH, bundle, utteranceId)
                            
                            if (speakResult == TextToSpeech.SUCCESS) {
                                Log.d("MainActivity", "Native TTS speak() succeeded")
                                result.success(null)
                            } else {
                                Log.e("MainActivity", "Native TTS speak() failed with result: $speakResult")
                                result.error("TTS_ERROR", "Native TTS speak failed", "Result code: $speakResult")
                            }
                        } else {
                            Log.e("MainActivity", "Native TTS not ready or not initialized")
                            result.error("TTS_ERROR", "Native TTS not ready", "TTS ready: $ttsReady")
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error with native TTS: ${e.message}")
                        result.error("TTS_ERROR", "Native TTS error", e.message)
                    }
                }
                "moveAppToBackground" -> {
                    try {
                        Log.d("MainActivity", "moveAppToBackground called - moving to recent apps")
                        moveTaskToBack(true)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error moving app to background: ${e.message}")
                        result.error("BACKGROUND_ERROR", "Failed to move app to background", e.message)
                    }
                }
                "bringAppToForeground" -> {
                    try {
                        Log.d("MainActivity", "bringAppToForeground called - bringing app back")
                        // This is automatically handled by Android when user taps the app in recents
                        // But we can ensure proper focus restoration
                        val currentFocus = currentFocus
                        currentFocus?.clearFocus()
                        runOnUiThread {
                            window.decorView.requestFocus()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error bringing app to foreground: ${e.message}")
                        result.error("FOREGROUND_ERROR", "Failed to bring app to foreground", e.message)
                    }
                }
                "resetFocus" -> {
                    try {
                        Log.d("MainActivity", "resetFocus called - applying Android focus reset")
                        resetFocus()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error resetting focus: ${e.message}")
                        result.error("FOCUS_ERROR", "Failed to reset focus", e.message)
                    }
                }
                "setMaxVolume" -> {
                    try {
                        Log.d("MainActivity", "setMaxVolume called - setting all audio streams to maximum volume")
                        setMaximumVolume()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error setting maximum volume: ${e.message}")
                        result.error("VOLUME_ERROR", "Failed to set maximum volume", e.message)
                    }
                }
                "setApplicationVolume" -> {
                    try {
                        val applicationVolume = call.argument<Int>("applicationVolume") ?: 10
                        val isPersonal = call.argument<Boolean>("isPersonal") ?: false
                        
                        Log.d("MainActivity", "setApplicationVolume called with level: $applicationVolume/10 (isPersonal=$isPersonal)")
                        
                        // Store the volume setting for restoration after device reconnection
                        if (isPersonal) {
                            storedPersonalVolume = applicationVolume
                            Log.d("MainActivity", "🔊 VOLUME: Stored personal volume: $applicationVolume/10")
                        } else {
                            storedSystemVolume = applicationVolume
                            Log.d("MainActivity", "🔊 VOLUME: Stored system volume: $applicationVolume/10")
                        }
                        
                        setApplicationVolumeLevel(applicationVolume)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error setting application volume: ${e.message}")
                        result.error("VOLUME_ERROR", "Failed to set application volume", e.message)
                    }
                }
                "initializeAudioWithVolume" -> {
                    try {
                        val personalVolume = call.argument<Int>("personalVolume") ?: 10
                        val systemVolume = call.argument<Int>("systemVolume") ?: 10
                        
                        Log.d("MainActivity", "initializeAudioWithVolume called: personal=$personalVolume/10, system=$systemVolume/10")
                        
                        // Store the volumes for device reconnection
                        storedPersonalVolume = personalVolume
                        storedSystemVolume = systemVolume
                        
                        // CRITICAL: Also save to savedPersonalVolume/savedSystemVolume so that resetToDefault() 
                        // will restore the USER'S SAVED VOLUMES, not the original device volumes
                        savedPersonalVolume = personalVolume
                        savedSystemVolume = systemVolume
                        Log.d("MainActivity", "🔊 VOLUME: Initialized stored volumes - personal: $personalVolume/10, system: $systemVolume/10")
                        Log.d("MainActivity", "🔊 VOLUME: Saved to savedPersonalVolume: $savedPersonalVolume, savedSystemVolume: $savedSystemVolume")
                        
                        // Force speaker and apply the volume
                        forceSpeaker()
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error initializing audio with volume: ${e.message}")
                        result.error("AUDIO_ERROR", "Failed to initialize audio with volume", e.message)
                    }
                }
                "suppressNotificationSounds" -> {
                    try {
                        Log.d("MainActivity", "suppressNotificationSounds called - muting notification sounds during scanning")
                        suppressNotificationSounds()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error suppressing notification sounds: ${e.message}")
                        result.error("NOTIFICATION_ERROR", "Failed to suppress notification sounds", e.message)
                    }
                }
                "restoreNotificationSounds" -> {
                    try {
                        Log.d("MainActivity", "restoreNotificationSounds called - restoring notification sounds after scanning")
                        restoreNotificationSounds()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error restoring notification sounds: ${e.message}")
                        result.error("NOTIFICATION_ERROR", "Failed to restore notification sounds", e.message)
                    }
                }
                "disableSoftKeyboard" -> {
                    try {
                        Log.d("MainActivity", "disableSoftKeyboard called - completely disabling soft keyboard for app")
                        disableSoftKeyboardCompletely()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error disabling soft keyboard: ${e.message}")
                        result.error("KEYBOARD_ERROR", "Failed to disable soft keyboard", e.message)
                    }
                }
                "showKeyboard" -> {
                    try {
                        Log.d("MainActivity", "showKeyboard method called from Flutter")
                        showKeyboard()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error showing keyboard: ${e.message}")
                        result.error("KEYBOARD_ERROR", "Failed to show keyboard", e.message)
                    }
                }
                "captureCurrentVolume" -> {
                    try {
                        val isPersonal = call.argument<Boolean>("isPersonal") ?: false
                        
                        // Read the current device volume and normalize to 0-10 scale
                        val currentVolume = if (isPersonal) {
                            // For personal (Bluetooth/headphones), read from music stream
                            audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        } else {
                            // For system (built-in speaker), also read from music stream
                            // (Android uses same stream for both speaker and headphones)
                            audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        }
                        
                        // Get max volume to normalize to 0-10 scale
                        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        
                        // Normalize to 0-10 scale
                        val normalizedVolume = if (maxVolume > 0) {
                            ((currentVolume.toDouble() / maxVolume) * 10).toInt()
                        } else {
                            10 // Fallback to maximum
                        }
                        
                        Log.d("MainActivity", "🔊 VOLUME: Captured current ${if (isPersonal) "personal" else "system"} volume: $currentVolume/$maxVolume → $normalizedVolume/10")
                        
                        // Also store it for Bluetooth reconnection
                        if (isPersonal) {
                            storedPersonalVolume = normalizedVolume
                            Log.d("MainActivity", "🔊 VOLUME: Stored personal volume for later: $normalizedVolume/10")
                        } else {
                            storedSystemVolume = normalizedVolume
                            Log.d("MainActivity", "🔊 VOLUME: Stored system volume for later: $normalizedVolume/10")
                        }
                        
                        result.success(normalizedVolume)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error capturing current volume: ${e.message}")
                        result.error("VOLUME_ERROR", "Failed to capture current volume", e.message)
                    }
                }
                else -> {
                    Log.d(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    // DeepSeek Audio Routing Methods
    private fun forceSpeaker(): Boolean {
        return try {
            Log.d(TAG, "Forcing audio to speaker using DeepSeek approach")
            
            // Save current state
            originalMode = audioManager.mode
            originalSpeakerphone = audioManager.isSpeakerphoneOn
            originalVoiceCallVolume = audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            originalMediaVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            originalSystemVolume = audioManager.getStreamVolume(AudioManager.STREAM_SYSTEM)
            
            Log.d(TAG, "Original state - Mode: $originalMode, Speakerphone: $originalSpeakerphone")
            Log.d(TAG, "Original volumes - VoiceCall: $originalVoiceCallVolume, Media: $originalMediaVolume, System: $originalSystemVolume")
            
            // Request audio focus first
            requestAudioFocus()
            
            // DeepSeek approach: Use MODE_IN_COMMUNICATION and disable other audio routes
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = true
            audioManager.isBluetoothScoOn = false
            
            // Set volume levels - use stored personal volume instead of maximum
            Log.d(TAG, "Applying stored volume settings instead of forcing maximum")
            try {
                // Use stored personal volume if available, otherwise use maximum
                val volumeToSet = storedPersonalVolume ?: 10
                Log.d(TAG, "Setting volume to stored personal level: $volumeToSet/10")
                setApplicationVolumeLevel(volumeToSet)
                Log.d(TAG, "✓ Stored personal volume applied")
            } catch (e: Exception) {
                Log.w(TAG, "Could not apply stored volume, using maximum as fallback: ${e.message}")
                try {
                    // Fallback to maximum if stored volume fails
                    setMaximumVolume()
                } catch (fallbackError: Exception) {
                    Log.w(TAG, "Fallback maximum volume also failed: ${fallbackError.message}")
                }
            }
            
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
            
            Log.d(TAG, "✓ Audio forced to speaker with max volume - Mode: ${audioManager.mode}, Speakerphone: ${audioManager.isSpeakerphoneOn}")
            
            // Add delay to allow audio routing to stabilize
            // This prevents audio cutoff at the beginning of playback
            Log.d(TAG, "Waiting 500ms for audio routing to stabilize...")
            Thread.sleep(500) // Increased to 500ms delay for routing establishment
            
            // Verify audio routing is actually set
            Log.d(TAG, "Verifying audio routing - Mode: ${audioManager.mode}, Speakerphone: ${audioManager.isSpeakerphoneOn}")
            Log.d(TAG, "Audio routing stabilization complete")
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "✗ Failed to force speaker: ${e.message}")
            false
        }
    }
    
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
    
    private fun restoreAudio(): Boolean {
        return try {
            Log.d(TAG, "🔊 RESTORE_AUDIO: Starting restoration")
            Log.d(TAG, "🔊 RESTORE_AUDIO: Current values - savedPersonalVolume=$savedPersonalVolume, savedSystemVolume=$savedSystemVolume, originalVoiceCallVolume=$originalVoiceCallVolume, originalMediaVolume=$originalMediaVolume")
            
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
            
            // CRITICAL FIX: Restore the USER'S SAVED volumes (0-10 scale) using per-stream max
            // This prevents resetToDefault() from lowering volume due to raw stream values
            try {
                val personalLevel = savedPersonalVolume ?: 10
                val systemLevel = savedSystemVolume ?: personalLevel

                val maxVoice = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                val maxMedia = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val maxSystem = audioManager.getStreamMaxVolume(AudioManager.STREAM_SYSTEM)

                val voiceCallVolumeToRestore = ((maxVoice * personalLevel) / 10).coerceIn(0, maxVoice)
                val mediaVolumeToRestore = ((maxMedia * personalLevel) / 10).coerceIn(0, maxMedia)
                val systemVolumeToRestore = ((maxSystem * systemLevel) / 10).coerceIn(0, maxSystem)

                Log.d(TAG, "🔊 RESTORE_AUDIO: Restoring to - voiceCall=$voiceCallVolumeToRestore/$maxVoice, media=$mediaVolumeToRestore/$maxMedia, system=$systemVolumeToRestore/$maxSystem (personalLevel=$personalLevel, systemLevel=$systemLevel)")

                audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, voiceCallVolumeToRestore, 0)
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, mediaVolumeToRestore, 0)
                audioManager.setStreamVolume(AudioManager.STREAM_SYSTEM, systemVolumeToRestore, 0)
                Log.d(TAG, "Restored volumes - VoiceCall: $voiceCallVolumeToRestore, Media: $mediaVolumeToRestore, System: $systemVolumeToRestore (savedPersonal: $savedPersonalVolume, savedSystem: $savedSystemVolume)")
            } catch (e: Exception) {
                Log.w(TAG, "Could not restore volume levels: ${e.message}")
            }
            
            // ALWAYS reset to MODE_NORMAL (0), not stored originalMode
            // This prevents getting stuck in MODE_IN_COMMUNICATION
            audioManager.mode = AudioManager.MODE_NORMAL
            audioManager.isSpeakerphoneOn = false
            
            Log.d(TAG, "✓ Audio restored - Mode: ${audioManager.mode}, Speakerphone: ${audioManager.isSpeakerphoneOn}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "✗ Failed to restore audio: ${e.message}")
            false
        }
    }

    private fun setApplicationVolumeLevel(applicationVolume: Int) {
        try {
            val volumeLevel = applicationVolume.coerceIn(0, 10)
            Log.d(TAG, "Setting audio streams to application volume level: $volumeLevel/10 (respecting notification suppression)")
            
            setVolumeToLevel(volumeLevel)
            
        } catch (e: Exception) {
            Log.e(TAG, "✗ Failed to set application volume level: ${e.message}")
        }
    }

    private fun setMaximumVolume() {
        try {
            Log.d(TAG, "Setting audio streams to maximum volume (respecting notification suppression)")
            
            setVolumeToLevel(10) // Set to maximum (10/10)
            
            // Set all relevant audio streams to maximum volume, EXCEPT notifications if suppressed
            val streams = if (notificationSoundsSuppressed) {
                Log.d(TAG, "Notifications are suppressed - excluding from volume maximization")
                arrayOf(
                    AudioManager.STREAM_MUSIC,        // Media/Music stream (most audio playback)
                    AudioManager.STREAM_VOICE_CALL,   // Voice call stream (used in communication mode)
                    AudioManager.STREAM_SYSTEM,       // System sounds
                    AudioManager.STREAM_RING,         // Ringtone
                    AudioManager.STREAM_ALARM         // Alarms
                    // INTENTIONALLY EXCLUDING STREAM_NOTIFICATION when suppressed
                )
            } else {
                Log.d(TAG, "Notifications not suppressed - including all streams")
                arrayOf(
                    AudioManager.STREAM_MUSIC,        // Media/Music stream (most audio playback)
                    AudioManager.STREAM_VOICE_CALL,   // Voice call stream (used in communication mode)
                    AudioManager.STREAM_SYSTEM,       // System sounds
                    AudioManager.STREAM_NOTIFICATION, // Notifications
                    AudioManager.STREAM_RING,         // Ringtone
                    AudioManager.STREAM_ALARM         // Alarms
                )
            }
            
            for (stream in streams) {
                try {
                    val maxVolume = audioManager.getStreamMaxVolume(stream)
                    val currentVolume = audioManager.getStreamVolume(stream)
                    
                    if (currentVolume < maxVolume) {
                        audioManager.setStreamVolume(stream, maxVolume, 0)
                        Log.d(TAG, "Stream $stream volume set to maximum: $maxVolume (was $currentVolume)")
                    } else {
                        Log.d(TAG, "Stream $stream already at maximum volume: $maxVolume")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not set volume for stream $stream: ${e.message}")
                }
            }
            
            // Special handling for headphone volume
            try {
                // When headphones are connected, ensure media volume is at max
                // This is the primary volume control for headphone output
                val maxMediaVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxMediaVolume, AudioManager.FLAG_SHOW_UI)
                Log.d(TAG, "✓ Headphone-optimized volume set - Media stream at maximum: $maxMediaVolume")
                
                // Also ensure voice call volume is maxed for communication mode audio
                val maxVoiceVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVoiceVolume, 0)
                Log.d(TAG, "✓ Voice call volume maximized for communication audio: $maxVoiceVolume")
                
            } catch (e: Exception) {
                Log.w(TAG, "Could not optimize headphone volume: ${e.message}")
            }
            
            Log.d(TAG, "✓ Maximum volume configuration completed successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "✗ Failed to set maximum volume: ${e.message}")
        }
    }

    private fun setVolumeToLevel(volumeLevel: Int) {
        try {
            val clampedLevel = volumeLevel.coerceIn(0, 10)
            Log.d(TAG, "Setting all audio streams to volume level: $clampedLevel/10")
            
            // Set all relevant audio streams to specified volume level, EXCEPT notifications if suppressed
            val streams = if (notificationSoundsSuppressed) {
                Log.d(TAG, "Notifications are suppressed - excluding from volume control")
                arrayOf(
                    AudioManager.STREAM_MUSIC,        // Media/Music stream (most audio playback)
                    AudioManager.STREAM_VOICE_CALL,   // Voice call stream (used in communication mode)
                    AudioManager.STREAM_SYSTEM,       // System sounds
                    AudioManager.STREAM_RING,         // Ringtone
                    AudioManager.STREAM_ALARM         // Alarms
                    // INTENTIONALLY EXCLUDING STREAM_NOTIFICATION when suppressed
                )
            } else {
                Log.d(TAG, "Notifications not suppressed - including all streams")
                arrayOf(
                    AudioManager.STREAM_MUSIC,        // Media/Music stream (most audio playback)
                    AudioManager.STREAM_VOICE_CALL,   // Voice call stream (used in communication mode)
                    AudioManager.STREAM_SYSTEM,       // System sounds
                    AudioManager.STREAM_NOTIFICATION, // Notifications
                    AudioManager.STREAM_RING,         // Ringtone
                    AudioManager.STREAM_ALARM         // Alarms
                )
            }
            
            for (stream in streams) {
                try {
                    val maxVolume = audioManager.getStreamMaxVolume(stream)
                    val targetVolume = ((maxVolume * clampedLevel) / 10).coerceIn(0, maxVolume)
                    val currentVolume = audioManager.getStreamVolume(stream)
                    
                    if (currentVolume != targetVolume) {
                        audioManager.setStreamVolume(stream, targetVolume, 0)
                        Log.d(TAG, "Stream $stream volume set to: $targetVolume/$maxVolume (level $clampedLevel/10, was $currentVolume)")
                    } else {
                        Log.d(TAG, "Stream $stream already at target volume: $targetVolume/$maxVolume (level $clampedLevel/10)")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not set volume for stream $stream: ${e.message}")
                }
            }
            
            // Special handling for headphone volume
            try {
                // When headphones are connected, ensure media volume is set to target level
                // This is the primary volume control for headphone output
                val maxMediaVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val targetMediaVolume = ((maxMediaVolume * clampedLevel) / 10).coerceIn(0, maxMediaVolume)
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetMediaVolume, AudioManager.FLAG_SHOW_UI)
                Log.d(TAG, "✓ Headphone-optimized volume set - Media stream at level $clampedLevel/10: $targetMediaVolume/$maxMediaVolume")
                
                // Also ensure voice call volume is set to target level for communication mode audio
                val maxVoiceVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                val targetVoiceVolume = ((maxVoiceVolume * clampedLevel) / 10).coerceIn(0, maxVoiceVolume)
                audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, targetVoiceVolume, 0)
                Log.d(TAG, "✓ Voice call volume set to level $clampedLevel/10: $targetVoiceVolume/$maxVoiceVolume")
                
            } catch (e: Exception) {
                Log.w(TAG, "Could not optimize volume levels: ${e.message}")
            }
            
            Log.d(TAG, "✓ Volume level $clampedLevel/10 configuration completed successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "✗ Failed to set volume level: ${e.message}")
        }
    }

    private fun hideKeyboard() {
        try {
            val inputMethodManager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            currentFocus?.let { view ->
                inputMethodManager.hideSoftInputFromWindow(view.windowToken, InputMethodManager.HIDE_NOT_ALWAYS)
                Log.d("MainActivity", "🚫 Keyboard hidden from current focus")
            }
            
            // Also try to hide from the window
            window?.let { window ->
                window.decorView?.let { decorView ->
                    inputMethodManager.hideSoftInputFromWindow(decorView.windowToken, InputMethodManager.HIDE_NOT_ALWAYS)
                    Log.d("MainActivity", "🚫 Keyboard hidden from window")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error hiding keyboard: ${e.message}")
        }
    }

    private fun showKeyboard() {
        try {
            Log.d("MainActivity", "🔤 Attempting to show keyboard with enhanced strategy...")
            val inputMethodManager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            
            // First, ensure window allows keyboard input
            window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            Log.d("MainActivity", "🔤 Window configured for keyboard visibility")
            
            // Strategy 1: Multiple attempts with delays to overcome focus conflicts
            runOnUiThread {
                try {
                    // Attempt 1: Immediate show
                    currentFocus?.let { view ->
                        inputMethodManager.showSoftInput(view, InputMethodManager.SHOW_FORCED)
                        Log.d("MainActivity", "🔤 Attempt 1: Keyboard show requested for current focus")
                    }
                    
                    // Attempt 2: After 100ms delay
                    window.decorView.postDelayed({
                        try {
                            inputMethodManager.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
                            Log.d("MainActivity", "🔤 Attempt 2: Forced keyboard toggle after 100ms")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error in attempt 2: ${e.message}")
                        }
                    }, 100)
                    
                    // Attempt 3: After 300ms delay with focus reset
                    window.decorView.postDelayed({
                        try {
                            // Clear and re-establish focus to trigger keyboard
                            val decorView = window.decorView
                            decorView.clearFocus()
                            decorView.requestFocus()
                            inputMethodManager.showSoftInput(decorView, InputMethodManager.SHOW_IMPLICIT)
                            Log.d("MainActivity", "🔤 Attempt 3: Focus reset and implicit show after 300ms")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error in attempt 3: ${e.message}")
                        }
                    }, 300)
                    
                    // Attempt 4: After 500ms with aggressive forcing
                    window.decorView.postDelayed({
                        try {
                            // Most aggressive approach - force show regardless of focus state
                            inputMethodManager.showSoftInput(window.decorView, InputMethodManager.SHOW_FORCED or InputMethodManager.SHOW_IMPLICIT)
                            Log.d("MainActivity", "🔤 Attempt 4: Aggressive force show after 500ms")
                            
                            // Also try the toggle method as backup
                            inputMethodManager.toggleSoftInput(InputMethodManager.SHOW_FORCED, InputMethodManager.HIDE_IMPLICIT_ONLY)
                            Log.d("MainActivity", "🔤 Attempt 4b: Toggle force show as backup")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error in attempt 4: ${e.message}")
                        }
                    }, 500)
                    
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error in runOnUiThread keyboard show: ${e.message}")
                }
            }
            
            Log.d("MainActivity", "🔤 Multi-attempt keyboard show strategy initiated")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error showing keyboard: ${e.message}")
        }
    }

    // *** DEEP SEEK'S NUCLEAR FOCUS RESET FOR ANDROID ***
    private fun resetFocus() {
        try {
            Log.d("MainActivity", "🧨 Starting nuclear focus reset...")
            
            // Clear focus from all views
            window.decorView.clearFocus()
            Log.d("MainActivity", "🧨 Cleared focus from decorView")
            
            // Force focus state reset using temporary view approach
            val tempView = View(this)
            tempView.isFocusable = true
            tempView.isFocusableInTouchMode = true
            
            // Get the root ViewGroup (content frame)
            val rootViewGroup = findViewById<ViewGroup>(android.R.id.content)
            
            if (rootViewGroup != null) {
                // Add temp view to force focus system reset
                rootViewGroup.addView(tempView)
                tempView.requestFocus()
                Log.d("MainActivity", "🧨 Temporary view added and focused")
                
                // Remove temp view immediately
                rootViewGroup.removeView(tempView)
                Log.d("MainActivity", "🧨 Temporary view removed")
            } else {
                Log.w("MainActivity", "🧨 Could not get root ViewGroup, skipping temp view approach")
            }
            
            // Additional keyboard hiding
            hideKeyboard()
            
            Log.d("MainActivity", "🧨 Nuclear focus reset complete!")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in nuclear focus reset: ${e.message}")
        }
    }

    // *** COMPLETE SOFT KEYBOARD DISABLE - ULTIMATE SOLUTION ***
    private fun disableSoftKeyboardCompletely() {
        try {
            Log.d("MainActivity", "🚫 Starting complete soft keyboard disable...")
            
            // Method 1: Set window flag to never show soft keyboard
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
            Log.d("MainActivity", "🚫 Set SOFT_INPUT_STATE_ALWAYS_HIDDEN")
            
            // Method 2: Clear the focusable flag from the window
            window.decorView.isFocusable = false
            window.decorView.isFocusableInTouchMode = false
            Log.d("MainActivity", "🚫 Disabled focusable on decorView")
            
            // Method 3: Override input method service behavior
            val inputMethodManager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.hideSoftInputFromWindow(window.decorView.windowToken, InputMethodManager.HIDE_NOT_ALWAYS)
            Log.d("MainActivity", "🚫 Hidden soft input from window")
            
            // Method 4: Set specific window flags to prevent keyboard
            window.setFlags(
                WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM,
                WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM
            )
            Log.d("MainActivity", "🚫 Set FLAG_ALT_FOCUSABLE_IM")
            
            Log.d("MainActivity", "🚫 Complete soft keyboard disable finished!")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in complete soft keyboard disable: ${e.message}")
        }
    }

    // Set up headphone detection for automatic volume control
    private fun setupHeadphoneDetection() {
        Log.d("MainActivity", "Setting up headphone/Bluetooth detection for automatic volume control")
        
        headphoneReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
                        // Headphones unplugged
                        Log.d("MainActivity", "🔊 Headphones unplugged - audio becoming noisy")
                    }
                    AudioManager.ACTION_HEADSET_PLUG -> {
                        val state = intent.getIntExtra("state", -1)
                        val name = intent.getStringExtra("name")
                        val microphone = intent.getIntExtra("microphone", -1)
                        
                        when (state) {
                            0 -> {
                                Log.d("MainActivity", "🔊 Headphones unplugged: $name (mic=$microphone)")
                            }
                            1 -> {
                                Log.d("MainActivity", "🔊 Headphones plugged in: $name (mic=$microphone)")
                                Log.d("MainActivity", "🔊 VOLUME: Restoring personal volume setting after headphones connected...")
                                
                                // Restore personal volume - check for local override first
                                try {
                                    val prefs = android.preference.PreferenceManager.getDefaultSharedPreferences(context)
                                    val hasOverride = prefs.getBoolean("personalVolumeOverride", false)
                                    val volumeToRestore = if (hasOverride) {
                                        prefs.getInt("personalVolumeOverrideValue", storedPersonalVolume ?: 10)
                                    } else {
                                        storedPersonalVolume ?: 10
                                    }
                                    Log.d("MainActivity", "🔊 VOLUME: Restoring personal volume to: $volumeToRestore/10 (override=$hasOverride)")
                                    setApplicationVolumeLevel(volumeToRestore)
                                    Log.d("MainActivity", "🔊 VOLUME: ✅ Personal volume restored successfully")
                                } catch (e: Exception) {
                                    Log.e("MainActivity", "🔊 VOLUME: ⚠️  Failed to restore personal volume: ${e.message}")
                                }
                            }
                        }
                    }
                    Intent.ACTION_HEADSET_PLUG -> {
                        // Alternative action name for some Android versions
                        val state = intent.getIntExtra("state", -1)
                        val name = intent.getStringExtra("name") ?: "Unknown"
                        
                        if (state == 1) {
                            Log.d("MainActivity", "🔊 Headphones connected via ACTION_HEADSET_PLUG: $name")
                            Log.d("MainActivity", "🔊 VOLUME: Restoring personal volume setting...")
                            
                            try {
                                val prefs = android.preference.PreferenceManager.getDefaultSharedPreferences(context)
                                val hasOverride = prefs.getBoolean("personalVolumeOverride", false)
                                val volumeToRestore = if (hasOverride) {
                                    prefs.getInt("personalVolumeOverrideValue", storedPersonalVolume ?: 10)
                                } else {
                                    storedPersonalVolume ?: 10
                                }
                                Log.d("MainActivity", "🔊 VOLUME: Restoring personal volume to: $volumeToRestore/10 (override=$hasOverride)")
                                setApplicationVolumeLevel(volumeToRestore)
                                Log.d("MainActivity", "🔊 VOLUME: ✅ Personal volume restored")
                            } catch (e: Exception) {
                                Log.e("MainActivity", "🔊 VOLUME: ⚠️  Failed to restore personal volume: ${e.message}")
                            }
                        }
                    }
                    // Handle Bluetooth audio device connections
                    android.bluetooth.BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED -> {
                        val state = intent.getIntExtra(android.bluetooth.BluetoothAdapter.EXTRA_CONNECTION_STATE, -1)
                        val prevState = intent.getIntExtra(android.bluetooth.BluetoothAdapter.EXTRA_PREVIOUS_CONNECTION_STATE, -1)
                        
                        Log.d("MainActivity", "🔊 Bluetooth connection state changed: $prevState -> $state")
                        
                        if (state == android.bluetooth.BluetoothAdapter.STATE_CONNECTED) {
                            Log.d("MainActivity", "🔊 Bluetooth device connected - restoring personal volume...")
                            
                            try {
                                // Small delay to ensure Bluetooth audio routing is established
                                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                    val prefs = android.preference.PreferenceManager.getDefaultSharedPreferences(context)
                                    val hasOverride = prefs.getBoolean("personalVolumeOverride", false)
                                    val volumeToRestore = if (hasOverride) {
                                        prefs.getInt("personalVolumeOverrideValue", storedPersonalVolume ?: 10)
                                    } else {
                                        storedPersonalVolume ?: 10
                                    }
                                    Log.d("MainActivity", "🔊 VOLUME: Restoring personal volume to: $volumeToRestore/10 after Bluetooth connection (override=$hasOverride)")
                                    setApplicationVolumeLevel(volumeToRestore)
                                    Log.d("MainActivity", "🔊 VOLUME: ✅ Personal volume restored after Bluetooth connection")
                                }, 500) // 500ms delay for Bluetooth routing to stabilize
                            } catch (e: Exception) {
                                Log.e("MainActivity", "🔊 VOLUME: ⚠️  Failed to restore volume after Bluetooth connection: ${e.message}")
                            }
                        }
                    }
                    // Handle Bluetooth A2DP (audio streaming) connection changes
                    android.bluetooth.BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED -> {
                        val state = intent.getIntExtra(android.bluetooth.BluetoothProfile.EXTRA_STATE, -1)
                        
                        Log.d("MainActivity", "🔊 Bluetooth A2DP state changed: $state")
                        
                        if (state == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                            Log.d("MainActivity", "🔊 Bluetooth A2DP connected - restoring personal volume...")
                            
                            try {
                                // Small delay to ensure Bluetooth audio routing is established
                                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                    val prefs = android.preference.PreferenceManager.getDefaultSharedPreferences(context)
                                    val hasOverride = prefs.getBoolean("personalVolumeOverride", false)
                                    val volumeToRestore = if (hasOverride) {
                                        prefs.getInt("personalVolumeOverrideValue", storedPersonalVolume ?: 10)
                                    } else {
                                        storedPersonalVolume ?: 10
                                    }
                                    Log.d("MainActivity", "🔊 VOLUME: Restoring personal volume to: $volumeToRestore/10 after Bluetooth A2DP connection (override=$hasOverride)")
                                    setApplicationVolumeLevel(volumeToRestore)
                                    Log.d("MainActivity", "🔊 VOLUME: ✅ Personal volume restored after Bluetooth A2DP connection")
                                }, 500) // 500ms delay for Bluetooth routing to stabilize
                            } catch (e: Exception) {
                                Log.e("MainActivity", "🔊 VOLUME: ⚠️  Failed to restore volume after Bluetooth A2DP connection: ${e.message}")
                            }
                        }
                    }
                }
            }
        }
        
        // Register the receiver for headphone and Bluetooth events
        val filter = IntentFilter().apply {
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            addAction(AudioManager.ACTION_HEADSET_PLUG)
            addAction(Intent.ACTION_HEADSET_PLUG)
            addAction(android.bluetooth.BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED)
            addAction(android.bluetooth.BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
        }
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(headphoneReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(headphoneReceiver, filter)
            }
            Log.d("MainActivity", "🔊 Headphone/Bluetooth detection receiver registered successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to register headphone/Bluetooth detection receiver: ${e.message}")
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            Log.d("MainActivity", "TextToSpeech initialized successfully")
            ttsReady = true
            
            // Set language to US English
            val result = textToSpeech!!.setLanguage(Locale.US)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.w("MainActivity", "Language not supported for TTS")
            } else {
                Log.d("MainActivity", "TTS language set to US English")
            }
        } else {
            Log.e("MainActivity", "TextToSpeech initialization failed with status: $status")
            ttsReady = false
        }
    }
    
    private fun suppressNotificationSounds() {
        try {
            if (!notificationSoundsSuppressed) {
                // Store original notification volume
                originalNotificationVolume = audioManager.getStreamVolume(AudioManager.STREAM_NOTIFICATION)
                
                // Mute notification sounds to prevent chirps during scanning
                audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, 0, 0)
                notificationSoundsSuppressed = true
                
                Log.d("MainActivity", "✓ Notification sounds suppressed (original volume: $originalNotificationVolume)")
            } else {
                Log.d("MainActivity", "Notification sounds already suppressed")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error suppressing notification sounds: ${e.message}")
        }
    }
    
    private fun restoreNotificationSounds() {
        try {
            if (notificationSoundsSuppressed) {
                // Restore original notification volume
                audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, originalNotificationVolume, 0)
                notificationSoundsSuppressed = false
                
                Log.d("MainActivity", "✓ Notification sounds restored to original volume: $originalNotificationVolume")
            } else {
                Log.d("MainActivity", "Notification sounds were not suppressed")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error restoring notification sounds: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Restore notification sounds if they were suppressed
        if (notificationSoundsSuppressed) {
            restoreNotificationSounds()
        }
        
        // Unregister headphone detection receiver
        headphoneReceiver?.let {
            try {
                unregisterReceiver(it)
                Log.d("MainActivity", "🔊 Headphone detection receiver unregistered")
            } catch (e: Exception) {
                Log.e("MainActivity", "Error unregistering headphone receiver: ${e.message}")
            }
            headphoneReceiver = null
        }
        
        // Clean up audio focus if still held
        audioFocusRequest?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioManager.abandonAudioFocusRequest(it)
            }
        }
        
        // Clean up TextToSpeech
        textToSpeech?.shutdown()
        Log.d(TAG, "MainActivity cleanup completed")
    }
}
