# 📊 EtherShare Database - Complete Analysis (Urdu/Hindi + English)

## 🎯 Database Overview

**Database Name:** `EtherShare`  
**Database Type:** MongoDB (NoSQL)  
**Connection:** `mongodb://localhost:27017/EtherShare`

Yeh ek **blockchain-based file sharing aur communication system** ka database hai jo MongoDB use karta hai. Har collection ka apna specific purpose hai aur sab collections ek saath mil kar complete system banate hain.

---

## 📋 Total Collections: 9

1. **users** - User profiles store karta hai
2. **workspaces** - Workspaces (teams/groups) store karta hai
3. **channels** - Communication channels store karta hai
4. **messages** - Messages store karta hai
5. **members** - Workspace members store karta hai
6. **files** - File metadata store karta hai
7. **nodes** - Distributed network nodes store karta hai
8. **ledgers** - Blockchain-like ledger store karta hai
9. **fs.files & fs.chunks** - GridFS file storage (automatic)

---

## 1️⃣ **users** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **user profiles** store karti hai. Har user ka basic information yahan save hota hai.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,                    // MongoDB auto-generated ID
  address: String,                  // User ka wallet address (PRIMARY KEY, UNIQUE)
  username: String,                 // User ka username (UNIQUE, 3-50 characters)
  email: String,                    // User ka email address
  created_at: Number,                // Timestamp jab user create hua
  updated_at: Number                 // Timestamp jab last update hua
}
```

### 🔑 Key Points:
- **address** unique hai - ek address se sirf ek user
- **username** bhi unique hai - duplicate username nahi ho sakta
- Address ko **lowercase** me normalize kiya jata hai
- Username **case-insensitive** check hota hai (John = john)

### 💾 Example Data:
```json
{
  "address": "0x1234567890abcdef",
  "username": "john_doe",
  "email": "john@example.com",
  "created_at": 1703123456789,
  "updated_at": 1703123456789
}
```

### 🔍 Indexes (Fast Searching Ke Liye):
- `address` (unique) - Fast lookup by address
- `email` - Fast lookup by email
- `username` (unique) - Fast lookup by username

### 🎯 Kya Kya Store Hota Hai:
- User ka blockchain wallet address
- Username jo app me dikhega
- Email address
- Creation aur update timestamps

---

## 2️⃣ **workspaces** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **workspaces** (teams/groups) store karti hai. Har workspace ek separate team/group hai jahan users kaam kar sakte hain.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  workspace_id: String,              // Unique workspace ID (PRIMARY KEY, UNIQUE)
  name: String,                      // Workspace ka naam
  inviter_address: String,           // Creator ka address (jo workspace banaya)
  created_at: Number,                // Creation timestamp
  timestamp: Number,                 // Hash chain ke liye timestamp
  previous_hash: String,             // Previous workspace ka hash (blockchain chain)
  current_hash: String               // Current workspace ka hash (blockchain chain)
}
```

### 🔑 Key Points:
- **workspace_id** unique hai - format: `ws_{inviter_address}_{timestamp}`
- Ek user ke liye **same name ka workspace duplicate nahi ho sakta** (case-insensitive)
- **Hash chain** maintain hoti hai - agar koi data modify kare to chain break ho jayegi
- Har workspace create hote hi **2 default channels** ban jate hain: "General" aur "Random"

### 💾 Example Data:
```json
{
  "workspace_id": "ws_0x1234567890abcdef_1703123456789",
  "name": "Development Team",
  "inviter_address": "0x1234567890abcdef",
  "created_at": 1703123456789,
  "timestamp": 1703123456789,
  "previous_hash": "0xabc123...",
  "current_hash": "0xdef456..."
}
```

### 🔍 Indexes:
- `workspace_id` (unique) - Fast lookup by workspace ID
- `inviter_address` - Find all workspaces by creator
- `timestamp` - Sort by creation time
- `inviter_address + name` - Prevent duplicate workspace names per user

