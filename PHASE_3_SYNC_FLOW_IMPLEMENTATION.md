# Phase 3: Offline → Online Sync Flow - Complete Implementation

## ✅ EXACT FLOW IMPLEMENTATION

### Phase 3 Requirements (EXACT)

1. Detect server online
2. Fetch messages WHERE state = PENDING_SYNC
3. Send headers to server
4. Server validates + confirms
5. Client updates state to SYNCED
6. NO UI re-render
7. NO block re-creation

## Implementation Details

### Step 1: Detect Server Online ✅

**Location**: `hybrid_storage_service.dart` line 1346-1348

```dart
Future<void> syncToServer() async {
  if (!_isServerOnline) {
    return; // Server offline - skip sync
  }
  // Server is online - proceed with sync
}
```

**Trigger Points**:
- Periodic timer (every 30s) checks `_isServerOnline`
- `checkServerStatus()` updates `_isServerOnline` flag
- Sync only runs when `_isServerOnline == true`

### Step 2: Fetch Messages WHERE state = PENDING_SYNC ✅

**Location**: `hybrid_storage_service.dart` line 1360-1378

**Flow**:
1. First, mark `OFFLINE_LOCAL` messages as `PENDING_SYNC` (transition state)
2. Then fetch only `PENDING_SYNC` messages for sync

```dart
// Mark OFFLINE_LOCAL messages as PENDING_SYNC (prepare for sync)
final offlineMessages = await SQLiteService.instance.getUnsyncedMessages();
for (final msg in offlineMessages) {
  if (state == 'OFFLINE_LOCAL') {
    await SQLiteService.instance.updateMessageState(
      messageId: messageId,
      state: 'PENDING_SYNC',
    );
  }
}

// PHASE 3 STEP 2: Fetch messages WHERE state = PENDING_SYNC (exact requirement)
final pendingSyncMessages = await SQLiteService.instance.getMessagesByState('PENDING_SYNC');
```

**New Method**: `getMessagesByState(String state)` - Fetches messages by exact state

### Step 3: Send Headers to Server ✅

**Location**: `hybrid_storage_service.dart` line 1533-1543

**Headers Sent**:
- `messageId`: Existing message_id (line 1540)
- `channelId`: Channel identifier (line 1535)
- `previousHash`: Previous hash from SQLite (line 1541)
- `currentHash`: Current hash from SQLite (line 1542)
- `timestamp`: Included in messageData on server

```dart
final serverMessageId = await DistributedService.addMessage(
  workspaceId: workspaceId ?? '',
  channelId: channelId, // Header: channel_id
  senderAddress: msg['sender_address'] ?? '',
  receiverAddress: msg['receiver_address'],
  messageText: msg['message_text'] ?? '',
  fileId: msg['file_id'],
  messageId: localMessageId, // Header: message_id
  previousHash: msg['previous_hash'] as String?, // Header: prev_hash
  currentHash: msg['current_hash'] as String?, // Header: current_hash
);
```

**Note**: Full message data is sent (for server validation), but server uses provided hashes (no recalculation)

### Step 4: Server Validates + Confirms ✅

**Location**: `backend/routes/messages.js` line 37-160

**Server Validation**:
1. Checks for existing `message_id` (idempotency) - Line 39-70
2. Validates `previousHash` matches chain state - Line 128-139
3. Uses provided hashes directly (no recalculation) - Line 121-125
4. Returns existing message if duplicate - Line 44-69
5. Inserts new message if not duplicate - Line 143

```javascript
// Check for duplicate message_id
if (messageId && messageId.trim().length > 0) {
  const existingMessage = await messagesCollection.findOne({
    message_id: messageId
  });
  
  if (existingMessage) {
    // Return existing (idempotent) - NO re-insert, NO re-hash
    return res.status(200).json({
      success: true,
      message: 'Message already exists (idempotent)',
      data: existingMessage
    });
  }
}

// Validate provided hashes
const verifyInfo = await HashChain.getAndVerifyLastHash(
  messagesCollection,
  filter,
  providedPreviousHash
);

// Use provided hashes (no recalculation)
messageWithHash = {
  ...messageData,
  previous_hash: providedPreviousHash,
  current_hash: providedCurrentHash,
};
```

### Step 5: Client Updates State to SYNCED ✅

**Location**: `hybrid_storage_service.dart` line 1558-1562

```dart
// PHASE 3 STEP 5: Update state to SYNCED
await SQLiteService.instance.updateMessageState(
  messageId: serverMessageId != localMessageId ? serverMessageId : localMessageId,
  state: 'SYNCED',
);
print('✅ PHASE 3: Message synced (state: SYNCED) - NO UI re-render, NO block re-creation');
```

**State Transition**: `PENDING_SYNC` → `SYNCED`

### Step 6: NO UI Re-render ✅

**Location**: `hybrid_storage_service.dart` line 982-995

