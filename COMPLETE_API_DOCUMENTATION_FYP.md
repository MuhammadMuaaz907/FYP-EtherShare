# Complete API Documentation for EtherShare - FYP Report

## 📋 Project Overview
**EtherShare** is a Blockchain-Based Secure File Sharing and Communication System that uses multiple API types for different functionalities.

---

## 📚 Table of Contents
1. [Backend REST APIs](#1-backend-rest-apis)
2. [Ethereum Blockchain APIs](#2-ethereum-blockchain-apis)
3. [WalletConnect APIs](#3-walletconnect-apis)
4. [TCP P2P Communication Protocol](#4-tcp-p2p-communication-protocol)
5. [API Summary Table](#5-api-summary-table)

---

## 1. BACKEND REST APIs

**Base URL:** `http://localhost:3000` (Development)  
**Protocol:** HTTP/HTTPS  
**Content-Type:** `application/json`

### 1.1 Health Check APIs

#### GET /health
**Description:** Check backend server health status  
**Method:** GET  
**Access:** Public  
**Parameters:** None

**Response:**
```json
{
  "success": true,
  "message": "EtherShare Backend API is running",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "database": "connected"
}
```

---

### 1.2 User Management APIs

#### POST /api/users/profile
**Description:** Create or update user profile  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "address": "0x1234...5678",
  "username": "john_doe",
  "email": "john@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "designation": "Developer"
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "User profile created/updated successfully",
  "data": {
    "address": "0x1234...5678",
    "username": "john_doe",
    "email": "john@example.com",
    "created_at": 1234567890,
    "updated_at": 1234567890
  }
}
```

#### GET /api/users/profile/:address
**Description:** Get user profile by Ethereum address  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `address` (path parameter): Ethereum address

**Response (200):**
```json
{
  "success": true,
  "data": {
    "address": "0x1234...5678",
    "username": "john_doe",
    "email": "john@example.com"
  }
}
```

#### GET /api/users/search
**Description:** Search users by username or email  
**Method:** GET  
**Access:** Public  
**Query Parameters:**
- `query` (required): Search term (minimum 2 characters)

**Response (200):**
```json
{
  "success": true,
  "count": 2,
  "data": [
    {
      "address": "0x1234...5678",
      "username": "john_doe",
      "email": "john@example.com"
    }
  ]
}
```

---

### 1.3 Workspace Management APIs

#### POST /api/workspaces
**Description:** Create new workspace with hash chain integrity  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "workspaceName": "My Workspace",
  "inviterAddress": "0x1234...5678"
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "Workspace created successfully",
  "data": {
    "workspace_id": "ws_0x1234...5678_1234567890",
    "name": "My Workspace",
    "inviter_address": "0x1234...5678",
    "created_at": 1234567890,
    "gas_used": 21000,
    "gas_price": 20,
    "transaction_fee": 0.00042,
    "transaction_time_ms": 125.50
  }
}
```

#### GET /api/workspaces/user/:address
**Description:** Get all workspaces for a user  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `address` (path parameter): User Ethereum address

**Response (200):**
```json
{
  "success": true,
  "count": 2,
  "data": [
    {
      "workspace_id": "ws_0x1234...5678_1234567890",
      "name": "My Workspace",
      "inviter_address": "0x1234...5678",
      "created_at": 1234567890
    }
  ]
}
```

#### GET /api/workspaces/:workspaceId
**Description:** Get workspace by ID  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `workspaceId` (path parameter): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "data": {
    "workspace_id": "ws_0x1234...5678_1234567890",
    "name": "My Workspace",
    "inviter_address": "0x1234...5678",
    "created_at": 1234567890
  }
}
```

#### GET /api/workspaces/resolve/slug
**Description:** Resolve workspace by slug and inviter address (for invite links)  
**Method:** GET  
**Access:** Public  
**Query Parameters:**
- `workspaceSlug` (required): URL-friendly workspace name
- `inviterAddress` (required): Inviter's Ethereum address

**Response (200):**
```json
{
  "success": true,
  "data": {
    "workspace_id": "ws_0x1234...5678_1234567890",
    "name": "My Workspace"
  }
}
```

#### POST /api/workspaces/:workspaceId/verify
**Description:** Verify workspace hash chain integrity  
**Method:** POST  
**Access:** Public  
**Parameters:**
- `workspaceId` (path parameter): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "data": {
    "workspace_id": "ws_0x1234...5678_1234567890",
    "chain_valid": true
  }
}
```

---

### 1.4 Channel Management APIs

#### POST /api/channels
**Description:** Create new channel in workspace with hash chain  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "workspaceId": "ws_0x1234...5678_1234567890",
  "channelId": "general",
  "channelName": "General",
  "creatorAddress": "0x1234...5678",
  "isPrivate": false
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "Channel created successfully",
  "data": {
    "channel_id": "general",
    "workspace_id": "ws_0x1234...5678_1234567890",
    "channel_name": "General",
    "creator_address": "0x1234...5678",
    "is_private": false,
    "is_default": true,
    "created_at": 1234567890,
    "gas_used": 21000,
    "gas_price": 20,
    "transaction_fee": 0.00042,
    "transaction_time_ms": 95.25
  }
}
```

#### GET /api/channels/workspace/:workspaceId
**Description:** Get all channels for a workspace  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `workspaceId` (path parameter): Workspace ID  
**Query Parameters:**
- `memberAddress` (optional): Filter channels by member access

**Response (200):**
```json
{
  "success": true,
  "count": 3,
  "data": [
    {
      "channel_id": "general",
      "workspace_id": "ws_0x1234...5678_1234567890",
      "channel_name": "General",
      "is_default": true,
      "is_private": false,
      "created_at": 1234567890
    }
  ]
}
```

#### GET /api/channels/:channelId
**Description:** Get channel by ID  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `channelId` (path parameter): Channel ID  
**Query Parameters:**
- `workspaceId` (required): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "data": {
    "channel_id": "general",
    "workspace_id": "ws_0x1234...5678_1234567890",
    "channel_name": "General",
    "is_private": false
  }
}
```

#### POST /api/channels/:channelId/members
**Description:** Add member to channel  
**Method:** POST  
**Access:** Public  
**Parameters:**
- `channelId` (path parameter): Channel ID  
**Request Body:**
```json
{
  "workspaceId": "ws_0x1234...5678_1234567890",
  "memberAddress": "0x5678...9012"
}
```
**Response (200):**
```json
{
  "success": true,
  "message": "Member added to channel",
  "data": {
    "channel_id": "general",
    "members": ["0x1234...5678", "0x5678...9012"]
  }
}
```

#### DELETE /api/channels/:channelId
**Description:** Delete channel (soft delete)  
**Method:** DELETE  
**Access:** Public  
**Parameters:**
- `channelId` (path parameter): Channel ID  
**Query Parameters:**
- `workspaceId` (required): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "message": "Channel deleted successfully"
}
```

#### POST /api/channels/:channelId/verify
**Description:** Verify channel hash chain integrity  
**Method:** POST  
**Access:** Public  
**Parameters:**
- `channelId` (path parameter): Channel ID  
**Query Parameters:**
- `workspaceId` (required): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "data": {
    "workspace_id": "ws_0x1234...5678_1234567890",
    "channel_id": "general",
    "chain_valid": true
  }
}
```

---

### 1.5 Message Management APIs

#### POST /api/messages
**Description:** Add message with hash chain integrity  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "workspaceId": "ws_0x1234...5678_1234567890",
  "channelId": "general",
  "senderAddress": "0x1234...5678",
  "receiverAddress": "0x5678...9012",
  "messageText": "Hello, World!",
  "fileId": "file_1234567890_0x1234"
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "Message sent successfully",
  "data": {
    "message_id": "msg_1234567890_0x1234...5678",
    "workspace_id": "ws_0x1234...5678_1234567890",
    "sender_address": "0x1234...5678",
    "message_text": "Hello, World!",
    "timestamp": 1234567890,
    "gas_used": 21000,
    "gas_price": 20,
    "transaction_fee": 0.00042,
    "transaction_time_ms": 85.75
  }
}
```

#### GET /api/messages/channel
**Description:** Get channel messages with chain integrity verification  
**Method:** GET  
**Access:** Public  
**Query Parameters:**
- `workspaceId` (required): Workspace ID
- `channelId` (required): Channel ID

**Response (200):**
```json
{
  "success": true,
  "chainValid": true,
  "count": 5,
  "data": [
    {
      "message_id": "msg_1234567890_0x1234...5678",
      "workspace_id": "ws_0x1234...5678_1234567890",
      "channel_id": "general",
      "sender_address": "0x1234...5678",
      "message_text": "Hello, World!",
      "timestamp": 1234567890
    }
  ]
}
```

#### GET /api/messages/direct
**Description:** Get direct messages between two users with chain integrity verification  
**Method:** GET  
**Access:** Public  
**Query Parameters:**
- `user1Address` (required): First user's Ethereum address
- `user2Address` (required): Second user's Ethereum address

**Response (200):**
```json
{
  "success": true,
  "chainValid": true,
  "count": 10,
  "data": [
    {
      "message_id": "msg_1234567890_0x1234...5678",
      "sender_address": "0x1234...5678",
      "receiver_address": "0x5678...9012",
      "message_text": "Hello!",
      "timestamp": 1234567890
    }
  ]
}
```

#### GET /api/messages/workspace/:workspaceId
**Description:** Get all messages in a workspace  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `workspaceId` (path parameter): Workspace ID  
**Query Parameters:**
- `limit` (optional, default: 100): Maximum number of messages
- `skip` (optional, default: 0): Number of messages to skip

**Response (200):**
```json
{
  "success": true,
  "count": 50,
  "data": [
    {
      "message_id": "msg_1234567890_0x1234...5678",
      "workspace_id": "ws_0x1234...5678_1234567890",
      "sender_address": "0x1234...5678",
      "message_text": "Hello, World!",
      "timestamp": 1234567890
    }
  ]
}
```

---

### 1.6 Member Management APIs

#### POST /api/members
**Description:** Add workspace member  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "workspaceId": "ws_0x1234...5678_1234567890",
  "memberAddress": "0x5678...9012",
  "displayName": "John Doe"
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "Member added successfully",
  "data": {
    "workspace_id": "ws_0x1234...5678_1234567890",
    "member_address": "0x5678...9012",
    "display_name": "John Doe",
    "joined_at": 1234567890
  }
}
```

