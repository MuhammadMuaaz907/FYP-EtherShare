# API Code Files List - EtherShare Project

## 📁 Backend API Route Files

Yeh sabhi files `backend/routes/` directory mein hain:

### 1. User Management APIs
**File:** `backend/routes/users.js`
- POST `/api/users/profile` - Create/Update user profile
- GET `/api/users/profile/:address` - Get user profile
- GET `/api/users/search` - Search users

### 2. Workspace Management APIs
**File:** `backend/routes/workspaces.js`
- POST `/api/workspaces` - Create workspace
- GET `/api/workspaces/user/:address` - Get user workspaces
- GET `/api/workspaces/:workspaceId` - Get workspace by ID
- GET `/api/workspaces/resolve/slug` - Resolve workspace by slug
- POST `/api/workspaces/:workspaceId/verify` - Verify workspace hash chain

### 3. Channel Management APIs
**File:** `backend/routes/channels.js`
- POST `/api/channels` - Create channel
- GET `/api/channels/workspace/:workspaceId` - Get workspace channels
- GET `/api/channels/:channelId` - Get channel by ID
- POST `/api/channels/:channelId/members` - Add member to channel
- DELETE `/api/channels/:channelId` - Delete channel
- POST `/api/channels/:channelId/verify` - Verify channel hash chain

### 4. Message Management APIs
**File:** `backend/routes/messages.js`
- POST `/api/messages` - Send message
- GET `/api/messages/channel` - Get channel messages
- GET `/api/messages/direct` - Get direct messages
- GET `/api/messages/workspace/:workspaceId` - Get workspace messages

### 5. Member Management APIs
**File:** `backend/routes/members.js`
- POST `/api/members` - Add workspace member
- GET `/api/members/workspace/:workspaceId` - Get workspace members
- DELETE `/api/members` - Remove workspace member

### 6. File Management APIs
**File:** `backend/routes/files.js`
- POST `/api/files/upload` - Upload file
- GET `/api/files/:fileId` - Get file metadata
- GET `/api/files/:fileId/download` - Download file
- GET `/api/files/workspace/:workspaceId` - Get workspace files

### 7. Node Management APIs
**File:** `backend/routes/nodes.js`
- POST `/api/nodes/register` - Register node
- GET `/api/nodes` - Get all nodes
- POST `/api/nodes/build-chain` - Build chain structure
- GET `/api/nodes/chain` - Get chain structure
- POST `/api/nodes/:nodeId/ledger` - Add block to ledger
- GET `/api/nodes/:nodeId/ledger` - Get node ledger
- POST `/api/nodes/:nodeId/verify` - Verify node ledger chain
- POST `/api/nodes/verify-chain` - Verify node chain integrity
- PUT `/api/nodes/:nodeId` - Update node
- GET `/api/nodes/messages/:userA/:userB` - Get messages between users
- DELETE `/api/nodes/clean` - Clean all nodes (testing)

### 8. Peer-to-Peer APIs
**File:** `backend/routes/peers.js`
- POST `/api/peers/register` - Register peer info
- GET `/api/peers/:user_address` - Get peer by address
- GET `/api/peers/workspace/:workspace_id` - Get workspace peers
- GET `/api/peers` - Get all active peers

### 9. Main Server File
**File:** `backend/server.js`
- GET `/health` - Health check endpoint
- GET `/` - Root endpoint with API information
- Routes registration and middleware setup

### 10. TCP Server (P2P Communication)
**File:** `backend/tcp-server.js`
- TCP socket-based P2P message routing
- Handshake, message forwarding, ledger sync

---

## 📁 Supporting Files

### Middleware
- `backend/middleware/auth.js` - Authentication middleware
- `backend/middleware/validation.js` - Input validation middleware

### Utilities
- `backend/utils/hashChain.js` - Hash chain integrity service
- `backend/utils/gasCalculator.js` - Gas calculation service
- `backend/utils/db.js` - Database connection utility

### Services
- `backend/services/nodeService.js` - Node management service
- `backend/services/ledgerService.js` - Ledger operations service

---

## 📁 Frontend API Service Files

### Flutter/Dart Services
- `blockchain_fyp/lib/services/distributed_service.dart` - Backend REST API calls
- `blockchain_fyp/lib/services/contract_service.dart` - Ethereum Smart Contract calls
- `blockchain_fyp/lib/services/hybrid_storage_service.dart` - Hybrid storage (local + remote)

---

## 📊 Summary

**Total API Route Files:** 8 files
**Total API Endpoints:** 42 REST endpoints + TCP P2P protocol
**Supporting Files:** 7 files (middleware, utils, services)