**Implementation**:
- `SYNCED` messages skipped when fetching from server
- `ONLINE_CONFIRMED` messages skipped when fetching from server
- Deduplication by `message_id` in UI layer

```dart
// Skip if message is already synced OR has state SYNCED/ONLINE_CONFIRMED
if (syncedMessageIds.contains(messageId)) {
  print('ℹ️ Skipping already synced message: $messageId');
  skipped++;
  continue;
}

// Also check message state
final msgState = existingMsgState['message_state']?.toString();
if (msgState == 'SYNCED' || msgState == 'ONLINE_CONFIRMED') {
  print('ℹ️ Skipping message with state $msgState: $messageId');
  skipped++;
  continue;
}
```

**Result**: Synced messages never trigger UI re-render

### Step 7: NO Block Re-creation ✅

**Location**: `backend/routes/messages.js` line 117-160

**Implementation**:
- Server uses provided hashes directly (no recalculation)
- If duplicate found, returns existing message (no insert)
- No hash recalculation on idempotent sync

```javascript
if (isIdempotentSync && providedPreviousHash && providedCurrentHash) {
  // Use provided hashes directly (no recalculation)
  messageWithHash = {
    ...messageData,
    previous_hash: providedPreviousHash,
    current_hash: providedCurrentHash,
  };
  
  // Insert with provided hashes (no block re-creation)
  await messagesCollection.insertOne(messageWithHash);
}
```

**Result**: Blocks never re-created, hashes preserved

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: OFFLINE → ONLINE SYNC FLOW                         │
└─────────────────────────────────────────────────────────────┘

1. Detect Server Online
   ├─ checkServerStatus() → _isServerOnline = true
   └─ syncToServer() called (periodic timer or status change)
   
2. Fetch Messages WHERE state = PENDING_SYNC
   ├─ Mark OFFLINE_LOCAL → PENDING_SYNC (transition)
   └─ getMessagesByState('PENDING_SYNC')
   
3. Send Headers to Server
   ├─ messageId (existing)
   ├─ channelId
   ├─ previousHash
   ├─ currentHash
   └─ timestamp (in messageData)
   
4. Server Validates + Confirms
   ├─ Check duplicate message_id
   ├─ Validate previousHash matches chain
   ├─ Use provided hashes (no recalculation)
   └─ Return existing if duplicate, insert if new
   
5. Client Updates State to SYNCED
   ├─ updateMessageState(messageId, 'SYNCED')
   └─ State: PENDING_SYNC → SYNCED
   
6. NO UI Re-render
   ├─ getChannelMessages() skips SYNCED messages
   └─ Deduplication by message_id
   
7. NO Block Re-creation
   ├─ Server uses provided hashes
   └─ No hash recalculation
```

## State Transitions

```
OFFLINE_LOCAL → PENDING_SYNC → SYNCED
     ↓              ↓             ↓
  (offline)    (sync start)  (sync complete)
```

## Verification

### Test Case 1: Offline Message Sync
1. ✅ Create message offline (state: OFFLINE_LOCAL)
2. ✅ Server comes online
3. ✅ Message marked as PENDING_SYNC
4. ✅ Headers sent to server
5. ✅ Server validates and confirms
6. ✅ State updated to SYNCED
7. ✅ NO UI re-render
8. ✅ NO block re-creation

### Test Case 2: Duplicate Sync Prevention
1. ✅ Same message synced twice
2. ✅ Server returns existing (idempotent)
3. ✅ State remains SYNCED
4. ✅ NO duplicate in MongoDB
5. ✅ NO UI re-render

### Test Case 3: Sync Failure Handling
1. ✅ Sync fails (network error)
2. ✅ PENDING_SYNC → OFFLINE_LOCAL (reset)
3. ✅ Retry on next sync
4. ✅ No messages stuck in PENDING_SYNC

## Code Locations

- **Step 1**: `hybrid_storage_service.dart` line 1346-1348
- **Step 2**: `hybrid_storage_service.dart` line 1360-1378, `sqlite_service.dart` line 906-918
- **Step 3**: `hybrid_storage_service.dart` line 1533-1543
- **Step 4**: `backend/routes/messages.js` line 37-160
- **Step 5**: `hybrid_storage_service.dart` line 1558-1562
- **Step 6**: `hybrid_storage_service.dart` line 982-995
- **Step 7**: `backend/routes/messages.js` line 117-160

## Summary

✅ **All Phase 3 Requirements Implemented**

- ✅ Step 1: Detect server online
- ✅ Step 2: Fetch messages WHERE state = PENDING_SYNC
- ✅ Step 3: Send headers to server
- ✅ Step 4: Server validates + confirms
- ✅ Step 5: Client updates state to SYNCED
- ✅ Step 6: NO UI re-render
- ✅ Step 7: NO block re-creation

**Result**: Exact Phase 3 flow implemented - offline messages sync once, no duplicates, no UI re-render, no block re-creation.
