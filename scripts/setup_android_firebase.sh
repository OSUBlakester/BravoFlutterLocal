#!/bin/bash

# Setup Android Firebase Configuration
# This script helps you download and configure Firebase settings for Android

echo "🔥 Android Firebase Configuration Setup"
echo "============================================"
echo ""
echo "You need to download google-services.json files from Firebase Console for each environment:"
echo ""

# Firebase project URLs
echo "📋 Firebase Projects:"
echo "1. DEV:  https://console.firebase.google.com/project/bravo-dev-465400"
echo "2. TEST: https://console.firebase.google.com/project/bravo-test-465400"  
echo "3. PROD: https://console.firebase.google.com/project/bravo-prod-465323"
echo ""

echo "📱 Steps for EACH environment:"
echo "1. Go to the Firebase Console URL above"
echo "2. Click on the Android app icon (or 'Add app' if no Android app exists)"
echo "3. Use package name: com.bravoaac.bravo"
echo "4. Download the google-services.json file"
echo "5. Save it in the correct location (shown below)"
echo ""

# Create directories
FIREBASE_DIR="android/app/firebase_configs"
mkdir -p "$FIREBASE_DIR"

echo "📂 Required file locations:"
echo "   DEV:  $FIREBASE_DIR/google-services-dev.json"
echo "   TEST: $FIREBASE_DIR/google-services-test.json" 
echo "   PROD: $FIREBASE_DIR/google-services-prod.json"
echo ""

# Check which files exist
echo "📋 Current status:"
for env in dev test prod; do
    file="$FIREBASE_DIR/google-services-$env.json"
    if [ -f "$file" ]; then
        echo "   ✅ $env: $file (exists)"
    else
        echo "   ❌ $env: $file (missing)"
    fi
done

echo ""
echo "🔧 After downloading all files, run:"
echo "   ./scripts/switch_env.sh dev    # Switch to dev and configure Android"
echo ""
echo "💡 The switch_env.sh script will be updated to handle Android Firebase configs automatically."