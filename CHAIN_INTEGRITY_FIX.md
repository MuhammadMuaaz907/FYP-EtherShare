# Chain Integrity Fix - Complete Solution

## Problem Summary
Chain verification failing with:
- previous_hash = "0" (genesis handling issue)
- calculated_hash ≠ stored_hash (hash mismatch)
- Chain integrity compromised in SQLite

## Root Causes Identified

### 1. Genesis Handling Inconsistency
**Problem**: previous_hash could be null/empty instead of "0" for genesis messages.

**Fix**: Enforced strict rule: previous_hash is NEVER null/empty. It's "0" for genesis, 64-char hex for chain.

### 2. Hash Calculation Inconsistency
**Problem**: JSON key ordering in `jsonEncode()` is not guaranteed, causing hash mismatches between insert and verification.

**Fix**: Sort keys before JSON encoding to ensure consistent hash calculation.

### 3. Missing Validation
**Problem**: No strict validation to block insertion if crypto fields are invalid.

**Fix**: Added 5 strict validations that block insertion if any field is invalid.

### 4. Verification Mismatch
**Problem**: Verification might use different hash calculation than insert.

**Fix**: Ensured verification uses exact same structure and sorted keys as insert.

## Solutions Implemented

### 1. Correct GENESIS Handling

**Rule**: previous_hash is NEVER null or empty
- **Genesis (first message)**: previous_hash = "0" (exactly, not empty)
- **Chain messages**: previous_hash = last message's current_hash (64-char hex)

**Code Location**: `sqlite_service.dart` lines 802-832

```dart
// CRITICAL GENESIS HANDLING: previous_hash must NEVER be null or empty
String previousHash = '0'; // Default to genesis
bool isGenesis = true;

if (lastMessage.isNotEmpty) {
  // Channel has messages - use last message's current_hash
  final lastCurrentHash = lastMessage.first['current_hash'] as String?;
  if (lastCurrentHash != null && lastCurrentHash.isNotEmpty && lastCurrentHash != '0') {
    previousHash = lastCurrentHash;
    isGenesis = false;
  }
} else if (storedServerHash != null && storedServerHash.isNotEmpty && storedServerHash != '0') {
  // No local messages but have server hash - link to server chain
  previousHash = storedServerHash;
  isGenesis = false;
} else {
  // No messages and no server hash - this is genesis
  previousHash = '0';
  isGenesis = true;
}

// CRITICAL VALIDATION: previous_hash must NEVER be null or empty
if (previousHash.isEmpty) {
  print('❌ [CRYPTO ERROR] previous_hash is empty - cannot proceed');
  return null;
}
```

### 2. Consistent Hash Calculation (Sorted Keys)

**Problem**: `jsonEncode()` doesn't guarantee key order, causing hash mismatches.

**Fix**: Sort keys before encoding.

**Code Location**: `sqlite_service.dart` lines 2466-2470

```dart
// CRITICAL: Sort keys before JSON encoding to ensure consistent hash calculation
final sortedKeys = dataToHash.keys.toList()..sort();
final sortedData = <String, dynamic>{};
for (final key in sortedKeys) {
  sortedData[key] = dataToHash[key];
}

final jsonString = jsonEncode(sortedData);
final bytes = utf8.encode(jsonString);
final digest = sha256.convert(bytes);
return digest.toString();
```

### 3. Strict Validation (Block Invalid Messages)

**5 Validations Added**:

1. **payload_hash**: Must be 64-char hex
2. **encrypted_message**: Must be present and non-empty
3. **iv**: Must be present and non-empty
4. **previous_hash**: Must be "0" (genesis) or 64-char hex (chain), never null/empty
5. **current_hash**: Must be 64-char hex

**Code Location**: `sqlite_service.dart` lines 980-1025

```dart
// CRITICAL: STRICT VALIDATION - Block insertion if ANY crypto field is invalid
if (hashVersion == 2) {
  // Validation 1: payload_hash must be valid 64-char hex
  if (payloadHash.isEmpty || payloadHash.length != 64 || 
      !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(payloadHash)) {
    print('❌ [CRYPTO VALIDATION FAILED] Invalid payload_hash - BLOCKING INSERT');
    return null;
  }
  
  // Validation 2-5: Similar strict checks for all fields...
}
```

### 4. Verification Uses Exact Same Calculation

**Ensured**: Verification uses same structure and sorted keys as insert.

**Code Location**: `sqlite_service.dart` lines 1620-1630, 1879-1891

