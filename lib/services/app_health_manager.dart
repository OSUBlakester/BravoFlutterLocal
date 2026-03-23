import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Comprehensive app health and timeout management service
class AppHealthManager {
  static AppHealthManager? _instance;
  static AppHealthManager get instance => _instance ??= AppHealthManager._();
  
  AppHealthManager._();
  
  // Method channel for Android native communication
  static const MethodChannel _channel = MethodChannel('audio_routing');
  
  // Health monitoring variables
  Timer? _healthCheckTimer;
  Timer? _timeoutTimer;
  DateTime? _lastActivityTime;
  bool _isHealthy = true;
  bool _isMonitoring = false;
  
  // Timeout configuration
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const Duration _activityTimeout = Duration(minutes: 2);
  static const Duration _criticalTimeout = Duration(minutes: 5);
  
  // Callbacks
  VoidCallback? onAppNeedsRefresh;
  VoidCallback? onAppTimeout;
  Function(Map<String, dynamic>)? onHealthStatusChanged;
  
  /// Start comprehensive health monitoring
  void startHealthMonitoring({
    VoidCallback? onNeedsRefresh,
    VoidCallback? onTimeout,
    Function(Map<String, dynamic>)? onHealthChanged,
  }) {
    if (_isMonitoring) return;
    
    debugPrint('🏥 AppHealthManager: Starting health monitoring');
    
    onAppNeedsRefresh = onNeedsRefresh;
    onAppTimeout = onTimeout;
    onHealthStatusChanged = onHealthChanged;
    
    _isMonitoring = true;
    _lastActivityTime = DateTime.now();
    
    // Start periodic health checks
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) => _performHealthCheck());
    
    // Start timeout monitoring
    _startTimeoutMonitoring();
  }
  
  /// Stop health monitoring
  void stopHealthMonitoring() {
    debugPrint('🏥 AppHealthManager: Stopping health monitoring');
    
    _healthCheckTimer?.cancel();
    _timeoutTimer?.cancel();
    _isMonitoring = false;
    
    _healthCheckTimer = null;
    _timeoutTimer = null;
  }
  
  /// Record user activity to reset timeout timers
  void recordActivity() {
    _lastActivityTime = DateTime.now();
    
    // Restart timeout monitoring
    _timeoutTimer?.cancel();
    _startTimeoutMonitoring();
  }
  
  /// Manual app refresh trigger
  Future<bool> refreshApp({bool force = false}) async {
    try {
      debugPrint('🔄 AppHealthManager: Starting app refresh (force: $force)');
      
      if (Platform.isAndroid) {
        await _channel.invokeMethod('refreshApp');
        debugPrint('🔄 AppHealthManager: Android native refresh completed');
      }
      
      // Reset health status
      _isHealthy = true;
      _lastActivityTime = DateTime.now();
      
      // Restart monitoring
      if (_isMonitoring) {
        _timeoutTimer?.cancel();
        _startTimeoutMonitoring();
      }
      
      debugPrint('🔄 AppHealthManager: App refresh completed successfully');
      return true;
      
    } catch (e) {
      debugPrint('🔄 AppHealthManager: App refresh failed: $e');
      return false;
    }
  }
  
  /// Check if app is responsive and healthy
  Future<Map<String, dynamic>> checkAppHealth() async {
    try {
      Map<String, dynamic> healthData = {
        'timestamp': DateTime.now().toIso8601String(),
        'isMonitoring': _isMonitoring,
        'lastActivity': _lastActivityTime?.toIso8601String(),
        'isHealthy': _isHealthy,
      };
      
      if (Platform.isAndroid) {
        final nativeHealth = await _channel.invokeMethod('checkAppHealth');
        if (nativeHealth is Map) {
          healthData.addAll(nativeHealth.cast<String, dynamic>());
        }
      }
      
      // Calculate time since last activity
      if (_lastActivityTime != null) {
        final timeSinceActivity = DateTime.now().difference(_lastActivityTime!);
        healthData['minutesSinceActivity'] = timeSinceActivity.inMinutes;
        healthData['isActivityTimeout'] = timeSinceActivity > _activityTimeout;
        healthData['isCriticalTimeout'] = timeSinceActivity > _criticalTimeout;
      }
      
      debugPrint('🏥 AppHealthManager: Health check completed: $healthData');
      return healthData;
      
    } catch (e) {
      debugPrint('🏥 AppHealthManager: Health check failed: $e');
      return {
        'error': e.toString(),
        'isHealthy': false,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
  
  /// Get current health status
  bool get isHealthy => _isHealthy;
  bool get isMonitoring => _isMonitoring;
  DateTime? get lastActivityTime => _lastActivityTime;
  
  /// Private methods
  void _performHealthCheck() async {
    if (!_isMonitoring) return;
    
    try {
      final healthData = await checkAppHealth();
      
      // Determine if app needs attention
      final needsAttention = _determineIfNeedsAttention(healthData);
      
      if (needsAttention && _isHealthy) {
        debugPrint('🚨 AppHealthManager: App health degraded, triggering refresh');
        _isHealthy = false;
        onAppNeedsRefresh?.call();
      } else if (!needsAttention && !_isHealthy) {
        debugPrint('🟢 AppHealthManager: App health restored');
        _isHealthy = true;
      }
      
      // Notify listeners of health status change
      onHealthStatusChanged?.call(healthData);
      
    } catch (e) {
      debugPrint('🚨 AppHealthManager: Health check error: $e');
      _isHealthy = false;
    }
  }
  
  bool _determineIfNeedsAttention(Map<String, dynamic> healthData) {
    // Check memory usage
    final memoryUsage = healthData['memoryUsagePercent'] as int?;
    if (memoryUsage != null && memoryUsage > 85) {
      debugPrint('🚨 AppHealthManager: High memory usage: $memoryUsage%');
      return true;
    }
    
    // Check if audio system is healthy
    final isAudioHealthy = healthData['isAudioHealthy'] as bool?;
    if (isAudioHealthy == false) {
      debugPrint('🚨 AppHealthManager: Audio system unhealthy');
      return true;
    }
    
    // Check TTS status
    final isTtsReady = healthData['isTtsReady'] as bool?;
    if (isTtsReady == false) {
      debugPrint('🚨 AppHealthManager: TTS system not ready');
      return true;
    }
    
    // Check for critical timeout
    final isCriticalTimeout = healthData['isCriticalTimeout'] as bool?;
    if (isCriticalTimeout == true) {
      debugPrint('🚨 AppHealthManager: Critical activity timeout detected');
      return true;
    }
    
    return false;
  }
  
  void _startTimeoutMonitoring() {
    _timeoutTimer = Timer(_criticalTimeout, () {
      if (_isMonitoring) {
        debugPrint('🚨 AppHealthManager: Critical timeout reached, triggering timeout callback');
        onAppTimeout?.call();
      }
    });
  }
  
  /// Manually trigger app refresh via native Android
  Future<void> triggerAppRefresh() async {
    try {
      debugPrint('🔄 AppHealthManager: Triggering app refresh');
      
      if (!kIsWeb && Platform.isAndroid) {
        await _channel.invokeMethod('refreshApp');
        debugPrint('✅ AppHealthManager: Android app refresh completed');
      } else {
        debugPrint('ℹ️ AppHealthManager: App refresh not available on this platform');
      }
      
      // Record activity to reset timeout
      recordActivity();
      
    } catch (e) {
      debugPrint('❌ AppHealthManager: App refresh failed: $e');
      rethrow;
    }
  }
}
