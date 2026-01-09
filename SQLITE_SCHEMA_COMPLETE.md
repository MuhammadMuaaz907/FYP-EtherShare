# 📊 SQLite Database Schema - Complete Analysis (MongoDB-Aligned)

## 🎯 Overview

SQLite database MongoDB ka complete mirror hai jo **offline support** ke liye use hota hai. Jab Node.js server off hota hai, tab bhi app SQLite se data load karta hai.

**Database Name:** `ethershare.db`  
**Location:** `getApplicationDocumentsDirectory()/ethershare.db`  
**Version:** 3 (MongoDB-aligned schema)

---

## 📋 Complete Table Schema

### 1️⃣ **users** Table
**Purpose:** User profiles store karta hai

```sql
CREATE TABLE users (
  address TEXT PRIMARY KEY,        -- User ka wallet address (unique)
  username TEXT,                   -- User ka username
  email TEXT,                      -- User ka email
  created_at INTEGER,              -- Timestamp jab user create hua
  updated_at INTEGER               -- Timestamp jab last update hua
);
```

**Indexes:**
- `address` (PRIMARY KEY)

**Kya Save Hota Hai:**
- User ka wallet address
- Username
- Email
- Creation aur update timestamps

---

### 2️⃣ **workspaces** Table
**Purpose:** Workspaces (teams/groups) store karta hai

```sql
CREATE TABLE workspaces (
  workspace_id TEXT PRIMARY KEY,   -- Unique workspace ID
  name TEXT,                       -- Workspace ka naam
  inviter_address TEXT,            -- Workspace creator ka address
  created_at INTEGER,              -- Timestamp jab workspace create hua
  timestamp INTEGER,               -- Timestamp for hash chain
  previous_hash TEXT,               -- Previous workspace ka hash (blockchain chain)
  current_hash TEXT,               -- Current workspace ka hash
  synced_to_server INTEGER DEFAULT 0  -- 0 = not synced, 1 = synced
);
```

**Indexes:**
- `workspace_id` (PRIMARY KEY)
- `idx_workspaces_inviter` (inviter_address)

**Kya Save Hota Hai:**
- Workspace ID aur naam
- Creator (inviter) address
- Hash chain for integrity verification
- Sync status

**Important:** Jab server online hota hai, workspaces automatically SQLite mein cache ho jate hain taake offline bhi kaam karein.

---

### 3️⃣ **members** Table
**Purpose:** Workspace members store karta hai

```sql
CREATE TABLE members (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workspace_id TEXT,               -- Kis workspace ka member hai
  member_address TEXT,             -- Member ka wallet address
  display_name TEXT,                -- Optional display name
  joined_at INTEGER,               -- Timestamp jab member join hua
  synced_to_server INTEGER DEFAULT 0  -- 0 = not synced, 1 = synced
);
```

**Indexes:**
- `idx_members_workspace` (workspace_id)
- `idx_members_address` (member_address)

**Kya Save Hota Hai:**
- Workspace reference
- Member ka address
- Display name (optional)
- Join timestamp
- Sync status

**Important:** Members automatically cache hote hain jab server se fetch hote hain. Ye P2P communication ke liye critical hai.

---

### 4️⃣ **channels** Table (MongoDB-Aligned)
**Purpose:** Communication channels store karta hai

```sql
CREATE TABLE channels (
  channel_id TEXT,                 -- Channel ka unique ID (lowercase)
  workspace_id TEXT,                -- Kis workspace ka channel hai
  channel_name TEXT,                -- Channel ka display name
  creator_address TEXT,             -- Channel creator ka address
  members TEXT,                     -- JSON array of member addresses
  is_private INTEGER DEFAULT 0,    -- 0 = public, 1 = private
  is_default INTEGER DEFAULT 0,     -- 0 = user-created, 1 = default (general/random)
  created_at INTEGER,               -- Timestamp jab channel create hua
  timestamp INTEGER,                -- Timestamp for hash chain
  previous_hash TEXT,                -- Previous channel ka hash
  current_hash TEXT,                 -- Current channel ka hash
  deleted INTEGER DEFAULT 0,        -- 0 = active, 1 = deleted (soft delete)
  synced_to_server INTEGER DEFAULT 0,  -- 0 = not synced, 1 = synced
  PRIMARY KEY (channel_id, workspace_id)
);
```

**Indexes:**
- `(channel_id, workspace_id)` (PRIMARY KEY)
- `idx_channels_workspace` (workspace_id)
- `idx_channels_deleted` (deleted)
- `idx_channels_creator` (creator_address)