### 🎯 Kya Kya Store Hota Hai:
- Workspace ka unique ID
- Workspace ka naam
- Creator ka address
- Blockchain-like hash chain (data integrity ke liye)

---

## 3️⃣ **channels** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **communication channels** store karti hai. Har workspace me multiple channels ho sakte hain (jaise Slack me).

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  channel_id: String,                // Unique channel ID (e.g., "general", "random")
  workspace_id: String,             // Kis workspace ka channel hai
  channel_name: String,              // Channel ka display name
  creator_address: String,           // Creator ka address
  members: Array<String>,             // Members jo is channel me hain (empty = all workspace members)
  is_private: Boolean,               // Private channel hai ya nahi
  is_default: Boolean,               // Default channel hai ya nahi (General/Random)
  created_at: Number,                // Creation timestamp
  timestamp: Number,                 // Hash chain timestamp
  previous_hash: String,             // Hash chain
  current_hash: String,              // Hash chain
  deleted: Boolean,                  // Soft delete flag
  deleted_at: Number                 // Deletion timestamp
}
```

### 🔑 Key Points:
- **channel_id + workspace_id** unique combination hai
- **Default channels** ("general", "random") har workspace me automatically ban jate hain
- **members** array empty ho to matlab **sab workspace members** ko access hai
- **Soft delete** - channel delete nahi hota, sirf `deleted: true` mark hota hai
- Default channels delete nahi ho sakte

### 💾 Example Data:
```json
{
  "channel_id": "general",
  "workspace_id": "ws_0x1234567890abcdef_1703123456789",
  "channel_name": "General",
  "creator_address": "0x1234567890abcdef",
  "members": [],
  "is_private": false,
  "is_default": true,
  "created_at": 1703123456789,
  "timestamp": 1703123456789,
  "previous_hash": "0xabc123...",
  "current_hash": "0xdef456...",
  "deleted": false
}
```

### 🔍 Indexes:
- `channel_id + workspace_id` (unique) - Fast lookup
- `workspace_id` - Find all channels in workspace
- `creator_address` - Find channels by creator
- `is_default` - Find default channels
- `deleted` - Filter deleted channels

### 🎯 Kya Kya Store Hota Hai:
- Channel ka unique ID aur naam
- Workspace reference
- Members list (ya empty for all members)
- Privacy settings
- Hash chain for integrity

---

## 4️⃣ **messages** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **messages** store karti hai - channel messages aur direct messages dono.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  message_id: String,                // Unique message ID (PRIMARY KEY, UNIQUE)
  workspace_id: String,              // Kis workspace ka message hai
  channel_id: String,                // Optional - channel message hai to
  sender_address: String,            // Sender ka address
  receiver_address: String,          // Optional - DM hai to receiver ka address
  message_text: String,              // Message ka content (1-5000 characters)
  file_id: String,                   // Optional - agar file attached hai to
  timestamp: Number,                 // Message timestamp
  previous_hash: String,             // Previous message ka hash (blockchain chain)
  current_hash: String               // Current message ka hash (blockchain chain)
}
```

### 🔑 Key Points:
- **message_id** unique hai - format: `msg_{timestamp}_{sender_address}`
- **Channel message** hai to `channel_id` hoga
- **Direct message (DM)** hai to `receiver_address` hoga
- Har message **hash chain** me link hota hai - agar koi message modify kare to chain break ho jayegi
- Messages ko **conversation ke basis** pe chain me link kiya jata hai

### 💾 Example Data:
```json
{
  "message_id": "msg_1703123456789_0x1234567890abcdef",
  "workspace_id": "ws_0x1234567890abcdef_1703123456789",
  "channel_id": "general",
  "sender_address": "0x1234567890abcdef",
  "message_text": "Hello everyone!",
  "timestamp": 1703123456789,
  "previous_hash": "0xabc123...",
  "current_hash": "0xdef456..."
}
```

### 🔍 Indexes:
- `message_id` (unique) - Fast lookup by message ID
- `workspace_id` - Find all messages in workspace
- `channel_id` - Find messages in channel
- `sender_address` - Find messages by sender
- `receiver_address` - Find DMs
- `timestamp` - Sort by time

