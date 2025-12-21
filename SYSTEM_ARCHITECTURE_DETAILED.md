# 🏗️ Complete System Architecture - Detailed Explanation

## 📊 System Overview

Aapka system **do layers** par kaam karta hai:

```
┌─────────────────────────────────────────────────────────┐
│              APPLICATION LAYER (Flutter)                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  User A  │  │  User B  │  │  User C  │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
└───────┼─────────────┼─────────────┼──────────────────────┘
        │             │             │
        ▼             ▼             ▼
┌─────────────────────────────────────────────────────────┐
│         DISTRIBUTED SYSTEM (MongoDB Server)             │
│  ┌─────────┐      ┌─────────┐      ┌─────────┐        │
│  │ Node 1  │─────▶│ Node 2  │─────▶│ Node 3  │        │
│  │ Chain   │      │ Chain   │      │ Chain   │        │
│  └─────────┘      └─────────┘      └─────────┘        │
└─────────────────────────────────────────────────────────┘
        │             │             │
        ▼             ▼             ▼
┌─────────────────────────────────────────────────────────┐
│      DECENTRALIZED SYSTEM (SQLite + TCP P2P)           │
│  ┌─────────┐  TCP  ┌─────────┐  TCP  ┌─────────┐      │
│  │Device A │◄─────►│Device B │◄─────►│Device C │      │
│  │(SQLite) │       │(SQLite) │       │(SQLite) │      │
│  └─────────┘       └─────────┘       └─────────┘      │
└─────────────────────────────────────────────────────────┘
```

---

## 🔗 PART 1: DISTRIBUTED SYSTEM DETAILED

### 📋 **1. MongoDB Collections Structure**

#### **Collection: `nodes`**
```javascript
{
  _id: ObjectId("..."),
  node_id: "node_abc123",
  node_name: "Node-Device-1",
  ip_address: "192.168.1.100",
  tcp_port: 3001,
  public_key: "pub_key_xyz",
  status: "online",  // online | offline | syncing
  last_seen: ISODate("2024-01-15T10:30:00Z"),
  
  // Chain Structure
  chain_position: 0,           // Position in chain (0 = first)
  previous_node_id: null,      // Previous node in chain
  next_node_id: "node_def456", // Next node in chain
  
  connected_nodes: [
    {
      node_id: "node_def456",
      connection_type: "tcp",
      last_connected: ISODate("2024-01-15T10:30:00Z")
    }
  ],
  
  created_at: ISODate("2024-01-15T10:00:00Z"),
  updated_at: ISODate("2024-01-15T10:30:00Z")
}
```

#### **Collection: `ledgers`**
```javascript
{
  _id: ObjectId("..."),
  block_id: "block_node_abc123_0_1705312800000",
  block_number: 0,  // 0 = Genesis block
  node_id: "node_abc123",
  
  // Hash Chain
  previous_hash: "0",  // Genesis block has "0"
  current_hash: "a1b2c3d4e5f6...",  // SHA-256 hash
  
  // Transaction Data
  data: {
    type: "message",
    sender_address: "0xUserA123",
    receiver_address: "0xUserB456",
    content: "Hello, how are you?",
    workspace_id: "ws_789"
  },
  
  transaction_type: "message",
  sender_address: "0xUserA123",
  receiver_address: "0xUserB456",
  workspace_id: "ws_789",
  timestamp: 1705312800000,
  
  // Integrity Flags
  verified: true,
  chain_broken: false,
  
  created_at: ISODate("2024-01-15T10:30:00Z")
}
```

#### **Collection: `messages`**
```javascript
{
  _id: ObjectId("..."),
  message_id: "msg_123456",
  workspace_id: "ws_789",
  channel_id: "general",
  sender_address: "0xUserA123",
  receiver_address: "0xUserB456",  // null for channel messages
  message_text: "Hello, how are you?",
  file_id: null,  // If file attached
  timestamp: 1705312800000,
  created_at: ISODate("2024-01-15T10:30:00Z")
}
```

