# URL Update Summary: Migration to app.talkwithbravo.com

## Overview
Updated the Bravo AAC Flutter app to use `app.talkwithbravo.com` as the primary API URL instead of the root domain `talkwithbravo.com`. This change accommodates the new landing page on the root domain while maintaining app functionality through the dedicated subdomain.

## Changes Made

### 1. Environment Configuration
**File**: `lib/config/environment_config.dart`
- **Before**: `_prodApiUrl = 'https://bravo-aac-api-lnquhqxkjq-uc.a.run.app'`
- **After**: `_prodApiUrl = 'https://app.talkwithbravo.com'`

### 2. Test URLs in Main Application
**File**: `lib/main.dart`
- Updated all test URLs from `talkwithbravo.com` to `app.talkwithbravo.com`
- Maintained Cloud Run URL as backup fallback
- **Primary URLs now**: `https://app.talkwithbravo.com/*`
- **Backup URLs remain**: `https://bravo-aac-api-lnquhqxkjq-uc.a.run.app/*`

### 3. Build Scripts
**File**: `scripts/switch_env.sh`
- **Before**: `URL="https://talkwithbravo.com"`
- **After**: `URL="https://app.talkwithbravo.com"`

### 4. Backend Server Configuration
**File**: `existingbackend/server.py`
- Added `app.talkwithbravo.com` to allowed origins for CORS
- **Production ALLOWED_ORIGINS**: `['https://talkwithbravo.com', 'https://app.talkwithbravo.com']`
- **Production DOMAIN**: `app.talkwithbravo.com`
- **Test environment**: Also includes `app.talkwithbravo.com` in allowed origins

### 5. Frontend Admin Pages
Updated SERVER_URL in multiple admin HTML files:
- `existingfrontend/audio_admin.html`
- `existingfrontend/admin_audit_report.html`
- `existingfrontend/admin_pages.html`
- `existingfrontend/user_diary_admin.html`
- `existingfrontend/auth.html`

All now use: `const SERVER_URL = "https://app.talkwithbravo.com";`

## Strategy & Fallback Behavior

### Multi-Strategy Connection Approach
The app maintains its robust connection strategy through the `cruiseShipSafeGet` function:

1. **Strategy 1**: Try `app.talkwithbravo.com` (primary)
2. **Strategy 2**: Force HTTPS on port 443
3. **Strategy 3**: Try HTTP on port 80
4. **Strategy 4**: Try HTTPS on port 8443
5. **Strategy 5**: Fallback to Google Cloud Run backup endpoint

### Backward Compatibility
- Cloud Run URL remains as Strategy 5 backup
- Backend accepts both `talkwithbravo.com` and `app.talkwithbravo.com` origins
- No breaking changes for existing functionality

## Environment Mappings

| Environment | URL |
|-------------|-----|
| Development | `https://dev.talkwithbravo.com` |
| Test | `https://test.talkwithbravo.com` |
| Production | `https://app.talkwithbravo.com` |
| Backup | `https://bravo-aac-api-lnquhqxkjq-uc.a.run.app` |

## Testing
- ✅ Release build successful (56.6MB APK)
- ✅ All configuration files updated
- ✅ CORS configuration includes both domains
- ✅ Fallback strategy preserved

## Benefits
1. **Clean separation**: Landing page on root domain, app on subdomain
2. **Maintained reliability**: All fallback strategies preserved
3. **Professional setup**: Proper subdomain structure
4. **No downtime**: Gradual migration with backward compatibility
5. **Easy maintenance**: Centralized configuration through `EnvironmentConfig`

## Next Steps
1. Deploy backend with updated CORS settings
2. Configure DNS for `app.talkwithbravo.com` subdomain
3. Test app functionality with new URL
4. Monitor logs for any connection issues
5. Eventually phase out old URL references once stable

All changes are backward compatible and maintain the robust connection strategy that works well for cruise ship and restricted network environments.