### 🎯 Kya Kya Store Hota Hai:
- Message content
- Sender aur receiver addresses
- Workspace aur channel references
- File attachments (file_id reference)
- Hash chain for message integrity

---

## 5️⃣ **members** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **workspace members** store karti hai. Har workspace me kaun-kaun members hain yahan track hota hai.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  workspace_id: String,              // Kis workspace ka member hai
  member_address: String,            // Member ka wallet address
  display_name: String,              // Optional - display name
  joined_at: Number                  // Timestamp jab member join hua
}
```

### 🔑 Key Points:
- **workspace_id + member_address** unique combination hai - ek member ek workspace me ek baar hi ho sakta hai
- Workspace creator automatically member ban jata hai
- Members ko **invite** karke add kiya jata hai

### 💾 Example Data:
```json
{
  "workspace_id": "ws_0x1234567890abcdef_1703123456789",
  "member_address": "0x9876543210fedcba",
  "display_name": "Jane Doe",
  "joined_at": 1703123456789
}
```

### 🔍 Indexes:
- `workspace_id + member_address` (unique) - Prevent duplicate members
- `member_address` - Find all workspaces of a member

### 🎯 Kya Kya Store Hota Hai:
- Workspace reference
- Member ka address
- Optional display name
- Join timestamp

---

## 6️⃣ **files** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **file metadata** store karti hai. Actual files GridFS me store hote hain, yahan sirf metadata hai.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  file_id: String,                  // Unique file ID (PRIMARY KEY, UNIQUE)
  filename: String,                 // Original filename
  workspace_id: String,             // Kis workspace me upload hua
  uploader_address: String,          // Uploader ka address
  gridfs_id: String,                // GridFS me file ka ID (actual file storage)
  file_size: Number,                // File size in bytes
  upload_timestamp: Number,          // Upload timestamp
  mime_type: String                 // File type (e.g., "image/png", "application/pdf")
}
```

### 🔑 Key Points:
- **file_id** unique hai - format: `file_{timestamp}_{uploader_address}`
- **Actual file** GridFS me store hota hai (`fs.files` aur `fs.chunks` collections me)
- **gridfs_id** se actual file download kiya jata hai
- File size limit: 10MB default (configurable)

### 💾 Example Data:
```json
{
  "file_id": "file_1703123456789_0x1234567890abcdef",
  "filename": "document.pdf",
  "workspace_id": "ws_0x1234567890abcdef_1703123456789",
  "uploader_address": "0x1234567890abcdef",
  "gridfs_id": "507f1f77bcf86cd799439011",
  "file_size": 1048576,
  "upload_timestamp": 1703123456789,
  "mime_type": "application/pdf"
}
```

### 🔍 Indexes:
- `file_id` (unique) - Fast lookup by file ID
- `workspace_id` - Find all files in workspace
- `uploader_address` - Find files by uploader

### 🎯 Kya Kya Store Hota Hai:
- File metadata (name, size, type)
- Workspace reference
- Uploader information
- GridFS reference (actual file location)

---