---

### ⛓️ **2. Chain Building Process**

#### **Step-by-Step Chain Creation:**

```javascript
// 1. Node Registration
Node 1 registers → {
  node_id: "node_1",
  chain_position: null  // Not yet in chain
}

Node 2 registers → {
  node_id: "node_2",
  chain_position: null
}

Node 3 registers → {
  node_id: "node_3",
  chain_position: null
}

// 2. Build Chain (Automatic)
buildChain() function runs:

Node 1 → {
  chain_position: 0,
  previous_node_id: null,      // First node
  next_node_id: "node_2"
}

Node 2 → {
  chain_position: 1,
  previous_node_id: "node_1",
  next_node_id: "node_3"
}

Node 3 → {
  chain_position: 2,
  previous_node_id: "node_2",
  next_node_id: null           // Last node
}
```

**Visual Chain:**
```
┌─────────────┐
│   Node 1    │  ← First (Genesis)
│ Position: 0 │
│ Prev: null  │
│ Next: node_2│
└──────┬──────┘
       │
       │ Chain Link
       ▼
┌─────────────┐
│   Node 2    │  ← Middle
│ Position: 1 │
│ Prev: node_1│
│ Next: node_3│
└──────┬──────┘
       │
       │ Chain Link
       ▼
┌─────────────┐
│   Node 3    │  ← Last
│ Position: 2 │
│ Prev: node_2│
│ Next: null  │
└─────────────┘
```

---

### 🔐 **3. Hash Chain Integrity - Detailed**

#### **Hash Calculation Formula:**

```javascript
// For each block:
const dataString = JSON.stringify(blockData.data, sortedKeys);
const combined = `${dataString}${previousHash}${blockNumber}${nodeId}`;
const currentHash = SHA256(combined);
```

#### **Example Hash Chain:**

```
Block 0 (Genesis):
  data: {message: "Hello"}
  previous_hash: "0"
  block_number: 0
  node_id: "node_1"
  
  combined = "{\"message\":\"Hello\"}0_0_node_1"
  current_hash = SHA256(combined)
  = "a1b2c3d4e5f6789..."

Block 1:
  data: {message: "World"}
  previous_hash: "a1b2c3d4e5f6789..."  ← Block 0 ka hash
  block_number: 1
  node_id: "node_1"
  
  combined = "{\"message\":\"World\"}a1b2c3d4e5f6789..._1_node_1"
  current_hash = SHA256(combined)
  = "x9y8z7w6v5u4321..."

Block 2:
  data: {message: "Test"}
  previous_hash: "x9y8z7w6v5u4321..."  ← Block 1 ka hash
  block_number: 2
  node_id: "node_1"
  
  combined = "{\"message\":\"Test\"}x9y8z7w6v5u4321..._2_node_1"
  current_hash = SHA256(combined)
  = "m5n4o3p2q1r0987..."
```

#### **Chain Breaking Detection:**

```javascript
// Scenario: Block 1 ka data change ho gaya

Original Block 1:
  data: {message: "World"}
  previous_hash: "a1b2c3..."
  current_hash: "x9y8z7..."

Tampered Block 1:
  data: {message: "HACKED"}  // ❌ Changed!
  previous_hash: "a1b2c3..."
  current_hash: "x9y8z7..."  // ❌ Old hash (invalid now!)

// Verification Process:
1. Recalculate hash:
   calculated = SHA256("{\"message\":\"HACKED\"}a1b2c3..._1_node_1")
   = "different_hash_123..."

2. Compare:
   calculated !== current_hash
   // ❌ MISMATCH! Chain broken!

3. Mark as broken:
   block.chain_broken = true
   // System alerts: "Chain integrity compromised!"
```

