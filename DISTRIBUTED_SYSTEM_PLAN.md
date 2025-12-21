# 🏗️ Distributed System Implementation Plan

## 📋 Requirements Analysis

### Current State:
- ❌ OrbitDB and IPFS need to be completely removed
- ✅ MongoDB backend already exists
- ✅ Hash chain system already implemented

### Target System:

#### **Distributed System:**
1. **MongoDB Chain Structure**
   - Nodes connected in chain: Node1 → Node2 → Node3
   - Each node maintains a ledger
   - Data converted to hash values
   - If one node's data changes → chain breaks

2. **Table Structure:**
   - `nodes` collection - Node information
   - `ledgers` collection - Chain of transactions
   - `messages` collection - UserA to UserB messages
   - `chain_blocks` collection - Hash chain blocks

3. **Hash Chain Integrity:**
   - Each block has: `previous_hash`, `current_hash`
   - Chain verification on every operation
   - Break detection if data tampered

#### **Decentralized System:**
1. **TCP-based P2P Communication**
   - TCP server for peer connections
   - Direct node-to-node communication
   - Works when main server is off

2. **Dual Storage:**
   - One copy on MongoDB server
   - Second copy via TCP to peer nodes
   - Sync mechanism between copies

3. **Communication Flow:**
   - UserA → Node1 → TCP → Node2 → UserB
   - Server can be offline, communication continues
   - Peer discovery and connection

## 🎯 Implementation Steps

### Phase 1: Remove OrbitDB/IPFS ✅
- [x] Remove OrbitDB from MainActivity.kt
- [ ] Remove libp2p from package.json
- [ ] Remove OrbitDB references from Flutter
- [ ] Clean up old server files

### Phase 2: Distributed Node System
- [ ] Create node registration system
- [ ] Implement chain structure in MongoDB
- [ ] Create ledger maintenance system
- [ ] Implement hash chain verification

### Phase 3: TCP P2P Communication
- [ ] Create TCP server for peer connections
- [ ] Implement peer discovery
- [ ] Create message routing (UserA → UserB)
- [ ] Implement offline communication

### Phase 4: Chain Integrity
- [ ] Hash calculation for each block
- [ ] Chain verification on data changes
- [ ] Break detection and reporting
- [ ] Chain repair mechanism

### Phase 5: Dual Storage & Sync
- [ ] MongoDB server storage
- [ ] TCP peer storage
- [ ] Sync mechanism
- [ ] Conflict resolution

## 📊 Architecture

```
┌─────────────┐
│   User A    │
└──────┬──────┘
       │
       ▼
┌─────────────┐      TCP      ┌─────────────┐
│   Node 1    │◄──────────────►│   Node 2    │
│  (MongoDB)  │                │  (MongoDB)  │
└──────┬──────┘                └──────┬──────┘
       │                               │
       │ Hash Chain                    │ Hash Chain
       │ Node1 → Node2                 │ Node2 → Node3
       │                               │
       ▼                               ▼
┌─────────────┐      TCP      ┌─────────────┐
│   Node 3    │◄──────────────►│   Node 4    │
│  (MongoDB)  │                │  (MongoDB)  │
└──────┬──────┘                └──────┬──────┘
       │                               │
       ▼                               ▼
┌─────────────┐                ┌─────────────┐
│   User B   │                │   User C    │
└─────────────┘                └─────────────┘
```

## 🔗 Chain Structure

```
Block 0 (Genesis)
├─ previous_hash: "0"
├─ current_hash: "hash1"
└─ data: {...}

Block 1
├─ previous_hash: "hash1"  ← Links to Block 0
├─ current_hash: "hash2"
└─ data: {...}

Block 2
├─ previous_hash: "hash2"  ← Links to Block 1
├─ current_hash: "hash3"
└─ data: {...}

If Block 1 data changes:
❌ Chain breaks! (previous_hash mismatch)
```

## 🚀 Next Steps

1. Start removing OrbitDB/IPFS
2. Create node system
3. Implement TCP server
4. Build chain structure
5. Test UserA → UserB communication