#### GET /api/members/workspace/:workspaceId
**Description:** Get all members of a workspace  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `workspaceId` (path parameter): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "count": 5,
  "data": [
    {
      "workspace_id": "ws_0x1234...5678_1234567890",
      "member_address": "0x5678...9012",
      "display_name": "John Doe",
      "joined_at": 1234567890
    }
  ]
}
```

#### DELETE /api/members
**Description:** Remove member from workspace  
**Method:** DELETE  
**Access:** Public  
**Request Body:**
```json
{
  "workspaceId": "ws_0x1234...5678_1234567890",
  "memberAddress": "0x5678...9012"
}
```
**Response (200):**
```json
{
  "success": true,
  "message": "Member removed successfully"
}
```

---

### 1.7 File Management APIs

#### POST /api/files/upload
**Description:** Upload file and save metadata  
**Method:** POST  
**Access:** Public  
**Content-Type:** `multipart/form-data`  
**Request Body (Form Data):**
- `file` (required): File to upload
- `workspaceId` (required): Workspace ID
- `uploaderAddress` (required): Uploader's Ethereum address

**Response (201):**
```json
{
  "success": true,
  "message": "File uploaded successfully",
  "data": {
    "file_id": "file_1234567890_0x1234...5678",
    "filename": "document.pdf",
    "file_size": 1048576,
    "upload_timestamp": 1234567890
  }
}
```

#### GET /api/files/:fileId
**Description:** Get file metadata  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `fileId` (path parameter): File ID

**Response (200):**
```json
{
  "success": true,
  "data": {
    "file_id": "file_1234567890_0x1234...5678",
    "filename": "document.pdf",
    "workspace_id": "ws_0x1234...5678_1234567890",
    "uploader_address": "0x1234...5678",
    "file_size": 1048576,
    "upload_timestamp": 1234567890,
    "mime_type": "application/pdf"
  }
}
```

#### GET /api/files/:fileId/download
**Description:** Download file from GridFS  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `fileId` (path parameter): File ID

**Response (200):**
- Content-Type: File's MIME type
- Content-Disposition: `attachment; filename="document.pdf"`
- Body: File binary data

#### GET /api/files/workspace/:workspaceId
**Description:** Get all files in a workspace  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `workspaceId` (path parameter): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "count": 10,
  "data": [
    {
      "file_id": "file_1234567890_0x1234...5678",
      "filename": "document.pdf",
      "file_size": 1048576,
      "upload_timestamp": 1234567890
    }
  ]
}
```

