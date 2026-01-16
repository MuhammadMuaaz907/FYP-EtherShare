# Codebase Analysis: Sync Triggers and Duplication Points

## PHASE 1: CODEBASE ANALYSIS RESULTS

### 1. Channel Logic

**Channel Creation**:
- **File**: `backend/routes/channels.js`
- Channels created ONLY when server is online (line 13-244)
- Channel ID normalized: `channelId.toLowerCase().trim().replace(/\s+/g, '-')`
- Channels stored in MongoDB with hash chain fields
- **SQLite Caching**: Channels cached to SQLite for offline access (line 1824-1832 in hybrid_storage_service.dart)

**Message Association**:
- Messages reference `channel_id` and `workspace_id`
- Offline messages MUST reference existing channel (channel created before server went offline)
- **VERIFIED**: ✅ Offline messages always reference existing channels

### 2. Message Lifecycle

**Message Creation Points**:

1. **Online Message Creation**:
   - **File**: `blockchain_fyp/lib/services/hybrid_storage_service.dart` (line 577-837)
   - Flow: `addMessage()` → SQLite (state: `ONLINE_CONFIRMED`) → Server → MongoDB
   - Hash generated: Server calculates hash chain

2. **Offline Message Creation**:
   - **File**: `blockchain_fyp/lib/services/hybrid_storage_service.dart` (line 577-837)
   - Flow: `addMessage()` → SQLite (state: `OFFLINE_LOCAL`) → P2P broadcast
   - Hash generated: SQLite calculates hash chain using stored server hash

3. **P2P Message Reception**:
   - **File**: `blockchain_fyp/lib/services/p2p_service.dart` (line 294-449)
   - Flow: P2P receives → SQLite (with `providedMessageId`) → Callback → `_syncMessageToServerIfNeeded()`
   - **ISSUE**: P2P messages don't set proper state (defaults to `OFFLINE_LOCAL`)

**Hash Generation**:
- **SQLite**: `sqlite_service.dart` line 1548-1553 (SHA-256)
- **Server**: `backend/utils/hashChain.js` line 14-27 (SHA-256)
- **Chain Continuity**: Uses `chain_state` table to link offline messages to server chain

**Message Storage**:
- **SQLite**: `sqlite_service.dart` line 576-696 (`addMessage()`)
- **MongoDB**: `backend/routes/messages.js` line 14-180 (`POST /api/messages`)

**Message Reload on Reconnect**:
- **File**: `blockchain_fyp/lib/services/hybrid_storage_service.dart` (line 1323-1597)
- Triggered by: `syncToServer()` called from multiple places

### 3. Sync Triggers (CRITICAL ISSUE FOUND)

**Multiple Sync Triggers Identified**:

1. **Periodic Timer** (Every 30 seconds):
   - **File**: `hybrid_storage_service.dart` line 301-322
   - Code: `Timer.periodic(const Duration(seconds: 30), (timer) async { await syncToServer(); })`
   - **Risk**: Can trigger sync while another sync is in progress

2. **Server Status Change**:
   - **File**: `hybrid_storage_service.dart` line 326-379
   - Code: `checkServerStatus()` → `syncToServer()` (line 372)
   - **Risk**: Triggers sync when server comes online (can overlap with timer)

3. **P2P Message Callback**:
   - **File**: `hybrid_storage_service.dart` line 78-85, 1599-1645
   - Code: `onMessageReceived` → `_syncMessageToServerIfNeeded()`
   - **Risk**: Syncs individual messages immediately (can overlap with batch sync)

4. **getWorkspaceChannels**:
   - **File**: `hybrid_storage_service.dart` line 1758-1764
   - Code: When server comes online → `syncToServer()`
   - **Risk**: Triggers sync when loading channels (can overlap with other syncs)

**Race Condition Scenario**:
```
Time 0s:  Server comes online
Time 0s:  checkServerStatus() triggers syncToServer()
Time 0s:  getWorkspaceChannels() triggers syncToServer()
Time 0s:  P2P message callback triggers _syncMessageToServerIfNeeded()
Time 30s: Periodic timer triggers syncToServer()
Result:   Multiple syncs running simultaneously → Duplicates!
```

### 4. Blockchain Validation

**Chain Integrity Check**:
- **File**: `backend/utils/hashChain.js` line 101-257 (`verifyChainIntegrity()`)
- **Current Behavior**: Fails on duplicate `message_id` (previous_hash mismatch)
- **Fixed**: Now ignores duplicates, only fails on actual tampering

