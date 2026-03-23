#!/bin/bash

# Script to increment iOS build number for TestFlight uploads
# Usage: ./scripts/increment_version.sh

echo "🔄 Incrementing iOS build number..."

# Get current version from pubspec.yaml
CURRENT_VERSION=$(grep "version:" pubspec.yaml | sed 's/version: //')
VERSION_NUMBER=$(echo $CURRENT_VERSION | cut -d'+' -f1)
BUILD_NUMBER=$(echo $CURRENT_VERSION | cut -d'+' -f2)

# Increment build number
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="${VERSION_NUMBER}+${NEW_BUILD_NUMBER}"

echo "📝 Current version: $CURRENT_VERSION"
echo "📝 New version: $NEW_VERSION"

# Update pubspec.yaml
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/version: $CURRENT_VERSION/version: $NEW_VERSION/" pubspec.yaml
else
    # Linux
    sed -i "s/version: $CURRENT_VERSION/version: $NEW_VERSION/" pubspec.yaml
fi

echo "✅ Updated pubspec.yaml with build number $NEW_BUILD_NUMBER"
echo "🚀 Ready to build with: flutter build ipa --export-method development"