**Code Implementation:**
```javascript
// ledgerService.js - verifyChain()
for (const block of blocks) {
  // 1. Check previous hash matches
  if (block.previous_hash !== expectedHash) {
    // Chain broken!
    block.chain_broken = true;
    return false;
  }
  
  // 2. Recalculate and verify current hash
  const calculatedHash = SHA256(data + previousHash + blockNumber + nodeId);
  if (calculatedHash !== block.current_hash) {
    // Hash mismatch! Data tampered!
    block.chain_broken = true;
    return false;
  }
  
  expectedHash = block.current_hash;
}
```

---

### 💬 **4. UserA to UserB Communication Flow**

#### **Complete Message Flow:**

```
┌──────────┐
│  User A  │
│ Address: │
│ 0xUserA  │
└────┬─────┘
     │
     │ 1. UserA sends message "Hello" to UserB
     ▼
┌─────────────────────────────────────┐
│  Flutter App (distributed_service)  │
│  sendMessage({                       │
│    senderAddress: "0xUserA",        │
│    receiverAddress: "0xUserB",       │
│    messageText: "Hello"              │
│  })                                  │
└────┬─────────────────────────────────┘
     │
     │ 2. HTTP POST to Backend
     ▼
┌─────────────────────────────────────┐
│  Backend API (Node.js)               │
│  POST /api/nodes/{nodeId}/ledger     │
│  {                                    │
│    type: "message",                  │
│    sender_address: "0xUserA",         │
│    receiver_address: "0xUserB",       │
│    content: "Hello"                   │
│  }                                    │
└────┬─────────────────────────────────┘
     │
     │ 3. Create Block in Ledger
     ▼
┌─────────────────────────────────────┐
│  LedgerService.addBlock()            │
│  ┌─────────────────────────────┐    │
│  │ 1. Get last block           │    │
│  │ 2. Calculate block_number   │    │
│  │ 3. Get previous_hash        │    │
│  │ 4. Calculate current_hash   │    │
│  │ 5. Save to MongoDB          │    │
│  │ 6. Verify chain integrity   │    │
│  └─────────────────────────────┘    │
└────┬─────────────────────────────────┘
     │
     │ 4. Store in messages collection
     ▼
┌─────────────────────────────────────┐
│  MongoDB Database                    │
│  ┌─────────────────────────────┐    │
│  │ ledgers collection:         │    │
│  │ {                            │    │
│  │   block_id: "block_...",    │    │
│  │   data: {message: "Hello"},  │    │
│  │   current_hash: "abc123..."  │    │
│  │ }                            │    │
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ messages collection:         │    │
│  │ {                            │    │
│  │   message_id: "msg_123",     │    │
│  │   sender: "0xUserA",         │    │
│  │   receiver: "0xUserB",        │    │
│  │   message_text: "Hello"      │    │
│  │ }                            │    │
│  └─────────────────────────────┘    │
└────┬─────────────────────────────────┘
     │
     │ 5. UserB retrieves message
     ▼
┌─────────────────────────────────────┐
│  GET /api/nodes/messages/            │
│      0xUserA/0xUserB                 │
│  Returns:                            │
│  [{                                  │
│    message_text: "Hello",             │
│    sender_address: "0xUserA",         │
│    timestamp: 1705312800000           │
│  }]                                  │
└────┬─────────────────────────────────┘
     │
     ▼
┌──────────┐
│  User B  │
│ Sees:    │
│ "Hello"  │
└──────────┘
```

---

## 🌐 PART 2: DECENTRALIZED SYSTEM DETAILED

### 💾 **1. SQLite Database Structure (Local)**

#### **Database Schema:**