## 7️⃣ **nodes** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **distributed network nodes** store karti hai. Yeh blockchain-like distributed system ke liye hai.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  node_id: String,                   // Unique node ID (PRIMARY KEY, UNIQUE)
  node_name: String,                 // Node ka naam
  ip_address: String,                // Node ka IP address
  tcp_port: Number,                  // TCP port (default: 3001)
  public_key: String,                 // Node ka public key (encryption)
  status: String,                    // "online", "offline", "syncing"
  last_seen: Date,                   // Last seen timestamp
  connected_nodes: [{                 // Connected nodes list
    node_id: String,
    connection_type: String,          // "tcp" or "http"
    last_connected: Date
  }],
  chain_position: Number,            // Position in blockchain chain
  previous_node_id: String,          // Previous node in chain
  next_node_id: String,              // Next node in chain
  previous_hash: String,              // Previous node ka hash
  current_hash: String,               // Current node ka hash
  gas_used: Number,                  // Gas used (blockchain-like)
  gas_price: Number,                 // Gas price (default: 1)
  transaction_fee: Number,           // Calculated fee (gas_used * gas_price)
  is_deprecated: Boolean,             // Node deprecated hai ya nahi
  deprecated_by: String,              // Replacement node ID
  deprecated_at: Date,               // Deprecation timestamp
  chain_broken: Boolean,             // Chain integrity broken hai ya nahi
  created_at: Date,                  // Creation timestamp
  updated_at: Date                   // Update timestamp
}
```

### 🔑 Key Points:
- **node_id** unique hai - format: `node_{timestamp}_{random}`
- Nodes **distributed network** banate hain - har node ek server/machine hai
- Nodes **blockchain-like chain** me link hote hain
- **Gas calculation** - real blockchain jaisa system
- **Deprecation** - agar node update hua to purana node deprecated mark hota hai

### 💾 Example Data:
```json
{
  "node_id": "node_1703123456789_abcd1234",
  "node_name": "Node-1",
  "ip_address": "192.168.1.100",
  "tcp_port": 3001,
  "public_key": "0xabc123...",
  "status": "online",
  "last_seen": "2024-01-01T12:00:00Z",
  "connected_nodes": [
    {
      "node_id": "node_1703123456789_efgh5678",
      "connection_type": "tcp",
      "last_connected": "2024-01-01T12:00:00Z"
    }
  ],
  "chain_position": 0,
  "previous_hash": "0",
  "current_hash": "0xdef456...",
  "gas_used": 0,
  "gas_price": 1,
  "transaction_fee": 0,
  "is_deprecated": false,
  "chain_broken": false
}
```

### 🔍 Indexes:
- `node_id` (unique) - Fast lookup by node ID
- `previous_hash` - Chain traversal
- `current_hash` - Hash verification
- `chain_position + is_deprecated` - Find active nodes in chain
- `is_deprecated` - Filter deprecated nodes

### 🎯 Kya Kya Store Hota Hai:
- Node network information (IP, port)
- Public key (encryption)
- Connection status
- Blockchain-like chain position
- Gas calculations
- Chain integrity flags

---

## 8️⃣ **ledgers** Collection

### 🎯 Purpose (Maqsad):
Yeh collection **blockchain-like ledger** store karti hai. Har transaction/operation yahan block ke form me store hota hai.

### 📝 Structure (Data Kaise Store Hota Hai):
```javascript
{
  _id: ObjectId,
  block_id: String,                  // Unique block ID (PRIMARY KEY, UNIQUE)
  block_number: Number,              // Block number in chain (0, 1, 2, ...)
  node_id: String,                   // Kis node ne block create kiya
  previous_hash: String,             // Previous block ka hash
  current_hash: String,              // Current block ka hash
  data: Object,                      // Actual transaction data (Mixed type)
  transaction_type: String,          // "message", "file", "user", "workspace", "member"
  sender_address: String,            // Transaction sender
  receiver_address: String,          // Optional - transaction receiver
  workspace_id: String,              // Optional - workspace reference
  timestamp: Number,                 // Transaction timestamp
  gas_used: Number,                  // Gas used
  gas_price: Number,                 // Gas price (default: 1)
  transaction_fee: Number,           // Calculated fee (gas_used * gas_price)
  verified: Boolean,                 // Block verified hai ya nahi
  chain_broken: Boolean,             // Chain integrity broken hai ya nahi
  created_at: Date,                  // Creation timestamp
  updated_at: Date                   // Update timestamp
}
```

### 🔑 Key Points:
- **block_id** unique hai
- **block_number** sequential hai - chain order maintain karta hai
- Har block **previous block ke hash** se link hota hai
- **data** field me actual transaction data hota hai (message, file, etc.)
- **Gas calculation** - real blockchain jaisa
- **Chain verification** - agar koi block modify hua to `chain_broken: true` ho jata hai

### 💾 Example Data:
```json
{
  "block_id": "block_1703123456789_abc123",
  "block_number": 5,
  "node_id": "node_1703123456789_abcd1234",
  "previous_hash": "0xabc123...",
  "current_hash": "0xdef456...",
  "data": {
    "message_id": "msg_1703123456789_0x1234567890abcdef",
    "message_text": "Hello!",
    "workspace_id": "ws_0x1234567890abcdef_1703123456789"
  },
  "transaction_type": "message",
  "sender_address": "0x1234567890abcdef",
  "timestamp": 1703123456789,
  "gas_used": 21000,
  "gas_price": 1,
  "transaction_fee": 21000,
  "verified": true,
  "chain_broken": false
}
```

### 🔍 Indexes:
- `block_id` (unique) - Fast lookup by block ID
- `block_number + node_id` - Chain traversal
- `previous_hash` - Find next block
- `transaction_type` - Filter by type
- `sender_address` - Find transactions by sender
- `timestamp` - Sort by time
- `gas_used` - Gas analysis
- `transaction_fee` - Fee analysis

### 🎯 Kya Kya Store Hota Hai:
- Transaction blocks (blockchain-like)
- Transaction data (messages, files, etc.)
- Hash chain for integrity
- Gas calculations
- Verification status

---

## 9️⃣ **fs.files & fs.chunks** Collections (GridFS)

### 🎯 Purpose (Magsad):
Yeh collections **actual files** store karti hain. MongoDB GridFS automatically yeh collections banata hai.

### 📝 Structure:

#### **fs.files** (File Metadata):
```javascript
{
  _id: ObjectId,                     // GridFS file ID
  filename: String,                  // Original filename
  length: Number,                    // File size in bytes
  chunkSize: Number,                 // Chunk size (default: 255KB)
  uploadDate: Date,                  // Upload timestamp
  md5: String,                       // File MD5 hash
  contentType: String,               // MIME type
  metadata: {                        // Custom metadata
    fileId: String,
    workspaceId: String,
    uploaderAddress: String
  }
}
```

#### **fs.chunks** (File Chunks):
```javascript
{
  _id: ObjectId,                     // Chunk ID
  files_id: ObjectId,                // Reference to fs.files
  n: Number,                          // Chunk number (0, 1, 2, ...)
  data: Binary                        // Actual file data (chunk)
}
```

### 🔑 Key Points:
- **GridFS** MongoDB ka built-in system hai large files store karne ke liye
- Files **chunks** me divide hote hain (default: 255KB per chunk)
- **fs.files** me metadata hota hai
- **fs.chunks** me actual file data hota hai
- Files ko **download** karne ke liye chunks ko combine kiya jata hai

### 💾 Example Data:

**fs.files:**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "filename": "document.pdf",
  "length": 1048576,
  "chunkSize": 255000,
  "uploadDate": "2024-01-01T12:00:00Z",
  "md5": "abc123def456...",
  "contentType": "application/pdf",
  "metadata": {
    "fileId": "file_1703123456789_0x1234567890abcdef",
    "workspaceId": "ws_0x1234567890abcdef_1703123456789",
    "uploaderAddress": "0x1234567890abcdef"
  }
}
```