---

### 1.8 Node Management APIs (Blockchain-like Distributed System)

#### POST /api/nodes/register
**Description:** Register a new node (blockchain-like)  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "node_name": "Node-1",
  "ip_address": "192.168.1.100",
  "tcp_port": 3001
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "Node registered successfully",
  "data": {
    "node_id": "node_abc123",
    "node_name": "Node-1",
    "ip_address": "192.168.1.100",
    "tcp_port": 3001,
    "chain_position": 0,
    "previous_hash": "0x0000...0000",
    "current_hash": "0xabcd...ef01",
    "gas_used": 21000,
    "gas_price": 20,
    "transaction_fee": 0.00042,
    "transaction_time_ms": 95.25,
    "chain_valid": true
  }
}
```

#### GET /api/nodes
**Description:** Get all online nodes  
**Method:** GET  
**Access:** Public

**Response (200):**
```json
{
  "success": true,
  "count": 5,
  "data": [
    {
      "node_id": "node_abc123",
      "node_name": "Node-1",
      "ip_address": "192.168.1.100",
      "tcp_port": 3001,
      "status": "online"
    }
  ]
}
```

#### POST /api/nodes/build-chain
**Description:** Build chain structure  
**Method:** POST  
**Access:** Public

**Response (200):**
```json
{
  "success": true,
  "message": "Chain built successfully",
  "data": {
    "chain_length": 5,
    "chain": [
      {
        "node_id": "node_abc123",
        "next_node_id": "node_def456"
      }
    ]
  }
}
```

#### GET /api/nodes/chain
**Description:** Get chain structure  
**Method:** GET  
**Access:** Public

**Response (200):**
```json
{
  "success": true,
  "data": {
    "chain_length": 5,
    "chain": [
      {
        "node_id": "node_abc123",
        "next_node_id": "node_def456"
      }
    ]
  }
}
```

#### POST /api/nodes/:nodeId/ledger
**Description:** Add block to node ledger  
**Method:** POST  
**Access:** Public  
**Parameters:**
- `nodeId` (path parameter): Node ID  
**Request Body:**
```json
{
  "type": "message",
  "sender_address": "0x1234...5678",
  "receiver_address": "0x5678...9012",
  "content": "Hello!",
  "workspace_id": "ws_0x1234...5678_1234567890"
}
```
**Response (201):**
```json
{
  "success": true,
  "message": "Block added to ledger",
  "data": {
    "block_id": "block_123",
    "node_id": "node_abc123",
    "timestamp": 1234567890,
    "hash": "0xabcd...ef01"
  }
}
```

#### GET /api/nodes/:nodeId/ledger
**Description:** Get node ledger  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `nodeId` (path parameter): Node ID  
**Query Parameters:**
- `limit` (optional, default: 100): Maximum number of blocks

**Response (200):**
```json
{
  "success": true,
  "count": 50,
  "data": [
    {
      "block_id": "block_123",
      "node_id": "node_abc123",
      "timestamp": 1234567890,
      "hash": "0xabcd...ef01"
    }
  ]
}
```

#### POST /api/nodes/:nodeId/verify
**Description:** Verify ledger chain integrity for a node  
**Method:** POST  
**Access:** Public  
**Parameters:**
- `nodeId` (path parameter): Node ID

**Response (200):**
```json
{
  "success": true,
  "data": {
    "node_id": "node_abc123",
    "chain_valid": true
  }
}
```

#### POST /api/nodes/verify-chain
**Description:** Verify node chain integrity (blockchain-like)  
**Method:** POST  
**Access:** Public

**Response (200):**
```json
{
  "success": true,
  "data": {
    "chain_valid": true,
    "message": "Node chain is valid"
  }
}
```

#### PUT /api/nodes/:nodeId
**Description:** Update node (blockchain-like: creates new node, deprecates old)  
**Method:** PUT  
**Access:** Public  
**Parameters:**
- `nodeId` (path parameter): Node ID  
**Request Body:**
```json
{
  "node_name": "Node-1-Updated",
  "ip_address": "192.168.1.101"
}
```
**Response (200):**
```json
{
  "success": true,
  "message": "Node updated successfully (new node created)",
  "data": {
    "old_node_id": "node_abc123",
    "new_node_id": "node_xyz789",
    "gas_used": 21000,
    "transaction_fee": 0.00042,
    "current_hash": "0xabcd...ef01"
  }
}
```

#### GET /api/nodes/messages/:userA/:userB
**Description:** Get messages between two users  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `userA` (path parameter): First user's Ethereum address
- `userB` (path parameter): Second user's Ethereum address  
**Query Parameters:**
- `nodeId` (optional): Filter by node ID

**Response (200):**
```json
{
  "success": true,
  "count": 10,
  "data": [
    {
      "sender_address": "0x1234...5678",
      "receiver_address": "0x5678...9012",
      "content": "Hello!",
      "timestamp": 1234567890
    }
  ]
}
```

#### DELETE /api/nodes/clean
**Description:** Clean all nodes from database (for testing)  
**Method:** DELETE  
**Access:** Public

**Response (200):**
```json
{
  "success": true,
  "message": "All nodes deleted successfully",
  "deleted_count": 10
}
```

---

### 1.9 Peer-to-Peer (P2P) APIs

#### POST /api/peers/register
**Description:** Register peer info (IP + Port) for P2P communication  
**Method:** POST  
**Access:** Public  
**Request Body:**
```json
{
  "user_address": "0x1234...5678",
  "ip_address": "192.168.1.100",
  "port": 8080
}
```
**Response (200):**
```json
{
  "success": true,
  "message": "Peer registered successfully",
  "data": {
    "user_address": "0x1234...5678",
    "ip_address": "192.168.1.100",
    "port": 8080
  }
}
```

#### GET /api/peers/:user_address
**Description:** Get peer info by user address  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `user_address` (path parameter): User's Ethereum address

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user_address": "0x1234...5678",
    "ip_address": "192.168.1.100",
    "port": 8080,
    "last_seen": "2024-01-01T00:00:00.000Z"
  }
}
```

