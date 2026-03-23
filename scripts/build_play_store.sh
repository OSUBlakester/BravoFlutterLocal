#!/bin/bash

# Play Store Deployment Script for Bravo AAC
# This script builds an Android App Bundle (AAB) for Google Play Store upload

set -e  # Exit on any error

echo "🏪 Starting Play Store Build Process for Bravo AAC..."
echo "==============================================="

# Check current version
CURRENT_VERSION=$(grep "version:" pubspec.yaml | sed 's/version: //')
CURRENT_ANDROID_VERSION=$(grep "versionCode =" android/app/build.gradle.kts | sed 's/.*versionCode = //' | sed 's/$//')
echo "📋 Current Flutter version: $CURRENT_VERSION"
echo "📋 Current Android version code: $CURRENT_ANDROID_VERSION"

# Ask user if they want to increment version
echo ""
read -p "Do you want to increment both version numbers? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Extract current build number and increment it
    VERSION_NAME=$(echo $CURRENT_VERSION | cut -d'+' -f1)
    BUILD_NUMBER=$(echo $CURRENT_VERSION | cut -d'+' -f2)
    NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
    NEW_VERSION="${VERSION_NAME}+${NEW_BUILD_NUMBER}"
    
    echo "🔢 Incrementing Flutter version: $CURRENT_VERSION → $NEW_VERSION"
    sed -i.bak "s/version: $CURRENT_VERSION/version: $NEW_VERSION/" pubspec.yaml
    rm pubspec.yaml.bak
    
    echo "🔢 Incrementing Android version code: $CURRENT_ANDROID_VERSION → $NEW_BUILD_NUMBER"
    sed -i.bak "s/versionCode = $CURRENT_ANDROID_VERSION/versionCode = $NEW_BUILD_NUMBER/" android/app/build.gradle.kts
    rm android/app/build.gradle.kts.bak
    
    echo "✅ Both versions updated successfully!"
else
    echo "📋 Keeping current versions"
fi

echo ""
echo "🧹 Cleaning project..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

echo "⚠️ Skipping code analysis (contains non-fatal warnings)"
echo "Building directly for Play Store deployment..."

echo ""
echo "🤖 Building Android App Bundle (AAB) for Play Store..."
echo "⏳ This may take a few minutes..."

# Build the Android App Bundle
flutter build appbundle --release

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Android App Bundle built successfully!"
    echo "==============================================="
    echo "📱 AAB file location:"
    echo "   build/app/outputs/bundle/release/app-release.aab"
    echo ""
    echo "📊 File size:"
    ls -lh build/app/outputs/bundle/release/app-release.aab
    echo ""
    echo "🔍 Version verification:"
    echo "   Flutter version: $(grep "version:" pubspec.yaml | sed 's/version: //')"
    echo "   Android version code: $(grep "versionCode =" android/app/build.gradle.kts | sed 's/.*versionCode = //' | sed 's/$//')"
    echo ""
    echo "🚀 Next steps:"
    echo "1. Open Google Play Console (https://play.google.com/console)"
    echo "2. Go to your Bravo AAC app"
    echo "3. Create a new release"
    echo "4. Upload the AAB file: build/app/outputs/bundle/release/app-release.aab"
    echo "5. Fill in release notes and publish"
    echo ""
    echo "💡 Tip: Test the AAB on internal testing before production release!"
else
    echo ""
    echo "❌ Build failed! Please check the errors above."
    exit 1
fi
