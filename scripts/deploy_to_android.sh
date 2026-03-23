#!/bin/bash

# Deploy script for installing app on Android devices (Fire tablet, Lenovo tab, etc.)
# Usage: ./scripts/deploy_to_android.sh [dev|test|prod] [device_name] [debug|release]
# Examples: 
#   ./scripts/deploy_to_android.sh prod fire debug
#   ./scripts/deploy_to_android.sh dev lenovo release
#   ./scripts/deploy_to_android.sh test  # Will show device list to choose from

ENVIRONMENT=$1
DEVICE_FILTER=$2
BUILD_MODE=$3

# Default to debug mode if not specified (since you've had success with debug)
if [ -z "$BUILD_MODE" ]; then
    BUILD_MODE="debug"
fi

# Known device configurations (add device IDs as you get them)
# Using regular variables instead of associative arrays for better shell compatibility
FIRE_DEVICE="amazon_fire_tablet"  # Will be updated with actual device ID
LENOVO_DEVICE="lenovo_tablet"     # Will be updated with actual device ID

if [ -z "$ENVIRONMENT" ]; then
    echo "📱 Android Deployment Script"
    echo ""
    echo "Usage: $0 [dev|test|prod] [device_name] [debug|release]"
    echo ""
    echo "Environment:"
    echo "  dev   - Development environment"
    echo "  test  - Test environment" 
    echo "  prod  - Production environment"
    echo ""
    echo "Device (optional):"
    echo "  fire   - Amazon Fire tablet"
    echo "  lenovo - Lenovo tablet"
    echo "  If no device specified, will show available devices"
    echo ""
    echo "Build Mode (optional, defaults to debug):"
    echo "  debug   - Debug build (faster, includes debug info)"
    echo "  release - Release build (optimized, smaller size)"
    echo ""
    echo "Examples:"
    echo "  $0 prod fire debug     # Deploy prod to Fire tablet (debug build)"
    echo "  $0 dev lenovo release  # Deploy dev to Lenovo tablet (release build)"
    echo "  $0 test                # Show device list for test deployment"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
    echo "❌ Error: Environment must be dev, test, or prod"
    exit 1
fi

# Validate build mode
if [[ ! "$BUILD_MODE" =~ ^(debug|release)$ ]]; then
    echo "❌ Error: Build mode must be debug or release (defaults to debug if not specified)"
    exit 1
fi

echo "🤖 Deploying $ENVIRONMENT environment to Android device (${BUILD_MODE} build)..."

# Check if ADB is available
if ! command -v adb &> /dev/null; then
    echo "❌ ADB not found. Please install Android SDK platform-tools."
    echo "💡 You can install it via:"
    echo "   brew install android-platform-tools"
    echo "   Or download from: https://developer.android.com/studio/releases/platform-tools"
    exit 1
fi

# Check for connected devices
echo "🔍 Checking for connected Android devices..."
CONNECTED_DEVICES=$(adb devices | grep -v "List of devices attached" | grep -v "^$" | grep "device$")

if [ -z "$CONNECTED_DEVICES" ]; then
    echo "❌ No Android devices found."
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "1. Enable 'Developer Options' on your Android device:"
    echo "   - Go to Settings → About tablet/phone"
    echo "   - Tap 'Build number' 7 times"
    echo "2. Enable 'USB Debugging' in Developer Options"
    echo "3. Connect your device via USB"
    echo "4. Accept the 'USB Debugging' prompt on your device"
    echo "5. For Fire tablets: Enable 'Apps from Unknown Sources'"
    echo ""
    echo "Run 'adb devices' to verify connection."
    exit 1
fi

echo "✅ Found connected Android devices:"
echo "$CONNECTED_DEVICES"
echo ""

# If device filter specified, try to find matching device
SELECTED_DEVICE=""
if [ -n "$DEVICE_FILTER" ]; then
    # Check if we have a known device mapping
    case "$DEVICE_FILTER" in
        "fire")
            KNOWN_ID="$FIRE_DEVICE"
            ;;
        "lenovo")
            KNOWN_ID="$LENOVO_DEVICE"
            ;;
        *)
            KNOWN_ID=""
            ;;
    esac
    
    if [ -n "$KNOWN_ID" ] && echo "$CONNECTED_DEVICES" | grep -q "$KNOWN_ID"; then
        # Check if the known device is connected
        SELECTED_DEVICE="$KNOWN_ID"
        echo "🎯 Selected known device: $DEVICE_FILTER ($KNOWN_ID)"
    else
        # Try to match by device name/model
        DEVICE_LINE=$(echo "$CONNECTED_DEVICES" | grep -i "$DEVICE_FILTER" | head -n 1)
        if [ -n "$DEVICE_LINE" ]; then
            SELECTED_DEVICE=$(echo "$DEVICE_LINE" | awk '{print $1}')
            echo "🎯 Selected device matching '$DEVICE_FILTER': $SELECTED_DEVICE"
        elif [ -n "$KNOWN_ID" ]; then
            echo "⚠️  Known device '$DEVICE_FILTER' not found in connected devices."
            echo "📝 You may need to update the device ID in this script."
        fi
    fi
