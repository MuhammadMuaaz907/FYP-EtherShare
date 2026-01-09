# 🌐 Decentralized P2P System - Action Plan

## 📋 Requirements Analysis

### Current State:
- ✅ MongoDB backend with HTTP API exists
- ✅ DistributedService for backend communication
- ✅ Node.js TCP server exists (backend level)
- ❌ No Flutter-side TCP P2P communication
- ❌ No SQLite local database
- ❌ No direct device-to-device messaging

### Target System:
1. **TCP/IP P2P Communication**
   - Each device acts as both client AND server
   - Direct UserA (192.168.1.1) ↔ UserB (192.168.1.2) communication
   - Ping-based messaging system
   - Works when main server is offline

2. **Dual Storage System**
   - MongoDB copy (on server when available)
   - SQLite copy (local on each device)
   - Sync mechanism between both

3. **Communication Flow**
   ```
   UserA (192.168.1.1) → TCP Direct → UserB (192.168.1.2)
   UserA → SQLite (local) → Sync → MongoDB (when server online)
   ```

---

## 🎯 Implementation Phases

### **Phase 1: SQLite Database Service** ✅
**Goal:** Create local SQLite database mirroring MongoDB functionality

**Tasks:**
- [ ] Add `sqflite` package to pubspec.yaml
- [ ] Create `sqlite_service.dart` with:
  - Database initialization
  - User profiles table
  - Workspaces table
  - Messages table
  - Members table
  - Files metadata table
  - Chain integrity fields (previous_hash, current_hash)
- [ ] Implement CRUD operations matching MongoDBService interface
- [ ] Add chain verification methods
- [ ] Test SQLite operations

**Files to Create:**
- `blockchain_fyp/lib/services/sqlite_service.dart`

---

### **Phase 2: TCP P2P Server/Client** ✅
**Goal:** Implement TCP server and client in Flutter for direct device communication

**Tasks:**
- [ ] Add TCP socket support (dart:io Socket/ServerSocket)
- [ ] Create `p2p_service.dart` with:
  - TCP server (listens for incoming connections)
  - TCP client (connects to other devices)
  - Peer discovery mechanism
  - Message routing (UserA → UserB)
  - Connection management
  - Heartbeat/ping system
- [ ] Implement IP address detection
- [ ] Port management (auto-assign or configurable)
- [ ] Handle connection errors gracefully

**Files to Create:**
- `blockchain_fyp/lib/services/p2p_service.dart`

**Key Features:**
- Server socket listens on configurable port (default: 8080)
- Client connects to peer IP:Port
- JSON message protocol
- Connection pooling for multiple peers

---

### **Phase 3: Peer Discovery** ✅
**Goal:** Discover other devices/users on the network

**Tasks:**
- [ ] Implement peer discovery methods:
  - Broadcast discovery (UDP multicast)
  - Manual IP entry
  - Server-assisted discovery (when server online)
  - QR code sharing
- [ ] Maintain peer list (IP, Port, User Address)
- [ ] Peer status monitoring (online/offline)
- [ ] Auto-reconnect on disconnect

**Implementation:**
- UDP broadcast for LAN discovery
- Server API endpoint for peer registry (when available)
- Local peer cache in SharedPreferences

---

### **Phase 4: Direct Messaging System** ✅
**Goal:** Enable UserA to UserB direct messaging via TCP

**Tasks:**
- [ ] Message routing logic:
  - Find peer by user address
  - Connect via TCP
  - Send message
  - Receive acknowledgment
- [ ] Message queue for offline peers
- [ ] Retry mechanism
- [ ] Message encryption (optional but recommended)
- [ ] Message format:
  ```json
  {
    "type": "message",
    "sender_address": "0x...",
    "receiver_address": "0x...",
    "content": "Hello",
    "workspace_id": "...",
    "timestamp": 1234567890,
    "message_id": "uuid"
  }
  ```

---

### **Phase 5: Hybrid Storage & Sync** ✅
**Goal:** Sync between SQLite and MongoDB

**Tasks:**
- [ ] Dual-write strategy:
  - Write to SQLite immediately (local)
  - Write to MongoDB when server available
  - Queue failed MongoDB writes
- [ ] Sync mechanism:
  - On app start: Check MongoDB for updates
  - Sync SQLite → MongoDB (when server online)
  - Sync MongoDB → SQLite (when server online)
- [ ] Conflict resolution:
  - Timestamp-based (newer wins)
  - Chain integrity check
- [ ] Offline mode:
  - All operations use SQLite
  - Queue for sync when online

**Implementation:**
- Modify `DistributedService` to use hybrid approach
- Add sync service
- Background sync task

---

### **Phase 6: Integration & Testing** ✅
**Goal:** Integrate all components and test

**Tasks:**
- [ ] Update UI to show P2P status
- [ ] Test direct messaging (server off)
- [ ] Test SQLite operations
- [ ] Test sync mechanism
- [ ] Test peer discovery
- [ ] Test offline mode
- [ ] Performance testing
- [ ] Error handling verification

---

