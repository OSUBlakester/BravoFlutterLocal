#!/bin/bash

# Build script for different environments
# Usage: ./scripts/build_environment.sh [dev|test|prod] [platform]
# Example: ./scripts/build_environment.sh dev web
#          ./scripts/build_environment.sh prod ios

ENVIRONMENT=$1
PLATFORM=$2

if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 [dev|test|prod] [platform]"
    echo "Platforms: web, ios, android, macos, windows, linux"
    exit 1
fi

if [ -z "$PLATFORM" ]; then
    echo "Usage: $0 [dev|test|prod] [platform]"
    echo "Platforms: web, ios, android, macos, windows, linux"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
    echo "Error: Environment must be dev, test, or prod"
    exit 1
fi

# Validate platform
if [[ ! "$PLATFORM" =~ ^(web|ios|android|macos|windows|linux)$ ]]; then
    echo "Error: Platform must be web, ios, android, macos, windows, or linux"
    exit 1
fi

echo "🏗️  Building for Environment: $ENVIRONMENT, Platform: $PLATFORM"

# Update environment in config file
ENV_CONFIG_FILE="lib/config/environment_config.dart"

case $ENVIRONMENT in
    dev)
        ENV_ENUM="Environment.dev"
        ;;
    test)
        ENV_ENUM="Environment.test"
        ;;
    prod)
        ENV_ENUM="Environment.prod"
        ;;
esac

# Create backup of current config
cp "$ENV_CONFIG_FILE" "$ENV_CONFIG_FILE.backup"

# Update the environment in the config file
sed -i.tmp "s/static const Environment _currentEnvironment = Environment\.[a-z]*/static const Environment _currentEnvironment = $ENV_ENUM/" "$ENV_CONFIG_FILE"
rm "$ENV_CONFIG_FILE.tmp"

echo "✅ Updated environment to $ENVIRONMENT"

# Build based on platform
case $PLATFORM in
    web)
        echo "🌐 Building for Web..."
        flutter build web --release
        ;;
    ios)
        echo "📱 Building for iOS..."
        flutter build ios --release
        ;;
    android)
        echo "🤖 Building for Android..."
        flutter build apk --release
        ;;
    macos)
        echo "💻 Building for macOS..."
        flutter build macos --release
        ;;
    windows)
        echo "🪟 Building for Windows..."
        flutter build windows --release
        ;;
    linux)
        echo "🐧 Building for Linux..."
        flutter build linux --release
        ;;
esac

echo "✅ Build completed for $ENVIRONMENT environment on $PLATFORM platform"
echo "📁 Build output location varies by platform - check flutter build output above"

# Restore backup (optional - comment out if you want to keep the environment set)
# mv "$ENV_CONFIG_FILE.backup" "$ENV_CONFIG_FILE"
# echo "🔄 Restored original environment config"