**Kya Save Hota Hai:**
- Channel ID aur naam
- Workspace reference
- Creator address
- **Members array** (JSON format) - kaun-kaun members ko access hai
- **is_private** flag - private ya public channel
- **is_default** flag - default channels (general/random)
- **deleted** flag - soft delete support
- Hash chain for integrity
- Sync status

**MongoDB Alignment:**
- ✅ `members` array (JSON format)
- ✅ `is_private` boolean
- ✅ `is_default` boolean
- ✅ `deleted` boolean (soft delete)
- ✅ `timestamp` for hash chain
- ✅ `previous_hash` and `current_hash`

---

### 5️⃣ **messages** Table
**Purpose:** Messages store karta hai (channel messages aur direct messages)

```sql
CREATE TABLE messages (
  message_id TEXT PRIMARY KEY,     -- Unique message ID
  workspace_id TEXT,               -- Kis workspace ka message hai
  channel_id TEXT,                 -- Kis channel ka message hai (optional)
  sender_address TEXT,             -- Message sender ka address
  receiver_address TEXT,           -- Message receiver ka address (for DMs)
  message_text TEXT,               -- Message content
  file_id TEXT,                    -- File attachment ID (optional)
  timestamp INTEGER,               -- Message timestamp
  previous_hash TEXT,              -- Previous message ka hash
  current_hash TEXT,                -- Current message ka hash
  synced_to_server INTEGER DEFAULT 0  -- 0 = not synced, 1 = synced
);
```

**Indexes:**
- `message_id` (PRIMARY KEY)
- `idx_messages_workspace` (workspace_id)
- `idx_messages_channel` (channel_id)
- `idx_messages_sender` (sender_address)
- `idx_messages_receiver` (receiver_address)
- `idx_messages_timestamp` (timestamp)

**Kya Save Hota Hai:**
- Message ID aur content
- Workspace aur channel references
- Sender aur receiver addresses
- File attachments
- Hash chain for integrity
- Sync status

---

### 6️⃣ **files** Table
**Purpose:** File metadata store karta hai

```sql
CREATE TABLE files (
  file_id TEXT PRIMARY KEY,        -- Unique file ID
  filename TEXT,                   -- File ka naam
  workspace_id TEXT,                -- Kis workspace ka file hai
  uploader_address TEXT,           -- File uploader ka address
  file_size INTEGER,                -- File size in bytes
  upload_timestamp INTEGER,         -- Upload timestamp
  local_path TEXT,                  -- Local file path (for offline access)
  synced_to_server INTEGER DEFAULT 0  -- 0 = not synced, 1 = synced
);
```

**Kya Save Hota Hai:**
- File metadata
- Local file path for offline access
- Sync status

---

### 7️⃣ **peers** Table
**Purpose:** P2P peer information store karta hai

```sql
CREATE TABLE peers (
  user_address TEXT PRIMARY KEY,   -- Peer ka wallet address
  ip_address TEXT,                 -- Peer ka IP address
  port INTEGER,                    -- Peer ka port
  last_seen INTEGER,               -- Last seen timestamp
  is_online INTEGER DEFAULT 0      -- 0 = offline, 1 = online
);
```

**Indexes:**
- `user_address` (PRIMARY KEY)
- `idx_peers_address` (user_address)

**Kya Save Hota Hai:**
- Peer connection information
- IP address aur port for P2P communication
- Online/offline status

**Important:** Ye P2P communication ke liye critical hai. Jab server off hota hai, peers SQLite se load hote hain.

---

## 🔄 Data Flow (Server Online vs Offline)

### **Server Online:**
1. **Workspaces:** Server se fetch → SQLite mein cache → UI mein show
2. **Members:** Server se fetch → SQLite mein cache → UI mein show
3. **Channels:** Server se fetch → SQLite mein cache → UI mein show
4. **Messages:** Server se fetch → SQLite mein cache → UI mein show

### **Server Offline:**
1. **Workspaces:** SQLite se load → UI mein show
2. **Members:** SQLite se load → UI mein show
3. **Channels:** SQLite se load → UI mein show (with proper filtering)
4. **Messages:** SQLite se load → UI mein show
5. **P2P:** SQLite se peer info load → Direct device-to-device communication

---

## 🎯 Channel Filtering Logic (MongoDB-Aligned)

