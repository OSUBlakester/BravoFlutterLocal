#!/bin/bash

# Show current environment status
# Usage: ./scripts/show_env.sh

ENV_CONFIG_FILE="lib/config/environment_config.dart"

if [ ! -f "$ENV_CONFIG_FILE" ]; then
    echo "❌ Environment config file not found: $ENV_CONFIG_FILE"
    exit 1
fi

# Extract current environment from config file
CURRENT_ENV=$(grep "_currentEnvironment = Environment\." "$ENV_CONFIG_FILE" | sed 's/.*Environment\.\([a-z]*\).*/\1/')

case $CURRENT_ENV in
    dev)
        PROJECT="bravo-dev-465400"
        URL="https://dev.talkwithbravo.com"
        FIREBASE_DOMAIN="bravo-dev-465400.firebaseapp.com"
        BUNDLE_ID="com.talkwithbravo.bravodev"
        ;;
    test)
        PROJECT="bravo-test-465400"
        URL="https://test.talkwithbravo.com"
        FIREBASE_DOMAIN="bravo-test-465400.firebaseapp.com"
        BUNDLE_ID="com.talkwithbravo.bravotest"
        ;;
    prod)
        PROJECT="bravo-prod-465323"
        URL="https://talkwithbravo.com"
        FIREBASE_DOMAIN="bravo-prod-465323.firebaseapp.com"
        BUNDLE_ID="com.talkwithbravo.bravoprod"
        ;;
    *)
        echo "❌ Unknown environment: $CURRENT_ENV"
        exit 1
        ;;
esac

echo "🎯 Current Environment: $CURRENT_ENV"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Project ID:      $PROJECT"
echo "🌐 API URL:         $URL"
echo "🔥 Firebase Domain: $FIREBASE_DOMAIN"
echo "📱 Bundle ID:       $BUNDLE_ID"
echo ""
echo "🔄 To switch environments:"
echo "   ./scripts/switch_env.sh [dev|test|prod]"
echo ""
echo "🚀 To build:"
echo "   ./scripts/build_environment.sh $CURRENT_ENV [web|ios|android|macos|windows|linux]"
echo ""
echo "▶️  To run:"
echo "   flutter run"
