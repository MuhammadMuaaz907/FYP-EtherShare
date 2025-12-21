# 📊 MongoDB Compass - Data Visualization Guide

## 🎯 Overview

MongoDB Compass is a GUI tool to visualize and interact with your MongoDB data. This guide shows you how to view your distributed system data.

## 📥 Installation

1. **Download MongoDB Compass:**
   - Visit: https://www.mongodb.com/try/download/compass
   - Download for Windows
   - Install the application

2. **Open MongoDB Compass:**
   - Launch the application
   - You'll see the connection screen

## 🔌 Connect to MongoDB

### Connection String:
```
mongodb://localhost:27017
```

### Steps:
1. **Paste connection string** in the connection field
2. **Click "Connect"**
3. You should see your databases appear on the left sidebar

## 📊 Viewing Your Data

### 1. **Select Database: `EtherShare`**

Once connected, you'll see:
- **Databases** on the left sidebar
- Click on **`EtherShare`** database

### 2. **Collections Available:**

#### **`nodes` Collection**
- **Purpose:** Stores all registered nodes in the distributed network
- **Key Fields:**
  - `node_id` - Unique node identifier
  - `node_name` - Node name
  - `ip_address` - Node IP address
  - `tcp_port` - TCP port for P2P communication
  - `chain_position` - Position in chain (0, 1, 2, ...)
  - `previous_node_id` - Previous node in chain
  - `next_node_id` - Next node in chain
  - `status` - online/offline/syncing

**Visualization:**
```
1. Click on "nodes" collection
2. You'll see all registered nodes
3. Check chain_position to see chain order
4. previous_node_id and next_node_id show chain connections
```

#### **`ledgers` Collection**
- **Purpose:** Blockchain-like ledger with hash chain
- **Key Fields:**
  - `block_id` - Unique block identifier
  - `block_number` - Block number in chain (0, 1, 2, ...)
  - `node_id` - Which node created this block
  - `previous_hash` - Hash of previous block
  - `current_hash` - Hash of current block
  - `data` - Actual message/data
  - `sender_address` - User who sent
  - `receiver_address` - User who receives
  - `chain_broken` - true if chain is broken

**Visualization:**
```
1. Click on "ledgers" collection
2. Sort by block_number to see chain order
3. Check previous_hash and current_hash to verify chain
4. If chain_broken is true, chain integrity is compromised
```

#### **`users` Collection**
- **Purpose:** User profiles
- **Key Fields:**
  - `address` - User wallet address
  - `username` - Username
  - `email` - Email address

#### **`workspaces` Collection**
- **Purpose:** Workspaces
- **Key Fields:**
  - `workspace_id` - Unique workspace ID
  - `name` - Workspace name
  - `inviter_address` - Creator address
  - `previous_hash` - Hash chain
  - `current_hash` - Hash chain

#### **`messages` Collection**
- **Purpose:** Messages (legacy, now using ledgers)
- **Key Fields:**
  - `message_id` - Message ID
  - `sender_address` - Sender
  - `receiver_address` - Receiver
  - `message_text` - Message content

## 🔍 Useful Queries in Compass

### 1. **View Chain Structure:**
```json
{}
```
Sort by: `chain_position` (ascending)

### 2. **View All Blocks for a Node:**
```json
{
  "node_id": "node_1234567890_abcd"
}
```
Sort by: `block_number` (ascending)

### 3. **Check Chain Integrity:**
```json
{
  "chain_broken": true
}
```
This shows all broken chains

### 4. **View Messages Between Users:**
```json
{
  "$or": [
    {
      "sender_address": "0xUserA",
      "receiver_address": "0xUserB"
    },
    {
      "sender_address": "0xUserB",
      "receiver_address": "0xUserA"
    }
  ],
  "transaction_type": "message"
}
```

### 5. **View Recent Blocks:**
```json
{}
```
Sort by: `timestamp` (descending)
Limit: 50

## 📈 Visualizing Chain Structure

### Step-by-Step:

1. **Open `ledgers` collection**
2. **Click on "Documents" tab**
3. **Use Filter:**
   ```json
   {
     "node_id": "your_node_id"
   }
   ```
4. **Sort by:** `block_number` (ascending)
5. **You'll see:**
   ```
   Block 0: previous_hash: "0", current_hash: "hash1"
   Block 1: previous_hash: "hash1", current_hash: "hash2"
   Block 2: previous_hash: "hash2", current_hash: "hash3"
   ```

### Verify Chain Integrity:

1. **Check if `previous_hash` of Block N matches `current_hash` of Block N-1**
2. **If mismatch → Chain is broken!**
3. **Look for `chain_broken: true` field**

## 🎨 Data Visualization Tips

### 1. **Use Schema Tab:**
- Click on "Schema" tab in any collection
- See data types and structure
- Understand field relationships

### 2. **Use Indexes Tab:**
- Click on "Indexes" tab
- See what indexes are created
- Understand query performance

### 3. **Export Data:**
- Select documents
- Click "Export Collection"
- Export as JSON or CSV

### 4. **Aggregation Pipeline:**
- Click on "Aggregations" tab
- Create complex queries
- Group and analyze data

## 🔍 Example Queries

### Find All Online Nodes:
```json
{
  "status": "online"
}
```

### Find Broken Chains:
```json
{
  "chain_broken": true
}
```

### Find Messages in Workspace:
```json
{
  "workspace_id": "ws_123",
  "transaction_type": "message"
}
```

### Find Recent Activity:
```json
{
  "timestamp": {
    "$gte": 1700000000000
  }
}
```

## 📊 Real-Time Monitoring

### Watch Data Changes:

1. **Keep Compass open**
2. **Send messages from your app**
3. **Refresh collection** (F5 or click refresh icon)
4. **See new blocks appear in real-time!**

### Monitor Chain Integrity:

1. **Create a filter:**
   ```json
   {
     "chain_broken": true
   }
   ```
2. **Watch this filter**
3. **If any documents appear → Chain is broken!**

## 🎯 Quick Reference

| Collection | Purpose | Key Fields |
|------------|---------|------------|
| `nodes` | Node registry | node_id, chain_position, previous_node_id, next_node_id |
| `ledgers` | Blockchain ledger | block_id, block_number, previous_hash, current_hash, data |
| `users` | User profiles | address, username, email |
| `workspaces` | Workspaces | workspace_id, name, inviter_address |
| `messages` | Messages (legacy) | message_id, sender_address, receiver_address |

## ✅ Best Practices

1. **Always sort by relevant field** (block_number, timestamp, etc.)
2. **Use filters** to narrow down data
3. **Check chain_broken field** regularly
4. **Export data** for backup
5. **Use Schema tab** to understand structure

## 🚀 Quick Start

1. **Connect:** `mongodb://localhost:27017`
2. **Select:** `EtherShare` database
3. **View:** `nodes` collection → See all nodes
4. **View:** `ledgers` collection → See blockchain
5. **Sort:** By `block_number` to see chain order
6. **Verify:** Check `previous_hash` matches previous `current_hash`

---

**MongoDB Compass makes it easy to visualize your distributed system!** 📊✨