fi

# If no device selected, show list and let user choose
if [ -z "$SELECTED_DEVICE" ]; then
    echo "📱 Available devices:"
    i=1
    declare -a DEVICE_LIST
    while IFS= read -r line; do
        DEVICE_ID=$(echo "$line" | awk '{print $1}')
        DEVICE_LIST[$i]="$DEVICE_ID"
        
        # Get device info
        DEVICE_MODEL=$(adb -s "$DEVICE_ID" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        DEVICE_BRAND=$(adb -s "$DEVICE_ID" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
        
        echo "  $i) $DEVICE_ID ($DEVICE_BRAND $DEVICE_MODEL)"
        ((i++))
    done <<< "$CONNECTED_DEVICES"
    
    echo ""
    echo -n "Select device (1-$((i-1))): "
    read DEVICE_CHOICE
    
    if [[ "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] && [ "$DEVICE_CHOICE" -ge 1 ] && [ "$DEVICE_CHOICE" -lt "$i" ]; then
        SELECTED_DEVICE="${DEVICE_LIST[$DEVICE_CHOICE]}"
        echo "✅ Selected device: $SELECTED_DEVICE"
    else
        echo "❌ Invalid selection."
        exit 1
    fi
fi

echo ""
echo "🎯 Target device: $SELECTED_DEVICE"

# Get device info for confirmation
DEVICE_MODEL=$(adb -s "$SELECTED_DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
DEVICE_BRAND=$(adb -s "$SELECTED_DEVICE" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
ANDROID_VERSION=$(adb -s "$SELECTED_DEVICE" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')

echo "📱 Device Info: $DEVICE_BRAND $DEVICE_MODEL (Android $ANDROID_VERSION)"

# Switch to the specified environment
echo ""
echo "🔄 Switching to $ENVIRONMENT environment..."
./scripts/switch_env.sh $ENVIRONMENT

# Clean previous builds to avoid caching issues
echo ""
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get

# Build APK with verbose output
echo ""
echo "🏗️  Building Android APK for $ENVIRONMENT (${BUILD_MODE} mode)..."

# Set APK path based on build mode
if [ "$BUILD_MODE" = "debug" ]; then
    BUILD_FLAG="--debug"
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
else
    BUILD_FLAG="--release"
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
fi

if ! flutter build apk $BUILD_FLAG --verbose; then
    echo "❌ Build failed. Please check the error messages above."
    echo "💡 Common fixes:"
    echo "   1. Check Android SDK is properly installed"
    echo "   2. Verify build.gradle configuration"
    echo "   3. Try 'flutter doctor' to check setup"
    echo "   4. For release builds, ensure signing configuration is correct"
    echo "   5. Try debug mode: ./scripts/deploy_to_android.sh $ENVIRONMENT $DEVICE_FILTER debug"
    exit 1
fi

# Wait a moment for build to complete
sleep 2

# Install on Android device with retry logic
echo ""
echo "📲 Installing app on Android device..."

if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK not found at $APK_PATH"
    echo "💡 Build may have failed. Check the build output above."
    exit 1
fi

echo "📦 APK found: $APK_PATH"
echo "📲 Installing on $SELECTED_DEVICE..."

# Try installation with retries
for i in {1..3}; do
    echo "🔄 Installation attempt $i/3..."
    
    # Uninstall previous version first (ignore errors)
    adb -s "$SELECTED_DEVICE" uninstall com.example.bravo_flutter 2>/dev/null
    
    # Install new version
    if adb -s "$SELECTED_DEVICE" install "$APK_PATH"; then
        echo ""
        echo "✅ Successfully deployed $ENVIRONMENT environment to Android device!"
        echo "📱 App package: com.example.bravo_flutter"
        echo "🎯 Device: $DEVICE_BRAND $DEVICE_MODEL"
        echo ""
        echo "🚀 The app is now installed and ready to use!"
        echo ""
        echo "🎯 Current Environment Details:"
        ./scripts/show_env.sh
        echo ""
        echo "💡 To update device shortcuts in this script, add:"
        echo "   KNOWN_DEVICES[\"$(echo $DEVICE_FILTER | tr '[:upper:]' '[:lower:]')\"]=\"$SELECTED_DEVICE\""
        exit 0
    else
        echo "⚠️  Installation attempt $i failed."
        if [ $i -lt 3 ]; then
            echo "🔄 Retrying in 3 seconds..."
            sleep 3
        fi
    fi
done

echo ""
echo "❌ Installation failed after 3 attempts."
echo ""
echo "🔧 Troubleshooting steps:"
echo "1. Check USB connection and try reconnecting"
echo "2. Ensure 'USB Debugging' is still enabled"
echo "3. For Fire tablets: Make sure 'Apps from Unknown Sources' is enabled"
echo "4. Try installing manually: adb -s $SELECTED_DEVICE install $APK_PATH"
echo "5. Check device storage space"
echo "6. Reboot the device and try again"
echo ""
echo "🆔 Device ID for future reference: $SELECTED_DEVICE"
exit 1
