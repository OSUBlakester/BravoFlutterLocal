# 🚢 Cruise Ship Network Troubleshooting Guide

## Problem: "Connection reset by peer" with port 58448

This is a common issue on cruise ship networks due to strict firewall rules and port restrictions.

## ✅ **Enhanced App Version (READY FOR TESTING)**

The updated APK includes these cruise ship network fixes:
- **Longer connection timeouts** (30s instead of default)
- **Automatic retry logic** (up to 5 retries for auth, 4 for API calls)
- **Certificate flexibility** for proxy compatibility
- **Exponential backoff** retry delays

## 🛠️ **Additional Troubleshooting Steps**

### 1. **Network Connection Test**
Try these basic connectivity tests first:
- Open a web browser and visit `talkwithbravo.com`
- Try loading Google or another major website
- Check if other apps requiring internet work properly

### 2. **Cruise Ship Network Tips**
- **Connect to ship WiFi** (not cellular if you're far from shore)
- **Try different times** - networks are often less congested early morning/late evening
- **Move to different locations** on the ship (upper decks often have better signals)
- **Close other apps** using internet to reduce network load

### 3. **App-Specific Solutions**

#### **If Authentication Fails:**
1. **Wait and retry** - the app now automatically retries up to 5 times
2. **Clear app cache** (Android Settings > Apps > Bravo > Storage > Clear Cache)
3. **Restart the app** completely
4. **Try airplane mode on/off** to reset network connection

#### **If It Works Briefly Then Fails:**
- This suggests intermittent connectivity
- The app will now automatically retry failed requests
- Wait a few minutes and try again during less busy network times

### 4. **Network Quality Indicators**
**Good signs:**
- Web pages load normally in browser
- Other apps work fine
- You can access cruise ship's portal/WiFi login page

**Bad signs:**
- Very slow web browsing
- Frequent timeouts on all apps
- Can't access cruise ship WiFi portal

### 5. **Emergency Workarounds**
If the app still won't connect:
- **Use during off-peak hours** (3-6 AM, 11 PM-1 AM ship time)
- **Try near WiFi hotspots** (lobby, dining areas often have stronger signals)
- **Contact cruise ship IT** - they can sometimes whitelist specific domains

## 📱 **What Changed in This Version**

### Enhanced Retry Logic:
```
Firebase Authentication: Up to 5 retries with 3-second delays
Backend API calls: Up to 4 retries with exponential backoff
Connection timeout: Extended to 30 seconds
Idle timeout: Extended to 60 seconds
```

### Better Error Handling:
- More descriptive error messages
- Automatic retry on temporary failures
- Certificate validation flexibility for cruise ship proxies

## 🔍 **Debug Information**
The app now logs detailed connection info:
- Look for "retryNetworkOperation" messages in logs
- Shows which attempt number is running
- Reports wait times between retries

## 📞 **If Nothing Works**
1. **Document the exact error** message and time
2. **Note your location** on the ship when it fails
3. **Try again during different network conditions**
4. **Contact cruise ship Guest Services** about internet connectivity issues

The enhanced app should handle most cruise ship network issues automatically with its retry logic and extended timeouts.