#### GET /api/peers/workspace/:workspace_id
**Description:** Get all peers in a workspace (for P2P discovery)  
**Method:** GET  
**Access:** Public  
**Parameters:**
- `workspace_id` (path parameter): Workspace ID

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "user_address": "0x1234...5678",
      "ip_address": "192.168.1.100",
      "port": 8080,
      "last_seen": "2024-01-01T00:00:00.000Z"
    }
  ]
}
```

#### GET /api/peers
**Description:** Get all registered peers (active in last 5 minutes)  
**Method:** GET  
**Access:** Public

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "user_address": "0x1234...5678",
      "ip_address": "192.168.1.100",
      "port": 8080,
      "last_seen": "2024-01-01T00:00:00.000Z"
    }
  ]
}
```

---

## 2. ETHEREUM BLOCKCHAIN APIs

**RPC URL:** `https://b47878c71279.ngrok-free.app` (via ngrok tunnel to Ganache)  
**Chain ID:** 1337 (Local Ganache Network)  
**Protocol:** JSON-RPC 2.0  
**Library:** Web3Dart (Dart/Flutter)

### 2.1 Smart Contract Address
**Contract Address:** `0x15D9fDF2c6514047A2FFa4B8eD0fa87BB069a0Cd`

### 2.2 Contract Functions (Smart Contract APIs)

