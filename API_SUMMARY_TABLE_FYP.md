# API Summary Table for FYP Report

## Complete API List - EtherShare Project

### Table 1: Backend REST APIs Summary

| # | Endpoint | Method | Category | Description | Access |
|---|----------|--------|----------|-------------|--------|
| 1 | `/health` | GET | Health | Server health check | Public |
| 2 | `/api/users/profile` | POST | Users | Create/Update user profile | Public |
| 3 | `/api/users/profile/:address` | GET | Users | Get user profile by address | Public |
| 4 | `/api/users/search` | GET | Users | Search users by username/email | Public |
| 5 | `/api/workspaces` | POST | Workspaces | Create new workspace | Public |
| 6 | `/api/workspaces/user/:address` | GET | Workspaces | Get user workspaces | Public |
| 7 | `/api/workspaces/:workspaceId` | GET | Workspaces | Get workspace by ID | Public |
| 8 | `/api/workspaces/resolve/slug` | GET | Workspaces | Resolve workspace by slug | Public |
| 9 | `/api/workspaces/:workspaceId/verify` | POST | Workspaces | Verify workspace hash chain | Public |
| 10 | `/api/channels` | POST | Channels | Create new channel | Public |
| 11 | `/api/channels/workspace/:workspaceId` | GET | Channels | Get workspace channels | Public |
| 12 | `/api/channels/:channelId` | GET | Channels | Get channel by ID | Public |
| 13 | `/api/channels/:channelId/members` | POST | Channels | Add member to channel | Public |
| 14 | `/api/channels/:channelId` | DELETE | Channels | Delete channel | Public |
| 15 | `/api/channels/:channelId/verify` | POST | Channels | Verify channel hash chain | Public |
| 16 | `/api/messages` | POST | Messages | Send message | Public |
| 17 | `/api/messages/channel` | GET | Messages | Get channel messages | Public |
| 18 | `/api/messages/direct` | GET | Messages | Get direct messages | Public |
| 19 | `/api/messages/workspace/:workspaceId` | GET | Messages | Get workspace messages | Public |
| 20 | `/api/members` | POST | Members | Add workspace member | Public |
| 21 | `/api/members/workspace/:workspaceId` | GET | Members | Get workspace members | Public |
| 22 | `/api/members` | DELETE | Members | Remove workspace member | Public |
| 23 | `/api/files/upload` | POST | Files | Upload file | Public |
| 24 | `/api/files/:fileId` | GET | Files | Get file metadata | Public |
| 25 | `/api/files/:fileId/download` | GET | Files | Download file | Public |
| 26 | `/api/files/workspace/:workspaceId` | GET | Files | Get workspace files | Public |
| 27 | `/api/nodes/register` | POST | Nodes | Register new node | Public |
| 28 | `/api/nodes` | GET | Nodes | Get all online nodes | Public |
| 29 | `/api/nodes/build-chain` | POST | Nodes | Build chain structure | Public |
| 30 | `/api/nodes/chain` | GET | Nodes | Get chain structure | Public |
| 31 | `/api/nodes/:nodeId/ledger` | POST | Nodes | Add block to ledger | Public |
| 32 | `/api/nodes/:nodeId/ledger` | GET | Nodes | Get node ledger | Public |
| 33 | `/api/nodes/:nodeId/verify` | POST | Nodes | Verify node ledger chain | Public |
| 34 | `/api/nodes/verify-chain` | POST | Nodes | Verify node chain integrity | Public |
| 35 | `/api/nodes/:nodeId` | PUT | Nodes | Update node | Public |
| 36 | `/api/nodes/messages/:userA/:userB` | GET | Nodes | Get messages between users | Public |
| 37 | `/api/nodes/clean` | DELETE | Nodes | Clean all nodes (testing) | Public |
| 38 | `/api/peers/register` | POST | Peers | Register peer info | Public |
| 39 | `/api/peers/:user_address` | GET | Peers | Get peer by address | Public |
| 40 | `/api/peers/workspace/:workspace_id` | GET | Peers | Get workspace peers | Public |
| 41 | `/api/peers` | GET | Peers | Get all active peers | Public |
| 42 | `/` | GET | Root | API information | Public |

---

### Table 2: Ethereum Blockchain Smart Contract APIs

| # | Function Name | Type | Description | Gas (approx) |
|---|---------------|------|-------------|--------------|
| 1 | `register()` | Write | Register new user on blockchain | ~5,000,000 |
| 2 | `login()` | Write | Login user on blockchain | ~3,000,000 |
| 3 | `isRegistered(address)` | Read | Check user registration status | Free |
| 4 | `enable2FA()` | Write | Enable Two-Factor Authentication | ~100,000 |
| 5 | `verify2FA(uint256)` | Write | Verify 2FA code | ~50,000 |
| 6 | `disable2FA()` | Write | Disable 2FA | ~80,000 |
| 7 | `is2FAEnabled(address)` | Read | Check if 2FA is enabled | Free |
| 8 | `getBackupCodeCount(address)` | Read | Get remaining backup codes | Free |
| 9 | `getFailedAttempts(address)` | Read | Get failed login attempts | Free |
| 10 | `isLockedOut(address)` | Read | Check account lockout status | Free |
| 11 | `getRemainingLockoutTime(address)` | Read | Get lockout time remaining | Free |
| 12 | `regenerateBackupCodes()` | Write | Regenerate 2FA backup codes | ~120,000 |