**Duplicate Detection**:
- **File**: `backend/utils/hashChain.js` line 129-172
- Uses `Set<String>` to track seen `message_id`
- Duplicates skipped (not fatal)

**Why Duplicates Break Integrity**:
- Before fix: Duplicate messages have different `previous_hash` values
- Chain validation expects sequential `previous_hash` chain
- Duplicate breaks chain → Integrity fails
- **Fixed**: Duplicates detected and skipped before hash validation

### 5. UI Rendering

**Message Display**:
- **File**: `blockchain_fyp/lib/channel_page.dart` line 424-560
- Messages loaded via `getChannelMessages()` → `_loadMessages()`
- Deduplication: Uses `Set<String>` to track `message_id` (line 429-432)

**UI Re-render Triggers**:
1. **Polling Timer**: Every 3 seconds (line 87-91)
2. **P2P Callback**: `onMessageReceived` triggers UI update (line 404-407)
3. **Server Fetch**: `getChannelMessages()` fetches from server (line 839-1217)

**Why Server Sync Causes Re-render**:
- **File**: `hybrid_storage_service.dart` line 904-1096
- Server messages cached to SQLite
- UI polls SQLite → Sees cached messages → Re-renders
- **Fixed**: Skip `SYNCED` messages when caching from server

## CRITICAL ISSUES FOUND

### Issue 1: Multiple Concurrent Sync Triggers

**Problem**: `syncToServer()` can be called from 4 different places simultaneously:
1. Periodic timer (every 30s)
2. Server status change callback
3. P2P message callback
4. getWorkspaceChannels callback

**Impact**: Race conditions → Messages synced multiple times → Duplicates

**Solution Needed**: Add sync lock/mutex to prevent concurrent syncs

### Issue 2: P2P Messages Missing State

**Problem**: P2P messages saved with `providedMessageId` but state defaults to `OFFLINE_LOCAL`
- Should be `OFFLINE_LOCAL` if server offline
- Should be `ONLINE_CONFIRMED` if server online (P2P + Server)

**Impact**: P2P messages might be re-synced even if already on server

**Solution Needed**: Set proper state when saving P2P messages

### Issue 3: Sync State Transition Race

**Problem**: Messages marked `PENDING_SYNC` but sync might fail/retry
- State stuck in `PENDING_SYNC` if sync fails
- Next sync retries same messages → Potential duplicates

**Impact**: Failed syncs leave messages in `PENDING_SYNC` → Retried → Duplicates

**Solution Needed**: Handle sync failures properly, reset state on retry

## RECOMMENDED FIXES

### Fix 1: Add Sync Lock

```dart
bool _isSyncing = false;

Future<void> syncToServer() async {
  if (!_isServerOnline || _isSyncing) {
    return; // Skip if already syncing
  }
  
  _isSyncing = true;
  try {
    // ... sync logic ...
  } finally {
    _isSyncing = false;
  }
}
```

### Fix 2: Set P2P Message State

```dart
// In p2p_service.dart, when saving message:
final messageState = _isServerOnline ? 'ONLINE_CONFIRMED' : 'OFFLINE_LOCAL';
await SQLiteService.instance.addMessage(
  // ...
  messageState: messageState,
);
```

### Fix 3: Handle Sync Failures

```dart
// Reset PENDING_SYNC to OFFLINE_LOCAL on sync failure
catch (e) {
  await SQLiteService.instance.updateMessageState(
    messageId: messageId,
    state: 'OFFLINE_LOCAL', // Reset for retry
  );
}
```

## SUMMARY

**Root Causes Identified**:
1. ✅ Multiple sync triggers (4 concurrent paths)
2. ✅ P2P messages missing proper state
3. ✅ Sync state transition race conditions
4. ✅ Blockchain validation too strict (FIXED)
5. ✅ UI re-render on sync (FIXED)

**Fixes Implemented**:
- ✅ Global message ID (idempotency)
- ✅ Message state tracking
- ✅ Server-side idempotency
- ✅ Blockchain duplicate detection
- ✅ UI re-render prevention

**Fixes Still Needed**:
- ⚠️ Sync lock to prevent concurrent syncs
- ⚠️ P2P message state setting
- ⚠️ Sync failure handling