#### register()
**Description:** Register a new user on the blockchain  
**Function Type:** Transaction (Write)  
**Parameters:** None  
**Returns:** Transaction receipt  
**Gas Used:** ~5000000

**Usage:**
```dart
await contract.methods.register().send({
  from: address,
  gas: 5000000
});
```

#### login()
**Description:** Login user on the blockchain  
**Function Type:** Transaction (Write)  
**Parameters:** None  
**Returns:** Transaction receipt  
**Gas Used:** ~3000000

#### isRegistered(address)
**Description:** Check if a user is registered  
**Function Type:** Call (Read)  
**Parameters:**
- `address`: Ethereum address to check  
**Returns:** Boolean

#### enable2FA()
**Description:** Enable Two-Factor Authentication for user  
**Function Type:** Transaction (Write)  
**Parameters:** None  
**Returns:** Transaction receipt

#### verify2FA(uint256 code)
**Description:** Verify 2FA code during login  
**Function Type:** Transaction (Write)  
**Parameters:**
- `code`: 6-digit TOTP code  
**Returns:** Transaction receipt

#### disable2FA()
**Description:** Disable Two-Factor Authentication  
**Function Type:** Transaction (Write)  
**Parameters:** None  
**Returns:** Transaction receipt

#### is2FAEnabled(address)
**Description:** Check if 2FA is enabled for an address  
**Function Type:** Call (Read)  
**Parameters:**
- `address`: Ethereum address to check  
**Returns:** Boolean