**Contract Address:** `0x15D9fDF2c6514047A2FFa4B8eD0fa87BB069a0Cd`  
**RPC URL:** `https://b47878c71279.ngrok-free.app` (via ngrok to Ganache)  
**Chain ID:** 1337 (Local Ganache Network)

---

### Table 3: Ethereum JSON-RPC Methods Used

| # | Method Name | Type | Description | Purpose |
|---|-------------|------|-------------|---------|
| 1 | `eth_getTransactionCount` | Read | Get nonce for address | Transaction preparation |
| 2 | `eth_sendTransaction` | Write | Send signed transaction | Execute contract functions |
| 3 | `eth_call` | Read | Read-only function call | Read contract state |
| 4 | `eth_getTransactionReceipt` | Read | Get transaction receipt | Verify transaction |
| 5 | `eth_gasPrice` | Read | Get current gas price | Fee calculation |
| 6 | `eth_estimateGas` | Read | Estimate gas required | Optimize gas usage |

---

### Table 4: WalletConnect APIs

| # | API Function | Description | Purpose |
|---|--------------|-------------|---------|
| 1 | `Web3App.createInstance()` | Initialize WalletConnect session | Setup wallet connection |
| 2 | `Web3App.connect()` | Connect to MetaMask/wallet | Establish wallet session |
| 3 | Session Events | Handle `accountsChanged`, `chainChanged` | Monitor wallet state |

**Project ID:** `1f976613b40ddd232f1339e8ae5f1634`  
**Protocol:** WalletConnect v2  
**Supported Wallets:** MetaMask, Trust Wallet, Coinbase Wallet

---

### Table 5: TCP P2P Communication Protocol

| # | Message Type | Direction | Description | Payload |
|---|--------------|-----------|-------------|---------|
| 1 | `handshake` | Client → Server | Initial connection | `{type, node_id}` |
| 2 | `handshake_ack` | Server → Client | Connection confirmed | `{type, node_id, message}` |
| 3 | `message` | Bidirectional | Route message (UserA→Node→UserB) | `{type, sender, receiver, content}` |
| 4 | `sync_request` | Client → Server | Request ledger sync | `{type, node_id, last_hash}` |
| 5 | `sync_response` | Server → Client | Send ledger data | `{type, node_id, ledger[]}` |
| 6 | `chain_verify` | Client → Server | Request chain verification | `{type, node_id}` |
| 7 | `chain_verify_response` | Server → Client | Chain validity result | `{type, node_id, valid}` |
| 8 | `error` | Server → Client | Error message | `{type, message}` |

**Protocol:** TCP/IP  
**Port:** 3001  
**Format:** JSON over TCP sockets

---

## API Statistics Summary

| Category | Total APIs | Write Operations | Read Operations |
|----------|-----------|------------------|-----------------|
| **Backend REST** | 42 | 20 | 22 |
| **Smart Contract** | 12 | 5 | 7 |
| **JSON-RPC** | 6 | 1 | 5 |
| **WalletConnect** | 3 | 1 | 2 |
| **TCP P2P** | 8 | 4 | 4 |
| **TOTAL** | **71** | **31** | **40** |

---

## API Category Breakdown

### Backend REST APIs (42 endpoints):
- **User Management:** 3 APIs
- **Workspace Management:** 5 APIs
- **Channel Management:** 6 APIs
- **Message Management:** 4 APIs
- **Member Management:** 3 APIs
- **File Management:** 4 APIs
- **Node Management:** 9 APIs
- **Peer Management:** 4 APIs
- **System:** 4 APIs (health, root, etc.)

### Blockchain APIs (18 functions):
- **Smart Contract Functions:** 12 APIs
- **JSON-RPC Methods:** 6 APIs

### P2P & Wallet APIs (11 functions):
- **WalletConnect:** 3 APIs
- **TCP P2P Protocol:** 8 message types

---

## API Security Features

| Feature | Implementation | APIs Affected |
|---------|---------------|---------------|
| Hash Chain Verification | Automatic on all write operations | Workspaces, Channels, Messages, Nodes |
| Chain Integrity Checks | Pre-retrieval verification | All GET operations |
| Gas Calculation | Time-based gas estimation | All write operations |
| Address Normalization | Lowercase conversion | All user/address fields |
| Input Validation | Middleware validation | All POST/PUT operations |
| Error Handling | Standardized error responses | All APIs |

---

## API Response Time & Gas Metrics

All write operations include:
- `gas_used`: Estimated gas units
- `gas_price`: Current gas price (gwei)
- `transaction_fee`: Calculated fee (ETH)
- `transaction_time_ms`: Execution time in milliseconds

**Example Response:**
```json
{
  "success": true,
  "data": {...},
  "gas_used": 21000,
  "gas_price": 20,
  "transaction_fee": 0.00042,
  "transaction_time_ms": 85.75
}
```

---

## API Testing Tools

| API Type | Testing Tool | Configuration |
|----------|-------------|---------------|
| REST APIs | Postman/Thunder Client | Base URL: `http://localhost:3000` |
| Blockchain APIs | Web3Dart Client | RPC: `https://b47878c71279.ngrok-free.app` |
| TCP P2P | Telnet/Netcat | Host: `localhost`, Port: `3001` |
| WalletConnect | MetaMask Mobile/Desktop | Project ID: `1f976613b40ddd232f1339e8ae5f1634` |

---

**Document Prepared For:** FYP Report  
**Project:** EtherShare - Blockchain-Based Secure File Sharing System  
**Total APIs Documented:** 71 APIs across 5 categories
