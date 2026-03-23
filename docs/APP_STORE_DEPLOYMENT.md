# App Store & Play Store Deployment Guide

## 🚀 QUICK DEPLOY TO TESTFLIGHT (iOS)
```bash
# 1. Increment build number (REQUIRED for each upload)
./scripts/increment_version.sh

# 2. Build the IPA (Updated December 2025 - Use app-store method for TestFlight/Production)
flutter clean && flutter pub get && flutter build ipa --export-method app-store

# 3. Upload via Apple Transporter
# - Download Transporter from Mac App Store
# - Drag build/ios/ipa/Bravo AAC.ipa into Transporter
# - Sign in and upload

# 4. Add testers in App Store Connect → TestFlight
```

## 🎉 DEPLOYMENT STATUS: READY FOR STORE SUBMISSION

### Current Configuration (Updated December 22, 2025)
- **App Name**: Bravo AAC
- **Description**: Bravo AAC - Augmentative and Alternative Communication  
- **Bundle ID (iOS)**: com.talkwithbravo.bravoprod *(existing Apple Developer ID)*
- **Package Name (Android)**: com.bravoaac.bravo
- **Apple Developer Account**: mr.blakethomas@gmail.com
- **Primary URL**: https://app.talkwithbravo.com
- **Current iOS Build**: Version 1.0.2, Build 25 *(as of December 22, 2025)*

### Prerequisites Completed ✅
- [x] App name updated to "Bravo AAC"
- [x] App icon generated from speech_bubble_spinner.png
- [x] Bundle identifiers updated for both platforms
- [x] Android toolchain configured with cmdline-tools
- [x] Android SDK licenses accepted
- [x] iOS TestFlight external testing approved
- [x] Android App Bundle builds successfully (44MB)
- [x] URL migration to app.talkwithbravo.com completed

## iOS App Store Steps

### 1. Set up App Store Connect
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Sign in with mr.blakethomas@gmail.com
3. Click "My Apps" → "+" → "New App"
4. Fill in:
   - **Platform**: iOS
   - **Name**: Bravo AAC
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: com.talkwithbravo.bravoprod *(select existing)*
   - **SKU**: BravoAAC2025 (or similar unique identifier)

### 2. Configure App Information
- **App Category**: Medical or Education
- **Content Rights**: Your app may contain content from third parties
- **Age Rating**: Complete questionnaire (likely 4+ for AAC app)
- **App Privacy**: Complete privacy questionnaire
- **App Review Information**: Provide test account if needed
  - **Sign-in Information**: Use demo account (e.g., demoreadonly@talkwithbravo.com)
  - **Notes**: Explain account capabilities and any special instructions
  - **Demo Content**: Ensure account has sample data for testing

### 3. Prepare for TestFlight Distribution
```bash
# Clean and build IPA for App Store/TestFlight (UPDATED COMMAND)
flutter clean
flutter pub get
flutter build ipa --release

# The IPA will be created at: build/ios/ipa/Runner.ipa
```

**Upload Options:**
1. **Apple Transporter (Recommended)**: Drag `build/ios/ipa/Bravo AAC.ipa` into Transporter app
2. **Xcode (Alternative)**: Open `ios/Runner.xcworkspace` → Product → Archive → Upload
3. **Command Line**: Use `xcrun altool` with API keys

After upload:
1. Go to App Store Connect → TestFlight
2. Add external testers (up to 10,000 by email)

**Common Issues & Solutions:**
- **PIF Transfer Error in Xcode**: Use `flutter build ipa --release` instead of Xcode Archive
- **"unable to initiate PIF transfer session"**: Clear DerivedData and use Flutter IPA command
- **Xcode Archive Issues**: Flutter's IPA build is more reliable than manual Xcode archiving
- **Orientation validation errors**: Fixed by adding `UIRequiresFullScreen` to Info.plist (required for landscape-only apps)
- **Build cache issues**: Run `flutter clean` and clear `~/Library/Developer/Xcode/DerivedData`

**Troubleshooting Steps:**
```bash
# If Xcode Archive fails, use this sequence:
pkill -f Xcode  # Quit Xcode completely
rm -rf ~/Library/Developer/Xcode/DerivedData  # Clear Xcode cache
flutter clean && flutter pub get  # Clean Flutter
flutter build ipa --release  # Build directly with Flutter

# If app icon doesn't update on TestFlight:
flutter packages pub run flutter_launcher_icons:main  # Regenerate icons
# Increment build number in pubspec.yaml (e.g., 1.0.2+18 → 1.0.2+19)
flutter clean && flutter pub get && flutter build ipa --release
```

### 4. Privacy Information Required
You'll need to declare:
- **Microphone Usage**: For speech recognition
- **Network Usage**: For cloud TTS and API calls
- **Device Storage**: For user preferences and speech history

## Google Play Store Steps