#### getBackupCodeCount(address)
**Description:** Get remaining backup code count  
**Function Type:** Call (Read)  
**Parameters:**
- `address`: Ethereum address  
**Returns:** uint256 (number of backup codes)

#### getFailedAttempts(address)
**Description:** Get failed 2FA verification attempts  
**Function Type:** Call (Read)  
**Parameters:**
- `address`: Ethereum address  
**Returns:** uint256 (number of failed attempts)

#### isLockedOut(address)
**Description:** Check if account is locked due to failed attempts  
**Function Type:** Call (Read)  
**Parameters:**
- `address`: Ethereum address  
**Returns:** Boolean

#### getRemainingLockoutTime(address)
**Description:** Get remaining lockout time in seconds  
**Function Type:** Call (Read)  
**Parameters:**
- `address`: Ethereum address  
**Returns:** uint256 (seconds remaining)

#### regenerateBackupCodes()
**Description:** Regenerate backup codes for 2FA  
**Function Type:** Transaction (Write)  
**Parameters:** None  
**Returns:** Transaction receipt

### 2.3 Ethereum JSON-RPC Methods (via Web3Dart)

#### eth_getTransactionCount
**Description:** Get transaction count (nonce) for an address  
**Purpose:** Used before sending transactions

#### eth_sendTransaction
**Description:** Send a signed transaction to the network  
**Purpose:** Execute contract functions

#### eth_call
**Description:** Execute a read-only function call  
**Purpose:** Read contract state without gas cost

#### eth_getTransactionReceipt
**Description:** Get transaction receipt after mining  
**Purpose:** Verify transaction completion

#### eth_gasPrice
**Description:** Get current gas price  
**Purpose:** Estimate transaction fees

#### eth_estimateGas
**Description:** Estimate gas required for a transaction  
**Purpose:** Optimize gas usage

---

## 3. WALLETCONNECT APIs

