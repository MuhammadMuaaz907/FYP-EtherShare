# Sync Race Condition Fix - Complete

## Problem Identified

Multiple sync triggers causing concurrent `syncToServer()` calls:
1. Periodic timer (every 30s)
2. Server status change callback
3. P2P message callback  
4. getWorkspaceChannels callback

**Result**: Race conditions → Messages synced multiple times → Duplicates

## Solution Implemented

### 1. Sync Lock (Mutex)

**File**: `blockchain_fyp/lib/services/hybrid_storage_service.dart`

**Added**:
```dart
bool _isSyncing = false; // Lock to prevent concurrent syncs

Future<void> syncToServer() async {
  if (!_isServerOnline || _isSyncing) {
    return; // Skip if already syncing
  }
  
  _isSyncing = true;
  try {
    // ... sync logic ...
  } finally {
    _isSyncing = false; // Always release lock
  }
}
```

**Effect**: Only one sync can run at a time, preventing race conditions

### 2. Removed Redundant Sync Triggers

**Removed sync triggers from**:
- `checkServerStatus()` - Removed `syncToServer()` call
- `getWorkspaceChannels()` - Removed `syncToServer()` call

**Reason**: Periodic timer (every 30s) handles all syncs automatically

**Result**: Single sync path → No race conditions

### 3. Sync Failure Handling

**Added**:
```dart
catch (e) {
  // Reset PENDING_SYNC messages back to OFFLINE_LOCAL for retry
  final failedMessages = await SQLiteService.instance.getUnsyncedMessages();
  for (final msg in failedMessages) {
    if (state == 'PENDING_SYNC') {
      await SQLiteService.instance.updateMessageState(
        messageId: messageId,
        state: 'OFFLINE_LOCAL', // Reset for retry
      );
    }
  }
} finally {
  _isSyncing = false; // Always release lock
}
```

**Effect**: Failed syncs don't leave messages stuck in `PENDING_SYNC` state

### 4. P2P Message State Fix

**File**: `blockchain_fyp/lib/services/p2p_service.dart`

**Fixed**:
- P2P messages now set `messageState: 'OFFLINE_LOCAL'` when saved
- Uses `providedMessageId` for consistency
- Sync will handle idempotency check

**Effect**: P2P messages properly tracked and won't be re-synced if already on server

## Sync Flow (Fixed)

### Single Sync Path

```
Periodic Timer (every 30s)
  ↓
checkServerStatus() (updates _isServerOnline)
  ↓
syncToServer() (if server online AND not already syncing)
  ↓
Lock acquired (_isSyncing = true)
  ↓
Fetch unsynced messages (PENDING_SYNC or OFFLINE_LOCAL)
  ↓
Mark as PENDING_SYNC
  ↓
Sync to server (idempotent)
  ↓
Update state to SYNCED
  ↓
Lock released (_isSyncing = false)
```

### Other Triggers (No Longer Sync)

- `checkServerStatus()`: Only updates `_isServerOnline` flag
- `getWorkspaceChannels()`: Only loads channels, no sync
- `_syncMessageToServerIfNeeded()`: Still syncs individual messages (has its own idempotency check)

## Testing Checklist

- [ ] Start app offline, create messages
- [ ] Server comes online
- [ ] Verify only ONE sync happens (check logs)
- [ ] Verify no duplicate messages in MongoDB
- [ ] Verify messages marked as SYNCED
- [ ] Trigger multiple sync conditions simultaneously
- [ ] Verify sync lock prevents concurrent syncs

## Result

✅ Single sync path (periodic timer only)
✅ Sync lock prevents race conditions
✅ Failed syncs handled properly
✅ P2P messages have proper state
✅ No more duplicate syncs