### **Workspace Members:**
- ✅ See **ALL channels** (except deleted)
- ✅ No filtering based on `members` array or `is_private` flag
- ✅ Only deleted channels are excluded

### **Non-Workspace Members:**
- ⚠️ See only:
  - Default channels (General, Random)
  - Public channels (`is_private = 0`)
  - Channels where they're in `members` array
  - Channels with empty `members` array

**Implementation:**
```dart
// Check if user is workspace member
bool isWorkspaceMember = await checkIfWorkspaceMember(workspaceId, memberAddress);

if (isWorkspaceMember) {
  // Show ALL channels (except deleted)
  query = "workspace_id = ? AND deleted = 0";
} else {
  // Filter based on privacy and membership
  query = "workspace_id = ? AND deleted = 0 AND (
    is_default = 1 OR 
    is_private = 0 OR 
    members LIKE '%memberAddress%' OR
    members = '[]'
  )";
}
```

---

## 📦 What Gets Saved to SQLite

### **Automatic Caching (When Server is Online):**

1. **Workspaces:**
   - ✅ Jab `getUserWorkspaces()` call hota hai
   - ✅ Server se fetch hote hi SQLite mein save ho jate hain
   - ✅ Offline access ke liye

2. **Workspace Members:**
   - ✅ Jab `getWorkspaceMembers()` call hota hai
   - ✅ Server se fetch hote hi SQLite mein save ho jate hain
   - ✅ P2P communication ke liye critical

3. **Channels:**
   - ✅ Jab `getWorkspaceChannels()` call hota hai
   - ✅ Server se fetch hote hi SQLite mein save ho jate hain
   - ✅ Complete metadata (members, is_private, etc.) ke saath

4. **Messages:**
   - ✅ Jab message send hota hai → SQLite mein immediately save
   - ✅ Server sync baad mein hota hai
   - ✅ Offline bhi messages save hote hain

5. **Peer Info:**
   - ✅ Jab P2P server start hota hai
   - ✅ Jab peer discovery hota hai
   - ✅ P2P communication ke liye

---

## 🔧 Database Migration

**Version 1 → 2:**
- Channels table add hua

**Version 2 → 3:**
- Channels table mein new columns add hue:
  - `members` (JSON array)
  - `is_private` (boolean)
  - `timestamp` (for hash chain)
  - `previous_hash` (for hash chain)
  - `current_hash` (for hash chain)
  - `deleted` (soft delete)
  - `synced_to_server` (sync status)

**Migration Automatic:**
- Jab app start hota hai, `onUpgrade()` automatically call hota hai
- Existing data preserve rehta hai
- New columns add ho jate hain

---

## ✅ Key Fixes Implemented

### **1. Workspace Caching:**
- ✅ `getUserWorkspaces()` ab server se fetch hote hi SQLite mein cache karta hai
- ✅ Server off hone par bhi workspaces show hote hain

### **2. Member Caching:**
- ✅ `getWorkspaceMembers()` ab server se fetch hote hi SQLite mein cache karta hai
- ✅ P2P communication ke liye members available hote hain

### **3. Channel Schema:**
- ✅ MongoDB-aligned complete schema
- ✅ Members array support
- ✅ Privacy flags support
- ✅ Soft delete support

### **4. Channel Filtering:**
- ✅ MongoDB jaisa filtering logic
- ✅ Workspace members ko sab channels dikhte hain
- ✅ Non-members ko filtered channels dikhte hain

---

## 🎯 Summary

**SQLite Database ab MongoDB ka complete mirror hai:**

1. ✅ **Complete Schema:** Sab tables MongoDB ke saath aligned
2. ✅ **Automatic Caching:** Server se data fetch hote hi SQLite mein save
3. ✅ **Offline Support:** Server off hone par bhi sab data available
4. ✅ **P2P Ready:** Peer info aur members cached for P2P communication
5. ✅ **Channel Filtering:** MongoDB jaisa filtering logic
6. ✅ **Data Integrity:** Hash chain support for verification

**Ab jab server off hoga:**
- ✅ Workspaces show honge
- ✅ Members show honge
- ✅ Channels properly filtered hoke show honge
- ✅ P2P communication kaam karega
- ✅ Messages offline bhi save/sync honge

---

## 📝 Notes

- **Database Version:** 3
- **Migration:** Automatic (on app start)
- **Location:** `getApplicationDocumentsDirectory()/ethershare.db`
- **Backup:** SQLite database automatically backup hota hai device par
- **Sync:** Jab server online aata hai, unsynced data automatically sync hota hai