**Protocol:** WalletConnect v2  
**Project ID:** `1f976613b40ddd232f1339e8ae5f1634`  
**Library:** walletconnect_flutter_v2: ^2.2.5

### 3.1 WalletConnect Connection APIs

#### Web3App.createInstance()
**Description:** Initialize WalletConnect session  
**Parameters:**
- `projectId`: WalletConnect Project ID
- `metadata`: App metadata (name, description, URL, icons)

**Usage:**
```dart
final app = await Web3App.createInstance(
  projectId: '1f976613b40ddd232f1339e8ae5f1634',
  metadata: const PairingMetadata(
    name: 'FYP Secure File Sharing',
    description: 'Blockchain-based file sharing app',
    url: 'https://example.com',
    icons: ['https://example.com/icon.png'],
  ),
);
```

#### Web3App.connect()
**Description:** Connect to MetaMask or other Web3 wallet  
**Parameters:**
- `requiredNamespaces`: Required blockchain namespaces
  - `eip155`: Ethereum namespace
    - `chains`: ['eip155:1337'] (Ganache local network)
    - `methods`: ['eth_accounts', 'wallet_switchEthereumChain']
    - `events`: ['accountsChanged', 'chainChanged']

**Usage:**
```dart
final response = await web3App.connect(
  requiredNamespaces: {
    'eip155': const RequiredNamespace(
      chains: ['eip155:1337'],
      methods: ['eth_accounts', 'wallet_switchEthereumChain'],
      events: ['accountsChanged', 'chainChanged'],
    ),
  },
);
```

#### Session Namespaces
**Description:** Handle wallet session after connection  
**Events:**
- `accountsChanged`: Triggered when wallet account changes
- `chainChanged`: Triggered when blockchain network changes

---

## 4. TCP P2P COMMUNICATION PROTOCOL

**Protocol:** TCP/IP  
**Default Port:** 3001  
**Format:** JSON messages over TCP sockets

### 4.1 Message Types

#### handshake
**Description:** Initial connection handshake between nodes  
**Direction:** Client → Server  
**Message Format:**
```json
{
  "type": "handshake",
  "node_id": "node_abc123"
}
```

**Response (handshake_ack):**
```json
{
  "type": "handshake_ack",
  "node_id": "node_def456",
  "message": "Connection established"
}
```

#### message
**Description:** Route message through P2P network (UserA → Node1 → Node2 → UserB)  
**Direction:** Client → Server  
**Message Format:**
```json
{
  "type": "message",
  "sender_address": "0x1234...5678",
  "receiver_address": "0x5678...9012",
  "content": "Hello, World!",
  "workspace_id": "ws_0x1234...5678_1234567890"
}
```

#### sync_request
**Description:** Request ledger synchronization from peer node  
**Direction:** Client → Server  
**Message Format:**
```json
{
  "type": "sync_request",
  "node_id": "node_abc123",
  "last_block_hash": "0xabcd...ef01"
}
```

**Response (sync_response):**
```json
{
  "type": "sync_response",
  "node_id": "node_abc123",
  "ledger": [
    {
      "block_id": "block_123",
      "hash": "0xabcd...ef01",
      "timestamp": 1234567890
    }
  ]
}
```

#### chain_verify
**Description:** Request chain integrity verification  
**Direction:** Client → Server  
**Message Format:**
```json
{
  "type": "chain_verify",
  "node_id": "node_abc123"
}
```

**Response (chain_verify_response):**
```json
{
  "type": "chain_verify_response",
  "node_id": "node_abc123",
  "valid": true
}
```

#### error
**Description:** Error message response  
**Direction:** Server → Client  
**Message Format:**
```json
{
  "type": "error",
  "message": "Error description"
}
```

---

## 5. API SUMMARY TABLE

