# Multi-Environment Setup for Bravo AAC Flutter App

This document explains how to use the multi-environment configuration for the Bravo AAC Flutter application.

## 🏗 Environment Configuration

The app supports three environments:
- **Development** (`dev`) - bravo-dev-465400 → dev.talkwithbravo.com  
- **Test** (`test`) - bravo-test-465400 → test.talkwithbravo.com
- **Production** (`prod`) - bravo-prod-465323 → talkwithbravo.com

## 🔄 Switching Environments

### Method 1: Using Scripts (Recommended)
```bash
# Switch to development
./scripts/switch_env.sh dev

# Switch to test  
./scripts/switch_env.sh test

# Switch to production
./scripts/switch_env.sh prod
```

### Method 2: Manual Configuration
Edit `lib/config/environment_config.dart` and change:
```dart
static const Environment _currentEnvironment = Environment.dev; // Change this line
```

### Method 3: VS Code Launch Configurations
Use the predefined launch configurations in VS Code:
- "Flutter (Dev)" - Automatically switches to dev and launches
- "Flutter (Test)" - Automatically switches to test and launches  
- "Flutter (Prod)" - Automatically switches to prod and launches
- "Flutter (Current Env)" - Uses current environment setting

## 🚀 Building for Different Environments

### Using Build Script
```bash
# Build dev for web
./scripts/build_environment.sh dev web

# Build test for iOS
./scripts/build_environment.sh test ios

# Build prod for Android
./scripts/build_environment.sh prod android
```

### Using VS Code Tasks
- `Ctrl+Shift+P` → "Tasks: Run Task"
- Select build task like "build-dev-web", "build-test-web", etc.

### Manual Flutter Commands
```bash
# Make sure environment is set correctly first
./scripts/switch_env.sh dev

# Then build normally
flutter build web --release
flutter build ios --release
flutter build apk --release
```

## 📱 Platform Support

The app supports all Flutter platforms:
- **Web** - Chrome, Safari, Firefox, Edge
- **iOS** - iPhone, iPad
- **Android** - Phones, Tablets  
- **macOS** - Desktop app
- **Windows** - Desktop app
- **Linux** - Desktop app

## 🔧 Environment Details

### Development Environment
- **Project ID**: bravo-dev-465400
- **API URL**: https://dev.talkwithbravo.com
- **Firebase**: Configured for development testing
- **Bundle ID**: com.talkwithbravo.bravodev

### Test Environment  
- **Project ID**: bravo-test-465400
- **API URL**: https://test.talkwithbravo.com
- **Firebase**: Configured for UAT testing
- **Bundle ID**: com.talkwithbravo.bravotest

### Production Environment
- **Project ID**: bravo-prod-465323  
- **API URL**: https://talkwithbravo.com
- **Firebase**: Live production configuration
- **Bundle ID**: com.talkwithbravo.bravoprod

## 🐛 Troubleshooting

### Firebase Connection Issues
1. Verify the environment is set correctly
2. Check console logs for Firebase initialization
3. Ensure all Firebase config values are correct

### API Connection Issues  
1. Verify the API URL for your environment
2. Check network connectivity to the environment
3. Confirm backend is deployed to the target environment

### Build Issues
1. Run `flutter clean` before building
2. Make sure you're on the correct environment
3. Check that all dependencies are installed

## 📋 Quick Commands

```bash
# Check current environment (look for _currentEnvironment)
grep "_currentEnvironment" lib/config/environment_config.dart

# Quick dev build and run
./scripts/switch_env.sh dev && flutter run -d chrome

# Quick production build
./scripts/build_environment.sh prod web

# Reset to original config (if you have backup)
cp lib/config/environment_config.dart.backup lib/config/environment_config.dart
```

## 🔐 Security Notes

- Never commit sensitive Firebase keys to version control in production
- Consider using environment variables for sensitive configuration in CI/CD
- Use different signing certificates for each environment on mobile platforms

## 📞 Support

For issues with environment configuration, check:
1. Firebase console for each project
2. GCP console for backend deployments  
3. DNS configuration for custom domains
