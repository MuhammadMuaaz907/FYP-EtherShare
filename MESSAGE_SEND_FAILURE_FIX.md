# Message Send Failure Fix - Analysis & Solution

## Problem
App shows "Failed to send message" immediately after sending a message in a new channel (fresh install).

## Root Cause Analysis

### Issue #1: payload_hash Generation Timing ✅ FIXED
**Status**: Already correct - payload_hash is calculated from plaintext BEFORE encryption in SQLiteService.addMessage() (line 835).

**Verification**:
- `payload_hash` is calculated at line 835 in `sqlite_service.dart`
- Encryption happens AFTER at line 850
- This ensures hash chain integrity (encryption-independent)

### Issue #2: Genesis (First Message) previous_hash Handling ✅ VERIFIED
**Status**: Correct - defaults to '0' when no previous messages exist.

**Code Location**: `sqlite_service.dart` line 795
```dart
String previousHash = '0'; // Default for genesis
```

**Backend Handling**: Backend correctly accepts `previous_hash = '0'` for genesis messages.

### Issue #3: v2 Schema Mismatch Between Local DB and Send Payload ❌ FIXED
**Status**: **THIS WAS THE MAIN ISSUE**

**Problem**:
1. SQLite correctly stores message with:
   - `encrypted_message` (Base64)
   - `iv` (Base64)
   - `payload_hash` (SHA-256 of plaintext)
   - `previous_hash` and `current_hash` (chain fields)
   - `hash_version` = 2

2. But `HybridStorageService.addMessage()` was sending to server:
   - Only `messageText` (plaintext) ❌
   - Missing `encrypted_message` and `iv` ❌
   - Missing `payload_hash`, `previous_hash`, `current_hash` ❌

3. Backend rejects because:
   - Backend requires `encrypted_message` + `iv` + `payload_hash` for v2 messages
   - Backend rejects plaintext messages (security enforcement)

**Fix Applied**:
- Updated `DistributedService.addMessage()` to accept `encryptedMessage` and `iv` parameters
- Updated `HybridStorageService.addMessage()` to retrieve message from SQLite after insert
- Pass all required fields: `encrypted_message`, `iv`, `payload_hash`, `previous_hash`, `current_hash`, `hash_version`, `message_id`

### Issue #4: Encryption Pipeline Issues ✅ VERIFIED
**Status**: Encryption pipeline is correct - happens after payload_hash calculation.

## Exact Failure Points to Log

### 1. SQLite Insert (sqlite_service.dart)
**Location**: After line 978
**Log Points**:
```dart
print('✅ Message added to SQLite: $messageId');
print('   Payload hash: ${payloadHash.substring(0, 16)}...');
print('   Previous hash: ${previousHash.substring(0, 16)}... (${previousHash == '0' ? 'GENESIS' : 'CHAIN'})');
print('   Current hash: ${currentHash.substring(0, 16)}...');
print('   Hash version: $hashVersion');
print('   Encrypted: ${encryptedMessage != null && iv != null}');
```

### 2. HybridStorageService Send (hybrid_storage_service.dart)
**Location**: Lines 798-842
**Log Points**:
```dart
print('📤 [SEND] Preparing to send message to server');
print('   Message ID: $messageId');
print('   Has encrypted_message: ${encryptedMessage != null && encryptedMessage.isNotEmpty}');
print('   Has iv: ${iv != null && iv.isNotEmpty}');
print('   Has payload_hash: ${payloadHash != null && payloadHash.isNotEmpty}');
print('   Has previous_hash: ${previousHash != null && previousHash.isNotEmpty}');
print('   Has current_hash: ${currentHash != null && currentHash.isNotEmpty}');
print('   Hash version: ${hashVersion ?? "null"}');
if (previousHash == '0') {
  print('🔗 [GENESIS] This is the first message in channel');
}
```

### 3. DistributedService Send (distributed_service.dart)
**Location**: Lines 964-1010
**Log Points**:
```dart
print('📤 [SEND] Sending message to backend API');
print('   Message ID: ${messageId ?? "pending"}');
print('   Hash version: $effectiveHashVersion');
print('   Has encrypted fields: $isV2');
print('   Has payload_hash: ${payloadHash != null && payloadHash.isNotEmpty}');
print('   Has previous_hash: ${previousHash != null && previousHash.isNotEmpty}');
print('   Has current_hash: ${currentHash != null && currentHash.isNotEmpty}');
```

