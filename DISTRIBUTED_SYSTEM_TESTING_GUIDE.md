# 🧪 Distributed System - Complete Testing Guide

## 📋 Table of Contents

1. [Prerequisites Check](#1-prerequisites-check)
2. [Environment Setup](#2-environment-setup)
3. [Backend Server Setup](#3-backend-server-setup)
4. [Test 1: Health Check](#test-1-health-check)
5. [Test 2: Node Registration](#test-2-node-registration)
6. [Test 3: Chain Building](#test-3-chain-building)
7. [Test 4: Hash Integrity](#test-4-hash-integrity)
8. [Test 5: Chain Breaking Detection](#test-5-chain-breaking-detection)
9. [Test 6: UserA to UserB Communication](#test-6-usera-to-userb-communication)
10. [Test 7: Complete Flow](#test-7-complete-flow)
11. [Troubleshooting](#troubleshooting)

---

## 1. Prerequisites Check

### ✅ Required Software:

1. **Node.js** (v16 or higher)
   ```bash
   node --version
   # Should show: v16.x.x or higher
   ```

2. **MongoDB** (Running)
   ```bash
   # Windows PowerShell:
   net start MongoDB
   
   # Check if running:
   mongo --version
   ```

3. **MongoDB Compass** (Optional but recommended)
   - Download from: https://www.mongodb.com/try/download/compass
   - Connect to: `mongodb://localhost:27017`

4. **Postman or Thunder Client** (For API testing)
   - Postman: https://www.postman.com/downloads/
   - Thunder Client: VS Code extension

---

## 2. Environment Setup

### Step 1: Navigate to Backend Directory

```bash
cd backend
```

### Step 2: Install Dependencies

```bash
npm install
```

**Expected Output:**
```
added 150 packages in 30s
```

### Step 3: Create `.env` File

Create `.env` file in `backend/` directory:

```env
PORT=3000
NODE_ENV=development

# MongoDB Configuration
MONGODB_URI=mongodb://localhost:27017/EtherShare

# JWT Secret
JWT_SECRET=your_super_secret_jwt_key_change_this
JWT_EXPIRES_IN=7d

# CORS
CORS_ORIGIN=http://localhost:3000,http://localhost:8080

# File Upload
MAX_FILE_SIZE=10485760
UPLOAD_PATH=./uploads
```

### Step 4: Verify MongoDB is Running

**Windows:**
```powershell
net start MongoDB
```

**Check in MongoDB Compass:**
1. Open MongoDB Compass
2. Connect to: `mongodb://localhost:27017`
3. Should connect successfully ✅

---

## 3. Backend Server Setup

### Start Backend Server

```bash
cd backend
npm run dev
```

**Expected Output:**
```
[nodemon] starting `node server.js`
🚀 Server running on port 3000
✅ MongoDB connected: mongodb://localhost:27017/EtherShare
📡 API Routes loaded
```

**Keep this terminal open!** Server should keep running.

---

## Test 1: Health Check

### Purpose:
Verify backend server aur MongoDB connection properly kaam kar rahe hain.

### Method 1: Browser Test

Open browser:
```
http://localhost:3000/health
```

**Expected Response:**
```json
{
  "success": true,
  "message": "EtherShare Backend API is running",
  "database": "connected"
}
```

### Method 2: Postman/Thunder Client

**Request:**
```
GET http://localhost:3000/health
```

**Expected Response:**
```json
{
  "success": true,
  "message": "EtherShare Backend API is running",
  "database": "connected"
}
```

### ✅ Success Criteria:
- Status code: `200 OK`
- `database: "connected"` ✅
- `success: true` ✅

### ❌ If Failed:
- Check MongoDB is running: `net start MongoDB`
- Check `.env` file has correct `MONGODB_URI`
- Check backend server logs for errors

---

## Test 2: Node Registration

### Purpose:
Test karo ke nodes properly register ho rahe hain.

### Test Case 1: Register First Node

**Request:**
```http
POST http://localhost:3000/api/nodes/register
Content-Type: application/json

{
  "node_name": "Node-Device-1",
  "ip_address": "192.168.1.100",
  "tcp_port": 3001
}
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Node registered successfully",
  "data": {
    "node_id": "node_abc123...",
    "node_name": "Node-Device-1",
    "ip_address": "192.168.1.100",
    "tcp_port": 3001,
    "status": "online",
    "chain_position": 0,
    "created_at": "2024-01-15T10:00:00.000Z"
  }
}
```

**Save `node_id` for next tests!** (Example: `node_abc123`)

### Test Case 2: Register Second Node

**Request:**
```http
POST http://localhost:3000/api/nodes/register
Content-Type: application/json

{
  "node_name": "Node-Device-2",
  "ip_address": "192.168.1.101",
  "tcp_port": 3002
}
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Node registered successfully",
  "data": {
    "node_id": "node_def456...",
    "node_name": "Node-Device-2",
    "ip_address": "192.168.1.101",
    "tcp_port": 3002,
    "status": "online"
  }
}
```

**Save this `node_id` too!** (Example: `node_def456`)

### Test Case 3: Register Third Node

**Request:**
```http
POST http://localhost:3000/api/nodes/register
Content-Type: application/json

{
  "node_name": "Node-Device-3",
  "ip_address": "192.168.1.102",
  "tcp_port": 3003
}
```

### Test Case 4: Get All Nodes

**Request:**
```http
GET http://localhost:3000/api/nodes
```

**Expected Response:**
```json
{
  "success": true,
  "count": 3,
  "data": [
    {
      "node_id": "node_abc123",
      "node_name": "Node-Device-1",
      "ip_address": "192.168.1.100",
      "tcp_port": 3001,
      "status": "online"
    },
    {
      "node_id": "node_def456",
      "node_name": "Node-Device-2",
      "ip_address": "192.168.1.101",
      "tcp_port": 3002,
      "status": "online"
    },
    {
      "node_id": "node_ghi789",
      "node_name": "Node-Device-3",
      "ip_address": "192.168.1.102",
      "tcp_port": 3003,
      "status": "online"
    }
  ]
}
```

### ✅ Success Criteria:
- All 3 nodes registered successfully ✅
- Each node has unique `node_id` ✅
- Status is `"online"` ✅
- `count: 3` ✅

### 📊 Verify in MongoDB Compass:
1. Open MongoDB Compass
2. Connect to: `mongodb://localhost:27017`
3. Database: `EtherShare`
4. Collection: `nodes`
5. Should see 3 documents ✅

---

## Test 3: Chain Building

### Purpose:
Test karo ke nodes properly chain mein connect ho rahe hain (Node1 → Node2 → Node3).

### Test Case: Build Chain

**Request:**
```http
POST http://localhost:3000/api/nodes/build-chain
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Chain built successfully",
  "data": {
    "chain_length": 3,
    "nodes": [
      {
        "node_id": "node_abc123",
        "position": 0,
        "previous": null,
        "next": "node_def456"
      },
      {
        "node_id": "node_def456",
        "position": 1,
        "previous": "node_abc123",
        "next": "node_ghi789"
      },
      {
        "node_id": "node_ghi789",
        "position": 2,
        "previous": "node_def456",
        "next": null
      }
    ]
  }
}
```

### Test Case: Get Chain Structure

**Request:**
```http
GET http://localhost:3000/api/nodes/chain
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "chain_length": 3,
    "chain": [
      {
        "node_id": "node_abc123",
        "chain_position": 0,
        "previous_node_id": null,
        "next_node_id": "node_def456"
      },
      {
        "node_id": "node_def456",
        "chain_position": 1,
        "previous_node_id": "node_abc123",
        "next_node_id": "node_ghi789"
      },
      {
        "node_id": "node_ghi789",
        "chain_position": 2,
        "previous_node_id": "node_def456",
        "next_node_id": null
      }
    ]
  }
}
```

### ✅ Success Criteria:
- Chain length: `3` ✅
- First node: `previous: null`, `next: node_2` ✅
- Middle node: `previous: node_1`, `next: node_3` ✅
- Last node: `previous: node_2`, `next: null` ✅

### 📊 Verify Chain Structure:
```
Node 1 (Position 0) → Node 2 (Position 1) → Node 3 (Position 2)
```

---

## Test 4: Hash Integrity

### Purpose:
Test karo ke hash calculation aur chain integrity properly kaam kar rahi hai.

### Test Case 1: Add First Block (Genesis Block)

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/ledger
Content-Type: application/json

{
  "type": "message",
  "sender_address": "0xUserA123",
  "receiver_address": "0xUserB456",
  "content": "Hello World - Block 0",
  "workspace_id": "ws_test123"
}
```

**Replace `{nodeId}` with actual node_id from Test 2!**

**Expected Response:**
```json
{
  "success": true,
  "message": "Block added to ledger",
  "data": {
    "block_id": "block_node_abc123_0_1705312800000",
    "block_number": 0,
    "node_id": "node_abc123",
    "previous_hash": "0",
    "current_hash": "a1b2c3d4e5f6789...",
    "data": {
      "type": "message",
      "sender_address": "0xUserA123",
      "receiver_address": "0xUserB456",
      "content": "Hello World - Block 0",
      "workspace_id": "ws_test123"
    },
    "timestamp": 1705312800000,
    "verified": true,
    "chain_broken": false
  }
}
```

**Save `current_hash` for next test!** (Example: `a1b2c3d4e5f6789...`)

### Test Case 2: Add Second Block

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/ledger
Content-Type: application/json

{
  "type": "message",
  "sender_address": "0xUserA123",
  "receiver_address": "0xUserB456",
  "content": "This is Block 1",
  "workspace_id": "ws_test123"
}
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Block added to ledger",
  "data": {
    "block_id": "block_node_abc123_1_1705312900000",
    "block_number": 1,
    "previous_hash": "a1b2c3d4e5f6789...",  // ← Block 0 ka hash
    "current_hash": "x9y8z7w6v5u4321...",   // ← New hash
    "data": {
      "content": "This is Block 1"
    },
    "chain_broken": false
  }
}
```

**Important:** `previous_hash` should match Block 0's `current_hash`! ✅

### Test Case 3: Add Third Block

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/ledger
Content-Type: application/json

{
  "type": "message",
  "sender_address": "0xUserA123",
  "receiver_address": "0xUserB456",
  "content": "This is Block 2",
  "workspace_id": "ws_test123"
}
```

### Test Case 4: Get Ledger (Verify Chain)

**Request:**
```http
GET http://localhost:3000/api/nodes/{nodeId}/ledger
```

**Expected Response:**
```json
{
  "success": true,
  "count": 3,
  "data": [
    {
      "block_number": 0,
      "previous_hash": "0",
      "current_hash": "a1b2c3d4e5f6789...",
      "data": {
        "content": "Hello World - Block 0"
      }
    },
    {
      "block_number": 1,
      "previous_hash": "a1b2c3d4e5f6789...",  // ← Matches Block 0's hash
      "current_hash": "x9y8z7w6v5u4321...",
      "data": {
        "content": "This is Block 1"
      }
    },
    {
      "block_number": 2,
      "previous_hash": "x9y8z7w6v5u4321...",  // ← Matches Block 1's hash
      "current_hash": "m5n4o3p2q1r0987...",
      "data": {
        "content": "This is Block 2"
      }
    }
  ]
}
```

### ✅ Success Criteria:
- Block 0: `previous_hash: "0"` ✅
- Block 1: `previous_hash` = Block 0's `current_hash` ✅
- Block 2: `previous_hash` = Block 1's `current_hash` ✅
- All blocks: `chain_broken: false` ✅

### 📊 Verify Hash Chain:
```
Block 0 (previous_hash: "0")
    ↓ (current_hash: "a1b2c3...")
Block 1 (previous_hash: "a1b2c3...")
    ↓ (current_hash: "x9y8z7...")
Block 2 (previous_hash: "x9y8z7...")
    ↓ (current_hash: "m5n4o3...")
```

---

## Test 5: Chain Breaking Detection

### Purpose:
Test karo ke agar data change ho to system chain break detect karta hai.

### Test Case 1: Verify Chain (Should be Valid)

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/verify
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "node_id": "node_abc123",
    "chain_valid": true
  }
}
```

### Test Case 2: Manually Break Chain (MongoDB Compass)

**Step 1:** Open MongoDB Compass
- Connect to: `mongodb://localhost:27017`
- Database: `EtherShare`
- Collection: `ledgers`

**Step 2:** Find Block 1
- Filter: `{ "block_number": 1 }`
- Click on Block 1 document

**Step 3:** Modify Data
- Change `data.content` from `"This is Block 1"` to `"HACKED DATA"`
- Click "Update"

**⚠️ Warning:** This will break the chain!

### Test Case 3: Verify Chain Again (Should Detect Break)

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/verify
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "node_id": "node_abc123",
    "chain_valid": false  // ← Chain broken!
  }
}

// Backend logs should show:
// ❌ Hash mismatch at block 1
// ❌ Chain broken at block 1
```

### Test Case 4: Check Ledger (Should Show Broken)

**Request:**
```http
GET http://localhost:3000/api/nodes/{nodeId}/ledger
```

**Expected Response:**
```json
{
  "success": true,
  "count": 3,
  "data": [
    {
      "block_number": 0,
      "chain_broken": false
    },
    {
      "block_number": 1,
      "chain_broken": true,  // ← Marked as broken!
      "data": {
        "content": "HACKED DATA"  // ← Modified data
      }
    },
    {
      "block_number": 2,
      "chain_broken": true  // ← Also marked (chain broken after block 1)
    }
  ]
}
```

### ✅ Success Criteria:
- Before modification: `chain_valid: true` ✅
- After modification: `chain_valid: false` ✅
- Block 1: `chain_broken: true` ✅
- Block 2: `chain_broken: true` ✅ (because chain broken at block 1)

### 🔧 Fix Chain (Optional):
1. Restore original data in MongoDB Compass
2. Or delete broken blocks and recreate

---

## Test 6: UserA to UserB Communication

### Purpose:
Test karo ke UserA se UserB ko messages properly send ho rahe hain.

### Test Case 1: Send Message from UserA to UserB

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/ledger
Content-Type: application/json

{
  "type": "message",
  "sender_address": "0xUserA123",
  "receiver_address": "0xUserB456",
  "content": "Hello UserB, how are you?",
  "workspace_id": "ws_test123"
}
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Block added to ledger",
  "data": {
    "block_id": "block_...",
    "sender_address": "0xUserA123",
    "receiver_address": "0xUserB456",
    "data": {
      "content": "Hello UserB, how are you?"
    }
  }
}
```

### Test Case 2: Send Reply from UserB to UserA

**Request:**
```http
POST http://localhost:3000/api/nodes/{nodeId}/ledger
Content-Type: application/json

{
  "type": "message",
  "sender_address": "0xUserB456",
  "receiver_address": "0xUserA123",
  "content": "Hi UserA, I'm doing great!",
  "workspace_id": "ws_test123"
}
```

### Test Case 3: Get Messages Between UserA and UserB

**Request:**
```http
GET http://localhost:3000/api/nodes/messages/0xUserA123/0xUserB456
```

**Expected Response:**
```json
{
  "success": true,
  "count": 2,
  "data": [
    {
      "block_id": "block_...",
      "block_number": 0,
      "sender_address": "0xUserA123",
      "receiver_address": "0xUserB456",
      "content": "Hello UserB, how are you?",
      "timestamp": 1705312800000
    },
    {
      "block_id": "block_...",
      "block_number": 1,
      "sender_address": "0xUserB456",
      "receiver_address": "0xUserA123",
      "content": "Hi UserA, I'm doing great!",
      "timestamp": 1705312900000
    }
  ]
}
```

### Test Case 4: Get Messages with Node Filter

**Request:**
```http
GET http://localhost:3000/api/nodes/messages/0xUserA123/0xUserB456?nodeId={nodeId}
```

**Expected Response:**
```json
{
  "success": true,
  "count": 2,
  "data": [
    // Same as above, but filtered by nodeId
  ]
}
```

### ✅ Success Criteria:
- Messages properly stored ✅
- Can retrieve messages between UserA and UserB ✅
- Messages in correct order (by timestamp) ✅
- Both directions work (UserA→UserB and UserB→UserA) ✅

---

## Test 7: Complete Flow

### Purpose:
Complete end-to-end test - Node registration se message sending tak.

### Complete Test Flow:

#### Step 1: Register 3 Nodes
```http
POST /api/nodes/register
POST /api/nodes/register
POST /api/nodes/register
```

#### Step 2: Build Chain
```http
POST /api/nodes/build-chain
```

#### Step 3: Add Multiple Messages
```http
POST /api/nodes/{nodeId}/ledger
POST /api/nodes/{nodeId}/ledger
POST /api/nodes/{nodeId}/ledger
```

#### Step 4: Verify Chain
```http
POST /api/nodes/{nodeId}/verify
```

#### Step 5: Get All Messages
```http
GET /api/nodes/messages/{userA}/{userB}
```

#### Step 6: Check Ledger
```http
GET /api/nodes/{nodeId}/ledger
```

### ✅ Complete Success Criteria:
- ✅ All nodes registered
- ✅ Chain built successfully
- ✅ Messages added to ledger
- ✅ Hash chain integrity maintained
- ✅ UserA to UserB communication works
- ✅ Chain verification passes

---

## Troubleshooting

### Problem 1: MongoDB Connection Failed

**Error:**
```
❌ MongoDB connection error: connect ECONNREFUSED
```

**Solution:**
```bash
# Windows:
net start MongoDB

# Verify:
mongo --version
```

**Check in MongoDB Compass:**
- Connect to: `mongodb://localhost:27017`
- Should connect successfully ✅

---

### Problem 2: Backend Server Not Starting

**Error:**
```
Error: Cannot find module 'express'
```

**Solution:**
```bash
cd backend
npm install
```

---

### Problem 3: Port Already in Use

**Error:**
```
Error: listen EADDRINUSE: address already in use :::3000
```

**Solution:**
```bash
# Find process using port 3000:
netstat -ano | findstr :3000

# Kill process (replace PID):
taskkill /PID <PID> /F

# Or change PORT in .env file
```

---

### Problem 4: Node Registration Fails

**Error:**
```
❌ Node registration failed: 500
```

**Solution:**
1. Check MongoDB is running
2. Check `.env` file has correct `MONGODB_URI`
3. Check backend server logs for detailed error

---

### Problem 5: Chain Building Fails

**Error:**
```
❌ Build chain failed: No nodes available
```

**Solution:**
1. First register nodes: `POST /api/nodes/register`
2. Then build chain: `POST /api/nodes/build-chain`

---

### Problem 6: Hash Verification Fails

**Error:**
```
❌ Chain broken at block X
```

**Solution:**
1. Check if data was manually modified in MongoDB
2. Verify hash calculation is correct
3. Recreate blocks if needed

---

## 📊 Testing Checklist

Use this checklist to track your testing progress:

- [ ] **Prerequisites Check**
  - [ ] Node.js installed
  - [ ] MongoDB running
  - [ ] MongoDB Compass installed (optional)

- [ ] **Environment Setup**
  - [ ] Dependencies installed (`npm install`)
  - [ ] `.env` file created
  - [ ] MongoDB connection verified

- [ ] **Backend Server**
  - [ ] Server starts successfully
  - [ ] Health check passes

- [ ] **Node Registration**
  - [ ] Register Node 1 ✅
  - [ ] Register Node 2 ✅
  - [ ] Register Node 3 ✅
  - [ ] Get all nodes ✅

- [ ] **Chain Building**
  - [ ] Build chain ✅
  - [ ] Get chain structure ✅
  - [ ] Verify chain positions ✅

- [ ] **Hash Integrity**
  - [ ] Add Block 0 (Genesis) ✅
  - [ ] Add Block 1 ✅
  - [ ] Add Block 2 ✅
  - [ ] Verify hash chain links ✅

- [ ] **Chain Breaking Detection**
  - [ ] Verify chain (should be valid) ✅
  - [ ] Modify data in MongoDB ✅
  - [ ] Verify chain (should detect break) ✅

- [ ] **UserA to UserB Communication**
  - [ ] Send message UserA → UserB ✅
  - [ ] Send message UserB → UserA ✅
  - [ ] Get messages between users ✅

- [ ] **Complete Flow**
  - [ ] All tests pass ✅
  - [ ] System working end-to-end ✅

---

## 🎯 Expected Test Results Summary

After completing all tests, you should have:

1. **3 Nodes Registered:**
   - Node 1, Node 2, Node 3
   - All with status: `"online"`

2. **Chain Structure:**
   - Node1 → Node2 → Node3
   - Proper `previous_node_id` and `next_node_id`

3. **Ledger with Multiple Blocks:**
   - Block 0 (Genesis): `previous_hash: "0"`
   - Block 1: `previous_hash` = Block 0's hash
   - Block 2: `previous_hash` = Block 1's hash

4. **Hash Integrity:**
   - All blocks: `chain_broken: false`
   - Chain verification: `chain_valid: true`

5. **User Messages:**
   - Messages between UserA and UserB
   - Properly stored and retrievable

---

## ✅ Success!

Agar sab tests pass ho gaye, to aapka **Distributed System** properly kaam kar raha hai! 🎉

**Next Step:** Ab aap **Decentralized System** (SQLite + TCP) implement kar sakte hain!

---

## 📝 Notes

- **Save node IDs:** Har test ke baad node IDs save karo for next tests
- **MongoDB Compass:** Use karo to visually verify data
- **Backend Logs:** Check karo for detailed error messages
- **Test Order:** Tests ko sequence mein karo (Test 1 → Test 2 → ...)

---

**Happy Testing! 🚀**