```sql
-- nodes table (local copy of network nodes)
CREATE TABLE nodes (
  node_id TEXT PRIMARY KEY,
  node_name TEXT NOT NULL,
  ip_address TEXT NOT NULL,
  tcp_port INTEGER NOT NULL,
  public_key TEXT,
  status TEXT DEFAULT 'offline',
  chain_position INTEGER,
  previous_node_id TEXT,
  next_node_id TEXT,
  last_seen INTEGER,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- ledger table (local blockchain copy)
CREATE TABLE ledger (
  block_id TEXT PRIMARY KEY,
  block_number INTEGER NOT NULL,
  node_id TEXT NOT NULL,
  previous_hash TEXT NOT NULL,
  current_hash TEXT NOT NULL,
  data TEXT NOT NULL,  -- JSON string
  transaction_type TEXT,
  sender_address TEXT,
  receiver_address TEXT,
  workspace_id TEXT,
  timestamp INTEGER NOT NULL,
  verified INTEGER DEFAULT 0,  -- 0 = false, 1 = true
  chain_broken INTEGER DEFAULT 0,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- messages table (local messages)
CREATE TABLE messages (
  message_id TEXT PRIMARY KEY,
  workspace_id TEXT,
  channel_id TEXT,
  sender_address TEXT NOT NULL,
  receiver_address TEXT,
  message_text TEXT NOT NULL,
  file_id TEXT,
  timestamp INTEGER NOT NULL,
  synced INTEGER DEFAULT 0,  -- 0 = not synced to server, 1 = synced
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- sync_queue table (for syncing with MongoDB)
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  operation TEXT NOT NULL,  -- 'insert', 'update', 'delete'
  data TEXT,  -- JSON string
  retry_count INTEGER DEFAULT 0,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);
```

---

### 🔌 **2. TCP Communication Protocol**

#### **TCP Message Format:**

```javascript
// Message Types:
{
  type: "handshake" | "message" | "sync_request" | "chain_verify",
  node_id: "node_abc123",
  timestamp: 1705312800000,
  data: {...}
}

// Example Messages:

// 1. Handshake
{
  type: "handshake",
  node_id: "node_abc123",
  message: "Connection request"
}

// 2. Message Forwarding
{
  type: "message",
  sender_address: "0xUserA",
  receiver_address: "0xUserB",
  content: "Hello",
  workspace_id: "ws_123",
  block_id: "block_...",
  timestamp: 1705312800000
}

// 3. Sync Request
{
  type: "sync_request",
  node_id: "node_abc123",
  last_sync_timestamp: 1705312800000
}

// 4. Chain Verification
{
  type: "chain_verify",
  node_id: "node_abc123",
  block_id: "block_..."
}
```

#### **TCP Server Implementation:**

```dart
// Flutter TCP Client
import 'dart:io';

class TCPClient {
  Socket? _socket;
  String _nodeId;
  String _ipAddress;
  int _port;
  
  // Connect to peer
  Future<void> connect(String ip, int port) async {
    _socket = await Socket.connect(ip, port);
    _socket!.listen(_handleData);
    
    // Send handshake
    sendMessage({
      'type': 'handshake',
      'node_id': _nodeId
    });
  }
  
  // Send message
  void sendMessage(Map<String, dynamic> message) {
    if (_socket != null) {
      _socket!.add(utf8.encode(jsonEncode(message)));
    }
  }
  
  // Handle incoming data
  void _handleData(List<int> data) {
    final message = jsonDecode(utf8.decode(data));
    _processMessage(message);
  }
  
  // Process message
  void _processMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'handshake_ack':
        print('✅ Connected to peer: ${message['node_id']}');
        break;
        
      case 'message':
        // Save to local SQLite
        _saveToSQLite(message);
        break;
        
      case 'sync_response':
        // Sync data
        _syncData(message['ledger']);
        break;
    }
  }
}
```

---

### 🔄 **3. Dual Storage & Sync Mechanism**

#### **Storage Flow:**

```
┌─────────────────────────────────────────────────────────┐
│              MESSAGE SENT BY USER A                      │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  Step 1: Try MongoDB │
        │  (If server online)   │
        └───────────┬───────────┘
                    │
        ┌───────────▼───────────┐
        │  Success?             │
        └───┬───────────────┬───┘
            │ Yes           │ No
            ▼               ▼
    ┌───────────────┐  ┌───────────────┐
    │ Save to       │  │ Add to        │
    │ MongoDB       │  │ sync_queue    │
    │ ✅            │  │ (Sync later)  │
    └───────┬───────┘  └───────┬───────┘
            │                  │
            └──────────┬────────┘
                       │
            ┌──────────▼──────────┐
            │  Step 2: Save to   │
            │  Local SQLite      │
            │  ✅ Always          │
            └──────────┬──────────┘
                       │
            ┌──────────▼──────────┐
            │  Step 3: Send via  │
            │  TCP to Peer       │
            │  (If peer online)   │
            └──────────┬──────────┘
                       │
            ┌──────────▼──────────┐
            │  Step 4: Peer saves│
            │  to SQLite         │
            │  ✅                 │
            └─────────────────────┘
```

