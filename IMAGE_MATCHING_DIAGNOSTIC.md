## Image Matching Diagnostic Report

### Issue
Images not matching in Prod environment on iPad Tap Interface, but working in:
- Dev environment (Flutter app)
- Prod environment (Web app)

### Root Cause Analysis

#### Environment Configuration
- **Flutter App Prod Project**: `bravo-prod-465323` (from environment_config.dart)
- **Backend Prod Project**: Uses `GCP_PROJECT_ID` env var, defaults to `bravo-prod-project`
- **Web App**: Uses `app.talkwithbravo.com` successfully

#### The Issue
The production backend may be connecting to a **different Firestore database** than dev/test environments:

1. **Dev/Test**: Uses `bravo-test-465400` or `bravo-dev-465400` Firestore
2. **Prod**: Should use `bravo-prod-465323` Firestore but backend defaults to `bravo-prod-project`

If the prod Firestore database (`bravo-prod-465323`) has:
- Different image collections
- Empty/incomplete `aac_images` collection  
- Different image URLs
- Missing images that exist in dev/test

Then the Flutter app won't find matching images!

### Diagnostic Steps

#### Step 1: Check what the backend is actually using
Run on iPad with debug enabled:
```dart
dart test_image_matching_diagnostic.dart
```

This will show:
- What API endpoint it's hitting
- What responses it's getting
- Whether images are being returned

#### Step 2: Compare API responses
Test the same word in both environments:

**Dev**: `https://dev.talkwithbravo.com/api/imagecreator/search?tag=cat&limit=5`
**Prod**: `https://app.talkwithbravo.com/api/imagecreator/search?tag=cat&limit=5`

If prod returns **empty results** or **different images**, the Firestore database is the issue.

#### Step 3: Verify Firestore collections
Check in Firebase Console:
- Go to `bravo-prod-465323` project
- Check `aac_images` collection
- Verify it has documents with `source == "bravo_images"`
- Compare count with dev/test environment

### Potential Solutions

#### Solution 1: Copy images from dev/test to prod
If prod database is empty, copy the `aac_images` collection from dev/test to prod.

#### Solution 2: Backend configuration fix
Ensure the production backend is using the correct project ID (`bravo-prod-465323`):
- Check backend environment variables
- Verify `GCP_PROJECT_ID` is set to `bravo-prod-465323`
- Check service account key is for the correct project

#### Solution 3: Use shared image database
If images should be shared across environments, configure all environments to use the same Firestore database for the `aac_images` collection.

### Next Steps

1. Run the diagnostic script to see what the API is actually returning
2. Check the Firebase Console to verify the prod database has images
3. Let me know what you find and we can determine the right fix

### Test Commands

```bash
# Run diagnostic on iPad
cd /Users/blakethomas/Documents/BravoGCPFlutter2/bravo_flutter
dart test_image_matching_diagnostic.dart

# Check current environment
grep "_currentEnvironment" lib/config/environment_config.dart

# Rebuild and deploy
./scripts/deploy_to_ipad.sh prod
```