## 📐 Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    UserA Device                          │
│  ┌──────────────┐         ┌──────────────┐             │
│  │   Flutter    │         │   SQLite     │             │
│  │     App      │◄───────►│   Database   │             │
│  └──────┬───────┘         └──────────────┘             │
│         │                                               │
│         │ TCP Server (Port 8080)                        │
│         │ TCP Client                                    │
│         │                                               │
└─────────┼───────────────────────────────────────────────┘
          │
          │ TCP/IP Direct Connection
          │ (192.168.1.1:8080 ↔ 192.168.1.2:8080)
          │
┌─────────┼───────────────────────────────────────────────┐
│         │                    UserB Device               │
│  ┌──────┴───────┐         ┌──────────────┐             │
│  │   Flutter    │         │   SQLite     │             │
│  │     App      │◄───────►│   Database   │             │
│  └──────┬───────┘         └──────────────┘             │
│         │                                               │
│         │ TCP Server (Port 8080)                        │
│         │ TCP Client                                    │
│         │                                               │
└─────────┼───────────────────────────────────────────────┘
          │
          │ HTTP API (when server online)
          │
┌─────────▼───────────────────────────────────────────────┐
│              Node.js Backend Server                      │
│  ┌──────────────┐         ┌──────────────┐             │
│  │   HTTP API   │◄───────►│   MongoDB    │             │
│  │   (Port 3000)│         │   Database   │             │
│  └──────────────┘         └──────────────┘             │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 Technical Specifications

### **1. SQLite Schema**

**users table:**
```sql
CREATE TABLE users (
  address TEXT PRIMARY KEY,
  username TEXT,
  email TEXT,
  created_at INTEGER,
  updated_at INTEGER
);
```

**workspaces table:**
```sql
CREATE TABLE workspaces (
  workspace_id TEXT PRIMARY KEY,
  name TEXT,
  inviter_address TEXT,
  created_at INTEGER,
  timestamp INTEGER,
  previous_hash TEXT,
  current_hash TEXT
);
```

**messages table:**
```sql
CREATE TABLE messages (
  message_id TEXT PRIMARY KEY,
  workspace_id TEXT,
  channel_id TEXT,
  sender_address TEXT,
  receiver_address TEXT,
  message_text TEXT,
  file_id TEXT,
  timestamp INTEGER,
  previous_hash TEXT,
  current_hash TEXT,
  synced_to_server INTEGER DEFAULT 0
);
```

**members table:**
```sql
CREATE TABLE members (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workspace_id TEXT,
  member_address TEXT,
  display_name TEXT,
  joined_at INTEGER
);
```

**files table:**
```sql
CREATE TABLE files (
  file_id TEXT PRIMARY KEY,
  filename TEXT,
  workspace_id TEXT,
  uploader_address TEXT,
  file_size INTEGER,
  upload_timestamp INTEGER,
  local_path TEXT
);
```

**peers table:**
```sql
CREATE TABLE peers (
  user_address TEXT PRIMARY KEY,
  ip_address TEXT,
  port INTEGER,
  last_seen INTEGER,
  is_online INTEGER DEFAULT 0
);
```

---

### **2. TCP Message Protocol**

**Handshake:**
```json
{
  "type": "handshake",
  "user_address": "0x...",
  "device_id": "uuid",
  "version": "1.0"
}
```

**Message:**
```json
{
  "type": "message",
  "message_id": "uuid",
  "sender_address": "0x...",
  "receiver_address": "0x...",
  "content": "Hello",
  "workspace_id": "...",
  "timestamp": 1234567890
}
```

**Acknowledgment:**
```json
{
  "type": "ack",
  "message_id": "uuid",
  "status": "received"
}
```

**Ping:**
```json
{
  "type": "ping",
  "timestamp": 1234567890
}
```

**Pong:**
```json
{
  "type": "pong",
  "timestamp": 1234567890
}
```

---

### **3. Dependencies to Add**

```yaml
dependencies:
  sqflite: ^2.3.0          # SQLite database
  path_provider: ^2.1.2     # Already added
  path: ^1.8.3              # Path utilities
```

---

## 🚀 Implementation Order

1. ✅ **SQLite Service** - Foundation for local storage
2. ✅ **TCP P2P Service** - Core communication layer
3. ✅ **Peer Discovery** - Find other devices
4. ✅ **Direct Messaging** - UserA → UserB communication
5. ✅ **Hybrid Storage** - Sync SQLite ↔ MongoDB
6. ✅ **Integration** - Connect all pieces
7. ✅ **Testing** - Verify everything works

---

## ✅ Success Criteria

- [ ] UserA can send message to UserB directly via TCP (server off)
- [ ] Messages stored in SQLite locally
- [ ] Messages sync to MongoDB when server online
- [ ] Peer discovery works (UDP broadcast or manual IP)
- [ ] Connection status visible in UI
- [ ] Offline mode fully functional
- [ ] Chain integrity maintained in SQLite
- [ ] Performance acceptable (< 100ms for local operations)

---

## 📝 Notes

- TCP port should be configurable (default: 8080)
- Use JSON for message format (easy to parse)
- Implement connection timeout (5 seconds)
- Add retry logic for failed connections
- Log all P2P operations for debugging
- Consider encryption for sensitive data
- Handle NAT traversal for internet communication (future)

---

**Status:** 🟡 Ready for Implementation
**Next Step:** Start with Phase 1 - SQLite Service