#### **Sync Mechanism:**

```dart
// Sync Service
class SyncService {
  // Sync local SQLite to MongoDB
  Future<void> syncToMongoDB() async {
    // 1. Get unsynced records
    final unsynced = await _getUnsyncedRecords();
    
    for (var record in unsynced) {
      try {
        // 2. Send to MongoDB
        await DistributedService.addMessage(
          workspaceId: record['workspace_id'],
          senderAddress: record['sender_address'],
          receiverAddress: record['receiver_address'],
          messageText: record['message_text'],
        );
        
        // 3. Mark as synced
        await _markAsSynced(record['message_id']);
      } catch (e) {
        // 4. Retry later
        await _incrementRetryCount(record['id']);
      }
    }
  }
  
  // Sync MongoDB to local SQLite
  Future<void> syncFromMongoDB() async {
    // 1. Get last sync timestamp
    final lastSync = await _getLastSyncTime();
    
    // 2. Fetch new messages from MongoDB
    final messages = await DistributedService.getChannelMessages(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    
    // 3. Save to SQLite
    for (var message in messages) {
      if (message['timestamp'] > lastSync) {
        await _saveToSQLite(message);
      }
    }
  }
}
```

---

### 🚫 **4. Offline Mode - Server Off**

#### **Scenario: MongoDB Server is Offline**

```
┌─────────────────────────────────────────┐
│  MongoDB Server: ❌ OFFLINE             │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Device A (SQLite)                      │
│  ┌──────────────────────────────────┐   │
│  │ User A sends message             │   │
│  │ "Hello" to User B                │   │
│  └──────────────┬───────────────────┘   │
│                 │                        │
│                 ▼                        │
│  ┌──────────────────────────────────┐   │
│  │ 1. Try MongoDB: ❌ Failed         │   │
│  │ 2. Add to sync_queue             │   │
│  │ 3. Save to local SQLite: ✅       │   │
│  └──────────────┬───────────────────┘   │
│                 │                        │
│                 ▼                        │
│  ┌──────────────────────────────────┐   │
│  │ 4. Send via TCP to Device B      │   │
│  │    (Direct P2P connection)       │   │
│  └──────────────┬───────────────────┘   │
└─────────────────┼────────────────────────┘
                  │
                  │ TCP Connection
                  ▼
┌─────────────────────────────────────────┐
│  Device B (SQLite)                      │
│  ┌──────────────────────────────────┐   │
│  │ 5. Receive message via TCP       │   │
│  │ 6. Save to local SQLite: ✅       │   │
│  │ 7. Display to User B            │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
                  │
                  │ When Server Comes Back
                  ▼
┌─────────────────────────────────────────┐
│  Device A: Sync sync_queue to MongoDB   │
│  ✅ All messages synced                 │
└─────────────────────────────────────────┘
```

**Code Example:**
```dart
// Offline message handling
Future<bool> sendMessageOffline({
  required String senderAddress,
  required String receiverAddress,
  required String messageText,
}) async {
  try {
    // 1. Try MongoDB first
    final success = await DistributedService.sendMessage(
      senderAddress: senderAddress,
      receiverAddress: receiverAddress,
      messageText: messageText,
    );
    
    if (success) {
      // Server online, message sent
      return true;
    }
  } catch (e) {
    // Server offline
    print('⚠️ Server offline, using offline mode');
  }
  
  // 2. Save to local SQLite
  await _saveToSQLite({
    'sender_address': senderAddress,
    'receiver_address': receiverAddress,
    'message_text': messageText,
    'synced': 0,  // Not synced yet
  });
  
  // 3. Add to sync queue
  await _addToSyncQueue('messages', messageId, 'insert', messageData);
  
  // 4. Try TCP to peer
  await _sendViaTCP(receiverAddress, messageText);
  
  return true;  // Message saved locally
}
```

