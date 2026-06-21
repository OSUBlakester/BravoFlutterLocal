#!/bin/bash

# Deploy script for installing app on iPad
# Usage: ./scripts/deploy_to_ipad.sh [dev|test|prod]
# Example: ./scripts/deploy_to_ipad.sh prod

ENVIRONMENT=$1

if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 [dev|test|prod] [device_id]"
    echo "Example: $0 prod"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
    echo "Error: Environment must be dev, test, or prod"
    exit 1
fi

echo "📱 Deploying $ENVIRONMENT environment to iPad..."

# Check if iPad is connected
echo "🔍 Checking for connected devices..."
DEVICES_OUTPUT=$(flutter devices)
echo "$DEVICES_OUTPUT"

# Auto-detect connected iOS device
IPAD_DEVICE_ID=$2
if [ -z "$IPAD_DEVICE_ID" ]; then
    # Try to find a physically connected iOS device first (excluding wireless)
    IPAD_DEVICE_ID=$(echo "$DEVICES_OUTPUT" | grep -i "ios" | grep -v "wireless" | head -n 1 | awk -F' • ' '{print $2}' | tr -d ' ')
    
    # Fallback to wireless iOS device if no physical device is connected
    if [ -z "$IPAD_DEVICE_ID" ]; then
        IPAD_DEVICE_ID=$(echo "$DEVICES_OUTPUT" | grep -i "ios" | head -n 1 | awk -F' • ' '{print $2}' | tr -d ' ')
    fi
fi

if [ -z "$IPAD_DEVICE_ID" ]; then
    echo "❌ No iOS device detected. Please make sure your iPad is connected and trusted."
    echo "💡 Try disconnecting and reconnecting the iPad, then run 'flutter devices' to verify."
    exit 1
fi

DEVICE_NAME=$(echo "$DEVICES_OUTPUT" | grep "$IPAD_DEVICE_ID" | head -n 1 | awk -F' • ' '{print $1}' | xargs)
echo "✅ iOS Device detected: $DEVICE_NAME ($IPAD_DEVICE_ID)"

# Switch to the specified environment
echo "🔄 Switching to $ENVIRONMENT environment..."
./scripts/switch_env.sh $ENVIRONMENT

# Verify the environment switch worked
if [ $? -ne 0 ]; then
    echo "❌ Environment switch failed"
    exit 1
fi

case $ENVIRONMENT in
    dev)
        BUILD_CONFIG="Debug-Dev"
        ;;
    test)
        BUILD_CONFIG="Debug-Test"
        ;;
    prod)
        BUILD_CONFIG="Release-Prod"
        ;;
esac

# Then use the configuration in your build command:
flutter build ios --release --flavor $ENVIRONMENT

# Clean previous builds to avoid caching issues
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get

# Build for iOS with verbose output
echo "🏗️  Building iOS app for $ENVIRONMENT..."
if ! flutter build ios --release --verbose; then
    echo "❌ Build failed. Please check the error messages above."
    echo "💡 Try opening Xcode and building manually: open ios/Runner.xcworkspace"
    exit 1
fi

# Wait a moment for build to complete
sleep 2

# Install on iPad with retry logic
echo "📲 Installing app on iPad..."
echo "🔄 Attempting installation..."

# Try installation with retries
for i in {1..3}; do
    echo "📲 Installation attempt $i/3..."
    if flutter install -d "$IPAD_DEVICE_ID"; then
        echo "✅ Successfully deployed $ENVIRONMENT environment to iPad!"
        echo "📱 The app is now installed and can run independently."
        echo ""
        echo "🎯 Current Environment Details:"
        ./scripts/show_env.sh
        exit 0
    else
        echo "⚠️  Installation attempt $i failed."
        if [ $i -lt 3 ]; then
            echo "🔄 Retrying in 3 seconds..."
            sleep 3
        fi
    fi
done

echo "❌ Installation failed after 3 attempts."
echo "🔧 Troubleshooting steps:"
echo "1. Disconnect and reconnect the iPad"
echo "2. Make sure the iPad is unlocked and 'Trust this computer' is confirmed"
echo "3. Try building and installing through Xcode: open ios/Runner.xcworkspace"
echo "4. Check that the iPad has enough storage space"
exit 1