```dart
// Build dataForHash with EXACT same structure as insert (line 923-931)
final dataForHash = {
  'message_id': record['message_id'],
  'workspace_id': record['workspace_id'],
  'sender_address': record['sender_address'],
  'receiver_address': record['receiver_address'],
  'timestamp': record['timestamp'],
  'previous_hash': expectedPreviousHash, // Use expectedPreviousHash (chain state)
};

// Add payload_hash or message_text based on hash version
if (hashVersion == 2) {
  dataForHash['payload_hash'] = storedPayloadHash;
} else {
  dataForHash['message_text'] = storedMessageText ?? '';
}

// Use same _calculateHash() function (with sorted keys)
final calculatedHash = _calculateHash(dataForHash, hashVersion: hashVersion);
```

### 5. Legacy v1 Message Handling

**v1 Messages (Legacy)**:
- Use `message_text` in hash calculation (plaintext)
- Stored as plaintext in SQLite
- `hash_version = 1`
- Still supported for backward compatibility

**v2 Messages (Current)**:
- Use `payload_hash` in hash calculation (encryption-independent)
- Stored as encrypted (`encrypted_message` + `iv`)
- `hash_version = 2`
- Enforced for all new messages

**Migration Strategy**:
```dart
// During verification, handle both versions
final hashVersion = record['hash_version'] as int? ?? 2;

if (hashVersion == 2) {
  // v2: Use payload_hash
  dataForHash['payload_hash'] = storedPayloadHash;
} else {
  // v1: Use message_text (legacy)
  dataForHash['message_text'] = storedMessageText ?? '';
}

// Both use same _calculateHash() function (with sorted keys)
final calculatedHash = _calculateHash(dataForHash, hashVersion: hashVersion);
```

## Complete addMessage() Flow for v2

### Step-by-Step Flow:

```
1. Generate messageId
   ↓
2. Determine previous_hash
   ├─ If no messages: previous_hash = "0" (GENESIS)
   ├─ If has messages: previous_hash = last message's current_hash
   └─ Validate: NEVER null/empty
   ↓
3. Calculate payload_hash (from plaintext, BEFORE encryption)
   ├─ SHA-256 of messageText
   └─ Validate: 64-char hex
   ↓
4. Encrypt message (AFTER payload_hash calculation)
   ├─ AES-256-CBC encryption
   ├─ Get encrypted_message (Base64)
   └─ Get iv (Base64)
   ↓
5. Build dataToHash (for current_hash calculation)
   ├─ message_id
   ├─ workspace_id
   ├─ sender_address
   ├─ receiver_address
   ├─ payload_hash (v2)
   ├─ timestamp
   └─ previous_hash
   ↓
6. Calculate current_hash
   ├─ Sort keys alphabetically
   ├─ JSON encode sorted data
   ├─ SHA-256 hash
   └─ Validate: 64-char hex
   ↓
7. STRICT VALIDATION (5 checks)
   ├─ payload_hash valid?
   ├─ encrypted_message present?
   ├─ iv present?
   ├─ previous_hash valid?
   └─ current_hash valid?
   ↓
8. Insert to SQLite (only if all validations pass)
   ↓
9. Verify insert succeeded
   ├─ Query message back
   ├─ Check all fields present
   └─ Return messageId (only if verified)
```

## Key Rules

### previous_hash Rules:
1. **NEVER null or empty** - Always a valid string
2. **Genesis**: Must be exactly "0" (not empty, not null)
3. **Chain**: Must be 64-char hex (matching previous message's current_hash)
4. **Validation**: Check format before insert and during verification

### Hash Calculation Rules:
1. **Key Ordering**: Always sort keys before JSON encoding
2. **Field Consistency**: Use exact same fields in insert and verification
3. **Version Handling**: v1 uses message_text, v2 uses payload_hash
4. **previous_hash**: Included in hash calculation (chain link)

### Validation Rules:
1. **Block Invalid**: Return null if ANY validation fails
2. **Format Checks**: All hashes must be 64-char hex
3. **Presence Checks**: All required fields must be present
4. **Genesis Check**: previous_hash = "0" only for first message

## Testing Checklist

- [x] Genesis message uses previous_hash = "0" (not empty)
- [x] Chain messages use previous_hash = last message's current_hash
- [x] Hash calculation uses sorted keys (consistent)
- [x] Verification matches insert hash calculation
- [x] Invalid messages blocked from insertion
- [x] Legacy v1 messages handled correctly
- [x] previous_hash never null/empty

## Error Prevention

### Before Fix:
```
❌ previous_hash could be null/empty
❌ Hash mismatches due to key ordering
❌ Invalid messages inserted
❌ Verification fails on valid messages
```

### After Fix:
```
✅ previous_hash always valid ("0" or 64-char hex)
✅ Consistent hash calculation (sorted keys)
✅ Invalid messages blocked
✅ Verification matches insert exactly
```

## Migration Notes

- **Existing v1 messages**: Continue to work (backward compatible)
- **New messages**: Must use v2 (enforced)
- **Chain integrity**: Verified on every read
- **Genesis detection**: Automatic (previous_hash = "0")
