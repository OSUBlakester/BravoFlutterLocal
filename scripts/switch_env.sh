#!/bin/bash

# Switch environment script
# Usage: ./scripts/switch_env.sh [dev|test|prod]
# Example: ./scripts/switch_env.sh dev

ENVIRONMENT=$1

if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 [dev|test|prod]"
    echo "Current environment can be found in lib/config/environment_config.dart"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
    echo "Error: Environment must be dev, test, or prod"
    exit 1
fi

ENV_CONFIG_FILE="lib/config/environment_config.dart"
IOS_RUNNER_DIR="ios/Runner"
IOS_PROJECT_FILE="ios/Runner.xcodeproj/project.pbxproj"
ANDROID_APP_DIR="android/app"
ANDROID_FIREBASE_DIR="android/app/firebase_configs"

case $ENVIRONMENT in
    dev)
        ENV_ENUM="Environment.dev"
        URL="https://dev.talkwithbravo.com"
        PROJECT="bravo-dev-465400"
        PLIST_FILE="GoogleService-Info-dev.plist"
        ANDROID_JSON_FILE="google-services-dev.json"
        BUNDLE_ID="com.talkwithbravo.bravodev"
        ;;
    test)
        ENV_ENUM="Environment.test"
        URL="https://test.talkwithbravo.com"
        PROJECT="bravo-test-465400"
        PLIST_FILE="GoogleService-Info-test.plist"
        ANDROID_JSON_FILE="google-services-test.json"
        BUNDLE_ID="com.talkwithbravo.bravotest"
        ;;
    prod)
        ENV_ENUM="Environment.prod"
        URL="https://app.talkwithbravo.com"
        PROJECT="bravo-prod-465323"
        PLIST_FILE="GoogleService-Info-prod.plist"
        ANDROID_JSON_FILE="google-services-prod.json"
        BUNDLE_ID="com.talkwithbravo.bravoprod"
        ;;
esac

echo "🔄 Switching to $ENVIRONMENT environment..."
echo "   📋 Project: $PROJECT"
echo "   🌐 API URL: $URL"
echo "   📱 iOS Firebase Config: $PLIST_FILE"
echo "   🤖 Android Firebase Config: $ANDROID_JSON_FILE"
echo "   📦 Bundle ID: $BUNDLE_ID"

# Create backup of current config
cp "$ENV_CONFIG_FILE" "$ENV_CONFIG_FILE.backup"

# Update the environment in the config file
sed -i.tmp "s/static const Environment _currentEnvironment = Environment\.[a-z]*/static const Environment _currentEnvironment = $ENV_ENUM/" "$ENV_CONFIG_FILE"
rm "$ENV_CONFIG_FILE.tmp"

# Update bundle ID in iOS project (both regular and sdk-specific entries)
echo "📦 Updating bundle ID to: $BUNDLE_ID"
sed -i.tmp "s/PRODUCT_BUNDLE_IDENTIFIER = com\.talkwithbravo\.bravo[a-z]*/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID/g" "$IOS_PROJECT_FILE"
sed -i.tmp2 "s/\"PRODUCT_BUNDLE_IDENTIFIER\[sdk=\*\]\" = com\.talkwithbravo\.bravo[a-z]*/\"PRODUCT_BUNDLE_IDENTIFIER[sdk=*]\" = $BUNDLE_ID/g" "$IOS_PROJECT_FILE"
rm "$IOS_PROJECT_FILE.tmp" "$IOS_PROJECT_FILE.tmp2"

# Switch Firebase configuration for iOS
if [ -f "$IOS_RUNNER_DIR/$PLIST_FILE" ]; then
    echo "🔥 Switching iOS Firebase config to $PLIST_FILE"
    # Remove existing symlink/file
    rm -f "$IOS_RUNNER_DIR/GoogleService-Info.plist"
    # Create new symlink to environment-specific config
    ln -s "$PLIST_FILE" "$IOS_RUNNER_DIR/GoogleService-Info.plist"
    echo "✅ iOS Firebase config switched"
else
    echo "⚠️  Warning: $IOS_RUNNER_DIR/$PLIST_FILE not found!"
    echo "   Please download the Firebase config file for $ENVIRONMENT environment"
    echo "   from Firebase Console and save it as $PLIST_FILE"
fi

# Switch Firebase configuration for Android
if [ -f "$ANDROID_FIREBASE_DIR/$ANDROID_JSON_FILE" ]; then
    echo "🤖 Switching Android Firebase config to $ANDROID_JSON_FILE"
    # Remove existing file
    rm -f "$ANDROID_APP_DIR/google-services.json"
    # Create new symlink to environment-specific config
    ln -s "firebase_configs/$ANDROID_JSON_FILE" "$ANDROID_APP_DIR/google-services.json"
    echo "✅ Android Firebase config switched"
else
    echo "⚠️  Warning: $ANDROID_FIREBASE_DIR/$ANDROID_JSON_FILE not found!"
    echo "   Please download the Android Firebase config file for $ENVIRONMENT environment"
    echo "   from Firebase Console and save it as $ANDROID_JSON_FILE"
    echo "   Run: ./scripts/setup_android_firebase.sh for detailed instructions"
fi

echo "✅ Environment switched to $ENVIRONMENT"
echo "🔥 You can now run: flutter run"
echo "📱 Or build with: ./scripts/build_environment.sh $ENVIRONMENT [platform]"