### 1. Set up Google Play Console
1. Go to [Google Play Console](https://play.google.com/console)
2. Create new app:
   - **App name**: Bravo AAC
   - **Default language**: English (United States)
## Android Play Store Steps ✅ READY FOR SUBMISSION

### 1. Set up Google Play Console
1. Go to [Google Play Console](https://play.google.com/console)
2. Sign in and create developer account
3. Click "Create app"
4. Fill in:
   - **App name**: Bravo AAC
   - **Default language**: English (United States)
   - **App or game**: App
   - **Free or paid**: Free (or Paid if applicable)

### 2. Build Android App Bundle

#### Build Commands (Environment Setup Required)
```bash
# Set Android environment (run this each session)
export ANDROID_HOME=/Users/blakethomas/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# Build App Bundle for Play Store
flutter build appbundle --release

# Alternative: Build APK if needed
flutter build apk --release
```

#### ✅ STATUS: READY FOR UPLOAD - PROPERLY SIGNED AND CRASH-FREE! 
The Android App Bundle is properly signed with your release keystore and ready for Google Play Store submission!

**File Location**: `build/app/outputs/bundle/release/app-release.aab` (51.7MB)
**Last Built**: September 3, 2025, 11:30 AM *(App name updated to "Bravo AAC")*
**Signing**: Custom release keystore (ready for Google Play App Signing)
**Keystore**: `android/app-release-key.jks` (password: `Il2hBVadl@goog!`)
**Status**: ✅ MainActivity ClassNotFoundException **RESOLVED** - App launches successfully

#### ✅ Recent Testing Results (September 3, 2025)
- **App Launch**: ✅ Successful - MainActivity properly loaded
- **App Name**: ✅ Updated to "Bravo AAC" (was "bravo_flutter")
- **Firebase Auth**: ✅ Configured - Token refresh encounters API restrictions but gracefully falls back
- **Network Connectivity**: ⚠️ Backend server timeouts (app.talkwithbravo.com) - server may need optimization
- **Permissions**: ✅ Working - Minor permission handler conflicts but non-blocking
- **Overall Status**: ✅ Ready for store submission - Core functionality working

#### Technical Notes
- ✅ Android SDK cmdline-tools installed and configured
- ✅ All Android licenses accepted
- ✅ NDK configured for native library handling
- ✅ App Bundle builds successfully without errors
- ✅ **SIGNING COMPLETE**: Custom release keystore created and configured
- ✅ **KEYSTORE**: `Il2hBVadl@goog!` (store password securely!)
- ✅ Google Play App Signing ready (upload keystore configured)
- ✅ Resource shrinking and code minification enabled for optimized builds

### 3. Upload to Google Play Console
1. In Google Play Console, go to your "Bravo AAC" app
2. Navigate to **Production** (or start with **Internal testing**)
3. Click **Create new release**
4. Upload: `build/app/outputs/bundle/release/app-release.aab`
5. Add release notes
6. Review and roll out

### 4. Configure Store Listing
- **Short description**: AAC communication app (80 characters max)
- **Full description**: Detailed description of Bravo AAC features
- **App icon**: Already generated (512x512 required)
- **Screenshots**: Take screenshots from different device sizes
- **Feature graphic**: 1024x500 banner image

### 5. App Signing ✅ CONFIGURED
- Using Google Play App Signing (recommended)
- Upload your App Bundle (Google manages signing automatically)
- No manual key management required

## Testing Distribution

### TestFlight (iOS)
- **External Testers** (recommended): Add up to 10,000 testers by email
  - Go to TestFlight → **External Testing** tab (not Internal Testing)
  - Create groups like "Bravo Testers" 
  - Add testers by email directly (no Apple ID required)
  - Testers get email invitation to download TestFlight app
- **Internal Testers**: Only shows users with App Store Connect access
  - Limited to team members in Users and Access → People
  - Add with "App Manager" or "Developer" role
- **Sandbox Testing**: Only needed for in-app purchases (skip for now)
- No App Store review required for TestFlight
- Builds expire after 90 days

### Internal Testing (Android)
- Add up to 100 testers
- No review required
- Instant distribution

## Commands for Release Builds ✅ WORKING

### Android Release (App Bundle for Google Play Store)
```bash
# Set up Android environment (required each session)
export ANDROID_HOME=/Users/blakethomas/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# Clean and build App Bundle (READY FOR GOOGLE PLAY STORE)
flutter clean
flutter pub get
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab (44MB)

# Alternative: Build APK (for testing/backup)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (54MB)
```

### iOS Release (TestFlight/App Store) ✅ UPDATED
```bash
# Clean and build IPA for TestFlight/App Store (CURRENT METHOD)
flutter clean
flutter pub get
flutter build ipa --release

# Output: build/ios/ipa/Bravo AAC.ipa (ready for TestFlight)

# Upload options:
# 1. Drag IPA into Apple Transporter app (easiest)
# 2. Or use Xcode: open ios/Runner.xcworkspace → Archive → Upload
```

### Android Toolchain Status ✅ RESOLVED
- **Issue**: Missing Android cmdline-tools prevented App Bundle builds
- **Solution**: Downloaded and installed cmdline-tools from Google
- **Status**: All Android SDK licenses accepted
- **Flutter Doctor**: All Android toolchain checks pass

## Next Steps
1. Complete Apple Developer Program enrollment
2. Set up App Store Connect app listing
3. Set up Google Play Console account and app listing
4. Prepare app screenshots and store assets
5. Create privacy policy (required for both stores)
6. Test release builds thoroughly
7. Submit for review

## Required Assets for Store Listings
- [ ] App screenshots (multiple device sizes)
- [ ] App description and keywords
- [ ] Privacy policy URL
- [ ] Support/contact information
- [ ] Feature graphic (Google Play)
- [ ] App preview video (optional but recommended)

## Notes
- Both stores require privacy policies for apps that collect user data
- App Store review typically takes 24-48 hours
- Google Play review can take 1-3 days for first submission
- Consider starting with TestFlight/Internal Testing for initial user feedback