### 4. Backend Response (distributed_service.dart)
**Location**: Lines 970-1007
**Log Points**:
```dart
if (messagesResponse.statusCode == 200 || messagesResponse.statusCode == 201) {
  print('✅ Message added to messages API: $returnedMessageId');
} else {
  print('❌ [SEND FAILED] Backend rejected message');
  print('   Status: ${messagesResponse.statusCode}');
  print('   Response: $errorBody');
  // Parse and log error details
}
```

## Required Fields at Send Time

### For v2 Messages (All New Messages):
1. **encrypted_message** (String, Base64) - REQUIRED
2. **iv** (String, Base64) - REQUIRED
3. **payload_hash** (String, 64-char hex) - REQUIRED
4. **previous_hash** (String) - REQUIRED (use '0' for genesis)
5. **current_hash** (String, 64-char hex) - REQUIRED
6. **hash_version** (int) - REQUIRED (must be 2)
7. **message_id** (String) - Optional (for idempotency)
8. **workspace_id** (String) - REQUIRED
9. **channel_id** (String) - Optional (for channel messages)
10. **sender_address** (String) - REQUIRED
11. **receiver_address** (String) - Optional (for DMs)

### For v1 Messages (Legacy - Deprecated):
- **message_text** (String) - Only for backward compatibility
- Backend will reject plaintext for new messages

## Safe Bootstrap for First Message in Channel

### Genesis Message Flow:
1. **SQLite Insert**:
   - Check for previous messages: `SELECT * FROM messages WHERE workspace_id = ? AND channel_id = ? ORDER BY timestamp DESC LIMIT 1`
   - If no messages: `previous_hash = '0'` (genesis)
   - If messages exist: `previous_hash = last_message.current_hash`
   - Calculate `payload_hash` from plaintext (BEFORE encryption)
   - Encrypt message
   - Calculate `current_hash` using v2 schema with `payload_hash`
   - Store with `hash_version = 2`

2. **Send to Server**:
   - Retrieve message from SQLite (get encrypted fields)
   - Send with `encrypted_message`, `iv`, `payload_hash`
   - Send with `previous_hash = '0'` (genesis indicator)
   - Send with `current_hash` and `hash_version = 2`

3. **Backend Validation**:
   - Backend verifies `previous_hash = '0'` is valid for first message
   - Backend calculates expected `current_hash` and verifies match
   - Backend stores message with chain fields

### Code-Level Fixes Applied:

#### 1. DistributedService.addMessage() (distributed_service.dart)
**Changes**:
- Added `encryptedMessage` and `iv` parameters
- Made `messageText` optional (deprecated for v2)
- Added validation for v2 required fields
- Send encrypted fields instead of plaintext for v2
- Added detailed error logging

#### 2. HybridStorageService.addMessage() (hybrid_storage_service.dart)
**Changes**:
- After SQLite insert, retrieve message to get encrypted fields
- Pass all required fields to `DistributedService.addMessage()`:
  - `encryptedMessage`, `iv`, `payloadHash`
  - `previousHash`, `currentHash`, `hashVersion`
  - `messageId` (for idempotency)
- Added detailed logging for debugging

## Testing Checklist

- [ ] Send first message in new channel (genesis)
- [ ] Verify `previous_hash = '0'` in logs
- [ ] Verify all required fields are present in send logs
- [ ] Verify backend accepts message (status 200/201)
- [ ] Send second message in same channel (chain)
- [ ] Verify `previous_hash` matches first message's `current_hash`
- [ ] Verify chain integrity maintained

## Error Scenarios Handled

1. **Missing encrypted_message**: Logs error, returns null
2. **Missing iv**: Logs error, returns null
3. **Missing payload_hash**: Logs error, returns null
4. **Backend rejection**: Logs status code and error response
5. **Message not found in SQLite**: Logs error, returns null

## Security Notes

- **Zero-Knowledge Enforcement**: Backend never receives plaintext for v2 messages
- **Hash Chain Integrity**: `payload_hash` is calculated from plaintext BEFORE encryption
- **Encryption Independence**: Hash chain is not affected by encryption randomness (IV)
- **Genesis Handling**: First message uses `previous_hash = '0'` (standard blockchain pattern)
