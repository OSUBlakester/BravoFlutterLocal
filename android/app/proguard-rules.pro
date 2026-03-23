# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /usr/local/Cellar/android-sdk/24.3.3/tools/proguard/proguard-android.txt
# You can edit the include path and order by changing the proguardFiles
# directive in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Add any project specific keep options here:

# CRITICAL: Keep MainActivity class - DO NOT OBFUSCATE
# Keep MainActivity from being obfuscated (correct package)
-keep class com.bravoaac.bravo.MainActivity { *; }
-keep class io.flutter.embedding.android.FlutterActivity { *; }

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Dart and Flutter
-dontwarn io.flutter.**
-keep class androidx.lifecycle.** { *; }

# Audio/TTS related
-keep class android.speech.** { *; }
-keep class android.media.** { *; }

# HTTP and networking
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**

# JSON and serialization
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# WebView (if used)
-keep class android.webkit.** { *; }

# Firebase (used in your app)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Flutter TTS
-keep class com.tundralabs.fluttertts.** { *; }

# Just Audio
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# Speech to Text
-keep class com.csdcorp.speech_to_text.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Google Fonts
-keep class io.flutter.plugins.googlemobileads.** { *; }

# Shared Preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Provider (state management)
-keep class ** extends io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }

# Platform channels and method channels
-keep class ** implements io.flutter.plugin.common.MethodCall.** { *; }
-keep class ** implements io.flutter.plugin.common.PluginRegistry.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep custom classes that might be called from native code
-keep class com.bravoaac.bravo.** { *; }

# General Android rules
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Keep enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
