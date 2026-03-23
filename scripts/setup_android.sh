#!/bin/bash

# Android Setup Helper Script
# This script helps set up Android development tools for Flutter

echo "🤖 Android Development Setup Helper"
echo ""

# Check if brew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Please install Homebrew first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# Check if ADB is installed
if command -v adb &> /dev/null; then
    echo "✅ ADB is already installed"
    ADB_VERSION=$(adb version | head -n 1)
    echo "   $ADB_VERSION"
else
    echo "📦 Installing Android Platform Tools (includes ADB)..."
    brew install android-platform-tools
    echo "✅ Android Platform Tools installed"
fi

echo ""

# Check Flutter Android setup
echo "🔍 Checking Flutter Android setup..."
flutter doctor --android-licenses 2>/dev/null | head -n 5

echo ""
echo "🎯 Flutter doctor output for Android:"
flutter doctor | grep -A 5 -B 1 "Android"

echo ""
echo "📱 Connected Android devices:"
adb devices

echo ""
echo "🔧 Setup Instructions:"
echo ""
echo "For Fire Tablets:"
echo "1. Enable Developer Options:"
echo "   - Go to Settings → Device Options → About Fire Tablet"
echo "   - Tap 'Serial Number' 7 times"
echo "2. Enable ADB Debugging:"
echo "   - Go to Settings → Device Options → Developer Options"
echo "   - Turn on 'Enable ADB'"
echo "3. Allow Unknown Sources:"
echo "   - Go to Settings → Security & Privacy"
echo "   - Turn on 'Apps from Unknown Sources'"
echo ""
echo "For other Android devices:"
echo "1. Enable Developer Options:"
echo "   - Go to Settings → About phone/tablet"
echo "   - Tap 'Build number' 7 times"
echo "2. Enable USB Debugging:"
echo "   - Go to Settings → Developer Options"
echo "   - Turn on 'USB Debugging'"
echo ""
echo "🚀 Once setup is complete, you can deploy using:"
echo "   ./scripts/deploy_to_android.sh prod fire"
echo "   ./scripts/deploy_to_android.sh dev lenovo"
echo ""