---

## 🎯 COMPLETE INTEGRATION FLOW

### **Full System: UserA → UserB Message**

```
┌──────────────────────────────────────────────────────────────┐
│                    USER A SENDS MESSAGE                      │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────┐
        │  Flutter App (distributed_service)     │
        │  sendMessage()                         │
        └───────────────┬───────────────────────┘
                        │
        ┌───────────────▼───────────────┐
        │  Check: Server Online?        │
        └───┬───────────────────────┬──┘
            │ Yes                    │ No
            ▼                        ▼
    ┌───────────────┐        ┌───────────────┐
    │ DISTRIBUTED   │        │ DECENTRALIZED │
    │ SYSTEM        │        │ SYSTEM        │
    │ (MongoDB)     │        │ (SQLite+TCP)  │
    └───────┬───────┘        └───────┬───────┘
            │                        │
            │                        │
    ┌───────▼────────┐       ┌───────▼────────┐
    │ 1. Create Block│       │ 1. Save to     │
    │ 2. Calculate   │       │    SQLite     │
    │    Hash         │       │ 2. Add to     │
    │ 3. Add to Chain│       │    sync_queue │
    │ 4. Verify      │       │ 3. Send via   │
    │ 5. Store in DB │       │    TCP         │
    └───────┬────────┘       └───────┬───────┘
            │                        │
            │                        │
            └──────────┬─────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │  PEER DEVICE (UserB) │
            │  ┌────────────────┐  │
            │  │ Receive via    │  │
            │  │ TCP or MongoDB │  │
            │  │ Save to SQLite │  │
            │  │ Display to User│  │
            │  └────────────────┘  │
            └──────────────────────┘
```

---

## ✅ IMPLEMENTATION STATUS

### **✅ Distributed System (COMPLETE)**
- ✅ MongoDB setup
- ✅ Node registration
- ✅ Chain building
- ✅ Hash calculation (SHA-256)
- ✅ Chain verification
- ✅ Chain breaking detection
- ✅ UserA to UserB messages
- ✅ Ledger maintenance
- ✅ API endpoints

### **⏳ Decentralized System (TO IMPLEMENT)**
- ⏳ SQLite database setup (Flutter)
- ⏳ TCP client/server (Flutter)
- ⏳ Local storage service
- ⏳ Peer discovery
- ⏳ Offline mode support
- ⏳ Sync service (SQLite ↔ MongoDB)
- ⏳ Conflict resolution

---

## 🚀 NEXT STEPS

1. **Complete Distributed System Testing:**
   - Test chain building
   - Test hash integrity
   - Test chain breaking detection
   - Test UserA to UserB communication

2. **Implement Decentralized System:**
   - Setup SQLite in Flutter
   - Implement TCP client
   - Create sync service
   - Add offline mode

3. **Integration:**
   - Connect both systems
   - Implement dual storage
   - Test offline scenarios

---

## 📝 SUMMARY

Aapka system design **perfect** hai! 

**Distributed System:** ✅ Complete - MongoDB par chain structure with hash integrity

**Decentralized System:** ⏳ Next step - SQLite + TCP for offline P2P communication

**Key Features:**
- ✅ Chain structure (Node1 → Node2 → Node3)
- ✅ Hash integrity (SHA-256)
- ✅ Chain breaking detection
- ✅ UserA to UserB communication
- ⏳ Offline mode (SQLite + TCP)
- ⏳ Dual storage (MongoDB + SQLite)

**Current Status:** Distributed system ready hai. Ab decentralized system implement karna hai! 🚀

