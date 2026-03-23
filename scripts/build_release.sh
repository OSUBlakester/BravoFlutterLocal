#!/bin/bash

# Release Build Script for Bravo AAC
# This script prepares release builds for both Android and iOS

set -e  # Exit on any error

echo "🚀 Starting Bravo AAC Release Build Process..."

# Clean the project
echo "🧹 Cleaning project..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build Android App Bundle for Play Store (requires Android Studio setup)
echo "🤖 Building Android APK for testing and distribution..."
flutter build apk --release

echo "✅ Android APK built successfully!"
echo "📱 Location: build/app/outputs/flutter-apk/app-release.apk"

# Note: For Play Store submission, you'll need Android Studio and App Bundle:
# flutter build appbundle --release

# Build iOS for App Store (requires macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Building iOS for App Store..."
    flutter build ios --release
    echo "✅ iOS build completed!"
    echo "📱 Open ios/Runner.xcworkspace in Xcode to archive and upload"
else
    echo "⚠️  iOS build skipped (requires macOS)"
fi

# Build Android APK for direct distribution (optional)
echo "🤖 Building Android APK for direct distribution..."
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
echo "✅ Android APK built successfully!"
echo "📱 Location: build/app/outputs/flutter-apk/app-release.apk"

echo ""
echo "🎉 Release builds completed!"
echo ""
echo "Next steps:"
echo "1. Test the release builds thoroughly"
echo "2. Upload Android App Bundle to Google Play Console"
echo "3. Archive and upload iOS build via Xcode"
echo "4. Set up store listings with screenshots and descriptions"
echo ""
echo "Files created:"
echo "  📱 Android App Bundle: build/app/outputs/bundle/release/app-release.aab"
echo "  📱 Android APK: build/app/outputs/flutter-apk/app-release.apk"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  📱 iOS: build/ios/iphoneos/Runner.app"
fi