| Category | API Type | Total Endpoints | Protocol | Port/URL |
|----------|----------|----------------|----------|----------|
| **Backend REST APIs** | REST/HTTP | 44 endpoints | HTTP/HTTPS | Port 3000 |
| **Ethereum Blockchain** | JSON-RPC | 12+ contract functions | JSON-RPC 2.0 | ngrok URL |
| **WalletConnect** | WebSocket/HTTP | 3 main functions | WalletConnect v2 | - |
| **TCP P2P Protocol** | TCP/IP | 5 message types | TCP Socket | Port 3001 |

---

## 6. API USAGE STATISTICS

### 6.1 Backend REST APIs Breakdown:
- **User Management:** 3 endpoints
- **Workspace Management:** 5 endpoints
- **Channel Management:** 6 endpoints
- **Message Management:** 4 endpoints
- **Member Management:** 3 endpoints
- **File Management:** 4 endpoints
- **Node Management:** 9 endpoints
- **Peer Management:** 4 endpoints
- **Health Check:** 1 endpoint
- **Root Endpoint:** 1 endpoint

### 6.2 Authentication & Security:
- **Hash Chain Verification:** Used in Workspaces, Channels, Messages, Nodes
- **Chain Integrity Checks:** Automatic verification before data retrieval
- **Gas Calculation:** All write operations include gas metrics

---

## 7. API DEPENDENCIES

### 7.1 External Services:
1. **MongoDB Database:** All REST APIs store data in MongoDB
2. **Ganache (via ngrok):** Ethereum blockchain RPC endpoint
3. **WalletConnect Cloud:** Wallet connection infrastructure
4. **MetaMask Wallet:** Web3 wallet for blockchain transactions

### 7.2 Internal Services:
1. **Hash Chain Service:** Integrity verification for all data
2. **Gas Calculator Service:** Transaction fee calculation
3. **Node Service:** Distributed node management
4. **Ledger Service:** Blockchain-like ledger operations

---

## 8. API ERROR HANDLING

All APIs follow consistent error response format:

```json
{
  "success": false,
  "error": "Error type",
  "message": "Detailed error message",
  "gas_used": 21000,
  "gas_price": 20,
  "transaction_fee": 0.00042,
  "transaction_time_ms": 85.75
}
```

### Common HTTP Status Codes:
- **200:** Success
- **201:** Created
- **400:** Bad Request
- **403:** Forbidden (Chain integrity compromised)
- **404:** Not Found
- **409:** Conflict (Duplicate data)
- **500:** Internal Server Error

---

## 9. API TESTING

### 9.1 Backend API Testing:
- Use **Postman** or **Thunder Client** for REST API testing
- Base URL: `http://localhost:3000`
- Example collection available in: `DISTRIBUTED_SYSTEM_POSTMAN_COLLECTION.json`

### 9.2 Blockchain API Testing:
- Connect to Ganache local network (Chain ID: 1337)
- Use MetaMask or Web3Dart client
- Test contract functions via `mobile_test.js`

### 9.3 P2P Protocol Testing:
- Use TCP client tools (e.g., `telnet`, `netcat`)
- Connect to `localhost:3001`
- Send JSON messages as per protocol specification

---

## 10. API SECURITY FEATURES

1. **Hash Chain Integrity:** Every write operation includes hash chain verification
2. **Chain Breaking Detection:** Automatic detection and blocking of compromised data
3. **Gas Calculation:** Transparent transaction fee tracking
4. **Address Normalization:** All Ethereum addresses normalized to lowercase
5. **Validation Middleware:** Input validation on all endpoints
6. **CORS Configuration:** Configurable CORS for production deployment

---

## 11. CONCLUSION

The EtherShare project uses a comprehensive set of APIs:
- **44 REST API endpoints** for backend operations
- **12+ Smart Contract functions** for blockchain operations
- **3 WalletConnect APIs** for wallet integration
- **5 TCP P2P message types** for peer-to-peer communication

All APIs are designed with security, integrity, and scalability in mind, featuring hash chain verification, gas calculation, and distributed architecture support.

---

**Document Version:** 1.0  
**Last Updated:** 2024  
**Project:** EtherShare - FYP