**fs.chunks:**
```json
{
  "_id": "507f1f77bcf86cd799439012",
  "files_id": "507f1f77bcf86cd799439011",
  "n": 0,
  "data": Binary("...actual file data...")
}
```

### 🎯 Kya Kya Store Hota Hai:
- Actual file data (chunks me divided)
- File metadata (name, size, type)
- Custom metadata (fileId, workspaceId, etc.)

---

## 🔗 Collections Ka Relationship (Kaise Connect Hote Hain)

### Relationship Diagram:
```
users (1) ──┐
            ├──> workspaces (1) ──┬──> channels (many)
            │                     ├──> members (many)
            │                     ├──> messages (many)
            │                     └──> files (many)
            │
            └──> messages (many) ──> files (optional)
            
nodes (many) ──> ledgers (many) ──> data (references to messages/files/etc.)
```

### Detailed Relationships:

1. **users → workspaces**: Ek user multiple workspaces create kar sakta hai
2. **workspaces → channels**: Har workspace me multiple channels hote hain
3. **workspaces → members**: Har workspace me multiple members hote hain
4. **workspaces → messages**: Har workspace me multiple messages hote hain
5. **workspaces → files**: Har workspace me multiple files upload ho sakte hain
6. **channels → messages**: Har channel me multiple messages hote hain
7. **messages → files**: Message me file attach ho sakti hai (optional)
8. **nodes → ledgers**: Har node multiple ledger blocks create kar sakta hai
9. **ledgers → data**: Ledger blocks me actual data (messages, files, etc.) store hota hai

