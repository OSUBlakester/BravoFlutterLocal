# ThreadsPage Wake Word Clean Architecture Refactor

## Problem Solved
- **Issue**: ThreadsPage wake word detection was cutting off questions prematurely and running multiple processes simultaneously
- **Root Cause**: ThreadsPage was over-managing the shared WakeWordService with 20+ restart calls throughout the codebase
- **Symptoms**: Session IDs rapidly cycling (15-24), multiple concurrent service instances, questions being interrupted

## Clean Architecture Solution

### Before (Complex/Problematic)
```dart
// Complex debounce and restart management
bool _isRestartingWakeWordService = false;
Timer? _restartDebounceTimer;

// Method called 20+ times throughout the file
Future<void> _restartOurWakeWordService() async {
  // 60+ lines of complex restart logic with debouncing
  // Constantly restarting the shared service
  // Creating conflicts and session overlaps
}

// 20+ calls scattered throughout:
// - Initialization
// - Timeout handlers  
// - Error recovery
// - Scanning startup
// - Health checks
// - User interaction handlers
```

### After (Clean/Simple)
```dart
// Simple connection tracking
// ThreadsPage is a PASSIVE consumer of the shared service
// NO restart management, NO service lifecycle control
final FlutterTts _flutterTts = FlutterTts();
bool _audioSessionInitialized = false;

// Clean connection method
Future<void> _setupWakeWordConnection() async {
  // Simply connects to existing shared service
  // Sets up callbacks but doesn't manage lifecycle
  _wakeWordService = WakeWordService.getCurrentInstance();
}

// All restart calls replaced with simple service usage:
final service = WakeWordService.getCurrentInstance();
await service?.startWakeWordListening();
```

## Key Architectural Changes

### 1. Eliminated Service Management
- **Removed**: `_restartOurWakeWordService()` method (60+ lines)
- **Removed**: All debounce logic (`_isRestartingWakeWordService`, `_restartDebounceTimer`)
- **Removed**: 20+ restart calls scattered throughout the file

### 2. Passive Consumer Pattern
- ThreadsPage now **consumes** the shared service instead of **managing** it
- No lifecycle control - just connects, sets callbacks, and uses
- Shared service handles its own auto-restart and recovery

### 3. Simplified Error Handling
- Removed complex restart-based error recovery
- Let the shared service handle its own resilience
- Simple graceful degradation when service unavailable

### 4. Clean Initialization
```dart
// Before: Complex initialization with forced restarts
await Future.delayed(const Duration(milliseconds: 2000));
await _restartOurWakeWordService(); // Creating conflicts

// After: Simple connection
_wakeWordService = WakeWordService.getCurrentInstance();
await _wakeWordService?.startWakeWordListening();
```

## Files Modified
- `lib/threads_page.dart` - Complete architectural refactor

## Expected Results
1. **No More Question Cutoffs**: Single service instance prevents interruption conflicts
2. **No More Multiple Processes**: Eliminated concurrent session creation 
3. **Stable Session IDs**: Service manages its own lifecycle consistently
4. **Faster Response**: No restart delays when user asks questions
5. **Better Reliability**: Shared service auto-restart handles recovery

## Testing Focus Areas
1. Wake word detection reliability ("hey bravo")
2. Question completion without interruption
3. No multiple session IDs in logs
4. Smooth transitions between scanning and voice input
5. Proper error recovery without restarts

## Git Backup
- Pre-refactor state saved as commit: `6a67955` 
- Can rollback if needed: `git reset --hard 6a67955`

---
**Architecture Principle**: ThreadsPage is now a **passive consumer** that trusts the shared service to manage itself, eliminating all the conflicts that came from over-management.