---

## 🔒 Security & Integrity Features

### 1. **Hash Chain (Blockchain-like)**
- **workspaces**, **channels**, **messages** me hash chain maintain hoti hai
- Har record ka `previous_hash` aur `current_hash` hota hai
- Agar koi data modify hua to chain break ho jati hai
- `chain_broken: true` flag se detect kiya jata hai

### 2. **Unique Constraints**
- **users.address** - unique
- **users.username** - unique
- **workspaces.workspace_id** - unique
- **channels.channel_id + workspace_id** - unique combination
- **messages.message_id** - unique
- **members.workspace_id + member_address** - unique combination
- **files.file_id** - unique
- **nodes.node_id** - unique
- **ledgers.block_id** - unique

### 3. **Indexes for Performance**
- Har collection me relevant fields pe indexes hain
- Fast searching aur querying ke liye
- Unique indexes data integrity maintain karte hain

---

## 📊 Data Flow Examples

### Example 1: User Workspace Create Karta Hai
1. User profile **users** collection me save hota hai
2. Workspace **workspaces** collection me create hota hai
3. User automatically **members** collection me add ho jata hai
4. 2 default channels (**channels** collection) automatically ban jate hain
5. Ledger block (**ledgers** collection) me transaction record hota hai

### Example 2: User Message Send Karta Hai
1. Message **messages** collection me save hota hai
2. Hash chain update hoti hai (previous_hash, current_hash)
3. Ledger block (**ledgers** collection) me transaction record hota hai
4. Gas calculation hoti hai (gas_used, transaction_fee)

### Example 3: User File Upload Karta Hai
1. File **GridFS** me store hoti hai (fs.files, fs.chunks)
2. File metadata **files** collection me save hoti hai
3. gridfs_id se file link hoti hai
4. Ledger block me transaction record hota hai

---

## 🎯 Summary (Khulasa)

### Total Collections: 9

1. **users** - User profiles (address, username, email)
2. **workspaces** - Teams/groups (workspace info, hash chain)
3. **channels** - Communication channels (channel info, members, privacy)
4. **messages** - Messages (content, sender, receiver, hash chain)
5. **members** - Workspace members (workspace, member address)
6. **files** - File metadata (filename, size, GridFS reference)
7. **nodes** - Network nodes (IP, port, chain position, gas)
8. **ledgers** - Blockchain ledger (blocks, transactions, hash chain)
9. **fs.files & fs.chunks** - Actual file storage (GridFS)

### Key Features:
- ✅ **Blockchain-like hash chain** for data integrity
- ✅ **Unique constraints** to prevent duplicates
- ✅ **Indexes** for fast queries
- ✅ **GridFS** for large file storage
- ✅ **Gas calculation** like real blockchain
- ✅ **Soft delete** for channels
- ✅ **Distributed nodes** for network

### Database Name: **EtherShare**
### Connection: `mongodb://localhost:27017/EtherShare`

---

## 📝 Notes

- Har collection **automatic indexes** create karti hai startup pe
- **Hash chain** verification se data tampering detect hota hai
- **GridFS** large files (16MB+) handle karne ke liye use hota hai
- **Normalization** - addresses aur IDs lowercase me store hote hain
- **Timestamps** - Unix timestamps (milliseconds) use hote hain

---

**End of Database Analysis** 🎉

